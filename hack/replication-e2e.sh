#!/usr/bin/env bash

# Copyright 2024 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script runs CSI replication e2e tests using ginkgo.
# It supports both main tests (for certification) and mock tests (for development).

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
source "${KUBE_ROOT}/hack/lib/init.sh"

# Find the ginkgo binary
ginkgo=$(kube::util::find-binary "ginkgo")

# Configuration variables with defaults
FOCUS_PATTERN="${FOCUS_PATTERN:-}"
SKIP_PATTERN="${SKIP_PATTERN:-}"
VERBOSITY="${VERBOSITY:-0}"
TEST_TYPE="${TEST_TYPE:-all}"
CSI_DRIVER="${CSI_DRIVER:-}"

# Verbosity settings for ginkgo
case "${VERBOSITY}" in
    0)
        GINKGO_ARGS=""
        ;;
    1)
        GINKGO_ARGS="-v"
        ;;
    2)
        GINKGO_ARGS="-vv"
        ;;
    *)
        GINKGO_ARGS="-v"
        ;;
esac

# Add focus and skip patterns if specified
if [[ -n "${FOCUS_PATTERN}" ]]; then
    GINKGO_ARGS="${GINKGO_ARGS} --focus='${FOCUS_PATTERN}'"
fi

if [[ -n "${SKIP_PATTERN}" ]]; then
    GINKGO_ARGS="${GINKGO_ARGS} --skip='${SKIP_PATTERN}'"
fi

# Function to run mock tests
run_mock_tests() {
    echo "Running CSI replication mock tests..."
    echo "Args: ${GINKGO_ARGS}"
    
    # Mock tests focus on CSI replication protocol validation
    local test_args=""
    if [[ -n "${FOCUS_PATTERN}" ]]; then
        test_args="-ginkgo.focus='.*CSI replication.*${FOCUS_PATTERN}'"
    else
        test_args="-ginkgo.focus='.*CSI replication'"
    fi
    
    if [[ -n "${SKIP_PATTERN}" ]]; then
        test_args="${test_args} -ginkgo.skip='${SKIP_PATTERN}'"
    fi
    
    # Add verbosity
    if [[ "${VERBOSITY}" == "1" ]]; then
        test_args="${test_args} -ginkgo.v"
    elif [[ "${VERBOSITY}" == "2" ]]; then
        test_args="${test_args} -ginkgo.vv"
    fi
    
    echo "Running: go test ./test/e2e/storage/csimock ${test_args}"
    eval "go test ./test/e2e/storage/csimock ${test_args}"
}

# Function to run main tests
run_main_tests() {
    if [[ -z "${CSI_DRIVER}" ]]; then
        echo "Error: CSI_DRIVER must be specified for main tests"
        echo "Example: CSI_DRIVER=./path/to/driver.yaml"
        exit 1
    fi
    
    echo "Running CSI replication main tests with driver: ${CSI_DRIVER}"
    echo "Args: ${GINKGO_ARGS}"
    
    # Validate that the driver file exists
    if [[ ! -f "${CSI_DRIVER}" ]]; then
        echo "Error: CSI driver file not found: ${CSI_DRIVER}"
        exit 1
    fi
    
    # Main tests focus on replication test suite
    local test_args=""
    if [[ -n "${FOCUS_PATTERN}" ]]; then
        test_args="-ginkgo.focus='Replication.*${FOCUS_PATTERN}'"
    else
        test_args="-ginkgo.focus='Replication'"
    fi
    
    if [[ -n "${SKIP_PATTERN}" ]]; then
        test_args="${test_args} -ginkgo.skip='${SKIP_PATTERN}'"
    fi
    
    # Add verbosity
    if [[ "${VERBOSITY}" == "1" ]]; then
        test_args="${test_args} -ginkgo.v"
    elif [[ "${VERBOSITY}" == "2" ]]; then
        test_args="${test_args} -ginkgo.vv"
    fi
    
    # Export driver configuration for tests
    export CSI_DRIVER_MANIFEST="${CSI_DRIVER}"
    
    echo "Running: go test ./test/e2e/storage/testsuites ${test_args}"
    eval "go test ./test/e2e/storage/testsuites ${test_args}"
}

# Function to validate environment
validate_environment() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "Warning: kubectl not found in PATH. Some tests may fail."
    fi
    
    # Check if running in cluster or with kubeconfig
    if [[ -z "${KUBECONFIG:-}" ]] && [[ ! -f "$HOME/.kube/config" ]] && [[ ! -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]]; then
        echo "Warning: No Kubernetes configuration found. Tests may fail."
        echo "Set KUBECONFIG or ensure ~/.kube/config exists."
    fi
}

# Main execution logic
main() {
    echo "=== CSI Replication E2E Test Runner ==="
    echo "Test type: ${TEST_TYPE}"
    echo "Verbosity: ${VERBOSITY}"
    [[ -n "${FOCUS_PATTERN}" ]] && echo "Focus: ${FOCUS_PATTERN}"
    [[ -n "${SKIP_PATTERN}" ]] && echo "Skip: ${SKIP_PATTERN}"
    [[ -n "${CSI_DRIVER}" ]] && echo "Driver: ${CSI_DRIVER}"
    echo "==========================================="
    
    validate_environment
    
    case "${TEST_TYPE}" in
        mock)
            run_mock_tests
            ;;
        main)
            run_main_tests
            ;;
        all)
            echo "Running all replication tests..."
            run_mock_tests
            echo ""
            echo "Mock tests completed. Running main tests..."
            if [[ -n "${CSI_DRIVER}" ]]; then
                run_main_tests
            else
                echo "Skipping main tests: no CSI_DRIVER specified"
                echo "To run main tests, provide: CSI_DRIVER=./path/to/driver.yaml"
            fi
            ;;
        *)
            echo "Error: Invalid TEST_TYPE '${TEST_TYPE}'. Must be 'mock', 'main', or 'all'"
            exit 1
            ;;
    esac
    
    echo ""
    echo "CSI replication tests completed successfully!"
}

# Execute main function
main "$@"