---
id: TP-CNTRLPLANE-3927-001
version: "1.0"
date: 2026-10-19
title: "E2E v2 test: imageContentSources propagation to the hosted-cluster IDMS and the ignition ConfigMap"
jira_issues:
  - key: CNTRLPLANE-3927
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-3927
pull_requests:
  - repo: openshift/hypershift
    number: 10029
    url: https://github.com/openshift/hypershift/pull/10029
    role: implementation
status: draft
tags:
  - e2e
  - e2e-v2
  - image-mirroring
  - idms
  - ignition
  - aws
ieee_829: true
author: "@Nirshal"
---

# Test Plan: E2E v2 test for imageContentSources propagation

## 1. Test Plan Identifier

**ID:** TP-CNTRLPLANE-3927-001
**Version:** 1.0
**Date:** 2026-10-19
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

**Verification report:** [`reports/cntrlplane-3927/index.html`](../reports/cntrlplane-3927/index.html)
(HTML bundle: one executed live scenario, automated tests, two independent reviews, the reproduction kit and sanitized evidence).

**Implementation PR:** [openshift/hypershift#10029](https://github.com/openshift/hypershift/pull/10029) (draft), stacked on
[openshift/hypershift#9996](https://github.com/openshift/hypershift/pull/9996) (CNTRLPLANE-3926, head `8d54f7ab32`);
the change under test is its last commit, `c9ad656db6`.

---

## 2. Introduction and Objectives

### 2.1 Purpose

CNTRLPLANE-3927 adds an e2e v2 lifecycle test that validates how a HostedCluster's `spec.imageContentSources`
propagates through two **independent** control-plane paths:

1. **HCCO path:** the hosted-cluster-config-operator reconciles a cluster-scoped `ImageDigestMirrorSet/cluster` in the
   hosted cluster, labelled `machineconfiguration.openshift.io/role: worker`.
2. **CPO path:** the control-plane-operator builds the same IDMS in memory and serializes it as YAML into
   `ConfigMap/<HCP namespace>/ignition-config-40-image-content-source` (`data.config`), labelled
   `hypershift.openshift.io/core-ignition-config: "true"`, which feeds node ignition.

The HostedCluster is created by the v2 lifecycle (`create-guests`) with the opt-in `image-mirroring` variant from
CNTRLPLANE-3926: the in-cluster mirror fixture provides the CA and two image content sources (the real
`quay.io/libpod/registry` and a virtual `mirror-source.hypershift-e2e.invalid/libpod/registry`, both mirrored to the
fixture Route). The deliverable is test code only; it does not change product behaviour.

The change consists of `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go` (registration and two `It`s),
`hosted_cluster_image_mirroring_helpers.go` (six private helpers), their unit tests, and a one-symbol linter allowlist
addition (`WithoutConditionDump`).

### 2.2 Objectives

1. Verify that both new specs execute and pass on a real HostedCluster created through the same lifecycle path CI will
   use (`create-guests` → `run-tests` → `destroy-guests`), selected only by the `lifecycle && image-mirroring` filter.
2. Verify the two outputs **independently of the Go code under test**, comparing each one with the HostedCluster spec
   (never one output with the other).
3. Verify that the assertions are not vacuous: they reject empty input, missing or extra sources, wrong associations,
   reordered or duplicated mirrors, wrong labels, wrong objects and malformed payloads (unit tests).
4. Verify registration, discovery and repository quality gates (compile, lint, analyzer, label filters, regressions).

### 2.3 Acceptance Criteria Mapping

Acceptance criteria are quoted from CNTRLPLANE-3927 in abbreviated form.

| CNTRLPLANE-3927 Acceptance Criterion | Test Cases |
|--------------------------------------|------------|
| AC1 — An HC created with `imageContentSources` pointing at the in-cluster mirror results in an IDMS in the hosted cluster with matching mirror entries (HCCO path) | TC-02, TC-03, TC-06, TC-10 |
| AC2 — That IDMS has `machineconfiguration.openshift.io/role: worker` (`ReconcileImageDigestMirrors`) | TC-03, TC-06, TC-10 |
| AC3 — The corresponding ignition ConfigMap is created in the HCP namespace by CPO (`ReconcileImageSourceMirrorsIgnitionConfigFromIDMS`), in a separate `It` | TC-04, TC-07, TC-10 |
| AC4 — v2 conventions (`[Feature:ImageMirroring]`, `RegisterXxxTests`, lifecycle test); HC creation through `create-guests` | TC-01, TC-02, TC-05, TC-08, TC-11, TC-12 |

**Where the tests go beyond the AC wording (agreed design decisions, see report appendix C):**

- *AC1, "matching mirror entries":* the comparison is exact. Source entries may be reordered, but each source must keep
  its mirrors in order and with the same multiplicity, and there must be no missing, extra or duplicate source (D4).
- *AC1, fixture provenance:* each spec first requires both fixture sources in the HC spec, each with a mirror whose host
  is exactly the fixture Route host. An unrelated ICS cannot satisfy the dedicated scenario (D3).
- *AC3, "is created":* the spec also decodes `data.config` as a typed `config.openshift.io/v1` `ImageDigestMirrorSet`
  named `cluster`, checks its worker label and mappings against the HC, and checks the ConfigMap's core-ignition label (D7).
- *Missing input:* in this dedicated lane, an HC without image content sources is a failure, never a skip (D2).
- Not asserted: node consumption of the ignition payload, image pulls (CNTRLPLANE-3928), `mirrorSourcePolicy`,
  removal/update of sources.

### 2.4 Automation-First Principle and Verification Strategy

The deliverable *is* test automation, and its CI job (CNTRLPLANE-3929) comes later. Pre-merge verification combines:

- **Unit tests** in the PR for every helper, with manually written inputs (no production converters as oracles) and
  fake clients (TC-10), plus the local quality gate (TC-11) and CI on the PR (TC-12).
- **One live scenario** that runs the real lifecycle binaries against a real management cluster (TC-01 … TC-09). The
  runbook has scripted PASS/FAIL checks (`check.sh`) that re-check both outputs with `oc`/`jq`, and the command output
  is pasted verbatim as evidence.
- **Two independent reviews:** a fresh session reviewed the complete code change and re-ran the local gate (R1); after
  the run, another read-only session checked the live evidence against a written checklist (`VERIFY.md`) without
  cluster access. Any third party can repeat the second review with the same checklist.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#10029](https://github.com/openshift/hypershift/pull/10029) (draft) |
| Change under test | Commit `c9ad656db6` (`test(e2e): verify image mirroring propagation through independent paths`), parent `8d54f7ab32` |
| Parent PR (dependency) | [openshift/hypershift#9996](https://github.com/openshift/hypershift/pull/9996) — CNTRLPLANE-3926 mirror fixture and lifecycle wiring; [verification report](https://github.com/hypershift-community/test-results-verification/pull/6) |
| Feature Jira | [CNTRLPLANE-3927](https://issues.redhat.com/browse/CNTRLPLANE-3927) (parent CNTRLPLANE-3922, epic OCPSTRAT-3316) |
| Specs | `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go` (`RegisterHostedClusterImageMirroringTests`) |
| Helpers and unit tests | `test/e2e/v2/tests/hosted_cluster_image_mirroring_helpers.go`, `…_helpers_test.go` (`e2ev2` build tag) |
| Linter support | `hack/tools/hypershiftlinter/analyzers/e2eutilallowlist/` (allowlist entry and analyzer test data) |
| Producers (not changed) | HCCO `reconcileImageContentPolicyType`, `globalconfig.ReconcileImageDigestMirrors`; CPO `reconcileCoreIgnitionConfig`, `ignition.ReconcileImageSourceMirrorsIgnitionConfigFromIDMS` |
| Reproduction kit | `reports/cntrlplane-3927/scripts/` (runbook, `env.sh`, `check.sh`, test plan, results template, `VERIFY.md`) |
| Consumers / follow-ups | CNTRLPLANE-3928 (workload pulls), CNTRLPLANE-3929 (Prow job running this lane) |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Management cluster | OpenShift 4.20.0, itself a HyperShift hosted cluster on AWS (nested management cluster, as in CI) |
| HyperShift operator | Server `e83d9072…` (supports OCP 4.14–4.21); CLI and lifecycle binaries built from `c9ad656db6` |
| Hosted cluster | Created by `create-guests`: AWS `us-east-1a`, OCP 4.20.0, 1 NodePool × 2 workers (CLI default instance type) |
| Producers exercised | CPO and HCCO of the 4.20.0 release payload (`ocp-v4.0-art-dev@sha256:5491113a…`) |
| Mirror fixture | CNTRLPLANE-3926 defaults: namespace `test-mirror-registry`, passthrough Route, fixture CA |
| Client tools | `oc`, `go`, `make`, `jq`, `yq`, `xmllint`, `openssl`, `curl`, `aws` |
| Prerequisites | Kubeconfig context for the management cluster, AWS credentials, a public Route53 zone, a pull secret |

---

## 5. Test Cases

Each manual test case lists the runbook steps that execute it. The runbook lives in
`reports/cntrlplane-3927/scripts/propagation/RUNBOOK.md`, and the report has the evidence for each step.

### Scenario 1 — Propagation (live lifecycle run)

`create-guests` with `HYPERSHIFT_E2E_IMAGE_MIRRORING=true` and a one-group test plan (`variant: image-mirroring`,
`labelFilter: "lifecycle && image-mirroring"`) creates the fixture and one HostedCluster; `run-tests` runs the specs;
`check.sh fixture|hc|junit|guest|cm|clean` prints PASS/FAIL lines; `destroy-guests` cleans up.

#### 5.1 TC-01: Only the two new specs are selected

**Objective:** The built suite selects exactly the two image-mirroring specs for the lane filter.
**Steps:** RUNBOOK step 0 (clean tree at the commit under test, build, dry run, preflight).
**Expected result:** `Will run 2 of <N> specs` with both spec names; no pre-existing fixture, Keycloak or HostedCluster.

#### 5.2 TC-02: The lifecycle creates the fixture and one HostedCluster with the fixture CA and ICS

**Objective:** `create-guests` runs the fixture, then the CLI with `--additional-trust-bundle` and `--image-content-sources`
from `SHARED_DIR`, and waits for Available and a completed version rollout.
**Steps:** RUNBOOK step 1.
**Expected result:** exit 0, `All clusters are ready`, one `image-mirroring` cluster; `check.sh fixture` 12/12;
`check.sh hc` 4/4 (HC ICS = fixture ICS, trust bundle = fixture CA, Available, rollout Completed); NodePool 2/2.

#### 5.3 TC-03: Spec 1 passes live (hosted IDMS mappings and worker role)

**Steps:** RUNBOOK step 2.
**Expected result:** `Successfully waited for HC clusters/<name> hosted ImageDigestMirrorSet/cluster mappings and worker role`; spec passed.

#### 5.4 TC-04: Spec 2 passes live (ignition ConfigMap, decoded IDMS)

**Steps:** RUNBOOK step 2.
**Expected result:** `Successfully waited for HC clusters/<name> ConfigMap <HCP ns>/ignition-config-40-image-content-source decoded IDMS mappings and labels`; spec passed.

#### 5.5 TC-05: JUnit reports two executed, passed testcases

**Steps:** RUNBOOK step 2.
**Expected result:** `Ran 2 of <N> Specs`, `2 Passed`, `All test groups passed`, exit 0; `check.sh junit` 6/6
(exactly 2 testcases, both `passed`, no failure/error/skipped, `DryRun=false`).

#### 5.6 TC-06: Independent check of the hosted IDMS against the HC spec

**Steps:** RUNBOOK step 3.
**Expected result:** `check.sh guest` 5/5: HC ICS non-empty; `ImageDigestMirrorSet/cluster` exists, `config.openshift.io/v1`,
cluster-scoped; worker label; mappings = HC ICS (entry order ignored, mirror order kept). No `mirrorSourcePolicy`.

#### 5.7 TC-07: Independent check of the ignition ConfigMap against the HC spec

**Steps:** RUNBOOK step 3.
**Expected result:** `check.sh cm` 6/6: ConfigMap exists in the HCP namespace; core-ignition label; `data.config` decodes as YAML;
payload `config.openshift.io/v1` `ImageDigestMirrorSet` `cluster`, cluster-scoped; worker label; mappings = HC ICS.

#### 5.8 TC-08: The specs are repeatable and read-only

**Steps:** RUNBOOK step 4.
**Expected result:** a second `run-tests` gives the same result; `check.sh junit` 6/6.

#### 5.9 TC-09: Cleanup leaves no leftovers

**Steps:** RUNBOOK steps 6 and 6b.
**Expected result:** `destroy-guests` exit 0; namespaces `clusters`, `keycloak`, `test-mirror-registry` deleted; `check.sh clean` 7/7
(no HC/NodePool/HCP namespace/PV/VPC/instances); S3 OIDC documents, public DNS records and the management-side KAS load balancer gone.

### Automated

#### 5.10 TC-10: Unit tests of the helpers

**Objective:** Input snapshot and fixture provenance, mapping comparison, IDMS and ConfigMap checks, and the exact getters,
including adversarial negative cases (see report "Automated tests").
**Primary method (automated):**
- `go test -tags e2ev2 -race -count=1 -v -run '^TestImageMirroring' ./test/e2e/v2/tests`

**Expected result:** 6 tests, 76 subcases pass; `TestE2EV2` (the cluster suite) is not executed.

#### 5.11 TC-11: Local quality gate

**Objective:** Compile (`make e2ev2`), analyzer test and scoped `golangci-lint` with the HyperShift linter plugin, discovery
with the positive and negative label filters, and regression tests of the lifecycle, fixture and framework packages.
**Expected result:** all commands exit 0; positive filter selects 2 specs, negative filter 0.

#### 5.12 TC-12: CI on the PR

**Objective:** The PR passes the repository's build, lint, verify and e2e-compile checks. The live lane itself is opt-in and
runs in CNTRLPLANE-3929.
**Expected result:** required checks pass on [#10029](https://github.com/openshift/hypershift/pull/10029).

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| The producers exercised are the 4.20.0 payload CPO/HCCO, not current `main` | Certain | Low | The change is test-only; current-main producers are exercised by the CNTRLPLANE-3929 job |
| One live run, not the five consecutive CI runs required to make the job blocking (CNTRLPLANE-3922) | Certain | Medium | Repeatability shown once (TC-08); CI history comes with CNTRLPLANE-3929 |
| A bug shared by both producers is invisible if the outputs are compared with each other | Low | High | Each spec and each `check.sh` phase compares its output with the HC spec only (D4) |
| Assertions pass on empty or unrelated objects | Low | High | Non-empty fixture-backed input required, exact named GETs, cardinality checks, adversarial unit tests (D2, D3, D5) |
| The parent PR #9996 changes before merge | Medium | Medium | Change and evidence anchored to parent head `8d54f7ab32`; re-check before merge |
| The AWS `PreCreate` also deploys Keycloak for an image-mirroring-only plan | Certain | Low | Pre-existing behaviour; cost/flakiness note for CNTRLPLANE-3929 |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | Alessandro Rossi (@Nirshal) | 2026-10-19 |
| Reviewer | | |
