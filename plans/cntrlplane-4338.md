---
id: CNTRLPLANE-4338-supplemental-verification
version: "3"
date: 2026-11-06
title: Supplemental verification for HyperShift PR 9920
status: draft
ieee_829: true
jira_issues:
  - key: CNTRLPLANE-4338
    role: primary
    url: https://redhat.atlassian.net/browse/CNTRLPLANE-4338
pull_requests:
  - repo: openshift/hypershift
    number: 9920
    url: https://github.com/openshift/hypershift/pull/9920
    role: implementation
tags:
  - global-configuration
  - supplemental-verification
reviewed_head: d037aa90aa5b889c69464004df2e74f4c4c5b287
scenario_count: 9
execution_status: not_run
---

# Supplemental verification for HyperShift PR #9920

## 1. Test plan identifier

| Field | Value |
| --- | --- |
| Identifier | CNTRLPLANE-4338-supplemental-verification |
| Version | 3 |
| Prepared | 2026-11-06 |
| Status | Draft |
| Component | HyperShift |
| Feature | [CNTRLPLANE-4338. Extract global-configuration ownership with characterization](https://redhat.atlassian.net/browse/CNTRLPLANE-4338) |

This draft uses the IEEE 829-2008 documentation standard and includes the
repository's required plan sections.

## 2. Introduction and objectives

[PR #9920, CNTRLPLANE-4338: Extract global-configuration ownership with
characterization](https://github.com/openshift/hypershift/pull/9920) is open against `main`. This
draft applies to head `d037aa90aa5b889c69464004df2e74f4c4c5b287`. Review the plan after a head
change.

This plan supplements the passing end-to-end suites. It calls for evidence that the refactor
preserves behavior, routes reads and writes to the correct cluster, keeps both cleanup policies and
the original install version, and runs the changed code. Preparation did not include additional test
runs, cluster launches, or changes to Jira or PR fields.

PR #9920 already covers all six unit-test groups, TC-REG-001 through TC-REG-006. Their test
functions and subcases were checked at the pinned head. These sections document existing coverage.
TC-REG-004 also identifies a proposed independent-deletion extension that is not covered in the PR.
Reuse existing PR execution evidence before scheduling another run.
The three live groups address gaps in the earlier e2e audit. "Covered in PR" means the test code
contains the named checks. This draft has not executed them. A skipped or informing assertion does
not count as a pass.

## 3. Scope, references, and requirements

This plan covers HCCO global configuration, image policy, install metadata, proxy CA handling,
observed Build and Project configuration, and the root reconciler's phase order, error aggregation,
and status handling. It proposes no new API, platform support, feature gate, watch design,
manifest-constructor relocation, or foundation-policy redesign.

The requirements come from CNTRLPLANE-4338 and its parent [CNTRLPLANE-4330. Extract hosted-cluster
configuration ownership from HCCO resources](https://redhat.atlassian.net/browse/CNTRLPLANE-4330).
The preceding foundation extraction,
[CNTRLPLANE-4337](https://redhat.atlassian.net/browse/CNTRLPLANE-4337), is closed. The subsequent
projection extraction, [CNTRLPLANE-4343](https://redhat.atlassian.net/browse/CNTRLPLANE-4343), is
separate work and does not block this plan. The story review found no clone or backport chain or
testing epic.

- AC1. Characterization before extraction covers creation, updates, deletion, platform conditions,
  cross-cluster observation, and aggregate errors.
- AC2. The configuration module owns resource selection and policy.
- AC3. Cross-cluster reads and writes use explicit adapters, with no broad shared context.
- AC4. The root retains shared input loading, phase order, error aggregation, and status handling.
- AC5. Existing watches and hosted-cluster behavior remain unchanged.
- AC6. Focused domain tests and full resources-controller regressions pass.

AC1 needs evidence that characterization ran before extraction. Rerunning tests now cannot establish
that timing. AC2 through AC4 require source review as well as test execution to check ownership
boundaries. AC5 needs a watch-registration comparison and live convergence. Complete test output can
establish AC6.

## 4. Prerequisites and evidence gates

- Use the pinned PR head and record the exact base or merge revision for each run. The earlier e2e
  audit used the same PR head with different base revisions.
- Use disposable, dedicated guest and control-plane test environments. Obtain authorized access to
  both clusters and snapshot every resource that live tests will modify. Do not use a production
  cluster or one that another suite is using.
- For each live scenario, trace the changed CPO or HCCO source to its built image. Record the
  requested image and the running container image IDs. An operator version string, a built artifact,
  or an upgrade of only the HyperShift operator does not establish that the changed code runs. Get
  workload and container names from the test environment.
- Follow the repository's test prerequisites and `TESTING.md`. Put new unit cases next to their
  implementation. Use `Test<FunctionName>` and "When ..., it should ..." naming. Verify the owner
  references that reconciliation sets. Do not add tests under the legacy `test/integration/`
  directory.
- All nine cases apply to this PR's `main` head and the release payload selected for its test
  environment. The fixtures do not establish a numeric release-support range. Record the payload and
  version in the results, and review API availability before using another release branch. This
  refactor introduces no feature gate.

### Gate E1. Characterize the original behavior

Request the pre-extraction source revision, characterization test revision, command, and complete
result log. If these are unavailable, run equivalent fixtures against the old root entry points and
the new configuration entry points in separate checkouts. Change only the code needed to invoke each
implementation. Compare fields, client routing, operation and error order, and deletion results.
Record the comparison as *retrospective equivalence evidence*. It cannot prove when the author ran
the tests. Tests that import new APIs will not compile in the old checkout. Do not count that
compile failure as a product failure.

### Gate E2. Review source and ownership

Compare root `resources.go`, registration and watch code, adapters, input types, manifest
constructors, and helper signatures with the pre-extraction implementation. Check for unintended
watch or policy changes, a new shared controller context, and resource-specific mutations left in
the root contrary to AC2 or AC4. Resolve the documentation discrepancy during review.
`configuration/README.md` describes `GlobalConfigParams` and a private compatibility snapshot, but
this head's `ReconcileGlobal` accepts `*HostedControlPlane`. Align the documentation with the design
and obtain reviewer agreement on the input contract. The discrepancy alone does not establish a
runtime regression.

### Gate E3. Trace runtime images and results

Before accepting a live result, attach the source, build, and running-image evidence, PR and base
SHAs, release payload, job or run URL, named test and subtest outcomes, and resource snapshots
before and after the test. Read the relevant JUnit results and test logs, including skipped and
informing cases. The earlier Azure informing custom-label skips do not count as passing assertions.
Their cause has not been tied to this refactor.

## 5. CI placement and execution

All proposed code belongs in `openshift/hypershift`. This plan requests no new repository or
release-blocking payload job. Existing PR jobs run independently.

| Trigger | Placement | Proposed coverage |
| --- | --- | --- |
| Pre-merge | Existing unit tests for configuration, resources, and shared globalconfig helpers | TC-REG-001 through TC-REG-006, with deterministic fake-client failure injection |
| Pre-merge supplemental live verification | Existing e2e framework, with tests run serially within a shared hosted cluster | TC-PROP-001, TC-CA-001, and TC-REG-007. Run manually at first and consider automation. |
| Post-merge periodic | Existing platform suites | Retain broad smoke coverage. This draft requires no extra periodic job. Agree with the team before adding one. |

Run the existing Make target below for the relevant controller subtree and helper regressions. It
generates prerequisites and forces uncached tests. The supplied flags enable verbose output and the
race detector. Run it from the repository root and save the full output and exit status.

```sh
make test-shard \
  TEST_PACKAGES='./control-plane-operator/hostedclusterconfigoperator/controllers/resources/... ./support/globalconfig/...' \
  GO_TEST_FLAGS='-race -v'
```

For an individual scenario, use the same target with the exact package and a `-run` selector for the
named test. Confirm that the selector runs the intended tests. If you modify tests, run the
applicable repository checks, including `make pre-commit`, `make verify-ci`, and `make test-linter`,
and review the diff for unintended changes. This plan does not require rerunning every broad e2e
suite.

## 6. Test cases

The paths below use **R** for
`control-plane-operator/hostedclusterconfigoperator/controllers/resources/` and **C** for
`R/configuration/`. Expand R without adding a double slash. All targets are in
`openshift/hypershift`. Coverage labels describe the tests inspected for this plan. They do not
establish complete repository coverage.

### TC-REG-001. Global configuration and platform equivalence

Run the unit tests in
[C/global_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/global_test.go),
`TestReconcileGlobal`. Fake clients allow exact field, status, and error assertions. PR #9920
already covers this unit-test group. Its coverage status is COVERED IN PR. Use the pinned main head
and version guidance in section 4. This case checks AC1, AC2, AC5, and AC6.

1. Run the create, update, and repeat-reconciliation cases. Assert that owned fields match inputs,
   unrelated annotations survive, and reconciliation leaves the caller's HCP unchanged. Repeated
   reconciliation must leave owned objects unchanged.
2. Run the existing None, AWS, Azure, GCP, PowerVS, and OpenStack fixture branches. Check each
   branch's platform fields and endpoint selection. Include AWS SharedVPC and tag filtering, Azure
   private access, Swift and legacy annotation behavior, GCP private access and label filtering, and
   the existing PowerVS and OpenStack expectations.
3. Run the managed AWS ingress-DNS case. Assert that guest DNS public and private zone IDs come from
   HCP status even when the spec has no zone IDs. This catches an input adapter that drops required
   status.
4. Run the cases for a missing endpoint, missing guest Proxy, network-validation errors,
   Infrastructure spec and status failures, and multiple write failures. Check continuation,
   operation order, status-write suppression, and error wrappers. The controller must not rewrite
   unchanged Infrastructure status.

The case passes when every named subcase executes and passes. Save verbose output and the E1
baseline comparison.

### TC-REG-002. Image-policy replacement and removal

Run the unit tests in
[C/image_policy_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/image_policy_test.go),
`TestReconcileImagePolicy`, and the deletion-error subcase of `TestReconcileGlobal`. These ordering
checks do not need a live registry. PR #9920 already covers this unit-test group. Its coverage
status is COVERED IN PR. Follow the version guidance in section 4. This case checks AC1, AC2, AC5,
and AC6.

1. Use the fixtures to seed the legacy ICSP and a stale IDMS. Reconcile configured sources. Assert
   that the controller deletes the legacy policy before the IDMS upsert, mirrors match the input,
   and the worker-role label remains as the test expects.
2. Remove image content sources. Assert that IDMS mirror contents become empty. Current policy
   empties the IDMS, so do not require its deletion. Reconcile again and assert stable output.
3. Inject a legacy-policy deletion failure. Assert that the error remains, the controller does not
   update IDMS during that attempt, and it still attempts subsequent global resources.

The case passes when source and mirror values, operation order, empty-source behavior, and
continuation match the original contract. Keep these checks even when live mirror-pull e2e evidence
is available.

### TC-REG-003. Preserve the original install version

Run the unit tests in
[C/install_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/install_test.go),
`TestReconcileInstallMetadata`. They check lazy accessor use and map preservation. PR #9920 already
covers this unit-test group. Its coverage status is COVERED IN PR. Follow the version guidance in
section 4. This case checks AC1, AC2, AC5, and AC6.

1. Start without install metadata and reconcile with a valid release accessor. Assert that
   `openshift-config/openshift-install` has `invoker=hypershift` and the initial release version.
2. Add unrelated data, then reconcile an existing version with the accessor unavailable. The
   existing test supplies nil. Assert that the original version and unrelated data survive and
   reconciliation does not call the accessor.
3. Test invalid component-version parsing when first populating the metadata. Assert the nested
   install and version error context. When the version key is absent, supply a callable accessor.
   The implementation requires one.

The case passes when initialization, preservation, and error checks pass. This metadata ConfigMap is
separate from the generated install-config YAML tested in global reconciliation.

### TC-REG-004. Route observed configuration to the correct cluster

Run the unit tests in
[C/observed_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/observed_test.go),
`TestReconcileObserved`. Separate fake clients check routing and allow controlled failures. PR #9920
already covers this unit-test group. Its coverage status is COVERED IN PR. Follow the version
guidance in section 4. This case checks AC1, AC3, AC5, and AC6.

1. Seed guest Build and Project configuration. Reconcile and update the Project marker as the test
   does. Assert that control-plane `observed-config-build`/`observed-config-project` data matches
   the source projection and owner references match the HCP name and UID.
2. Assert that reconciliation creates no destination ConfigMaps in the guest client. Remove both
   source objects together in the isolated fixture and reconcile twice, as the pinned test does.
   Assert that reconciliation removes only the control-plane copies and makes no further change
   when they are absent.
3. Inject source-read failures and destination upsert and delete failures. Assert that
   reconciliation attempts both sources in Build-then-Project order and retains both errors as
   separate entries with their original context.

The case passes when routing, data, ownership, deletion, and independent errors match expectations.
The current lifecycle test updates Project. TC-PROP-001 adds live Build update evidence.

Proposed extension, not covered in PR #9920: seed both sources, delete only Build, and reconcile.
Assert that only `observed-config-build` disappears and that the Project projection and owner
references remain unchanged. Restore Build and verify both projections before deleting only
Project. Assert the inverse, including unchanged Build data and ownership. Reconcile each absence
state twice to check stability. The pinned test deletes both sources together, so its existing
coverage does not prove independent deletion.

### TC-REG-005. Preserve both proxy cleanup policies

Run the unit tests in
[C/proxy_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/proxy_test.go)
and
[C/inputs_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/configuration/inputs_test.go),
`TestReconcileProxyTrustedCA`, `TestReconcileProxyCABundle`, and `TestProxyParamsFor`. Inject
failures through fake clients instead of breaking cluster permissions. PR #9920 already covers this
unit-test group. Its coverage status is COVERED IN PR. Follow the version guidance in section 4.
This case checks AC1, AC2, AC3, AC5, and AC6.

1. Run the nil, empty, and configured proxy-input cases. Enable, replace, and remove the CA
   reference. Verify exact source and destination data and cleanup targets across both clients.
2. For TrustedCA-reference cleanup, inject stale-copy deletion failures. Assert that reconciliation
   logs the failures, treats cleanup as best effort, and still copies the new CA.
3. For the user bundle `openshift-controller-manager/openshift-user-ca`, enable, update, and disable
   it twice. Assert that reconciliation removes the guest bundle on disable and preserves the
   control-plane source.
4. Inject failures for a missing user bundle and for reads, upserts, and deletes. Assert that
   reconciliation preserves existing destination data and propagates errors with their expected
   context. Keep this error policy separate from best-effort TrustedCA cleanup.

The case passes when assertions verify both cleanup policies, including their different error
handling.

### TC-REG-006. Preserve root phase order, continuation, error identity, and status

Run the unit test in
[R/foundation_order_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/foundation_order_test.go),
`TestReconcile`. Also run all
[R/resources_test.go](https://github.com/openshift/hypershift/blob/d037aa90aa5b889c69464004df2e74f4c4c5b287/control-plane-operator/hostedclusterconfigoperator/controllers/resources/resources_test.go)
regressions with the full package command. Operation traces and injected failures check the root
reconciler's orchestration contract. PR #9920 already covers this unit-test group. Its coverage
status is COVERED IN PR. Follow the version guidance in section 4. This case checks AC1, AC3, AC4,
and AC6.

1. Run the root regression with multiple failures in the foundation, global, misc, and observed
   phases. Assert that reconciliation still attempts later resources.
2. Verify the existing relative phase-order assertions. Foundation stages must retain their
   positions. Proxy user CA must follow pull-secret propagation and precede OAuth CA. Observed Build
   and Project must follow storage and recycler work.
3. Assert that observed Build and Project failures remain separate entries in the root aggregate,
   with their original error identity and order.
4. Assert that reconciliation sets `ConfigOperatorReconciliationSucceeded` to false with
   `ReconcileErrorReason`, the aggregate message, and the current observed generation. It must leave
   the HCP spec unchanged.
5. Run the complete resources-controller subtree as well as the focused `-run` selection. Include
   existing regressions unrelated to the extraction.

The case passes when the phase-order, continuation, status, and aggregate assertions pass, along
with the complete subtree.

### TC-PROP-001. Verify live Build and Project updates through watches

Run this e2e case serially because it changes cluster-scoped configuration in a dedicated guest. Add
it to `test/e2e/create_cluster_test.go` using the existing guest and management clients. Coverage is
PARTIAL. TC-REG-004 covers policy, but live lifecycle and watch evidence is missing. Automation is
proposed. Use manual verification until then and follow the version guidance in section 4. This case
checks AC1, AC3, and AC5.

1. Meet E3. Snapshot guest `builds.config.openshift.io/cluster` and
   `projects.config.openshift.io/cluster`, their control-plane observed ConfigMaps, and the HCP UID.
   Choose a harmless, schema-valid Build field, unique markers, a bounded timeout, and a poll
   interval. Record those choices and the available watch-event or reconcile tracing.
2. Change only the approved Build field. Keep Project unchanged. Record the source resource
   version and mutation time, then wait for `observed-config-build` to contain the new value before
   changing Project. Capture the Build watch event and resulting reconciliation where the
   environment exposes them. Verify that the Project projection stays unchanged.
3. Change only Project `spec.projectRequestMessage`. Keep Build unchanged. Record the same evidence
   for the Project mutation and wait for `observed-config-project` to contain its new value. Verify
   that the Build projection stays unchanged. Do not call internal reconciliation functions or
   copy destination data manually in either phase.
4. At each phase, read both observed ConfigMaps in the HCP namespace. Assert that their payloads
   match the expected sources and owner references match the HCP. Verify that reconciliation
   creates no same-name test destination in the guest.
5. Restore each source spec separately and verify its observed data returns to the original value
   before restoring the other. Repeat reads over a recorded observation interval to check that the
   projections stay unchanged. Allow metadata and status changes from other controllers. Do not
   require globally unchanged resource versions.
6. Use the unit deletion case to check source absence by default. Add live singleton deletion only
   with explicit approval for the environment and baseline evidence. Do not delete cluster singleton
   configuration just to satisfy this plan.

The case passes when each isolated update and restoration converges, routing and ownership are
correct, and evidence identifies each source's watch event and resulting reconciliation. All
resource watches enqueue the same reconcile request. Convergence and timestamps alone cannot
exclude another event or retry as the trigger. If available tracing cannot distinguish the Build
and Project triggers, record the watch assertion as blocked and retain the propagation evidence;
do not report the full case as passed.

### TC-CA-001. Rotate and remove a live CA without changing connectivity

Run this e2e case serially so cluster-wide trust changes do not race other tests. Extend
`TestCreateClusterProxy` in `test/e2e/create_cluster_test.go`, which is AWS-only. Coverage is
PARTIAL. The existing proxy e2e and TC-REG-005 provide relevant checks, but full live rotation and
removal evidence is missing. Automation is proposed. Use manual verification until then. Follow the
version guidance in section 4 and start with AWS to match the existing test. This case checks AC1,
AC3, and AC5.

1. Meet E3. Use a dedicated cluster and snapshot the supported desired proxy configuration and
   every referenced source and destination ConfigMap. Identify all CAs required for existing API
   and outbound/proxy connectivity. Record successful baseline checks for both. Do not assume
   connectivity is independent of the current custom CA.
2. Register cleanup before changing any source or reference. Cleanup must recreate any original
   source ConfigMaps removed by TrustedCA cleanup before restoring the original desired reference.
   It must then verify reconciliation and connectivity and remove test-owned copies after they
   are no longer referenced. Retain valid original CA data for recovery.
3. Provision test-owned source ConfigMaps A and B in the control-plane HCP namespace before
   selecting either reference. Use distinguishable, valid CA bundles that both retain every CA
   needed for existing connectivity. Provision any additional source copies required by the
   supported HostedCluster path. Verify that both control-plane sources exist and contain the
   expected data. `TestCreateClusterProxy` enables the proxy but does not create these sources.
4. Set reference A through the supported HostedCluster configuration path. Verify its projection to
   the HCP and guest, including the named TrustedCA copy under `openshift-config` and the user
   bundle under `openshift-controller-manager`. Recheck API and required outbound/proxy access.
5. Confirm source B is still present before selecting it. Rotate to B and verify the new
   destination data and removal of stale A copies where TrustedCA cleanup policy requires it.
   Cleanup may delete A's control-plane source as well as its guest copy. Check unrelated resources
   and recheck API and required outbound/proxy access after replacement.
6. Before clearing the test reference, verify that all CAs required for connectivity remain
   available independently of that reference. If that cannot be established, block the removal
   assertion and use cleanup to restore the baseline. Otherwise remove the test reference and
   verify guest `openshift-user-ca` cleanup and expected stale TrustedCA-copy cleanup against E1.
   Check each cleanup path's source-preservation policy separately and recheck connectivity.
7. Run the registered cleanup, restoring original source objects before the original desired
   reference. Verify the original projections, normal reconciliation, API access, and required
   outbound/proxy access. Use unit tests for injected read, delete, and upsert failures. Do not
   manipulate live RBAC to trigger them.

The case passes when the running code projects, rotates, removes, and restores the expected data
while preserving required trust and connectivity at every phase. A blocked removal assertion
prevents a full pass. Before execution, approve valid CA fixtures, source provisioning, connectivity
checks, and the environment's safety.

### TC-REG-007. Verify live global-config updates and preserve the install version

Run this e2e case serially because it changes cluster-wide configuration. Extend
`TestCreateClusterCustomConfig` in `test/e2e/create_cluster_test.go` and retain its AWS and Azure
platform guards. Coverage is PARTIAL. The existing custom-config e2e covers creation, and TC-REG-001
and TC-REG-003 cover detailed policy. Evidence for a live update and restoration is missing.
Automation is proposed. Use manual verification until then and follow the version guidance in
section 4. This case checks AC1, AC2, and AC5.

1. Meet E3. Capture the current HostedCluster desired configuration, corresponding HCP, guest target
   configuration, and `openshift-config/openshift-install` data. Record the original installed
   version and the current `release` component version used by the running HCCO's release-image
   accessor. They must differ for the preservation assertion, for example in an already-upgraded
   fixture. If they match and no suitable fixture is available, mark that assertion blocked.
2. Choose a safe, schema-valid setting from the existing custom-config fixture. Change it through
   the supported HostedCluster path and assert that the HCP and guest owned field converge. Do not
   modify immutable endpoint, DNS, or network fields even if fake-client fixtures allow it.
3. Add a test-owned annotation to the guest object. Verify that it survives a subsequent
   desired-setting update. Restore the original setting and confirm that the guest owned field
   returns to its original value.
4. Throughout the update and restoration, assert that `openshift-install.data.version` retains the
   original installed value, `invoker` remains `hypershift`, and unrelated metadata entries remain.
   Do not overwrite the original version to manufacture a preservation test.
5. Remove the test annotation and restore modified configuration and data. Capture the final HCP
   reconciliation condition and resource data. Use unit TC-REG-003 to prove lazy-accessor behavior.
   This live case cannot prove that reconciliation never called the accessor.

The case passes when live fields propagate and return to their original values, and install metadata
retains its original version despite a distinct current release version. An equal-version fixture
cannot detect an overwrite and does not qualify as a full pass. Before execution, select the safe
mutable field and convergence bounds with the environment reviewer.

## 7. Coverage and requirement mapping

| Requirement | Evidence to retain | Remaining qualification |
| --- | --- | --- |
| AC1. Characterization before extraction | E1; TC-REG-001 through TC-REG-006 | Current-head tests cannot establish when characterization ran. |
| AC2. Configuration ownership | E2; TC-REG-001 through TC-REG-003; TC-REG-005; TC-REG-007 | Review the source to check ownership boundaries. |
| AC3. Explicit cross-cluster adapters | E2; TC-REG-004 through TC-REG-006; TC-PROP-001; TC-CA-001 | Compare actual clients and runtime destinations. |
| AC4. Root responsibilities | E2; TC-REG-006 | Review residual root policy and shared input loading. |
| AC5. Unchanged watches and behavior | E2; TC-REG-001 through TC-REG-005; all three live cases | Compare watch registration and verify live convergence. Both are required. |
| AC6. Focused and full regressions | Complete test-shard output; TC-REG-001 through TC-REG-006; existing e2es | Every intended package and subtest must execute. |

The plan has nine scenario groups, six unit and three serial e2e. Six are covered and three are
partial. None is wholly uncovered. The partial groups need live lifecycle evidence and proposed
automation. These classifications do not establish complete test coverage. The selected gaps need no
integration-only scenarios or new periodic scenarios.

## 8. Existing verification evidence and regression scope

The PR author reports pre-extraction characterization, pre-commit review, `make pre-commit`, `make
verify-ci`, `make test-linter`, focused race tests, and clean-tree and generation checks. No
independent evidence yet establishes that characterization ran before extraction.

The earlier audit recorded seven successful e2e contexts on the pinned head. It found relevant AWS
custom-config and proxy assertions, AWS v2 mirror assertions, and passing resources and
configuration unit packages. Configuration statement coverage was 95.6%. That percentage does not
establish complete behavioral coverage. This draft uses the earlier audit's evidence without
rerunning those checks. References:

- [AWS e2e
  run](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_hypershift/9920/pull-ci-openshift-hypershift-main-e2e-aws/2115051527855935488)
- [AWS v2 e2e
  run](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_hypershift/9920/pull-ci-openshift-hypershift-main-e2e-v2-aws/2118015396597469184)
- [Focused package results within the unit
  job](https://github.com/openshift/hypershift/actions/runs/39599697000/job/119221191613)

Retain foundation-ordering and unrelated root regressions. Keep the separate APIService, endpoint,
and OAuth extraction outside this plan. This refactor preserves behavior and adds no security
feature or performance requirement. Keep platform-specific policy fixtures in unit coverage. Do not
provision every platform just to repeat deterministic field-copy assertions.

## 9. Risks, result collection, cleanup, and sign-off

Live configuration changes can disrupt trust or affect other tests. Use a dedicated environment,
harmless mutable fields, valid CA fixtures, and snapshots. Bound each convergence wait and restore
every change. Missing image provenance can invalidate a result even when resources converge.
Complete E3 before making changes.

For each case, record the ID, source and base revisions, payload and platform, exact command or live
operations, expected and actual results, pass/fail/blocked/skip outcome, logs and JUnit results,
resource snapshots before and after, and cleanup result. Redact kubeconfigs, tokens, private keys,
pull secrets, and unrelated workload or customer data. Retain only non-secret provenance and
relevant configuration evidence.

Stop live changes if runtime provenance is missing, cluster contexts or namespaces are ambiguous,
the source fixture is invalid, the environment is unhealthy before testing, or cleanup cannot be
guaranteed. Diagnose infrastructure failures separately. Do not call an unexplained failure a flake
or count a blocked or skipped case as passed.

When troubleshooting, compare desired HostedCluster input with projected HCP and guest state. Check
the cluster, namespace, and source references. Inspect HCCO logs and the HCP reconciliation
condition, then compare error wrappers with the unit contract. Preserve failing state before
restoration when safe. If a focused selector runs zero tests, correct it before interpreting the
result.

Complete these checks before sign-off:

- Support E1 with historical evidence, or record it as retrospective evidence and obtain reviewer
  acceptance of that limitation.
- Complete the E2 ownership, watch, and input review. Resolve the README and input-contract
  discrepancy or record an explicit review decision.
- Retain successful existing PR results for all six covered unit groups and the full
  resources-controller and helper regressions at the reviewed revision. Rerun only when the revision
  changes or evidence is missing.
- Pass all three live cases with runtime CPO or HCCO provenance. Obtain an explicit
  reviewer-approved decision for each omission. Do not count skips as verification.
- Restore all changes and remove test-owned annotations and configuration. Confirm that availability
  and reconciliation return to baseline.
- Have a reviewer accept the evidence and remaining gaps. Completing this plan does not authorize a
  Jira status or verification-label change.

A developer should collect unit and equivalence evidence. An authorized environment tester should
run live cases, and a reviewer should accept the results. The issue supplies no named owners, dates,
environment allocation, timeouts, or mutable fixtures. Agree on these before execution. Automation
remains proposed.

## 10. Decisions before execution

1. Supply E1's original characterization evidence or agree to a retrospective comparison.
2. Select a dedicated environment and trace the source to the running image.
3. Approve harmless live Build and global-config changes, valid CA fixtures, restoration steps, and
   convergence bounds.
4. Reconcile the README description with the actual global-input API during source review.
5. Assign execution and review roles and dates. Decide whether to automate the three live groups.

### Read-only evidence collection examples

Resolve and record `GUEST_CONTEXT`, `MGMT_CONTEXT`, `HCP_NAMESPACE`, and `HCP_NAME` from the
dedicated environment before using these examples. MGMT_CONTEXT must point to the cluster that holds
the HCP and its observed ConfigMaps. The reads do not replace the approved changes and restoration
steps. Save snapshots before the change, after the change, and after restoration. Compare relevant
fields and allow volatile metadata to change.

```sh
oc --context="$GUEST_CONTEXT" get builds.config.openshift.io cluster -o yaml
oc --context="$GUEST_CONTEXT" get projects.config.openshift.io cluster -o yaml
oc --context="$MGMT_CONTEXT" -n "$HCP_NAMESPACE" get configmap observed-config-build observed-config-project -o yaml
oc --context="$MGMT_CONTEXT" -n "$HCP_NAMESPACE" get hostedcontrolplane "$HCP_NAME" -o yaml
oc --context="$GUEST_CONTEXT" -n openshift-config get configmap openshift-install -o yaml
oc --context="$GUEST_CONTEXT" -n openshift-controller-manager get configmap openshift-user-ca -o yaml
oc --context="$MGMT_CONTEXT" -n "$HCP_NAMESPACE" get pods -o json
```

The last command reads requested container images and running image IDs from the selected pods.
Identify the containers that execute the changed code. An unrelated pod's image does not establish
runtime provenance. Test CA destinations may be absent after deliberate disable. Missing sources
during enabled phases are failures.

## 11. Abbreviations

AC: acceptance criterion; CA: certificate authority; CI: continuous integration; CPO: control-plane
operator; e2e: end-to-end; HCCO: hosted cluster config operator; HCP: HostedControlPlane; ICSP:
ImageContentSourcePolicy; IDMS: ImageDigestMirrorSet; PR: pull request; TC: test case; REG:
regression; PROP: propagation.

## 12. Conformance metadata

```yaml
plan_version: 3
generated_at: '2026-11-06T16:39:16Z'
jira_key: CNTRLPLANE-4338
jira_status: Code Review
prs_analyzed:
  - url: https://github.com/openshift/hypershift/pull/9920
    state: open
    base_branch: main
    head: d037aa90aa5b889c69464004df2e74f4c4c5b287
classification: mixed_product_tests_docs
raw_changed_lines: 1978
normalized_changed_lines_excluding_vendor_generated: 1978
normalization_note: 'No vendor/generated files; whitespace-only changes not separately quantified. Not a complexity metric.'
scenario_count: 9
tiers:
  unit: 6
  e2e-serial: 3
coverage:
  covered: 6
  partial: 3
  gap: 0
  preliminary: 0
execution_status: not_run
jira_updated: false
pr_updated: false
```
