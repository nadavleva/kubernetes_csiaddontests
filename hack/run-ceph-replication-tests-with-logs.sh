#!/bin/bash
# Simple script to run Ceph replication tests and capture output to Logs folder
# Usage: ./hack/run-ceph-replication-tests-with-logs.sh [driver-config.yaml] [focus-pattern]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${REPO_ROOT}/Logs"

# Default values
DRIVER_CONFIG="${1:-${REPO_ROOT}/examples/ceph-replication-driver.yaml}"
FOCUS_PATTERN="${2:-External.Storage.*\[Feature:Replication\]}"
VERBOSE="${VERBOSE:-1}"

# Create Logs directory if it doesn't exist
mkdir -p "${LOGS_DIR}"

# Generate timestamp for log filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOGS_DIR}/ceph-replication-test_${TIMESTAMP}.log"

echo "=========================================="
echo "CSI Replication Tests - Ceph Storage"
echo "=========================================="
echo ""

# Check KUBECONFIG
if [[ -z "${KUBECONFIG:-}" ]]; then
    if [[ -f "${HOME}/.kube/config" ]]; then
        export KUBECONFIG="${HOME}/.kube/config"
    else
        echo "WARNING: KUBECONFIG not set. Tests may fail if kubectl cannot access cluster."
    fi
fi

# Convert to absolute path (must be done before using DRIVER_CONFIG_ABS)
DRIVER_CONFIG_ABS=$(cd "$(dirname "${DRIVER_CONFIG}")" && pwd)/$(basename "${DRIVER_CONFIG}")

echo "Driver Config: ${DRIVER_CONFIG_ABS}"
echo "Focus Pattern: ${FOCUS_PATTERN}"
echo "KUBECONFIG: ${KUBECONFIG:-not set (using default)}"
echo "Log File: ${LOG_FILE}"
echo ""

# Verify file exists
if [[ ! -f "${DRIVER_CONFIG_ABS}" ]]; then
    echo "ERROR: Driver config file not found: ${DRIVER_CONFIG_ABS}"
    exit 1
fi

# Extract driver name from config
DRIVER_NAME=$(grep -E "^[[:space:]]*Name:" "${DRIVER_CONFIG_ABS}" | head -1 | sed 's/.*Name:[[:space:]]*//' | tr -d '"' || echo "")

if [[ -z "${DRIVER_NAME}" ]]; then
    echo "ERROR: Could not extract driver name from config file."
    exit 1
fi

# Build focus pattern with driver name
FULL_FOCUS="External.Storage.*${DRIVER_NAME}.*${FOCUS_PATTERN}"

# Prepare ginkgo command
GINKGO_CMD="go test -v ./test/e2e"
GINKGO_CMD="${GINKGO_CMD} --ginkgo.focus=\"${FULL_FOCUS}\""
GINKGO_CMD="${GINKGO_CMD} --ginkgo.no-color"
GINKGO_CMD="${GINKGO_CMD} --storage.testdriver=\"${DRIVER_CONFIG_ABS}\""

# Add kubeconfig if set
if [[ -n "${KUBECONFIG:-}" ]]; then
    GINKGO_CMD="${GINKGO_CMD} --kubeconfig=\"${KUBECONFIG}\""
fi

# Add provider flag for local cluster testing (per Kubernetes e2e testing guidelines)
# Default to "local" if not set, as per https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md
PROVIDER="${PROVIDER:-local}"
GINKGO_CMD="${GINKGO_CMD} --provider=\"${PROVIDER}\""

if [[ "${VERBOSE}" == "1" ]] || [[ "${VERBOSE}" == "2" ]]; then
    GINKGO_CMD="${GINKGO_CMD} --ginkgo.v"
fi

if [[ "${VERBOSE}" == "2" ]]; then
    GINKGO_CMD="${GINKGO_CMD} --ginkgo.vv"
fi

echo "Command: ${GINKGO_CMD}"
echo "Provider: ${PROVIDER:-local}"
echo "Output will be saved to: ${LOG_FILE}"
echo ""
echo "Starting tests at $(date)..."
echo "=========================================="
echo ""

# Change to repo root
cd "${REPO_ROOT}"

# Build replication test suite before running
echo "Building replication test suite..."
VERBOSE=${VERBOSE:-1} make replication-build

# Run tests and capture all output to log file
# Using tee to also show output on screen while saving to file
eval "${GINKGO_CMD}" 2>&1 | tee "${LOG_FILE}"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
echo "Test Execution Complete"
echo "=========================================="
echo "Exit Code: ${EXIT_CODE}"
echo "Log File: ${LOG_FILE}"
echo "Completed at $(date)"

# Create a symlink to the latest log for easy access
LATEST_LOG="${LOGS_DIR}/latest.log"
ln -sf "$(basename "${LOG_FILE}")" "${LATEST_LOG}"
echo "Latest log symlink: ${LATEST_LOG}"

exit ${EXIT_CODE}
