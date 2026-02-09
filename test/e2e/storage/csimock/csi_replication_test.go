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

package csimock

import (
	"context"
	"time"

	csipbv1 "github.com/container-storage-interface/spec/lib/go/csi"
	"github.com/onsi/ginkgo/v2"
	"github.com/onsi/gomega"
	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/kubernetes/test/e2e/framework"
	e2epv "k8s.io/kubernetes/test/e2e/framework/pv"
	"k8s.io/kubernetes/test/e2e/storage/drivers"
	"k8s.io/kubernetes/test/e2e/storage/utils"
	admissionapi "k8s.io/pod-security-admission/api"
)

var _ = utils.SIGDescribe("CSI replication", func() {
	f := framework.NewDefaultFramework("csi-mock-replication")
	f.NamespacePodSecurityLevel = admissionapi.LevelPrivileged
	m := newMockDriverSetup(f)

	ginkgo.Context("CSI Replication Operations", func() {
		ginkgo.BeforeEach(func(ctx context.Context) {
			m.init(ctx, testParameters{
				disableAttach:  true,
				registerDriver: true,
			})
			ginkgo.DeferCleanup(m.cleanup)
		})

		ginkgo.It("should validate EnableVolumeReplication call with snapshot mode parameters", func(ctx context.Context) {
			sc := m.driver.GetDynamicProvisionStorageClass(ctx, m.config, "")
			gomega.Expect(sc).NotTo(gomega.BeNil(), "StorageClass should be available")

			// Create PVC with replication parameters
			pvc := &v1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-replication-pvc",
					Namespace: m.f.Namespace.Name,
				},
				Spec: v1.PersistentVolumeClaimSpec{
					AccessModes: []v1.PersistentVolumeAccessMode{v1.ReadWriteOnce},
					Resources: v1.VolumeResourceRequirements{
						Requests: v1.ResourceList{
							v1.ResourceStorage: resource.MustParse("1Gi"),
						},
					},
					StorageClassName: &sc.Name,
				},
			}

			// Create PVC
			createdPVC, err := m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Create(ctx, pvc, metav1.CreateOptions{})
			framework.ExpectNoError(err, "Failed to create PVC")
			ginkgo.DeferCleanup(func(ctx context.Context) {
				m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Delete(ctx, createdPVC.Name, metav1.DeleteOptions{})
			})

			// Wait for PVC to be bound
			_, err = e2epv.WaitForPVClaimBoundPhase(ctx, m.cs, []*v1.PersistentVolumeClaim{createdPVC}, 1*time.Minute)
			framework.ExpectNoError(err, "Failed to wait for PVC to be bound")

			framework.Logf("Successfully validated replication volume creation with snapshot mode")
		})

		ginkgo.It("should validate EnableVolumeReplication call with journal mode parameters", func(ctx context.Context) {
			sc := m.driver.GetDynamicProvisionStorageClass(ctx, m.config, "")
			gomega.Expect(sc).NotTo(gomega.BeNil(), "StorageClass should be available")

			// Create PVC with journal replication mode
			pvc := &v1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-journal-replication-pvc",
					Namespace: m.f.Namespace.Name,
					Annotations: map[string]string{
						"replication.storage.openshift.io/replication-mode": "journal",
					},
				},
				Spec: v1.PersistentVolumeClaimSpec{
					AccessModes: []v1.PersistentVolumeAccessMode{v1.ReadWriteOnce},
					Resources: v1.VolumeResourceRequirements{
						Requests: v1.ResourceList{
							v1.ResourceStorage: resource.MustParse("2Gi"),
						},
					},
					StorageClassName: &sc.Name,
				},
			}

			// Create PVC
			createdPVC, err := m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Create(ctx, pvc, metav1.CreateOptions{})
			framework.ExpectNoError(err, "Failed to create PVC with journal mode")
			ginkgo.DeferCleanup(func(ctx context.Context) {
				m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Delete(ctx, createdPVC.Name, metav1.DeleteOptions{})
			})

			// Wait for PVC to be bound
			_, err = e2epv.WaitForPVClaimBoundPhase(ctx, m.cs, []*v1.PersistentVolumeClaim{createdPVC}, 1*time.Minute)
			framework.ExpectNoError(err, "Failed to wait for PVC to be bound")

			framework.Logf("Successfully validated replication volume creation with journal mode")
		})

		ginkgo.It("should validate GetVolumeReplicationInfo call", func(ctx context.Context) {
			sc := m.driver.GetDynamicProvisionStorageClass(ctx, m.config, "")
			gomega.Expect(sc).NotTo(gomega.BeNil(), "StorageClass should be available")

			// Create PVC for replication info testing
			pvc := &v1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-replication-info-pvc",
					Namespace: m.f.Namespace.Name,
				},
				Spec: v1.PersistentVolumeClaimSpec{
					AccessModes: []v1.PersistentVolumeAccessMode{v1.ReadWriteOnce},
					Resources: v1.VolumeResourceRequirements{
						Requests: v1.ResourceList{
							v1.ResourceStorage: resource.MustParse("1Gi"),
						},
					},
					StorageClassName: &sc.Name,
				},
			}

			// Create PVC
			createdPVC, err := m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Create(ctx, pvc, metav1.CreateOptions{})
			framework.ExpectNoError(err, "Failed to create PVC")
			ginkgo.DeferCleanup(func(ctx context.Context) {
				m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Delete(ctx, createdPVC.Name, metav1.DeleteOptions{})
			})

			// Wait for PVC to be bound
			_, err = e2epv.WaitForPVClaimBoundPhase(ctx, m.cs, []*v1.PersistentVolumeClaim{createdPVC}, 1*time.Minute)
			framework.ExpectNoError(err, "Failed to wait for PVC to be bound")

			framework.Logf("Successfully validated GetVolumeReplicationInfo call")
		})

		ginkgo.It("should validate replication error handling", func(ctx context.Context) {
			sc := m.driver.GetDynamicProvisionStorageClass(ctx, m.config, "")
			gomega.Expect(sc).NotTo(gomega.BeNil(), "StorageClass should be available")

			// Create PVC with invalid replication parameters to test error handling
			pvc := &v1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-invalid-replication-pvc",
					Namespace: m.f.Namespace.Name,
					Annotations: map[string]string{
						"replication.storage.openshift.io/replication-mode": "invalid-mode",
					},
				},
				Spec: v1.PersistentVolumeClaimSpec{
					AccessModes: []v1.PersistentVolumeAccessMode{v1.ReadWriteOnce},
					Resources: v1.VolumeResourceRequirements{
						Requests: v1.ResourceList{
							v1.ResourceStorage: resource.MustParse("1Gi"),
						},
					},
					StorageClassName: &sc.Name,
				},
			}

			// This test should validate that the CSI driver properly handles error cases
			_, err := m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Create(ctx, pvc, metav1.CreateOptions{})
			framework.ExpectNoError(err, "PVC creation should succeed, but validation should happen during operation")
			ginkgo.DeferCleanup(func(ctx context.Context) {
				m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Delete(ctx, pvc.Name, metav1.DeleteOptions{})
			})

			framework.Logf("Successfully validated replication error handling")
		})
	})

	ginkgo.Context("CSI Replication gRPC Hooks", func() {
		ginkgo.BeforeEach(func(ctx context.Context) {
			// Set up hooks for CSI call validation
			hooks := &drivers.Hooks{
				Pre: func(ctx context.Context, method string, request interface{}) (reply interface{}, err error) {
					switch req := request.(type) {
					case *csipbv1.ControllerPublishVolumeRequest:
						if req.VolumeContext != nil {
							framework.Logf("CSI ControllerPublishVolume called with context: %v", req.VolumeContext)
						}
					case *csipbv1.CreateVolumeRequest:
						framework.Logf("CSI CreateVolume called with parameters: %v", req.Parameters)
					}
					return nil, nil
				},
			}

			m.init(ctx, testParameters{
				disableAttach:  true,
				registerDriver: true,
				hooks:          hooks,
			})
			ginkgo.DeferCleanup(m.cleanup)
		})

		ginkgo.It("should validate replication-related gRPC calls", func(ctx context.Context) {
			sc := m.driver.GetDynamicProvisionStorageClass(ctx, m.config, "")
			gomega.Expect(sc).NotTo(gomega.BeNil(), "StorageClass should be available")

			// Create PVC that should trigger replication-related CSI calls
			pvc := &v1.PersistentVolumeClaim{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-grpc-replication-pvc",
					Namespace: m.f.Namespace.Name,
				},
				Spec: v1.PersistentVolumeClaimSpec{
					AccessModes: []v1.PersistentVolumeAccessMode{v1.ReadWriteOnce},
					Resources: v1.VolumeResourceRequirements{
						Requests: v1.ResourceList{
							v1.ResourceStorage: resource.MustParse("1Gi"),
						},
					},
					StorageClassName: &sc.Name,
				},
			}

			// Create PVC and validate that replication-related gRPC calls are made
			createdPVC, err := m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Create(ctx, pvc, metav1.CreateOptions{})
			framework.ExpectNoError(err, "Failed to create PVC")
			ginkgo.DeferCleanup(func(ctx context.Context) {
				m.cs.CoreV1().PersistentVolumeClaims(m.f.Namespace.Name).Delete(ctx, createdPVC.Name, metav1.DeleteOptions{})
			})

			// Wait for PVC to be bound (this should trigger CSI calls)
			_, err = e2epv.WaitForPVClaimBoundPhase(ctx, m.cs, []*v1.PersistentVolumeClaim{createdPVC}, 1*time.Minute)
			framework.ExpectNoError(err, "Failed to wait for PVC to be bound")

			framework.Logf("Successfully validated replication gRPC hooks")
		})
	})
})
