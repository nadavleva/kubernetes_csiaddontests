#!/bin/bash
# Quick-start script to run CSI replication tests against Ceph storage cluster
# Usage: ./hack/run-ceph-replication-tests.sh [driver-config.yaml] [focus-pattern]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
DRIVER_CONFIG="${1:-${REPO_ROOT}/examples/ceph-replication-driver.yaml}"
FOCUS_PATTERN="${2:-External.Storage.*\[Feature:Replication\]}"
VERBOSE="${VERBOSE:-0}"

echo "=========================================="
echo "CSI Replication Tests - Ceph Storage"
echo "=========================================="
echo ""
echo "Driver Config: ${DRIVER_CONFIG}"
echo "Focus Pattern: ${FOCUS_PATTERN}"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot access Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

# Check if driver config exists
if [[ ! -f "${DRIVER_CONFIG}" ]]; then
    echo "ERROR: Driver config file not found: ${DRIVER_CONFIG}"
    echo ""
    echo "Please create a driver config file or use the example:"
    echo "  cp examples/ceph-replication-driver.yaml my-ceph-driver.yaml"
    echo "  # Edit my-ceph-driver.yaml with your Ceph CSI driver details"
    echo "  ${0} my-ceph-driver.yaml"
    exit 1
fi

# Extract driver name from config
DRIVER_NAME=$(grep -E "^[[:space:]]*Name:" "${DRIVER_CONFIG}" | head -1 | sed 's/.*Name:[[:space:]]*//' | tr -d '"' || echo "")

if [[ -z "${DRIVER_NAME}" ]]; then
    echo "ERROR: Could not extract driver name from config file."
    exit 1
fi

echo "✓ kubectl available"
echo "✓ Cluster accessible"
echo "✓ Driver config found: ${DRIVER_CONFIG}"
echo "✓ Driver name: ${DRIVER_NAME}"
echo ""

# Verify CSIDriver exists
echo "Verifying CSIDriver deployment..."
if ! kubectl get csidriver "${DRIVER_NAME}" &> /dev/null; then
    echo "WARNING: CSIDriver '${DRIVER_NAME}' not found in cluster."
    echo "Available CSIDrivers:"
    kubectl get csidrivers || true
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✓ CSIDriver '${DRIVER_NAME}' found"
fi

# Verify StorageClass
STORAGE_CLASS=$(grep -A 5 "StorageClass:" "${DRIVER_CONFIG}" | grep "FromExistingClassName:" | sed 's/.*FromExistingClassName:[[:space:]]*//' | tr -d '"' || echo "")

if [[ -n "${STORAGE_CLASS}" ]]; then
    if kubectl get storageclass "${STORAGE_CLASS}" &> /dev/null; then
        echo "✓ StorageClass '${STORAGE_CLASS}' found"
    else
        echo "WARNING: StorageClass '${STORAGE_CLASS}' not found."
        echo "Available StorageClasses:"
        kubectl get storageclass || true
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo ""
echo "Building test suite..."
cd "${REPO_ROOT}"

# Build ginkgo if needed
if [[ ! -f "${REPO_ROOT}/_output/bin/ginkgo" ]]; then
    echo "Building ginkgo..."
    VERBOSE=${VERBOSE:-1} make ginkgo
fi

echo ""
echo "=========================================="
echo "Running Replication Tests"
echo "=========================================="
echo ""

# Build focus pattern with driver name
FULL_FOCUS="External.Storage.*${DRIVER_NAME}.*${FOCUS_PATTERN}"

# Prepare ginkgo command
GINKGO_CMD="go test -v ./test/e2e"
GINKGO_CMD="${GINKGO_CMD} --ginkgo.focus=\"${FULL_FOCUS}\""
GINKGO_CMD="${GINKGO_CMD} --ginkgo.no-color"
GINKGO_CMD="${GINKGO_CMD} --storage.testdriver=\"${DRIVER_CONFIG}\""

if [[ "${VERBOSE}" == "1" ]] || [[ "${VERBOSE}" == "2" ]]; then
    GINKGO_CMD="${GINKGO_CMD} --ginkgo.v"
fi

if [[ "${VERBOSE}" == "2" ]]; then
    GINKGO_CMD="${GINKGO_CMD} --ginkgo.vv"
fi

echo "Command: ${GINKGO_CMD}"
echo ""

# Run the tests
eval "${GINKGO_CMD}"

echo ""
echo "=========================================="
echo "Test Execution Complete"
echo "=========================================="
