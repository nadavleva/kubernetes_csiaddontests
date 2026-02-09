# Quick Start: Ceph Replication Testing

Quick reference for running CSI replication tests against Ceph storage using the Kubernetes storage e2e test framework.

## Prerequisites Check

```bash
# Verify cluster access
kubectl cluster-info

# Find your Ceph CSI driver
kubectl get csidrivers

# Find your StorageClass
kubectl get storageclass
```

## Setup

1. **Create driver configuration** (`my-ceph-driver.yaml`):
```yaml
DriverInfo:
  Name: rbd.csi.ceph.com  # Your driver name
  Capabilities:
    persistence: true
    replication: true
    block: true
    topology: true
StorageClass:
  FromExistingClassName: csi-rbd-sc  # Your StorageClass name
```

2. **Build test framework**:
```bash
make ginkgo
```

## Running Tests

### All Replication Tests
```bash
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*\[Feature:Replication\]" \
  --storage.testdriver=./my-ceph-driver.yaml
```

### Specific Test Categories
```bash
# EnableVolumeReplication only
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication" \
  --storage.testdriver=./my-ceph-driver.yaml

# Snapshot mode
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication.*snapshot" \
  --storage.testdriver=./my-ceph-driver.yaml

# Journal mode
go test -v ./test/e2e \
  --ginkgo.focus="External.Storage.*rbd.csi.ceph.com.*EnableVolumeReplication.*journal" \
  --storage.testdriver=./my-ceph-driver.yaml
```

## Common Issues

**Tests skip**: Ensure `replication: true` in driver config capabilities

**StorageClass not found**: Verify StorageClass exists and update driver config

**PVC fails**: Check CSI driver pods and test PVC creation manually

## Full Documentation

- [Ceph Replication Testing Guide](./ceph-replication-testing.md) - Detailed guide
- [Replication Test Suite](../testsuites/REPLICATION.md) - Test suite specification
