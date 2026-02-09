/*
Copyright 2024 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package utils

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/onsi/ginkgo/v2"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apiserver/pkg/storage/names"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/kubernetes/test/e2e/framework"
)

const (
	// ReplicationGroup is the replication CRD api group
	ReplicationGroup = "replication.storage.openshift.io"
	// ReplicationAPIVersion is the replication CRD api version
	ReplicationAPIVersion = "replication.storage.openshift.io/v1alpha1"
)

var (
	// VolumeReplicationGVR is GroupVersionResource for volumereplications
	VolumeReplicationGVR = schema.GroupVersionResource{Group: ReplicationGroup, Version: "v1alpha1", Resource: "volumereplications"}
	// VolumeReplicationClassGVR is GroupVersionResource for volumereplicationclasses
	VolumeReplicationClassGVR = schema.GroupVersionResource{Group: ReplicationGroup, Version: "v1alpha1", Resource: "volumereplicationclasses"}
)

// CreateVolumeReplication creates a VolumeReplication CRD for a given PVC
func CreateVolumeReplication(ctx context.Context, dc dynamic.Interface, namespace, name, pvcName, replicationClassName string, replicationMode string, parameters map[string]string) (*unstructured.Unstructured, error) {
	return CreateVolumeReplicationWithTestName(ctx, dc, namespace, name, pvcName, replicationClassName, replicationMode, parameters, "")
}

// CreateVolumeReplicationWithTestName creates a VolumeReplication CRD for a given PVC with test name in labels
func CreateVolumeReplicationWithTestName(ctx context.Context, dc dynamic.Interface, namespace, name, pvcName, replicationClassName string, replicationMode string, parameters map[string]string, testName string) (*unstructured.Unstructured, error) {
	ginkgo.By(fmt.Sprintf("creating VolumeReplication %s for PVC %s", name, pvcName))

	// Build metadata with labels if test name is provided
	metadata := map[string]interface{}{
		"name":      name,
		"namespace": namespace,
	}

	// Add test name to labels for easier identification of leftover resources
	if testName != "" {
		labels := map[string]interface{}{
			"test-case": sanitizeTestName(testName),
		}
		metadata["labels"] = labels
	}

	vr := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"kind":       "VolumeReplication",
			"apiVersion": ReplicationAPIVersion,
			"metadata":   metadata,
			"spec": map[string]interface{}{
				"dataSource": map[string]interface{}{
					"name": pvcName,
					"kind": "PersistentVolumeClaim",
				},
				"volumeReplicationClass": replicationClassName,
				"replicationState":       "primary",
			},
		},
	}

	// Add replication mode and other parameters if provided
	if replicationMode != "" {
		if vr.Object["spec"].(map[string]interface{})["parameters"] == nil {
			vr.Object["spec"].(map[string]interface{})["parameters"] = make(map[string]interface{})
		}
		vr.Object["spec"].(map[string]interface{})["parameters"].(map[string]interface{})["replication.storage.openshift.io/replication-mode"] = replicationMode
	}

	if parameters != nil {
		if vr.Object["spec"].(map[string]interface{})["parameters"] == nil {
			vr.Object["spec"].(map[string]interface{})["parameters"] = make(map[string]interface{})
		}
		params := vr.Object["spec"].(map[string]interface{})["parameters"].(map[string]interface{})
		for k, v := range parameters {
			params[k] = v
		}
	}

	createdVR, err := dc.Resource(VolumeReplicationGVR).Namespace(namespace).Create(ctx, vr, metav1.CreateOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to create VolumeReplication: %w", err)
	}

	framework.Logf("Created VolumeReplication %s/%s", namespace, name)
	return createdVR, nil
}

// DeleteVolumeReplication deletes a VolumeReplication CRD and waits for it to be deleted.
// If the deletion is stuck due to finalizers, it will attempt to remove them after a timeout.
func DeleteVolumeReplication(ctx context.Context, dc dynamic.Interface, namespace, name string) error {
	return DeleteVolumeReplicationWithTimeout(ctx, dc, namespace, name, 30*time.Second)
}

// DeleteVolumeReplicationWithTimeout deletes a VolumeReplication CRD with a custom timeout.
// If deletion is stuck due to finalizers, it will attempt to remove them after the timeout.
func DeleteVolumeReplicationWithTimeout(ctx context.Context, dc dynamic.Interface, namespace, name string, timeout time.Duration) error {
	ginkgo.By(fmt.Sprintf("deleting VolumeReplication %s/%s", namespace, name))

	// Check for finalizers before deletion and remove them proactively
	vr, err := dc.Resource(VolumeReplicationGVR).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("failed to get VolumeReplication %s/%s: %w", namespace, name, err)
	}
	if err == nil {
		finalizers := vr.GetFinalizers()
		if len(finalizers) > 0 {
			framework.Logf("VolumeReplication %s/%s has finalizers: %v, removing them before deletion", namespace, name, finalizers)
			if err := removeVolumeReplicationFinalizers(ctx, dc, namespace, name); err != nil {
				framework.Logf("Warning: failed to remove finalizers from VolumeReplication %s/%s before deletion: %v", namespace, name, err)
			}
		}
	}

	// Attempt to delete the VolumeReplication
	err = dc.Resource(VolumeReplicationGVR).Namespace(namespace).Delete(ctx, name, metav1.DeleteOptions{})
	if err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("failed to delete VolumeReplication %s/%s: %w", namespace, name, err)
	}

	// If already not found, we're done
	if apierrors.IsNotFound(err) {
		return nil
	}

	// Wait for deletion to complete
	framework.Logf("Waiting for VolumeReplication %s/%s to be deleted (timeout: %v)", namespace, name, timeout)
	deadline := time.Now().Add(timeout)
	pollInterval := 1 * time.Second

	for time.Now().Before(deadline) {
		vr, err := dc.Resource(VolumeReplicationGVR).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
		if apierrors.IsNotFound(err) {
			framework.Logf("VolumeReplication %s/%s deleted successfully", namespace, name)
			return nil
		}
		if err != nil {
			framework.Logf("Error checking VolumeReplication %s/%s status: %v", namespace, name, err)
			time.Sleep(pollInterval)
			continue
		}

		// Check if deletion is stuck due to finalizers
		finalizers := vr.GetFinalizers()
		if len(finalizers) > 0 {
			framework.Logf("VolumeReplication %s/%s has finalizers: %v, waiting for controller to remove them", namespace, name, finalizers)

			// If we're close to timeout, try to remove finalizers
			if time.Until(deadline) < 5*time.Second {
				framework.Logf("VolumeReplication %s/%s deletion is stuck with finalizers, attempting to remove them", namespace, name)
				return removeVolumeReplicationFinalizers(ctx, dc, namespace, name)
			}
		}

		time.Sleep(pollInterval)
	}

	// Timeout reached, try to remove finalizers as last resort
	framework.Logf("Timeout waiting for VolumeReplication %s/%s deletion, attempting to remove finalizers", namespace, name)
	return removeVolumeReplicationFinalizers(ctx, dc, namespace, name)
}

// removeVolumeReplicationFinalizers removes all finalizers from a VolumeReplication object
func removeVolumeReplicationFinalizers(ctx context.Context, dc dynamic.Interface, namespace, name string) error {
	vr, err := dc.Resource(VolumeReplicationGVR).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil // Already deleted
	}
	if err != nil {
		return fmt.Errorf("failed to get VolumeReplication %s/%s: %w", namespace, name, err)
	}

	finalizers := vr.GetFinalizers()
	if len(finalizers) == 0 {
		framework.Logf("VolumeReplication %s/%s has no finalizers, should be deleted soon", namespace, name)
		return nil
	}

	framework.Logf("Removing finalizers from VolumeReplication %s/%s: %v", namespace, name, finalizers)

	// Patch to remove all finalizers
	patch := []byte(`{"metadata":{"finalizers":[]}}`)
	_, err = dc.Resource(VolumeReplicationGVR).Namespace(namespace).Patch(
		ctx,
		name,
		types.MergePatchType,
		patch,
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("failed to remove finalizers from VolumeReplication %s/%s: %w", namespace, name, err)
	}

	framework.Logf("Successfully removed finalizers from VolumeReplication %s/%s", namespace, name)
	return nil
}

// RemovePVCFinalizers removes all finalizers from a PVC object
func RemovePVCFinalizers(ctx context.Context, cs kubernetes.Interface, namespace, name string) error {
	pvc, err := cs.CoreV1().PersistentVolumeClaims(namespace).Get(ctx, name, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		return nil // Already deleted
	}
	if err != nil {
		return fmt.Errorf("failed to get PVC %s/%s: %w", namespace, name, err)
	}

	finalizers := pvc.GetFinalizers()
	if len(finalizers) == 0 {
		framework.Logf("PVC %s/%s has no finalizers", namespace, name)
		return nil
	}

	framework.Logf("Removing finalizers from PVC %s/%s: %v", namespace, name, finalizers)

	// Patch to remove all finalizers
	patch := []byte(`{"metadata":{"finalizers":[]}}`)
	_, err = cs.CoreV1().PersistentVolumeClaims(namespace).Patch(
		ctx,
		name,
		types.MergePatchType,
		patch,
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("failed to remove finalizers from PVC %s/%s: %w", namespace, name, err)
	}

	framework.Logf("Successfully removed finalizers from PVC %s/%s", namespace, name)
	return nil
}

// GenerateVolumeReplicationClassSpec constructs a new VolumeReplicationClass instance spec
func GenerateVolumeReplicationClassSpec(
	provisioner string,
	parameters map[string]string,
	ns string,
) *unstructured.Unstructured {
	vrClass := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"kind":       "VolumeReplicationClass",
			"apiVersion": ReplicationAPIVersion,
			"metadata": map[string]interface{}{
				"name": names.SimpleNameGenerator.GenerateName(ns),
			},
			"provisioner": provisioner,
			"parameters":  parameters,
		},
	}

	return vrClass
}

// sanitizeTestName converts a test name to a valid Kubernetes label value
// Kubernetes labels must be lowercase alphanumeric characters, '-', '_' or '.'
func sanitizeTestName(testName string) string {
	// Remove special characters and convert to lowercase
	result := ""
	for _, r := range testName {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			result += string(r)
		} else if r >= 'A' && r <= 'Z' {
			result += string(r + 32) // Convert to lowercase
		} else if r == ' ' || r == '[' || r == ']' {
			result += "-"
		}
		// Skip other special characters
	}

	// Limit length to 63 characters (Kubernetes label value limit)
	if len(result) > 63 {
		result = result[:63]
	}

	// Remove leading/trailing dashes
	result = strings.Trim(result, "-")

	if result == "" {
		result = "unknown-test"
	}

	return result
}
