---
id: TP-OCPSTRAT-2653-001
version: "1.1"
date: 2026-11-18
title: "Deterministic LoadBalancer IP Management for Hosted Control Planes"
jira_issues:
  - key: OCPSTRAT-2653
    role: primary
    url: https://issues.redhat.com/browse/OCPSTRAT-2653
  - key: CNTRLPLANE-4574
    url: https://issues.redhat.com/browse/CNTRLPLANE-4574
  - key: CNTRLPLANE-4579
    url: https://issues.redhat.com/browse/CNTRLPLANE-4579
pull_requests:
  - repo: openshift/hypershift
    number: 9913
    url: https://github.com/openshift/hypershift/pull/9913
    role: implementation
  - repo: openshift/hypershift
    number: 9898
    url: https://github.com/openshift/hypershift/pull/9898
    role: implementation
  - repo: openshift/hypershift
    number: 10133
    url: https://github.com/openshift/hypershift/pull/10133
    role: implementation
  - repo: openshift/hypershift
    number: 10142
    url: https://github.com/openshift/hypershift/pull/10142
    role: implementation
  - repo: openshift/hypershift
    number: 10237
    url: https://github.com/openshift/hypershift/pull/10237
    role: test
  - repo: openshift/release
    number: 88475
    url: https://github.com/openshift/release/pull/88475
    role: test
status: draft
tags:
  - loadbalancer
  - deterministic-ip
  - metallb
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
**Version:** 1.1
**Date:** 2026-11-18
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

---

## 2. Introduction and Objectives

### 2.1 Purpose

This plan defines the verification strategy for **Deterministic LoadBalancer
IP Management** in HyperShift. The feature allows users to pin a fixed IP on
the KAS (Kubernetes API Server) LoadBalancer Service via HostedCluster
annotations, preventing IP drift across lifecycle events on bare-metal,
on-prem and cloud deployments.

Key capabilities under test:

**Day 1 (PRs #9898, #9913, #10133, #10142 — implemented):**
- `serviceAnnotations` passthrough from `HostedCluster.spec.services[].servicePublishingStrategy.loadBalancer` to **the primary** kube-apiserver Service via CPO (`ReconcileService()` for a public cluster, `ReconcilePrivateService()` for a private one). Only the Service exposing the primary endpoint receives the address annotations; requesting the same address on both leaves whichever load balancer loses the race pending forever, so `ReconcilePrivateService()` actively removes them once a public endpoint exists.
- `loadBalancerClass` selection on the KAS Service (MetalLB, F5, Cilium, etc.). Unlike the annotations, it applies to every LoadBalancer KAS Service because it selects the provisioning controller rather than an address — but only at Service creation, or when a Service is converted to type `LoadBalancer`. An existing LoadBalancer Service that predates the field is left without one, because Kubernetes makes `loadBalancerClass` immutable once set.
- CEL validation: `loadBalancerClass` qualified-name format, `serviceAnnotations` provider-prefix allowlist plus size bounds (see §3 Design notes), and whole-list `spec.services` immutability with the IBMCloud exemption.
- `spec.services` immutability: PR #9913 **kept** `ListType=atomic` and the pre-existing deep-equality CEL rule (`self.services == oldSelf.services`, IBMCloud exempt). It did **not** convert the rules to per-entry immutability — that conversion is Day 2 work, needed so `serviceAnnotations` can become mutable.

**Day 2 (not yet implemented — targeted at OCP 5.2; test cases defined against enhancement design):**
- Zero-rollout sidecar updates via SIGUSR2 (no pod restart on IP change)
- Ignition server `/kas-ip` endpoint for node IP discovery
- Config hash stability across IP changes (placeholder mechanism)
- `ValidLoadBalancerIPConfiguration` / `ValidLoadBalancerIPSupport` condition transitions
- Version skew compatibility between HyperShift Operator and Control Plane Operator

### 2.2 Objectives

1. Verify `serviceAnnotations` on `HostedCluster.spec` are passed through to the **primary** kube-apiserver Service — public for a public cluster, private for a private one — and the LB acquires the specified IP.
2. Verify `loadBalancerClass` is set at Service creation and on conversion to type `LoadBalancer`, and is deliberately not retro-fitted to a pre-existing LoadBalancer Service.
3. Verify CEL validation enforces `loadBalancerClass` format, the `serviceAnnotations` provider-prefix allowlist and size bounds, and whole-list `spec.services` immutability.
4. Verify no regression for existing HCs without LB annotations.
5. *(Day 2)* Verify IP changes trigger sidecar reload (SIGUSR2), not pod rollout.
6. *(Day 2)* Verify the `/kas-ip` ignition server endpoint returns the correct IP.
7. *(Day 2)* Verify config hash stability when only IP-related annotations change.
8. *(Day 2)* Verify version skew scenarios and condition transitions between old and new operator versions.

### 2.3 Acceptance Criteria Mapping

| Acceptance Criterion | Test Cases |
|----------------------|------------|
| AC #1 — Annotations passed through to the primary KAS Service | TC-001, TC-003 (Section 5.1) |
| AC #2 — loadBalancerClass correctly set | TC-002 (Section 5.1) |
| AC #3 — No regression without annotations | TC-004 (Section 5.1) |
| AC #4 — IP change triggers SIGUSR2, no rollout | TC-005, TC-006, TC-007 (Section 5.2) |
| AC #5 — Config hash stable on IP change | TC-025, TC-026, TC-027 (Section 5.7) |
| AC #6 — CEL validation (immutability, bounds, format) | TC-019 through TC-024, TC-039, TC-040 (Section 5.6) |
| AC #7 — /kas-ip endpoint correct | TC-012 through TC-015 (Section 5.4) |
| AC #8 — Upgrade flow and condition transitions | TC-029 through TC-032 (Section 5.9) |
| AC #9 — Kubelet via HAProxy (prerequisite) | TC-016 (Section 5.5) |
| AC #16 — Non-regression without feature (gate on, no annotations) | TC-004, TC-017, TC-018 (Section 5.1) |
| AC #17 — Version skew NodePool compatibility | TC-010, TC-011 (Section 5.3) |
| AC #18 — Cilium LB IPAM integration | TC-028 (Section 5.8) |
| AC #11 — Annotation removal from Service | TC-034 (Section 5.1) |
| AC #12 — IBMCloud exemption preserved | TC-039 (Section 5.6) |
| AC #13 — IPv6 support | TC-038, TC-041 (Sections 5.4, 5.7) |
| AC #14 — Proxy cluster Day 2 path | TC-036 (Section 5.2) |
| AC #15 — Azure service routing | TC-042 (Section 5.8) |

### 2.4 Automation-First Principle

The primary verification method for every test case is the automated test
suite delivered with the implementation PRs. Manual execution is a fallback
only. Day 2 test cases (§5.2, §5.3, §5.4, §5.7, §5.9) currently document
only fallback methods because no implementation PR exists yet — primary
automated methods will be added when the implementation lands.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Enhancement proposal | [openshift/enhancements#2117](https://github.com/openshift/enhancements/pull/2117) |
| Implementation PR (API fields) | [openshift/hypershift#9913](https://github.com/openshift/hypershift/pull/9913) |
| Implementation PR (annotation allowlist + size bounds) | [openshift/hypershift#10142](https://github.com/openshift/hypershift/pull/10142) |
| Implementation PR (CPO passthrough to KAS Services) | [openshift/hypershift#10133](https://github.com/openshift/hypershift/pull/10133) |
| Implementation PR (feature gate) | [openshift/hypershift#9898](https://github.com/openshift/hypershift/pull/9898) |
| Implementation PR (CLI flags, envtest and e2e) | [openshift/hypershift#10237](https://github.com/openshift/hypershift/pull/10237) |
| Implementation PR (ignition server /kas-ip) | TBD — tracked by [CNTRLPLANE-4799](https://issues.redhat.com/browse/CNTRLPLANE-4799) |
| Strategy Jira | [OCPSTRAT-2653](https://issues.redhat.com/browse/OCPSTRAT-2653) |
| Epic | [CNTRLPLANE-4574](https://issues.redhat.com/browse/CNTRLPLANE-4574) |
| E2E story | [CNTRLPLANE-4579](https://issues.redhat.com/browse/CNTRLPLANE-4579) |
| HAProxy prerequisite | [CNTRLPLANE-4732](https://issues.redhat.com/browse/CNTRLPLANE-4732) |

**Design notes:**

- PR #9913 **kept** `spec.services` as `ListType=atomic` with the pre-existing
  deep-equality CEL rule (`self.services == oldSelf.services`, IBMCloud exempt).
  No per-entry rules were introduced. Deep equality covers the new fields
  automatically — `loadBalancerClass` and `serviceAnnotations` are immutable
  because every field of every service entry is. Converting to per-entry
  immutability (service keys and strategy types fixed, `serviceAnnotations`
  mutable) is **Day 2** work, required before annotations can change at runtime.
- `serviceAnnotations` is a `map[string]string` with `MinProperties=1` and
  `MaxProperties=10`, plus a **CEL provider-prefix allowlist**. Every key must
  start with one of: `metallb.io/`, `metallb.universe.tf/`,
  `service.beta.kubernetes.io/aws-load-balancer-eip`,
  `service.beta.kubernetes.io/aws-load-balancer-subnet`,
  `service.beta.kubernetes.io/aws-load-balancer-target-group`,
  `service.beta.kubernetes.io/azure-load-balancer-ipv`,
  `service.beta.kubernetes.io/azure-load-balancer-resource-group`,
  `networking.gke.io/` (except `networking.gke.io/load-balancer-type`),
  `cis.f5.com/`, `lbipam.cilium.io/`, `loadbalancer.openstack.org/`.
  Keys are limited to 317 characters and values to 253. HyperShift does not
  validate annotation *value* semantics.
- `loadBalancerClass` has CEL validation for valid qualified-name format
  (≤253 chars, name segment ≤63) and is immutable after creation, both because
  of the whole-list rule and because Kubernetes Services make the field
  immutable (matching Kubernetes Service semantics). It is applied on create,
  and when a Service is converted to type `LoadBalancer` on a private → public
  endpoint transition.
- AWS carve-out: `service.beta.kubernetes.io/aws-load-balancer-type` is skipped
  on AWS in both reconciliation paths (OCPBUGS-16728 — the admission policy
  blocks changing the NLB type after creation, so a user value would make every
  subsequent Service update fail). Note this key is not in the CEL allowlist
  today, so the guard is defensive and currently unreachable from user input.
- *(Day 2)* Sidecar reload uses SIGUSR2 signal, avoiding full pod rollout.

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Bare-metal simulation | Agent platform with KubeVirt |
| Cloud provider | AWS |
| LB provider (CI) | AWS NLB (existing optional lane); MetalLB on Agent (planned) |
| Management cluster OCP version | 4.18+ |
| HostedCluster release image (min) | 5.1+ (Day 2 sidecar requires 5.1+ NodePool images) |
| Prerequisites | `hypershift` CLI, `oc` CLI. The AWS lane reserves an EIP and a management-VPC subnet in a pre-step. The planned Agent lane requires the MetalLB operator. |
| Provider lanes | AWS (live, optional), Agent (next; MetalLB + Cilium variants), Azure (after Agent), KubeVirt (last) |
| FeatureGate | `DeterministicLBIP` |

### CI Execution Strategy

Test cases are consolidated to minimize E2E test count while maximizing
coverage. Unit and integration tests run in presubmit; heavier E2E
scenarios run in periodic jobs.

**E2E tests:**

| E2E Test | TCs Covered | Platform | CI Tier |
|----------|-------------|----------|---------|
| Day 1 deterministic LB — create a `PublicAndPrivate` HC with EIP/subnet passthrough, verify the public KAS Service keeps the reserved address and survives reconciliation | TC-001 (AWS EIP), TC-003 | AWS NLB + EIP | Optional presubmit `e2e-v2-aws-deterministic-lb` ([release#88475](https://github.com/openshift/release/pull/88475)) |
| Day 1 lifecycle — create HC with MetalLB fixed IP and `loadBalancerClass` | TC-001, TC-002 | Agent/MetalLB | Presubmit (lane not implemented) |
| Day 1 Azure deterministic LB — create HC with an Azure LB IP annotation, verify the address on `kube-apiserverlb` and the Azure routing | TC-001 (Azure LB IP), TC-042 | Azure LB | Presubmit (planned, after Agent) |
| Day 1 KubeVirt deterministic LB — create HC with management-cluster LB annotations, verify the fixed address | TC-001 | KubeVirt | TBD (last) |
| Day 2 lifecycle — change IP (no rollout + hash), non-IP annotation change, annotation removal, kubelet via HAProxy | TC-005, 006, 007, 016, 034 | Agent/MetalLB | Presubmit |
| Day 2 scale + upgrade — scale-up NP after IP change, InPlace upgrade with deterministic IP | TC-008, 009 | Agent/MetalLB | Periodic |
| Upgrade flow — HO old→new, HC version upgrade, mixed NP versions, partial upgrade, condition transitions, absent condition handling | TC-010, 011, 029, 030, 031, 032 | Agent/MetalLB | Periodic |
| Agent/Cilium variant — create HC with Cilium LB IPAM annotations (Agent platform, Cilium LB) | TC-028 | Agent + Cilium | Periodic (variant not implemented) |
| Proxy Day 2 — create HC with proxy config, verify IP update via manifest rewrite | TC-036 | Agent/MetalLB | Periodic |
| Init container resilience — ignition server unavailable during scale-up | TC-035 | Agent/MetalLB | Periodic |

**Unit/integration tests (5 suites):**

| Suite | TCs Covered | CI Tier |
|-------|-------------|---------|
| CEL validation | TC-019 to TC-024, TC-039 | Presubmit |
| Hash stability | TC-025 to TC-027, TC-041 | Presubmit |
| /kas-ip HTTP handler | TC-012 to TC-015, TC-037, TC-038 | Presubmit |
| CPO annotation passthrough | TC-034 (GA only), TC-040 | Presubmit |
| Azure service routing | TC-042 | Presubmit |

**Non-regression tests (gate enabled, no annotations):**

| Scenario | TCs | Note |
|----------|-----|------|
| Legacy HC lifecycle with gate enabled | TC-004 | Covered by the existing `e2e-v2-aws` presubmit: it installs the operator with `TECH_PREVIEW_NO_UPGRADE=true` and creates its `public` variant with `--feature-set=TechPreviewNoUpgrade` and no `serviceAnnotations`. The full AWS suite runs on that cluster. No dedicated assertion that the annotations are absent was added. |
| Cloud provider unaffected | TC-018 | Same cluster as TC-004: the KAS Service obtains its NLB and the NodePools reach `Ready`, or the suite fails. |
| Private HC unaffected | TC-017 | Not separately exercised. See the endpoint-access scope decision below. |

**Provider scope decisions for Day 1:**

- The AWS lane runs a single `PublicAndPrivate` variant. It covers the public
  endpoint and asserts that the private endpoint does **not** receive the
  deterministic annotations. No separate `Public` or `Private` AWS variant is
  added: the private and public-and-private paths are treated as covered by the
  public lane plus the envtest reconciliation suite, which reconciles both KAS
  Services and the PublicAndPrivate→Private transition.
- `loadBalancerClass` is not exercised on AWS. The AWS cloud provider ignores
  Services that set a class, so the KAS Service never obtains an address and the
  HostedCluster never becomes available. TC-002 stays with the Agent/MetalLB
  lane.
- The private endpoint is not run against a live private AWS cluster. The public
  lane covers the shared passthrough path and the envtest suite covers the
  private Service wiring; there is no separate Day 1 case.

**Platforms affected (Day 1):** the feature applies to any HostedCluster whose
APIServer service publishing strategy is `LoadBalancer`, regardless of
`spec.platform.type`. The platform only changes the LB implementation and the
annotation prefix; the passthrough path is the same. Day 1 coverage by platform:

| Platform / LB implementation | Affected | Day 1 coverage |
|------------------------------|----------|----------------|
| AWS (NLB + EIP) | Yes | Live lane `e2e-v2-aws-deterministic-lb`: TC-001, TC-003; non-regression TC-004/TC-018 in `e2e-v2-aws` |
| Azure (Azure LB; public Service `kube-apiserverlb`, private port 7443) | Yes | TC-042 (unit now; E2E planned after Agent) |
| Agent / bare metal (MetalLB) | Yes | Next lane: TC-001, TC-002 |
| Agent / bare metal (Cilium LB IPAM) | Yes | TC-028; periodic variant |
| KubeVirt (management-cluster LB) | Yes | E2E planned last |
| IBMCloud | Carve-out only | TC-039 (CEL), not deterministic annotations |
| GKE, F5 and OpenStack prefixes | Allowlisted | No Day 1 lane |
| Private endpoint (internal LB) | Yes, private Service only | Covered by the public lane; envtest covers the private Service wiring; no separate case |
| APIServer strategy Route or NodePort | No | Non-regression TC-004/TC-018 |

Platforms using Route or NodePort for the APIServer are unaffected: the feature
only rewrites annotations on the Service that exposes the primary endpoint, and
that Service is a LoadBalancer only for the rows marked Yes.

**Coverage limits of the AWS lane:** the spec carries the `Informing` label, so
an assertion failure is reported as a skipped informing failure and does not
fail the job; the job is `optional: true`; and the spec skips when the EIP
pre-step did not export `HYPERSHIFT_DETERMINISTIC_LB_EIP`,
`HYPERSHIFT_DETERMINISTIC_LB_SUBNET` or `E2E_EXPECTED_DETERMINISTIC_LB_IP`. A
green job therefore counts as coverage only when the JUnit reports the spec as
passed, not skipped.

### Day 1 verification evidence (2026-11-18)

Taken from the optional AWS lane rehearsal ([Prow
job](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_release/88475/rehearse-88475-pull-ci-openshift-hypershift-main-e2e-v2-aws-deterministic-lb/2123000912807989248),
`e2e-v2-aws-deterministic-lb`). JUnit: 1 test, 0 failures, 40.6 s; the suite ran
1 of 1178 specs under the `deterministic-lb-ip` label filter.

| Test case | Evidence | Status |
|-----------|----------|--------|
| TC-001 | The pre-step reserved an EIP and the HC was created with the EIP and subnet annotations. The spec `should configure the primary kube-apiserver LoadBalancer Service from the HostedCluster annotations` reported the public KAS Service with both annotations, and its NLB resolved to the reserved address. | Verified (AWS NLB/EIP) |
| TC-003 | Same run: the spec removed the control-plane component label, waited for the operator to restore it, and held Service UID, annotations, class and ingress stable for 30 s. | Verified (30 s window; the 5-minute window is deferred) |
| TC-004 | The `e2e-v2-aws` presubmit runs gate-on with no annotations and the full AWS suite passes on that cluster. | Covered implicitly; no dedicated assertion |
| TC-018 | Same cluster: the KAS Service obtains its NLB and the NodePools reach `Ready`. | Covered implicitly |
| TC-002 | The envtest reconciliation suite asserts the field on both KAS Services; there is no live provisioning run. | Partial (Agent/MetalLB lane) |
| TC-019–TC-024, TC-039 | CEL YAML suite. | Verified (automated) |
| TC-040 | No reachable test: admission rejects every CPO-managed key. | Gap |
| TC-028, TC-042 | Allowlist admission and unit coverage only. | Partial |

---

## 5. Test Cases

### 5.1 Day 1 — Annotation Passthrough and loadBalancerClass

#### 5.1.1 TC-001: Fixed IP via Service Annotation

**Objective:** Verify that a provider LoadBalancer IP annotation on the
HostedCluster spec results in the KAS Service acquiring the specified fixed IP.
The live Day 1 lane uses an AWS NLB with an Elastic IP; the Agent/MetalLB lane
uses a MetalLB address from an IPAddressPool.

**Preconditions:**
- A LoadBalancer provider that assigns an address from an annotation: AWS NLB
  with an EIP (live lane) or MetalLB with an IPAddressPool (Agent lane).
- FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- E2E: `e2e-v2-aws-deterministic-lb` optional presubmit (AWS EIP) and the
  Agent/MetalLB presubmit once implemented (see §4 CI table).
- Unit: CPO annotation passthrough suite.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with a provider IP annotation (`metallb.universe.tf/loadBalancerIPs`, `lbipam.cilium.io/ips`, or `service.beta.kubernetes.io/aws-load-balancer-eip-allocations`) | HC creation succeeds |
| 2 | Inspect the KAS Service in the HCP namespace | Service has the requested annotation |
| 3 | Wait for LB address assignment | Service `.status.loadBalancer.ingress` resolves to the requested address |
| 4 | Verify KAS is reachable at the assigned address | `oc --server=https://<address>:6443 get ns` succeeds |

---

#### 5.1.2 TC-002: loadBalancerClass Passthrough

**Objective:** Verify that `loadBalancerClass` set on the HostedCluster is
propagated to the KAS Service.

**Preconditions:**
- A LoadBalancer controller that watches the target class is installed for a
  live run; envtest does not require one.

**Primary method (automated):**
- Envtest: `loadBalancerClass` on both KAS Services (see §4 CI table).
- Unit: CPO annotation passthrough suite.

**Live coverage:** none. AWS ignores Services that set a class, so the KAS
Service stays `Pending`; the Agent/MetalLB lane that can exercise it is not
implemented.

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

**Primary method (automated):**
- E2E: Day 1 lifecycle presubmit (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Note current annotations on the KAS Service | Annotations include the user-specified LB annotations |
| 2 | Trigger a reconciliation (e.g. update an unrelated HC field) | Reconciliation completes |
| 3 | Re-inspect the KAS Service annotations | LB annotations unchanged |
| 4 | Wait 5 minutes, inspect again | Annotations still preserved |
| 5 | Verify MetalLB status annotations preserved | MetalLB-written annotations (e.g. `ip-allocated-from-pool`) still present alongside user annotations |

---

#### 5.1.4 TC-004: Legacy Behavior — No Annotations, No Regression

**Objective:** Verify that a HostedCluster created without any LB annotations
works identically to pre-feature behavior.

**Preconditions:**
- FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- E2E: `e2e-v2-aws` presubmit, gate on and no annotations (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC without any `serviceAnnotations` or `loadBalancerClass` | HC creation succeeds |
| 2 | Inspect the KAS Service | No unexpected annotations added, no `loadBalancerClass` set |
| 3 | Verify KAS is reachable | API server responds normally |
| 4 | Run standard NodePool lifecycle (create, scale, delete) | All operations succeed |

---

#### 5.1.5 TC-034: Annotation Removal from Spec (Day 2 / GA)

> **⚠️ Phase note:** `serviceAnnotations` is immutable during TechPreview.
> This TC verifies annotation removal which requires mutability — it is
> executable only at GA when the immutability CEL rule is removed.

**Objective:** Verify that removing an annotation key from `serviceAnnotations`
causes it to be removed from the KAS Service on the next reconciliation.

**Preconditions:**
- HC with `serviceAnnotations` containing at least 2 annotations.
- GA release (serviceAnnotations immutability rule removed).

**Primary method (automated):**
- E2E: Day 2 lifecycle presubmit (see §4 CI table).
- Unit: CPO annotation passthrough suite.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Verify both annotations present on the KAS Service | Both annotations confirmed |
| 2 | Remove one annotation key from the HC `serviceAnnotations` | HC update accepted |
| 3 | Wait for reconciliation | CPO processes the change |
| 4 | Inspect the KAS Service | Removed key is gone from Service annotations |
| 5 | Verify remaining annotation still present | Second annotation unchanged |

---

#### 5.1.6 TC-017: Private HostedCluster Unaffected

**Objective:** Verify that private HCs (endpoint access = Private) are not
affected by the deterministic IP feature when the gate is enabled.

**Preconditions:**
- Private HC (no public LB). FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- E2E: not run in a dedicated private lane; the envtest reconciliation suite covers the private KAS Service wiring (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a private HC without LB annotations | HC creation succeeds |
| 2 | Verify KAS uses private networking (NodePort/Route) | No LoadBalancer Service created for KAS, or Service type is not LB |
| 3 | Verify nodes join normally | Nodes reach `Ready` via private path |

---

#### 5.1.7 TC-018: Cloud Provider Unaffected

**Objective:** Verify that cloud-provider HCs (e.g. AWS) continue to work
without requiring the deterministic IP feature when the gate is enabled.

**Preconditions:**
- AWS HC without LB annotations. FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- E2E: `e2e-v2-aws` presubmit, gate on and no annotations (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC on AWS without `serviceAnnotations` or `loadBalancerClass` | HC creation succeeds |
| 2 | Verify KAS Service gets a cloud LB (hostname or IP) | LB assigned by cloud provider |
| 3 | Verify nodes join normally | Nodes reach `Ready` |

---

> **⚠️ Implementation status:** Test cases in this section are defined against
> the enhancement design ([enhancements#2117](https://github.com/openshift/enhancements/pull/2117)).
> No implementation PR exists yet for the sidecar, SIGUSR2 reload, or
> `/kas-ip` endpoint. These TCs are not verifiable until the Day 2
> implementation PRs land. Tracked by [CNTRLPLANE-4799](https://issues.redhat.com/browse/CNTRLPLANE-4799)
> and [CNTRLPLANE-4800](https://issues.redhat.com/browse/CNTRLPLANE-4800).

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
| 4a | Check sidecar logs for the reload event | Sidecar logs contain SIGUSR2 received / config reloaded message |
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

#### 5.2.6 TC-035: Init Container Fallback on Ignition Unreachable

**Objective:** Verify init container behavior when the ignition server
`/kas-ip` endpoint is temporarily unreachable.

**Preconditions:**
- HC with deterministic IP. HAProxy sidecar enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scale down ignition server deployment to 0 replicas | Ignition server unavailable |
| 2 | Scale up NodePool by 1 replica | New node provisioning starts |
| 3 | Observe init container logs | Retries with exponential backoff |
| 4 | Scale ignition server back to original replicas | Ignition server available |
| 5 | Verify init container succeeds | HAProxy starts with correct IP |
| 6 | Verify new node joins the cluster | Node reaches `Ready` |

---

#### 5.2.7 TC-036: Proxy-Configured Cluster Day 2 IP Update

**Objective:** Verify Day 2 IP change works on clusters where
`kubernetes-default-proxy` replaces HAProxy (proxy-configured clusters).

**Preconditions:**
- HC with `spec.configuration.proxy.httpsProxy` set and KAS not in `noProxy`.
- Deterministic IP configured. FeatureGate enabled.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Verify `kubernetes-default-proxy` static pod running on worker (not HAProxy) | Pod present with `--apiserver-addr` flag |
| 2 | Record current `--apiserver-addr` value | Baseline captured |
| 3 | Change the IP annotation on the HC | HC update accepted |
| 4 | Wait for sidecar to detect IP change | Sidecar logs show new IP detected |
| 5 | Verify sidecar rewrites `kube-apiserver-proxy.yaml` manifest on worker | Manifest updated with new `--apiserver-addr` |
| 6 | Verify kubelet detects manifest change and restarts static pod | New `kubernetes-default-proxy` pod running |
| 7 | Verify `--apiserver-addr` points to new IP | New IP confirmed |
| 8 | Verify KAS is reachable through proxy | API server responds |

---

> **⚠️ Implementation status:** TC-010 and TC-011 depend on the Day 2
> sidecar and condition logic. Covered by the upgrade flow periodic E2E.

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

> **⚠️ Implementation status:** The `/kas-ip` ignition server endpoint has no
> implementation PR yet. Tracked by [CNTRLPLANE-4799](https://issues.redhat.com/browse/CNTRLPLANE-4799).
> TC-012 through TC-015, TC-037, TC-038 are not verifiable until that PR lands.

> **Security note:** TC-013 explicitly tests that `/kas-ip` requires no
> authentication. This means any party with network reach to the ignition
> server can enumerate HostedClusters (200 vs 404) and learn their API-server
> IPs. This is a conscious design choice: the ignition server is already
> unauthenticated for ignition config delivery, and `/kas-ip` exposes no
> additional information beyond what the ignition config already contains.
> If this posture changes, TC-013 must be updated accordingly.

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

#### 5.4.3 TC-014: /kas-ip Returns IP When KAS Resolves to Hostname

**Objective:** Verify the `/kas-ip` endpoint returns a resolved IP address
even when the KAS publishing strategy resolves to a hostname (e.g. a cloud
LB that returns a DNS name instead of an IP in `.status.loadBalancer.ingress`).

**Preconditions:**
- Ignition server running. HC with a KAS Service whose LB status reports a hostname.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC where the LB assigns a hostname (e.g. AWS ELB) | Service `.status.loadBalancer.ingress[0].hostname` is set |
| 2 | `curl http://<ignition-server>/kas-ip/<hcp-namespace>/<hcp-name>` | Returns the hostname string (sidecar resolves it) |

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

#### 5.4.5 TC-037: /kas-ip Returns 503 When Endpoint Empty

**Objective:** Verify the `/kas-ip` endpoint returns 503 when the HCP exists
but `Status.ControlPlaneEndpoint` is empty (LB has not yet assigned an IP).

**Preconditions:**
- Ignition server running. HCP exists but ControlPlaneEndpoint not yet populated.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HCP without waiting for LB IP assignment | HCP exists, endpoint empty |
| 2 | `curl http://<ignition-server>/kas-ip/<hcp-namespace>/<hcp-name>` | HTTP 503 |
| 3 | Wait for LB to assign IP | `ControlPlaneEndpoint.Host` populated |
| 4 | Repeat the curl | HTTP 200 with correct IP |

---

#### 5.4.6 TC-038: /kas-ip IPv6 Response Format

**Objective:** Verify `/kas-ip` returns a raw IPv6 address string without
brackets or port suffix. The sidecar is responsible for bracketing.

**Preconditions:**
- IPv6-enabled management cluster. Ignition server running.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with IPv6 LB IP | HC creation succeeds |
| 2 | `curl http://<ignition-server>/kas-ip/<hcp-namespace>/<hcp-name>` | Returns raw IPv6 (e.g. `2001:db8::1`, not `[2001:db8::1]`) |
| 3 | Verify sidecar consumes the raw IPv6 and applies bracketing in haproxy.cfg | Backend line reads `[2001:db8::1]:6443` |

---

> **Note:** TC-017 (Private HC Unaffected) and TC-018 (Cloud Provider
> Unaffected) were moved to §5.1 — they are non-regression tests, not
> HAProxy prerequisites.

### 5.5 Prerequisite — Kubelet Through HAProxy (CNTRLPLANE-4732)

#### 5.5.1 TC-016: Public Bare-Metal Kubelet Registers via HAProxy

**Objective:** Verify that on public bare-metal (Agent platform), kubelet
connects to KAS through HAProxy using the deterministic IP.

**Preconditions:**
- Agent-platform HC with MetalLB and deterministic IP.
- HAProxy configured per CNTRLPLANE-4732.

**Primary method (automated):**
- E2E: Day 2 lifecycle presubmit (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC on Agent platform with deterministic IP | HC reaches `Available` |
| 2 | Create NodePool and wait for nodes | Nodes reach `Ready` |
| 3 | Verify kubelet's `--server` points to the deterministic IP | IP matches the configured LB IP |
| 4 | Verify traffic flows through HAProxy | HAProxy access logs show kubelet connections |

---

---

### 5.6 CEL Validation

#### 5.6.1 TC-019: serviceAnnotations Enforces the Provider-Prefix Allowlist and Size Bounds

**Objective:** Verify that `serviceAnnotations` accepts keys that start with one
of the allowlisted provider prefixes within the `MinProperties=1` /
`MaxProperties=10` bounds, and rejects keys outside the allowlist.
Matching an allowlisted prefix is necessary but not sufficient: a specific
allowlisted key can still be denied (`networking.gke.io/load-balancer-type`),
and a malformed qualified name is rejected regardless of its prefix.
See §3 Design notes for the full prefix list and the explicit denials.

**Preconditions:**
- FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- Test: the `DeterministicLBIP` envtest suite that drives CEL admission. The
  cases are `cmd/install/assets/crds/hypershift-operator/tests/hostedclusters.hypershift.openshift.io/featuregated.hostedclusters.deterministiclbip.testsuite.yaml`,
  which `test/envtest/suite_test.go` generates into the Ginkgo suite. The spec
  in `test/envtest/deterministic_lb_ip_test.go` reconciles Services and does
  not exercise admission.
- Run: `make test-envtest-ocp` executes the whole `./test/envtest/...` package
  across the supported versions and forwards no selection flags. To run this
  suite alone on one version, resolve the assets to an absolute path and call
  the test binary directly:
  `KUBEBUILDER_ASSETS="$(hack/tools/bin/setup-envtest use --use-env --bin-dir "$PWD/hack/tools/bin/envtest-ocp" -p path --index https://raw.githubusercontent.com/openshift/api/master/envtest-releases.yaml 1.34.1)" go test -tags envtest ./test/envtest/ -run TestAPIs -count=1 -v -args -ginkgo.focus='DeterministicLBIP'`
  On Kubernetes 1.34.1 this selects 48 of 1147 specs and all 48 pass. The
  `--bin-dir` value must be absolute: a relative path resolves against the
  package directory, so the suite cannot start its control plane.
- Expected outcome: allowlisted prefixes are admitted; a non-allowlisted key,
  `networking.gke.io/load-balancer-type`, a malformed qualified name, more than
  10 entries, zero entries, and a value longer than 253 characters are each
  rejected at admission.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with a MetalLB annotation (`metallb.universe.tf/address-pool: "pool-1"`) | Accepted — `metallb.universe.tf/` is allowlisted |
| 2 | Create HC with a Cilium annotation (`lbipam.cilium.io/ips: "10.0.0.5"`) | Accepted — `lbipam.cilium.io/` is allowlisted |
| 3 | Create HC with a non-allowlisted key (`custom.example.com/foo: "bar"`) | Rejected — key must start with an allowlisted provider prefix |
| 4 | Create HC with `networking.gke.io/load-balancer-type: "Internal"` | Rejected — this specific GKE key is denied even though the prefix is allowed |
| 5 | Create HC with a malformed key under an allowlisted prefix (`metallb.io/Bad..Key: "x"`) | Rejected — the name segment must be a valid qualified name |
| 6 | Create HC with 10 annotations (max) | Accepted |
| 7 | Create HC with 11 annotations | Rejected by `MaxProperties=10` validation |
| 8 | Create HC with 0 annotations (empty map `{}`) | Rejected by `MinProperties=1` validation |
| 9 | Create HC with a value longer than 253 characters | Rejected by the value-length rule |

---

#### 5.6.2 TC-020: loadBalancerClass Immutability

**Objective:** Verify that `loadBalancerClass` cannot be changed or removed
after initial creation. `loadBalancerClass` is immutable (matching Kubernetes
Service semantics); `serviceAnnotations` is immutable during TechPreview
(tested in TC-021) and becomes mutable at GA.
See also TC-022 (anti-removal of the `loadBalancer` block) and TC-023
(optional field zero-value protection).

**Preconditions:**
- HC created with `loadBalancerClass` set.

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `loadBalancerClass: "metallb.io/metallb"` | Accepted |
| 2 | Attempt to change `loadBalancerClass` to a different value | Rejected by CEL validation |
| 3 | Attempt to remove `loadBalancerClass` (set to empty) | Rejected by CEL validation |

---

#### 5.6.3 TC-021: serviceAnnotations Immutability (TechPreview)

**Objective:** Verify that `serviceAnnotations` is immutable during
TechPreview — updates to existing annotations are rejected by CEL validation.
At GA graduation the immutability rule is removed and this TC becomes a
mutability test (updates accepted).

**Preconditions:**
- HC created with `serviceAnnotations`.
- `DeterministicLBIP` FeatureGate enabled (TechPreviewNoUpgrade).

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Attempt to update an existing annotation value | Rejected by CEL validation |
| 2 | Attempt to add a new annotation | Rejected by CEL validation |
| 3 | Attempt to remove an annotation key | Rejected by CEL validation |

> **GA behavior:** When the immutability rule is removed at GA, the same steps
> should result in updates being accepted and reflected on the KAS Service.

---

#### 5.6.4 TC-022: loadBalancer Field Anti-Removal

**Objective:** Verify that the `loadBalancer` configuration section cannot be
removed once set.

**Preconditions:**
- HC created with `loadBalancer` configuration.

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Attempt to patch the HC removing the entire `loadBalancer` block | Rejected by validation |
| 2 | Verify HC state is unchanged | HC still has `loadBalancer` config |

---

#### 5.6.5 TC-023: Optional Field Zero-Value Protection

**Objective:** Verify that optional fields within `LoadBalancerPublishingStrategy`
cannot be set to zero-values to bypass immutability. This is distinct from
TC-020 (which tests changing `loadBalancerClass` to a different value or
removing it via empty string). This TC covers the `null` / field-absent case.

**Preconditions:**
- HC with `loadBalancerClass` set to `"metallb.io/metallb"`.

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Patch HC to set `loadBalancerClass: null` (field absent) | Rejected by CEL validation — field was previously set |
| 2 | Patch HC to omit `loadBalancerClass` from the spec entirely | Rejected — Kubernetes treats omission as deletion for optional fields |
| 3 | Set `serviceAnnotations` to `null` on an HC that had annotations | TP: Rejected — `serviceAnnotations` is immutable. GA: Accepted — can be cleared |

---

#### 5.6.6 TC-024: loadBalancerClass Format Validation

**Objective:** Verify that `loadBalancerClass` values are validated for
correct format (qualified name).

**Preconditions:**
- FeatureGate enabled.

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Set `loadBalancerClass: "metallb.io/metallb"` | Accepted |
| 2 | Set `loadBalancerClass: "invalid class name!"` | Rejected by validation |
| 3 | Set `loadBalancerClass: ""` (empty) | Rejected by validation |

---

#### 5.6.7 TC-039: IBMCloud CEL Carve-out Preserved

**Objective:** Verify that the IBMCloud exemption from `services` immutability
is preserved. There is no CEL rule migration in Day 1 — PR #9913 kept the
pre-existing deep-equality rule — so this case guards the exemption itself, and
must keep passing unchanged when the per-entry conversion lands in Day 2.

**Preconditions:**
- FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- Unit: CEL validation suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `platform.type=IBMCloud` and `serviceAnnotations` | Accepted |
| 2 | Modify a `services` entry (e.g. change publishing strategy type) | Accepted — IBMCloud is exempted from immutability |
| 3 | Create HC with `platform.type=AWS` and `serviceAnnotations` | Accepted |
| 4 | Attempt the same `services` modification as step 2 | Rejected by CEL validation |

---

#### 5.6.8 TC-040: CPO-Managed Annotation Precedence

**Objective:** Verify that CPO's own platform annotations end up on the reconciled
KAS Service whatever the user supplied, and that the one key CPO refuses to pass
through — `aws-load-balancer-type` on AWS — is dropped.

**This collision cannot be produced through the API.** Every annotation CPO sets
on the KAS Services falls outside the CEL allowlist:
`service.beta.kubernetes.io/aws-load-balancer-type`,
`.../aws-load-balancer-attributes`,
`.../aws-load-balancer-cross-zone-load-balancing-enabled`,
`.../aws-load-balancer-internal`,
`.../azure-load-balancer-internal`, and
`external-dns.alpha.kubernetes.io/hostname`. Admission rejects all of them before
CPO sees them, so the ordering is only reachable from a unit test that injects
the annotation into the HCP spec.

**What the existing tests actually cover** — two narrower behaviours, neither of
which is general precedence:

- Coexistence: a user annotation and CPO's platform annotations both survive on
  the reconciled Service, with no shared key
  (`TestReconcilePrivateService`, case "When creating a private service with
  serviceAnnotations it should preserve CPO platform annotations").
- The skip guard: a user-supplied `aws-load-balancer-type` is not applied on
  either path (`TestReconcilePrivateServiceAWSNLBAnnotation`, cases "…it should
  ignore a user-supplied NLB annotation").

No case applies a user value for a CPO-managed key and then observes CPO's later
write winning. That test is **missing**, and this case stays a gap until it
exists. A non-skipped CPO-managed key such as
`service.beta.kubernetes.io/aws-load-balancer-attributes` would exercise it.

**Preconditions:** None beyond a reconcilable HCP; the unit tests build the spec in memory.

**Primary method (automated):**

**Test:** KAS Service reconciliation suite in `kas/service_test.go`.

**Run:** `go test ./control-plane-operator/controllers/hostedcontrolplane/kas/ -run 'TestReconcile'`

**Expected outcome:** CPO's platform annotations are present on the reconciled
Service, and a user-supplied `aws-load-balancer-type` is not applied on AWS.

Remaining gap: nothing asserts that CPO's later write overrides an applied user
value, which is what the objective states. The case is not closed by the
existing tests.

**Fallback method (manual):** None available. Admission rejects every
CPO-managed key, so no manual procedure reaches reconciliation with a colliding
annotation.

---

> **⚠️ Implementation status:** The hash stability placeholder mechanism has
> no implementation PR yet. TC-025 through TC-027 and TC-041 are defined
> against enhancement design and are not verifiable until the Day 2
> implementation lands. Tracked by [CNTRLPLANE-4800](https://issues.redhat.com/browse/CNTRLPLANE-4800).

### 5.7 Hash Stability (Unit/Integration)

#### 5.7.1 TC-025: Placeholder Mechanism for Annotation Values

**Objective:** Verify that annotation values are replaced with placeholders
before computing the config hash, so that IP changes don't affect the hash.

**Preconditions:**
- `DeterministicLBIP` FeatureGate enabled.
- A `HostedControlPlane` whose KAS service uses the `LoadBalancer` publishing
  strategy, with `serviceAnnotations` set to an IP-bearing key.
- The placeholder mechanism has no implementation yet — this case is defined
  against the enhancement design (CNTRLPLANE-4800).

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

**Preconditions:**
- `DeterministicLBIP` FeatureGate enabled.
- A reconcilable `HostedControlPlane` able to re-render the NodePool config
  payload, with `serviceAnnotations` set to an IP-bearing key.
- Not implemented yet — defined against the enhancement design
  (CNTRLPLANE-4800).

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

**Note:** Since `serviceAnnotations` and `loadBalancerClass` are gated behind
`DeterministicLBIP` at the API level, these fields cannot be set via the
HostedCluster API with the gate disabled. This test targets the **internal**
hash computation path: the unit test directly calls the config renderer with
annotation values, bypassing API admission. It verifies the code path, not
the user-facing API flow.

**Preconditions:**
- `DeterministicLBIP` FeatureGate **disabled** in the test harness.
- Direct access to the config renderer, so annotation values can be supplied
  without passing HostedCluster admission.
- Not implemented yet — defined against the enhancement design
  (CNTRLPLANE-4800).

**Primary method (automated):**
- Unit test with FeatureGate disabled, calling the config renderer directly.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Disable `DeterministicLBIP` FeatureGate in the test harness | Feature off |
| 2 | Call config renderer directly with annotation A, compute hash | Hash_A |
| 3 | Call config renderer directly with annotation B, compute hash | Hash_B |
| 4 | Compare | Hash_A != Hash_B (expected: hash changes without the feature) |

---

#### 5.7.4 TC-041: IPv6 Bracketing in HAProxy Config Template

**Objective:** Verify the sidecar sed correctly brackets IPv6 addresses in the
haproxy.cfg backend directive.

**Preconditions:**
- `DeterministicLBIP` FeatureGate enabled.
- An IPv6 or dual-stack management cluster, or the ability to render the
  HAProxy config template directly with a supplied address.
- Not implemented yet — defined against the enhancement design
  (CNTRLPLANE-4800).

**Primary method (automated):**
- Unit test in the haproxy config template package.

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Render haproxy.cfg with IPv6 IP `2001:db8::1` | Backend server line is `server controlplane [2001:db8::1]:6443` (bracketed) |
| 2 | Render haproxy.cfg with IPv4 IP `10.0.0.1` | Backend server line is `server controlplane 10.0.0.1:6443` (no brackets) |
| 3 | Compute config hash for both renders | Hashes are identical (placeholder mechanism active) |

---

### 5.8 Provider Validation

> Cilium LB IPAM is an Agent LB implementation; its Agent variant runs in
> periodic CI.

#### 5.8.1 TC-028: Cilium LB IPAM Integration (Agent variant)

**Objective:** Verify deterministic IP assignment works with Cilium LB IPAM on
the Agent platform.

**Preconditions:**
- Agent platform (the management cluster provides the LB).
- Cilium with LB IPAM enabled on the management cluster.
- IP pool configured in Cilium.

**Primary method (automated):**
- E2E: Agent Cilium variant, periodic (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create HC with `serviceAnnotations: {"lbipam.cilium.io/ips": "<target-ip>"}` | HC creation succeeds — `lbipam.cilium.io/` is allowlisted (see TC-019) |
| 2 | Verify Cilium assigns the requested IP | Service LB IP matches requested IP |
| 3 | Verify KAS is reachable | API server responds |

---

#### 5.8.2 TC-042: Azure Annotation Routing to Correct Service

**Objective:** Verify annotations are applied to the correct Azure service
(`KubeAPIServerServiceAzureLB` on port 7443) instead of the standard KAS
Service.

**Preconditions:**
- Azure platform HC with FeatureGate `DeterministicLBIP` enabled.

**Primary method (automated):**
- Unit: Azure service routing suite (see §4 CI table).

**Fallback method (manual):**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create Azure HC with `serviceAnnotations` | HC creation succeeds |
| 2 | Inspect `KubeAPIServerServiceAzureLB` in the HCP namespace | Service has the user-specified annotations |
| 3 | Inspect the standard KAS Service | Does NOT have user annotations |
| 4 | Verify LB assigns IP on the Azure-specific service | IP assigned on `KubeAPIServerServiceAzureLB` |

---

> **⚠️ Implementation status:** `ValidLoadBalancerIPConfiguration` and
> `ValidLoadBalancerIPSupport` conditions are described in the enhancement
> ([enhancements#2117](https://github.com/openshift/enhancements/pull/2117))
> but not introduced by PR #9913 or #9898. TC-029 through TC-032 are not
> verifiable until the condition implementation lands. Tracked by
> [CNTRLPLANE-4801](https://issues.redhat.com/browse/CNTRLPLANE-4801).

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
| 8 | Delete the NodePool's `ValidLoadBalancerIPSupport` condition (simulate pre-reconcile NP) | Condition removed |
| 9 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=False` — absent condition treated as unsupported (conservative) |

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
| 5 | Attempt a Day 2 IP change | Update accepted into spec, but `ValidLoadBalancerIPConfiguration=False` signals the sidecar will not act on non-compliant NodePools until they are upgraded |
| 6 | Upgrade NodePool-2 and NodePool-3 to 5.1+ | Upgrades complete |
| 7 | Inspect HC conditions | `ValidLoadBalancerIPConfiguration=True` |
| 8 | Attempt Day 2 IP change | Accepted and applied |
| 9 | Scale one NodePool to 0 replicas, inspect HC conditions | `ValidLoadBalancerIPConfiguration` still checks zero-replica NodePools (no skip) |

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| MetalLB not available in all CI environments | Medium | High | TC-001 through TC-009, TC-016, TC-029 through TC-032 require MetalLB; document setup steps in test environment |
| SIGUSR2 behavior varies across sidecar implementations | Low | High | TC-005 verifies the specific sidecar; add explicit signal handling tests |
| User annotations conflict with CPO-managed keys | Low | Medium | TC-040 verifies CPO takes precedence for its managed keys; document which keys CPO manages |
| Pre-5.1 NodePools may not exist in CI | Medium | Medium | TC-010, TC-011 may require manual execution with specific release images |
| Cilium only in periodic CI, not presubmit | Low | Low | TC-028 covered by periodic jobs; failures detected within 24h |
| Upgrade flow requires multiple release images | Medium | Medium | TC-029 through TC-032 need pre-5.1 and 5.1+ images; periodic jobs with pinned versions |
| Proxy pod path untested in CI | Medium | Medium | TC-036 covers proxy path; requires proxy-configured test environment |
| IPv6 E2E environment not available | Medium | Low | TC-038, TC-041 unit tests cover format handling; E2E deferred to IPv6-capable CI |
| Azure-specific service routing | Low | Medium | TC-042 unit test; Azure E2E if environment available |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | jparrill | 2026-10-14 |
| Reviewer | | |
