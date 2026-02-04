# CSI Replication Test Suite

This document describes the CSI Replication Test Suite, which validates CSI driver compliance with the CSI Replication specification for EnableVolumeReplication and GetVolumeReplicationInfo operations.

## Table of Contents

1. [Overview](#overview)
2. [Test Suite Architecture](#test-suite-architecture)
3. [Test Categories](#test-categories)
4. [Driver Requirements](#driver-requirements)
5. [Configuration Examples](#configuration-examples)
6. [Running Tests](#running-tests)
7. [Certification Usage](#certification-usage)
8. [Mock Driver Testing](#mock-driver-testing)

---

## Overview

The CSI Replication Test Suite validates CSI driver implementations of replication functionality as defined in the [CSI Replication specification](https://github.com/nadavleva/csi_replication_certs/blob/main/docs/layer-1-readme.md). The test suite focuses on:

- **EnableVolumeReplication**: Volume replication enablement with various modes and parameters
- **GetVolumeReplicationInfo**: Replication status and health information retrieval  
- **StorageClass Integration**: Validation of replication parameters in StorageClass configurations
- **Error Handling**: Graceful handling of invalid parameters and non-existent volumes

### Key Features

- **Two Testing Modes**: Support for both real CSI driver testing (certification) and mock driver testing (development)
- **Multiple Replication Modes**: Tests for snapshot mode (periodic) and journal mode (real-time) replication
- **Parameter Validation**: Comprehensive validation of replication-specific parameters
- **Idempotent Operations**: Verification of idempotent behavior for replication operations
- **Error Scenarios**: Testing of error conditions and graceful failure handling

---

## Test Suite Architecture

### Test Execution Flow

The replication test suite follows the standard Kubernetes storage test framework architecture:

```
Test Code → Kubernetes API → CSI Driver Components → gRPC → CSI Driver → Storage Array
```

**Important**: Tests do not directly call CSI gRPC APIs. All interactions happen through Kubernetes resources:
- Tests create PVCs, StorageClasses, and Pods
- Kubernetes components (external-provisioner, kubelet, etc.) make gRPC calls to CSI driver
- Tests validate behavior by observing Kubernetes resource states

### Integration Points

1. **StorageClass Configuration**: Replication parameters defined in StorageClass
2. **PVC Annotations**: Replication mode and scheduling parameters via annotations
3. **Volume Lifecycle**: Standard Kubernetes volume provisioning, attachment, and mounting
4. **Driver Capabilities**: Replication capability declaration in driver configuration

---

## Test Categories

### EnableVolumeReplication Tests

#### 1. Snapshot Mode Replication [L1-E-001]
- **Purpose**: Validate periodic snapshot-based replication
- **Test**: Creates volume with snapshot mode replication enabled
- **Validation**: Verifies volume provisioning and data persistence

#### 2. Journal Mode Replication [L1-E-002] 
- **Purpose**: Validate real-time journal-based replication
- **Test**: Creates volume with journal mode replication via annotations
- **Validation**: Confirms journal mode parameter handling

#### 3. Idempotent Operations [L1-E-005]
- **Purpose**: Verify idempotent behavior of replication enablement
- **Test**: Multiple enable operations on same volume
- **Validation**: Ensures stable volume behavior across operations

### GetVolumeReplicationInfo Tests

#### 1. Healthy Replication Status [L1-INFO-001]
- **Purpose**: Validate replication status reporting for healthy volumes
- **Test**: Creates replicated volume and verifies operational status
- **Validation**: Confirms volume functionality indicates healthy replication

#### 2. Non-Existent Volume Handling [L1-INFO-008]
- **Purpose**: Test graceful handling of queries for non-existent volumes
- **Test**: Attempts to query replication info without existing volumes
- **Validation**: Verifies appropriate error handling

### StorageClass Validation Tests

#### 1. Replication Parameter Support
- **Purpose**: Validate StorageClass supports replication parameters
- **Test**: Verifies StorageClass configuration for replication
- **Validation**: Confirms provisioner supports replication functionality

---

## Driver Requirements

### Required CSI Capabilities

Drivers must declare the following capabilities to run replication tests:

```yaml
Capabilities:
  persistence: true    # Data persistence across pod restarts
  replication: true    # CSI replication support (NEW)
```

### Optional Capabilities

Additional capabilities that enhance replication testing:

```yaml
Capabilities:
  block: true          # Raw block volume support
  controllerExpansion: true  # Volume expansion support
  snapshotDataSource: true   # Snapshot data source support
  topology: true       # Multi-zone replication support
```

### Infrastructure Requirements

#### Multi-Site Configuration
- **Primary Site**: Source storage array with CSI driver
- **Secondary Site**: Target storage array for replication
- **Network Connectivity**: Secure connection between replication sites
- **Cluster Access**: Kubernetes cluster with access to both sites

#### Kubernetes Components
- **CSI Driver**: Deployed with replication add-on support
- **External Components**: external-provisioner, external-attacher, etc.
- **StorageClass**: Configured with replication parameters
- **RBAC**: Appropriate permissions for replication operations

---

## Configuration Examples

### Driver Configuration File

#### Basic Replication Driver
```yaml
# replication-driver.yaml
DriverInfo:
  Name: mycompany.csi.replication.driver
  SupportedSizeRange:
    Min: 1Gi
    Max: 100Ti
  Capabilities:
    persistence: true
    replication: true
    controllerExpansion: true
    topology: true
StorageClass:
  FromExistingClassName: replication-storage-class
```

#### Advanced Multi-Site Configuration
```yaml
# advanced-replication-driver.yaml
DriverInfo:
  Name: enterprise.replication.csi.driver
  SupportedSizeRange:
    Min: 5Gi
    Max: 1Ti
  Capabilities:
    persistence: true
    replication: true
    block: true
    snapshotDataSource: true
    topology: true
    multipods: true
  StressTestOptions:
    NumPods: 5
    NumSnapshots: 3
  Timeouts:
    PodStart: "10m"
    PVBound: "5m"
StorageClass:
  FromFile: "configs/enterprise-replication-sc.yaml"
SnapshotClass:
  FromExistingClassName: replication-snapshot-class
```

### StorageClass Examples

#### Snapshot Mode Replication
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: replication-snapshot-mode
provisioner: mycompany.csi.replication.driver
parameters:
  replicationMode: "snapshot"
  schedulingInterval: "15m"
  schedulingStartTime: "00:00"
  remoteStorageClassName: "remote-storage-class"
  remoteClusterID: "remote-cluster-123"
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

#### Journal Mode Replication
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: replication-journal-mode
provisioner: mycompany.csi.replication.driver
parameters:
  replicationMode: "journal"
  remoteStorageClassName: "remote-journal-storage"
  remoteClusterID: "remote-cluster-456"
  flattenMode: "force"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

## Running Tests

### External Driver Testing (Certification)

#### Prerequisites
1. **Deploy CSI Driver**:
   ```bash
   kubectl apply -f replication-csi-driver.yaml
   kubectl apply -f replication-storage-class.yaml
   ```

2. **Verify Driver Deployment**:
   ```bash
   kubectl get csidrivers
   kubectl get pods -n csi-system
   ```

#### Basic Test Execution
```bash
# Run all replication tests
ginkgo -focus='External.Storage.*mycompany.csi.replication.driver' \
       -skip='\[Disruptive\]' \
       e2e.test \
       -- \
       --storage.testdriver=configs/replication-driver.yaml

# Run only EnableVolumeReplication tests
ginkgo -focus='External.Storage.*mycompany.csi.replication.driver.*EnableVolumeReplication' \
       e2e.test \
       -- \
       --storage.testdriver=configs/replication-driver.yaml

# Run specific test scenario
ginkgo -focus='External.Storage.*mycompany.csi.replication.driver.*\[L1-E-001\]' \
       e2e.test \
       -- \
       --storage.testdriver=configs/replication-driver.yaml
```

#### Certification Test Suite
```bash
# Full CSI certification including replication
ginkgo -focus='External.Storage.*mycompany.csi.replication.driver' \
       -skip='\[Feature:|\[Disruptive\]' \
       e2e.test \
       -- \
       --storage.testdriver=configs/replication-driver.yaml

# Replication-specific certification
ginkgo -focus='External.Storage.*mycompany.csi.replication.driver.*\[Feature:Replication\]' \
       e2e.test \
       -- \
       --storage.testdriver=configs/replication-driver.yaml
```

### Mock Driver Testing (Development)

Mock driver tests focus on gRPC protocol validation and parameter handling:

#### Run Mock Tests
```bash
# CSI mock replication tests
ginkgo -focus='\[sig-storage\] CSI replication' \
       e2e.test

# Specific mock test categories
ginkgo -focus='\[sig-storage\] CSI replication.*EnableVolumeReplication' \
       e2e.test
```

---

## Certification Usage

### CSI Driver Certification Process

The replication test suite is designed for CSI driver certification and compliance validation:

#### 1. Pre-Certification Setup
- Deploy replication-capable CSI driver in test cluster
- Configure multi-site storage infrastructure
- Create appropriate StorageClass and SnapshotClass resources
- Verify network connectivity between replication sites

#### 2. Certification Test Execution
```bash
# Complete certification test run
ginkgo -focus='External.Storage.*driver-name' \
       -skip='\[Disruptive\]|\[Feature:(?!Replication)\]' \
       e2e.test \
       -- \
       --storage.testdriver=/path/to/driver-config.yaml \
       --kubeconfig=/path/to/admin.kubeconfig
```

#### 3. Results Validation
- All EnableVolumeReplication tests must pass
- GetVolumeReplicationInfo tests must pass
- StorageClass validation must pass
- No test skips due to missing capabilities

#### 4. Certification Report
Generate certification report from ginkgo XML output:
```bash
# Generate JUnit XML for certification
ginkgo -focus='External.Storage.*driver-name' \
       --junit-report=certification-results.xml \
       e2e.test \
       -- \
       --storage.testdriver=driver-config.yaml
```

### Compliance Requirements

For CSI replication certification, drivers must:
- ✅ Support `EnableVolumeReplication` gRPC method
- ✅ Support `GetVolumeReplicationInfo` gRPC method  
- ✅ Handle snapshot mode replication parameters
- ✅ Handle journal mode replication parameters
- ✅ Provide idempotent operation behavior
- ✅ Return appropriate error codes for invalid parameters
- ✅ Support standard Kubernetes volume lifecycle with replication

---

## Mock Driver Testing

### Purpose

Mock driver tests validate CSI protocol compliance without requiring real storage infrastructure. These tests focus on:

- gRPC call sequences and parameters
- Error response validation
- Protocol compliance verification
- Development-time validation

### Mock Test Categories

#### 1. gRPC Protocol Validation
- Verifies correct gRPC method calls
- Validates request/response parameters
- Tests error condition handling

#### 2. Parameter Validation
- Tests valid parameter combinations
- Verifies invalid parameter rejection
- Validates parameter parsing

#### 3. Framework Integration
- Tests capability detection
- Validates test suite integration
- Verifies skip logic for unsupported features

### Development Workflow

1. **Implement Replication gRPC Methods** in your CSI driver
2. **Run Mock Tests** to validate protocol compliance
3. **Deploy Driver** in test cluster
4. **Run External Tests** for integration validation
5. **Execute Certification Tests** for compliance verification

### Mock Test Limitations

Mock tests cannot validate:
- Real storage array integration
- Multi-cluster replication functionality
- Network partition handling
- Storage-specific error conditions
- Performance characteristics

---

## Troubleshooting

### Common Issues

#### Test Skips Due to Missing Capabilities
**Problem**: Tests skip with "Driver does not support replication"
**Solution**: Add `replication: true` to driver capabilities in configuration

#### StorageClass Not Found
**Problem**: Tests fail with StorageClass not found errors
**Solution**: Ensure StorageClass exists or use `FromExistingClassName` in driver config

#### Network Connectivity Issues
**Problem**: Replication setup fails due to network issues
**Solution**: Verify connectivity between replication sites and proper firewall configuration

#### Permission Errors
**Problem**: Tests fail with insufficient permissions
**Solution**: Ensure cluster-admin level permissions for test execution

### Debug Commands

```bash
# Check driver deployment
kubectl get csidrivers
kubectl describe csidriver mycompany.csi.replication.driver

# Verify StorageClass
kubectl get storageclass
kubectl describe storageclass replication-storage-class

# Check CSI components
kubectl get pods -n csi-system
kubectl logs -n csi-system -l app=csi-driver

# Test PVC creation manually
kubectl create -f test-replication-pvc.yaml
kubectl describe pvc test-replication-pvc
```

---

## Contributing

When adding new replication test scenarios:

1. Follow existing test patterns in `testsuites/replication.go`
2. Add corresponding mock tests in `csimock/csi_replication.go`
3. Update capability requirements in this README
4. Include test references from the CSI replication specification
5. Add appropriate ginkgo test tags and labels

### Test Naming Convention
- Use specification reference in test descriptions: `[L1-E-001]`
- Include descriptive test names indicating the scenario
- Use appropriate ginkgo Context groupings for organization

---

## References

- [CSI Replication Test Plan](https://github.com/nadavleva/csi_replication_certs/blob/main/docs/layer-1-readme.md)
- [CSI Replication Test Specifications](https://github.com/nadavleva/csi_replication_certs/blob/main/docs/layer-1-vr-tests.md)
- [Kubernetes Storage E2E Test Framework](./README.md)
- [CSI Specification](https://github.com/container-storage-interface/spec)