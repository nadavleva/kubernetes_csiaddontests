#!/bin/bash
# Diagnose pod image pull issues and check available images
# Usage: ./hack/diagnose-pod-image-issue.sh [pod-name] [namespace]

set -euo pipefail

POD_NAME="${1:-non-replicated-test}"
NAMESPACE="${2:-}"

echo "=========================================="
echo "Pod Image Diagnostic Tool"
echo "=========================================="
echo ""

# Find pod if namespace not provided
if [[ -z "${NAMESPACE}" ]]; then
    echo "Searching for pod '${POD_NAME}' in all namespaces..."
    POD_INFO=$(kubectl get pods -A -o json 2>/dev/null | jq -r --arg name "${POD_NAME}" '.items[] | select(.metadata.name | contains($name)) | "\(.metadata.namespace) \(.metadata.name)"' | head -1)
    
    if [[ -z "${POD_INFO}" ]]; then
        echo "❌ Pod '${POD_NAME}' not found in any namespace"
        echo ""
        echo "Searching for pods with 'replication' in name:"
        kubectl get pods -A 2>/dev/null | grep -i replication || echo "No replication pods found"
        exit 1
    fi
    
    NAMESPACE=$(echo "${POD_INFO}" | awk '{print $1}')
    POD_NAME=$(echo "${POD_INFO}" | awk '{print $2}')
    echo "✅ Found pod: ${NAMESPACE}/${POD_NAME}"
else
    echo "Checking pod: ${NAMESPACE}/${POD_NAME}"
fi

echo ""
echo "=========================================="
echo "1. Pod Status"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null || echo "Pod not found"

echo ""
echo "=========================================="
echo "2. Pod Container Images"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].image}' 2>/dev/null | tr ' ' '\n' | while read -r img; do
    echo "  Image: ${img}"
done

echo ""
echo "=========================================="
echo "3. Pod Events (ImagePull Errors)"
echo "=========================================="
kubectl get events -n "${NAMESPACE}" --field-selector involvedObject.name="${POD_NAME}" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "No events found"

echo ""
echo "=========================================="
echo "4. Pod Description (Full Status)"
echo "=========================================="
kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}" 2>/dev/null | grep -A 20 "Events:" || echo "Cannot describe pod"

echo ""
echo "=========================================="
echo "5. Available Images on Cluster Nodes"
echo "=========================================="
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [[ -z "${NODES}" ]]; then
    echo "⚠️  Cannot retrieve node list"
else
    for node in ${NODES}; do
        echo ""
        echo "--- Node: ${node} ---"
        # Try to get images from node status
        IMAGES=$(kubectl get node "${node}" -o jsonpath='{.status.images[*].names[*]}' 2>/dev/null || echo "")
        if [[ -n "${IMAGES}" ]]; then
            echo "${IMAGES}" | tr ' ' '\n' | grep -E "(busybox|alpine|ubuntu|agnhost)" | head -10 || echo "  No common test images found"
        else
            echo "  Cannot list images (may require node access)"
        fi
    done
fi

echo ""
echo "=========================================="
echo "6. Image Pull Policy"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].imagePullPolicy}' 2>/dev/null | tr ' ' '\n' | while read -r policy; do
    echo "  Policy: ${policy}"
done

echo ""
echo "=========================================="
echo "7. Image Pull Secrets"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.imagePullSecrets[*].name}' 2>/dev/null | tr ' ' '\n' | while read -r secret; do
    if [[ -n "${secret}" ]]; then
        echo "  Secret: ${secret}"
    fi
done
if [[ -z "$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.imagePullSecrets[*].name}' 2>/dev/null)" ]]; then
    echo "  No image pull secrets configured"
fi

echo ""
echo "=========================================="
echo "8. PVC Volume Mode (if applicable)"
echo "=========================================="
PVC_NAME=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}' 2>/dev/null | awk '{print $1}')
if [[ -n "${PVC_NAME}" ]]; then
    VOL_MODE=$(kubectl get pvc "${PVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.volumeMode}' 2>/dev/null || echo "unknown")
    echo "  PVC: ${PVC_NAME}"
    echo "  Volume Mode: ${VOL_MODE}"
    if [[ "${VOL_MODE}" == "Block" ]]; then
        echo "  ⚠️  WARNING: PVC is Block mode - pod should use VolumeDevices, not VolumeMounts"
    fi
else
    echo "  No PVC found in pod spec"
fi

echo ""
echo "=========================================="
echo "Suggested Fixes"
echo "=========================================="
echo ""
echo "1. For minikube, pre-load the busybox image:"
echo "   minikube image load busybox"
echo "   # Or:"
echo "   eval \$(minikube docker-env)"
echo "   docker pull busybox"
echo ""
echo "2. Check if the image registry is accessible:"
echo "   kubectl run test-pull --image=busybox --rm -it --restart=Never -- echo 'test'"
echo ""
echo "3. If using private registry, create image pull secret:"
echo "   kubectl create secret docker-registry <secret-name> \\"
echo "     --docker-server=<registry> \\"
echo "     --docker-username=<user> \\"
echo "     --docker-password=<pass>"
echo ""
echo "4. For Block volume mode issues, ensure pod uses VolumeDevices:"
echo "   Check pod spec for volumeDevices (not volumeMounts) when PVC is Block mode"
echo ""
echo "5. Check node image pull policy:"
echo "   kubectl get nodes -o jsonpath='{.items[*].status.images[*].names[*]}' | grep busybox"
