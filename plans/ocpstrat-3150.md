# Test Plan: etcd Sharding for HyperShift Hosted Clusters

## 1. Test Plan Identifier

**ID:** TP-OCPSTRAT-3150-001
**Version:** 2.0
**Date:** 2026-09-07
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This test plan defines an **automation-first** verification strategy for **etcd Sharding** in HyperShift hosted clusters. The feature distributes Kubernetes resources across multiple independent etcd clusters organized by resource type, addressing etcd performance limitations in very large hosted clusters or clusters with high resource churn.

The primary goal is to **maximize automated test coverage**. Every testable objective is mapped to:

- **(A) Existing automated tests** — unit tests, CRD/CEL validation test suites, and controller-level tests that run in CI today, cited by file path and test function name.
- **(P) Proposed automation** — gaps where automated tests should be added, with the intended test layer (unit, integration, or e2e) and ownership.
- **(M) Residual manual / live-cluster validation** — behaviors that require a running cluster or cloud infrastructure, with an explicit justification for why automation is insufficient.

The implementation spans two PRs:
- [PR #8705](https://github.com/openshift/hypershift/pull/8705) — Core etcd sharding by resource kind (merged)
- [PR #9146](https://github.com/openshift/hypershift/pull/9146) — Multi-shard etcd backup and restore support (open, not yet merged)

> **Note:** All references to PR #9146 tests reflect the PR's current implementation state. Those tests will become part of CI only after the PR merges.

### 2.2 Objectives

1. Verify that etcd shards are provisioned as independent StatefulSets, Services, PDBs, ServiceMonitors, and TLS certificates when configured in `spec.etcd.managed.shards`.
2. Verify that the kube-apiserver is configured with `--etcd-servers-overrides` to route specified resource types to the appropriate shard.
3. Verify that CEL validation rules enforce resource overlap prevention, shard immutability, name format, and storage constraints.
4. Verify that multi-shard backup captures snapshots from all PersistentVolume-backed shards and populates `ShardSnapshots` in `HCPEtcdBackupStatus`.
5. Verify that multi-shard restore injects `etcd-init` containers for shards with `restoreSnapshotURL` and aggregates the `EtcdSnapshotRestored` condition.
6. Verify backward compatibility: single-shard (unsharded) clusters continue to work; `SnapshotURL` in backup status is populated for the default shard.
7. Verify that the `EtcdSharding` feature gate controls visibility of shard-related API fields.

### 2.3 Acceptance Criteria Mapping

| # | Feature Capability | Coverage | Test Case(s) |
|---|---|---|---|
| 1 | Shard provisioning — StatefulSet, Service, PDB, ServiceMonitor, TLS per shard | **(A)** Unit + **(M)** Live cluster | TC-001 (§6.3) |
| 2 | KAS resource routing via `--etcd-servers-overrides` | **(A)** Unit + **(M)** Live cluster | TC-002 (§6.4) |
| 3 | Shard immutability — cannot add, remove, reorder, or rename shards after creation | **(A)** CRD testsuite | TC-003 (§6.5) |
| 4 | CEL validation — resource overlap, name format, storage type constraints | **(A)** CRD testsuite | TC-004 (§6.6) |
| 5 | Multi-shard backup — per-shard snapshots, EmptyDir skipped, backward compat | **(A)** Unit (PR #9146) + **(M)** Live cluster | TC-005 (§6.7) |
| 6 | Multi-shard restore — init container injection, aggregate condition | **(A)** Unit (PR #9146) + **(M)** Live cluster | TC-006 (§6.8) |
| 7 | Feature gate gating — fields hidden without `EtcdSharding` gate | **(A)** CRD manifest + **(M)** Live cluster | TC-007 (§6.9) |
| 8 | Backward compatibility — unsharded cluster behavior unchanged | **(A)** Unit + **(M)** Live cluster | TC-008 (§6.10) |

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Sharding implementation PR | [openshift/hypershift#8705](https://github.com/openshift/hypershift/pull/8705) — "Add etcd sharding by resource kind support" (merged) |
| Backup/restore PR | [openshift/hypershift#9146](https://github.com/openshift/hypershift/pull/9146) — "Add multi-shard etcd backup and restore support" (open) |
| Feature Jira | OCPSTRAT-3150 |
| API: shard spec (managed) | `api/hypershift/v1beta1/hostedcluster_types.go` — `ManagedEtcdSpec.Shards`, `ManagedEtcdShardSpec`, `EtcdShardResource` |
| API: shard spec (unmanaged) | `api/hypershift/v1beta1/hostedcluster_types.go` — `UnmanagedEtcdSpec.Shards`, `UnmanagedEtcdShardSpec` |
| API: backup status | `api/hypershift/v1beta1/etcdbackup_types.go` — `HCPEtcdBackupStatus.ShardSnapshots`, `HCPEtcdShardSnapshot` |
| API: restore field | `api/hypershift/v1beta1/hostedcluster_types.go` — `ManagedEtcdShardSpec.RestoreSnapshotURL` |
| Feature gate | `EtcdSharding` (TechPreviewNoUpgrade) |
| CRD manifests | `zz_generated.featuregated-crd-manifests/hostedclusters.hypershift.openshift.io/EtcdSharding.yaml` |
| Controller: shard component | `control-plane-operator/controllers/hostedcontrolplane/v2/etcd/shard.go` |
| Controller: KAS params | `control-plane-operator/controllers/hostedcontrolplane/v2/kas/params.go`, `kas/deployment.go`, `kas/config.go` |
| Controller: backup reconciler | `hypershift-operator/controllers/etcdbackup/reconciler.go` |
| Controller: restore logic | `control-plane-operator/controllers/hostedcontrolplane/hostedcontrolplane_controller.go` |
| Controller: PKI (shard certs) | `control-plane-operator/controllers/hostedcontrolplane/pki/etcd.go` |
| Support: shard helpers | `support/etcd/shards.go` |
| etcd-upload CLI | `etcd-upload/etcdupload.go` |

### 3.1 Automated Test Inventory

| Test File | Test Functions | PR | Layer |
|-----------|---------------|-----|-------|
| `support/etcd/shards_test.go` | `TestEffectiveShards`, `TestUnmanagedEffectiveShards`, `TestResourcePrefix`, `TestClientServiceName`, `TestDiscoveryServiceName` | #8705 (merged) | Unit |
| `control-plane-operator/.../v2/etcd/shard_test.go` | `TestEtcdShardInterface`, `TestNewShardComponent`, `TestEtcdTemplateData`, `TestAdaptShardStorage`, `TestAdaptShardScheduling`, `TestAdaptStatefulSetForShard`, `TestAdaptStatefulSetForShard_IPv6WithDefrag`, `TestAdaptStatefulSetForShard_RestoreInitContainer`† | #8705 + #9146† | Unit |
| `control-plane-operator/.../v2/assets/assets_test.go` | `TestLoadStatefulSetManifest` (shard template subtests) | #8705 (merged) | Unit |
| `control-plane-operator/.../v2/kas/params_test.go` | `TestNewConfigParams` (managed/unmanaged shard override subtests) | #8705 (merged) | Unit |
| `hypershift-operator/.../etcdbackup/reconciler_test.go` | `TestEtcdShards`†, `TestCheckEtcdHealthMultiShard`†, `TestBuildSnapshotInitContainers`†, `TestParseShardSnapshots`†, `TestGetShardSnapshotsFromPod`†, `TestBuildUploadContainer`†, `TestCreateBackupJob` (shard subtests)†, `TestEnsureNetworkPolicyMultiShard`† | #9146† | Unit |
| `control-plane-operator/.../hostedcontrolplane_controller_test.go` | `TestEtcdRestoredCondition`†, `TestHasRestoreURLs`†, `TestAggregateEtcdRestoredCondition`†, `TestReconcileEtcdStatus` (restore subtest)† | #9146† | Unit |
| `etcd-upload/etcdupload_test.go` | `TestNewStartCommand`, `TestRunValidation`†, `TestRunDir`†, `TestNewUploader`, `TestKeyGeneration` | #8705 + #9146† | Unit |
| `cmd/.../tests/.../featuregated.hostedclusters.etcdsharding.testsuite.yaml` | 5 CRD tests (merged) + 5 CRD tests (PR #9146†) | #8705 + #9146† | CRD |
| `cmd/.../tests/.../techpreview.hcpetcdbackups.status.testsuite.yaml` | 2 CRD tests (PR #9146†) | #9146† | CRD |

> **†** = from PR #9146 (open). These tests will run in CI only after that PR merges.

### 3.2 Key API Types

| Type | Purpose |
|------|---------|
| `ManagedEtcdShardSpec` | Per-shard config: name, resources, storage, replicas, scheduling, restoreSnapshotURL |
| `EtcdShardResource` | Identifies a resource type (apiGroup + resource) to route to a shard |
| `EtcdShardSchedulingSpec` | Per-shard nodeSelector, tolerations, topology spread constraints |
| `HCPEtcdShardSnapshot` | Per-shard backup snapshot URL (name + snapshotURL) |
| `UnmanagedEtcdShardSpec` | Per-shard config for unmanaged etcd: name, resources, endpoint |

### 3.3 Key Constraints (from CEL validation)

| Rule | Description | Automated? |
|------|-------------|------------|
| `has(oldSelf.shards) == has(self.shards)` | Shards cannot be added or removed after creation | ✅ CRD testsuite |
| `self.size() == oldSelf.size()` | Shard count is immutable | ✅ CRD testsuite |
| `oldSelf.all(old, self.exists(cur, cur.name == old.name))` | Existing shards cannot be replaced | ✅ CRD testsuite |
| Resource overlap prevention | Resources must not overlap across shards | ✅ CRD testsuite |
| Name format validation | Shard names must be valid DNS-1123 labels | ✅ CRD testsuite |
| `restoreSnapshotURL` immutability | Once set, value cannot be changed | ✅ CRD testsuite (PR #9146) |
| `restoreSnapshotURL` removal guard | Once set, cannot be removed | ✅ CRD testsuite (PR #9146) |
| EmptyDir + restoreSnapshotURL rejection | `restoreSnapshotURL` is not supported for EmptyDir shards | ✅ CRD testsuite (PR #9146) |
| URL scheme validation | `restoreSnapshotURL` and `snapshotURL` must use `https` or `s3` scheme | ✅ CRD testsuite (PR #9146) |
| MaxItems=10 | Maximum 10 named shards per cluster | Schema-enforced (kubebuilder annotation) |

---

## 4. Features to Be Tested

1. **Managed etcd shard provisioning** — Creating a HostedCluster with `spec.etcd.managed.shards` entries causes independent StatefulSets, Services, PDBs, ServiceMonitors, and TLS secrets to be created for each shard in the hosted control plane namespace.
2. **KAS resource routing** — The kube-apiserver container args include `--etcd-servers-overrides` entries that map each shard's resources to its etcd endpoint.
3. **Shard immutability after creation** — Attempts to add, remove, reorder, rename shards, or change their storage type after initial HostedCluster creation are rejected by admission.
4. **CEL validation rules** — API server rejects: overlapping resources across shards; invalid shard names; `restoreSnapshotURL` on EmptyDir shards; invalid URL schemes; restoreSnapshotURL mutation or removal.
5. **Multi-shard backup** — An `HCPEtcdBackup` captures snapshots from the default shard and all PersistentVolume-backed named shards. EmptyDir-backed shards are skipped. `ShardSnapshots` in status contains per-shard snapshot URLs.
6. **Multi-shard restore** — Setting `restoreSnapshotURL` on shard specs causes `etcd-init` containers to be injected in the shard StatefulSet. The `EtcdSnapshotRestored` condition is aggregated across all shards.
7. **Feature gate enforcement** — Without the `EtcdSharding` feature gate enabled, the `shards` and `scheduling` fields are not present in the HostedCluster CRD schema.
8. **Backward compatibility** — A HostedCluster without shards (single default etcd) continues to operate normally. Backup status retains `snapshotURL` for the default shard alongside `shardSnapshots`.
9. **Per-shard storage options** — Shards can independently use `PersistentVolume` or `EmptyDir` storage types.
10. **Per-shard scheduling** — Each shard can have independent `nodeSelector`, `tolerations`, and `topologySpreadConstraints`.

---

## 5. Features Not to Be Tested

The following are explicitly out of scope:

- **Unmanaged etcd sharding** — While the API supports `spec.etcd.unmanaged.shards`, unmanaged etcd is an external-cluster integration path. API validation is covered by CRD tests. Functional testing is out of scope.
- **etcd-defrag behavior** — The `etcd-defrag` binary was updated to handle multiple instances, but defragmentation testing requires long-running load generation and is covered by existing etcd CI jobs.
- **Performance and scale testing** — The feature targets 7,500+ node clusters; validating at-scale performance requires dedicated capacity testing outside this plan.
- **CRD-backed / aggregated API resource routing** — `--etcd-servers-overrides` only routes kube-apiserver built-in types. CRD and aggregated API resources are NOT routed. This is a known kube-apiserver limitation.
- **etcd-upload CLI internals** — The `--snapshot-dir` flag and JSON termination log changes are tested by unit tests (`TestRunValidation`, `TestRunDir`). Manual CLI testing is out of scope.
- **Multi-replica shard dynamics under failure** — Testing etcd quorum loss within individual shards requires fault injection infrastructure.

---

## 6. Test Approach and Design

### 6.1 Approach

This plan follows an **automation-first** strategy organized in three tiers:

1. **Automated (CI)** — Unit tests and CRD validation test suites that execute in every PR build and periodic CI. These cover the majority of logic: shard resolution, template rendering, StatefulSet adaptation, CEL validation, backup job construction, restore init-container injection, and condition aggregation.
2. **Proposed automation** — Gaps where new automated tests should be added. Each gap names the test layer and suggested owner.
3. **Residual manual / live-cluster** — Behaviors that inherently require a running multi-component cluster (real kube-apiserver, etcd pods, cloud storage). These are integration or e2e tests that supplement the automated unit coverage.

Each test case below identifies its coverage tier with **(A)**, **(P)**, or **(M)**.

### 6.2 Running the Automated Tests

All automated tests in the HyperShift repository can be run with:

```bash
# Unit tests for shard logic
go test ./support/etcd/... -run 'TestEffectiveShards|TestUnmanagedEffectiveShards|TestResourcePrefix|TestClientServiceName|TestDiscoveryServiceName' -v

# Unit tests for shard component
go test ./control-plane-operator/controllers/hostedcontrolplane/v2/etcd/... -run 'TestEtcdShardInterface|TestNewShardComponent|TestEtcdTemplateData|TestAdaptShardStorage|TestAdaptShardScheduling|TestAdaptStatefulSetForShard' -v

# Unit tests for asset template rendering
go test ./control-plane-operator/controllers/hostedcontrolplane/v2/assets/... -run 'TestLoadStatefulSetManifest' -v

# Unit tests for KAS overrides
go test ./control-plane-operator/controllers/hostedcontrolplane/v2/kas/... -run 'TestNewConfigParams' -v

# Unit tests for backup reconciler (after PR #9146 merges)
go test ./hypershift-operator/controllers/etcdbackup/... -run 'TestEtcdShards|TestCheckEtcdHealthMultiShard|TestBuildSnapshotInitContainers|TestParseShardSnapshots|TestGetShardSnapshotsFromPod|TestBuildUploadContainer|TestEnsureNetworkPolicyMultiShard' -v

# Unit tests for restore conditions (after PR #9146 merges)
go test ./control-plane-operator/controllers/hostedcontrolplane/... -run 'TestEtcdRestoredCondition|TestHasRestoreURLs|TestAggregateEtcdRestoredCondition|TestReconcileEtcdStatus' -v

# Unit tests for etcd-upload CLI
go test ./etcd-upload/... -run 'TestNewStartCommand|TestRunValidation|TestRunDir|TestNewUploader|TestKeyGeneration' -v

# CRD validation tests (run via the crd-schema-check tool)
make verify-featuregated-crds
```

### 6.3 Common Prerequisites for Manual Tests

- A running HyperShift management cluster with an operational HyperShift operator.
- The HyperShift operator version includes changes from both PR #8705 and PR #9146.
- The `EtcdSharding` feature gate is enabled (TechPreviewNoUpgrade or equivalent).
- The `HCPEtcdBackup` feature gate is enabled (for backup/restore test cases).
- `oc` / `kubectl` CLI access to the management cluster.
- Access to a cloud provider (AWS, Azure, or GCP) for PersistentVolume-backed etcd storage.

---

### 6.4 Test Case TC-001: Managed Etcd Shard Provisioning

**Objective:** Confirm that creating a HostedCluster with etcd shards results in independent infrastructure resources (StatefulSet, Service, PDB, ServiceMonitor, TLS secrets) for each defined shard.

#### Automated Coverage (A)

The following unit tests verify the controller-level logic for shard provisioning:

| Test File | Test Function | What It Verifies |
|-----------|---------------|------------------|
| `support/etcd/shards_test.go` | `TestEffectiveShards` | Shard resolution: nil → nil; no shards → default only; 2 shards → default + `etcd-events` + `etcd-leases` |
| `v2/etcd/shard_test.go` | `TestAdaptStatefulSetForShard` | StatefulSet adaptation: shard-specific labels, replicas, TLS volume mounts |
| `v2/etcd/shard_test.go` | `TestAdaptShardStorage` | PV inherits parent storageClassName; PV overrides per-shard; EmptyDir replaces VolumeClaimTemplates |
| `v2/etcd/shard_test.go` | `TestAdaptShardScheduling` | nodeSelector applied; tolerations appended; no-op when scheduling is empty |
| `v2/etcd/shard_test.go` | `TestEtcdTemplateData` | Template variables: `etcd` → `etcd-client`/`etcd-discovery`; `etcd-events` → `etcd-client-events`/`etcd-discovery-events` |
| `v2/assets/assets_test.go` | `TestLoadStatefulSetManifest` | StatefulSet YAML template renders correctly with default name and shard-specific name (`etcd-events`) |
| `support/etcd/shards_test.go` | `TestClientServiceName`, `TestDiscoveryServiceName` | Service naming: `etcd-client`, `etcd-client-events`, `etcd-discovery-events` |
| `v2/etcd/shard_test.go` | `TestNewShardComponent` | Component factory: 1-replica shard vs. 3-replica shard |
| `v2/etcd/shard_test.go` | `TestAdaptStatefulSetForShard_IPv6WithDefrag` | IPv6 defrag handling with shards |

#### Proposed Automation (P)

| Gap | Proposed Layer | Owner |
|-----|---------------|-------|
| Service, PDB, ServiceMonitor YAML templates rendered with shard-specific names | Unit test in `assets_test.go` (extend `TestLoadStatefulSetManifest` pattern for non-StatefulSet manifests) | Feature developer |
| PKI certificate generation for shard-specific TLS secrets (`etcd-events-peer-tls`, etc.) | Unit test in `pki/etcd_test.go` | Feature developer |

#### Residual Manual Validation (M)

**Justification:** Unit tests verify that each resource is *constructed* correctly in isolation. Only a live cluster confirms that the controller loop actually creates all 5 resource types in the HCP namespace, that pods start successfully, and that the full reconciliation cycle completes.

**Steps:**

1. Create a HostedCluster with two etcd shards (`events` with PV storage, `leases` with EmptyDir):
   ```yaml
   spec:
     etcd:
       managementType: Managed
       managed:
         storage:
           type: PersistentVolume
           persistentVolume:
             size: 8Gi
         shards:
           - name: events
             resources:
               - apiGroup: ""
                 resource: events
             storage:
               type: PersistentVolume
               persistentVolume:
                 size: 4Gi
             replicas: 1
           - name: leases
             resources:
               - apiGroup: coordination.k8s.io
                 resource: leases
             storage:
               type: EmptyDir
             replicas: 1
   ```

2. Wait for the HostedCluster to reach `Available`:
   ```
   oc wait hostedcluster shard-test-001 -n <namespace> --for=condition=Available --timeout=30m
   ```

3. Verify resources exist in the HCP namespace:
   ```bash
   HC_NS=$(oc get hostedcluster shard-test-001 -n <namespace> -o jsonpath='{.status.controlPlaneNamespace}')
   oc get statefulset -n "$HC_NS" -l app=etcd          # expect: etcd, etcd-events, etcd-leases
   oc get service -n "$HC_NS" | grep etcd               # expect: client/discovery services per shard
   oc get pdb -n "$HC_NS" | grep etcd                   # expect: PDB per shard
   oc get servicemonitor -n "$HC_NS" | grep etcd         # expect: ServiceMonitor per shard
   oc get secret -n "$HC_NS" | grep -E 'etcd.*(peer|client|server)' # expect: TLS secrets per shard
   oc get pods -n "$HC_NS" -l app=etcd                  # expect: all pods Running
   ```

4. Verify storage types:
   ```bash
   oc get statefulset etcd-events -n "$HC_NS" -o jsonpath='{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'
   # expect: 4Gi
   oc get statefulset etcd-leases -n "$HC_NS" -o jsonpath='{.spec.template.spec.volumes}' | grep emptyDir
   # expect: emptyDir volume present
   ```

**Pass criteria:** All shard infrastructure resources exist with correct naming and storage types; pods are running.

---

### 6.5 Test Case TC-002: KAS Resource Routing via etcd-servers-overrides

**Objective:** Confirm that the kube-apiserver is configured with `--etcd-servers-overrides` to route specified resource types to the appropriate etcd shard.

#### Automated Coverage (A)

| Test File | Test Function | What It Verifies |
|-----------|---------------|------------------|
| `v2/kas/params_test.go` | `TestNewConfigParams` — "When managed etcd has shards, it should configure server overrides" | `EtcdServersOverrides` contains `/events#https://etcd-client-events...` and `coordination.k8s.io/leases#https://etcd-client-leases...` |
| `v2/kas/params_test.go` | `TestNewConfigParams` — "When unmanaged etcd has shards, it should configure server overrides" | Unmanaged shard endpoints produce correct overrides |
| `support/etcd/shards_test.go` | `TestResourcePrefix` | Core group → `/events`; non-core → `coordination.k8s.io/leases` |

#### Residual Manual Validation (M)

**Justification:** Unit tests verify that `EtcdServersOverrides` is computed correctly. However, confirming that resources are *actually routed* to the correct etcd shard (events stored in events-shard, absent from default-shard) requires a running KAS connected to multiple etcd instances with real data flowing through the API.

**Steps:**

1. With TC-001's HostedCluster available, verify the KAS deployment:
   ```bash
   oc get deployment kube-apiserver -n "$HC_NS" -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-apiserver")].command}' | tr ',' '\n' | grep etcd-servers-overrides
   ```
   Expected: `--etcd-servers-overrides` with entries for events and leases shards.

2. Create resources in the hosted cluster to generate events:
   ```bash
   oc --kubeconfig=<hosted-kubeconfig> create namespace shard-routing-test
   oc --kubeconfig=<hosted-kubeconfig> run test-pod --image=busybox --restart=Never -n shard-routing-test -- sleep 3600
   ```

3. Verify events are stored in the events shard (not the default shard):
   ```bash
   # Events shard should contain event keys:
   oc exec -n "$HC_NS" etcd-events-0 -c etcd -- etcdctl \
     --cacert /etc/etcd/tls/etcd-ca/ca.crt --cert /etc/etcd/tls/client/tls.crt --key /etc/etcd/tls/client/tls.key \
     --endpoints https://localhost:2379 get /kubernetes.io/events/ --prefix --keys-only --limit=5

   # Default shard should NOT contain event keys:
   oc exec -n "$HC_NS" etcd-0 -c etcd -- etcdctl \
     --cacert /etc/etcd/tls/etcd-ca/ca.crt --cert /etc/etcd/tls/client/tls.crt --key /etc/etcd/tls/client/tls.key \
     --endpoints https://localhost:2379 get /kubernetes.io/events/ --prefix --keys-only --limit=5
   ```

**Pass criteria:** Events keys are in the events shard and absent from the default shard; non-routed resources (namespaces) remain in the default shard.

---

### 6.6 Test Case TC-003: Shard Immutability After Creation

**Objective:** Confirm that attempts to modify the shard list after HostedCluster creation are rejected.

#### Automated Coverage (A) — Fully Automated

All immutability rules are enforced by CEL validation and tested by the CRD test suite. **No manual testing is required for this test case.**

**File:** `cmd/install/assets/crds/hypershift-operator/tests/hostedclusters.hypershift.openshift.io/featuregated.hostedclusters.etcdsharding.testsuite.yaml`

| CRD Test Name | What It Verifies |
|---|---|
| `When managed shards size changes it should fail` | Adding a shard after creation → rejected with "shards cannot be added or removed after creation" |
| `When managed shard name is replaced it should fail` | Renaming a shard → rejected with "existing shards cannot be replaced" |
| `When managed shards are unchanged it should pass` | Valid update (no shard mutation) → accepted |

**Execution:** `make verify-featuregated-crds`

**Pass criteria:** All three CRD test cases pass.

---

### 6.7 Test Case TC-004: CEL Validation Rules

**Objective:** Confirm that the API server correctly validates shard configuration: resource overlap, name format, storage constraints, restoreSnapshotURL rules.

#### Automated Coverage (A) — Fully Automated

All validation rules are tested by the CRD test suites. **No manual testing is required for this test case.**

**File:** `featuregated.hostedclusters.etcdsharding.testsuite.yaml`

| CRD Test Name | What It Verifies |
|---|---|
| `When managed shards have overlapping resources it should fail` | Overlapping resource across shards → rejected (onCreate) |
| `When managed shard name is invalid it should fail` | `INVALID_NAME` → rejected with "name must be a valid DNS1123 label" (onCreate) |
| `When restoreSnapshotURL is changed it should fail` † | Mutating restoreSnapshotURL → rejected with "restoreSnapshotURL is immutable" |
| `When restoreSnapshotURL is removed after being set it should fail` † | Removing restoreSnapshotURL → rejected with "restoreSnapshotURL cannot be removed once set" |
| `When restoreSnapshotURL is set on PV-backed shard it should pass` † | Valid PV + restoreSnapshotURL → accepted |
| `When restoreSnapshotURL is set on EmptyDir shard it should fail` † | EmptyDir + restoreSnapshotURL → rejected |
| `When restoreSnapshotURL has invalid scheme it should fail` † | `http://` scheme → rejected |

> **†** = from PR #9146 (not yet merged).

**Note:** The MaxItems=10 limit is enforced by the CRD schema's `maxItems` annotation (kubebuilder), which is validated by kube-apiserver schema validation, not CEL. No separate CRD test exists; schema enforcement is implicit.

**Execution:** `make verify-featuregated-crds`

**Pass criteria:** All CRD test cases pass.

---

### 6.8 Test Case TC-005: Multi-Shard Backup

**Objective:** Confirm that an `HCPEtcdBackup` captures snapshots from all PersistentVolume-backed shards, skips EmptyDir-backed shards, and populates `ShardSnapshots` in status.

> **Dependency:** This test case depends on PR #9146 merging.

#### Automated Coverage (A)

**File:** `hypershift-operator/controllers/etcdbackup/reconciler_test.go` (PR #9146)

| Test Function | Subtests | What It Verifies |
|---|---|---|
| `TestEtcdShards` | "no shards → default only"; "PV-backed → included"; "EmptyDir → skipped" | Shard enumeration; EmptyDir exclusion |
| `TestCheckEtcdHealthMultiShard` | "all ready → healthy"; "one not ready → unhealthy"; "not found → unhealthy" | Multi-shard health check before backup |
| `TestBuildSnapshotInitContainers` | "single shard → fetch-certs + 1 snapshot"; "multiple → fetch-certs + N" | Backup job init container construction |
| `TestParseShardSnapshots` | "JSON array → all shards"; "plain URL → single default (backward compat)"; "empty → nil"; "invalid JSON → error" | Termination message parsing |
| `TestGetShardSnapshotsFromPod` | — | Snapshot URL extraction from pod status |
| `TestCreateBackupJob` | "single shard → --snapshot-path"; "multiple → --snapshot-dir" | Backward-compatible vs. multi-shard job args |
| `TestBuildUploadContainer` | termination message policy | Upload container construction |
| `TestEnsureNetworkPolicyMultiShard` | shard app labels in NetworkPolicy | Network access for shard pods |

**File:** `techpreview.hcpetcdbackups.status.testsuite.yaml` (PR #9146)

| CRD Test Name | What It Verifies |
|---|---|
| `When shardSnapshots has valid entries it should pass` | Valid `ShardSnapshots` status accepted |
| `When shardSnapshots entry has invalid snapshotURL scheme it should fail` | Invalid scheme in shard snapshot → rejected |

**File:** `etcd-upload/etcdupload_test.go` (PR #9146)

| Test Function | What It Verifies |
|---|---|
| `TestRunValidation` | Neither `--snapshot-path` nor `--snapshot-dir` → error; both set → error |
| `TestRunDir` | Empty dir → error; `.db` files → uploads each; non-existent dir → error |

#### Residual Manual Validation (M)

**Justification:** Unit tests verify job construction, shard enumeration, and snapshot parsing. However, the actual upload to cloud storage (S3/Azure) and the end-to-end flow of `HCPEtcdBackup` status population require live etcd pods and cloud credentials.

**Steps:**

1. With TC-001's HostedCluster available, create an `HCPEtcdBackup`:
   ```yaml
   apiVersion: hypershift.openshift.io/v1beta1
   kind: HCPEtcdBackup
   metadata:
     name: shard-backup-test
     namespace: <hc-namespace>
   spec:
     hostedClusterRef:
       name: shard-test-001
   ```

2. Wait for completion:
   ```
   oc wait hcpetcdbackup shard-backup-test -n <hc-namespace> --for=condition=BackupCompleted=True --timeout=15m
   ```

3. Verify `ShardSnapshots`:
   ```bash
   oc get hcpetcdbackup shard-backup-test -n <hc-namespace> -o jsonpath='{.status.shardSnapshots[*].name}'
   # expect: etcd and etcd-events (PV-backed shards); NOT etcd-leases (EmptyDir)
   ```

4. Verify backward-compatible `SnapshotURL`:
   ```bash
   oc get hcpetcdbackup shard-backup-test -n <hc-namespace> -o jsonpath='{.status.snapshotURL}'
   # expect: non-empty URL matching the default shard's snapshot
   ```

**Pass criteria:** `ShardSnapshots` contains PV-backed shards only; `SnapshotURL` matches the default shard; EmptyDir shard is excluded.

---

### 6.9 Test Case TC-006: Multi-Shard Restore

**Objective:** Confirm that setting `restoreSnapshotURL` on shard specs causes `etcd-init` containers to be injected and the `EtcdSnapshotRestored` condition is aggregated.

> **Dependency:** This test case depends on PR #9146 merging.

#### Automated Coverage (A)

**File:** `v2/etcd/shard_test.go` (PR #9146)

| Test Function | Subtests | What It Verifies |
|---|---|---|
| `TestAdaptStatefulSetForShard_RestoreInitContainer` | "RestoreSnapshotURL set + not restored → inject etcd-init"; "EtcdSnapshotRestored=True → skip inject"; "empty URL → no inject"; "EmptyDir shard → no inject (defense-in-depth)" | Init container injection logic |

**File:** `hostedcontrolplane_controller_test.go` (PR #9146)

| Test Function | Subtests | What It Verifies |
|---|---|---|
| `TestEtcdRestoredCondition` | "single pod ready → True"; "pod not ready → False with exit code/reason"; "3 pods all ready → True" | `EtcdSnapshotRestored` condition per-StatefulSet |
| `TestHasRestoreURLs` | — | Restore URL presence detection |
| `TestAggregateEtcdRestoredCondition` | — | Cross-shard condition aggregation |
| `TestReconcileEtcdStatus` | "Managed with RestoreSnapshotURL and StatefulSet has ready pods → EtcdSnapshotRestored=True" | Integration of restore in reconcile loop |

#### Residual Manual Validation (M)

**Justification:** Unit tests verify init-container injection and condition aggregation logic. However, the actual restore workflow — downloading a snapshot from cloud storage, initializing the etcd data directory, and having the hosted cluster boot successfully from restored data — requires live infrastructure.

**Steps:**

1. Using snapshot URLs from TC-005, create a new HostedCluster with `restoreSnapshotURL`:
   ```yaml
   spec:
     etcd:
       managementType: Managed
       managed:
         storage:
           type: PersistentVolume
           persistentVolume:
             size: 8Gi
           restoreSnapshotURL: "<default-shard-snapshot-url>"
         shards:
           - name: events
             resources:
               - apiGroup: ""
                 resource: events
             storage:
               type: PersistentVolume
               persistentVolume:
                 size: 4Gi
             replicas: 1
             restoreSnapshotURL: "<events-shard-snapshot-url>"
   ```

2. Verify `etcd-init` container is present:
   ```bash
   HC_NS=$(oc get hostedcluster shard-restore-test -n <namespace> -o jsonpath='{.status.controlPlaneNamespace}')
   oc get statefulset etcd-events -n "$HC_NS" -o jsonpath='{.spec.template.spec.initContainers[*].name}'
   # expect: etcd-init present
   ```

3. Wait for the cluster to become available and verify the restore condition:
   ```bash
   oc wait hostedcluster shard-restore-test -n <namespace> --for=condition=Available --timeout=30m
   oc get hostedcluster shard-restore-test -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="EtcdSnapshotRestored")].status}'
   # expect: True
   ```

**Pass criteria:** `etcd-init` container present; `EtcdSnapshotRestored` condition is `True`; cluster becomes available.

---

### 6.10 Test Case TC-007: Feature Gate Enforcement

**Objective:** Confirm that the `EtcdSharding` feature gate controls visibility of shard-related API fields.

#### Automated Coverage (A)

The feature gate is enforced via featuregated CRD manifests:
- `api/hypershift/v1beta1/featuregates/featureGate-Hypershift-TechPreviewNoUpgrade.yaml` — declares `EtcdSharding`
- `zz_generated.featuregated-crd-manifests/hostedclusters.hypershift.openshift.io/EtcdSharding.yaml` — CRD manifest gated by `EtcdSharding`
- The `verify-featuregated-crds` make target validates that the gate declarations and CRD manifests are consistent.

The CRD test suite itself runs with the feature gate enabled (the testsuite YAML declares `featureGates: [EtcdSharding]`), validating that the gated schema is correct when the gate is active.

#### Proposed Automation (P)

| Gap | Proposed Layer | Owner |
|-----|---------------|-------|
| Verify that the Default (non-TechPreview) CRD manifest does NOT contain the `shards` field | Unit test or CI check comparing Default vs TechPreview CRD manifests | Feature developer |

#### Residual Manual Validation (M)

**Justification:** Verifying field visibility requires deploying the HyperShift operator with and without the feature gate on a real cluster and inspecting the installed CRD schema.

**Steps:**

1. On a cluster where `EtcdSharding` is **not** enabled:
   ```bash
   oc get crd hostedclusters.hypershift.openshift.io -o json | \
     python3 -c "
   import json, sys
   crd = json.load(sys.stdin)
   schema = crd['spec']['versions'][0]['schema']['openAPIV3Schema']
   etcd_managed = schema['properties']['spec']['properties']['etcd']['properties']['managed']
   print('shards present:', 'shards' in etcd_managed.get('properties', {}))
   print('scheduling present:', 'scheduling' in etcd_managed.get('properties', {}))
   "
   ```
   Expected: Both fields are `False`.

2. Attempt to create a HostedCluster with `spec.etcd.managed.shards`:
   Expected: The `shards` field is silently dropped (unknown field pruning).

**Pass criteria:** Shard-related fields are not exposed in the CRD schema without the feature gate.

---

### 6.11 Test Case TC-008: Backward Compatibility — Unsharded Cluster

**Objective:** Confirm that a HostedCluster created without any shard configuration continues to operate with a single default etcd.

#### Automated Coverage (A)

| Test File | Test Function | What It Verifies |
|-----------|---------------|------------------|
| `support/etcd/shards_test.go` | `TestEffectiveShards` — "no shards → default only" | Single default shard with name `etcd` and ResourcePrefixes `["/"]` |
| `reconciler_test.go` (PR #9146) | `TestParseShardSnapshots` — "plain URL → single default shard" | Backward-compatible snapshot parsing |
| `reconciler_test.go` (PR #9146) | `TestCreateBackupJob` — "single shard → --snapshot-path" | Backward-compatible backup job args |
| `reconciler_test.go` | `TestReconcileHappyPath` | Full reconcile loop for single-shard backup |
| `controller_test.go` | `TestReconcileEtcdStatus` — "Managed and StatefulSet exists with quorum → True" | Default etcd status reconciliation |

#### Residual Manual Validation (M)

**Justification:** Unit tests confirm that the code paths handle the no-shards case identically to the pre-sharding behavior. However, confirming no regression in a real cluster — especially that no extra StatefulSets appear, no `--etcd-servers-overrides` flag is set, and backup produces both `ShardSnapshots` and `SnapshotURL` — requires a live cluster.

**Steps:**

1. Verify only the default etcd StatefulSet exists:
   ```bash
   oc get statefulset -n "$HC_NS" -l app=etcd --no-headers
   # expect: only "etcd"
   ```

2. Verify no `--etcd-servers-overrides` flag:
   ```bash
   oc get deployment kube-apiserver -n "$HC_NS" \
     -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-apiserver")].command}' | grep etcd-servers-overrides
   # expect: no output
   ```

3. Create and verify backup:
   ```bash
   # Create backup, wait for completion, then verify:
   oc get hcpetcdbackup unsharded-backup-test -n <hc-namespace> -o jsonpath='{.status.snapshotURL}'
   # expect: non-empty URL
   ```

**Pass criteria:** Single etcd StatefulSet; no overrides flag; backup produces valid `SnapshotURL`.

---

## 7. Pass/Fail Criteria

### 7.1 Overall Pass

1. **Automated tests:** All unit tests and CRD validation tests listed in §3.1 pass in CI (`go test` + `make verify-featuregated-crds`).
2. **Manual tests:** All residual manual validations (TC-001/M, TC-002/M, TC-005/M, TC-006/M, TC-007/M, TC-008/M) pass their individual criteria.

### 7.2 Overall Fail

- Any automated test failure blocks the PR that introduced the regression.
- Any manual test case failure generates a defect linked to OCPSTRAT-3150.

### 7.3 Evidence Requirements

**For automated tests:** CI build logs showing all test functions pass (exit code 0, no `FAIL` output).

**For manual tests:** Terminal output or screenshots of `oc` commands showing resource states, condition statuses, and validation error messages.

---

## 8. Suspension and Resumption Criteria

### 8.1 Suspension Criteria

- The HyperShift management cluster becomes unavailable or the HostedCluster enters a degraded state unrelated to the feature under test.
- The HyperShift operator is crash-looping or not reconciling.
- Cloud provider infrastructure issues prevent etcd PersistentVolume provisioning or backup storage access.
- The `EtcdSharding` or `HCPEtcdBackup` feature gate is unexpectedly disabled.
- PR #9146 has not merged (suspends TC-005 and TC-006 automated tests).

### 8.2 Resumption Criteria

- The management cluster and HostedCluster are restored to a healthy, operational state.
- The HyperShift operator pod is running and reconciling.
- Any test HostedClusters created during a suspended test run are cleaned up before resuming.
- Feature gates are confirmed enabled and the correct operator version is deployed.

---

## 9. Test Deliverables

| Deliverable | Description |
|-------------|-------------|
| This test plan | `plans/ocpstrat-3150.md` |
| Automated test results | CI build logs from `go test` and `make verify-featuregated-crds` |
| Manual test execution log | Timestamped record of `oc` commands and outputs (for residual manual tests only) |
| Pass/fail summary | Per-test-case verdict with evidence references |
| Defect reports | Jira issues filed for any failures, linked to OCPSTRAT-3150 |

---

## 10. Test Environment

### 10.1 Automated Test Environment

| Component | Requirement |
|-----------|-------------|
| Go toolchain | Go version matching `go.mod` in the HyperShift repository |
| Test execution | `go test ./...` for unit tests; `make verify-featuregated-crds` for CRD tests |
| CI system | OpenShift CI (Prow) — tests run automatically on every PR |

### 10.2 Manual Test Environment

| Component | Requirement |
|-----------|-------------|
| Management cluster | OpenShift cluster running the HyperShift operator with PR #8705 and PR #9146 changes |
| Feature gates | `EtcdSharding` (TechPreviewNoUpgrade) and `HCPEtcdBackup` enabled |
| Platform | AWS, Azure, or GCP with PersistentVolume support for etcd storage |
| Backup storage | S3 bucket or equivalent cloud storage configured for HCPEtcdBackup |
| CLI tools | `oc` or `kubectl` with cluster-admin access; kubeconfig for hosted cluster |
| etcdctl | Available within etcd pods (used in TC-002/M for key inspection) |

### 10.3 Feature Gate Configuration

- `EtcdSharding` — Required for all test cases
- `HCPEtcdBackup` — Required for TC-005, TC-006, TC-008

For TC-007 (feature gate enforcement), a separate cluster or operator configuration with `EtcdSharding` **disabled** is required.

---

## 11. Responsibilities and Roles

| Role | Responsibility |
|------|---------------|
| Test author | Created this plan based on PR #8705 and PR #9146 implementation |
| Feature developer | Owns automated unit tests; addresses proposed automation gaps |
| QE engineer | Executes residual manual test cases; captures evidence; reports results |
| QE lead | Reviews and approves this test plan; triages any failures |

---

## 12. Schedule and Milestones

| Milestone | Timing |
|-----------|--------|
| Automated tests (PR #8705) | Running in CI now (merged) |
| Test plan review | Before PR #9146 merges |
| Automated tests (PR #9146) | Running in CI after PR #9146 merges |
| Proposed automation gaps addressed | Within one sprint of PR #9146 merge |
| Manual test execution — core sharding (TC-001/M, TC-002/M, TC-007/M, TC-008/M) | Within one sprint of operator image availability |
| Manual test execution — backup/restore (TC-005/M, TC-006/M) | After PR #9146 merges and operator image includes both PRs |
| Results reporting | Within 2 business days of manual test execution |

---

## 13. Risks and Contingencies

| Risk | Impact | Mitigation |
|------|--------|------------|
| PR #9146 not yet merged | Backup/restore automated tests and manual tests cannot execute | Execute core sharding tests first; defer backup/restore tests until merge |
| Feature gate behavior changes | CRD field visibility may differ | Verify CRD schema against actual operator deployment before TC-007/M |
| etcdctl not available in shard pods | TC-002/M routing verification impossible | Use alternative: check KAS logs or create resources and verify via API behavior |
| Cloud storage configuration issues | TC-005/M, TC-006/M blocked | Pre-validate backup storage by running a simple backup on an unsharded cluster |
| CEL validation rule changes | Error messages in CRD tests may differ | Tests track exact error messages; update testsuite YAML if messages change |
| Automated test flakiness | False failures in CI | Investigate and fix; do not disable tests |
| Proposed automation gaps not addressed | Reduced coverage | Track as tech debt; manual tests provide interim coverage |

---

## 14. Approval and Exit Criteria

### 14.1 Approval

This test plan requires review and approval from the QE lead and the feature developer before test execution begins.

### 14.2 Exit Criteria

Testing is considered complete when:

1. **All automated tests pass** — Unit tests and CRD validation tests from both PR #8705 and PR #9146 pass in CI.
2. **All residual manual tests pass** — TC-001/M through TC-008/M execute successfully on at least one supported platform, or defects have been filed for failures.
3. **Proposed automation gaps tracked** — Each gap in §6 marked **(P)** has been filed as a follow-up task.
4. **Evidence archived** — CI logs and manual test execution logs have been collected.
5. **Results reported** — Filed defects are linked to OCPSTRAT-3150.

### 14.3 Coverage Summary

| Category | Automated Tests | Status |
|----------|----------------|--------|
| CRD/CEL validation | 12 CRD test cases | 5 merged; 7 pending PR #9146 |
| Shard reconciliation | ~25 unit subtests | Merged |
| KAS routing | 3 unit subtests | Merged |
| Backup multi-shard | ~18 unit subtests | Pending PR #9146 |
| Restore multi-shard | ~11 unit subtests | Pending PR #9146 |
| etcd-upload CLI | ~8 unit subtests | Partially merged; rest pending PR #9146 |
| **Total automated** | **~77 test cases** | |
| **Residual manual** | **6 live-cluster validations** | Require real cluster + cloud storage |
