# Kubernetes Storage E2E Test Framework

This document describes the architecture, test suites, and usage of the Kubernetes storage end-to-end (e2e) test framework.

## Table of Contents

1. [Test Suites Overview](#test-suites-overview)
2. [Architecture](#architecture)
3. [Test Options and Capabilities](#test-options-and-capabilities)
4. [Disruptive Tests](#disruptive-tests)

---

## Test Suites Overview

The storage test framework organizes tests into **test suites**, each focusing on specific storage functionality. Test suites are defined in `test/e2e/storage/testsuites/`.

### BaseSuites

These test suites work for both in-tree volume plugins and CSI drivers:

1. **CapacityTestSuite** (`capacity.go`)
   - Validates storage capacity information published by drivers
   - Tests capacity-based scheduling

2. **VolumesTestSuite** (`volumes.go`)
   - Basic volume operations (create, attach, mount, unmount, detach, delete)
   - Volume lifecycle management

3. **VolumeIOTestSuite** (`volume_io.go`)
   - I/O operations on volumes
   - Read/write operations, data persistence

4. **VolumeModeTestSuite** (`volumemode.go`)
   - Filesystem vs Block volume mode support
   - Tests both PersistentVolumeFilesystem and PersistentVolumeBlock modes

5. **SubPathTestSuite** (`subpath.go`)
   - Subpath mounting functionality
   - Multiple subpaths in a single volume

6. **ProvisioningTestSuite** (`provisioning.go`)
   - Dynamic volume provisioning
   - StorageClass-based provisioning
   - PVC creation and binding

7. **MultiVolumeTestSuite** (`multivolume.go`)
   - Multiple volumes per pod
   - Volume interaction and isolation

8. **VolumeExpandTestSuite** (`volume_expand.go`)
   - Online and offline volume expansion
   - Controller and node expansion capabilities

9. **DisruptiveTestSuite** (`disruptive.go`)
   - Kubelet restart scenarios
   - Pod deletion during kubelet downtime
   - See [Disruptive Tests](#disruptive-tests) section for details

10. **VolumeLimitsTestSuite** (`volumelimits.go`)
    - Volume limits per node
    - Maximum volumes per node validation

11. **TopologyTestSuite** (`topology.go`)
    - Topology-aware volume scheduling
    - Zone/region constraints

12. **VolumeStressTestSuite** (`volume_stress.go`)
    - Stress testing with multiple pods and volumes
    - Volume lifecycle under load

13. **FsGroupChangePolicyTestSuite** (`fsgroupchangepolicy.go`)
    - FSGroup change policies (OnRootMismatch)
    - Volume ownership management

14. **VolumeGroupSnapshottableTestSuite** (`volume_group_snapshottable.go`)
    - Volume group snapshot functionality
    - Multiple volume snapshots in a group

15. **CustomEphemeralTestSuite** (`ephemeral.go`)
    - Generic ephemeral volumes
    - Inline ephemeral volume support

### CSISuites

These test suites are **CSI-specific** and include all BaseSuites plus:

1. **SnapshottableTestSuite** (`snapshottable.go`)
   - Volume snapshot creation and restoration
   - Snapshot data source for PVCs

2. **SnapshottableStressTestSuite** (`snapshottable_stress.go`)
   - Stress testing snapshot operations
   - Multiple snapshots per volume

3. **VolumePerformanceTestSuite** (`volumeperf.go`)
   - Performance metrics for volume operations
   - Provisioning latency and throughput

4. **PvcDeletionPerformanceTestSuite** (`pvcdeletionperf.go`)
   - PVC deletion performance
   - Cleanup operation metrics

5. **ReadWriteOncePodTestSuite** (`readwriteoncepod.go`)
   - ReadWriteOncePod access mode
   - Single pod access enforcement

6. **VolumeModifyTestSuite** (`volume_modify.go`)
   - Volume modification via VolumeAttributesClass
   - Runtime volume attribute changes

7. **VolumeModifyStressTestSuite** (`volume_modify_stress.go`)
   - Stress testing volume modifications
   - Multiple concurrent modifications

8. **SELinuxMountTestSuite** (`selinuxmount.go`)
   - SELinux mount options
   - Security context handling

---

## Architecture

### Test Execution Flow

The storage test framework follows this execution flow:

```
Test Registration → Driver Preparation → Test Pattern Matching → Test Execution
```

1. **Test Registration**: Test suites are registered via `DefineTestSuites()` which creates Ginkgo test contexts for each driver and test pattern combination.

2. **Driver Preparation**: Before each test, `driver.PrepareTest()` is called to:
   - Set up test-specific configuration
   - Create namespaces
   - Configure node selection
   - Initialize framework resources

3. **Test Pattern Matching**: The framework validates that:
   - The driver supports the test pattern's volume type (DynamicPV, PreprovisionedPV, etc.)
   - The driver supports the filesystem type
   - The driver has required capabilities

4. **Test Execution**: Tests run using the Kubernetes API and interact with the storage driver indirectly through Kubernetes resources.

### Test Interaction Model

**Important**: Storage tests **do NOT directly contact the CSI driver via gRPC**. Instead, they interact with:

1. **Kubernetes API Server**:
   - Create/delete PVCs, PVs, StorageClasses
   - Create/delete Pods
   - Query VolumeAttachments
   - Monitor resource status

2. **Kubelet** (via SSH for disruptive tests):
   - Restart kubelet
   - Check kubelet status
   - Verify mount points

3. **Storage Driver** (indirectly):
   - Tests assume the driver is pre-installed in the cluster
   - Driver operations are triggered through Kubernetes API calls
   - Tests validate driver behavior by observing Kubernetes resource states

### gRPC API vs Custom Resource (CR) Creation Flow

**Critical Understanding**: Tests **never directly call gRPC APIs** on the CSI driver. All interactions follow this flow:

```
Test Code → Kubernetes API (CRs) → Kubernetes Components → gRPC → CSI Driver
```

#### Detailed Flow

1. **Test Creates Kubernetes Resources (CRs)**:
   - Tests use Kubernetes API client (`clientset.Interface`) to create:
     - `PersistentVolumeClaim` (PVC) objects
     - `StorageClass` objects
     - `Pod` objects with volume references
     - `VolumeSnapshot` objects (for snapshot tests)
   - Example: `cs.CoreV1().PersistentVolumeClaims(ns).Create(ctx, pvc, metav1.CreateOptions{})`

2. **Kubernetes Components Make gRPC Calls**:
   - When a PVC is created, Kubernetes components automatically trigger:
     - **external-provisioner**: Calls `CreateVolume` gRPC to provision storage
     - **external-attacher**: Calls `ControllerPublishVolume` gRPC to attach volume
     - **kubelet**: Calls `NodeStageVolume` and `NodePublishVolume` gRPC to mount volume
   - These gRPC calls happen **automatically** as part of Kubernetes' normal operation
   - Tests have **no direct control** over when or how these gRPC calls are made

3. **CSI Driver Receives gRPC Calls**:
   - The CSI driver (pre-installed in cluster) receives gRPC calls from Kubernetes components
   - For mock driver tests, gRPC calls are intercepted and logged
   - Mock driver logs gRPC calls with prefix `gRPCCall:` for test verification

4. **Test Verification**:
   - Tests verify behavior by checking:
     - **Kubernetes resource states**: PVC status, Pod status, VolumeAttachment status
     - **gRPC call logs** (mock driver only): Tests can call `GetCalls()` to retrieve logged gRPC calls
     - **Pod file system**: Verify data persistence, I/O operations

#### Example: Volume Provisioning Flow

```go
// Test code (in testsuites/provisioning.go)
// 1. Test creates StorageClass via Kubernetes API
sc, err := cs.StorageV1().StorageClasses().Create(ctx, storageClass, metav1.CreateOptions{})

// 2. Test creates PVC via Kubernetes API
pvc, err := cs.CoreV1().PersistentVolumeClaims(ns).Create(ctx, pvc, metav1.CreateOptions{})

// 3. Kubernetes external-provisioner automatically:
//    - Watches for new PVC
//    - Calls driver.CreateVolume() via gRPC
//    - Creates PV and binds to PVC

// 4. Test verifies by checking Kubernetes resource state
err = e2epv.WaitForPersistentVolumeClaimPhase(
    v1.ClaimBound, cs, pvc.Namespace, pvc.Name, framework.Poll, timeouts.ClaimProvision)
```

#### Mock Driver gRPC Observation

For tests using the mock CSI driver (`csimock` package):

- Mock driver intercepts gRPC calls via `interceptGRPC()` function
- All gRPC calls are logged with JSON format: `gRPCCall: {"Method":"CreateVolume",...}`
- Tests can retrieve logged calls: `driver.GetCalls(ctx)` returns `[]MockCSICall`
- Tests verify gRPC call sequences, parameters, and responses
- **Note**: This is observation only - tests still don't make direct gRPC calls

#### No VolumeReplication CRD Usage

The storage test framework **does not create or interact with VolumeReplication CRDs**. Tests only work with standard Kubernetes storage resources:
- `PersistentVolumeClaim`
- `PersistentVolume`
- `StorageClass`
- `VolumeSnapshot` (CSI snapshot API)
- `VolumeGroupSnapshot` (CSI group snapshot API)

If your CSI driver uses VolumeReplication CRDs for replication features, those would be managed by your driver's controller, not by the test framework.

### Test Driver Interfaces

The framework defines several driver interfaces:

- **TestDriver**: Base interface with `GetDriverInfo()` and `PrepareTest()`
- **DynamicPVTestDriver**: For drivers supporting dynamic provisioning
- **PreprovisionedPVTestDriver**: For drivers with pre-provisioned volumes
- **SnapshottableTestDriver**: For drivers supporting snapshots
- **EphemeralTestDriver**: For drivers supporting ephemeral inline volumes
- **VolumeAttributesClassTestDriver**: For drivers supporting volume modification

### External vs In-Tree Tests

#### External Storage Tests (CSI Drivers)

- Defined via `--storage.testdriver` flag pointing to a YAML/JSON file
- Driver definition file specifies capabilities, StorageClass, SnapshotClass
- Tests run against a **pre-installed** driver in the cluster
- No pre-flight driver availability check

#### In-Tree Volume Tests

- Hardcoded driver list in `in_tree_volumes.go`
- Enabled via `--enabled-volume-drivers` flag
- Examples: GCE PD, AWS EBS, Azure Disk

---

## Test Options and Capabilities

### Command Line Options

#### External Storage Tests

```bash
--storage.testdriver=<file>
```
- **Purpose**: Load driver definition from YAML/JSON file
- **Can be used multiple times**: Yes (for multiple drivers)
- **File location**: Absolute or relative to `--repo-root`
- **Example**: `--storage.testdriver=/path/to/driver.yaml`

#### In-Tree Volume Tests

```bash
--enabled-volume-drivers=<driver1>,<driver2>
```
- **Purpose**: Enable specific in-tree volume drivers
- **Examples**: `gcepd`, `aws`
- **Legacy**: `ENABLE_STORAGE_GCE_PD_DRIVER=yes` (deprecated)

#### Migration Testing

```bash
--storage.migratedPlugins=<plugin1>,<plugin2>
```
- **Purpose**: Specify in-tree plugins migrated to CSI
- **Format**: `kubernetes.io/{pluginName}`
- **Usage**: Validates that migrated plugins use CSI metrics instead of in-tree

### Driver Capabilities

Drivers declare capabilities in their `DriverInfo` structure. These capabilities determine which tests run:

#### Core Capabilities

- **`persistence`**: Data persists across pod restarts
- **`block`**: Supports raw block volumes
- **`fsGroup`**: Supports volume ownership via fsGroup
- **`volumeMountGroup`**: Has VolumeMountGroup CSI node capability
- **`exec`**: Supports executing files in the volume
- **`multipods`**: Multiple pods on a node can use the same volume concurrently

#### Access Mode Capabilities

- **`RWX`**: Supports ReadWriteMany access mode
- **`readWriteOncePod`**: Supports ReadWriteOncePod access mode
- **`capReadOnlyMany`**: Supports ReadOnlyMany (ROX) access mode

#### Expansion Capabilities

- **`controllerExpansion`**: Controller supports volume expansion
- **`nodeExpansion`**: Node supports volume expansion
- **`offlineExpansion`**: Supports offline volume expansion (default: true if controllerExpansion)
- **`onlineExpansion`**: Supports online volume expansion (default: true if controllerExpansion)

#### Data Source Capabilities

- **`snapshotDataSource`**: Supports populating data from snapshot
- **`pvcDataSource`**: Supports populating data from PVC
- **`groupSnapshot`**: Supports volume group snapshots

#### Advanced Capabilities

- **`volumeLimits`**: Supports volume limits per node (can be slow)
- **`singleNodeVolume`**: Volume can run on single node (like hostpath)
- **`topology`**: Supports topology-aware scheduling
- **`capacity`**: Publishes storage capacity information
- **`multiplePVsSameID`**: Can handle multiple PVs with same VolumeHandle
- **`seLinuxMount`**: Supports SELinux mount options
- **`FSResizeFromSourceNotSupported`**: Anti-capability - does not support filesystem resizing of PVCs cloned/restored from snapshot

### Test Pattern Selection

Tests are organized by **TestPattern**, which combines:
- **Volume Type**: DynamicPV, PreprovisionedPV, InlineVolume, CSIInlineVolume, GenericEphemeralVolume
- **Volume Mode**: Filesystem or Block
- **Filesystem Type**: ext4, xfs, ntfs, or default
- **Binding Mode**: Immediate or WaitForFirstConsumer (for DynamicPV)

Tests automatically skip if:
- Driver doesn't implement required interface (e.g., DynamicPVTestDriver)
- Driver doesn't support the filesystem type
- Driver doesn't have required capabilities

### Running Specific Tests

#### By Driver

```bash
ginkgo -focus='External.Storage.*<driver-name>'
```

#### By Feature

```bash
ginkgo -focus='\[Feature:VolumeSnapshotDataSource\]'
```

#### Skip Disruptive Tests

```bash
ginkgo -skip='\[Disruptive\]'
```

#### Skip Feature Tests

```bash
ginkgo -skip='\[Feature:'
```

#### Combined Example

```bash
ginkgo -p \
  -focus='External.Storage.*hostpath.csi.k8s.io.*\[Feature:VolumeSnapshotDataSource\]' \
  -skip='\[Disruptive\]' \
  e2e.test \
  -- \
  -storage.testdriver=/tmp/hostpath-testdriver.yaml
```

---

## Disruptive Tests

### Overview

The **DisruptiveTestSuite** (`testsuites/disruptive.go`) contains tests that intentionally disrupt the cluster state to validate recovery and cleanup behavior. These tests are marked with `[Disruptive]` tag and require SSH access to nodes.

### Requirements

- **SSH Key**: Must be present (checked via `SkipUnlessSSHKeyPresent()`)
- **Privileged Pods**: Tests run with `admissionapi.LevelPrivileged`
- **Linux Only**: Tests are marked with `LinuxOnly` label
- **Block Volume Support**: Some tests require driver to support block volumes

### Test Scenarios

#### Single Pod Tests

1. **Kubelet Restart with Persistent Volume**
   - **Test**: `Should test that pv written before kubelet restart is readable after restart.`
   - **What it does**:
     - Creates a pod with a volume
     - Writes data to the volume
     - Restarts kubelet on the node
     - Verifies data is still readable after restart
   - **Supports**: Both filesystem and block volumes

2. **Pod Deletion During Kubelet Downtime**
   - **Test**: `Should test that pv used in a pod that is deleted while the kubelet is down cleans up when the kubelet returns.`
   - **What it does**:
     - Creates a pod with a volume
     - Stops kubelet
     - Deletes the pod (while kubelet is down)
     - Starts kubelet
     - Verifies volume is unmapped/cleaned up
   - **Supports**: Block volumes only (filesystem test covered in subpath suite)

3. **Force Pod Deletion During Kubelet Downtime**
   - **Test**: `Should test that pv used in a pod that is force deleted while the kubelet is down cleans up when the kubelet returns.`
   - **What it does**:
     - Similar to above, but uses force deletion
     - Validates cleanup after force deletion
   - **Supports**: Block volumes only

#### Multiple Pod Tests (ReadWriteOncePod)

These tests require `ReadWriteOncePod` access mode and SELinux feature:

1. **Pod Deletion and Reuse**
   - **Test**: `Should test that pv used in a pod that is deleted while the kubelet is down is usable by a new pod when kubelet returns`
   - **What it does**:
     - Creates pod1 with ReadWriteOncePod volume
     - Stops kubelet
     - Deletes pod1
     - Starts kubelet
     - Creates pod2 with same volume
     - Verifies pod2 can use the volume

2. **Force Pod Deletion and Reuse**
   - **Test**: `Should test that pv used in a pod that is force deleted while the kubelet is down is usable by a new pod when kubelet returns`
   - **What it does**: Same as above with force deletion

3. **SELinux Context Change**
   - **Tests**: 
     - `Should test that pv used in a pod that is deleted while the kubelet is down is usable by a new pod with a different SELinux context when kubelet returns`
     - `Should test that pv used in a pod that is force deleted while the kubelet is down is usable by a new pod with a different SELinux context when kubelet returns`
   - **What it does**:
     - Tests volume reuse with different SELinux contexts
     - Validates SELinux mount option handling

### Test Pattern Support

The disruptive test suite supports:
- `DefaultFsInlineVolume`
- `FsVolModePreprovisionedPV`
- `FsVolModeDynamicPV`
- `BlockVolModePreprovisionedPV`
- `BlockVolModeDynamicPV`

### Implementation Details

#### Kubelet Control

Tests use SSH to control kubelet:
- **Stop**: `systemctl stop kubelet`
- **Start**: `systemctl start kubelet`
- **Restart**: `systemctl restart kubelet`

#### Test Utilities

Key utility functions in `test/e2e/storage/utils/utils.go`:
- `TestKubeletRestartsAndRestoresMount()`: Filesystem volume test
- `TestKubeletRestartsAndRestoresMap()`: Block volume test
- `TestVolumeUnmapsFromDeletedPod()`: Block volume cleanup test
- `TestVolumeUnmapsFromForceDeletedPod()`: Force deletion cleanup test
- `TestVolumeUnmountsFromDeletedPodWithForceOption()`: Multi-pod scenarios

#### Cleanup

All tests use `ginkgo.DeferCleanup()` to ensure:
- Pods are deleted
- Volume resources (PVCs, PVs) are cleaned up
- Errors are aggregated and reported

### Running Disruptive Tests

#### Include Disruptive Tests

```bash
ginkgo -focus='\[Disruptive\]' e2e.test -- -storage.testdriver=driver.yaml
```

#### Exclude Disruptive Tests (Default in CI)

```bash
ginkgo -skip='\[Disruptive\]' e2e.test -- -storage.testdriver=driver.yaml
```

### Limitations

- **No Storage Array Failure Tests**: The disruptive suite does not test storage array failures or network partitions
- **No Driver Direct Interaction**: Tests don't simulate driver unavailability
- **Requires SSH**: All disruptive tests require SSH access to nodes
- **Linux Only**: Windows nodes are not supported

---

## Additional Resources

- [External Storage Test README](./external/README.md) - Detailed guide for external storage tests
- [Test Framework Documentation](./framework/) - Framework implementation details
- [Test Utilities](./utils/) - Helper functions for tests
