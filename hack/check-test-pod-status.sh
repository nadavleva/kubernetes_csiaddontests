#!/bin/bash
# Check status of test pods and available images
# Usage: ./hack/check-test-pod-status.sh [pod-name] [namespace]

set -euo pipefail

POD_NAME="${1:-non-replicated-test}"
NAMESPACE="${2:-}"

echo "=========================================="
echo "Test Pod Diagnostic Tool"
echo "=========================================="
echo ""

# If namespace not provided, search all namespaces
if [[ -z "${NAMESPACE}" ]]; then
    echo "Searching for pod '${POD_NAME}' in all namespaces..."
    POD_INFO=$(kubectl get pods -A -o json | jq -r --arg name "${POD_NAME}" '.items[] | select(.metadata.name | contains($name)) | "\(.metadata.namespace) \(.metadata.name)"' | head -1)
    
    if [[ -z "${POD_INFO}" ]]; then
        echo "Pod '${POD_NAME}' not found in any namespace"
        echo ""
        echo "Searching for pods with 'replication' in name:"
        kubectl get pods -A | grep -i replication || echo "No replication pods found"
        exit 1
    fi
    
    NAMESPACE=$(echo "${POD_INFO}" | awk '{print $1}')
    POD_NAME=$(echo "${POD_INFO}" | awk '{print $2}')
    echo "Found pod: ${NAMESPACE}/${POD_NAME}"
else
    echo "Checking pod: ${NAMESPACE}/${POD_NAME}"
fi

echo ""
echo "=========================================="
echo "Pod Details"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o wide

echo ""
echo "=========================================="
echo "Pod Description (Events & Status)"
echo "=========================================="
kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}"

echo ""
echo "=========================================="
echo "Pod YAML (Image Information)"
echo "=========================================="
kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o yaml | grep -A 5 -B 5 "image:"

echo ""
echo "=========================================="
echo "Pod Events (ImagePull Errors)"
echo "=========================================="
kubectl get events -n "${NAMESPACE}" --field-selector involvedObject.name="${POD_NAME}" --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=========================================="
echo "Available Images on Nodes"
echo "=========================================="
echo "Checking images available on cluster nodes..."
echo ""

# Get all nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in ${NODES}; do
    echo "--- Node: ${node} ---"
    # Try to get images from node (requires node access or using kubectl debug)
    kubectl get node "${node}" -o jsonpath='{.status.images[*].names[*]}' 2>/dev/null | tr ' ' '\n' | grep -E "(busybox|alpine|ubuntu)" | head -10 || echo "Cannot list images on node (may require node access)"
    echo ""
done

echo ""
echo "=========================================="
echo "Suggested Fixes"
echo "=========================================="
echo "1. If image pull fails, try pre-pulling the image:"
echo "   kubectl run image-pull-test --image=busybox --rm -it --restart=Never -- echo 'test'"
echo ""
echo "2. Check if image pull secrets are needed:"
echo "   kubectl get secrets -n ${NAMESPACE} | grep -i pull"
echo ""
echo "3. Check node image pull policy:"
echo "   kubectl get nodes -o jsonpath='{.items[*].status.images[*].names[*]}' | grep busybox"
echo ""
echo "4. For minikube, load image:"
echo "   minikube image load busybox"
echo "   # Or use minikube's registry:"
echo "   eval \$(minikube docker-env)"
echo "   docker pull busybox"
