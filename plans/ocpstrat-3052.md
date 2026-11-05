---
id: TP-OCPSTRAT-3052-001
version: "1.0"
date: 2026-11-05
title: "Ignition System Re-Architecture — Split Generation from Serving"
jira_issues:
  - key: OCPSTRAT-3052
    role: primary
    url: https://issues.redhat.com/browse/OCPSTRAT-3052
status: draft
tags:
  - ignition
  - nodepool
  - techpreview
  - rollout
ieee_829: true
---

# Test Plan: Ignition System Re-Architecture — Split Generation from Serving

## 1. Test Plan Identifier

**ID:** TP-OCPSTRAT-3052-001
**Version:** 1.0
**Date:** 2026-11-05
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard for
Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

OCPSTRAT-3052 re-architects the HyperShift ignition subsystem by splitting it
into two independently-scaled roles:

- **Generation** — a leader-elected singleton controller that renders, hashes,
  and signs each NodePool's ignition payload and publishes it to a payload
  store, exposing per-NodePool state through an `IgnitionPayload` custom
  resource.
- **Serving** — a stateless, horizontally-scalable server that verifies a
  booting node's signed bearer token and serves the matching payload from the
  store.

Under a management-cluster feature gate (`IgnitionPayloadSystem`, delivered as
`TechPreviewNoUpgrade`, default **OFF**), the **HyperShift Operator (HO)** owns
the full ignition stack (generator, server, proxy), while the **Control Plane
Operator (CPO)** stands its legacy monolithic ignition-server down via
feature-set mutual exclusion. When the gate is OFF, behavior is the current
(legacy) ignition path.

A central design guarantee is **fleet safety on enablement**: turning the gate
on for an already-running cluster must *adopt* its NodePools without triggering
a Machine rollout.

### 2.2 Objectives

1. Verify that, under the gate, the HO deploys the split generation/serving
   stack and the CPO stands down its legacy ignition-server (no dual
   ownership, no flapping).
2. Verify that a booting node fetches its payload from the new serving tier
   using a signed bearer token.
3. Verify that enabling the gate on an existing (legacy) cluster adopts its
   NodePools **without** re-pointing userdata or recreating Machines.
4. Verify rollout policy: a rollout-relevant change rolls the pool; a
   management-side-only change refreshes the served payload **without** rolling
   (Policy A).
5. Verify that teardown cascades CR-owned objects and frees payload-store
   entries, while leaving referenced-in-place core configuration intact.

### 2.3 Acceptance Criteria Mapping

| ID | Acceptance Criterion | Test Case(s) |
|----|----------------------|--------------|
| C1 | Generation (leader-elected singleton) is split from serving (stateless, scaled); the HO owns both under the gate; the CPO stands down. | TC-001, TC-004 |
| C2 | A booting node fetches its payload from the new serving tier with a signed bearer token. | TC-001, TC-003, TC-004 |
| C3 | Enabling the gate on an existing cluster adopts NodePools without rolling (no userdata re-point, no Machine recreation). | TC-002 |
| C4 | A rollout-relevant change rolls; a management-side-only change refreshes served content without rolling (Policy A). | TC-005, TC-006 |
| C5 | Teardown cascades CR-owned objects; payload-store entries are freed; referenced-in-place core configs are left intact. | TC-007 |

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Feature Jira | [OCPSTRAT-3052](https://issues.redhat.com/browse/OCPSTRAT-3052) |
| Enhancement | HyperShift enhancement — *ignition system re-architecture* |
| Implementation | Phased, stacked pull-request series (pre-merge) |
| Activation | `IgnitionPayloadSystem` management feature gate (`TechPreviewNoUpgrade`), default OFF |
| New API | `IgnitionPayload` custom resource (per NodePool) in the hosted control-plane namespace |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster on AWS, `PublicAndPrivate` endpoint access |
| Control-plane / release | OCP 5.1 (pre-release) |
| NodePool upgrade type | Replace |
| NodePool health | autoRepair enabled |
| Activation | `IgnitionPayloadSystem` via `TechPreviewNoUpgrade` |
| Baseline (gate OFF) | Legacy ignition path — unchanged from current behavior |

---

## 5. Test Cases

### 5.1 TC-001: Fresh new-model deployment (gate ON from creation)

**Objective:** Verify the HO deploys the split stack, the CPO stands down, and
nodes boot via the new serving tier. *(C1, C2)*

**Preconditions:**
- Management cluster running with the `IgnitionPayloadSystem` gate ON and the
  `IgnitionPayload` CRD installed.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a HostedCluster with a Replace NodePool. | HO reconciles generator, server, and proxy as control-plane components; the serving Deployment runs the new payload-server command. |
| 2 | Inspect the CPO. | CPO carries the tech-preview feature set and does **not** own `ignition-server` (no image/command flapping). |
| 3 | Inspect the per-NodePool `IgnitionPayload` CR. | `PayloadGenerated=True`; `status.current` references a generator-authored userdata Secret. |
| 4 | Wait for the NodePool nodes to join. | Nodes boot by fetching the payload from the new serving tier (signed bearer token); `IgnitionReached=True`. |

---

### 5.2 TC-002: No-roll adoption on gate enablement

**Objective:** Verify enabling the gate on an existing legacy cluster adopts
the running NodePool without rolling it. *(C3)*

**Preconditions:**
- A HostedCluster created with the gate **OFF** (legacy path), nodes joined and
  the NodePool settled.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record baseline: NodePool userdata Secret name, infrastructure (machine) template name, and Machine names/creation timestamps. | Baseline captured. |
| 2 | Enable the gate (HO restarts with the feature set on). | CPO is redeployed with the tech-preview feature set and stands its ignition-server down; the HO brings up the split stack; a per-NodePool `IgnitionPayload` CR is generated. |
| 3 | Compare live state against the baseline. | Userdata Secret name **unchanged**; infrastructure template **unchanged**; **no** Machine recreated (same names and creation timestamps). |
| 4 | Inspect the NodePool and the adopted userdata Secret. | NodePool gains a one-time deployed-generation baseline annotation; the existing userdata Secret is now owned by the `IgnitionPayload` CR and its content is swapped in place to the new-model signed-token format. |

---

### 5.3 TC-003: Scale-up after adoption boots via the new serving tier

**Objective:** Verify a node added after adoption boots on the new path while
existing nodes are untouched. *(C2)*

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scale the adopted NodePool up by one. | A new Machine is created referencing the adopted userdata Secret. |
| 2 | Wait for the new node to join. | The new node boots by fetching from the new serving tier; `IgnitionReached=True`. Existing Machines are unchanged. |

---

### 5.4 TC-004: New NodePool created under the gate (born on canonical naming)

**Objective:** Verify a NodePool created while the gate is ON is born directly
on the new model (not adopted). *(C1, C2)*

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a second NodePool while the gate is ON. | A dedicated `IgnitionPayload` CR is generated; the NodePool records the deployed-generation baseline immediately. |
| 2 | Inspect the NodePool's userdata reference. | Userdata is the generator's canonical name (not an adopted legacy name); no legacy-named userdata Secret is created. |
| 3 | Wait for the node to join. | The node boots via the new serving tier; `IgnitionReached=True`; autoRepair health checking is created. |

---

### 5.5 TC-005: Rollout-relevant configuration change rolls

**Objective:** Verify a rollout-relevant change rolls the pool. *(C4)*

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Apply a user MachineConfig change to the NodePool. | The payload's rollout generation advances; a new canonical userdata Secret is produced. |
| 2 | Observe the MachineDeployment. | It is re-pointed to the new userdata; new Machines roll and old Machines drain. |
| 3 | After the rollout drains. | At most two payloads are retained (current + previous); the superseded payload and its userdata Secret are freed. |

---

### 5.6 TC-006: Management-side-only change refreshes without rolling (Policy A)

**Objective:** Verify a management-side-only change refreshes served content
without rolling the fleet. *(C4)*

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Trigger a management-side-only content refresh (no change to node rollout identity). | The served payload's config hash changes; the rollout generation is **unchanged**. |
| 2 | Observe the NodePool. | Userdata Secret name unchanged; **no** Machine recreated. |
| 3 | Scale up by one. | The new node boots with the refreshed content; existing nodes are untouched. |

> Endpoint-identity changes (e.g. Public/Private transition, API-server
> address/port) are the deliberate exception and **must** roll; they are folded
> into the rollout identity.

---

### 5.7 TC-007: Teardown and cascade cleanup

**Objective:** Verify deletion cascades CR-owned objects and frees payload
storage. *(C5)*

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Delete a NodePool. | The consumer and store-cleanup finalizers are cleared and the `IgnitionPayload` CR is removed. |
| 2 | Inspect the hosted control-plane namespace. | CR-owned projected ConfigMaps and generator-authored userdata Secrets cascade-delete; payload-store entries are freed. |
| 3 | Inspect referenced-in-place core/tuning configs. | Configs with no owner reference are left intact. No leaked payload Secrets remain. |

---

## 6. Risks and Mitigations

| Risk | Mitigation | Verified by |
|------|------------|-------------|
| Enabling the gate rolls every NodePool on the fleet (disruptive). | One-time deployed-generation baseline makes adoption decisions generation-based, not hash-based, so the legacy↔new hash-formula difference cannot trigger a spurious roll. | TC-002 |
| Management-side churn (e.g. serving-tier image bumps) rolls the fleet. | Policy A separates rollout identity from served content; management-side changes refresh bytes in place. | TC-006 |
| Dual ownership of `ignition-server` during cutover. | CPO feature-set standdown hands ownership to the HO. | TC-001 |
| Orphaned payloads / userdata after rollout or deletion. | Bounded retention (current + previous) with drain-gated retirement, plus owner-reference and store-cleanup finalizers. | TC-005, TC-007 |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | | |
| Reviewer | | |
