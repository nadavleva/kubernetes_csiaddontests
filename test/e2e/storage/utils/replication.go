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

	"github.com/onsi/ginkgo/v2"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apiserver/pkg/storage/names"
	"k8s.io/client-go/dynamic"
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
	ginkgo.By(fmt.Sprintf("creating VolumeReplication %s for PVC %s", name, pvcName))

	vr := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"kind":       "VolumeReplication",
			"apiVersion": ReplicationAPIVersion,
			"metadata": map[string]interface{}{
				"name":      name,
				"namespace": namespace,
			},
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

// DeleteVolumeReplication deletes a VolumeReplication CRD
func DeleteVolumeReplication(ctx context.Context, dc dynamic.Interface, namespace, name string) error {
	ginkgo.By(fmt.Sprintf("deleting VolumeReplication %s/%s", namespace, name))
	err := dc.Resource(VolumeReplicationGVR).Namespace(namespace).Delete(ctx, name, metav1.DeleteOptions{})
	if err != nil && !apierrors.IsNotFound(err) {
		return fmt.Errorf("failed to delete VolumeReplication %s/%s: %w", namespace, name, err)
	}
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
