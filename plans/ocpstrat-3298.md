# Test Plan: Predictable NodePool Rollout Control

## 1. Test Plan Identifier

**ID:** TP-OCPSTRAT-3298-001
**Version:** 2.0
**Date:** 2026-09-07
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This test plan defines an **automation-first** verification strategy for the **Predictable NodePool Rollout Control** feature in HyperShift. The primary execution path uses the automated e2e tests and unit tests delivered with the implementation in [PR #8698](https://github.com/openshift/hypershift/pull/8698). Manual procedures are retained as a **fallback only**, to be used when automation cannot run (e.g., infrastructure unavailability, platform-specific constraints). The feature decouples NodePool rollout triggering from management-side configuration changes (e.g., HAProxy image digest bumps) so that only user-driven spec changes cause worker node replacement.

### 2.2 Objectives

1. Verify that management-side-only configuration changes (e.g., HAProxy image annotation updates) do **not** trigger a NodePool rollout or node replacement.
2. Verify that spec-driven configuration changes (e.g., adding a user MachineConfig) **do** trigger a NodePool rollout and update the rollout hash annotation.
3. Verify that after an operator upgrade (simulated by removing the rollout config annotation), the controller re-seeds the annotation on the next reconciliation **without** triggering a rollout.

### 2.3 Acceptance Criteria Mapping

This test plan maps to the verified acceptance criteria of [OCPSTRAT-3298](https://issues.redhat.com/browse/OCPSTRAT-3298) ("Predictable NodePool Rollout Control for Hosted Control Planes"):

| OCPSTRAT-3298 Acceptance Criterion | Test Case |
|-------------------------------------|-----------|
| AC #2 — Only a change in the rollout hash MUST trigger a Replace rollout | TC-002 (Section 6.5) |
| AC #3 — A change in only the payload hash MUST NOT trigger a Replace rollout | TC-001 (Section 6.4) |
| AC #4 — Rollout hash tracked via a separate `nodePoolCurrentRolloutConfig` annotation | Verified across TC-001, TC-002, and TC-003 |
| AC #5 — On first reconcile after upgrade, the controller MUST seed the new annotation WITHOUT triggering a rollout | TC-003 (Section 6.6) |

### 2.4 Automation-First Principle

The **primary** verification method for every test case is the automated test suite delivered with PR #8698. Manual execution is a **fallback only**; any use of the manual fallback procedure must be accompanied by a written justification of why automation was infeasible and must produce equivalent evidence (same assertions, same annotation/condition/node-identity checks). Results from automated runs and manual fallback runs are equally valid for acceptance, but automation is always preferred.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#8698](https://github.com/openshift/hypershift/pull/8698) — "CNTRLPLANE-3632: Predictable NodePool rollout control" |
| E2E test file | `test/e2e/v2/tests/nodepool_rollout_control_test.go` (new, 397 lines) |
| E2E registration | `RegisterPredictableRolloutTests()` in `test/e2e/v2/tests/nodepool_lifecycle_test.go` |
| API changes | `api/hypershift/v1beta1/nodepool_conditions.go` — new `ConfigUpdatePending` condition type, `ManagementConfigDriftReason` reason |
| Controller: config hashing | `hypershift-operator/controllers/nodepool/config.go` — new `RolloutHash()` / `RolloutHashWithoutVersion()` methods |
| Controller: CAPI propagation | `hypershift-operator/controllers/nodepool/capi.go` — refactored `propagateVersionAndTemplate()` |
| Controller: conditions | `hypershift-operator/controllers/nodepool/conditions.go` — new `configUpdatePendingCondition()`, updated `updatingConfigCondition()` |
| Controller: token lifecycle | `hypershift-operator/controllers/nodepool/token.go` — rewritten `isOutdated()` |
| Controller: main reconciler | `hypershift-operator/controllers/nodepool/nodepool_controller.go` — annotation seeding on first reconcile |
| Karpenter integration | `karpenter-operator/controllers/karpenterignition/karpenterignition_controller.go` — parallel rollout config annotation tracking |
| Unit tests | `capi_test.go` (+670), `conditions_test.go` (+138), `config_test.go` (+516), `nodepool_controller_test.go` (+12) |
| Feature Jira | [OCPSTRAT-3298](https://issues.redhat.com/browse/OCPSTRAT-3298) — "Predictable NodePool Rollout Control for Hosted Control Planes" |

### 3.1 Key Annotations

| Annotation | Purpose |
|------------|---------|
| `hypershift.openshift.io/nodePoolCurrentRolloutConfig` | Tracks the rollout-relevant config hash (spec-driven inputs only). Changed only on spec-driven rollouts. |
| `hypershift.openshift.io/nodePoolCurrentConfig` | Tracks the full config hash (all inputs including management-side). Changes on any input change. |
| `hypershift.openshift.io/nodePoolCurrentConfigVersion` | Legacy full config+version hash. Retained for backward compatibility. |

### 3.2 Key Conditions

| Condition Type | Meaning |
|----------------|---------|
| `UpdatingConfig` | `True` when the rollout hash differs from the stored annotation (a spec-driven rollout is in progress). `False` when stable. |
| `ConfigUpdatePending` | `True` when management-side content has drifted but no rollout has been triggered. `False` otherwise. |

---

## 4. Features to Be Tested

1. **Management-side image isolation** — Changing the HAProxy image annotation on a NodePool must not alter the `nodePoolCurrentRolloutConfig` annotation, must not set `UpdatingConfig` to `True`, and must not replace any nodes.
2. **Spec-driven rollout triggering** — Adding a user MachineConfig to a NodePool's `spec.config` must trigger a full rollout, update both `nodePoolCurrentRolloutConfig` and `nodePoolCurrentConfig` annotations to new values, and result in nodes running the new configuration.
3. **Operator upgrade annotation seeding** — When the `nodePoolCurrentRolloutConfig` annotation is absent (simulating a pre-upgrade NodePool), the controller must re-seed it on the next reconciliation without triggering a rollout or replacing nodes.

---

## 5. Features Not to Be Tested

The following are explicitly out of scope for this test plan:

- **Version upgrade rollouts** — Release image upgrades (version field changes) are an existing feature and are not modified by this PR.
- **Karpenter-specific rollout behavior** — The Karpenter integration changes (`karpenterignition_controller.go`) parallel the CAPI changes but target `OpenshiftEC2NodeClass` objects. Karpenter-specific e2e coverage is not included in the PR's test file and is out of scope here.
- **InPlace upgrade strategy** — The e2e tests exercise `Replace` (RollingUpdate) strategy only. InPlace rollout behavior is not covered.
- **KubeVirt platform** — The spec-driven rollout test explicitly skips KubeVirt (pending [CNV-38196](https://issues.redhat.com/browse/CNV-38196)).
- **ConfigUpdatePending condition validation** — The new `ConfigUpdatePending` condition is unit-tested but not exercised in the e2e tests; manual verification of this condition is out of scope.
- **Multi-replica rollout dynamics** — Tests use 1-replica NodePools; surge/unavailability behavior at scale is not covered.
- **Build, deployment, or CI infrastructure** — This plan covers test execution only.

---

## 6. Test Approach and Design

### 6.1 Automation-First Approach

The **primary execution path** is the automated test suite in `test/e2e/v2/tests/nodepool_rollout_control_test.go`, registered via `RegisterPredictableRolloutTests()` in `nodepool_lifecycle_test.go`. These Ginkgo-based e2e tests run in HyperShift CI against real management clusters and exercise the same scenarios defined as TC-001, TC-002, and TC-003.

**Execution priority:**

1. **Automated e2e tests (primary)** — Run via HyperShift CI (`e2ev2` build tag). Each e2e test performs the exact sequence of mutations, polling, and assertions described in the corresponding manual fallback procedure, including 2-minute `Consistently` observation windows and node identity verification.
2. **Automated unit tests (supplementary)** — Run via `go test ./hypershift-operator/controllers/nodepool/...`. Unit tests cover internal logic at finer granularity (hash computation, annotation seeding, condition evaluation, `isOutdated` logic, `propagateVersionAndTemplate` behavior).
3. **Manual procedures (fallback only)** — Used only when automation cannot run. Every fallback execution must include a written justification and produce equivalent evidence.

### 6.2 Automated Test Execution / Evidence Matrix

The following matrix maps each automated test to the test case, OCPSTRAT-3298 acceptance criteria, and the evidence it produces.

#### 6.2.1 E2E Tests (Primary)

| Automated E2E Test | Test Case | OCPSTRAT-3298 AC | Evidence Produced |
|--------------------|-----------|------------------|-------------------|
| `ManagementImageChangeNoRolloutTest` | TC-001 | AC #3 (payload-only hash change must NOT trigger rollout), AC #4 (rollout hash annotation) | Patches HAProxy annotation → asserts rollout hash stable over 2 min (`Consistently`), `UpdatingConfig` stays `False`, node count stable, node names unchanged |
| `SpecDrivenChangeTriggersRolloutTest` | TC-002 | AC #2 (rollout hash change MUST trigger rollout), AC #4 (rollout hash annotation) | Creates NodePool + MachineConfig ConfigMap → patches `spec.config` → waits for rollout completion → asserts both `nodePoolCurrentRolloutConfig` and `nodePoolCurrentConfig` changed to new non-empty values |
| `OperatorUpgradeNoRolloutTest` | TC-003 | AC #5 (annotation seeding on upgrade without rollout), AC #4 (rollout hash annotation) | Creates NodePool → removes `nodePoolCurrentRolloutConfig` → triggers reconcile → asserts annotation re-seeded within 1 min (`Eventually`), `UpdatingConfig` stays `False` over 2 min (`Consistently`), `nodePoolCurrentConfig` unchanged, node names unchanged |

All three tests are registered via `RegisterPredictableRolloutTests()` in `test/e2e/v2/tests/nodepool_lifecycle_test.go` and run under the `[sig-hypershift][Jira:Hypershift][Feature:NodePoolLifecycle]` Ginkgo suite with the `e2ev2` build tag.

#### 6.2.2 Unit Tests (Supplementary)

| Unit Test | File | Coverage Area | Relevant TC / AC |
|-----------|------|---------------|-------------------|
| `TestPropagateVersionAndTemplate` | `capi_test.go` | Verifies that management-side-only changes do not update bootstrap secret or trigger spec update; verifies rollout-hash-driven propagation | TC-001 / AC #3, TC-002 / AC #2 |
| `TestPropagateVersionAndTemplateToMachineSet` | `capi_test.go` | Same propagation logic for MachineSet path; management-side changes must not trigger update | TC-001 / AC #3 |
| `TestReconcileMachineDeploymentStatus` | `capi_test.go` | Annotation updates on version/rollout changes; management-side changes must not update config annotations | TC-001 / AC #3, TC-002 / AC #2 |
| `TestReconcileMachineSetStatus` | `capi_test.go` | Same status reconciliation for MachineSet path | TC-001 / AC #3 |
| `TestConfigUpdatePendingCondition` | `conditions_test.go` | `ConfigUpdatePending` condition set/cleared correctly | AC #3 |
| `TestUpdatingConfigCondition` | `conditions_test.go` | `UpdatingConfig` condition uses rollout hash, not full hash | TC-001 / AC #3, TC-002 / AC #2 |
| `TestRolloutHash` | `config_test.go` | `RolloutHash` excludes management-side inputs (HAProxy, platform-computed NoProxy); includes spec-driven inputs (user MachineConfig, pull secret, trust bundle) | TC-001 / AC #3, TC-002 / AC #2 |
| `TestRolloutHashAnnotationSeeding` | `config_test.go` | `isUpdatingConfig` returns `false` when annotation is absent (pre-upgrade); returns `true` when hash differs | TC-003 / AC #5 |
| `TestRolloutGlobalConfigString` | `config_test.go` | `rolloutGlobalConfig` excludes platform-computed NoProxy entries; TLS APIServer changes affect rollout config | AC #3 |
| `TestIsOutdated` | `config_test.go` | Token `isOutdated()` logic: new NodePools are outdated; existing NodePools after upgrade (no new annotation) are not outdated; matching rollout hash + version is not outdated | TC-003 / AC #5 |
| `TestIsUpdatingConfig` | `nodepool_controller_test.go` | Uses `nodePoolAnnotationCurrentRolloutConfig` (not legacy `currentConfig`) | AC #4 |

### 6.3 Common Prerequisites

- A running HyperShift management cluster with an operational HostedCluster.
- The HyperShift operator version includes the changes from PR #8698 (or equivalent).
- A default NodePool exists with at least one ready node.
- The default NodePool has the `hypershift.openshift.io/nodePoolCurrentRolloutConfig` annotation set by the controller.
- The `UpdatingConfig` condition on the default NodePool is `False`.
- For automated execution: CI environment with `e2ev2` build tag and access to the management cluster.
- For manual fallback: `oc` / `kubectl` CLI access to both the management cluster and the hosted cluster; sufficient permissions to create/patch/delete NodePool objects, ConfigMaps, and read Node objects in the hosted cluster.

---

### 6.4 Test Case TC-001: Management-Side Image Change Must Not Trigger Rollout

**Objective:** Confirm that patching the HAProxy image annotation on a NodePool does not trigger a rollout, does not change the rollout hash, and does not replace any nodes.

**Primary Execution (Automated):** `ManagementImageChangeNoRolloutTest` in `test/e2e/v2/tests/nodepool_rollout_control_test.go`. The test patches `hypershift.openshift.io/haproxyImage` with `quay.io/openshift/origin-haproxy-router:e2e-dummy-digest`, then uses a 2-minute `Consistently` loop (15-second interval) to assert rollout hash stability, `UpdatingConfig` remains `False`, and node count is unchanged. Finally verifies node names are identical to baseline via `ConsistOf`.

**Evidence from automation:** CI JUnit report showing pass/fail; Ginkgo log output with `By` step annotations; assertion details on failure.

#### Fallback: Manual Procedure (use only when automation is infeasible)

> **⚠ FALLBACK ONLY** — Before using this procedure, document why the automated e2e test `ManagementImageChangeNoRolloutTest` could not be run. Produce equivalent evidence (annotation values, condition statuses, node names) at each step.

**Prerequisites:**
- Common prerequisites (Section 6.3) are satisfied.
- Identify the default NodePool name: `oc get nodepools -n <hc-namespace>`.

**Steps:**

1. **Record baseline state:**
   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Record this value as `BASELINE_ROLLOUT_HASH`.

   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentConfig}'
   ```
   Record this value as `BASELINE_CONFIG_HASH`.

   Verify `UpdatingConfig` is `False`:
   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.status.conditions[?(@.type=="UpdatingConfig")].status}'
   ```
   Expected: `False`.

   Record baseline node names (on the hosted cluster):
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=<np-name> -o jsonpath='{.items[*].metadata.name}'
   ```
   Record as `BASELINE_NODES`.

2. **Patch the HAProxy image annotation:**
   ```
   oc annotate nodepool <np-name> -n <hc-namespace> \
     hypershift.openshift.io/haproxyImage=quay.io/openshift/origin-haproxy-router:e2e-dummy-digest \
     --overwrite
   ```

3. **Observe stability over 2 minutes (check every 15 seconds):**

   Repeat the following checks at 15-second intervals for at least 2 minutes:

   a. Rollout config annotation unchanged:
   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Expected: equals `BASELINE_ROLLOUT_HASH`.

   b. `UpdatingConfig` condition remains `False`:
   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.status.conditions[?(@.type=="UpdatingConfig")].status}'
   ```
   Expected: `False`.

   c. Node count unchanged (on the hosted cluster):
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=<np-name> --no-headers | wc -l
   ```
   Expected: same count as baseline.

4. **Verify node identity is preserved:**
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=<np-name> -o jsonpath='{.items[*].metadata.name}'
   ```
   Expected: identical set to `BASELINE_NODES` (no replacements occurred).

5. **Verify final rollout hash:**
   ```
   oc get nodepool <np-name> -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Expected: equals `BASELINE_ROLLOUT_HASH`.

6. **Clean up:**
   ```
   oc annotate nodepool <np-name> -n <hc-namespace> hypershift.openshift.io/haproxyImage-
   ```

**Pass criteria:** All assertions in steps 3-5 hold. No rollout triggered; no nodes replaced; rollout hash stable.

**Fail criteria:** Any of: `UpdatingConfig` becomes `True`; rollout hash changes; node names change; node count changes.

---

### 6.5 Test Case TC-002: Spec-Driven MachineConfig Change Must Trigger Rollout

**Objective:** Confirm that adding a MachineConfig to a NodePool's `spec.config` triggers a rollout, updates both hash annotations to new values, and results in nodes converging on the new configuration.

**Primary Execution (Automated):** `SpecDrivenChangeTriggersRolloutTest` in `test/e2e/v2/tests/nodepool_rollout_control_test.go`. The test creates a dedicated 1-replica NodePool with `RollingUpdate` strategy (MaxUnavailable=0, MaxSurge=1), waits for ready, records baseline hashes, creates a MachineConfig ConfigMap with an Ignition file at `/etc/predictable-rollout-test`, patches `spec.config`, waits for rollout completion, and asserts both `nodePoolCurrentRolloutConfig` and `nodePoolCurrentConfig` changed to new non-empty values. The test skips KubeVirt platform (pending CNV-38196). Cleanup is automatic via `DeferCleanup`.

**Evidence from automation:** CI JUnit report showing pass/fail; Ginkgo log output with `By` step annotations; before/after hash values on failure.

#### Fallback: Manual Procedure (use only when automation is infeasible)

> **⚠ FALLBACK ONLY** — Before using this procedure, document why the automated e2e test `SpecDrivenChangeTriggersRolloutTest` could not be run. Produce equivalent evidence (annotation values before/after, rollout completion) at each step.

**Prerequisites:**
- Common prerequisites (Section 6.3) are satisfied.
- The platform is **not** KubeVirt (this test is skipped for KubeVirt per CNV-38196).

**Steps:**

1. **Create a dedicated test NodePool:**

   Create a NodePool manifest with 1 replica and RollingUpdate strategy (MaxUnavailable=0, MaxSurge=1), based on the default NodePool's platform configuration. Example:
   ```yaml
   apiVersion: hypershift.openshift.io/v1beta1
   kind: NodePool
   metadata:
     name: rollout-ctl-test
     namespace: <hc-namespace>
   spec:
     clusterName: <hosted-cluster-name>
     replicas: 1
     release:
       image: <same-as-default-nodepool>
     platform: <copy-from-default-nodepool>
     management:
       upgradeType: Replace
       replace:
         strategy: RollingUpdate
         rollingUpdate:
           maxUnavailable: 0
           maxSurge: 1
   ```
   Apply: `oc apply -f <nodepool-manifest>.yaml`

2. **Wait for the NodePool to become ready:**
   ```
   oc wait nodepool rollout-ctl-test -n <hc-namespace> --for=condition=Ready --timeout=20m
   ```
   Verify at least one ready node exists (on the hosted cluster):
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=rollout-ctl-test --no-headers | wc -l
   ```
   Expected: `1`.

3. **Record baseline state:**
   ```
   oc get nodepool rollout-ctl-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Record as `BASELINE_ROLLOUT_HASH`.

   ```
   oc get nodepool rollout-ctl-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentConfig}'
   ```
   Record as `BASELINE_CONFIG_HASH`.

4. **Create a MachineConfig ConfigMap:**
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: rollout-ctl-mc
     namespace: <hc-namespace>
   data:
     config: |
       apiVersion: machineconfiguration.openshift.io/v1
       kind: MachineConfig
       metadata:
         name: predictable-rollout-test
         labels:
           machineconfiguration.openshift.io/role: worker
       spec:
         config:
           ignition:
             version: "3.2.0"
           storage:
             files:
               - path: /etc/predictable-rollout-test
                 contents:
                   source: "data:,rollout-test%0A"
   ```
   Apply: `oc apply -f <configmap-manifest>.yaml`

5. **Patch the NodePool to reference the MachineConfig:**
   ```
   oc patch nodepool rollout-ctl-test -n <hc-namespace> --type=merge \
     -p '{"spec":{"config":[{"name":"rollout-ctl-mc"}]}}'
   ```

6. **Wait for the rollout to complete:**

   Monitor `UpdatingConfig` condition until it returns to `False` (may take 10-20 minutes depending on platform):
   ```
   oc wait nodepool rollout-ctl-test -n <hc-namespace> --for=condition=UpdatingConfig=False --timeout=30m
   ```
   Then wait for all nodes to be ready:
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=rollout-ctl-test -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
   ```
   Expected: `True` for all nodes.

7. **Verify the rollout hash annotation was updated:**
   ```
   oc get nodepool rollout-ctl-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Expected: **differs** from `BASELINE_ROLLOUT_HASH`; is non-empty.

8. **Verify the full config hash annotation was also updated:**
   ```
   oc get nodepool rollout-ctl-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentConfig}'
   ```
   Expected: **differs** from `BASELINE_CONFIG_HASH`; is non-empty.

9. **Clean up:**
   ```
   oc delete nodepool rollout-ctl-test -n <hc-namespace>
   oc delete configmap rollout-ctl-mc -n <hc-namespace>
   ```

**Pass criteria:** Rollout completes successfully; both `nodePoolCurrentRolloutConfig` and `nodePoolCurrentConfig` annotations have changed to new non-empty values.

**Fail criteria:** Rollout does not trigger; annotation values remain at baseline; nodes never converge to ready state.

---

### 6.6 Test Case TC-003: Operator Upgrade Annotation Seeding Without Rollout

**Objective:** Confirm that when the `nodePoolCurrentRolloutConfig` annotation is absent (simulating a pre-upgrade NodePool), the controller re-seeds it on the next reconciliation without triggering a rollout or replacing nodes.

**Primary Execution (Automated):** `OperatorUpgradeNoRolloutTest` in `test/e2e/v2/tests/nodepool_rollout_control_test.go`. The test creates a 1-replica NodePool, waits for ready, records baseline, removes the `nodePoolCurrentRolloutConfig` annotation, adds a dummy `e2e-reconcile-trigger` annotation to force reconciliation, asserts the annotation is re-seeded within 1 minute (`Eventually`, 10-second interval), then uses a 2-minute `Consistently` loop (15-second interval) to assert `UpdatingConfig` stays `False`, `nodePoolCurrentConfig` unchanged, node count stable, and finally verifies node names are identical. Cleanup is automatic via `DeferCleanup`.

**Evidence from automation:** CI JUnit report showing pass/fail; Ginkgo log output with `By` step annotations; assertion details on failure.

#### Fallback: Manual Procedure (use only when automation is infeasible)

> **⚠ FALLBACK ONLY** — Before using this procedure, document why the automated e2e test `OperatorUpgradeNoRolloutTest` could not be run. Produce equivalent evidence (annotation values, condition statuses, node names) at each step.

**Prerequisites:**
- Common prerequisites (Section 6.3) are satisfied.

**Steps:**

1. **Create a dedicated test NodePool:**

   Create a NodePool with 1 replica (using defaults for upgrade strategy). Apply and wait for ready:
   ```
   oc apply -f <nodepool-manifest>.yaml
   oc wait nodepool upgrade-seed-test -n <hc-namespace> --for=condition=Ready --timeout=20m
   ```

2. **Record baseline state:**

   Verify the rollout config annotation exists:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Expected: non-empty. Record as `BASELINE_ROLLOUT_HASH`.

   Record `nodePoolCurrentConfig`:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentConfig}'
   ```
   Record as `BASELINE_CONFIG_HASH`.

   Verify `UpdatingConfig` is `False`:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.status.conditions[?(@.type=="UpdatingConfig")].status}'
   ```
   Expected: `False`.

   Record baseline node names (on the hosted cluster):
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=upgrade-seed-test -o jsonpath='{.items[*].metadata.name}'
   ```
   Record as `BASELINE_NODES`.

3. **Simulate pre-upgrade state by removing the rollout config annotation:**
   ```
   oc annotate nodepool upgrade-seed-test -n <hc-namespace> \
     hypershift.openshift.io/nodePoolCurrentRolloutConfig-
   ```

4. **Force a reconciliation via a dummy annotation:**
   ```
   oc annotate nodepool upgrade-seed-test -n <hc-namespace> \
     hypershift.openshift.io/e2e-reconcile-trigger="$(date +%s)" --overwrite
   ```

5. **Wait for the controller to re-seed the rollout config annotation (up to 1 minute):**

   Poll every 10 seconds:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentRolloutConfig}'
   ```
   Expected: a non-empty value appears within 1 minute.

6. **Verify no rollout was triggered (observe over 2 minutes, every 15 seconds):**

   a. `UpdatingConfig` condition remains `False`:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.status.conditions[?(@.type=="UpdatingConfig")].status}'
   ```
   Expected: `False`.

   b. `nodePoolCurrentConfig` annotation is unchanged:
   ```
   oc get nodepool upgrade-seed-test -n <hc-namespace> -o jsonpath='{.metadata.annotations.hypershift\.openshift\.io/nodePoolCurrentConfig}'
   ```
   Expected: equals `BASELINE_CONFIG_HASH`.

   c. Node count unchanged (on the hosted cluster):
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=upgrade-seed-test --no-headers | wc -l
   ```
   Expected: same count as baseline.

7. **Verify node identity is preserved:**
   ```
   oc get nodes -l hypershift.openshift.io/nodePool=upgrade-seed-test -o jsonpath='{.items[*].metadata.name}'
   ```
   Expected: identical set to `BASELINE_NODES` (no replacements occurred).

8. **Clean up:**
   ```
   oc delete nodepool upgrade-seed-test -n <hc-namespace>
   ```

**Pass criteria:** Rollout config annotation is re-seeded within 1 minute; no rollout triggered; `UpdatingConfig` stays `False`; node identities unchanged; full config hash unchanged.

**Fail criteria:** Annotation is not re-seeded within 1 minute; `UpdatingConfig` becomes `True`; nodes are replaced; config hash changes.

---

## 7. Pass/Fail Criteria

### 7.1 Overall Pass

All three test cases (TC-001, TC-002, TC-003) pass their individual criteria as defined in Sections 6.4-6.6, via either automated execution (preferred) or documented manual fallback.

### 7.2 Overall Fail

Any single test case fails its criteria.

### 7.3 Evidence Requirements

**Automated execution (primary):**
- CI JUnit XML reports showing pass/fail status for `ManagementImageChangeNoRolloutTest`, `SpecDrivenChangeTriggersRolloutTest`, and `OperatorUpgradeNoRolloutTest`.
- Ginkgo test output logs (available in CI artifacts) containing `By` step annotations and assertion results.
- Unit test results from `go test ./hypershift-operator/controllers/nodepool/...` showing pass counts for all related test functions.

**Manual fallback execution:**
- Written justification of why automated execution was infeasible.
- Screenshots or terminal output of all `oc get` commands showing annotation values and condition statuses.
- Timestamped logs of the 2-minute observation windows (for TC-001 and TC-003).
- Before/after annotation values for TC-002 demonstrating the hash change.
- Node name lists before and after the test action for TC-001 and TC-003.

---

## 8. Suspension and Resumption Criteria

### 8.1 Suspension Criteria

- CI infrastructure is unavailable or the e2e test suite cannot be triggered.
- The HyperShift management cluster becomes unavailable or the HostedCluster enters a degraded state.
- The NodePool controller is crash-looping or not reconciling (operator pod not running).
- Infrastructure issues prevent node provisioning (cloud provider quota, networking).

### 8.2 Resumption Criteria

- CI infrastructure is restored and the e2e test suite can be triggered.
- The management cluster and HostedCluster are restored to a healthy, operational state.
- The HyperShift operator pod is running and reconciling NodePools.
- Any test NodePools created during a suspended test run are cleaned up before resuming.
- If automated execution was suspended, re-run the full automated suite before falling back to manual procedures.

---

## 9. Test Deliverables

| Deliverable | Description |
|-------------|-------------|
| This test plan | `plans/ocpstrat-3298.md` |
| Automated e2e results | CI JUnit reports for `ManagementImageChangeNoRolloutTest`, `SpecDrivenChangeTriggersRolloutTest`, `OperatorUpgradeNoRolloutTest` |
| Automated unit test results | `go test` output for `capi_test.go`, `conditions_test.go`, `config_test.go`, `nodepool_controller_test.go` |
| Fallback execution log (if used) | Justification for manual fallback; timestamped record of all commands and outputs |
| Pass/fail summary | Per-test-case verdict with evidence references (CI artifact links or manual evidence) |
| Defect reports | Jira issues filed for any failures, linked to OCPSTRAT-3298 |

---

## 10. Test Environment

### 10.1 Automated Execution Environment

| Component | Requirement |
|-----------|-------------|
| CI system | HyperShift CI with `e2ev2` build tag support |
| Management cluster | OpenShift cluster running the HyperShift operator with PR #8698 changes |
| HostedCluster | At least one operational HostedCluster with a default NodePool |
| Platform | AWS, Azure, or other supported platform (**not** KubeVirt for TC-002) |
| Test framework | Ginkgo v2 with `e2ev2` build tag; `go test` for unit tests |

### 10.2 Manual Fallback Environment

| Component | Requirement |
|-----------|-------------|
| Management cluster | OpenShift cluster running the HyperShift operator with PR #8698 changes |
| HostedCluster | At least one operational HostedCluster with a default NodePool |
| Platform | AWS, Azure, or other supported platform (**not** KubeVirt for TC-002) |
| CLI tools | `oc` or `kubectl` with cluster-admin access to management cluster; kubeconfig for hosted cluster |

### 10.3 Platform Exclusions

- **KubeVirt:** TC-002 (spec-driven rollout) must be skipped on KubeVirt platform pending resolution of [CNV-38196](https://issues.redhat.com/browse/CNV-38196). TC-001 and TC-003 are platform-agnostic.

---

## 11. Responsibilities and Roles

| Role | Responsibility |
|------|---------------|
| Test author | Created this plan based on PR #8698 implementation and automated test suite |
| CI system | Executes the automated e2e and unit tests as the primary verification method |
| QE engineer | Reviews CI results; executes manual fallback procedures only when automation is infeasible; captures evidence; reports results |
| Feature developer | Provides clarification on expected behavior; reviews test results |
| QE lead | Reviews and approves this test plan; triages any failures; approves manual fallback justifications |

---

## 12. Schedule and Milestones

| Milestone | Timing |
|-----------|--------|
| Test plan review | Before PR #8698 merges |
| Automated unit test validation | Continuous — runs on every PR update via CI |
| Automated e2e test validation | Continuous — runs in HyperShift CI after operator image build |
| Manual fallback execution (if needed) | Within one sprint of operator image availability; only if automated tests cannot run |
| Results reporting | Within 2 business days of automated test completion (or manual fallback execution) |

---

## 13. Risks and Contingencies

| Risk | Impact | Mitigation |
|------|--------|------------|
| CI environment unavailable | Automated tests cannot run; delays verification | Fall back to manual procedures with documented justification; re-run automated suite when CI is restored |
| Acceptance criteria change before merge | Test-case-to-AC mapping becomes stale | Re-verify AC mapping against OCPSTRAT-3298 if requirements are revised |
| PR #8698 not yet merged | Feature may change before merge | Re-review test plan if PR is substantially revised |
| E2e test flakiness | False failures block verification | Review Ginkgo logs for flaky assertions; re-run automated suite; file flake reports if pattern persists |
| NodePool provisioning timeouts | Automated test execution delayed | Use pre-existing NodePools for TC-001; allow 20+ minute timeouts for TC-002/TC-003 |
| KubeVirt platform exclusion | Reduced coverage | Track CNV-38196; add KubeVirt coverage when resolved |
| Annotation key changes before merge | Automated tests and manual commands use wrong annotation names | Verify annotation keys against merged code before execution |
| Manual fallback without equivalent evidence | Reduced confidence in results | QE lead must review and approve that fallback evidence meets the same assertion criteria as automated tests |

---

## 14. Approval and Exit Criteria

### 14.1 Approval

This test plan requires review and approval from the QE lead and the feature developer before test execution begins.

### 14.2 Exit Criteria

Testing is considered complete when:

1. All three e2e tests (`ManagementImageChangeNoRolloutTest`, `SpecDrivenChangeTriggersRolloutTest`, `OperatorUpgradeNoRolloutTest`) pass in CI on at least one supported platform, **OR** equivalent manual fallback results are approved with documented justification.
2. Unit tests in `capi_test.go`, `conditions_test.go`, `config_test.go`, and `nodepool_controller_test.go` pass with zero failures.
3. All pass criteria are met, or defects have been filed for any failures.
4. Test execution evidence (CI JUnit reports or manual logs) has been archived.
5. Results have been reported to the feature team.
6. Any filed defects have been linked to the feature Jira ([OCPSTRAT-3298](https://issues.redhat.com/browse/OCPSTRAT-3298)).
