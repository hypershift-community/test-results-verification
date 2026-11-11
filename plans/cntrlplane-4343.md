---
id: TP-CNTRLPLANE-4343-001
title: "Control-plane integration projection ownership"
date: 2026-11-11
status: draft
version: "7.0"
ieee_829: true
author: "Codex (AI-generated draft)"
jira_issues:
  - key: CNTRLPLANE-4343
    role: primary
    url: https://redhat.atlassian.net/browse/CNTRLPLANE-4343
pull_requests:
  - repo: openshift/hypershift
    number: 10244
    role: implementation
    url: https://github.com/openshift/hypershift/pull/10244
---

Plan Status: Draft

Feature: [CNTRLPLANE-4343](https://redhat.atlassian.net/browse/CNTRLPLANE-4343), Extract APIService, endpoint,
and OAuth projection ownership

Component: HyperShift, Hosted Cluster Config Operator resources controller

# Test plan for control-plane integration projection ownership

Test plan identifier: `TP-CNTRLPLANE-4343-001`

Source snapshot: PR [#10244](https://github.com/openshift/hypershift/pull/10244), OPEN, targeting `main`, head
`048cced8aeecbb08cb9debf4241ec6ed37bc74ec`. Snapshot captured 2026-11-10.

Structural reviews compare [base `7880cde58491`](https://github.com/openshift/hypershift/commit/7880cde58491473785ae0f865718a953782e2dc0)
with the recorded source head. The base is the parent of the first characterization commit. It is also the
merge base of the recorded three-commit change.

## 1. Test plan identifier

ID: TP-CNTRLPLANE-4343-001

Version: 7.0

Date: 2026-11-11

Profile: IEEE 829 content profile required by this repository. The earlier Jira identifier was
`CNTRLPLANE-4343-test-plan`.

## 2. Introduction and objectives

PR #10244 moves projection selection and mutation from `resources.go` into `resources/integration`.
Hosted-cluster and control-plane behavior must stay unchanged. The root calls `integration.Reconcile` at two
existing phase positions, using a stage selector.

This plan covers [PR #10244](https://github.com/openshift/hypershift/pull/10244), which changes product code,
tests, test support, and documentation.

The PR changes 2,775 lines across 20 files, with 2,396 additions and 379 deletions. The normalized count is
also 2,775 because no vendor, generated, or separate formatting-only changes were found. Tests account for
1,971 lines, shared test support for 110, documentation for 39, and runtime code for 655.

The six acceptance criteria come from the Jira description. Jira returned no separate acceptance-criteria
field, release version, subtasks, clone links, or backport links.

The [earlier approved plan, part
1](https://redhat.atlassian.net/browse/CNTRLPLANE-4343?focusedCommentId=19438767) and [part
2](https://redhat.atlassian.net/browse/CNTRLPLANE-4343?focusedCommentId=19438778) establish the two-stage
scope and exclude `kubernetes.default` endpoints. This revision retains its 23 case IDs and adds two
error-path cases. The four `TC-REG` items remain review and execution tasks.

## 3. Scope and references

The components under test are the new [integration
domain](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/README.md),
the two root phase adapters in
[resources.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources.go),
and their existing projection mutators.

The projections include OpenShift and OAuth APIService trust, hosted Services and Endpoints, the kubeadmin
hash and source annotation, the OAuth CA bundle, three OAuth clients, and serving-certificate Role and
RoleBinding.

The parent [CNTRLPLANE-4329](https://redhat.atlassian.net/browse/CNTRLPLANE-4329) covers broader control-plane
integration ownership. The prerequisite
[CNTRLPLANE-4338](https://redhat.atlassian.net/browse/CNTRLPLANE-4338), global-configuration extraction, is
Closed. This story blocks [CNTRLPLANE-4340](https://redhat.atlassian.net/browse/CNTRLPLANE-4340), which
remains To Do and owns Konnectivity, connection status, connection checks, and remaining CA projections.

The follow-up extraction is out of scope. Kubernetes API endpoints, external OIDC configuration, monitoring,
OLM, and unrelated CA projections stay in the root. The source requirements specify no cloud,
deployment-topology, performance, or encryption changes.

Cross-cluster testing covers the existing adapters and source kubeadmin annotation. All planned test work
belongs in `openshift/hypershift`.

## 4. Abbreviations

| Abbreviation | Full form |
|---|---|
| AC | Acceptance criterion |
| API | Application programming interface |
| CA | Certificate authority |
| CI | Continuous integration |
| DNS | Domain Name System |
| HCCO | Hosted Cluster Config Operator |
| HCP | HostedControlPlane resource |
| OCP | OpenShift Container Platform |
| OIDC | OpenID Connect |
| OAuth | Open Authorization |
| RBAC | Role-based access control |
| TC | Test case |
| FUNC | Functional test |
| NEG | Negative test |
| AGG | Aggregate-error test |
| ORDER | Phase-order test |
| XC | Cross-cluster test |
| REG | Regression validation task |
| IPv6 | Internet Protocol version 6 |
| CLI | Command-line interface |
| OLM | Operator Lifecycle Manager |
| IEEE 829 | IEEE Standard for Software and System Test Documentation |

## 5. Test environment and version applicability

| Property | Value |
|---|---|
| Test target | HCCO resources controller and integration-domain functions, with isolated hosted-cluster and control-plane fake clients. No live cluster is required. |
| Platform or provider | Platform-independent unit tests. No cloud provider, deployment topology, or management-cluster setup is used. |
| Version or build | PR #10244 head `048cced8aeecbb08cb9debf4241ec6ed37bc74ec`, using Go 1.26.3. The intended OCP release remains an action item. |
| Prerequisites or tooling | The Go toolchain, vendored repository dependencies, standard Go tests with Gomega, and controller-runtime fake clients and interceptors. |

Run the commands in a checkout at the recorded source head with both the base and head commits available.
Record both revisions with structural-review evidence and the tested head with execution results. If the head
changes, update the source snapshot, base/head pair, source links, and coverage assessment. Rerun the affected
cases and structural reviews before accepting results for the new revision.

Use Go 1.26.3 from
[go.mod](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/go.mod) and the
vendored dependencies. These unit tests need no cluster credentials, cloud resources, image builds, or
feature-gate configuration.

Run the following once in the PR checkout before the scenario commands:

```bash
export GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor
export HCCO_RESOURCES=control-plane-operator/hostedclusterconfigoperator/controllers/resources
export HCCO_SOURCE_BASE=7880cde58491473785ae0f865718a953782e2dc0
export HCCO_SOURCE_HEAD=048cced8aeecbb08cb9debf4241ec6ed37bc74ec
test "$(git rev-parse HEAD)" = "$HCCO_SOURCE_HEAD"
```

All 25 cases apply to branches containing this refactor. The change adds no feature gate or version-based
skip.

> Action required. Release applicability. Jira returned no fix version or target version. Record the intended
  OCP release and any backport branches before treating this plan as release-specific.

## 6. Pre-existing verification evidence

The PR author reports the following results. This plan records those claims without independently rerunning
the product tests:

- Resources-controller race tests passed before and after extraction.
- `make verify-ci` passed, including the checks listed by the author.
- `make test` passed for 278 packages. The reported integration-domain statement coverage was 96.8%.
- `make build`, `make e2e`, and `make tests` passed. The last two compile test binaries and do not prove live
  end-to-end behavior.
- Dead-code, commit-message/layout, spelling, container-sync, coverage, and diff checks passed.
- Live environment validation was not run. The earlier Jira plan also records a requester choice to skip it.

The commit history supports characterization-first sequencing. Commit
[`8aa60a55ff17`](https://github.com/openshift/hypershift/commit/8aa60a55ff173cfd7fa5c663382d31b51843a825) adds
characterization without runtime production changes. Commit
[`4b75e97154d5`](https://github.com/openshift/hypershift/commit/4b75e97154d5ac8a9e7b1c7f1a93fe8bd9a3df33)
performs the extraction without modifying `control_plane_integration_test.go`. The current head subsequently
shares tracing helpers. Test execution evidence must identify the commit tested.

> Action required. Current-head verification evidence. Attach the focused race-test and full regression
  results for `048cced8aeecbb08cb9debf4241ec6ed37bc74ec`, or its successor after any test additions. The PR
  body does not tie its results to a SHA. Coverage classification below records assertions found in source,
  not a fresh pass result.

## 7. Criteria assessment

| Acceptance criterion | Testability and verification | Test cases |
|---|---|---|
| AC1: Characterization covers readiness, missing sources, endpoint data, OAuth enablement, and aggregation before extraction. | Observable behaviors map to FUNC, NEG, and AGG scenarios. Commit order and the author's before/after results address the historical sequencing requirement. | TC-FUNC-001, TC-FUNC-002, TC-FUNC-003, TC-FUNC-004, TC-FUNC-005, TC-FUNC-006, TC-FUNC-007, TC-FUNC-008, TC-FUNC-009, TC-NEG-001, TC-NEG-002, TC-NEG-003, TC-NEG-004, TC-NEG-005, TC-NEG-006, TC-NEG-007, TC-NEG-008, TC-NEG-009, TC-AGG-001, TC-AGG-002, TC-AGG-003 |
| AC2: The integration module owns resource selection and policy. | Module scenarios validate behavior. Review task TC-REG-003 verifies ownership and narrow parameters. Ownership itself is a structural requirement. | TC-FUNC-001, TC-FUNC-004, TC-FUNC-006, TC-FUNC-007, TC-FUNC-009, TC-AGG-003 |
| AC3: Cross-cluster reads and writes remain explicit and narrowly scoped. | TC-XC-001/002 and TC-FUNC-005/008 validate the client boundaries. TC-NEG-008/009 address remaining write and cleanup error paths. | TC-XC-001, TC-XC-002, TC-FUNC-005, TC-FUNC-008, TC-NEG-008, TC-NEG-009 |
| AC4: One integration entry point retains phase order and aggregation. | TC-AGG-001/002/003 and TC-ORDER-001/002 validate results and observed operation order. TC-REG-003 checks the two source call positions. | TC-AGG-001, TC-AGG-002, TC-AGG-003, TC-ORDER-001, TC-ORDER-002 |
| AC5: Existing watches and both clusters' behavior remain unchanged. | All behavior scenarios plus TC-REG-002/003. Predicate tests alone cannot establish unchanged watch registration. | TC-FUNC-001, TC-FUNC-002, TC-FUNC-003, TC-FUNC-004, TC-FUNC-005, TC-FUNC-006, TC-FUNC-007, TC-FUNC-008, TC-FUNC-009, TC-NEG-001, TC-NEG-002, TC-NEG-003, TC-NEG-004, TC-NEG-005, TC-NEG-006, TC-NEG-007, TC-NEG-008, TC-NEG-009, TC-AGG-001, TC-AGG-002, TC-AGG-003, TC-ORDER-001, TC-ORDER-002, TC-XC-001, TC-XC-002 |
| AC6: Focused cross-cluster and full resources-controller tests pass. | This is an execution gate, not a separate product behavior. TC-REG-001/004 below specify the commands and evidence. | TC-FUNC-001, TC-FUNC-002, TC-FUNC-003, TC-FUNC-004, TC-FUNC-005, TC-FUNC-006, TC-FUNC-007, TC-FUNC-008, TC-FUNC-009, TC-NEG-001, TC-NEG-002, TC-NEG-003, TC-NEG-004, TC-NEG-005, TC-NEG-006, TC-NEG-007, TC-NEG-008, TC-NEG-009, TC-AGG-001, TC-AGG-002, TC-AGG-003, TC-ORDER-001, TC-ORDER-002, TC-XC-001, TC-XC-002 |

AC6 is a test-execution gate. It does not add a separate product behavior to test.

## 8. Approach and CI placement

All cases use the `unit` tier. Separate fake clients can verify resource contents, errors, and client routing
without an API server. Keep tests beside the production code, following
[TESTING.md](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/TESTING.md).

| Downstream repository | Pre-merge coverage | Post-merge coverage |
|---|---|---|
| `openshift/hypershift` | The unit workflow calls the reusable workflow. Its `cpo-other` shard includes `hostedclusterconfigoperator/...`, covering all scenarios and the tracing helpers. Keep additions in these existing packages. | The reusable workflow has push triggers for `main` and `release-4.22`. No feature-specific periodic job is required or specified for this refactor. |

Sources: [unit
trigger](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/.github/workflows/test.yaml),
[cpo-other shard and push
triggers](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/.github/workflows/test-reusable.yaml),
and [Make
targets](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/Makefile). The
caller references the reusable workflow on `main`; these links describe the reviewed snapshot. CI jobs can run
concurrently. There is no sequential CI execution-phase requirement and no new e2e or payload-tier assignment.

## 9. Test cases

Coverage labels describe assertions found at the reviewed PR head. `[COVERED]` means the assertions exist.
`[PARTIAL]` means some assertions exist. `[NOT COVERED]` identifies tests to add. These labels do not record a
test run.

All target paths belong to `openshift/hypershift`. Add behavior-named subtests to the existing top-level
tests. These packages use standard Go tests. Each verification command must exit with status zero and report
no data race.

### TC-FUNC-001: Project OpenShift APIService trust and service references

Objective: Each OpenShift APIService trusts the control-plane root CA and points to the hosted Service.

Preconditions: Create separate hosted and control-plane fake clients. Provide the root CA and both API server
source Services.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC2, AC5.
- Existing tests: `TestReconcileAPIServiceProjections`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth`.

Steps:

1. Seed separate control-plane and hosted fake clients. Provide `root-ca` with `ca.crt: root-ca-bundle` and
   the API server source Services.
2. Run the API-service projection stage with OAuth enabled.
3. Read every OpenShift APIService selected by `OpenShiftAPIServerAPIServiceGroups()`. Expect the source CA,
   group `<group>.openshift.io`, version `v1`, priorities `9900` and `15`, and service reference
   `default/openshift-apiserver:443`.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
```

Expected results: Every selected APIService has the source CA, its expected group, version v1, priorities 9900
and 15, and service reference default/openshift-apiserver:443.

### TC-FUNC-002: Project the hosted OpenShift API server Service

Objective: The API-service stage creates the hosted OpenShift API server Service and preserves write errors.

Preconditions: Provide valid source inputs and no hosted Services. Prepare a separate case with a failing
hosted Service upsert.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC2, AC5.
- Existing tests: `TestReconcileAPIServiceProjections`, `TestReconcileClusterService`.

Steps:

1. Run the API-service stage with valid source inputs and no hosted Services.
2. Read hosted Service `default/openshift-apiserver`. Expect its port list to contain exactly `https`, port
   `443`, as asserted by the stage test.
3. Inject a hosted Service upsert failure. Expect the original error identity from `reconcileClusterService`
   and continued processing at stage level.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections|TestReconcileClusterService)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: The hosted Service has the https port on 443. A failed upsert preserves the error identity,
and the stage continues later projections.

### TC-FUNC-003: Refresh endpoints when source readiness or addresses change

Objective: Hosted endpoints follow source readiness and address changes across reconciles.

Preconditions: For each API server, seed hosted Endpoints at 10.0.0.1 and a source Service without a
ClusterIP.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [PARTIAL].
- Implementation status: To be automated.
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC5.
- Existing tests: `TestReconcileEndpoints`, `TestReconcileAPIServiceProjections`.

Existing tests cover correct endpoint data, replacement of stale OpenShift endpoints, and separate not-ready
cases. They do not exercise readiness recovery and subsequent address changes across repeated calls for both
servers.

Steps:

1. Parameterize OpenShift and OAuth API server projections. Seed hosted Endpoints with `10.0.0.1` and a source
   Service without a ClusterIP.
2. Reconcile. Expect the existing endpoints to remain unchanged and a not-ready error. Assign the source
   ClusterIP in the fake client and reconcile again.
3. Expect one endpoint address matching the source ClusterIP and the port `https`, `443`, `TCP`. Replace the
   source Service with a new address and reconcile again. Expect the hosted endpoint address to follow it.
4. Repeat without changing inputs. Expect identical endpoint data and no error.

Run after adding the missing subtests:

```bash
go test -race -count=1 -run '^(TestReconcileEndpoints|TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
```

Add the proposed subtests before treating this command as verification of the complete case.

Expected results: An unready source leaves existing endpoints unchanged. Once ready, endpoints use the source
ClusterIP and https/443/TCP. Later address changes update the endpoints. Repeated unchanged input preserves
the data.

### TC-FUNC-004: Project OAuth API server resources when enabled

Objective: OAuth enablement selects the OAuth APIService, Service, and Endpoints projections.

Preconditions: Enable OAuth and provide all control-plane source objects.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC2, AC5.
- Existing tests: `TestReconcileAPIServiceProjections`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth`.

Steps:

1. Use OAuth-enabled parameters with all control-plane inputs present.
2. Run the API-service stage. Expect `v1.oauth.openshift.io` and `v1.user.openshift.io` to trust the
   control-plane root CA and reference `default/openshift-oauth-apiserver:443`.
3. Expect the hosted OAuth API server Service on port `443` and Endpoints at the OAuth source Service
   ClusterIP `172.30.0.11`.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
```

Expected results: The oauth and user APIServices trust the root CA and reference
default/openshift-oauth-apiserver:443. The hosted Service uses port 443, and Endpoints use the source
ClusterIP.

### TC-FUNC-005: Preserve kubeadmin hashing and the control-plane annotation

Objective: The hosted kubeadmin hash and control-plane annotation agree with the source password.

Preconditions: Provide a control-plane password Secret and an unrelated OAuth Deployment. Test absent, stale,
and matching hosted hashes separately.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC5.
- Existing tests: `TestReconcileKubeadminPasswordHashSecret`.

Steps:

1. Provide control-plane Secret `kubeadmin-password` with `password: adminpass`. Test no hosted hash, a stale
   hash, and an already matching bcrypt hash.
2. Reconcile each case. Expect hosted `kube-system/kubeadmin` to contain a bcrypt hash that validates the
   password. Preserve the bytes of an already matching hash.
3. Read the control-plane source Secret. Expect `pkgoauth.KubeadminSecretHashAnnotation` to equal the hosted
   `kubeadmin` hash. Verify the unrelated OAuth Deployment remains present.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileKubeadminPasswordHashSecret)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: The hosted hash validates the password. A matching hash keeps its bytes. The source
annotation equals the hosted hash, and the unrelated Deployment remains present.

### TC-FUNC-006: Project the OAuth serving certificate CA bundle

Objective: The OAuth CA projection copies the source certificate into the hosted bundle.

Preconditions: Seed the control-plane OAuth master CA ConfigMap with ca.crt set to oauth-master-ca.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC2, AC5.
- Existing tests: `TestReconcileOAuthProjections`, `TestReconcileOAuthServingCertCABundle`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileNetworkingAndSecrets`.

Steps:

1. Seed the control-plane ConfigMap returned by `OpenShiftOAuthMasterCABundle(namespace)` with `ca.crt:
   oauth-master-ca`.
2. Run the OAuth stage. Read hosted `openshift-config-managed/oauth-serving-cert`.
3. Expect its data to equal `{"ca-bundle.crt":"oauth-master-ca"}`. Expect the source ConfigMap read to use the
   control-plane client.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileOAuthProjections|TestReconcileOAuthServingCertCABundle)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileNetworkingAndSecrets)$' "./${HCCO_RESOURCES}"
```

Expected results: The hosted oauth-serving-cert ConfigMap contains ca-bundle.crt set to oauth-master-ca. The
source read uses the control-plane client.

### TC-FUNC-007: Preserve OAuth client URLs and serving-certificate RBAC

Objective: OAuth client redirects and serving-certificate RBAC preserve their existing values.

Preconditions: Use fresh fixtures for DNS address oauth.example.com on port 443 and IPv6 address fd00::1 on
port 6443.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC2, AC5.
- Existing tests: `TestReconcileOAuthProjections`. Also
  [oauth/reconcile_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/oauth/reconcile_test.go):
  `TestReconcileOauthServingCertRole` and
  [oauth/reconcile_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/oauth/reconcile_test.go):
  `TestReconcileOauthServingCertRoleBinding`, `TestReconcileBrowserClient`, and
  `TestReconcileChallengingClient`.

Steps:

1. Run OAuth projections with `oauth.example.com:443`, then with IPv6 address `fd00::1` and port `6443` in
   separate cases.
2. Expect browser and challenging-client redirects to use `/oauth/token/display` and `/oauth/token/implicit`.
   Expect IPv6 hosts to be bracketed and the challenging client to respond with challenges.
3. Expect CLI redirects `http://127.0.0.1/callback` and `http://[::1]/callback`, a nonempty browser secret,
   and RoleBinding RoleRef matching the projected Role.
4. Run the adjacent OAuth mutator tests. Expect the Role permissions and RoleBinding subjects to match their
   existing contracts.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileOAuthProjections)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileBrowserClient|TestReconcileChallengingClient|TestReconcileOauthServingCertRole|TestReconcileOauthServingCertRoleBinding)$' "./${HCCO_RESOURCES}/oauth"
```

Expected results: Browser and challenging redirects use the expected paths and bracket IPv6 hosts. CLI
callbacks, browser secret, challenge behavior, Role permissions, and RoleBinding references and subjects match
the existing contracts.

### TC-FUNC-008: Skip OAuth projections for external OIDC

Objective: External OIDC disables OAuth projections without changing the existing hosted hash.

Preconditions: Set HCP authentication to OIDC, or disable OAuth in module parameters. Seed a hosted kubeadmin
hash.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC5.
- Existing tests: `TestReconcileAPIServiceProjections`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth`,
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileNetworkingAndSecrets`,
  [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go):
  `TestReconcileOAuthProjections`.

Steps:

1. Set HCP authentication type to `OIDC` at the root, or use disabled OAuth parameters at module level. Seed
   an existing hosted kubeadmin hash.
2. Run both projection stages. Expect OpenShift API server resources to remain selected. Expect no OAuth
   APIService, OAuth Service, OAuth Endpoints, OAuth CA bundle, OAuthClient, or serving-certificate RBAC
   creation.
3. Expect the existing kubeadmin hash to remain unchanged. Expect no OAuth source reads or control-plane
   writes. At module level, the OAuth-only stage must perform no cluster operations.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections|TestReconcileOAuthProjections)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth|TestReconcileNetworkingAndSecrets)$' "./${HCCO_RESOURCES}"
```

Expected results: OpenShift API server resources still reconcile. OAuth resources are not created, and the
existing hash stays unchanged. The API stage skips OAuth source reads and the annotation write. The OAuth-only
stage performs no cluster operations.

### TC-FUNC-009: Capture narrow HCP and OAuth facts

Objective: Params captures namespace, endpoint facts, and the existing OAuth enablement policy.

Preconditions: Construct HCP objects in memory for each authentication configuration. No API client is
required.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/params_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/params_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC2, AC3.
- Existing tests: `TestParamsFor`.

Steps:

1. Construct parameters for nil configuration, absent authentication, integrated OAuth, and external OIDC.
2. Expect OAuth enabled in the first three cases and disabled for OIDC. Expect the namespace, OAuth address,
   and port to match the inputs.
3. Change the HCP after parameter construction. Expect the captured parameter values to remain unchanged.

Run:

```bash
go test -race -count=1 -run '^(TestParamsFor)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: OAuth is enabled for nil configuration, absent authentication, and integrated OAuth, and
disabled for OIDC. Parameters preserve their captured values after the HCP changes.

### TC-NEG-001: Continue other projections when the root CA is missing

Objective: A missing root CA prevents APIService writes while other projections continue.

Preconditions: Remove the control-plane root-ca Secret and keep the other source objects.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileAPIServicesAndOAuth`. Also
  [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go):
  `TestReconcileAPIServices`.

Steps:

1. Remove control-plane Secret `root-ca` while keeping the other source inputs.
2. Run the API-service stage. Expect zero hosted APIServices and two errors containing `failed to get root ca
   from control plane`.
3. Preserve the outer wording `failed to reconcile openshift apiserver service` and `failed to reconcile
   openshift oauth apiserver apiservices`. Expect Services, Endpoints, and the kubeadmin hash to reconcile.
   Verify the wrapped not-found cause.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
go test -race -count=1 -run '^(TestReconcileAPIServices)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: No APIServices are created. Both root-CA errors retain their original wrappers and not-found
cause. Services, Endpoints, and kubeadmin processing continue.

### TC-NEG-002: Isolate a missing OpenShift API server source Service

Objective: A missing OpenShift API server source Service affects only its endpoint projection.

Preconditions: Omit the control-plane openshift-apiserver Service.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileAPIServicesAndOAuth`. Also
  [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go):
  `TestReconcileAPIServiceProjections`.

Steps:

1. Omit control-plane Service `openshift-apiserver`.
2. Run the API-service stage. Expect no new hosted OpenShift API server Endpoints and error prefix `failed to
   reconcile openshift apiserver endpoints: failed to get openshift apiserver service from control plane`.
3. Expect the hosted Service, OAuth resources, and control-plane kubeadmin annotation write to continue.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: The stage creates no new OpenShift API server Endpoints and returns the wrapped
source-Service error. Hosted Service, OAuth projections, and the kubeadmin annotation still reconcile.

### TC-NEG-003: Preserve existing endpoints while the source is not ready

Objective: An empty source ClusterIP preserves existing hosted endpoints.

Preconditions: Seed a source Service without a ClusterIP and hosted Endpoints with address and port data.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC5.
- Existing tests: `TestReconcileEndpoints`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth`.

Steps:

1. Seed a source Service with an empty ClusterIP and existing hosted Endpoints.
2. Reconcile. Expect `<server> service in control plane does not yet have a cluster IP` and no hosted endpoint
   write.
3. Read the existing hosted Endpoints. Expect their address and port data to remain unchanged. Run the root
   characterization case for the OpenShift API server and the focused module case for the OAuth API server.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileEndpoints)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
```

Expected results: The helper returns the existing readiness error and makes no hosted endpoint write. Existing
address and port data remain unchanged.

### TC-NEG-004: Isolate missing and not-ready OAuth source Services

Objective: An absent or unready OAuth source Service leaves other API-service projections running.

Preconditions: Use separate fixtures with the OAuth source Service absent and with an empty ClusterIP.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileAPIServicesAndOAuth`. Also
  [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go):
  `TestReconcileAPIServiceProjections`.

Steps:

1. Run separate cases with control-plane `openshift-oauth-apiserver` absent and with an empty ClusterIP.
2. Expect no new hosted OAuth Endpoints. Expect the corresponding missing-Service or ClusterIP-readiness error
   with outer prefix `failed to reconcile openshift oauth apiserver endpoints`.
3. Expect the OpenShift API server endpoints and kubeadmin hash processing to continue.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: No new OAuth Endpoints are created. The expected missing-Service or readiness error retains
its outer wrapper. OpenShift endpoints and kubeadmin processing continue.

### TC-NEG-005: Delete the hosted hash only when its source is absent

Objective: An absent source password removes a hosted hash without a control-plane write.

Preconditions: Omit the source password Secret. Test the hosted hash present and absent in separate fixtures.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC5.
- Existing tests: `TestReconcileKubeadminPasswordHashSecret`, `TestDeleteKubeadminPasswordHashSecret`.

Steps:

1. Omit the control-plane kubeadmin password Secret. Run once with a hosted hash Secret and once without one.
2. Reconcile. Expect the hosted hash to be absent and no error in both cases.
3. Expect no control-plane update. When the hosted hash is already absent, expect no Delete call.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileKubeadminPasswordHashSecret|TestDeleteKubeadminPasswordHashSecret)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: The hosted hash is absent after reconciliation, and no error or control-plane update occurs.
An already absent hash causes no Delete call.

### TC-NEG-006: Preserve the hosted hash on other source-read errors

Objective: A source-read error other than NotFound preserves the hosted hash.

Preconditions: Seed a hosted hash and inject a non-not-found error on the control-plane password read.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC5.
- Existing tests: `TestReconcileKubeadminPasswordHashSecret`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth`.

Steps:

1. Seed a hosted hash and inject a non-not-found error `cp unavailable` when reading the control-plane
   password Secret.
2. Reconcile. Expect `failed to get kubeadmin password secret: cp unavailable`. At stage level, expect the
   additional outer prefix `failed to reconcile kubeadmin password hash secret`.
3. Expect the hosted hash bytes to remain unchanged and no control-plane update.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileKubeadminPasswordHashSecret)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth)$' "./${HCCO_RESOURCES}"
```

Expected results: The helper returns the wrapped read error. The stage adds the original outer wrapper. Hash
bytes remain unchanged, and no control-plane update occurs.

### TC-NEG-007: Continue OAuth clients and RBAC after a missing CA

Objective: A missing OAuth master CA does not stop client and RBAC projections.

Preconditions: Remove the control-plane OAuth master CA ConfigMap.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go).
- Coverage status: [PARTIAL].
- Implementation status: To be automated.
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileOAuthProjections`, `TestReconcileOAuthServingCertCABundle`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileNetworkingAndSecrets`.

The existing stage and root tests check the missing-CA error text and continued reconciliation.
Only `TestReconcileOAuthServingCertCABundle` checks the not-found cause. Add that assertion to
`TestReconcileOAuthProjections` so the case also covers the stage wrapper.

Steps:

1. Remove the control-plane OAuth master CA ConfigMap.
2. Run OAuth projections. Expect error prefix `failed to reconcile oauth serving cert CA bundle: cannot get
   oauth master ca bundle` and a wrapped not-found cause.
3. Expect all three OAuth clients and both serving-certificate RBAC resources to reconcile despite the missing
   bundle.

4. In the missing-CA subtest of `TestReconcileOAuthProjections`, assert
   `apierrors.IsNotFound(errs[0])` after the existing error-list assertion. Expect true so the stage-level
   wrapper preserves the typed cause.

Run after adding the missing subtest:

```bash
go test -race -count=1 -run '^(TestReconcileOAuthProjections|TestReconcileOAuthServingCertCABundle)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileNetworkingAndSecrets)$' "./${HCCO_RESOURCES}"
```

The current command covers the existing assertions. Add the stage-level cause assertion before claiming
full coverage.

Expected results: The CA projection returns the original wrappers and not-found cause. All three OAuth clients
and both RBAC resources still reconcile.

### TC-NEG-008: Report a failed control-plane kubeadmin annotation write

Objective: A failed source annotation write is reported and succeeds on retry.

Preconditions: Provide the password Secret. Fail its control-plane upsert after the hosted hash upsert
succeeds.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go).
- Coverage status: [NOT COVERED].
- Implementation status: To be automated.
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC4, AC5.
- Existing tests: `TestReconcileKubeadminPasswordHashSecret`.

Current tests cover a successful source annotation and a failed hosted hash upsert, but not failure of the
subsequent control-plane annotation upsert.

Add stage-wrapper assertions to `TestReconcileAPIServiceProjections` in
[integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).

Steps:

1. Provide the password Secret. Inject sentinel error `annotation write failed` for the control-plane upsert
   of that Secret, after the hosted hash upsert succeeds.
2. Reconcile. Expect the hosted hash to exist and validate the password. Expect `failed to annotate
   kubeadmin-password secret in hcp namespace: annotation write failed`, preserving the sentinel through
   wrapping.
3. Run through the API-service stage. Expect outer prefix `failed to reconcile kubeadmin password hash
   secret`. Remove the failure and retry. Expect the source annotation to match the same hosted hash.

Run after adding the missing subtests:

```bash
go test -race -count=1 -run '^(TestReconcileKubeadminPasswordHashSecret|TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
```

Add the proposed subtests before treating this command as verification of the complete case.

Expected results: The hosted hash remains valid. The error identifies the failed source annotation write and
preserves its cause through the stage wrapper. Retrying without the failure annotates the source with the same
hash.

### TC-NEG-009: Return hosted hash cleanup read and delete errors

Objective: Hosted hash cleanup preserves read and Delete errors and can retry.

Preconditions: Use fresh fixtures for a hosted Get error and a Delete error. Seed the hosted hash for the
Delete case.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go).
- Coverage status: [NOT COVERED].
- Implementation status: To be automated.
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC4, AC5.
- Existing tests: `TestDeleteKubeadminPasswordHashSecret`.

The helper currently tests successful deletion and already-absent behavior. It has no hosted Get-failure or
Delete-failure assertion. Add cases to the existing top-level test; no production API change is needed.

Add stage-wrapper assertions to `TestReconcileAPIServiceProjections` in
[integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).

Steps:

1. Inject a non-not-found error on the hosted hash Get. Call the cleanup helper. Expect the original error and
   no Delete attempt.
2. In another case, seed the hosted hash and inject a Delete error with a client interceptor. Expect that
   error to remain identifiable and the hash Secret to remain present.
3. Run the missing-password path through the API-service stage. Expect the cleanup failure to appear under
   `failed to reconcile kubeadmin password hash secret`. Remove the failure and retry. Expect successful
   deletion.

Run after adding the missing subtests:

```bash
go test -race -count=1 -run '^(TestDeleteKubeadminPasswordHashSecret|TestReconcileAPIServiceProjections)$' "./${HCCO_RESOURCES}/integration"
```

Add the proposed subtests before treating this command as verification of the complete case.

Expected results: A failed Get returns its original error without deleting. A failed Delete leaves the Secret
present. The stage preserves the cleanup cause under its kubeadmin wrapper, and a later retry deletes the
hash.

### TC-AGG-001: Keep API-service failures ordered and independently recoverable

Objective: API-service failures retain their order and causes while later work continues.

Preconditions: Inject distinct APIService-group, Service, Endpoints, and hosted-hash upsert failures.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileAPIServiceProjections`, `TestReconcileAPIServices`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileAPIServicesAndOAuth` and
  [resources_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources_test.go):
  `TestAppendAggregateErrors`.

Steps:

1. Inject distinct failures for APIService groups and selected Service, Endpoints, and hosted hash upserts.
2. Run the stage. Expect later projections and successful APIService groups to continue. Expect one error per
   failed group in the APIService aggregate and the existing outer projection wrappers.
3. Compare stage error messages in execution order and verify each injected cause with `errors.Is`. Run the
   root aggregate tests to confirm domain entries remain individual root entries.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServiceProjections|TestReconcileAPIServices)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth|TestAppendAggregateErrors)$' "./${HCCO_RESOURCES}"
```

Expected results: Successful groups and later projections continue. Each failed group has an aggregate entry.
Stage and root errors retain their order, original wrappers, and identifiable causes.

### TC-AGG-002: Keep OAuth-stage failures ordered and preserve root status

Objective: OAuth-stage failures preserve root error entries and reconciliation status.

Preconditions: Inject distinct failures into OAuth CA, client, Role, and RoleBinding upserts. Use the root
fixture for status assertions.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC4, AC5.
- Existing tests: `TestReconcileOAuthProjections`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileNetworkingAndSecrets` and
  [foundation_order_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go):
  `TestReconcile`.

Steps:

1. Inject distinct failures for the OAuth CA bundle, clients, Role, and RoleBinding.
2. Run the OAuth stage. Expect every remaining projection to be attempted and error messages to retain their
   original order and wrapping.
3. Run the root reconciliation case with failures in both integration stages. Expect each additional
   projection failure as an individual root entry and the `ConfigOperatorReconciliationSucceeded` condition to
   be False with `Message == err.Error()`.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileOAuthProjections)$' "./${HCCO_RESOURCES}/integration"
go test -race -count=1 -run '^(TestReconcileNetworkingAndSecrets|TestReconcile)$' "./${HCCO_RESOURCES}"
```

Expected results: The stage attempts later projections and returns ordered errors. Root aggregation keeps
separate entries and sets ConfigOperatorReconciliationSucceeded to False with Message equal to err.Error().

### TC-AGG-003: Return nil on success and reject unknown stages without access

Objective: The domain returns nil on success, aggregates failures, and rejects unknown stages.

Preconditions: Use fresh valid fixtures for both stages, separate injected-failure fixtures, and Stage(99) for
the invalid-stage case.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/reconcile_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/reconcile_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC2, AC4.
- Existing tests: `TestReconcile`.

Steps:

1. Call `integration.Reconcile` separately with valid inputs for `APIServiceProjections` and
   `OAuthProjections`. Expect nil rather than an empty aggregate.
2. Inject several projection failures. Expect one aggregate containing the ordered projection failures.
3. Call with `Stage(99)`. Expect `unknown integration reconciliation stage: 99` and no hosted or control-plane
   operations.

Run:

```bash
go test -race -count=1 -run '^(TestReconcile)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: Both successful stages return nil. Failures return one ordered aggregate. An unknown stage
returns the expected error without cluster access.

### TC-ORDER-001: Keep API-service projections at their existing root phase

Objective: API-service projections keep their existing root phase position.

Preconditions: Use the root reconciliation fixture and recording upsert provider in foundation_order_test.go.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC4, AC5.
- Existing tests: `TestReconcile`.

Steps:

1. Run the root reconciler with the recording upsert provider in the existing integration-order subtest.
2. Expect the integration APIService, Service, Endpoints, hash, and source-annotation operations to follow the
   connection-check resources and precede the Kubernetes API server ServiceMonitor.
3. Use the recorded base/head comparison in TC-REG-002 to verify that the integration call remains after
   both connection-condition methods. The operation trace does not directly prove status-condition call ordering.

Run:

```bash
go test -race -count=1 -run '^(TestReconcile)$' "./${HCCO_RESOURCES}"
```

Expected results: Projection operations follow connection-check resources and precede the Kubernetes API
server ServiceMonitor. Source review confirms the integration call follows both connection-condition methods.

### TC-ORDER-002: Keep OAuth projections at their existing networking phase

Objective: OAuth projections keep their existing networking phase position.

Preconditions: Use the root recording fixture and networking-and-secrets fixture. Prepare a separate failing
OAuth case.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go).
- Coverage status: [PARTIAL].
- Implementation status: To be automated.
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC4, AC5.
- Existing tests: `TestReconcile`. Also
  [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go):
  `TestReconcileNetworkingAndSecrets`.

The existing tests check phase order on the successful run. They do not assert that controller-manager
CA processing continues after an OAuth projection failure. Add that failure-path assertion to the root
`TestReconcile` case.

Steps:

1. Run the root reconciliation ordering subtests and the networking-and-secrets characterization test.
2. Expect OAuth CA, browser client, challenging client, CLI client, Role, and RoleBinding in their original
   order after proxy CA processing.
3. Use the recorded base/head comparison in TC-REG-002 to verify that the OAuth-stage call remains before
   cloud credential secrets and cloud config.
4. In the failing root reconciliation case, retain the attempt trace returned by `newRoot`. Assert that
   `upsert hosted *v1.ConfigMap openshift-controller-manager/openshift-service-ca` occurs after the injected
   OAuth projection failure. Require both operations to be present and the CA upsert to appear later.

Run after adding the failure-path assertion:

```bash
go test -race -count=1 -run '^(TestReconcile|TestReconcileNetworkingAndSecrets)$' "./${HCCO_RESOURCES}"
```

The current command covers successful ordering and error handling. Add the continuation assertion before
claiming full coverage.

Expected results: OAuth projections retain their order after proxy CA processing and before cloud credentials.
Later controller-manager CA processing continues after a projection failure.

### TC-XC-001: Limit cross-cluster access to declared projection objects

Objective: Each projection uses its declared cluster client and source objects.

Preconditions: Use separate recording clients and enabled and disabled OAuth fixtures. Capture traces before
assertion reads.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC1, AC3, AC5.
- Existing tests: `TestReconcileAPIServicesAndOAuth`, `TestReconcileNetworkingAndSecrets`. Also
  [integration/adapters_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/adapters_test.go):
  `TestNewHostedCluster` and
  [integration/adapters_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/adapters_test.go):
  `TestNewControlPlane`. The unfiltered stage traces are checked by
  [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go):
  `TestReconcileAPIServiceProjections` and
  [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go):
  `TestReconcileOAuthProjections`.

The root tests filter control-plane operations to known projection objects. Use the stage tests' unfiltered
control-plane traces to check that no additional source objects are read. Adapter tests check client wiring.

Steps:

1. Run `TestReconcileAPIServiceProjections` and `TestReconcileOAuthProjections` with their separate recording
   clients. Capture the unfiltered control-plane traces before assertion reads.
2. Expect API-stage control-plane reads of `root-ca`, `openshift-apiserver`, `openshift-oauth-apiserver`, and
   `kubeadmin-password`. Expect the only control-plane write to update the kubeadmin password Secret
   annotation.
3. Expect the OAuth stage to read only its master CA ConfigMap from the control plane. Expect projected
   resources on the hosted client. Run disabled cases to confirm OAuth reads and the source annotation write
   disappear.
4. Run module adapter tests to verify that reads, upserts, and hosted deletion use the supplied client and
   upsert function.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileAPIServicesAndOAuth|TestReconcileNetworkingAndSecrets)$' "./${HCCO_RESOURCES}"
go test -race -count=1 -run '^(TestNewHostedCluster|TestNewControlPlane|TestReconcileAPIServiceProjections|TestReconcileOAuthProjections)$' "./${HCCO_RESOURCES}/integration"
```

Expected results: Reads and writes use their declared clients. The kubeadmin annotation is the only
control-plane projection write. Unfiltered stage traces contain no additional source reads. Disabling OAuth
removes its source reads and annotation write.

### TC-XC-002: Preserve root client and upsert error-handling behavior

Objective: Root client wiring and aggregate flattening preserve existing error behavior.

Preconditions: Use root error-injection fixtures and fresh error slices in resources_test.go.

- CI tier: `unit`.
- Tier justification: Fake clients can verify the resource changes and returned errors.
- Target file path:
  [openshift/hypershift/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources_test.go).
- Coverage status: [COVERED].
- Implementation status: Implemented in [PR #10244](https://github.com/openshift/hypershift/pull/10244).
- OCP version applicability: Builds containing PR #10244. No version-based skip.
- Traceability: AC3, AC4, AC5.
- Existing tests: `TestReconcileErrorHandling`, `TestAppendAggregateErrors`.

Steps:

1. Run existing root error-injection cases using the shared create-or-update provider.
2. Expect their existing read and create-count assertions to pass with the extracted domain wired to the same
   hosted and control-plane clients.
3. Run `TestAppendAggregateErrors`. Expect nil errors to leave existing entries unchanged, aggregate entries
   to append individually in order, and ordinary errors to append as one entry.

Run:

```bash
go test -race -count=1 -run '^(TestReconcileErrorHandling|TestAppendAggregateErrors)$' "./${HCCO_RESOURCES}"
```

Expected results: Existing read and create-count assertions pass. Nil errors leave entries unchanged,
aggregates append individual entries in order, and ordinary errors append once.

## 10. Existing test coverage and gaps

The plan has 25 unit cases. Existing assertions cover 20, partially cover three, and leave two to add.

| Scenario | Coverage | Source evidence or remaining work |
|---|---|---|
| TC-FUNC-001 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileAPIServiceProjections` |
| TC-FUNC-002 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileAPIServiceProjections` |
| TC-FUNC-003 | [PARTIAL] | Existing tests cover correct endpoint data, replacement of stale OpenShift endpoints, and separate not-ready cases. They do not exercise readiness recovery and subsequent address changes across repeated calls for both servers. |
| TC-FUNC-004 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileAPIServiceProjections` |
| TC-FUNC-005 | [COVERED] | [integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go): `TestReconcileKubeadminPasswordHashSecret` |
| TC-FUNC-006 | [COVERED] | [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go): `TestReconcileOAuthProjections` |
| TC-FUNC-007 | [COVERED] | [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go): `TestReconcileOAuthProjections` |
| TC-FUNC-008 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileAPIServiceProjections` |
| TC-FUNC-009 | [COVERED] | [integration/params_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/params_test.go): `TestParamsFor` |
| TC-NEG-001 | [COVERED] | [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go): `TestReconcileAPIServicesAndOAuth` |
| TC-NEG-002 | [COVERED] | [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go): `TestReconcileAPIServicesAndOAuth` |
| TC-NEG-003 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileEndpoints` |
| TC-NEG-004 | [COVERED] | [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go): `TestReconcileAPIServicesAndOAuth` |
| TC-NEG-005 | [COVERED] | [integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go): `TestReconcileKubeadminPasswordHashSecret` |
| TC-NEG-006 | [COVERED] | [integration/kubeadmin_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/kubeadmin_test.go): `TestReconcileKubeadminPasswordHashSecret` |
| TC-NEG-007 | [PARTIAL] | [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go): `TestReconcileOAuthProjections`. The stage and root tests check error text; add a typed not-found cause assertion to the stage test. |
| TC-NEG-008 | [NOT COVERED] | Current tests cover a successful source annotation and a failed hosted hash upsert, but not failure of the subsequent control-plane annotation upsert. |
| TC-NEG-009 | [NOT COVERED] | The helper currently tests successful deletion and already-absent behavior. It has no hosted Get-failure or Delete-failure assertion. Add cases to the existing top-level test; no production API change is needed. |
| TC-AGG-001 | [COVERED] | [integration/apiservices_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/apiservices_test.go): `TestReconcileAPIServiceProjections` |
| TC-AGG-002 | [COVERED] | [integration/oauth_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/oauth_test.go): `TestReconcileOAuthProjections` |
| TC-AGG-003 | [COVERED] | [integration/reconcile_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/reconcile_test.go): `TestReconcile` |
| TC-ORDER-001 | [COVERED] | [foundation_order_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go): `TestReconcile` |
| TC-ORDER-002 | [PARTIAL] | [foundation_order_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go): `TestReconcile`. Successful ordering is checked; add the controller-manager CA continuation assertion after an OAuth failure. |
| TC-XC-001 | [COVERED] | [control_plane_integration_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/control_plane_integration_test.go): `TestReconcileAPIServicesAndOAuth`. The integration stage tests assert the unfiltered control-plane traces. |
| TC-XC-002 | [COVERED] | [resources_test.go](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources_test.go): `TestReconcileErrorHandling` |

The adjacent `oauth/reconcile_test.go` covers browser and challenging redirects, Role permissions, and
RoleBinding subjects. The adjacent `kubeadminpassword/reconcile_test.go` covers bcrypt generation,
replacement, and preservation. The new `internal/testtrace/testtrace_test.go` validates the shared recorder
and failure-injection helpers. These supporting tests are not counted as extra product scenarios.

The root `TestReconcileRequeueBehavior`, `TestReconcileConfigOperatorReconciliationCondition`,
`TestReconcileKASEndpoints`, `TestReconcileAuthOIDC`, connection-condition tests, and metrics-forwarder tests
provide regression coverage around the moved code. The complete resources subtree includes them.

> Action required. Endpoint recovery coverage. Extend TC-FUNC-003 with repeated reconciliation after source
  readiness and address changes for both API server projections.

> Action required. Continuation after OAuth failure. Add the controller-manager CA failure-path
  assertion described in TC-ORDER-002.

> Action required. OAuth missing-CA error cause. Add a typed not-found cause assertion to
  `TestReconcileOAuthProjections` as described in TC-NEG-007.

> Action required. Control-plane annotation error coverage. Add TC-NEG-008 to distinguish a failed source
  annotation write from a failed hosted hash write, and verify retry behavior.

> Action required. Hosted hash cleanup error coverage. Add TC-NEG-009 for non-not-found hosted reads and
  Delete failures, including the stage-level wrapper.

## 11. Regression testing and review tasks

These retain the earlier plan's TC-REG identifiers for traceability. They are execution or review tasks, not
additional runtime scenarios.

### TC-REG-001: Run the complete resources-controller regression suite

Run in the PR checkout. Expect exit status zero, no race report, and passing root, integration-domain,
tracing-helper, configuration, OAuth, OpenShift API, and kubeadmin-password packages.

```bash
go test -race -count=1 "./${HCCO_RESOURCES}/..."
```

Keep the command, full output, tested commit, and toolchain version. Run the complete subtree even if the
focused commands pass.

### TC-REG-002: Verify that watches and requeue behavior are preserved

Compare `resources.go` between `HCCO_SOURCE_BASE` and `HCCO_SOURCE_HEAD`, as recorded above. Expect no
changes to `Setup`, watch registrations, predicates, or requeue behavior. Keep both revisions and the diff
with the review evidence. Use the same comparison for TC-ORDER-001, TC-ORDER-002, and TC-REG-003. Run the
existing predicate and requeue tests:

```bash
go test -race -count=1 -run '^(TestNamespacedNamePredicateFunc|TestNotUserCABundlePredicate|TestReconcileRequeueBehavior)$' "./${HCCO_RESOURCES}"
git diff --no-ext-diff --no-color "$HCCO_SOURCE_BASE" "$HCCO_SOURCE_HEAD" -- "${HCCO_RESOURCES}/resources.go"
```

The reviewed diff leaves watch registration unchanged. Live watch delivery has not been tested.

### TC-REG-003: Verify domain ownership and adjacent behavior

Review [root
orchestration](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources.go),
[Params](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/params.go),
and
[adapters](https://github.com/openshift/hypershift/blob/048cced8aeecbb08cb9debf4241ec6ed37bc74ec/control-plane-operator/hostedclusterconfigoperator/controllers/resources/integration/adapters.go).

- Expect one `integration.Reconcile` entry-point symbol at two phase positions: after both
  connection-condition methods and before the Kubernetes API server ServiceMonitor, then after proxy CA
  processing and before cloud credentials.
- Expect the included selection and mutation policy in `resources/integration`. `Params` contains only
  namespace, OAuth enablement, OAuth address, and OAuth port.
- Expect the kubeadmin annotation to remain the only control-plane projection write. The control-plane adapter
  exposes no projection Delete or status mutation.
- Expect Kubernetes API endpoints, external OIDC, Konnectivity, connection checks and conditions, monitoring,
  and unrelated CA projections to stay in their existing owners.
- Review `appendAggregateErrors` and its reuse for observed configuration, because that helper also changes
  how another domain's aggregate reaches root status.

The diff changes no ignition, MachineConfig, NodePool config hash, or registry-authentication policy. It
should not trigger a fleet-wide NodePool rollout. Reassess the operator-upgrade gate if that scope changes.

### TC-REG-004: Collect the existing repository gate results

Require the existing PR checks to pass at the delivery head. For local reproduction of the author-reported
checks, use the declared repository targets:

```bash
make test
make verify-ci
make build
make e2e
make tests
```

`make e2e` and `make tests` are compilation evidence. Do not record them as live-cluster execution. This plan
does not request provisioning or live environment validation.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A projection reads or writes through the wrong cluster client after extraction. | Run TC-XC-001 and TC-XC-002 with separate clients and assert the source annotation is the only control-plane projection write. |
| A transient missing source overwrites valid hosted endpoints or deletes a hash on the wrong error. | Run TC-NEG-001 through TC-NEG-009 and extend TC-FUNC-003 with repeated reconciliation through source readiness and address changes. |
| Aggregation or phase-order changes alter root status messages or stop later work. | Run TC-AGG-001 through TC-AGG-003 and TC-ORDER-001/002. Review the two call positions and the aggregate helper. |
| Compiling test binaries or citing results from another commit is mistaken for verification of this PR head. | Record the tested SHA with full race-test output. Keep compilation evidence and author-provided results separate from execution performed for acceptance. |
| The intended release or backport scope is assumed without a Jira target version. | Keep this plan in Draft and resolve the release-applicability action before release-specific acceptance. |

## 13. Success criteria

- [ ] AC1: The characterization-first commit order is verified and before/after execution evidence is
      retained.
- [ ] AC1 and AC5: All 25 behavior scenarios pass, including the added recovery and error-path assertions, or
      the reviewer explicitly records any accepted coverage exclusions.
- [ ] AC2 and AC3: TC-REG-003 confirms domain ownership, narrow parameter facts, and explicit cluster routing.
- [ ] AC4: Error text, error order, individual root aggregate entries, and the root reconciliation condition
      match the existing behavior.
- [ ] AC4 and AC5: Both phase positions and all watch registrations remain unchanged.
- [ ] AC6: The complete resources race suite and applicable repository checks pass on the recorded delivery
      SHA.
- [ ] The intended release is recorded and the seven action-required items are resolved or explicitly accepted
      by the reviewer.

## 14. Troubleshooting

- If package `resources/integration` does not exist, use a checkout containing the reviewed PR head.
- If endpoint tests fail, compare the source Service ClusterIP and hosted endpoint subsets. An empty source
  ClusterIP must preserve existing endpoint data.
- If OIDC cases touch OAuth resources, inspect `ParamsFor` and both stage guards. An existing hosted hash is
  left untouched when OAuth is disabled.
- If root aggregate counts or status messages change, inspect `appendAggregateErrors`. Preserve individual
  domain entries and their original wrappers. The OpenShift APIService outer error intentionally retains the
  older word `service`.
- If a narrow-access trace fails, capture the trace before assertion reads and check which client the adapter
  passes to the upsert provider.
- If a new case fails the test-function linter, extend the existing matching `Test<FunctionName>` function
  with a behavior-named subtest.

## 15. Review and delivery

This plan follows the [repository format
contract](https://github.com/hypershift-community/test-results-verification/blob/c70865b77e74a9c9591dbe1e328d3ae0088decf2/docs/format.md).
It remains Draft while the target release, current-head product test results, and five coverage additions
await review.

Jira provides no QA contact, approver, or execution schedule. Assign those roles during review. No additional
staffing or training requirement is identified for the existing Go test packages.

Stop acceptance if a characterization case changes output, cross-cluster writes expand, or phase or watch
behavior changes. Keep the failure and tested commit with the review. Resume after fixing the refactor or
approving the behavior change.

Deliver the reviewed plan, any adopted subtests, the tested commit, focused and full regression logs,
repository check results, and structural review. Product tests and live validation have not been run for this
plan.

## 16. Approvals

| Role | Name | Date |
|---|---|---|
| Author | Codex, AI-generated draft | 2026-11-10 |
| Reviewer | Pending | Pending |

The author row records document generation. This revision remains Draft until a reviewer checks the cases,
resolves or accepts the action items, and records approval.

## 17. Artifact validation

Use `verify-artifacts` from [validator PR
#10](https://github.com/hypershift-community/test-results-verification/pull/10) at commit
`c70865b77e74a9c9591dbe1e328d3ae0088decf2`, with Gitleaks 8.30.1.

Install the pinned tools with `GOFLAGS= make install-tools` if they are not already available.
Use command-scoped `GOFLAGS=` so the product checkout's `-mod=vendor` setting does not reach the validator.
Set `ARTIFACT_ROOT` to an artifact tree containing this file at
`plans/cntrlplane-4343.md` and run:

```bash
GOFLAGS= make build
PATH="$PWD/bin:$PATH" bin/verify-artifacts --root "$ARTIFACT_ROOT" --secrets --format json
```

The command must exit with status zero and return `{"findings":[]}` for this plan. It checks metadata,
content, case mappings, references, and sanitization. It does not execute product tests or approve the plan.

## 18. Conformance metadata

```yaml
plan_version: 7
generated_at: 2026-11-11T13:16:21+00:00
jira_key: CNTRLPLANE-4343
jira_status: In Progress
component: HyperShift
prs_analyzed:
  - url: https://github.com/openshift/hypershift/pull/10244
    state: open
    base_branch: main
    base_sha: 7880cde58491473785ae0f865718a953782e2dc0
    head_sha: 048cced8aeecbb08cb9debf4241ec6ed37bc74ec
raw_changed_lines: 2775
normalized_changed_lines: 2775
scenario_count: 25
scenarios_by_tier:
  unit: 25
  integration: 0
  e2e-serial: 0
  e2e-parallel: 0
  e2e-periodic: 0
coverage:
  covered: 20
  partial: 3
  gap: 2
  preliminary: 0
action_required_count: 7
test_execution_during_generation: false
artifact_validator_pr: https://github.com/hypershift-community/test-results-verification/pull/10
artifact_validator_sha: c70865b77e74a9c9591dbe1e328d3ae0088decf2
artifact_validation_includes_secrets: true
live_environment_validation: not_run
skipped_prs: []
```
