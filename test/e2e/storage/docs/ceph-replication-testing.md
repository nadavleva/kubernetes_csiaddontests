# Testing CSI Replication with Ceph Storage

This document describes how to run the CSI replication test suite against a Ceph storage cluster using the Kubernetes storage e2e test framework.

## Overview

The CSI replication test suite validates CSI driver implementations of replication functionality. When testing against Ceph storage, the tests verify that volumes can be replicated using either snapshot-based or journal-based replication modes.

## Prerequisites

1. **Kubernetes cluster** (e.g., minikube with 3 nodes)
2. **Ceph CSI driver deployed** with replication add-on support
3. **StorageClass configured** for Ceph volumes with replication parameters
4. **kubectl configured** to access your cluster
5. **Test framework built** (`make ginkgo`)

## Driver Configuration

### Step 1: Identify Your Ceph CSI Driver

Determine your Ceph CSI driver name and StorageClass:

```bash
# List available CSI drivers
kubectl get csidrivers

# List available StorageClasses
kubectl get storageclass
```

Common Ceph CSI driver names:
- `rbd.csi.ceph.com` (for RBD block volumes)
- `cephfs.csi.ceph.com` (for CephFS file volumes)

### Step 2: Create Driver Configuration File

Create a driver configuration file that describes your Ceph setup to the test framework. Example:

```yaml
DriverInfo:
  Name: rbd.csi.ceph.com
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
  FromExistingClassName: csi-rbd-sc
```

Save this as `my-ceph-driver.yaml`. The test framework uses this configuration to:
- Identify which CSI driver to test
- Determine which capabilities are available
- Select the appropriate StorageClass for provisioning

### Step 3: Verify StorageClass Configuration

Ensure your StorageClass supports replication. The StorageClass should exist in your cluster:

```bash
kubectl get storageclass <your-storage-class-name> -o yaml
```

If you need to create a StorageClass with replication support, see the example in `configs/ceph-replication-sc.yaml`.

## Running Tests

### Basic Test Execution

Run all replication tests against your Ceph driver:

```bash
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*\[Feature:Replication\]" \
  --storage.testdriver=./my-ceph-driver.yaml
```

### Running Specific Test Categories

Focus on specific replication operations:

```bash
# EnableVolumeReplication tests only
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication" \
  --storage.testdriver=./my-ceph-driver.yaml

# Snapshot mode replication
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication.*snapshot" \
  --storage.testdriver=./my-ceph-driver.yaml

# Journal mode replication
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication.*journal" \
  --storage.testdriver=./my-ceph-driver.yaml

# GetVolumeReplicationInfo tests
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*GetVolumeReplicationInfo" \
  --storage.testdriver=./my-ceph-driver.yaml
```

### Verbose Output

Enable detailed logging for debugging:

```bash
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*\[Feature:Replication\]" \
  --ginkgo.v \
  --storage.testdriver=./my-ceph-driver.yaml
```

## Test Framework Integration

The replication tests are integrated into the Kubernetes storage e2e test framework. Tests follow this flow:

1. **Test Framework** creates a test namespace
2. **Driver Configuration** is loaded from the `--storage.testdriver` file
3. **StorageClass** is created or referenced from the configuration
4. **PVCs** are created with replication annotations
5. **CSI Driver** receives replication parameters via gRPC calls
6. **Tests** validate replication behavior by observing Kubernetes resources

## Troubleshooting

### Tests Skip with "Driver does not support replication"

**Cause**: The driver configuration doesn't declare replication capability or the CSI driver doesn't support it.

**Solution**:
- Verify `replication: true` is set in your driver config capabilities
- Check that your Ceph CSI driver has the replication add-on enabled:
  ```bash
  kubectl get csidriver rbd.csi.ceph.com -o yaml
  ```

### StorageClass Not Found

**Cause**: The StorageClass name in the driver config doesn't match an existing StorageClass.

**Solution**:
- List available StorageClasses: `kubectl get storageclass`
- Update `StorageClass.FromExistingClassName` in your driver config

### PVC Creation Fails

**Cause**: The CSI driver cannot provision volumes, or StorageClass parameters are incorrect.

**Solution**:
- Test PVC creation manually:
  ```bash
  kubectl create -f - <<EOF
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: test-pvc
  spec:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
    storageClassName: <your-storage-class-name>
  EOF
  ```
- Check CSI driver pods: `kubectl get pods -n csi-rbdplugin`
- Review driver logs for errors

### Tests Timeout

**Cause**: Operations take longer than expected, possibly due to cluster resource constraints.

**Solution**: Increase timeouts in your driver config:
```yaml
Timeouts:
  PodStart: "15m"
  PVBound: "10m"
```

### Permission Errors

**Cause**: Insufficient RBAC permissions for test execution.

**Solution**: Ensure cluster-admin level permissions:
```bash
kubectl auth can-i '*' '*' --all-namespaces
```

## Ceph-Specific Considerations

### Multi-Node Cluster Testing

With a 3-node minikube cluster, you can test topology-aware replication:

1. Configure Ceph pools across nodes
2. Enable `topology: true` in driver capabilities
3. Configure StorageClass with topology constraints

### Replication Modes

Ceph supports both replication modes tested by the suite:

- **Snapshot Mode**: Periodic replication (e.g., every 5 minutes). Configured via StorageClass parameters.
- **Journal Mode**: Real-time replication using Ceph RBD mirroring. Requires additional Ceph configuration.

### Remote Cluster Configuration

For replication tests, configure a "remote cluster" target. In a single-cluster setup, some drivers allow using the same cluster with different pool names as the remote target.

## Related Documentation

- [Replication Test Suite Specification](../testsuites/REPLICATION.md) - Complete test suite documentation
- [Storage E2E Test Framework README](../README.md) - General storage testing framework documentation
- [Ceph CSI Driver Documentation](https://github.com/ceph/ceph-csi) - Ceph CSI driver implementation details
