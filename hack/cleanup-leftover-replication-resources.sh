#!/bin/bash
# Cleanup script for leftover CSI replication test resources
# 
# NOTE: This is a SAFETY NET script for manual cleanup of orphaned resources.
# Normal test cleanup should happen automatically via ginkgo.DeferCleanup().
# Use this script only when:
# - Tests were interrupted (Ctrl+C, timeout, etc.)
# - Test cleanup failed due to cluster issues
# - Manual cleanup is needed for debugging
#
# This script removes orphaned PVCs, VolumeReplications, and namespaces from failed/interrupted test runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
DRY_RUN="${DRY_RUN:-false}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-csi-replication-}"
FORCE="${FORCE:-false}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-2}"

# Build kubectl command with context if provided
KUBECTL_CMD="kubectl"
if [[ -n "${KUBECTL_CONTEXT}" ]]; then
    KUBECTL_CMD="kubectl --context=${KUBECTL_CONTEXT}"
fi

# Function to show usage
usage() {
    cat <<EOF
CSI Replication Test Resource Cleanup Script

Usage: ${0} [OPTIONS]

Environment Variables:
  DRY_RUN              Set to 'true' to preview actions without executing (default: false)
  FORCE                Set to 'true' to remove finalizers and force deletion (default: false)
  NAMESPACE_PREFIX     Prefix for test namespaces to clean up (default: csi-replication-)
  KUBECTL_CONTEXT      Kubernetes context to use (default: current context)
  WAIT_TIMEOUT         Timeout in seconds to wait for resource deletion (default: 10)
  CHECK_INTERVAL       Interval in seconds between deletion checks (default: 2)

Examples:
  # Preview cleanup without executing
  DRY_RUN=true ${0}

  # Force cleanup (remove finalizers)
  FORCE=true ${0}

  # Use specific Kubernetes context
  KUBECTL_CONTEXT=my-cluster ${0}

  # Custom timeout and check interval
  WAIT_TIMEOUT=30 CHECK_INTERVAL=5 ${0}

  # Combine options
  FORCE=true KUBECTL_CONTEXT=my-cluster WAIT_TIMEOUT=20 ${0}
EOF
    exit 0
}

# Check for help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
fi

echo "=========================================="
echo "CSI Replication Test Resource Cleanup"
echo "=========================================="
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "🔍 DRY RUN MODE - No resources will be deleted"
    echo ""
fi

# Check kubectl availability
if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl not found in PATH"
    exit 1
fi

# Function to cleanup VolumeReplication objects
cleanup_volume_replications() {
    echo "=== Cleaning up VolumeReplication objects ==="
    
    # Get all VolumeReplication objects
    vrs=$(${KUBECTL_CMD} get volumereplications --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
    
    if [[ -z "${vrs}" ]]; then
        echo "No VolumeReplication objects found"
        return
    fi
    
    echo "${vrs}" | while IFS=$'\t' read -r ns name; do
        if [[ -z "${ns}" ]] || [[ -z "${name}" ]]; then
            continue
        fi
        
        # Check if namespace matches our test pattern
        if [[ "${ns}" != ${NAMESPACE_PREFIX}* ]]; then
            continue
        fi
        
        # Get test-case label if present
            testCase=$(${KUBECTL_CMD} get volumereplication "${name}" -n "${ns}" -o jsonpath='{.metadata.labels.test-case}' 2>/dev/null || echo "")
        
        if [[ -n "${testCase}" ]]; then
            echo "Found VolumeReplication: ${ns}/${name} (test-case: ${testCase})"
        else
            echo "Found VolumeReplication: ${ns}/${name}"
        fi
        
        # Check for finalizers
        finalizers=$(${KUBECTL_CMD} get volumereplication "${name}" -n "${ns}" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
        
        if [[ -n "${finalizers}" ]]; then
            echo "  ⚠️  Has finalizers: ${finalizers}"
            
            if [[ "${DRY_RUN}" != "true" ]]; then
                if [[ "${FORCE}" == "true" ]]; then
                    echo "  🔧 Removing finalizers..."
                    ${KUBECTL_CMD} patch volumereplication "${name}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
                else
                    echo "  ⚠️  Skipping (use FORCE=true to remove finalizers)"
                    continue
                fi
            fi
        fi
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            echo "  🗑️  Deleting VolumeReplication ${ns}/${name}..."
            ${KUBECTL_CMD} delete volumereplication "${name}" -n "${ns}" --ignore-not-found=true || true
        else
            echo "  [DRY RUN] Would delete VolumeReplication ${ns}/${name}"
        fi
    done
    echo ""
}

# Function to cleanup PVCs in test namespaces
cleanup_pvcs() {
    echo "=== Cleaning up PVCs in test namespaces ==="
    
    # Get all namespaces matching our pattern
    namespaces=$(${KUBECTL_CMD} get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep "^${NAMESPACE_PREFIX}" || echo "")
    
    if [[ -z "${namespaces}" ]]; then
        echo "No test namespaces found"
        return
    fi
    
    echo "${namespaces}" | while read -r ns; do
        if [[ -z "${ns}" ]]; then
            continue
        fi
        
        echo "Checking namespace: ${ns}"
        
        # Get PVCs in this namespace
        pvcs=$(${KUBECTL_CMD} get pvc -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
        
        if [[ -z "${pvcs}" ]]; then
            echo "  No PVCs found"
            continue
        fi
        
        echo "${pvcs}" | while read -r pvc; do
            if [[ -z "${pvc}" ]]; then
                continue
            fi
            
            # Get test-case label if present
            testCase=$(${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" -o jsonpath='{.metadata.labels.test-case}' 2>/dev/null || echo "")
            
            # Check PVC status
            pvcStatus=$(${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            
            # Check for finalizers
            finalizers=$(${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
            
            if [[ -n "${testCase}" ]]; then
                echo "  Found PVC: ${pvc} (test-case: ${testCase}, status: ${pvcStatus:-Unknown})"
            else
                echo "  Found PVC: ${pvc} (status: ${pvcStatus:-Unknown})"
            fi
            
            # Handle PVCs stuck in Terminating state (most common case)
            if [[ "${pvcStatus}" == "Terminating" ]]; then
                echo "  ⚠️  PVC is stuck in Terminating state"
                if [[ -n "${finalizers}" ]]; then
                    echo "  ⚠️  Has finalizers: ${finalizers}"
                    if [[ "${FORCE}" == "true" ]]; then
                        echo "  🔧 Removing finalizers to unstick deletion..."
                        ${KUBECTL_CMD} patch pvc "${pvc}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
                        echo "  ✅ Finalizers removed, PVC should be deleted shortly"
                    else
                        echo "  ⚠️  Skipping (use FORCE=true to remove finalizers and unstick deletion)"
                        continue
                    fi
                else
                    echo "  ℹ️  No finalizers found, PVC should complete deletion automatically"
                fi
                continue
            fi
            
            # Handle PVCs with finalizers that aren't in Terminating yet
            if [[ -n "${finalizers}" ]]; then
                echo "  ⚠️  Has finalizers: ${finalizers}"
                if [[ "${FORCE}" == "true" ]]; then
                    echo "  🔧 Removing finalizers before deletion..."
                    ${KUBECTL_CMD} patch pvc "${pvc}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
                else
                    echo "  ⚠️  Skipping (use FORCE=true to remove finalizers)"
                    continue
                fi
            fi
            
            if [[ "${DRY_RUN}" != "true" ]]; then
                echo "  🗑️  Deleting PVC ${ns}/${pvc}..."
                ${KUBECTL_CMD} delete pvc "${pvc}" -n "${ns}" --ignore-not-found=true || true
                
                # Wait a bit and check if deletion succeeded or got stuck
                sleep ${CHECK_INTERVAL}
                if ${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" &>/dev/null; then
                    newStatus=$(${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
                    newFinalizers=$(${KUBECTL_CMD} get pvc "${pvc}" -n "${ns}" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null || echo "")
                    
                    if [[ "${newStatus}" == "Terminating" ]]; then
                        echo "  ⚠️  PVC is now in Terminating state"
                        if [[ -n "${newFinalizers}" ]]; then
                            if [[ "${FORCE}" == "true" ]]; then
                                echo "  🔧 Removing finalizers: ${newFinalizers}"
                                ${KUBECTL_CMD} patch pvc "${pvc}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
                            else
                                echo "  ⚠️  PVC deletion stuck with finalizers: ${newFinalizers}"
                                echo "  💡 Run with FORCE=true to remove finalizers"
                            fi
                        fi
                    fi
                else
                    echo "  ✅ PVC deleted successfully"
                fi
            else
                echo "  [DRY RUN] Would delete PVC ${ns}/${pvc}"
            fi
        done
    done
    echo ""
}

# Function to cleanup test namespaces
cleanup_namespaces() {
    echo "=== Cleaning up test namespaces ==="
    
    # Get all namespaces matching our pattern
    namespaces=$(${KUBECTL_CMD} get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep "^${NAMESPACE_PREFIX}" || echo "")
    
    if [[ -z "${namespaces}" ]]; then
        echo "No test namespaces found"
        return
    fi
    
    echo "${namespaces}" | while read -r ns; do
        if [[ -z "${ns}" ]]; then
            continue
        fi
        
        # Check if namespace is empty or only has finalizers
        resources=$(${KUBECTL_CMD} api-resources --verbs=list --namespaced -o name | xargs -n1 ${KUBECTL_CMD} get --show-kind --ignore-not-found -n "${ns}" 2>/dev/null | grep -v "No resources found" | wc -l || echo "0")
        
        if [[ "${resources}" == "0" ]] || [[ "${FORCE}" == "true" ]]; then
            echo "Found namespace: ${ns}"
            
            if [[ "${DRY_RUN}" != "true" ]]; then
                echo "  🗑️  Deleting namespace ${ns}..."
                ${KUBECTL_CMD} delete namespace "${ns}" --ignore-not-found=true --timeout=${WAIT_TIMEOUT}s || true
            else
                echo "  [DRY RUN] Would delete namespace ${ns}"
            fi
        else
            echo "Namespace ${ns} still has resources, skipping (use FORCE=true to force deletion)"
        fi
    done
    echo ""
}

# Main execution
main() {
    echo "Configuration:"
    echo "  Namespace prefix: ${NAMESPACE_PREFIX}"
    echo "  Dry run: ${DRY_RUN}"
    echo "  Force: ${FORCE}"
    if [[ -n "${KUBECTL_CONTEXT}" ]]; then
        echo "  Kubernetes context: ${KUBECTL_CONTEXT}"
    else
        echo "  Kubernetes context: (current)"
    fi
    echo "  Wait timeout: ${WAIT_TIMEOUT}s"
    echo "  Check interval: ${CHECK_INTERVAL}s"
    echo ""
    
    # Cleanup in order: VolumeReplications -> PVCs -> Namespaces
    cleanup_volume_replications
    cleanup_pvcs
    cleanup_namespaces
    
    echo "=========================================="
    echo "Cleanup completed!"
    echo ""
    echo "To see remaining resources:"
    echo "  ${KUBECTL_CMD} get volumereplications --all-namespaces"
    echo "  ${KUBECTL_CMD} get pvc --all-namespaces | grep ${NAMESPACE_PREFIX}"
    echo "  ${KUBECTL_CMD} get namespaces | grep ${NAMESPACE_PREFIX}"
    echo ""
    echo "To force cleanup (remove finalizers):"
    echo "  FORCE=true ${0}"
    echo ""
    echo "To preview what would be deleted:"
    echo "  DRY_RUN=true ${0}"
    echo ""
    echo "For more options, run: ${0} --help"
}

# Execute main function
main "$@"
