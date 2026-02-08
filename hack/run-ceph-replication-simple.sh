#!/bin/bash
# Simple script to run Ceph replication tests with automatic setup and logging
# 
# Usage: ./hack/run-ceph-replication-simple.sh
#
# Environment variables:
#   DRY_RUN          - Dry-run mode: "true" = only show test list and exit,
#                      "preview" = show test list then run tests (default),
#                      "false" = skip dry-run and run tests directly
#   GENERATE_REPORTS - Set to "true" to generate JUnit and JSON reports (default: "true")
#   FOCUSED_REPORTS  - Set to "true" to create focused JUnit reports with only replication tests (default: "true")
#   KEEP_FULL_REPORT - Set to "true" to keep the full JUnit report alongside the focused one (default: "false")
#   REPORT_DIR       - Directory for test reports (default: "${REPO_ROOT}/Reports")
#   PROVIDER         - Kubernetes provider (default: "local")
#   VERBOSE          - Verbosity level (default: "1")
#
# Examples:
#   # Preview mode: show test list then run tests (default)
#   ./hack/run-ceph-replication-simple.sh
#   DRY_RUN=preview ./hack/run-ceph-replication-simple.sh
#
#   # Dry-run only: show test list and exit (don't run tests)
#   DRY_RUN=true ./hack/run-ceph-replication-simple.sh
#
#   # Skip dry-run: run tests directly without preview
#   DRY_RUN=false ./hack/run-ceph-replication-simple.sh
#
#   # Run without reports
#   GENERATE_REPORTS=false ./hack/run-ceph-replication-simple.sh
#
#   # Generate focused reports only (default)
#   FOCUSED_REPORTS=true ./hack/run-ceph-replication-simple.sh
#
#   # Keep both full and focused reports
#   KEEP_FULL_REPORT=true ./hack/run-ceph-replication-simple.sh
#
#   # Custom report directory
#   REPORT_DIR=/tmp/my-reports ./hack/run-ceph-replication-simple.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${REPO_ROOT}/Logs"
REPORTS_DIR="${REPORT_DIR:-${REPO_ROOT}/Reports}"

# Create Logs and Reports directories
mkdir -p "${LOGS_DIR}"
mkdir -p "${REPORTS_DIR}"

# Configuration flags
# DRY_RUN modes: "true" = only dry-run (exit after), "preview" = dry-run then run, "false" = skip dry-run
DRY_RUN="${DRY_RUN:-preview}"
GENERATE_REPORTS="${GENERATE_REPORTS:-true}"
FOCUSED_REPORTS="${FOCUSED_REPORTS:-true}"
KEEP_FULL_REPORT="${KEEP_FULL_REPORT:-false}"

# Generate timestamp for log filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOGS_DIR}/ceph-replication-test_${TIMESTAMP}.log"

echo "=========================================="
echo "Ceph Replication Test Runner"
echo "=========================================="
echo ""

# Step 1: Verify cluster access
echo "[1/5] Verifying cluster access..."

# Check if KUBECONFIG is set, if not try default locations
if [[ -z "${KUBECONFIG:-}" ]]; then
    if [[ -f "${HOME}/.kube/config" ]]; then
        export KUBECONFIG="${HOME}/.kube/config"
        echo "Using KUBECONFIG: ${KUBECONFIG}"
    else
        echo "WARNING: KUBECONFIG not set and ${HOME}/.kube/config not found"
        echo "Please set KUBECONFIG environment variable or ensure kubeconfig is in default location"
    fi
else
    echo "Using KUBECONFIG: ${KUBECONFIG}"
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot access Kubernetes cluster."
    echo "Please check:"
    echo "  1. KUBECONFIG is set correctly: ${KUBECONFIG:-not set}"
    echo "  2. kubectl can access the cluster: kubectl cluster-info"
    echo "  3. For minikube: minikube status"
    exit 1
fi
echo "✓ Cluster accessible"

# Step 2: Detect Ceph CSI driver
echo "[2/5] Detecting Ceph CSI drivers..."
DRIVER_NAME=""
if kubectl get csidriver rook-ceph.rbd.csi.ceph.com &> /dev/null; then
    DRIVER_NAME="rook-ceph.rbd.csi.ceph.com"
    echo "✓ Found Rook Ceph RBD driver: ${DRIVER_NAME}"
elif kubectl get csidriver rbd.csi.ceph.com &> /dev/null; then
    DRIVER_NAME="rbd.csi.ceph.com"
    echo "✓ Found standard Ceph RBD driver: ${DRIVER_NAME}"
else
    echo "ERROR: No Ceph RBD CSI driver found."
    echo "Available drivers:"
    kubectl get csidrivers
    exit 1
fi

# Step 3: Detect StorageClass
echo "[3/5] Detecting StorageClass..."
STORAGE_CLASS=""
if kubectl get storageclass rook-ceph-block &> /dev/null; then
    STORAGE_CLASS="rook-ceph-block"
elif kubectl get storageclass csi-rbd-sc &> /dev/null; then
    STORAGE_CLASS="csi-rbd-sc"
else
    # Try to auto-detect
    STORAGE_CLASS=$(kubectl get storageclass -o jsonpath="{.items[?(@.provisioner==\"${DRIVER_NAME}\")].metadata.name}" 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -z "${STORAGE_CLASS}" ]]; then
        echo "WARNING: Could not auto-detect StorageClass. Please specify manually."
        echo "Available StorageClasses:"
        kubectl get storageclass
        read -p "Enter StorageClass name: " STORAGE_CLASS
    fi
fi
echo "✓ Using StorageClass: ${STORAGE_CLASS}"

# Step 4: Create driver config
echo "[4/5] Creating driver configuration..."
DRIVER_CONFIG="${REPO_ROOT}/rook-ceph-rbd-driver.yaml"
cat > "${DRIVER_CONFIG}" <<EOF
DriverInfo:
  Name: ${DRIVER_NAME}
  SupportedSizeRange:
    Min: 1Gi
    Max: 10Ti
  Capabilities:
    persistence: true
    replication: true
    block: true
    controllerExpansion: true
    topology: true
StorageClass:
  FromExistingClassName: ${STORAGE_CLASS}
EOF
echo "✓ Driver config created: ${DRIVER_CONFIG}"

# Convert to absolute path to avoid path issues
DRIVER_CONFIG_ABS=$(cd "$(dirname "${DRIVER_CONFIG}")" && pwd)/$(basename "${DRIVER_CONFIG}")

# Step 5: Build and run tests
echo "[5/5] Building test framework and running tests..."
echo ""

# Build replication test suite and ginkgo if needed
cd "${REPO_ROOT}"
echo "Building replication test suite..."
VERBOSE=${VERBOSE:-1} make replication-build

if [[ ! -f "${REPO_ROOT}/_output/bin/ginkgo" ]]; then
    echo "Building ginkgo..."
    VERBOSE=${VERBOSE:-1} make ginkgo
fi

# Dry-run to see what tests match
# Modes: "true" = only dry-run (exit), "preview" = dry-run then run, "false" = skip
if [[ "${DRY_RUN}" == "true" ]] || [[ "${DRY_RUN}" == "preview" ]]; then
    DRY_RUN_ONLY=false
    if [[ "${DRY_RUN}" == "true" ]]; then
        DRY_RUN_ONLY=true
        echo "=========================================="
        echo "Dry-Run Only: Listing tests that would be executed"
        echo "=========================================="
        echo "(Tests will NOT be executed. Set DRY_RUN=preview to preview then run, or DRY_RUN=false to skip dry-run)"
    else
        echo "=========================================="
        echo "Dry-Run Preview: Checking what tests match the focus pattern"
        echo "=========================================="
        echo "(Tests will be executed after this preview. Set DRY_RUN=true for dry-run only, or DRY_RUN=false to skip)"
    fi
    echo ""
    cd "${REPO_ROOT}"
    DRY_RUN_FOCUS="External.Storage.*${DRIVER_NAME}.*EnableVolumeReplication|External.Storage.*${DRIVER_NAME}.*GetVolumeReplicationInfo|External.Storage.*${DRIVER_NAME}.*replication"
    
    echo "Listing tests with focus: ${DRY_RUN_FOCUS}"
    echo ""
    
    # Create a temporary JSON report file for dry-run
    TEMP_JSON_REPORT=$(mktemp /tmp/ginkgo-dry-run-XXXXXX.json)
    trap "rm -f ${TEMP_JSON_REPORT}" EXIT
    
    # Try multiple methods to get test names:
    # Method 1: Use --list-tests flag (framework flag)
    set +e  # Temporarily disable exit on error
    DRY_RUN_OUTPUT=$(cd "${REPO_ROOT}" && go test ./test/e2e --ginkgo.focus="${DRY_RUN_FOCUS}" --list-tests --storage.testdriver="${DRIVER_CONFIG_ABS}" 2>&1)
    DRY_RUN_EXIT_CODE=$?
    set -e
    
    # Method 2: If --list-tests doesn't produce test names, try JSON report with dry-run
    if [[ -z "${DRY_RUN_OUTPUT}" ]] || echo "${DRY_RUN_OUTPUT}" | grep -qE "^(ok|FAIL)"; then
        echo "Trying alternative method: Using JSON report with dry-run..."
        set +e
        cd "${REPO_ROOT}"
        go test ./test/e2e --ginkgo.focus="${DRY_RUN_FOCUS}" --ginkgo.dry-run --ginkgo.json-report="${TEMP_JSON_REPORT}" --storage.testdriver="${DRIVER_CONFIG_ABS}" >/dev/null 2>&1
        if [[ -f "${TEMP_JSON_REPORT}" ]] && [[ -s "${TEMP_JSON_REPORT}" ]]; then
            # Extract test names from JSON report using jq if available, otherwise use grep
            if command -v jq &> /dev/null; then
                TEST_NAMES_FROM_JSON=$(jq -r '.SpecReports[]? | select(.LeafNodeType == "It") | .FullText' "${TEMP_JSON_REPORT}" 2>/dev/null | head -200)
                if [[ -n "${TEST_NAMES_FROM_JSON}" ]]; then
                    DRY_RUN_OUTPUT="Test names from JSON report:
${TEST_NAMES_FROM_JSON}"
                fi
            else
                # Fallback: try to extract from JSON using grep
                TEST_NAMES_FROM_JSON=$(grep -oE '"FullText":"[^"]*External\.Storage[^"]*"' "${TEMP_JSON_REPORT}" 2>/dev/null | sed 's/"FullText":"\(.*\)"/\1/' | head -200)
                if [[ -n "${TEST_NAMES_FROM_JSON}" ]]; then
                    DRY_RUN_OUTPUT="Test names from JSON report:
${TEST_NAMES_FROM_JSON}"
                fi
            fi
        fi
        set -e
    fi
    
    # Method 3: If still nothing, try running with --ginkgo.v and --ginkgo.dry-run to see verbose output
    if [[ -z "${DRY_RUN_OUTPUT}" ]] || echo "${DRY_RUN_OUTPUT}" | grep -qE "^(ok|FAIL)"; then
        echo "Trying verbose dry-run to extract test names..."
        set +e
        VERBOSE_DRY_RUN=$(cd "${REPO_ROOT}" && timeout 30 go test ./test/e2e --ginkgo.focus="${DRY_RUN_FOCUS}" --ginkgo.dry-run --ginkgo.v --storage.testdriver="${DRIVER_CONFIG_ABS}" 2>&1 | head -500)
        if echo "${VERBOSE_DRY_RUN}" | grep -qiE "External\.Storage.*${DRIVER_NAME}"; then
            DRY_RUN_OUTPUT="${VERBOSE_DRY_RUN}"
        fi
        set -e
    fi
    
    # Always show raw output first for debugging, then try to extract
    RAW_OUTPUT_LINES=$(echo "${DRY_RUN_OUTPUT}" | wc -l)
    
    if [[ -z "${DRY_RUN_OUTPUT}" ]] || [[ "${RAW_OUTPUT_LINES}" -eq 0 ]]; then
        echo "⚠ Dry-run produced no output (exit code: ${DRY_RUN_EXIT_CODE})."
        echo "This might indicate:"
        echo "   - No tests match the focus pattern"
        echo "   - Test framework initialization failed"
        echo "   - Driver configuration issue"
        echo ""
        echo "Try running without dry-run to see actual errors:"
        echo "  DRY_RUN=false ./hack/run-ceph-replication-simple.sh"
    else
        # Show raw output first so user can see what ginkgo returned
        echo "Raw dry-run output (${RAW_OUTPUT_LINES} lines):"
        echo "----------------------------------------"
        echo "${DRY_RUN_OUTPUT}"
        echo "----------------------------------------"
        echo ""
        
        # Extract test names from output
        echo "Test names that will be executed:"
        echo "----------------------------------------"
        
        # Check if output contains "Test names from JSON report" (from our JSON extraction)
        if echo "${DRY_RUN_OUTPUT}" | grep -q "Test names from JSON report"; then
            TEST_NAMES=$(echo "${DRY_RUN_OUTPUT}" | sed -n '/Test names from JSON report:/,$p' | tail -n +2 | head -200)
        # Check if --list-tests output format (has "The following spec names")
        elif echo "${DRY_RUN_OUTPUT}" | grep -q "The following spec names"; then
            # Extract lines after the header (indented lines with file:line: format)
            TEST_NAMES=$(echo "${DRY_RUN_OUTPUT}" | sed -n '/The following spec names/,/^$/p' | grep -E "^\s+.*:" | sed 's/^[[:space:]]*//' | head -200)
        # Try extracting lines with "External.Storage" and driver name
        else
            TEST_NAMES=$(echo "${DRY_RUN_OUTPUT}" | grep -iE "External\.Storage.*${DRIVER_NAME}" | head -200)
        fi
        
        # If still nothing, try extracting any lines that look like test descriptions
        if [[ -z "${TEST_NAMES}" ]]; then
            # Look for lines with test patterns (EnableVolumeReplication, GetVolumeReplicationInfo, etc.)
            TEST_NAMES=$(echo "${DRY_RUN_OUTPUT}" | grep -iE "(EnableVolumeReplication|GetVolumeReplicationInfo|replication.*test)" | head -200)
        fi
        
        # If still nothing, try extracting from verbose output (lines with [It] or test descriptions)
        if [[ -z "${TEST_NAMES}" ]]; then
            TEST_NAMES=$(echo "${DRY_RUN_OUTPUT}" | grep -E "\[(It|Spec|Describe|Context)\]" | head -200)
        fi
        
        if [[ -n "${TEST_NAMES}" ]]; then
            echo "${TEST_NAMES}"
            TEST_COUNT=$(echo "${TEST_NAMES}" | wc -l)
            echo ""
            echo "✓ Found ${TEST_COUNT} test spec(s) that match the focus pattern"
        else
            # Last resort: show any non-empty lines that might contain test info
            echo "Could not extract test names. Showing relevant output:"
            echo "----------------------------------------"
            # Filter out common go test output lines
            RELEVANT=$(echo "${DRY_RUN_OUTPUT}" | grep -vE "^(ok|FAIL|===|Running|Will run|Ginkgo)" | grep -v "^$" | grep -iE "(test|spec|external|storage|replication|${DRIVER_NAME})" | head -100)
            if [[ -n "${RELEVANT}" ]]; then
                echo "${RELEVANT}"
            else
                echo "(No test names found in output)"
                echo ""
                echo "Note: The 'ok' message above indicates tests were found, but test names weren't listed."
                echo "This is a known limitation of --ginkgo.dry-run."
                echo ""
                echo "To see test names, try:"
                echo "  1. Run with DRY_RUN=preview to see test names during execution"
                echo "  2. Run: go test ./test/e2e --ginkgo.focus=\"${DRY_RUN_FOCUS}\" --ginkgo.v --storage.testdriver=\"${DRIVER_CONFIG_ABS}\" | grep -E 'External.Storage'"
            fi
        fi
    fi
    echo ""
    echo "=========================================="
    echo ""
    
    # If dry-run only, exit here
    if [[ "${DRY_RUN_ONLY}" == "true" ]]; then
        echo "Dry-run completed. Exiting without running tests."
        echo "To run the tests, use: DRY_RUN=preview ./hack/run-ceph-replication-simple.sh"
        echo "Or: DRY_RUN=false ./hack/run-ceph-replication-simple.sh"
        exit 0
    fi
fi

# Prepare test command

# Try simpler focus pattern first - just match driver and replication-related tests
FULL_FOCUS="External.Storage.*${DRIVER_NAME}.*EnableVolumeReplication|External.Storage.*${DRIVER_NAME}.*GetVolumeReplicationInfo|External.Storage.*${DRIVER_NAME}.*replication"
TEST_CMD="go test -v ./test/e2e --ginkgo.focus=\"${FULL_FOCUS}\" --ginkgo.v --ginkgo.no-color --storage.testdriver=\"${DRIVER_CONFIG_ABS}\""

# Add kubeconfig if set
if [[ -n "${KUBECONFIG:-}" ]]; then
    TEST_CMD="${TEST_CMD} --kubeconfig=\"${KUBECONFIG}\""
fi

# Add provider flag for local cluster testing (per Kubernetes e2e testing guidelines)
# Default to "local" if not set, as per https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/e2e-tests.md
PROVIDER="${PROVIDER:-local}"
TEST_CMD="${TEST_CMD} --provider=\"${PROVIDER}\""

# Initialize report variables (will be set if reports are enabled)
REPORT_PREFIX=""
REPORT_DIR_ABS=""

# Add report generation if enabled
if [[ "${GENERATE_REPORTS}" == "true" ]]; then
    REPORT_PREFIX="ceph-replication-${TIMESTAMP}"
    REPORT_DIR_ABS=$(cd "$(dirname "${REPORTS_DIR}")" && pwd)/$(basename "${REPORTS_DIR}")
    
    # Create report directory
    mkdir -p "${REPORT_DIR_ABS}"
    
    # Add report flags for Ginkgo
    TEST_CMD="${TEST_CMD} --ginkgo.junit-report=\"${REPORT_DIR_ABS}/${REPORT_PREFIX}-junit.xml\""
    TEST_CMD="${TEST_CMD} --ginkgo.json-report=\"${REPORT_DIR_ABS}/${REPORT_PREFIX}-report.json\""
    
    # Add e2e framework report flags (for Kubernetes e2e framework reports)
    TEST_CMD="${TEST_CMD} --report-dir=\"${REPORT_DIR_ABS}\""
    TEST_CMD="${TEST_CMD} --report-prefix=\"${REPORT_PREFIX}\""
fi

echo "=========================================="
echo "Running Tests"
echo "=========================================="
echo "Driver: ${DRIVER_NAME}"
echo "StorageClass: ${STORAGE_CLASS}"
echo "Focus: ${FULL_FOCUS}"
echo "Driver Config: ${DRIVER_CONFIG_ABS}"
echo "Provider: ${PROVIDER:-local}"
echo "Dry-Run: ${DRY_RUN}"
echo "Generate Reports: ${GENERATE_REPORTS}"
if [[ "${GENERATE_REPORTS}" == "true" ]]; then
    echo "Report Directory: ${REPORT_DIR_ABS}"
    echo "Report Prefix: ${REPORT_PREFIX}"
    echo "Focused Reports: ${FOCUSED_REPORTS}"
    echo "Keep Full Report: ${KEEP_FULL_REPORT}"
fi
echo "Log File: ${LOG_FILE}"
echo ""
echo "Starting at $(date)..."
echo ""

# Change to repo root and run tests
cd "${REPO_ROOT}"

# Verify driver config exists
if [[ ! -f "${DRIVER_CONFIG_ABS}" ]]; then
    echo "ERROR: Driver config file not found: ${DRIVER_CONFIG_ABS}"
    exit 1
fi

# Run tests and capture output
eval "${TEST_CMD}" 2>&1 | tee "${LOG_FILE}"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
echo "Test Execution Complete"
echo "=========================================="
echo "Exit Code: ${EXIT_CODE}"
echo "Log File: ${LOG_FILE}"
echo "Completed at $(date)"
echo ""

# Function to create focused JUnit report
create_focused_junit_report() {
    local full_junit_file="$1"
    local focused_junit_file="$2"
    local driver_name="$3"
    
    if [[ ! -f "${full_junit_file}" ]]; then
        echo "WARNING: Full JUnit report not found: ${full_junit_file}"
        return 1
    fi
    
    echo "Creating focused JUnit report..."
    
    # Extract replication test cases using sed/awk (works without external dependencies)
    # This creates a new XML with only the replication-related test cases
    
    # Count replication tests
    local repl_tests_total=0
    local repl_tests_passed=0
    local repl_tests_failed=0
    local repl_tests_skipped=0
    local total_time="0"
    
    # Create temporary file for replication test cases
    local temp_testcases=$(mktemp)
    
    # Extract testcases that contain replication-related keywords in the name attribute
    # This captures:
    # 1. Tests with "csi-replication" in name
    # 2. Tests with "EnableVolumeReplication" in name  
    # 3. Tests with "GetVolumeReplicationInfo" in name
    # 4. Tests with "VolumeReplication" in name
    # 5. Tests with "replication" keyword and the specific driver
    sed -n '/<testcase.*name="[^"]*\(csi-replication\|EnableVolumeReplication\|GetVolumeReplicationInfo\|VolumeReplication\|replication.*'"${driver_name//./\\.}"'\|'"${driver_name//./\\.}"'.*replication\)"[^>]*>/,/<\/testcase>/p' "${full_junit_file}" > "${temp_testcases}"
    
    # Count different test states and calculate totals
    repl_tests_total=$(grep -c '<testcase' "${temp_testcases}" 2>/dev/null || echo "0")
    repl_tests_passed=$(grep -c 'status="passed"' "${temp_testcases}" 2>/dev/null || echo "0")
    repl_tests_failed=$(grep -c 'status="failed"' "${temp_testcases}" 2>/dev/null || echo "0")
    repl_tests_skipped=$(grep -c 'status="skipped"' "${temp_testcases}" 2>/dev/null || echo "0")
    
    # Extract total time from original file
    total_time=$(grep '<testsuites' "${full_junit_file}" | sed -n 's/.*time="\([^"]*\)".*/\1/p' || echo "0")
    
    # Create focused JUnit XML
    cat > "${focused_junit_file}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="${repl_tests_total}" disabled="0" errors="0" failures="${repl_tests_failed}" time="${total_time}">
    <testsuite name="CSI Replication Test Suite" package="csi-replication" tests="${repl_tests_total}" disabled="0" skipped="${repl_tests_skipped}" errors="0" failures="${repl_tests_failed}" time="${total_time}" timestamp="$(date -Iseconds)">
        <properties>
            <property name="driver" value="${driver_name}"/>
            <property name="test-execution-date" value="$(date +%Y-%m-%d)"/>
            <property name="focused-report" value="true"/>
            <property name="original-total-tests" value="$(grep '<testsuites' "${full_junit_file}" | sed -n 's/.*tests="\([^"]*\)".*/\1/p')"/>
        </properties>
EOF
    
    # Add the extracted test cases
    cat "${temp_testcases}" >> "${focused_junit_file}"
    
    # Close the XML
    cat >> "${focused_junit_file}" << EOF
    </testsuite>
</testsuites>
EOF
    
    # Clean up temp file
    rm -f "${temp_testcases}"
    
    echo "✓ Focused JUnit report created: ${focused_junit_file}"
    echo "  → Replication tests: ${repl_tests_total} total, ${repl_tests_passed} passed, ${repl_tests_failed} failed, ${repl_tests_skipped} skipped"
    
    return 0
}

# Create symlink to latest log
LATEST_LOG="${LOGS_DIR}/latest.log"
ln -sf "$(basename "${LOG_FILE}")" "${LATEST_LOG}"
echo "Latest log: ${LATEST_LOG}"

# Show report files if generated
if [[ "${GENERATE_REPORTS}" == "true" ]]; then
    echo ""
    echo "=========================================="
    echo "Test Reports Generated"
    echo "=========================================="
    echo "Report Directory: ${REPORT_DIR_ABS}"
    
    # List generated report files
    if [[ -f "${REPORT_DIR_ABS}/${REPORT_PREFIX}-junit.xml" ]]; then
        local original_junit="${REPORT_DIR_ABS}/${REPORT_PREFIX}-junit.xml"
        
        # Create focused JUnit report if enabled
        if [[ "${FOCUSED_REPORTS}" == "true" ]]; then
            local focused_junit="${REPORT_DIR_ABS}/${REPORT_PREFIX}-focused-junit.xml"
            
            # Create focused report
            if create_focused_junit_report "${original_junit}" "${focused_junit}" "${DRIVER_NAME}"; then
                echo "✓ Focused JUnit Report: ${focused_junit}"
                
                # Create symlink to latest focused JUnit report
                LATEST_JUNIT="${REPORTS_DIR}/latest-junit.xml"
                ln -sf "$(basename "${focused_junit}")" "${LATEST_JUNIT}"
                echo "  → Latest: ${LATEST_JUNIT}"
                
                # Handle full report based on KEEP_FULL_REPORT setting
                if [[ "${KEEP_FULL_REPORT}" == "true" ]]; then
                    # Rename original to indicate it's the full report
                    local full_junit="${REPORT_DIR_ABS}/${REPORT_PREFIX}-full-junit.xml"
                    mv "${original_junit}" "${full_junit}"
                    echo "✓ Full JUnit Report: ${full_junit}"
                else
                    # Replace original with focused report
                    mv "${focused_junit}" "${original_junit}"
                    echo "✓ JUnit Report (focused): ${original_junit}"
                    # Create symlink to latest JUnit report
                    LATEST_JUNIT="${REPORTS_DIR}/latest-junit.xml"
                    ln -sf "$(basename "${original_junit}")" "${LATEST_JUNIT}"
                    echo "  → Latest: ${LATEST_JUNIT}"
                fi
            else
                echo "⚠ Failed to create focused report, keeping original"
                echo "✓ JUnit Report: ${original_junit}"
                # Create symlink to latest JUnit report
                LATEST_JUNIT="${REPORTS_DIR}/latest-junit.xml"
                ln -sf "$(basename "${original_junit}")" "${LATEST_JUNIT}"
                echo "  → Latest: ${LATEST_JUNIT}"
            fi
        else
            echo "✓ JUnit Report: ${original_junit}"
            # Create symlink to latest JUnit report
            LATEST_JUNIT="${REPORTS_DIR}/latest-junit.xml"
            ln -sf "$(basename "${original_junit}")" "${LATEST_JUNIT}"
            echo "  → Latest: ${LATEST_JUNIT}"
        fi
    fi
    
    if [[ -f "${REPORT_DIR_ABS}/${REPORT_PREFIX}-report.json" ]]; then
        echo "✓ JSON Report: ${REPORT_DIR_ABS}/${REPORT_PREFIX}-report.json"
        # Create symlink to latest JSON report
        LATEST_JSON="${REPORTS_DIR}/latest-report.json"
        ln -sf "$(basename "${REPORT_DIR_ABS}/${REPORT_PREFIX}-report.json")" "${LATEST_JSON}"
        echo "  → Latest: ${LATEST_JSON}"
    fi
    
    # Check for e2e framework reports
    if [[ -f "${REPORT_DIR_ABS}/junit_${REPORT_PREFIX}01.xml" ]]; then
        echo "✓ E2E Framework JUnit: ${REPORT_DIR_ABS}/junit_${REPORT_PREFIX}01.xml"
    fi
    
    if [[ -d "${REPORT_DIR_ABS}/ginkgo" ]]; then
        echo "✓ Ginkgo Reports Directory: ${REPORT_DIR_ABS}/ginkgo"
        if [[ -f "${REPORT_DIR_ABS}/ginkgo/report.json" ]]; then
            echo "  → JSON: ${REPORT_DIR_ABS}/ginkgo/report.json"
        fi
        if [[ -f "${REPORT_DIR_ABS}/ginkgo/report.xml" ]]; then
            echo "  → XML: ${REPORT_DIR_ABS}/ginkgo/report.xml"
        fi
    fi
    
    echo ""
    echo "To view reports:"
    echo "  - JUnit XML: Can be viewed in CI/CD tools (Jenkins, GitLab CI, etc.)"
    echo "  - JSON: Use 'jq' or other JSON tools to parse"
    echo "  - Example: jq '.SpecReports[] | select(.State == \"failed\")' ${REPORT_DIR_ABS}/${REPORT_PREFIX}-report.json"
fi

# Show log file location
echo ""
if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo "✓ Tests completed successfully!"
else
    echo "✗ Tests failed. Check log file for details: ${LOG_FILE}"
    if [[ "${GENERATE_REPORTS}" == "true" ]]; then
        echo "  Check reports in: ${REPORT_DIR_ABS}"
    fi
fi

exit ${EXIT_CODE}
