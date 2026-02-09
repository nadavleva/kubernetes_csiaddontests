# CSI Replication Test Suite - Build and Test Guide

This guide explains how to build, lint, and run the CSI replication test suite using the provided make targets.

## Overview

The CSI replication test suite provides comprehensive testing for CSI replication functionality including:

- **Main Tests**: Real CSI driver certification tests for `EnableVolumeReplication` and `GetVolumeReplicationInfo`
- **Mock Tests**: Protocol validation and development tests using mock CSI driver
- **Framework Integration**: Seamless integration with Kubernetes storage test framework

## Quick Start

### Prerequisites

- Go 1.25+ installed (automatically managed by Kubernetes build system)
- `kubectl` configured for your Kubernetes cluster (for full e2e tests)
- CSI driver deployed (for main tests only)

### Build and Validate Everything

```bash
# Complete build, lint, and test validation
make replication-all
```

### Quick Development Validation

```bash
# Build only
make replication-build

# Lint only  
make replication-lint

# Test compilation validation
make replication-test
```

## Make Targets Reference

### Build Targets

#### `make replication-build`
Compiles all replication test components and validates integration.

```bash
# Basic build
make replication-build

# Build with verbose Go output
make replication-build GOFLAGS=-v
```

**Output**: Validates that main tests, mock tests, and framework changes compile successfully.

### Linting Targets

#### `make replication-lint` 
Runs `go vet` on replication test packages to validate code quality.

```bash
make replication-lint
```

**Output**: Reports any code quality issues in replication test files.

### Test Targets

#### `make replication-test`
Validates that the test suite compiles and provides guidance for running actual tests.

```bash
# Basic validation
make replication-test

# With verbose output during build phase
make replication-test VERBOSE=1
```

**What it does:**
- Validates main replication test suite compilation
- Validates mock replication test suite compilation  
- Validates framework integration
- Provides commands for running actual tests

#### `make replication-test-main`
Provides guidance and examples for running main CSI driver certification tests.

```bash
make replication-test-main
```

**Output:**
- Prerequisites checklist
- Example commands for e2e test execution
- Integration instructions

#### `make replication-test-mock`
Attempts to run mock CSI driver tests and provides execution guidance.

```bash
# Basic mock test execution
make replication-test-mock

# With verbose output
make replication-test-mock VERBOSE=1
```

**What it does:**
- Runs `go test` on csimock package with standalone unit tests
- Shows actual command syntax for cluster-based and standalone execution
- Provides development workflow guidance

#### `make replication-all`
Comprehensive target that builds, lints, and validates everything.

```bash
make replication-all
```

**Complete pipeline:**
1. **Build**: Compiles all components
2. **Lint**: Validates code quality  
3. **Test**: Runs mock test validation
4. **Report**: Shows success summary

## Running Actual Tests

The make targets provide **build validation and guidance**. To run actual tests:

### Mock Tests (Development & CI)

**Option 1: Standalone Unit Tests (No Cluster Required)**
```bash
# Run standalone mock tests (fastest for development)
go test -v ./test/e2e/storage/csimock -run TestCSIReplication

# Run with verbose Go test output
go test -v ./test/e2e/storage/csimock -run TestCSIReplication -args -test.v

# Run specific test pattern
go test -v ./test/e2e/storage/csimock -run TestCSIReplication.*SnapshotMode
```

**Option 2: E2E Framework Tests (Requires Cluster)**
```bash
# List available tests (dry run)
go test -v ./test/e2e --ginkgo.focus="CSI replication" --ginkgo.dry-run

# Run CSI mock replication tests (requires cluster)
go test -v ./test/e2e --ginkgo.focus="CSI replication"

# Focus on specific functionality
go test -v ./test/e2e --ginkgo.focus="EnableVolumeReplication.*snapshot mode"
```

### Main Tests (Driver Certification)

```bash
# Focus on all replication tests across all drivers
go test -v ./test/e2e --ginkgo.focus="EnableVolumeReplication"

# Focus on specific test patterns
go test -v ./test/e2e --ginkgo.focus="csi-replication.*journal mode"

# Focus on specific driver
go test -v ./test/e2e --ginkgo.focus="CSI Volumes.*csi-hostpath.*EnableVolumeReplication"
```

**Prerequisites for actual test execution:**
- Running Kubernetes cluster with kubectl configured
- CSI drivers deployed and configured (for main tests)
- Proper e2e test environment setup

## Test Focus Patterns

Use these patterns with the actual test commands:

### Available Test Suites

**CSI Mock Tests** (protocol validation):
- `"CSI replication"` - All CSI mock replication tests
- `"EnableVolumeReplication.*snapshot mode parameters"` - Snapshot mode validation
- `"EnableVolumeReplication.*journal mode parameters"` - Journal mode validation

**Storage Framework Tests** (driver certification):
- `"EnableVolumeReplication"` - All EnableVolumeReplication tests across drivers
- `"csi-replication.*snapshot mode"` - Snapshot mode tests
- `"csi-replication.*journal mode"` - Journal mode tests  
- `"idempotent replication"` - Idempotency tests

### Driver-Specific Focus

Target specific drivers:
```bash
# CSI Hostpath driver tests
go test -v ./test/e2e --ginkgo.focus="csi-hostpath.*EnableVolumeReplication"

# Google PD CSI driver tests  
go test -v ./test/e2e --ginkgo.focus="pd.csi.storage.gke.io.*EnableVolumeReplication"
```

### Test Pattern Focus

Target specific test patterns:
```bash
# Block volume mode tests
go test -v ./test/e2e --ginkgo.focus="block volmode.*EnableVolumeReplication"

# Default filesystem tests
go test -v ./test/e2e --ginkgo.focus="default fs.*EnableVolumeReplication"

# Ext4 filesystem tests
go test -v ./test/e2e --ginkgo.focus="ext4.*EnableVolumeReplication"
```

## Driver Configuration

For main tests, you'll need a driver configuration. See `examples/csi-replication-driver.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-replication-test-sc
  annotations:
    replication.storage.openshift.io/replication-enabled: "true"
provisioner: your-csi-driver.example.com
parameters:
  replication.storage.openshift.io/replication-mode: "snapshot"
  replication.storage.openshift.io/remote-cluster: "remote-cluster-1"
volumeBindingMode: Immediate
```

## CI/CD Integration

### Basic Validation Pipeline
```bash
# Validate build and code quality
make replication-build
make replication-lint

# Run mock tests for protocol validation  
go test -v ./test/e2e/storage/csimock -ginkgo.focus="CSI replication"
```

### Complete Validation
```bash
# Single command for full validation
make replication-all
```

### Integration with Existing CI
Add to your CI pipeline:

```yaml
# Example GitHub Actions step
- name: Validate CSI Replication Tests
  run: make replication-all
```

## Development Workflow

1. **Make Changes**: Edit replication test files
2. **Build**: `make replication-build`
3. **Lint**: `make replication-lint` 
4. **Quick Validation**: `make replication-test`
5. **Test Protocol**: `make replication-test-mock`

For rapid iteration:
```bash
# Quick feedback loop
make replication-build && make replication-test-mock VERBOSE=1
```

## Troubleshooting

### Build Issues
```bash
# Clean and rebuild
make clean
make replication-build
```

### Lint Issues
```bash
# Run lint with verbose output
make replication-lint VERBOSE=1
```

### Test Execution Issues

**For standalone mock tests (no cluster):**
```bash
# Direct execution with full output
go test -v ./test/e2e/storage/csimock -run TestCSIReplication -args -test.v

# Check available tests
go test ./test/e2e/storage/csimock -list TestCSI
```

**For e2e framework mock tests (requires cluster):**
```bash
# Direct execution with full output
go test -v ./test/e2e --ginkgo.focus="CSI replication" --ginkgo.vv
```

**For main tests:**
- Verify cluster connectivity: `kubectl cluster-info`
- Check CSI driver: `kubectl get csidriver`
- Review e2e framework setup

### Common Issues

1. **"KUBERNETES_SERVICE_HOST must be defined" error**: 
   - For e2e tests: Set up kubeconfig with `export KUBECONFIG=~/.kube/config`
   - For standalone tests: Use `go test ./test/e2e/storage/csimock -run TestCSI`

2. **"No test files" or "Unable to find in-cluster config"**: 
   - Use standalone unit tests for development: `go test -v ./test/e2e/storage/csimock`
   - E2E tests require a running Kubernetes cluster

3. **Go version issues**: The build system automatically downloads the correct Go version (1.25.x) as needed.

4. **Missing ginkgo**: The build system creates ginkgo at `_output/local/bin/linux/amd64/ginkgo`.

## Summary

The make targets provide:
- **Compilation validation**: Ensures all components build correctly
- **Code quality**: Lints replication test code
- **Integration testing**: Validates framework integration
- **Documentation**: Clear guidance for running actual tests
- **CI/CD ready**: Simple targets for automation pipelines

Use `make replication-all` for comprehensive validation, then follow the provided guidance for running actual tests in your environment.

## Quick Commands Reference

**Mock Tests (No Cluster Required):**
```bash
# Standalone unit tests with verbose output
go test -v ./test/e2e/storage/csimock -run TestCSIReplication

# Parameter validation tests  
go test -v ./test/e2e/storage/csimock -run TestReplication

# Performance benchmarks
go test -v ./test/e2e/storage/csimock -bench=BenchmarkCSI -run=^$
```

**E2E Tests (Requires Cluster):**
```bash
# List available e2e tests
go test -v ./test/e2e --ginkgo.focus="CSI replication" --ginkgo.dry-run

# Run e2e mock tests with maximum verbosity
go test -v ./test/e2e --ginkgo.focus="CSI replication" --ginkgo.vv
```