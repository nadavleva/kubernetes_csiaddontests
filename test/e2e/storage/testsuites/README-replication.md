# CSI Replication Test Suite

This directory contains the CSI replication test suite for validating CSI driver replication functionality.

## Quick Reference

### Build & Validate

```bash
# Build everything
make replication-build

# Validate code quality  
make replication-lint

# Full validation pipeline
make replication-all
```

### Help & Guidance

```bash
# See complete usage guide
make replication-test PRINT_HELP=y

# Main test guidance
make replication-test-main

# Mock test execution
make replication-test-mock
```

## Files Overview

- `replication.go` - Main CSI replication test suite (EnableVolumeReplication, GetVolumeReplicationInfo)
- `replication_mock.go` - Mock CSI driver tests for protocol validation
- `replication_framework.go` - Storage framework integration
- `README-replication.md` - This file

## Documentation

See [docs/replication-testing-guide.md](../../../docs/replication-testing-guide.md) for complete build, test, and usage documentation.

## Integration

The replication test suite integrates with the existing Kubernetes storage test framework in `pkg/volume/util/storageclass.go`.

The tests follow the standard Kubernetes e2e test patterns and can be executed as part of the broader e2e test suite.

## Go Version Requirement

This project uses **Go 1.25.0+** as specified by the Kubernetes project requirements. The build system automatically manages the Go toolchain - you don't need to manually install Go 1.25.6. When you run any make command, it will:

1. Download the correct Go version to `_output/local/go/`
2. Use that specific version for all builds and tests
3. Ensure consistency across all developers and CI systems

The specific Go version requirement comes from:
- Kubernetes core requirements for e2e test framework
- Compatibility with the CSI spec implementation
- Integration with the existing test infrastructure

## Architecture

### Test Registration System

The CSI replication test suite uses Kubernetes' **import-based test registration system** rather than traditional Go `*_test.go` file discovery. This architectural pattern is fundamental to how Kubernetes e2e tests work.

#### Registration-Based vs File-Pattern Detection

**Traditional Go Testing (`*_test.go` pattern):**
```go
// example_test.go
package mypackage

import "testing"

func TestSomething(t *testing.T) {
    // test code
}
```
- Tests discovered by Go's built-in test runner
- Files must end with `_test.go`
- Run with `go test ./package`
- Each package tested independently

**Kubernetes E2E Testing (Import-Based Registration):**
```go
// test/e2e/e2e_test.go (main entry point)
package e2e

import (
    // Importing a package registers its tests
    _ "k8s.io/kubernetes/test/e2e/storage/csimock"  // ← Registers our tests
    _ "k8s.io/kubernetes/test/e2e/storage/testsuites"
)

func TestE2E(t *testing.T) {
    RunE2ETests(t) // Runs all registered test suites
}
```

```go
// test/e2e/storage/csimock/csi_replication.go (our tests)
package csimock

import "k8s.io/kubernetes/test/e2e/storage/utils"

// This registers the test suite when the package is imported
var _ = utils.SIGDescribe("CSI replication", func() {
    // Test definitions automatically registered with Ginkgo
})
```

#### Why Kubernetes Uses Registration-Based Testing

1. **Centralized Control**: Single entry point (`test/e2e/e2e_test.go`) manages thousands of tests
2. **Selective Execution**: Can focus on specific test categories with `--ginkgo.focus`
3. **Shared Infrastructure**: Common setup/teardown, configuration, and cluster management
4. **Build Flexibility**: Can create different test binaries with different test combinations
5. **Category Organization**: Tests organized by sig-storage, sig-apps, etc.

#### Test Discovery Flow

```
1. go test ./test/e2e --ginkgo.focus="CSI replication"
   ↓
2. e2e_test.go imports csimock package
   ↓
3. csimock package initialization runs
   ↓  
4. var _ = utils.SIGDescribe(...) executes
   ↓
5. utils.SIGDescribe registers tests with Ginkgo's global registry
   ↓
6. TestE2E() calls RunE2ETests()
   ↓
7. Ginkgo finds all registered tests matching focus pattern
   ↓
8. Tests execute with shared e2e framework infrastructure
```

#### Practical Implications

**Why our tests are in `.go` files (not `_test.go`):**
- They're not standalone Go tests, they're registrations for the e2e framework
- Run through: `go test ./test/e2e --ginkgo.focus="pattern"`
- Not through: `go test ./test/e2e/storage/csimock` (would find no tests)

**Test File Structure:**
```
test/e2e/storage/
├── csimock/
│   ├── csi_replication.go       ← Registers mock tests
│   ├── csi_snapshot.go         ← Other CSI mock tests  
│   └── base.go                 ← Common mock setup
├── testsuites/
│   ├── replication.go          ← Registers main certification tests
│   ├── snapshots.go            ← Other test suites
│   └── volumes.go              ← Volume test suites
└── utils/
    └── utils.go                ← Contains SIGDescribe() registration func
```

### Test Suite Architecture

```
CSI Replication Test Suite
├── Registration Layer
│   ├── Import-based test discovery
│   ├── utils.SIGDescribe() registration
│   └── Ginkgo global test registry
├── Main Tests (certification)
│   ├── EnableVolumeReplication
│   │   ├── Snapshot mode validation
│   │   ├── Journal mode validation  
│   │   └── Error handling
│   └── GetVolumeReplicationInfo
│       ├── Status queries
│       ├── Progress tracking
│       └── Metadata validation
├── Mock Tests (development)  
│   ├── gRPC protocol validation
│   ├── Parameter validation
│   └── Error response testing
└── Framework Integration
    ├── Storage class handling
    ├── Volume lifecycle
    └── Cleanup procedures
```

### Test Execution Patterns

**Discovery and Execution:**
```bash
# List all replication tests (registration-based discovery)
go test -v ./test/e2e --ginkgo.focus="replication" --ginkgo.dry-run

# Run CSI mock tests (5 tests discovered via registration)
go test -v ./test/e2e --ginkgo.focus="CSI replication"

# Run storage framework tests (20 tests discovered via registration)  
go test -v ./test/e2e --ginkgo.focus="EnableVolumeReplication"
```

**Why Traditional Go Test Discovery Fails:**
```bash
# This would fail - no *_test.go files found
go test -v ./test/e2e/storage/csimock
# Output: testing: warning: no tests to run
```

## Status

✅ **Complete**: Build, lint, and validation infrastructure  
✅ **Complete**: Mock test execution guidance  
✅ **Complete**: Main test compilation validation  
✅ **Complete**: Documentation and examples  
📋 **Ready**: For integration with CSI driver certification workflows