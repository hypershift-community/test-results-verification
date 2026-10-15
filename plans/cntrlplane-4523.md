---
id: TP-CNTRLPLANE-4523-001
version: "1.0"
date: 2026-10-15
title: "Surface Persistent Infrastructure Failures in NodePool AllMachinesReady Condition"
jira_issues:
  - key: CNTRLPLANE-4523
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-4523
  - key: CNTRLPLANE-4522
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-4522
  - key: CNTRLPLANE-4747
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-4747
pull_requests:
  - repo: openshift/hypershift
    number: 9781
    url: https://github.com/openshift/hypershift/pull/9781
    role: implementation
status: draft
tags:
  - nodepool
  - conditions
  - infrastructure-failure
  - allmachinesready
  - machine-status
  - multi-platform
ieee_829: true
author: sdminonne
---

# Test Plan: Surface Persistent Infrastructure Failures in NodePool AllMachinesReady Condition

## 1. Test Plan Identifier

**ID:** TP-CNTRLPLANE-4523-001
**Version:** 1.0
**Date:** 2026-10-15
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This plan defines the verification strategy for surfacing **persistent
infrastructure failures** in the NodePool `AllMachinesReady` condition.

When CAPI Machines fail due to cloud-provider problems (quota exhaustion,
invalid credentials, capacity shortages, terminated instances), the
NodePool's `AllMachinesReady` condition previously stayed `False` with a
generic reason like `WaitingForInfrastructure`. Users could not
distinguish "still provisioning normally" from "terminally failed, user
must act" without inspecting individual Machine objects.

This feature adds a new `InfrastructureFailure` reason to the existing
`AllMachinesReady` condition. Terminal failures are detected using explicit
per-platform reason sets matched against the Machine's v1beta2
`ReadyCondition.Reason`. Classification is based solely on condition
reasons; message text is not a stable contract and is never used for
terminal detection.

Key capabilities under test:

- `InfrastructureFailure` reason on `AllMachinesReady` condition when
  machines have persistent cloud failures
- Per-platform terminal reason detection (AWS, Azure, IBMCloud, PowerVS,
  OpenStack, KubeVirt)
- Transient/self-healing failures preserve existing reason behavior
- Condition self-heals when machines recover
- Aggregated messages include machine names and cloud error text
- Rate limiter max delay increased from 10s to 5m to reduce reconcile
  pressure on persistent failures

### 2.2 Objectives

1. Verify that terminal infrastructure reasons on each supported platform
   produce `InfrastructureFailure` on `AllMachinesReady`.
2. Verify that transient/self-healing reasons (`WaitingForInfrastructure`,
   `Deleting`) preserve their existing behavior (no `InfrastructureFailure`).
3. Verify that mixed scenarios (some terminal, some transient) report
   `InfrastructureFailure` when at least one terminal failure exists.
4. Verify that the condition clears to `AsExpected` when machines recover.
5. Verify that aggregated messages include per-machine names and error text.
6. Verify that platforms without registered terminal reasons pass through
   provider reasons unchanged.
7. Verify the rate limiter max delay change does not break reconciliation.

### 2.3 Acceptance Criteria Mapping

| Acceptance Criterion | Test Cases |
|----------------------|------------|
| AC #1 — `InfrastructureFailure` shown for persistent cloud failures | TC-001 through TC-005 (Section 5.1) |
| AC #2 — Transient/self-healing failures keep existing reasons | TC-006, TC-007 (Section 5.2) |
| AC #3 — Condition clears when machines recover | TC-008 (Section 5.2) |
| AC #4 — Mixed failures produce `InfrastructureFailure` | TC-009 (Section 5.3) |
| AC #5 — Message includes machine name and cloud error text | TC-010 (Section 5.3) |
| AC #6 — Unregistered platforms pass through reasons unchanged | TC-011 (Section 5.4) |
| AC #7 — Observable via `oc get nodepool` in a real cluster | TC-012 (Section 5.5) |
| AC #8 — Rate limiter max delay increased to 5m | TC-013 (Section 5.6) |

### 2.4 Automation-First Principle

The primary verification method for every test case is the automated unit
test suite delivered with the implementation PR
(`TestSetMachineAndNodeConditions` — 27 cases). Manual execution is a
fallback only.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#9781](https://github.com/openshift/hypershift/pull/9781) |
| API constant | `api/hypershift/v1beta1/nodepool_conditions.go` — `NodePoolInfrastructureFailureReason` |
| Condition logic | `hypershift-operator/controllers/nodepool/conditions.go` — `setAllMachinesReadyCondition`, `isTerminalInfraReason`, `terminalInfraReasons` |
| Rate limiter | `hypershift-operator/controllers/nodepool/nodepool_controller.go` — `SetupWithManager` |
| Unit tests | `hypershift-operator/controllers/nodepool/nodepool_controller_test.go` — `TestSetMachineAndNodeConditions` |
| Epic | [CNTRLPLANE-4523](https://issues.redhat.com/browse/CNTRLPLANE-4523) |
| Story | [CNTRLPLANE-4522](https://issues.redhat.com/browse/CNTRLPLANE-4522) |

**Design notes:**

- Terminal reasons are provider-owned and platform-scoped. Each provider
  emits its own set of reasons on the `InfrastructureReady` condition,
  which CAPI best-effort-converts into the Machine's v1beta2
  `ReadyCondition` reason.
- The deprecated `Machine.Status.FailureReason`/`FailureMessage` fields
  and the `MachineHasFailure` v1beta1 reason are not consulted (per
  upstream CAPI proposal 20240916-improve-status-in-CAPI-resources).
- No new condition types, CRD fields, or feature gates are introduced.

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster |
| Platforms | AWS, Azure, IBMCloud, PowerVS, OpenStack, KubeVirt |
| OCP version | 4.18+ / 5.1+ |
| Prerequisites | `hypershift` CLI, `oc` CLI |

### CI Execution Strategy

All test cases are covered by the unit test suite
`TestSetMachineAndNodeConditions` in presubmit CI. No new E2E tests are
introduced — the condition is verified via unit tests with synthetic
Machine objects.

**Unit tests (1 suite, presubmit):**

| Suite | TCs Covered | CI Tier |
|-------|-------------|---------|
| `TestSetMachineAndNodeConditions` | TC-001 through TC-011 | Presubmit |

**Manual verification (1 scenario):**

| Scenario | TCs Covered | CI Tier |
|----------|-------------|---------|
| Observe condition via `oc get nodepool -o yaml` | TC-012 | Manual |

---

## 5. Test Cases

### 5.1 Terminal Infrastructure Failures — Per-Platform

#### 5.1.1 TC-001: AWS InstanceTerminated Produces InfrastructureFailure

**Objective:** Verify that an AWS Machine with `ReadyCondition.Reason =
InstanceTerminated` causes `AllMachinesReady` to report
`InfrastructureFailure`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When AWS machine has
  InstanceTerminated reason it should report InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on AWS platform | NodePool created |
| 2 | Simulate a Machine with `ReadyCondition` status `False`, reason `InstanceTerminated` | Machine reflects terminal state |
| 3 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InfrastructureFailure`, message includes machine name and `InstanceTerminated` text |

---

#### 5.1.2 TC-002: AWS InstanceProvisionFailed Produces InfrastructureFailure

**Objective:** Verify that an AWS Machine with `ReadyCondition.Reason =
InstanceProvisionFailed` causes `AllMachinesReady` to report
`InfrastructureFailure`, regardless of the message text.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When AWS machine has
  InstanceProvisionFailed reason it should report InfrastructureFailure
  regardless of message"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on AWS platform | NodePool created |
| 2 | Simulate a Machine with `ReadyCondition` status `False`, reason `InstanceProvisionFailed`, message `failed to create instance: some API error` | Machine reflects failure |
| 3 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InfrastructureFailure` |

---

#### 5.1.3 TC-003: Azure VMProvisionFailed Produces InfrastructureFailure

**Objective:** Verify that an Azure Machine with `ReadyCondition.Reason =
VMProvisionFailed` causes `AllMachinesReady` to report
`InfrastructureFailure`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When Azure machine has
  VMProvisionFailed reason it should report InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on Azure platform | NodePool created |
| 2 | Simulate a Machine with `ReadyCondition` status `False`, reason `VMProvisionFailed`, message `failed to create VM: quota exceeded` | Machine reflects failure |
| 3 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InfrastructureFailure`, message includes `VMProvisionFailed: failed to create VM: quota exceeded` |

---

#### 5.1.4 TC-004: IBMCloud/PowerVS Terminal Reasons

**Objective:** Verify that IBMCloud and PowerVS Machines with
`InstanceProvisionFailed` or `InstanceErrored` reasons produce
`InfrastructureFailure`.

**Primary method (automated):**
- Covered by `isTerminalInfraReason` through the `terminalInfraReasons`
  map which registers both reasons for `IBMCloudPlatform` and
  `PowerVSPlatform`.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on IBMCloud platform | NodePool created |
| 2 | Simulate a Machine with reason `InstanceProvisionFailed` | `AllMachinesReady` reason is `InfrastructureFailure` |
| 3 | Simulate a Machine with reason `InstanceErrored` | `AllMachinesReady` reason is `InfrastructureFailure` |
| 4 | Repeat steps 1-3 for PowerVS platform | Same results |

---

#### 5.1.5 TC-005: OpenStack and KubeVirt Terminal Reasons

**Objective:** Verify that OpenStack Machines with `InstanceCreateFailed`
or `InstanceStateError`, and KubeVirt Machines with `VMCreateFailed`,
produce `InfrastructureFailure`.

**Primary method (automated):**
- Covered by `isTerminalInfraReason` through the `terminalInfraReasons`
  map which registers the appropriate reasons for each platform.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on OpenStack platform | NodePool created |
| 2 | Simulate a Machine with reason `InstanceCreateFailed` | `AllMachinesReady` reason is `InfrastructureFailure` |
| 3 | Simulate a Machine with reason `InstanceStateError` | `AllMachinesReady` reason is `InfrastructureFailure` |
| 4 | Create a NodePool on KubeVirt platform | NodePool created |
| 5 | Simulate a Machine with reason `VMCreateFailed` | `AllMachinesReady` reason is `InfrastructureFailure` |

---

### 5.2 Transient Failures and Recovery

#### 5.2.1 TC-006: WaitingForInfrastructure Does Not Produce InfrastructureFailure

**Objective:** Verify that an AWS Machine with `ReadyCondition.Reason =
WaitingForInfrastructure` does NOT produce `InfrastructureFailure` — it is
a normal lifecycle state.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When only
  WaitingForInfrastructure machines exist on AWS it should not report
  InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool on AWS platform | NodePool created |
| 2 | Simulate a Machine with `ReadyCondition` status `False`, reason `WaitingForInfrastructure` | Machine in provisioning state |
| 3 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `WaitingForInfrastructure` (NOT `InfrastructureFailure`) |

---

#### 5.2.2 TC-007: Deleting Machine Does Not Produce InfrastructureFailure

**Objective:** Verify that a Machine in `Deleting` state does NOT produce
`InfrastructureFailure`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When machine is in Deleting
  state it should not report InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Simulate a Machine with `ReadyCondition` status `False`, reason `Deleting`, message `Waiting for machine volumes to be detached` | Machine in deletion state |
| 2 | Inspect NodePool conditions | `AllMachinesReady=False`, reason is `Deleting` (NOT `InfrastructureFailure`) |

---

#### 5.2.3 TC-008: Recovery From Infrastructure Failure Clears Condition

**Objective:** Verify that when a Machine recovers from an infrastructure
failure (ReadyCondition becomes True), `AllMachinesReady` returns to
`AsExpected`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When machine recovers from
  infrastructure failure it should return to AsExpected"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Simulate a Machine with `ReadyCondition` status `True` (recovered from failure) | Machine healthy |
| 2 | Inspect NodePool conditions | `AllMachinesReady=True`, reason `AsExpected`, message `All is well` |

---

### 5.3 Mixed Scenarios and Message Aggregation

#### 5.3.1 TC-009: Mixed Transient and Terminal Failures Produce InfrastructureFailure

**Objective:** Verify that when some Machines have transient failures and
at least one has a terminal failure, `AllMachinesReady` reports
`InfrastructureFailure`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When AWS machines mix
  transient and terminal failures it should report InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create 3 Machines on AWS: node1 with `WaitingForInfrastructure`, node2 with `InstanceProvisionFailed`, node3 `Ready` | Mixed state |
| 2 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InfrastructureFailure` |
| 3 | Verify message content | Message says "2 of 3 machines are not ready", lists both node1 and node2 with their respective reasons |

---

#### 5.3.2 TC-010: Large-Scale Aggregation With Multiple Failure Reasons

**Objective:** Verify that with many machines (e.g. 20) having different
failure reasons including terminal ones, the condition correctly reports
`InfrastructureFailure` with aggregated messages.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When 10 of 20 machines are
  not ready with different reasons it should aggregate correctly"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create 20 Machines on AWS with mixed reasons: `NodeStartupTimeout`, `WaitingForInfrastructure`, `InstanceProvisionFailed`, `InstanceTerminated`, `MachineHasFailure` | Mixed failure state |
| 2 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InfrastructureFailure` |
| 3 | Verify message content | Message says "10 of 20 machines are not ready", lists failing machines with their reasons and cloud error messages |

---

### 5.4 Platform Without Terminal Reasons

#### 5.4.1 TC-011: Unregistered Platform Passes Through Reason Unchanged

**Objective:** Verify that when a Machine on a platform with no registered
terminal reasons has a failure reason (e.g. `InstanceProvisionFailed` on
`NonePlatform`), the reason passes through unchanged — NOT
`InfrastructureFailure`.

**Primary method (automated):**
- Test: `TestSetMachineAndNodeConditions` / "When platform has no terminal
  reasons a provider failure reason should not report
  InfrastructureFailure"

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Simulate a Machine on a platform with no terminal reasons with `ReadyCondition` reason `InstanceProvisionFailed` | Machine reflects failure |
| 2 | Inspect NodePool conditions | `AllMachinesReady=False`, reason `InstanceProvisionFailed` (NOT `InfrastructureFailure`) |

---

### 5.5 End-to-End Observability

#### 5.5.1 TC-012: Condition Observable via oc get nodepool

**Objective:** Verify that the `InfrastructureFailure` reason is visible
via `oc get nodepool -o yaml` in a cluster experiencing a real
quota/capacity failure.

**Preconditions:**
- A HostedCluster with a NodePool on a supported platform.
- A cloud-provider condition that causes persistent machine failure (e.g.
  quota exhaustion, invalid instance type).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool requesting an instance type that does not exist or exceeds quota | Machine provisioning fails |
| 2 | Wait for the NodePool controller to reconcile | Condition updated |
| 3 | Run `oc get nodepool <name> -o yaml` | `AllMachinesReady` condition shows `status: "False"`, `reason: InfrastructureFailure`, message includes machine name and cloud error |
| 4 | Fix the underlying issue (e.g. increase quota, fix instance type) | Machine provisioning succeeds |
| 5 | Verify condition clears | `AllMachinesReady` returns to `status: "True"`, `reason: AsExpected` |

---

### 5.6 Rate Limiter

#### 5.6.1 TC-013: Rate Limiter Max Delay Increased to 5 Minutes

**Objective:** Verify that the NodePool controller rate limiter max delay
is 5 minutes (changed from 10 seconds) to reduce reconcile pressure on
persistent failures.

**Primary method (code review):**
- File: `hypershift-operator/controllers/nodepool/nodepool_controller.go`
- Change: `NewTypedItemExponentialFailureRateLimiter` max delay argument
  changed from `10*time.Second` to `5*time.Minute`.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Introduce a persistent failure on a NodePool | Controller starts reconciling |
| 2 | Observe reconciliation intervals over time | Back-off increases exponentially, capping at 5 minutes (not 10 seconds) |
| 3 | Resolve the failure | Controller returns to normal reconciliation cadence |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CAPI providers change ReadyCondition reason strings | Low | High | Terminal reasons are provider-owned constants; monitor upstream CAPI releases for reason renames |
| New platform added without terminal reasons registered | Medium | Low | `isTerminalInfraReason` returns false for unknown platforms — falls back to existing behavior |
| Rate limiter 5m cap delays recovery detection | Low | Medium | Rate limiter resets on successful reconciliation; only affects persistent-failure backoff |
| Terminal reason false positive on a genuinely transient failure | Low | High | Reason classification is conservative — only reasons known to be terminal are registered |
| TC-012 manual verification requires specific cloud quota conditions | Medium | Low | Can be triggered with an invalid instance type; automated unit tests cover the logic |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | sdminonne | 2026-10-15 |
| Reviewer | | |
