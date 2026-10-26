---
id: TP-CNTRLPLANE-3926-001
version: "1.0"
date: 2026-10-15
title: "In-cluster mirror registry fixture for HyperShift e2e v2"
jira_issues:
  - key: CNTRLPLANE-3926
    role: primary
    url: https://issues.redhat.com/browse/CNTRLPLANE-3926
pull_requests:
  - repo: openshift/hypershift
    number: 9996
    url: https://github.com/openshift/hypershift/pull/9996
    role: implementation
status: draft
tags:
  - e2e
  - test-infrastructure
  - image-mirroring
  - idms
  - aws
ieee_829: true
author: "@Nirshal"
---

# Test Plan: In-cluster mirror registry fixture for HyperShift e2e v2

## 1. Test Plan Identifier

**ID:** TP-CNTRLPLANE-3926-001
**Version:** 1.0
**Date:** 2026-10-15
**IEEE 829 Compliance:** This document follows the IEEE 829-2008 Standard
for Software and System Test Documentation.

**Verification report:** [`reports/cntrlplane-3926/index.html`](../reports/cntrlplane-3926/index.html)
(HTML bundle: three executed scenarios, automated tests, the reproduction kit, and sanitized evidence).

---

## 2. Introduction and Objectives

### 2.1 Purpose

CNTRLPLANE-3926 provides a reusable **in-cluster mirror registry** for HyperShift e2e v2 tests. It is shared by
the OCPSTRAT-3316 stories: CNTRLPLANE-3922 (`imageContentSources` → hosted cluster IDMS), CNTRLPLANE-3923
(`--registry-overrides`) and CNTRLPLANE-3924 (management-cluster IDMS). The deliverable is test infrastructure
(the Go package `test/e2e/v2/util/mirrorregistry` and opt-in wiring in the v2 AWS lifecycle). It does not change
how the product resolves images.

The fixture runs on an OpenShift management cluster and does the following:

1. Deploys `registry` (Distribution v2.8.2) as a Deployment + Service with a PVC, in an owned namespace.
2. Generates a CA (or accepts one supplied by the caller) and serves TLS with a certificate for the Route host
   and the Service names.
3. Copies the requested images through the internal Service with an in-cluster Job that runs `oc` (digests preserved).
4. Restarts the registry **read-only**, and only then exposes it through a **passthrough Route**.
5. Returns the endpoint, the CA bundle and `[]hyperv1.ImageContentSource` for the consuming tests.

This plan defines how the fixture is verified before merge, including whether hosted-cluster nodes can pull from it.

### 2.2 Objectives

1. Verify the design assumptions on a real nested OpenShift management cluster before implementation (Scenario 1).
2. Verify that the Go fixture provisions, re-runs idempotently, keeps its invariants and tears down on a real
   cluster, including caller-supplied CA handling (Scenario 2).
3. Verify that the nodes of a HostedCluster created with the fixture outputs pull from the mirror over verified
   TLS, anonymously and by digest only (Scenario 3).
4. Verify the code paths that are hard to reach live (error handling, retries, ordering invariants, lifecycle
   wiring) with unit tests using fake clients (automated).

### 2.3 Acceptance Criteria Mapping

Acceptance criteria are quoted from CNTRLPLANE-3926 in abbreviated form.

| CNTRLPLANE-3926 Acceptance Criterion | Test Cases |
|--------------------------------------|------------|
| AC1 — A Go helper deploys a registry as Deployment + Service on the management cluster | TC-01, TC-07, TC-19 |
| AC2 — A subset of images is mirrored into the in-cluster mirror; specify which images | TC-02, TC-05, TC-07, TC-19 |
| AC3 — The mirror is accessible from hosted cluster nodes (LoadBalancer, passthrough Route or NodePort) | TC-04, TC-14, TC-15, TC-16 |
| AC4 — TLS with a self-signed CA so pulls work without `--insecure-registry` | TC-01, TC-04, TC-09, TC-12, TC-13, TC-14 |
| AC5 — The helper provides setup/teardown lifecycle for v2 e2e tests | TC-10, TC-11, TC-19, TC-20 |
| AC6 — The helper returns the mirror address and the ImageContentSource entries | TC-07, TC-13, TC-19 |

**Where the implementation deviates from the AC wording (agreed design decisions, see report appendix C):**

- *AC1, "registry:2":* the default image is `quay.io/libpod/registry:2.8.2`, pinned by manifest-list digest. It is
  the same upstream Distribution registry v2.8.2, and pulling it from Quay instead of Docker Hub avoids rate limits in CI (D8).
- *AC2, "which images":* the CI lane added by this PR mirrors the workload image needed by CNTRLPLANE-3928
  (`DefaultRegistryImage`, mirrored to its real repository and to a virtual `.invalid` repository).
  Full release payloads (CNTRLPLANE-3931) are supported through `MirrorRequest.ReleaseImages`
  (`oc adm release mirror`). That path is covered by unit tests and a payload dry-run (TC-05). Mirroring a real payload is verified in CNTRLPLANE-3931.
- *AC4, "evaluate a simpler insecure alternative":* evaluated and rejected. A CA distributed through
  `additionalTrustBundle` at cluster creation avoids a NodePool rollout and needs no `--insecure-registry` (D3).
- *AC5, "Ginkgo tests":* the package has no Ginkgo/Gomega imports. Ginkgo tests, `lifecycle` hooks and future CI
  steps can all call it. The v2 lifecycle calls it from `PlatformConfig.PreCreate` (D1, D9).

### 2.4 Automation-First Principle and Verification Strategy

The fixture *is* test automation, and the e2e job that exercises it end to end (CNTRLPLANE-3929) comes later.
So pre-merge verification combines:

- **Unit tests** in the PR (fake clients) for logic, error paths and invariants (TC-19), and CI build/lint jobs (TC-20).
- **Three manual scenarios** on a real management cluster (TC-01 … TC-18). Each scenario has a runbook, scripted
  PASS/FAIL checks, and the command output pasted verbatim as evidence.
- **Independent evidence verification:** a separate, read-only review session checked the Scenario 3 evidence
  against a written checklist (`VERIFY.md`) without access to clusters. The same checklist can be reused by any third party.

---

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#9996](https://github.com/openshift/hypershift/pull/9996) (head `8d54f7ab32`) |
| Feature Jira | [CNTRLPLANE-3926](https://issues.redhat.com/browse/CNTRLPLANE-3926) (parent: CNTRLPLANE-3922, epic OCPSTRAT-3316) |
| Fixture package | `test/e2e/v2/util/mirrorregistry/` (`api.go`, `options.go`, `tls.go`, `resources.go`, `copier.go`, `registry.go`) |
| Lifecycle wiring | `test/e2e/v2/lifecycle/aws.go`, `test/e2e/v2/lifecycle/mirrorregistry.go`, `test/e2e/v2/cmd/create-guests/main.go` |
| Unit tests | `test/e2e/v2/util/mirrorregistry/*_test.go`, `test/e2e/v2/lifecycle/{aws,mirrorregistry}_test.go` (`e2ev2` build tag) |
| CI shard | `.github/workflows/test-reusable.yaml` (`other` shard) |
| Reproduction kit | `reports/cntrlplane-3926/scripts/` (runbooks, `env.sh`, check scripts, Go harness, manifests) |
| Consumers | CNTRLPLANE-3922/3923/3924 (fixture users), 3927/3928/3932/3933 (assertions), 3929 (Prow job), 3931 (payload mirroring) |

---

## 4. Test Environment

| Property | Value |
|----------|-------|
| Management cluster | OpenShift 4.20.0, itself a HyperShift hosted cluster on AWS (nested management cluster, as in CI) |
| HyperShift operator | Installed on the management cluster; server `e83d9072…` (supports OCP 4.14–4.21), CLI `cce02430…` |
| Hosted cluster (Scenario 3) | Dedicated AWS HostedCluster, OCP 4.20.0, 2 workers, RHCOS 9.6, CRI-O 1.33.4, `us-east-1` |
| Storage | Default StorageClass `gp3-csi` (PVC, RWO) |
| Images | Registry `quay.io/libpod/registry@sha256:e642e860…` (2.8.2); copier `openshift/cli` ImageStream `latest` (oc 4.20) |
| Client tools | `oc`, `hypershift`, `go`, `jq`, `yq`, `openssl`, `curl`, `skopeo`, `envsubst`, `aws` |
| Prerequisites | Kubeconfig context for the management cluster; for Scenario 3, AWS credentials, a public Route53 zone and a pull secret |

---

## 5. Test Cases

Each manual test case lists the runbook steps that execute it. The runbooks live in
`reports/cntrlplane-3926/scripts/<scenario>/RUNBOOK.md`, and the report has the evidence for each step.

### Scenario 1 — Smoke (design validation, pre-implementation)

Hand-written manifests (`scripts/smoke/manifests/`) on the management cluster. Nothing from the PR code runs here.
This scenario validates the decisions that the code then implements.

#### 5.1 TC-01: Registry runs under `restricted-v2` with TLS

**Objective:** The registry image runs as a non-root random UID with a PVC and serves TLS with the fixture certificate.
**Steps:** RUNBOOK steps 1–3, 9.
**Expected result:** Rollout succeeds without PodSecurity warnings; SCC `restricted-v2`; log `listening on [::]:5000, tls`;
probes answer `200` over HTTP/2.

#### 5.2 TC-02: In-cluster copy preserves digests, including a virtual source repository

**Objective:** An `oc image mirror` Job copies a by-digest source to `<internal>/<source-registry>/<path>` and to a
virtual repository (`mirror-source.hypershift-e2e.invalid/...`), trusting the CA via `SSL_CERT_FILE`.
**Steps:** RUNBOOK step 4, step 7 (digest check).
**Expected result:** Job `Complete`, no TLS errors; both repositories serve the source manifest-list digest `sha256:e642e860…`.

#### 5.3 TC-03: Read-only mode rejects pushes and keeps content

**Objective:** `storage.maintenance.readonly.enabled=true` rejects writes, and content survives the restart (PVC).
**Steps:** RUNBOOK step 5, step 7.
**Expected result:** Push Job fails with `HTTP 405 Method not allowed`; previously copied digests are still served.

#### 5.4 TC-04: Passthrough Route: anonymous read, verified TLS, no push

**Objective:** A passthrough Route with an explicit host exposes the registry. Anonymous reads work only with the CA,
and pushes through the Route are rejected.
**Steps:** RUNBOOK steps 6–8.
**Expected result:** `Admitted=True`; `/v2/` → `{} 200` with the CA; curl exit 60 without it; skopeo push → 405;
re-applying the manifests reports `unchanged`.

#### 5.5 TC-05: Release payload sizing and source repositories (discovery)

**Objective:** Record payload size and source repositories, for PVC sizing and `CopyResult.ReleaseSourceRepositories` (CNTRLPLANE-3931).
**Steps:** RUNBOOK step 10 (dry-run, nothing pushed).
**Expected result:** Size summary and IDMS snippet listing `ocp-release` and `ocp-v4.0-art-dev`.

#### 5.6 TC-06: `oc` availability in the CI test image (discovery)

**Objective:** Decide whether copying can run from the CI pod or needs an in-cluster Job.
**Steps:** RUNBOOK step 11.
**Expected result:** Recorded as present or absent. If absent, the in-cluster Job design (D5) is required.

### Scenario 2 — Harness (fixture code on a live cluster)

A thin Go CLI (`scripts/harness/main.go`) calls `mirrorregistry.New`, `Setup` and `Teardown`. `watch.sh` records state
transitions and flags any moment when the Route exists while the registry is configured writable (`VIOLATION`).
`verify.sh` runs 5 PASS/FAIL checks against the public endpoint.

#### 5.7 TC-07: Setup on a fresh namespace returns a complete Result

**Steps:** RUNBOOK step 1.
**Expected result:** Exit 0. Copier image resolved from the `openshift/cli` ImageStream by digest. `Host` = Route host,
`InternalHost` = `mirror-registry.test-mirror-registry.svc:5000`. Two `Images` (real and virtual source) with
`MirrorRef` = `<host>/<source repo>@<digest>`. Two sorted `ImageContentSources`, one mirror each.

#### 5.8 TC-08: Exposure invariant during Setup (D4)

**Steps:** RUNBOOK steps 1 and 3 (watch logs).
**Expected result:** Order is writable → copy Job completes and is removed → read-only rollout → Route admitted.
On re-runs, the Route is withdrawn before writes are re-enabled. No `VIOLATION` line.

#### 5.9 TC-09: Public endpoint and certificate checks

**Steps:** RUNBOOK step 2.
**Expected result:** `verify.sh` 5/5 PASS. Serving certificate has CN `mirror-registry`, SANs (Route host + 4 Service names)
and issuer = fixture CA. Stored CA Secret = returned CA. No leftover copy Job or Secret, config read-only, SCC `restricted-v2`.

#### 5.10 TC-10: Idempotent re-run keeps CA and Result

**Steps:** RUNBOOK step 3.
**Expected result:** Second Setup succeeds; `cmp`/`diff` report CA and Result unchanged; `verify.sh` 5/5 PASS.

#### 5.11 TC-11: Teardown and repeated Teardown

**Steps:** RUNBOOK steps 4, 10.
**Expected result:** Namespace `NotFound`, PV deleted. A second Teardown returns nil immediately.

#### 5.12 TC-12: Caller-supplied CA: use, reuse, rotation

**Steps:** RUNBOOK steps 6–9.
**Expected result:** With a PKCS#8 caller CA: Result CA = stored CA = caller CA, verify 5/5. Without a CA, the stored caller CA
is reused. With a second CA, rotation succeeds (withdrawal trusts the old CA), verify passes, and the old CA is rejected (exit 60).

### Scenario 3 — Reachability (hosted-cluster nodes pull from the mirror)

A dedicated HostedCluster is created with `hypershift create cluster aws --additional-trust-bundle <fixture CA>
--image-content-sources <fixture ICS>`, using the outputs of a fresh fixture Setup. `check.sh hc|guest|pods` prints PASS/FAIL lines.

#### 5.13 TC-13: The HostedCluster carries the fixture CA and image content sources

**Steps:** RUNBOOK steps 1–3.
**Expected result:** `check.sh hc` 3/3 (trust bundle ConfigMap = fixture CA, `spec.imageContentSources` = fixture ICS);
HC `Available`, NodePool 2/2 `AllNodesHealthy`, no condition mentioning the mirror inputs.

#### 5.14 TC-14: Configuration reaches the hosted cluster and its nodes

**Steps:** RUNBOOK steps 4–5.
**Expected result:** `check.sh guest` 7/7. The IDMS maps both repositories to the mirror, and `openshift-config/user-ca-bundle`
= fixture CA. The node `registries.conf` has a digest-only mirror for the virtual repository, and the node trust anchor =
fixture CA. `curl https://<mirror>/v2/` from a node with system trust → `{} 200`.

#### 5.15 TC-15: A pod from the virtual repository by digest pulls from the mirror

**Steps:** RUNBOOK step 6.
**Expected result:** Pod `<virtual repo>@sha256:e642e860…` with `imagePullPolicy: Always` becomes Ready after a real pull
(`Successfully pulled`). The mirror log shows CRI-O `GET /v2/<virtual repo>/manifests/sha256:…` → 200. `.invalid` never
resolves, so only the mirror can have served it.

#### 5.16 TC-16: Negative control: tag pulls do not use the mirror

**Steps:** RUNBOOK step 6.
**Expected result:** The pod referencing `<virtual repo>:2.8.2` fails with a DNS error for `mirror-source.hypershift-e2e.invalid`.
The mirror log shows no tag lookup (IDMS is digest-only).

#### 5.17 TC-17: `imagePullPolicy: Always` re-contacts the mirror (information for CNTRLPLANE-3928)

**Steps:** RUNBOOK step 7.
**Expected result:** Recreating the pod on the same node increases the mirror's manifest request count.

#### 5.18 TC-18: Cleanup leaves no leftovers

**Steps:** RUNBOOK step 8.
**Expected result:** HostedCluster, NodePool and control-plane namespace gone. No VPC or instances tagged with the infra ID.
Fixture namespace `NotFound`.

### Automated

#### 5.19 TC-19: Unit tests

**Objective:** Option validation and defaults, TLS material and CA parsing (RSA keys, PKCS#1/PKCS#8), resource builders, copier Job
and script, result decoding, transient-error retries, Setup orchestration (including the read-only-before-Route invariant,
withdrawal before writes, CA reuse and rotation), Teardown, and the lifecycle wiring (`PreCreate`, cluster specs, `SHARED_DIR` outputs).
**Primary method (automated):**
- `go test -race ./test/e2e/v2/util/mirrorregistry/...`
- `go test -tags e2ev2 -race ./test/e2e/v2/lifecycle/`

**Expected result:** All tests pass.

#### 5.20 TC-20: CI on the PR

**Objective:** The PR passes the repository's build, lint, verify and e2e-compile checks. The end-to-end lifecycle run
(`create-guests` with the `image-mirroring` variant) is out of scope here and becomes the first job of CNTRLPLANE-3929.
**Expected result:** Required checks pass. The report records which checks ran the fixture's unit tests.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| The live scenarios ran at commits that predate the PR head (before a rebase) | Certain | Medium | `git range-diff` shows commits 1–8 patch-identical; the `mirrorregistry` package is byte-identical at the PR head; commit 9 changed only to merge upstream `PreCreate` code (report appendix A) |
| Scenario 3 used the Go harness, not the `create-guests` lifecycle path | Certain | Medium | Both write the same `Result` (CA bundle, ICS marshalled from the same type); unit tests cover the lifecycle file outputs; CNTRLPLANE-3929 runs the real path |
| Unit tests of the new package do not run in the PR's GitHub Actions job (the reusable workflow is consumed from `main`) | Certain | Low | Local `-race` runs at the PR head are attached (report: automated tests); the shard change takes effect once merged |
| Concurrent runs on one management cluster collide on the fixed namespace | Low (one nested management cluster per CI job) | Medium | `Options.Namespace` for shared clusters; same model as the Keycloak fixture |
| Anonymous read access to mirrored content during the job | Certain | Low | Read-only endpoint, ephemeral cluster, per-job hostname; htpasswd can be added later without API change (D4) |

---

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | Alessandro Rossi (@Nirshal) | 2026-10-15 |
| Reviewer | | |
