---
id: TP-CNTRLPLANE-4415-001
version: "1.0"
date: 2026-10-21
title: "Configurable Event TTL for HyperShift Hosted Control Planes"
jira_issues:
  - key: OCPSTRAT-3679
    role: primary
    url: https://redhat.atlassian.net/browse/OCPSTRAT-3679
  - key: CNTRLPLANE-4415
    url: https://issues.redhat.com/browse/CNTRLPLANE-4415
pull_requests:
  - repo: openshift/hypershift
    number: 9836
    url: https://github.com/openshift/hypershift/pull/9836
    role: implementation
status: draft
tags:
  - kube-apiserver
  - event-ttl
  - etcd
  - operator-configuration
  - tech-preview
ieee_829: true
author: mehabhalodiya
---

# Test Plan: Configurable Event TTL for HyperShift Hosted Control Planes

## 1. Test Plan Identifier

**ID:** TP-CNTRLPLANE-4415-001
**Version:** 1.0
**Date:** 2026-10-21
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

> **Status of the work under test:** at the time of writing, both the
> enhancement proposal ([openshift/enhancements#2137](https://github.com/openshift/enhancements/pull/2137))
> and the implementation ([openshift/hypershift#9836](https://github.com/openshift/hypershift/pull/9836))
> are **open and unmerged**. This plan describes the design as proposed in
> those PRs. No test result in this document is asserted as having passed —
> results belong in a verification report under `reports/cntrlplane-4415/`.

---

## 2. Introduction and Objectives

### 2.1 Purpose

The hosted kube-apiserver has historically been started with a hardcoded
`--event-ttl=3h`, set in the Control Plane Operator (CPO). Hosted control
planes have no kube-apiserver operator, so the standalone OpenShift
mechanism — `eventTTLMinutes` on the `operator.openshift.io/v1`
`KubeAPIServer` resource, behind the `EventTTL` gate — never reaches a
hosted cluster. Neither the HostedCluster owner nor the service provider's
SRE team had a supported way to change event retention, even though the
hosted etcd is sized and paid for by the service provider.

PR #9836 exposes the setting as a typed field on the HyperShift API:

```yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
spec:
  operatorConfiguration:
    kubeAPIServer:
      eventTTLMinutes: 60
```

This plan defines the verification strategy for that field: its validation,
its propagation to the hosted kube-apiserver, its day-2 mutability, and the
absence of behavioural change for hosted clusters that do not set it.

**Design facts this plan is built on** (taken from the PR diffs, not from the
original annotation proposal, which was explicitly abandoned):

| Aspect | Actual design |
|--------|---------------|
| API surface | `spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes` on `HostedCluster` **and** `HostedControlPlane` (shared `KubeAPIServerOperatorSpec` type) |
| Go type | `int32`, `+optional`, `omitempty` — **not** `metav1.Duration`, **not** an annotation |
| Range | `+kubebuilder:validation:Minimum=5`, `+kubebuilder:validation:Maximum=180` |
| Validation point | **Admission time, via the CRD schema only.** No operator-side validation and no new `ValidConfiguration` condition handling |
| CRD default | **None.** Omitted means "no opinion"; the platform supplies the default |
| Platform default | `defaultEventTTL = "180m"` in `kas/params.go` — changed from the previous literal `"3h"` |
| Rendering | `resolveEventTTL(hcp)` returns `fmt.Sprintf("%dm", …)` when the value is `> 0`, else `defaultEventTTL`; `generateConfig` sets `args.Set("event-ttl", …)` |
| Propagation | No new plumbing. HyperShift Operator already deep-copies `spec.operatorConfiguration` onto the HostedControlPlane; CPO renders the flag into the `kas-config` ConfigMap |
| Rollout | Config change alters the CPO v2 component config hash → kube-apiserver Deployment rolls. Day-2 mutable, no cluster recreation |
| Feature gate | `KubeAPIServerEventTTL`, **enabled in `TechPreviewNoUpgrade` only**; disabled in `Default` |
| Parent-field gating | `operatorConfiguration.kubeAPIServer` is declared on **both** `HCPUserFacingOperatorLogs` and `KubeAPIServerEventTTL`, so `logLevel` stays available in `Default` while `eventTTLMinutes` appears only in TechPreview |

### 2.2 Objectives

1. Verify that omitting the field preserves the pre-existing three-hour
   retention for new and existing hosted clusters, including across upgrade.
2. Verify that in-range values (`5`, representative intermediates, `180`) are
   accepted and converted to the correct whole-minute `--event-ttl` duration.
3. Verify that out-of-range, zero, negative, and malformed values are
   rejected at admission with a clear error, and that no invalid value can
   reach the hosted kube-apiserver.
4. Verify that a configured value propagates `HostedCluster` →
   `HostedControlPlane` → rendered `kas-config` → running kube-apiserver
   process.
5. Verify that changing the value on a running hosted cluster takes effect
   without cluster recreation, rolls the kube-apiserver, and converges.
6. Verify that the feature introduces no regression in unrelated
   HostedCluster behaviour, including the sibling `kubeAPIServer.logLevel`
   setting.

### 2.3 Acceptance Criteria Mapping

CNTRLPLANE-4417 (implementation) acceptance criteria:

| Acceptance Criterion | Test Case |
|----------------------|-----------|
| AC #1 — Cluster administrators can configure the kube-apiserver event TTL per hosted cluster | TC-005 (5.5), TC-007 (5.7) |
| AC #2 — The configured value is validated within an acceptable range | TC-001 (5.1), TC-002 (5.2), TC-011 (5.11) |
| AC #3 — Hosted clusters without a configured value retain the current default behavior | TC-003 (5.3), TC-004 (5.4), TC-010 (5.10) |
| AC #4 — Changes to the event TTL take effect without requiring cluster recreation | TC-005 (5.5), TC-008 (5.8), TC-009 (5.9) |
| AC #5 — Envtest, unit, and E2E coverage passing in CI | TC-001 – TC-005 |
| AC #6 — Documentation merged in openshift/hypershift docs | TC-013 (5.13) |

CNTRLPLANE-4416 (enhancement proposal) acceptance criteria — "proposal
submitted" and "proposal reviewed and merged" — are **document-review
criteria with no executable test**. They are tracked here only as a
precondition: this plan assumes the merged enhancement matches the design
summarised in Section 2.1, and must be revisited if API review changes the
field (for example to `metav1.Duration`, which the enhancement still lists
as an open question).

### 2.4 Automation-First Principle

The primary verification method is the automated suite delivered with
PR #9836 (Section 5.1 – 5.5). Sections 5.6 – 5.13 are **not duplicates** of
those tests; each covers a layer the automated tests provably do not reach —
the running kube-apiserver process, actual event expiry, upgrade, the
`Default` feature set, and documented error handling. Section 6.2 lists the
coverage gaps that motivate them.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Epic | [CNTRLPLANE-4415](https://issues.redhat.com/browse/CNTRLPLANE-4415) — Configurable event TTL for Hosted Control Planes |
| Enhancement task | [CNTRLPLANE-4416](https://issues.redhat.com/browse/CNTRLPLANE-4416) |
| Implementation task | [CNTRLPLANE-4417](https://issues.redhat.com/browse/CNTRLPLANE-4417) |
| Strategy | [OCPSTRAT-3679](https://issues.redhat.com/browse/OCPSTRAT-3679) |
| Enhancement PR | [openshift/enhancements#2137](https://github.com/openshift/enhancements/pull/2137) (open) |
| Implementation PR | [openshift/hypershift#9836](https://github.com/openshift/hypershift/pull/9836) (open) |
| Superseded prior art | [CNTRLPLANE-1617](https://issues.redhat.com/browse/CNTRLPLANE-1617) / [openshift/hypershift#7202](https://github.com/openshift/hypershift/pull/7202) — annotation-based design, approved but closed; **not** the design under test |
| Standalone enhancement | [openshift/enhancements#1857](https://github.com/openshift/enhancements/pull/1857) — `enhancements/kube-apiserver/event-ttl.md` |
| API type | `api/hypershift/v1beta1/operator.go` — `KubeAPIServerOperatorSpec.EventTTLMinutes` |
| Gate wiring | `api/hypershift/v1beta1/hostedcluster_types.go` — second `+openshift:enable:FeatureGate=KubeAPIServerEventTTL` marker on `OperatorConfiguration.KubeAPIServer` |
| Feature gate sets | `api/hypershift/v1beta1/featuregates/featureGate-{Hypershift,SelfManagedHA}-{Default,TechPreviewNoUpgrade}.yaml` |
| Resolution logic | `control-plane-operator/controllers/hostedcontrolplane/v2/kas/params.go` — `resolveEventTTL`, `defaultEventTTL` |
| Rendering logic | `control-plane-operator/controllers/hostedcontrolplane/v2/kas/config.go` — `generateConfig`, `eventTTLOrDefault` |
| Shared manifest helpers | `pkg/manifests/cpo/kas.go` — `KubeAPIServerConfigMapName` (`kas-config`), `KubeAPIServerConfigKey` (`config.json`) |
| Unit tests | `…/v2/kas/params_test.go` (`TestResolveEventTTL`, `TestNewConfigParams`), `…/v2/kas/config_test.go` (`TestGenerateConfig`) |
| CRD schema tests | `cmd/install/assets/crds/hypershift-operator/tests/hostedclusters.hypershift.openshift.io/featuregated.hostedclusters.kubeapiserver-eventttl.testsuite.yaml` |
| E2E test | `test/e2e/v2/tests/hosted_cluster_event_ttl_test.go` (label `hosted-cluster-event-ttl`) |
| E2E registration | `test/e2e/v2/lifecycle/aws.go` — AWS `public` variant label filter |
| Product docs | `docs/content/how-to/configure-ocp-components/kubeapi-server-event-ttl.md` |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Cluster type | HostedCluster on a management cluster |
| Platform | AWS (`public` lifecycle variant is where the e2e is registered); other platforms for regression only |
| Control plane topology | `HighlyAvailable` for rollout tests (TC-008); `SingleReplica` acceptable elsewhere |
| Management cluster feature set | **`TechPreviewNoUpgrade` required** for TC-005 – TC-009 and TC-011. Install the HyperShift Operator with `HYPERSHIFT_FEATURESET=TechPreviewNoUpgrade` |
| Management cluster feature set (TC-006) | `Default` — deliberately, to verify gated-off behaviour |
| OCP / HyperShift version | A build containing PR #9836. For TC-010, a *pre*-#9836 build is also required |
| Tooling | `oc`, `hypershift` CLI, `jq`, Go toolchain (for unit/envtest), `make` |
| Test-only requirement | `KubeAPIServerEventTTL` must appear in the installed `hostedclusters.hypershift.openshift.io` CRD schema; confirm before running cluster-level cases (see TC-006 step 1) |

**Common helper — read the rendered flag:**

```bash
oc get configmap kas-config -n clusters-<hc-name> \
  -o jsonpath='{.data.config\.json}' | jq -r '.apiServerArguments["event-ttl"][0]'
```

---

## 5. Test Cases

### 5.1 TC-001: API validation — accepted values (envtest / CRD schema)

**Objective:** Verify the CRD schema accepts the documented range and the
omitted case, on create and on update.

**Level:** envtest / CRD schema validation.

**Preconditions:** Go toolchain; envtest assets fetched by the make target.

**Primary method (automated):**

- Suite: `cmd/install/assets/crds/hypershift-operator/tests/hostedclusters.hypershift.openshift.io/featuregated.hostedclusters.kubeapiserver-eventttl.testsuite.yaml`
- Harness: `test/envtest` (see `test/envtest/README.md`)
- Run: `make test-envtest-ocp` (all supported OCP K8s versions),
  `make test-envtest-ocp ENVTEST_OCP_K8S_VERSIONS="1.34.1"` (single version),
  or `make test-envtest-api-all`. Also exercised by `make test`.

**Cases present in the suite:**

| # | Case | Expected |
|---|------|----------|
| 1 | `onCreate` `eventTTLMinutes: 5` (minimum) | Accepted |
| 2 | `onCreate` `eventTTLMinutes: 180` (maximum) | Accepted |
| 3 | `onCreate` `eventTTLMinutes: 60` (intermediate) | Accepted |
| 4 | `onCreate` `eventTTLMinutes: 60` alongside `logLevel: Debug` | Accepted — coexists with the sibling field |
| 5 | `onCreate` field omitted entirely | Accepted; stored object carries no value |
| 6 | `onUpdate` `60` → `90` | Accepted — the field is mutable |

**Expected result:** All six cases pass on every envtest API-server version
the harness runs.

**Cleanup:** None — envtest installs and uninstalls the CRD per suite.

---

### 5.2 TC-002: API validation — rejected values (envtest / CRD schema)

**Objective:** Verify out-of-range, zero, and negative values are rejected at
admission with the expected message.

**Level:** envtest / CRD schema validation.

**Primary method (automated):** same suite and run command as TC-001.

**Cases present in the suite:**

| # | Input | Expected error substring |
|---|-------|--------------------------|
| 1 | `eventTTLMinutes: 4` (below minimum) | `spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes in body should be greater than or equal to 5` |
| 2 | `eventTTLMinutes: 181` (above maximum) | `… should be less than or equal to 180` |
| 3 | `eventTTLMinutes: 0` (explicit zero) | `… should be greater than or equal to 5` |
| 4 | `eventTTLMinutes: -1` (negative) | `… should be greater than or equal to 5` |

Case 3 is the important one for API semantics: because the Go zero value also
means "unset", a user writing `0` expecting "never expire" must get a
rejection rather than silent fallback to the default.

**Expected result:** All four creates are rejected with the stated messages.

**Known gap:** the suite has **no `onUpdate` rejection case**. The enhancement
test plan calls for rejection "on both create and update". Covered manually
by TC-011 until a case is added; see Section 6.2.

---

### 5.3 TC-003: Resolution and defaulting (unit)

**Objective:** Verify `resolveEventTTL` and `NewConfigParams` map the API
field onto the `--event-ttl` parameter, and fall back to the platform default
in every unset shape.

**Level:** Go unit test.

**Primary method (automated):**

- `TestResolveEventTTL` in
  `control-plane-operator/controllers/hostedcontrolplane/v2/kas/params_test.go`
- `TestNewConfigParams` in the same file (two new cases)
- Run: `go test ./control-plane-operator/controllers/hostedcontrolplane/v2/kas/... -run 'TestResolveEventTTL|TestNewConfigParams' -count=1`

**Cases:**

| Input HostedControlPlane state | Expected `EventTTL` |
|--------------------------------|---------------------|
| `spec.operatorConfiguration` nil | `180m` |
| `operatorConfiguration` set, `eventTTLMinutes` unset | `180m` |
| `operatorConfiguration` set with only `logLevel: Debug` | `180m` |
| `eventTTLMinutes: 5` | `5m` |
| `eventTTLMinutes: 60` | `60m` |
| `eventTTLMinutes: 180` | `180m` |

**Expected result:** All cases pass. Note the implementation guards on
`> 0`, so a hypothetical negative that bypassed admission would also fall
back to the default rather than render a negative duration.

---

### 5.4 TC-004: Rendering into the kube-apiserver config (unit + fixtures)

**Objective:** Verify the resolved value is rendered as the `event-ttl`
API-server argument, and that the no-opinion path renders `180m`.

**Level:** Go unit test and golden fixtures.

**Primary method (automated):**

- `TestGenerateConfig` case *"When event TTL is configured, it should set
  event-ttl argument"* in `…/v2/kas/config_test.go` — `EventTTL: "60m"` must
  render `apiServerArguments["event-ttl"] == ["60m"]`.
- `defaultKASConfig()` in the same file now asserts `defaultEventTTL`.
- `TestControlPlaneComponents` golden fixtures updated from `3h` to `180m`
  across the base case and the `AROSwift`, `EtcdRestore`, `GCP`, `IBMCloud`,
  `ModernTLS`, and `TechPreviewNoUpgrade` variants, in both the
  `kas_config_configmap` and `kube_apiserver_deployment` fixtures.
- Run: `go test ./control-plane-operator/... -count=1`

**Expected result:** Unit cases pass; no fixture under
`control-plane-operator/controllers/hostedcontrolplane/testdata/kube-apiserver/`
still contains `event-ttl: 3h`.

**Verification that the change is semantically inert:**
`3h` and `180m` are the same duration. Confirm by diffing a fixture pair that
only the literal changed — if any other rendered field moved, the default
change is not inert and the "no behaviour change on upgrade" claim in TC-010
is invalidated.

---

### 5.5 TC-005: Day-2 propagation to the rendered config (e2e)

**Objective:** Verify that setting the field on a running HostedCluster
reaches the rendered kube-apiserver config without recreating the cluster,
and that removing it returns to the default.

**Level:** End-to-end, against a live management cluster.

**Preconditions:**
- Management cluster at `TechPreviewNoUpgrade`; `eventTTLMinutes` present in
  the installed HostedCluster CRD schema.
- A healthy HostedCluster on the AWS `public` variant that does **not**
  already set `eventTTLMinutes`.

**Primary method (automated):**

- Test: `test/e2e/v2/tests/hosted_cluster_event_ttl_test.go` —
  `[sig-hypershift][Jira:Hypershift][Feature:EventTTL] Hosted Cluster Event TTL`
- Ginkgo labels: `lifecycle`, `hosted-cluster-event-ttl`; spec label
  `event-ttl-propagation`
- Build: `make e2ev2` (produces `bin/test-e2e-v2`)
- Select with the Ginkgo label filter `hosted-cluster-event-ttl`. In CI it is
  carried by the AWS `public` lifecycle variant's label filter in
  `test/e2e/v2/lifecycle/aws.go`, which already runs with
  `--feature-set=TechPreviewNoUpgrade`.

**What the test asserts:**

| Step | Assertion |
|------|-----------|
| 1 | The installed HostedCluster CRD exposes `spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes`; otherwise the spec **skips** (on a `Default` management cluster the API server silently prunes the field, so the test would otherwise wait forever) |
| 2 | Unconfigured cluster reports `event-ttl == 180m` |
| 3 | Merge-patch `eventTTLMinutes: 30` onto the HostedCluster succeeds |
| 4 | Within 10 min (10 s poll), `kas-config`/`config.json` reports `event-ttl == 30m` |
| 5 | `ValidHostedClusterConfiguration` condition is present and `True` within 5 min |

**Cleanup (asserted, via `DeferCleanup`):** the test restores the captured
original shape — `operatorConfiguration: null`, `kubeAPIServer: null`, or
`eventTTLMinutes: null` depending on what existed before — and waits for
`event-ttl` to return to `180m`. The three-way patch exists because
`KubeAPIServerOperatorSpec` carries `MinProperties=1`: nulling
`eventTTLMinutes` alone would leave an empty `kubeAPIServer` object and be
rejected.

**Expected result:** Spec passes, or skips with the documented feature-gate
message on a non-TechPreview management cluster. A skip is **not** a pass —
record it as such in the verification report.

---

### 5.6 TC-006: Gated-off behaviour on the `Default` feature set (manual)

**Objective:** Verify what a user sees when the `KubeAPIServerEventTTL` gate
is not enabled, and confirm the parent field's `Default` behaviour is
unchanged.

**Level:** Manual, cluster-level. Not covered by any automated test — the e2e
*skips* in exactly this configuration.

**Preconditions:** Management cluster with the HyperShift Operator installed
at the **`Default`** feature set.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | `oc get crd hostedclusters.hypershift.openshift.io -o jsonpath='{.spec.versions[?(@.name=="v1beta1")].schema.openAPIV3Schema.properties.spec.properties.operatorConfiguration.properties.kubeAPIServer.properties}' \| jq keys` | Lists `logLevel` but **not** `eventTTLMinutes` |
| 2 | Patch a HostedCluster with `eventTTLMinutes: 60` | Patch is accepted by the API server, but the field is **silently pruned** — no error is returned |
| 3 | `oc get hostedcluster <hc> -n clusters -o jsonpath='{.spec.operatorConfiguration.kubeAPIServer}'` | Does not contain `eventTTLMinutes` |
| 4 | Read the rendered flag (helper in Section 4) | `180m` — unchanged |
| 5 | Set `spec.operatorConfiguration.kubeAPIServer.logLevel: Debug` | Accepted and takes effect — the dual-gate declaration did not regress `logLevel` on `Default` |

**Expected result:** Steps 1–4 confirm the feature is inert on `Default`;
step 5 confirms no regression to the pre-existing `HCPUserFacingOperatorLogs`
field.

**Cleanup:** Revert `logLevel`; remove `kubeAPIServer`/`operatorConfiguration`
if the test introduced it.

**Note:** silent pruning (step 2) is expected Kubernetes behaviour for a
gated-off field, but it is a poor administrator experience. Record it; see
Risk R-02.

---

### 5.7 TC-007: Day-1 configuration at cluster creation (manual)

**Objective:** Verify the field can be set when the HostedCluster is first
created, not only as a day-2 patch. The e2e only exercises the day-2 path.

**Level:** Manual, cluster-level.

**Preconditions:** Management cluster at `TechPreviewNoUpgrade`.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Render a HostedCluster manifest (`hypershift create cluster … --render`) and add `spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes: 45` | Manifest applies without validation error |
| 2 | Wait for the HostedCluster to become `Available` | Cluster provisions normally; no additional rollout attributable to the field |
| 3 | `oc get hostedcontrolplane <hc> -n clusters-<hc> -o jsonpath='{.spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes}'` | `45` — the HyperShift Operator mirrored `operatorConfiguration` onto the HCP |
| 4 | Read the rendered flag | `45m` |
| 5 | `oc get deployment kube-apiserver -n clusters-<hc> -o jsonpath='{.spec.template.spec.containers[?(@.name=="kube-apiserver")].args}'` and inspect the mounted config | The running kube-apiserver config carries `45m`; the Deployment did not restart-loop |

**Expected result:** The value is present at every layer from first boot.

**Cleanup:** Destroy the HostedCluster.

**Note on step 3:** this is the only explicit check of the
HostedCluster → HostedControlPlane mirror. PR #9836 adds **no** unit test for
that hop; it relies on the pre-existing deep-copy that already carries
`logLevel`. See Section 6.2.

---

### 5.8 TC-008: Rollout of the running kube-apiserver on a day-2 change (manual)

**Objective:** Verify a change rolls the kube-apiserver Deployment, that the
**running process** picks up the new flag, and that a `HighlyAvailable`
control plane stays available through the rollout. The e2e asserts only the
ConfigMap contents — it never looks at pods.

**Level:** Manual, cluster-level.

**Preconditions:** `TechPreviewNoUpgrade`; a `HighlyAvailable` HostedCluster
with `eventTTLMinutes` unset.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Record `oc get deployment kube-apiserver -n clusters-<hc> -o jsonpath='{.spec.template.metadata.annotations.component\.hypershift\.openshift\.io/config-hash}'` and the current pod names | Baseline captured; rendered flag is `180m` |
| 2 | Start a background availability probe against the hosted cluster API (e.g. `oc get --raw /readyz` in a 1 s loop with a kubeconfig for the hosted cluster) | Probe running |
| 3 | `oc patch hostedcluster <hc> -n clusters --type=merge -p '{"spec":{"operatorConfiguration":{"kubeAPIServer":{"eventTTLMinutes":30}}}}'` | Accepted |
| 4 | Watch the Deployment | `config-hash` annotation changes; a rolling update replaces pods one replica at a time |
| 5 | After rollout, inspect the config mounted by a **new** pod: `oc exec deploy/kube-apiserver -n clusters-<hc> -c kube-apiserver -- cat /etc/kubernetes/config/config.json \| jq '.apiServerArguments["event-ttl"]'` (adjust the mount path to the running spec) | `["30m"]` |
| 6 | Stop the probe and review | No sustained unavailability; only the brief per-replica connection resets expected of any rolling update |
| 7 | `oc get hostedcluster <hc> -n clusters -o jsonpath='{.status.conditions}'` | `Available=True`, `ValidHostedClusterConfiguration=True`, `KubeAPIServerAvailable=True` |
| 8 | Change again, `30` → `90` | A second rollout occurs and converges to `90m` |
| 9 | Re-apply the **same** value `90` | No new `config-hash` and **no** rollout — idempotent reconciliation |
| 10 | Set `eventTTLMinutes: 180` explicitly | Rendered flag is `180m`, byte-identical to the unset default, and therefore **no** rollout relative to the unset state (the stated reason the default literal moved from `3h` to `180m`) |

**Expected result:** Each distinct value produces exactly one rollout and
converges; repeated or default-equivalent values produce none.

**Cleanup:** Remove the whole `kubeAPIServer` object (see the `MinProperties`
caveat in TC-011 step 5) and confirm the flag returns to `180m`.

---

### 5.9 TC-009: Effective event expiry in the hosted cluster (manual)

**Objective:** Verify the setting has its intended *effect* — events actually
expire at the configured TTL — and that the documented "applies to new events
only" behaviour holds. No automated test in PR #9836 observes event lifetime.

**Level:** Manual, cluster-level, in the hosted cluster's data plane.

**Preconditions:** `TechPreviewNoUpgrade`; hosted-cluster kubeconfig. Uses the
minimum TTL so the window fits a test run.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | In the hosted cluster, create a namespace and generate events (e.g. a pod with a deliberately bad image, producing `Failed`/`BackOff` events). Record creation timestamps | Events exist, visible via `oc get events -n <ns>` |
| 2 | Set `eventTTLMinutes: 5` on the HostedCluster and wait for the rollout to complete | Rendered flag `5m`; kube-apiserver `Available` |
| 3 | Immediately re-check the events from step 1 | **Still present** — pre-existing events keep the TTL they were written with. Absence here would contradict the documented behaviour |
| 4 | Generate a fresh batch of events after the rollout and note the time | New events visible |
| 5 | Poll `oc get events -n <ns>` for ~10 min | The step-4 events disappear at approximately 5 minutes (±1 min; expiry is driven by etcd lease TTL, not an exact timer) |
| 6 | Raise the TTL to `120`, wait for rollout, generate new events, and sample at 10 min | New events are still present well past 5 minutes |

**Expected result:** Expiry tracks the configured value for newly created
events; existing events are unaffected by a change.

**Cleanup:** Delete the test namespace; remove the `kubeAPIServer` object.

---

### 5.10 TC-010: Upgrade compatibility / backward compatibility (manual)

**Objective:** Verify a hosted cluster created before the field existed keeps
three-hour retention after its control plane is upgraded, and measure the
one-time config rewrite caused by moving the default literal from `3h` to
`180m`.

**Level:** Manual, cluster-level, across two builds.

**Priority:** Highest of the manual cases. This is the only test that
exercises the upgrade claim in the enhancement's *Upgrade / Downgrade
Strategy* section, and the only one that observes the whole existing fleet
rather than a single purpose-built cluster.

#### Claim under test

The enhancement states, for hosted control planes:

> Existing `HostedCluster` resources predate the field, so it is absent from
> their spec. Absent means "no opinion", which the control-plane-operator
> resolves to the same 180-minute value that is hardcoded today. Upgrading
> the HyperShift operator and control-plane-operator therefore produces a
> byte-identical `--event-ttl=3h` for every existing hosted cluster, and no
> kube-apiserver rollout is triggered by this change alone.

This decomposes into four separable assertions, which this test case
evaluates independently because they do **not** all hold:

| # | Assertion | Pre-assessment from the PR diff | Verified by |
|---|-----------|----------------------------------|-------------|
| A-1 | The field is absent from existing specs and nothing is written into them | Expected to hold — the field carries no CRD default | Step 4 |
| A-2 | Retention is unchanged in effect | Expected to hold — `3h` and `180m` are the same duration | Step 5 |
| A-3 | The rendered config is **byte-identical** | **Expected to FAIL.** PR #9836 changes the rendered literal from `3h` to `180m`. Seven golden fixtures under `control-plane-operator/controllers/hostedcontrolplane/testdata/kube-apiserver/` change from `"event-ttl":["3h"]` to `"event-ttl":["180m"]`, and the PR description states the flip "does change the rendered config once" | Steps 5–7 |
| A-4 | No kube-apiserver rollout is triggered by this change alone | **Expected to need re-wording.** The config-hash necessarily changes, so a rollout *is* triggered; the defensible claim is that it is absorbed by the CPO upgrade, which rolls the kube-apiserver anyway because the CPO ships in the release payload | Steps 6, 8–9 |

A-3 and A-4 are what make this case critical: if the rollout is *not*
absorbed by the upgrade, then every hosted cluster on a management cluster
takes an extra kube-apiserver rollout on upgrade purely to rewrite a literal
into an equivalent one. At fleet scale that is a material event, and it is
invisible to every automated test in PR #9836.

**Preconditions:** A management cluster running a HyperShift build that
**pre-dates** PR #9836, with at least two healthy HostedClusters (so step 9
can distinguish a per-cluster effect from a one-off).

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | On the pre-#9836 build, read the rendered flag for each HostedCluster | `3h` |
| 2 | For each HostedCluster capture: full `kas-config`/`config.json`, the kube-apiserver `config-hash` annotation, `deployment.metadata.generation`, `status.observedGeneration`, and pod names/start times | Baseline captured |
| 3 | Upgrade the HyperShift Operator and CPO to a build containing #9836 | Upgrade completes; every HostedCluster stays `Available` |
| 4 | `oc get hostedcluster <hc> -n clusters -o yaml \| grep -c eventTTLMinutes` | `0` for every cluster — **A-1**. The field has no CRD default, so the API server wrote nothing into any stored object |
| 5 | Read the rendered flag | `180m`. **A-2 holds** (same duration, retention unchanged); **A-3 fails** (not byte-identical to `3h`). Record both |
| 6 | Diff the full `config.json` against the step-2 baseline | `event-ttl` is the **only** differing key. Any other difference invalidates the "semantically inert" argument and must be raised |
| 7 | Compare the `config-hash` annotation to the baseline | Changed — expected and unavoidable given step 5 |
| 8 | Count kube-apiserver rollouts during the upgrade window (`deployment.metadata.generation` delta, pod restart count, `oc get events -n clusters-<hc>`) | **A-4, the decisive measurement.** Exactly **one** rollout, coinciding with the CPO image change. **Two** distinct rollouts — one for the CPO image, a second for the config-hash — means the rewrite is *not* absorbed and the enhancement's claim is wrong as written |
| 9 | Repeat steps 5–8 for the second HostedCluster | Identical behaviour — confirms this is a uniform fleet-wide effect, not an artefact of one cluster |
| 10 | After the upgrade settles, confirm no further rollouts occur on a subsequent reconcile loop | Stable; the rewrite is genuinely one-time, not repeating each reconcile |
| 11 | Opt in post-upgrade: set `eventTTLMinutes: 60` | Accepted; propagates as in TC-005 |

**Expected result:** A-1 and A-2 hold. A-3 is expected to fail as worded.
A-4 holds **only** in the weaker form "no *additional* rollout beyond the one
the CPO upgrade causes anyway" — step 8 decides this.

**Reporting requirement:** Record the step 8 rollout count explicitly in the
verification report, for every cluster observed. A pass/fail verdict on
TC-010 without that number does not discharge this test case.

**If step 8 shows two rollouts,** this is a finding to raise on both PRs, not
a test failure to work around: either the default literal should stay `3h`
(at the cost of `eventTTLMinutes: 180` rendering a spurious change, which is
the trade-off PR #9836 deliberately made in the other direction), or the
enhancement's Upgrade / Downgrade Strategy section must state that existing
clusters take one extra kube-apiserver rollout on upgrade.

**Version skew (optional sub-case):** if the HyperShift Operator can be
upgraded ahead of the CPO, set the field during the skew window. Expected: the
value is accepted and preserved in the spec, the older CPO ignores it and keeps
rendering the old default, and the value takes effect once the CPO is upgraded
— a no-op, not an error.

**Version skew (optional sub-case):** if the HyperShift Operator can be
upgraded ahead of the CPO, set the field during the skew window. Expected: the
value is accepted and preserved in the spec, the older CPO ignores it and keeps
rendering the old default, and the value takes effect once the CPO is upgraded
— a no-op, not an error.

**Cleanup:** Remove the `kubeAPIServer` object from any cluster the test
configured.

---

### 5.11 TC-011: Invalid and malformed input on a live cluster (manual)

**Objective:** Cover the rejection paths that the envtest suite does not
reach: update-time rejection, non-integer input, and the documented
`MinProperties` error on revert.

**Level:** Manual, cluster-level. Deliberately scoped to the delta over
TC-002 — the in-range/out-of-range create matrix is **not** repeated here.

**Preconditions:** `TechPreviewNoUpgrade`; a HostedCluster with
`eventTTLMinutes: 60` already set and propagated.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Patch `eventTTLMinutes: 240` on the **existing** cluster | Rejected at admission: `The HostedCluster "<hc>" is invalid: spec.operatorConfiguration.kubeAPIServer.eventTTLMinutes: Invalid value: 240: … should be less than or equal to 180` |
| 2 | Patch `eventTTLMinutes: 1` | Rejected: `… should be greater than or equal to 5` |
| 3 | Patch `eventTTLMinutes: "60m"` (string, not integer) | Rejected as a type error at decode time — the field is `int32`, so a duration string is not valid input. Record the exact message; it differs from the range errors and is what a user migrating from the standalone `--event-ttl` syntax will hit |
| 4 | Patch `eventTTLMinutes: 60.5` (non-integer number) | Rejected as a type error |
| 5 | After each rejection, read the rendered flag | Still `60m` — no invalid value reached the CPO or the kube-apiserver, and no rollout was triggered |
| 6 | Attempt the naive revert `-p '{"spec":{"operatorConfiguration":{"kubeAPIServer":{"eventTTLMinutes":null}}}}'` when `eventTTLMinutes` is the only property set | Rejected: `spec.operatorConfiguration.kubeAPIServer: Invalid value: 0: … should have at least 1 properties` — matches the warning in the product docs |
| 7 | Use the documented workaround `-p '{"spec":{"operatorConfiguration":{"kubeAPIServer":null}}}'` | Accepted; rendered flag returns to `180m` |
| 8 | Repeat step 6 on a cluster that **also** sets `logLevel` | Accepted — with a sibling property present, nulling `eventTTLMinutes` alone is valid |

**Expected result:** Every invalid input is rejected before reaching a
controller; the cluster's effective configuration is never left in an
inconsistent state; the documented revert workaround works as written.

**Cleanup:** Restore the cluster to its original `operatorConfiguration`.

---

### 5.12 TC-012: Regression (automated + manual)

**Objective:** Verify the change does not alter unrelated HostedCluster
behaviour.

**Level:** Mixed.

**Primary method (automated):**
- Full unit suite: `make test` — in particular `TestControlPlaneComponents`
  across all platform variants, which would catch any unintended rendered
  config change.
- Existing AWS `public` lifecycle e2e variant: all labels in the filter other
  than `hosted-cluster-event-ttl` must continue to pass with the new test
  registered alongside them.
- `make verify-crd-schema` — the CRD schema change must be non-breaking
  relative to the base branch.

**Fallback / additional manual checks:**

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Provision a HostedCluster with **no** `operatorConfiguration` at all | Provisions and reaches `Available` exactly as before; rendered flag `180m` |
| 2 | Set only `kubeAPIServer.logLevel: Debug` (no TTL) | Takes effect; rendered flag stays `180m` — the new field does not disturb the sibling |
| 3 | Set both `logLevel` and `eventTTLMinutes` | Both take effect; one rollout, not two conflicting ones |
| 4 | Exercise the pre-existing kube-apiserver tuning annotations (e.g. `hypershift.openshift.io/goaway-chance`) on the same cluster | Unchanged behaviour; `goaway-chance` and `event-ttl` are rendered independently |
| 5 | Confirm standalone OpenShift is untouched | No file under the standalone kube-apiserver-operator is modified by PR #9836; the HCP change cannot alter standalone defaults |

**Expected result:** No regression in provisioning, in sibling
`operatorConfiguration` fields, or in other kube-apiserver arguments.

---

### 5.13 TC-013: Documentation review (manual)

**Objective:** Verify the shipped documentation matches observed behaviour.

**Level:** Manual review against test execution.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Review `docs/content/how-to/configure-ocp-components/kubeapi-server-event-ttl.md` against TC-005 – TC-011 results | Stated range, default, verification command, and error messages match what was observed |
| 2 | Check the page is reachable from `docs/mkdocs.yml` navigation | Present under *How-to → Configure OCP components* |
| 3 | Check `docs/content/reference/api.md` and `aggregated-docs.md` | `eventTTLMinutes` documented with its range, default, and mutability |
| 4 | Confirm the Tech Preview caveat is stated | Page carries the `KubeAPIServerEventTTL` / `TechPreviewNoUpgrade` notice |

**Expected result:** Documentation is accurate and discoverable. Any mismatch
found while executing TC-005 – TC-011 is filed against the docs, not silently
corrected in the report.

---

## 5.14 Test Level Summary

| Level | Test cases | Automation status |
|-------|-----------|-------------------|
| Unit (Go) | TC-003, TC-004 | Delivered in PR #9836 |
| envtest / CRD schema | TC-001, TC-002 | Delivered in PR #9836 (gap: no `onUpdate` rejection case) |
| End-to-end | TC-005 | Delivered in PR #9836; **skips** unless the management cluster is TechPreview |
| Manual / cluster-level | TC-006 – TC-011 | Not automated — each covers a layer the above do not reach |
| Regression | TC-012 | Mixed: existing automated suites plus manual sibling-field checks |
| Documentation | TC-013 | Manual review |

---

## 6. Risks and Mitigations

### 6.1 Product and test risks

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| R-01 | The default literal change `3h` → `180m` rewrites the rendered kube-apiserver config once, producing a config-hash change and a kube-apiserver rollout on upgrade for **every** hosted cluster, including those that never set the field. The enhancement's Upgrade / Downgrade Strategy section currently claims the upgrade "produces a byte-identical `--event-ttl=3h` for every existing hosted cluster, and no kube-apiserver rollout is triggered by this change alone" — the first half is contradicted by the seven golden fixtures in PR #9836 that change `"event-ttl":["3h"]` to `"event-ttl":["180m"]` | High (the rewrite is certain; the open question is only whether the resulting rollout is absorbed by the CPO upgrade) | Medium at single-cluster scale, High across a fleet | TC-010 treats the claim as four separate assertions (A-1 – A-4) and measures the rollout count directly (step 8) across more than one cluster, rather than accepting either PR's phrasing. Flagged by review on enhancements#2137 as critical |
| R-02 | On a `Default`-feature-set management cluster the field is silently pruned with no error, so an administrator can believe they configured the TTL when they did not | High | Medium | TC-006 documents the behaviour explicitly so it can be surfaced in release notes / docs before GA |
| R-03 | The e2e test **skips** rather than fails on a non-TechPreview management cluster, so a green CI run does not imply the feature was exercised | High | High | Verification reports must record skips distinctly from passes (TC-005). Confirm the AWS `public` variant really runs at `TechPreviewNoUpgrade` for the run being reported |
| R-04 | `MinProperties=1` on `KubeAPIServerOperatorSpec` makes reverting to the default non-obvious and the naive patch fails | Certain | Low | Documented in the product docs and handled in the e2e cleanup; verified by TC-011 steps 6–8 |
| R-05 | Nothing in the delivered tests observes actual event expiry, so a propagation success could mask a kube-apiserver that ignores the flag | Low | High | TC-009 verifies the end effect at the minimum TTL |
| R-06 | The e2e asserts the `kas-config` ConfigMap, not the Deployment rollout or the running pods — a stalled rollout would still pass | Medium | Medium | TC-008 inspects the config-hash, the rolling update, and a new pod's mounted config |
| R-07 | The 10-minute `Eventually` window in the e2e may be tight for a `HighlyAvailable` kube-apiserver rollout on a loaded management cluster, causing flakes | Medium | Low | Track flake rate across CI runs; raise with the author if observed |
| R-08 | Both PRs are unmerged and the enhancement still lists the `int32`-vs-`metav1.Duration` choice as an open question | Medium | High | This plan is versioned; if API review changes the type, bump `version`, update Section 2.1, and re-validate TC-001/TC-002/TC-011 |
| R-09 | `operatorConfiguration.kubeAPIServer` is now declared on two feature gates; a mistake there could remove `logLevel` from the `Default` CRD variant | Low | High | TC-006 step 5 and TC-012 step 2 check `logLevel` on both feature sets |

### 6.2 Known automation coverage gaps

These are gaps in PR #9836's test suite, identified by reading the diff. Each
is covered manually above; each is also a candidate for additional automation
before GA.

1. **No `onUpdate` rejection cases** in the CRD testsuite — only a passing
   `60 → 90` update. The enhancement test plan asks for rejection on create
   *and* update. → TC-011 steps 1–2.
2. **No unit test for the HostedCluster → HostedControlPlane mirror.** The PR
   relies on the pre-existing deep-copy of `spec.operatorConfiguration`. The
   enhancement test plan lists such a test; it was not added. → TC-007 step 3.
3. **No assertion that the kube-apiserver Deployment rolls.** → TC-008.
4. **No assertion about actual event expiry.** The enhancement test plan
   proposes creating an event and watching it expire at a short TTL; the
   delivered e2e does not. → TC-009.
5. **No upgrade test.** Nothing in PR #9836 exercises an existing hosted
   cluster across the upgrade that introduces the field, so the enhancement's
   Upgrade / Downgrade Strategy claim is currently unverified by automation —
   and the golden-fixture change from `3h` to `180m` shows at least part of
   it to be wrong as written. → TC-010, R-01. Highest-value candidate for
   additional automation before GA.
6. **No coverage of the `Default` feature set path** beyond the e2e skip
   guard. → TC-006.
7. **Only one e2e value (`30`) is exercised**; the boundaries `5` and `180`
   are covered at unit and schema level but never end-to-end. → TC-008 step
   10, TC-009 step 2.

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | mehabhalodiya | 2026-10-21 |
| Reviewer | | |
| QE sign-off | | |
