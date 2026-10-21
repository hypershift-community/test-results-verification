---
id: TP-EXAMPLE-001
version: "1.0"
date: 2026-09-10
title: "Example Feature — Sanitized Test Plan"
jira_issues:
  - key: OCPSTRAT-0000
    role: primary
    url: https://issues.redhat.com/browse/OCPSTRAT-0000
  - key: OCPBUGS-00001
    role: backport
    url: https://issues.redhat.com/browse/OCPBUGS-00001
pull_requests:
  - repo: openshift/hypershift
    number: 9999
    url: https://github.com/openshift/hypershift/pull/9999
    role: implementation
  - repo: openshift/hypershift
    number: 10000
    url: https://github.com/openshift/hypershift/pull/10000
    role: backport
status: draft
tags:
  - example
  - nodepool
ieee_829: true
author: HyperShift Team
---

# Test Plan: Example Feature

> **This is a sanitized example using the IEEE 829 profile** (`ieee_829: true`).
> All identifiers, cluster names, and data are fictional. Use this file as a
> reference when writing new IEEE 829-style plans. For preserved legacy plans, see the
> [lightweight template](../docs/format.md#lightweight-template-default) in
> the format specification.

## 1. Test Plan Identifier

**ID:** TP-EXAMPLE-001
**Version:** 1.0
**Date:** 2026-09-10
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This test plan defines the verification strategy for the **Example Feature**
in HyperShift. The feature adds a new reconciliation mode to the NodePool
controller that improves handling of configuration drift.

### 2.2 Objectives

1. Verify that the new reconciliation mode correctly detects configuration
   drift between the desired and actual node state.
2. Verify that the controller takes the expected corrective action when drift
   is detected.
3. Verify that the feature does not regress existing NodePool lifecycle
   behavior.

### 2.3 Acceptance Criteria Mapping

| OCPSTRAT-0000 Acceptance Criterion | Test Case |
|-------------------------------------|-----------|
| AC #1 — Controller detects configuration drift | TC-001 (Section 5.1) |
| AC #2 — Corrective action is taken | TC-002 (Section 5.2) |
| AC #3 — No regression in standard lifecycle | TC-003 (Section 5.3) |

### 2.4 Automation-First Principle

The primary verification method for every test case is the automated test
suite delivered with the implementation PR. Manual execution is a fallback
only.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#9999](https://github.com/openshift/hypershift/pull/9999) |
| Backport PR | [openshift/hypershift#10000](https://github.com/openshift/hypershift/pull/10000) |
| E2E test file | `test/e2e/v2/tests/example_feature_test.go` |
| Controller code | `hypershift-operator/controllers/nodepool/example.go` |
| Feature Jira | [OCPSTRAT-0000](https://issues.redhat.com/browse/OCPSTRAT-0000) |
| Backport Jira | [OCPBUGS-00001](https://issues.redhat.com/browse/OCPBUGS-00001) |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster |
| Management cluster | `example-mgmt` (placeholder) |
| OCP version | 4.18+ |
| Platform | AWS (`us-east-1`, placeholder) |
| Prerequisites | `hypershift` CLI, `oc` CLI, valid kubeconfig |

---

## 5. Test Cases

### 5.1 TC-001: Configuration Drift Detection

**Objective:** Verify the controller detects when the actual node
configuration diverges from the desired spec.

**Preconditions:**
- A HostedCluster is created and in a `Ready` state.
- A NodePool exists with at least one running node.

**Primary method (automated):**
- Test: `TestExampleFeatureDriftDetection` in
  `test/e2e/v2/tests/example_feature_test.go`
- Run: `make e2e TEST_NAME=TestExampleFeatureDriftDetection`

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a HostedCluster and NodePool | Cluster and NodePool reach `Ready` |
| 2 | Modify the node configuration outside the spec | Controller sets `ConfigDriftDetected` condition to `True` |
| 3 | Verify the condition message | Message includes the drifted field name |

---

### 5.2 TC-002: Corrective Action on Drift

**Objective:** Verify the controller takes corrective action when drift
is detected.

**Preconditions:**
- TC-001 preconditions met.
- Configuration drift has been introduced.

**Primary method (automated):**
- Test: `TestExampleFeatureCorrectiveAction`
- Run: `make e2e TEST_NAME=TestExampleFeatureCorrectiveAction`

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Trigger configuration drift (as in TC-001) | `ConfigDriftDetected` condition is `True` |
| 2 | Wait for the next reconciliation cycle | Controller initiates a rolling update |
| 3 | Verify nodes are replaced | New nodes match the desired spec |
| 4 | Verify condition is cleared | `ConfigDriftDetected` condition is `False` |

---

### 5.3 TC-003: No Regression in Standard Lifecycle

**Objective:** Verify that the feature does not break standard NodePool
create, scale, and delete operations.

**Primary method (automated):**
- Test: `TestNodePoolLifecycle` (existing test, unmodified)
- Run: `make e2e TEST_NAME=TestNodePoolLifecycle`

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a NodePool with 2 replicas | 2 nodes join the cluster |
| 2 | Scale to 3 replicas | 1 additional node joins |
| 3 | Scale to 1 replica | 2 nodes are removed |
| 4 | Delete the NodePool | All nodes are removed, NodePool is deleted |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Drift detection triggers false positives during upgrades | Medium | High | TC-001 includes an upgrade scenario variant |
| Corrective action causes unnecessary node churn | Low | Medium | TC-002 asserts that only drifted nodes are replaced |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | (example) | 2026-09-10 |
| Reviewer | (example) | — |
