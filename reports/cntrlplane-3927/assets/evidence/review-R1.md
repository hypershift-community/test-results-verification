# CNTRLPLANE-3927 — independent R1 review

## Verdict

**LOCAL GATE PASS; LIVE ACCEPTANCE UNVERIFIED.**

No blocking or nonblocking source defects identified in the complete incremental change. D1–D10 and the locally inspectable portions of all four ACs are satisfied. V1–V5 were independently rerun against the completed tree; every command exited 0. This is not an overall/live AC pass: no V6 evidence was supplied or collected, and dry-run does not execute propagation assertions.

**To the same I1 implementer:** no source remediation is requested. Retain the live-acceptance qualification. Actual acceptance requires separately authorized V6 evidence of both executed, non-skipped, non-informing passing specs and their observed resources. No new helper-agent assignment is needed.

## Reviewed snapshot and complete scope

- Checkout: `~/hypershift`.
- Branch: `CNTRLPLANE-3927`.
- Tested HEAD: `c9ad656db618ee953923cb5f8ec91e3566885d95`.
- Its direct parent: `8d54f7ab3249ddf01777824b35a60e1025d72972` (the requested review base).
- Before and after validation: clean tracked working tree; empty staged and working diffs; `git ls-files --others --exclude-standard` returned no files. There are no untracked source files to omit. The implementation report's earlier untracked state is explicitly historical; its authorized-commit update agrees with the actual snapshot.
- Read `plan.md` and `implementation.md`, repository development/testing guidance, v2 guidance and Effective Go skill. Read all three new source files in full and every analyzer diff. Parent-to-HEAD is six files / 703 insertions, not the underlying 3926 fixture change.

Complete reviewed inventory (paths relative to root):

| File | Scope |
|---|---|
| `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go:1–87` | New feature registration and two independent specs |
| `test/e2e/v2/tests/hosted_cluster_image_mirroring_helpers.go:1–166` | Six private helpers |
| `test/e2e/v2/tests/hosted_cluster_image_mirroring_helpers_test.go:1–444` | Six ordinary tests, 76 subcases |
| `hack/tools/hypershiftlinter/analyzers/e2eutilallowlist/e2eutilallowlist.go:42` | Only `WithoutConditionDump` added |
| `hack/tools/hypershiftlinter/analyzers/e2eutilallowlist/testdata/src/test/e2e/v2/good/good_test.go:18` | Allowed-symbol exercise |
| `hack/tools/hypershiftlinter/analyzers/e2eutilallowlist/testdata/src/github.com/openshift/hypershift/test/e2e/util/util.go:10–12` | Isolated analyzer fixture stub |

The stub is a justified narrow addition to the plan's listed files: analysistest resolves this stand-in package, so the good fixture needs the symbol there. It does not broaden runtime behavior or the allowlist. No production, fixture, lifecycle configuration, suite, CI, or default matrix changes exist.

## Findings and D1–D10 audit

**Findings: none requiring fixes.** The following file:line references record the contract checks rather than invented defects. In this table, `spec` means `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go`; `helpers` means `test/e2e/v2/tests/hosted_cluster_image_mirroring_helpers.go`.

| Decision | Assessment and source evidence |
|---|---|
| D1 | PASS — `spec:27–87`: registrar, feature-scoped Describe, lifecycle/image-mirroring decorators, two ordinary independent Its at 28 and 57. Runtime context acquisition, no creation/mutation, Ordered, Serial or Informing. |
| D2 | PASS — `helpers:31–73`, `spec:31–36,60–65`: missing HC is an assertion failure; nil/empty ICS, blank sources/mirrors, zero mirrors and duplicate sources are rejected. Each It obtains its own HC and deep-copied ICS snapshot. No Skip. |
| D3 | PASS — `spec:33–36,62–65`, `helpers:51–70`: management GET of the default fixture Route; nonempty host; both real and virtual sources required; exact hostname component equality plus repository path, not prefix matching. Additional HC entries retained. No fixture output generator or invented artifact bridge. |
| D4 | PASS — `helpers:108–138`: independent HC oracle, exact source count and source-to-mirror association, one-to-one matching by deleting consumed source keys. Duplicate actual sources fail even when length matches. Only outer entry order is ignored; mirror order and multiplicity are retained via ordered slice equality. No mutation/sorting of inputs or production converters. |
| D5 | PASS — `helpers:75–92`, `spec:43–52,70–79`: exact GET `ImageDigestMirrorSet/cluster` with empty namespace through hosted client; exact management CM in `tc.ControlPlaneNamespace`. Successful GET returns only the observed singleton; errors return no synthetic object. Group predicates explicitly reject empty/multiple/nil/wrong-identity targets. No LIST/label selection. |
| D6 | PASS — `spec:28–82`: only first It creates port-forwarded hosted client and immediately registers Close after the error assertion (`38–40`). Second It uses only management client, independently gets HC/Route and never reads the first output. Both use tc.Context, and poll getters use their supplied context. |
| D7 | PASS — `helpers:140–166` plus `94–106`: exact CM identity/core label; nonempty config; typed YAML IDMS decoding; explicit API version/kind; payload name, empty namespace, worker label and HC mappings. Allows unrelated metadata/data and formatting, not raw YAML equality or substring validation. |
| D8 | PASS — `spec:41–54,68–81`: separate EventuallyObjects calls with explicit 10m/3s, fresh GETs, WithoutConditionDump. Observed mismatches/decode errors return false, nonempty reason, nil error, so they can converge; input setup failures precede polling. Existing `test/e2e/util/eventually.go:232–350` retries/logs getter errors and fails on timeout. |
| D9 | PASS — `helpers:68,100–110,145–164`, `spec:32,36,39,42,61,65–69`: actionable identity/setup/expected-versus-actual diagnostics; no secrets or kubeconfigs dumped. Narrow allowlist and analyzer test pass. Both waits disable unsupported condition extraction, not assertions. |
| D10 | PASS — `spec:85–87`: actual Ginkgo labels, no skip/platform/version masking. Existing AWS matrix remains unchanged and excludes this feature. V4 selects exactly two feature specs and zero under the negative filter. Live execution of both remains unverified. |

Producer/framework cross-checks: `support/globalconfig/imagecontentsource.go:45–87` establishes named IDMS, worker label and ordered copies; `hypershift-operator/controllers/hostedcluster/hostedcluster_controller.go:2954–3082` copies HC input to HCP; HCCO `controllers/resources/resources.go:3430–3448` reconciles hosted IDMS. CPO `hostedcontrolplane_controller.go:2423–2480` independently builds in-memory IDMS and serializes the ignition CM. `ignition/reconcile.go:98–143` confirms YAML in `data.config`, and `manifests/ignition.go:44–51` confirms the exact CM name. `test/e2e/v2/internal/test_context.go:54–70,159–257` confirms management HC lookup, hosted API client and cleanup contract. `lifecycle/aws.go:175–208` and `util/mirrorregistry/api.go:13–28` agree with the fixture source and Route identity checks. These existing producers are not used to generate test expectations.

## AC coverage and limits

| Criterion | Local coverage | Remaining acceptance evidence |
|---|---|---|
| AC1 — fixture HC → matching hosted IDMS | D2–D6; spec first It; input/mapping/getter adversarial unit tests | Actual fixture-backed HC and hosted IDMS plus first executed testcase (V6) |
| AC2 — worker role | `helpers:102–104`; absent/wrong-label negatives; not used as a selection filter | Observed hosted IDMS label in V6 |
| AC3 — independent ignition CM | Second It, management exact key and typed payload/labels/mappings; no dependency on hosted client | Real HCP-namespace CM and second executed testcase (V6) |
| AC4 — v2/lifecycle registration and creation path | Requested filename/registrar/feature annotation; two discovery results; existing 3926 lifecycle setup reused without changes | Authorized create-guests/step-chain invocation and actual selected lifecycle execution |
| Jira EventuallyObjects requirement | Both independent waits use the required helper and exact cardinality | Actual convergence behavior remains V6 |

The six helpers each have a corresponding TestImageMirroring function. Manual typed fixtures/YAML avoid circular production expectations. Cases cover empty/invalid setup, exact Route provenance, input immutability, missing/extra/duplicate/wrong sources, swapped associations, reordered/dropped/duplicated mirrors, repeated-mirror multiplicity, wrong labels/identities, malformed/wrong/empty payload, unrelated metadata/formatting, exact getter contexts/keys, NotFound and injected API failures. Registrar callbacks are compiled/discovered, not executed by ordinary unit tests; this is intentional and is not live coverage.

## Independent validation evidence

All commands below were rerun from the checkout root on the SHA above. Environment: `go version go1.26.3 darwin/arm64`. Every command exited **0**. Logs and matching numeric `.exit` files are in `.work/cntrlplane-3927/review-evidence/`; these are reviewer results, not reused I1 logs.

| Gate / log basename | Exact command | Result |
|---|---|---|
| V1 / `v1` | `GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go test -tags e2ev2 -race -count=1 -v -run '^TestImageMirroring' ./test/e2e/v2/tests` | 6 top-level tests, 76 passing subcases; package 3.347s; no TestE2EV2 execution |
| V2 / `v2` | `make e2ev2` | Binary compiled |
| V3 / `v3-analyzer` | `(cd hack/tools && GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go test -race -count=1 ./hypershiftlinter/analyzers/e2eutilallowlist)` | PASS |
| V3 / `v3-tools` | `make "$(pwd)/hack/tools/bin/golangci-lint" "$(pwd)/hack/tools/bin/hypershiftlinter.so"` | PASS |
| V3 / `v3-lint` | `hack/tools/bin/golangci-lint run --config ./.golangci.yml --modules-download-mode=readonly ./test/e2e/v2/tests/...` | 0 issues; unused exclusion configuration warnings only |
| V4 / `v4-positive` | `bin/test-e2e-v2 --ginkgo.dry-run --ginkgo.v --ginkgo.label-filter='lifecycle && image-mirroring'` | Exactly 2 of 1149 selected; both feature specs |
| V4 / `v4-negative` | `bin/test-e2e-v2 --ginkgo.dry-run --ginkgo.v --ginkgo.label-filter='image-mirroring && !lifecycle'` | Exactly 0 of 1149 selected |
| V5 / `v5-lifecycle` | `GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go test -tags e2ev2 -race -count=1 ./test/e2e/v2/lifecycle/` | PASS |
| V5 / `v5-mirrorregistry` | `GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go test -race -count=1 ./test/e2e/v2/util/mirrorregistry/...` | PASS |
| V5 / `v5-framework` | `make test-e2ev2-unit` | PASS |
| V5 / `v5-diff-check` | `git diff --check` | Clean |
| Additional / `v5-committed-check` | `git diff --check 8d54f7ab3249ddf01777824b35a60e1025d72972 HEAD` | Clean committed increment |
| V5 / `v5-stat` | `git diff --stat 8d54f7ab3249ddf01777824b35a60e1025d72972...HEAD` | Expected six files / 703 insertions |

Both discovered specs inherit `[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring` and labels `[lifecycle, image-mirroring]`:

1. `should propagate imageContentSources to the hosted cluster IDMS with the worker role`
2. `should propagate imageContentSources independently to the control plane ignition ConfigMap`

Neither has Informing. The dry-run logs also print two unrelated pending DNS specs with Informing; those are not selected image-mirroring tests. Positive summary is 2 dry-run passed / 0 failed / 2 unrelated pending / 1145 filtered skipped; negative is 0 / 0 / 2 / 1147. These summaries are discovery evidence only, not two live passing cases.

No source edits, branch changes, commits, publication, Jira, CI or cluster calls were made during review. No V6 or pre-PR make pre-commit was attempted. Normal local build outputs and reviewer support evidence were produced. Actual propagation, runtime permissions/port forwarding, registry reachability, image pulls and node consumption are not established by these gates; the latter workload/node behaviors are also outside this change's scope.
