#!/bin/bash
# List available replication tests for a driver
# Usage: ./hack/list-replication-tests.sh [driver-config.yaml]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRIVER_CONFIG="${1:-${REPO_ROOT}/rook-ceph-rbd-driver.yaml}"

if [[ ! -f "${DRIVER_CONFIG}" ]]; then
    echo "ERROR: Driver config not found: ${DRIVER_CONFIG}"
    exit 1
fi

# Extract driver name
DRIVER_NAME=$(grep -E "^[[:space:]]*Name:" "${DRIVER_CONFIG}" | head -1 | sed 's/.*Name:[[:space:]]*//' | tr -d '"' || echo "")

if [[ -z "${DRIVER_NAME}" ]]; then
    echo "ERROR: Could not extract driver name from config"
    exit 1
fi

echo "Listing tests for driver: ${DRIVER_NAME}"
echo "Using config: ${DRIVER_CONFIG}"
echo ""

cd "${REPO_ROOT}"

# List all External Storage tests for this driver
echo "=== All External Storage tests for ${DRIVER_NAME} ==="
go test ./test/e2e --ginkgo.dry-run --ginkgo.focus="External.Storage.*${DRIVER_NAME}" --storage.testdriver="${DRIVER_CONFIG}" 2>&1 | grep "External.Storage" | head -50

echo ""
echo "=== Tests matching 'replication' ==="
go test ./test/e2e --ginkgo.dry-run --ginkgo.focus="External.Storage.*${DRIVER_NAME}.*replication" --storage.testdriver="${DRIVER_CONFIG}" 2>&1 | grep -i replication | head -20

echo ""
echo "=== Tests matching 'EnableVolumeReplication' ==="
go test ./test/e2e --ginkgo.dry-run --ginkgo.focus="External.Storage.*${DRIVER_NAME}.*EnableVolumeReplication" --storage.testdriver="${DRIVER_CONFIG}" 2>&1 | grep -i "EnableVolumeReplication\|External.Storage" | head -20

echo ""
echo "=== All External Storage tests (no filter) ==="
go test ./test/e2e --ginkgo.dry-run --ginkgo.focus="External.Storage.*${DRIVER_NAME}" --storage.testdriver="${DRIVER_CONFIG}" 2>&1 | tail -5
