---
id: TP-OCPSTRAT-2653-001
version: "1.0"
date: 2026-10-14
title: "Deterministic LoadBalancer IP Management for Hosted Control Planes"
jira_issues:
  - key: OCPSTRAT-2653
    role: primary
    url: https://issues.redhat.com/browse/OCPSTRAT-2653
  - key: CNTRLPLANE-4574
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-4574
  - key: CNTRLPLANE-4579
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-4579
pull_requests:
  - repo: openshift/enhancements
    number: 2117
    url: https://github.com/openshift/enhancements/pull/2117
    role: implementation
  - repo: openshift/hypershift
    number: 9913
    url: https://github.com/openshift/hypershift/pull/9913
    role: implementation
  - repo: openshift/hypershift
    number: 9898
    url: https://github.com/openshift/hypershift/pull/9898
    role: implementation
status: draft
tags:
  - loadbalancer
  - deterministic-ip
  - metalb
  - bare-metal
  - annotations
  - cel-validation
  - version-skew
ieee_829: true
author: jparrill
---

# Test Plan: Deterministic LoadBalancer IP Management for Hosted Control Planes

## 1. Test Plan Identifier

**ID:** TP-OCPSTRAT-2653-001
**Version:** 1.0
**Date:** 2026-10-14
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This plan defines the verification strategy for **Deterministic LoadBalancer
IP Management** in HyperShift. The feature allows users to pin a fixed IP on
the KAS (Kubernetes API Server) LoadBalancer Service via HostedCluster
annotations, preventing IP drift across lifecycle events on bare-metal and
on-prem deployments.

Key capabilities under test:

- Annotation passthrough from HostedCluster spec to KAS Service
- `loadBalancerClass` selection (MetalLB, F5, Cilium)
- Zero-rollout sidecar updates via SIGUSR2 (no pod restart on IP change)
- Ignition server `/kas-ip` endpoint for node IP discovery
- CEL validation enforcing an annotation allowlist
- Config hash stability across IP changes
- Version skew compatibility between HyperShift Operator and Control Plane Operator

### 2.2 Objectives

1. Verify annotations on `HostedCluster.spec` are passed through to the KAS
   Service and the LB acquires the specified IP.
2. Verify `loadBalancerClass` is correctly set on the KAS Service.
3. Verify IP changes trigger sidecar reload (SIGUSR2), not pod rollout.
4. Verify the `/kas-ip` ignition server endpoint returns the correct IP.
5. Verify CEL validation enforces the annotation allowlist (11 prefixes).
6. Verify config hash stability when only IP-related annotations change.
7. Verify no regression for existing HCs without LB annotations.
8. Verify version skew scenarios between old and new operator versions.

### 2.3 Acceptance Criteria Mapping

| Acceptance Criterion | Test Cases |
|----------------------|------------|
| AC #1 — Annotations passed through to KAS Service | TC-001, TC-003 (Section 5.1) |
| AC #2 — loadBalancerClass correctly set | TC-002 (Section 5.1) |
| AC #3 — No regression without annotations | TC-004 (Section 5.1) |
| AC #4 — IP change triggers SIGUSR2, no rollout | TC-005, TC-006, TC-007 (Section 5.2) |
| AC #5 — Config hash stable on IP change | TC-025, TC-026, TC-027 (Section 5.7) |
| AC #6 — CEL allowlist enforced | TC-019 through TC-024 (Section 5.6) |
| AC #7 — /kas-ip endpoint correct | TC-012 through TC-015 (Section 5.4) |
| AC #8 — Upgrade flow and condition transitions | TC-029 through TC-032 (Section 5.9) |
| AC #9 — Kubelet via HAProxy (prerequisite) | TC-016 through TC-018 (Section 5.5) |

### 2.4 Automation-First Principle

The primary verification method for every test case is the automated test
suite delivered with the implementation PRs. Manual execution is a fallback
only.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Enhancement proposal | [openshift/enhancements#2117](https://github.com/openshift/enhancements/pull/2117) |
| Implementation PR (API + CEL) | [openshift/hypershift#9913](https://github.com/openshift/hypershift/pull/9913) |
| Implementation PR (feature gate) | [openshift/hypershift#9898](https://github.com/openshift/hypershift/pull/9898) |
| Implementation PR (ignition server /kas-ip) | TBD — not yet implemented |
| Strategy Jira | [OCPSTRAT-2653](https://issues.redhat.com/browse/OCPSTRAT-2653) |
| Epic | [CNTRLPLANE-4574](https://issues.redhat.com/browse/CNTRLPLANE-4574) |
| E2E story | [CNTRLPLANE-4579](https://issues.redhat.com/browse/CNTRLPLANE-4579) |
| HAProxy prerequisite | [CNTRLPLANE-4732](https://issues.redhat.com/browse/CNTRLPLANE-4732) |

**Design notes:**

- `listType` on service annotations is `atomic` (not `map`), per review
  decision on PR #9913.
- Annotation allowlist uses 11 CEL-validated prefixes.
- Sidecar reload uses SIGUSR2 signal, avoiding full pod rollout.

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Bare-metal simulation | Agent platform with KubeVirt |
| Cloud provider | AWS |
| LB provider (CI) | MetalLB |
| OCP version | 4.18+ / 5.1+ |
| Prerequisites | `hypershift` CLI, `oc` CLI, MetalLB operator installed |
| FeatureGate | `DeterministicLBIP` |

### CI Execution Strategy

Test cases are consolidated to minimize E2E test count while maximizing
coverage. Unit and integration tests run in presubmit; heavier E2E
scenarios run in periodic jobs.

**E2E tests (3 total):**

| E2E Test | TCs Covered | Platform | CI Tier |
|----------|-------------|----------|---------|
| Full Day 1+2 lifecycle — create HC with MetalLB + LBclass, verify IP, change IP (no rollout + hash), non-IP annotation change, scale-up NP, InPlace upgrade | TC-001, 002, 003, 005, 006, 007, 008, 009, 016 | Agent/MetalLB | Presubmit |
| Upgrade flow — HO old→new, HC version upgrade, NPs pre-5.1, partial upgrade, condition transitions | TC-029, 030, 031, 032 (subsumes TC-010, 011) | Agent/MetalLB | Periodic |
| Cilium — create HC with Cilium LB IPAM annotations | TC-028 | Cilium | Periodic |

**Unit/integration tests (3 suites):**

| Suite | TCs Covered | CI Tier |
|-------|-------------|---------|
| CEL validation | TC-019 to TC-024 | Presubmit |
| Hash stability | TC-025 to TC-027 | Presubmit |
| /kas-ip HTTP handler | TC-012 to TC-015 | Presubmit |

**Covered by existing tests (no new E2E needed):**

| Scenario | TCs |
|----------|-----|
| AWS/private HC lifecycle without annotations | TC-004, TC-017, TC-018 |

---

## 5. Test Cases

### 5.1 Day 1 — Annotation Passthrough and loadBalancerClass

#### 5.1.1 TC-001: MetalLB Fixed IP via Service Annotation

**Objective:** Verify that a MetalLB IP-pool annotation on the HostedCluster
spec results in the KAS Service acquiring the specified fixed IP.

**Preconditions:**
- MetalLB operator installed on management cluster with an IPAddressPool.
- FeatureGate `DeterministicLBIP` enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `spec.services[kube-apiserver].servicePublishingStrategy.loadBalancer.serviceAnnotations` including MetalLB pool annotation and target IP | HC creation succeeds |
| 2 | Inspect the KAS Service in the HCP namespace | Service has the MetalLB annotation |
| 3 | Wait for LB IP assignment | Service `.status.loadBalancer.ingress[0].ip` matches the target IP |
| 4 | Verify KAS is reachable at the assigned IP | `oc --server=https://<ip>:6443 get ns` succeeds |

---

#### 5.1.2 TC-002: loadBalancerClass Passthrough

**Objective:** Verify that `loadBalancerClass` set on the HostedCluster is
propagated to the KAS Service.

**Preconditions:**
- A LoadBalancer controller that watches the target class is installed.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `spec.services[kube-apiserver].servicePublishingStrategy.loadBalancer.loadBalancerClass: "metallb.io/metallb"` | HC creation succeeds |
| 2 | Inspect the KAS Service | `.spec.loadBalancerClass` equals `metallb.io/metallb` |
| 3 | Verify MetalLB claims the Service | LB IP is assigned from the MetalLB pool |

---

#### 5.1.3 TC-003: Annotation Preservation Across Reconciliation

**Objective:** Verify that LB annotations on the KAS Service survive
controller reconciliation loops.

**Preconditions:**
- TC-001 preconditions met. HC created with LB annotations.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Note current annotations on the KAS Service | Annotations include the user-specified LB annotations |
| 2 | Trigger a reconciliation (e.g. update an unrelated HC field) | Reconciliation completes |
| 3 | Re-inspect the KAS Service annotations | LB annotations unchanged |
| 4 | Wait 5 minutes, inspect again | Annotations still preserved |

---

#### 5.1.4 TC-004: Legacy Behavior — No Annotations, No Regression

**Objective:** Verify that a HostedCluster created without any LB annotations
works identically to pre-feature behavior.

**Preconditions:**
- FeatureGate `DeterministicLBIP` enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC without any `serviceAnnotations` or `loadBalancerClass` | HC creation succeeds |
| 2 | Inspect the KAS Service | No unexpected annotations added, no `loadBalancerClass` set |
| 3 | Verify KAS is reachable | API server responds normally |
| 4 | Run standard NodePool lifecycle (create, scale, delete) | All operations succeed |

---

### 5.2 Day 2 — Sidecar Zero-Rollout

#### 5.2.1 TC-005: IP Change via Annotation — SIGUSR2 Reload, No Pod Rollout

**Objective:** Verify that changing the LB IP annotation triggers a sidecar
SIGUSR2 reload without restarting KAS pods.

**Preconditions:**
- HC running with a fixed IP via MetalLB annotation (TC-001 state).
- At least one NodePool with ready nodes.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record current KAS pod names and restart counts | Baseline captured |
| 2 | Update the IP annotation on the HC to a new IP from the MetalLB pool | HC update accepted |
| 3 | Wait for the Service to acquire the new IP | `.status.loadBalancer.ingress[0].ip` changes to new IP |
| 4 | Verify KAS pod names and restart counts | Same pod names, same restart counts (no rollout) |
| 5 | Verify KAS is reachable at the new IP | API server responds at new IP |

---

#### 5.2.2 TC-006: Config Hash Stability on IP Change (E2E)

**Objective:** Verify that the rendered config hash does not change when only
the IP annotation changes, preventing unnecessary rollouts.

**Preconditions:**
- HC running with a fixed IP.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record the config hash from the KAS deployment annotation | Hash noted |
| 2 | Change the IP annotation to a different IP | Update accepted |
| 3 | Wait for reconciliation to complete | Service IP updated |
| 4 | Read the config hash again | Hash is identical to step 1 |

---

#### 5.2.3 TC-007: Non-IP Annotation Change — No Sidecar Restart

**Objective:** Verify that changing a non-IP-related service annotation does
not trigger a sidecar restart.

**Preconditions:**
- HC running with LB annotations.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record sidecar container restart count | Baseline captured |
| 2 | Add or modify a non-IP annotation in `serviceAnnotations` | Update accepted |
| 3 | Wait for reconciliation | Service annotations updated |
| 4 | Check sidecar restart count | Unchanged |

---

#### 5.2.4 TC-008: Scale-Up NodePool After IP Change

**Objective:** Verify that new nodes added after an IP change receive the
updated IP in their ignition config.

**Preconditions:**
- HC running. IP changed via annotation (TC-005 completed).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scale up the NodePool by 1 replica | Scale operation starts |
| 2 | Wait for the new node to join | Node reaches `Ready` |
| 3 | Verify the new node's kubelet is configured with the current (new) IP | kubelet `--server` flag or kubeconfig points to the new IP |

---

#### 5.2.5 TC-009: InPlace Upgrade with Deterministic IP

**Objective:** Verify that an InPlace upgrade strategy preserves the
deterministic IP across the upgrade.

**Preconditions:**
- HC running with a fixed IP. NodePool using InPlace upgrade strategy.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record the current KAS LB IP | IP noted |
| 2 | Trigger a NodePool upgrade (e.g. bump release image) | Upgrade starts |
| 3 | Wait for upgrade to complete | All nodes updated |
| 4 | Verify KAS LB IP is unchanged | Same IP as step 1 |
| 5 | Verify KAS is reachable | API server responds |

---


---

### 5.3 Day 2 — Pre-5.1 NodePool Compatibility

#### 5.3.1 TC-010: Mixed NodePool Versions (Pre-5.1 and 5.1+)

**Objective:** Verify that a HC with both pre-5.1 and 5.1+ NodePools
functions correctly when deterministic IP is configured.

**Preconditions:**
- HC with deterministic IP enabled.
- Two NodePools: one at a pre-5.1 release image, one at 5.1+.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with fixed IP and two NodePools at different versions | HC creation succeeds |
| 2 | Wait for both NodePools to reach `Ready` | Both NodePools have ready nodes |
| 3 | Verify nodes from both NodePools can reach the KAS | `oc get nodes` shows all nodes `Ready` |
| 4 | Change the IP annotation | Update accepted |
| 5 | Verify all nodes (both pools) eventually converge to the new IP | All nodes remain `Ready` |

---

#### 5.3.2 TC-011: Upgrade NodePool from Pre-5.1 to 5.1+

**Objective:** Verify that upgrading a NodePool from pre-5.1 to 5.1+
correctly picks up the deterministic IP management feature.

**Preconditions:**
- HC with deterministic IP. One NodePool at a pre-5.1 release image.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Verify nodes are running with pre-5.1 image | Nodes show pre-5.1 version |
| 2 | Update the NodePool release image to 5.1+ | Upgrade starts |
| 3 | Wait for the upgrade to complete | All nodes updated |
| 4 | Verify nodes use the deterministic IP path | Nodes' kubelet config references the fixed IP |

---

### 5.4 Ignition Server /kas-ip Endpoint

#### 5.4.1 TC-012: /kas-ip Returns Correct KAS IP

**Objective:** Verify the `/kas-ip` endpoint returns the current KAS
LoadBalancer IP.

**Preconditions:**
- HC running with a deterministic IP assigned.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Get the current KAS Service LB IP | IP noted |
| 2 | `curl http://<ignition-server>/kas-ip/<hcp-namespace>/<hcp-name>` | Returns the same IP in the response body |
| 3 | Change the IP annotation and wait for LB update | New IP assigned |
| 4 | Repeat the curl | Returns the new IP |

---

#### 5.4.2 TC-013: /kas-ip Requires No Authentication

**Objective:** Verify the `/kas-ip` endpoint is accessible without
authentication tokens.

**Preconditions:**
- Ignition server running.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `curl` the `/kas-ip` endpoint without any auth headers | HTTP 200, IP returned |
| 2 | `curl` with a bogus auth header | HTTP 200, IP returned (auth ignored) |

---

#### 5.4.3 TC-014: /kas-ip Rejects Hostname Requests

**Objective:** Verify the endpoint rejects requests that pass a hostname
instead of an IP-based path.

**Preconditions:**
- Ignition server running.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `curl` the `/kas-ip` endpoint using a hostname in the Host header | Request rejected or returns error |

---

#### 5.4.4 TC-015: /kas-ip Returns 404 for Unknown HCP

**Objective:** Verify the endpoint returns 404 when the requested HCP does
not exist.

**Preconditions:**
- Ignition server running.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `curl http://<ignition-server>/kas-ip/nonexistent-ns/nonexistent-hcp` | HTTP 404 |

---

### 5.5 Prerequisite — Kubelet Through HAProxy (CNTRLPLANE-4732)

#### 5.5.1 TC-016: Public Bare-Metal Kubelet Registers via HAProxy

**Objective:** Verify that on public bare-metal (Agent platform), kubelet
connects to KAS through HAProxy using the deterministic IP.

**Preconditions:**
- Agent-platform HC with MetalLB and deterministic IP.
- HAProxy configured per CNTRLPLANE-4732.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC on Agent platform with deterministic IP | HC reaches `Available` |
| 2 | Create NodePool and wait for nodes | Nodes reach `Ready` |
| 3 | Verify kubelet's `--server` points to the deterministic IP | IP matches the configured LB IP |
| 4 | Verify traffic flows through HAProxy | HAProxy access logs show kubelet connections |

---

#### 5.5.2 TC-017: Private HostedCluster Unaffected

**Objective:** Verify that private HCs (endpoint access = Private) are not
affected by the deterministic IP feature.

**Preconditions:**
- Private HC (no public LB).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a private HC without LB annotations | HC creation succeeds |
| 2 | Verify KAS uses private networking (NodePort/Route) | No LoadBalancer Service created for KAS, or Service type is not LB |
| 3 | Verify nodes join normally | Nodes reach `Ready` via private path |

---

#### 5.5.3 TC-018: Cloud Provider Unaffected

**Objective:** Verify that cloud-provider HCs (e.g. AWS) continue to work
without requiring the deterministic IP feature.

**Preconditions:**
- AWS HC without LB annotations.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC on AWS without `serviceAnnotations` or `loadBalancerClass` | HC creation succeeds |
| 2 | Verify KAS Service gets a cloud LB (hostname or IP) | LB assigned by cloud provider |
| 3 | Verify nodes join normally | Nodes reach `Ready` |

---

### 5.6 CEL Validation

#### 5.6.1 TC-019: Annotation Allowlist Enforcement

**Objective:** Verify that only the 11 allowed annotation prefixes are
accepted by CEL validation.

**Preconditions:**
- FeatureGate `DeterministicLBIP` enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with an allowed annotation prefix (e.g. `metallb.universe.tf/`) | Accepted |
| 2 | Create HC with a disallowed annotation (e.g. `custom.example.com/foo`) | Rejected by admission webhook with CEL validation error |
| 3 | Repeat step 1 for each of the 11 allowed prefixes | All accepted |

---

#### 5.6.2 TC-020: loadBalancerClass Immutability

**Objective:** Verify that `loadBalancerClass` cannot be changed or removed
after initial creation (it is the only immutable field in LoadBalancerPublishingStrategy;
`serviceAnnotations` is mutable and tested separately in TC-021).

**Preconditions:**
- HC created with `loadBalancerClass` set.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `loadBalancerClass: "metallb.io/metallb"` | Accepted |
| 2 | Attempt to change `loadBalancerClass` to a different value | Rejected by CEL validation |
| 3 | Attempt to remove `loadBalancerClass` (set to empty) | Rejected by CEL validation |

---

#### 5.6.3 TC-021: serviceAnnotations Mutability

**Objective:** Verify that mutable `serviceAnnotations` can be updated after
HC creation.

**Preconditions:**
- HC created with mutable service annotations.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Update an existing allowed annotation value | Update accepted |
| 2 | Add a new allowed annotation | Update accepted |
| 3 | Verify the KAS Service reflects the changes | Annotations updated on the Service |

---

#### 5.6.4 TC-022: loadBalancer Field Anti-Removal

**Objective:** Verify that the `loadBalancer` configuration section cannot be
removed once set.

**Preconditions:**
- HC created with `loadBalancer` configuration.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Attempt to patch the HC removing the entire `loadBalancer` block | Rejected by validation |
| 2 | Verify HC state is unchanged | HC still has `loadBalancer` config |

---

#### 5.6.5 TC-023: Optional Field Bypass Protection

**Objective:** Verify that optional fields within the LB config cannot be
used to bypass validation by setting them to zero-values.

**Preconditions:**
- HC with LB configuration.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Set an optional LB field to its zero value (empty string, nil) | Accepted only if the field was not previously set |
| 2 | Attempt to zero-out a previously-set optional field | Rejected if the field is protected |

---

#### 5.6.6 TC-024: loadBalancerClass Format Validation

**Objective:** Verify that `loadBalancerClass` values are validated for
correct format (qualified name).

**Preconditions:**
- FeatureGate enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Set `loadBalancerClass: "metallb.io/metallb"` | Accepted |
| 2 | Set `loadBalancerClass: "invalid class name!"` | Rejected by validation |
| 3 | Set `loadBalancerClass: ""` (empty) | Rejected by validation |

---

### 5.7 Hash Stability (Unit/Integration)

#### 5.7.1 TC-025: Placeholder Mechanism for Annotation Values

**Objective:** Verify that annotation values are replaced with placeholders
before computing the config hash, so that IP changes don't affect the hash.

**Primary method (automated):**
- Unit test in the config hash computation package.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Render the config with IP annotation `10.0.0.1` | Config contains a placeholder token, not the literal IP |
| 2 | Render the config with IP annotation `10.0.0.2` | Same placeholder token produced |
| 3 | Compute hash of both rendered configs | Hashes are identical |

---

#### 5.7.2 TC-026: Config Hash Unchanged on IP Change

**Objective:** Verify end-to-end that changing the IP annotation does not
change the deployment config hash.

**Primary method (automated):**
- Integration test that creates a config, changes the IP, and asserts hash equality.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create config with IP annotation A, compute hash | Hash_A recorded |
| 2 | Change IP annotation to B, re-render, compute hash | Hash_B recorded |
| 3 | Compare | Hash_A == Hash_B |

---

#### 5.7.3 TC-027: Config Hash Changes Without FeatureGate

**Objective:** Verify that without the `DeterministicLBIP`
FeatureGate, the placeholder mechanism is not active and the hash changes
when annotations change.

**Primary method (automated):**
- Unit test with FeatureGate disabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Disable `DeterministicLBIP` FeatureGate | Feature off |
| 2 | Render config with annotation A, compute hash | Hash_A |
| 3 | Render config with annotation B, compute hash | Hash_B |
| 4 | Compare | Hash_A != Hash_B (expected: hash changes without the feature) |

---

### 5.8 Provider Validation

> Cilium validation runs in periodic CI jobs.

#### 5.8.1 TC-028: Cilium LB IPAM Integration

**Objective:** Verify deterministic IP assignment works with Cilium LB IPAM.

**Preconditions:**
- Cilium with LB IPAM enabled on the management cluster.
- IP pool configured in Cilium.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with Cilium-specific annotations | HC creation succeeds |
| 2 | Verify Cilium assigns the requested IP | Service LB IP matches requested IP |
| 3 | Verify KAS is reachable | API server responds |

---

### 5.9 Upgrade Flow and Version Skew

#### 5.9.1 TC-029: HO Upgrade — No Hash Change

**Objective:** Verify that upgrading the HyperShift Operator from pre-feature
to feature-enabled version does not change config hashes or cause rollouts
on existing HCs.

**Preconditions:**
- Running HC with NodePools on pre-feature HO version.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record config hash and pod names of all KAS deployments | Baseline captured |
| 2 | Upgrade HO to feature-enabled version | HO upgrade completes |
| 3 | Verify config hashes on existing HCs | Hashes unchanged — new fields are optional, no defaults |
| 4 | Verify no pod rollouts occurred | Same pod names and restart counts |
| 5 | Verify HC remains functional | KAS reachable, nodes healthy |

---

#### 5.9.2 TC-030: HC Version Upgrade — No Visible Change

**Objective:** Verify that upgrading the HC release image (new CPO) does not
cause disruption when `serviceAnnotations` are not yet configured.

**Preconditions:**
- HO already at feature-enabled version (TC-029 completed).
- HC without `serviceAnnotations` configured.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Upgrade HC release image to 5.1+ | HC upgrade starts |
| 2 | Wait for CPO rollout to complete | New CPO running |
| 3 | Verify no `ValidLoadBalancerIPConfiguration` condition appears | Condition absent — feature not configured |
| 4 | Verify HC remains functional | KAS reachable, nodes healthy |

---

#### 5.9.3 TC-031: NodePool Upgrade — Condition Transition with Single NodePool

**Objective:** Verify that upgrading the only NodePool from pre-5.1 to 5.1+
transitions `ValidLoadBalancerIPConfiguration` from `False` to `True`.

**Preconditions:**
- HC with `serviceAnnotations` configured. Single NodePool at pre-5.1 image.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=False`, reason `UnsupportedNodePoolVersion`, message lists the NodePool name |
| 2 | Inspect NodePool conditions | `ValidLoadBalancerIPSupport=False` |
| 3 | Upgrade NodePool release image to 5.1+ | Upgrade starts |
| 4 | Wait for all nodes to be replaced | NodePool upgrade completes |
| 5 | Inspect NodePool conditions | `ValidLoadBalancerIPSupport=True` |
| 6 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=True` |
| 7 | Verify Day 2 IP change is now possible | Update `serviceAnnotations` IP — accepted and applied |

---

#### 5.9.4 TC-032: NodePool Upgrade — Partial Upgrade with Multiple NodePools

**Objective:** Verify that during a rolling upgrade of multiple NodePools,
`ValidLoadBalancerIPConfiguration` stays `False` until all NodePools are
upgraded, with the message listing non-compliant NodePools.

**Preconditions:**
- HC with `serviceAnnotations` configured. Three NodePools at pre-5.1 image.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=False`, reason `UnsupportedNodePoolVersion`, message lists all 3 NodePools |
| 2 | Upgrade NodePool-1 to 5.1+ | Upgrade starts |
| 3 | Wait for NodePool-1 upgrade to complete | `ValidLoadBalancerIPSupport=True` on NodePool-1 |
| 4 | Inspect HC conditions | Still `False`, message now lists only NodePool-2 and NodePool-3 |
| 5 | Attempt a Day 2 IP change | Rejected or blocked — not all NodePools compliant |
| 6 | Upgrade NodePool-2 and NodePool-3 to 5.1+ | Upgrades complete |
| 7 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=True` |
| 8 | Attempt Day 2 IP change | Accepted and applied |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| MetalLB not available in all CI environments | Medium | High | TC-001 through TC-005 require MetalLB; document setup steps in test environment |
| SIGUSR2 behavior varies across sidecar implementations | Low | High | TC-005 verifies the specific sidecar; add explicit signal handling tests |
| CEL validation rules may conflict with future annotation additions | Low | Medium | TC-019 tests all 11 prefixes; update allowlist and tests when new prefixes added |
| Pre-5.1 NodePools may not exist in CI | Medium | Medium | TC-010, TC-011 may require manual execution with specific release images |
| Cilium only in periodic CI, not presubmit | Low | Low | TC-028 covered by periodic jobs; failures detected within 24h |
| Upgrade flow requires multiple release images | Medium | Medium | TC-029 through TC-032 need pre-5.1 and 5.1+ images; periodic jobs with pinned versions |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | jparrill | 2026-10-14 |
| Reviewer | | |
