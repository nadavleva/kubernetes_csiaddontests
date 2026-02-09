#!/bin/bash
# CSI Replication Tests - Quick Start Examples
# Run from: /home/nlevanon/workspace/csi-tests/sources/kubernetes_csiaddontests

set -e

echo "=========================================="
echo "CSI Replication Test Suite - Quick Start"
echo "=========================================="
echo ""

echo "1. Build and validate everything:"
echo "   make replication-all"
echo ""

echo "2. List available replication tests:"
echo "   go test -v ./test/e2e --ginkgo.focus=\"replication\" --ginkgo.dry-run"
echo ""

echo "3. Run CSI mock protocol tests:"
echo "   go test -v ./test/e2e --ginkgo.focus=\"CSI replication\""
echo ""

echo "4. Run all EnableVolumeReplication tests:"  
echo "   go test -v ./test/e2e --ginkgo.focus=\"EnableVolumeReplication\""
echo ""

echo "5. Focus on specific functionality:"
echo "   go test -v ./test/e2e --ginkgo.focus=\"EnableVolumeReplication.*snapshot mode\""
echo "   go test -v ./test/e2e --ginkgo.focus=\"EnableVolumeReplication.*journal mode\""
echo "   go test -v ./test/e2e --ginkgo.focus=\"csi-hostpath.*EnableVolumeReplication\""
echo ""

echo "6. Available test types discovered:"
echo "   ✓ CSI Mock Tests (2 tests) - Protocol validation"
echo "   ✓ Storage Framework Tests (18 tests) - Driver certification"
echo "   ✓ Multiple drivers: csi-hostpath, pd.csi.storage.gke.io"
echo "   ✓ Multiple patterns: default fs, ext4, block volmode"
echo ""

echo "Prerequisites:"
echo "- Running Kubernetes cluster with kubectl configured"
echo "- CSI drivers deployed (for full e2e tests)"
echo ""

echo "Documentation: docs/replication-testing-guide.md"
echo ""