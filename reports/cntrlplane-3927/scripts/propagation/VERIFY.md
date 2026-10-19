# CNTRLPLANE-3927 — Verification of the live run (checklist for a fresh session)

Input: `propagation/RESULTS.md` (Evidence sections pasted by the user after running `propagation/RUNBOOK.md`).
Reference: `propagation/RUNBOOK.md` (expected outcomes), `propagation/check.sh` (what each PASS line actually tests),
`propagation/env.sh` (constants), `propagation/test-plan.yaml`, the specs in
`test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go` and helpers, and the 3926 T8 baseline
(`reports/cntrlplane-3926/assets/evidence/reachability-RESULTS.md` in this repository: same management cluster, same fixture, same release).

The verifier is **read-only on clusters and code**: do not run `oc`, `hypershift`, `aws`, the lifecycle binaries or
anything that contacts a cluster or AWS. The run is over and the HC is destroyed; judge only from the pasted evidence.
Allowed writes: `.work/cntrlplane-3927/reviews/live.md`, and the table/verdict/"Problems"/"Surprises" parts of
`propagation/RESULTS.md` (never edit the Evidence blocks).

## Constants to cross-check against the evidence

The values below are those of the original run (sanitized). For a new run, replace them with the values printed by
`env.sh` and the commit under test; the shapes stay the same.

| Name | Value |
|------|-------|
| Commit | `c9ad656db6` on `CNTRLPLANE-3927`, clean tree |
| PROW_JOB_ID → HC | `tester-cntrlplane-3927-run1` → `clusters/image-mirroring-beaa1f2bd2`, infra ID = name, HCP ns `clusters-image-mirroring-beaa1f2bd2` |
| NodePool | `image-mirroring-beaa1f2bd2-us-east-1a`, 2 replicas, CLI-default instance type |
| Release | `quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64` |
| Test plan | `image-mirroring-propagation`, one group `image-mirroring`, variant `image-mirroring`, filter `lifecycle && image-mirroring` |
| HOST | `mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com` (as printed by env.sh) |
| Sources | `quay.io/libpod/registry`, `mirror-source.hypershift-e2e.invalid/libpod/registry`; one mirror each = `HOST/<source>` |
| Spec 1 | `[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring should propagate imageContentSources to the hosted cluster IDMS with the worker role` |
| Spec 2 | `… Hosted Cluster Image Mirroring should propagate imageContentSources independently to the control plane ignition ConfigMap` |
| Targets | hosted `ImageDigestMirrorSet/cluster` (label `machineconfiguration.openshift.io/role: worker`); HCP ConfigMap `ignition-config-40-image-content-source` (label `hypershift.openshift.io/core-ignition-config: "true"`, key `config`) |

## Procedure

1. **Completeness.** Evidence for steps 0, 1, 2, 3, 6 (including 6b) is mandatory; 4 is optional; 5 only if something failed.
   Missing mandatory section → verdict at most `INCOMPLETE` (list what is missing; steps 1–5 cannot be redone after
   step 6 without a new run).
2. **Secret hygiene first.** Scan for kubeconfig contents (`client-key-data`, `token:`, `certificate-authority-data`),
   `-----BEGIN ... PRIVATE KEY-----`, pull-secret `auths`/`auth":`, AWS keys (`AKIA`, `aws_secret_access_key`), Keycloak
   passwords. If found: blocker for sharing at the top of `reviews/live.md`, with the lines to redact (do not copy the secret).
   A CA certificate or fingerprint is fine.
3. **Per-step checks** (table below). Every `check.sh` block must end with `0 failure(s)` and the expected PASS count
   (fixture 12, hc 4, junit 6, guest 5, cm 6, clean 7). A FAIL line is not automatically a product failure: decide
   whether it is (a) a real failure, (b) a `check.sh` false negative, or (c) environment (API timeout, laptop DNS).
   Only (a) fails the verdict; (b)/(c) need raw evidence proving the same fact.
4. **Cross-step consistency** (section below).
5. **Verdict and report.**

## Per-step checks

| Step | Must see in the evidence | Red flags |
|------|--------------------------|-----------|
| 0 | `git log` shows `c9ad656db6`, `git status --short` empty; `make` ok; dry run `Will run 2 of <N> specs` with both spec names; namespaces `test-mirror-registry`, `keycloak`, `clusters` NotFound; no HostedCluster; `hs version` client from this branch, server version supporting 4.20; ImageStream `cli` `latest` by `@sha256:`; ARN `…:user/tester`; zone public (`False`); `pull secret has quay.io`; empty `$SHARED`/`$ARTIFACTS` | dirty tree or other commit (evidence would not cover the reviewed code); pre-existing fixture/Keycloak/HC (stale state could satisfy checks) |
| 1 | `Using test plan "image-mirroring-propagation"`; exactly one `Cluster image-mirroring: name=image-mirroring-beaa1f2bd2`; `Keycloak deployed`; one `Running: …hypershift [create cluster aws …]` containing `--name=image-mirroring-beaa1f2bd2`, `--node-pool-replicas=2`, `--release-image=…4.20.0…`, `--base-domain=hypershift.example.com`, `--additional-trust-bundle=…/mirror-registry-ca.pem`, `--image-content-sources=…/mirror-registry-ics.yaml`; `All clusters are ready`, `exit=0`; `check.sh fixture` 12 PASS; `check.sh hc` 4 PASS; ics.yaml two entries `HOST/<source>`; NodePool 2/2 | any other variant created (plan/env wrong → cost); `--aws-creds` present (not the CI path); `ERROR` lines; rollout never `Completed` (acceptable only as a recorded deviation if step 2 still passed) |
| 2 | `Running image-mirroring tests against image-mirroring-beaa1f2bd2...`; `Will run 2 of <N> specs`; two `Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 …` lines — one `hosted ImageDigestMirrorSet/cluster mappings and worker role`, one `ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels`; `Ran 2 of <N> Specs`, `2 Passed`, `All test groups passed`, `exit=0`; `check.sh junit` 6 PASS | `Ran 0`, skipped or pending specs; `DryRun` true; a different HC name; only one `Successfully waited` line |
| 3 | 2 nodes Ready; `check.sh guest` 5 PASS; `check.sh cm` 6 PASS; HC spec, IDMS spec and CM payload show the same two sources and mirrors; IDMS label `worker`; CM label `core-ignition-config: "true"`; payload `apiVersion: config.openshift.io/v1`, `kind: ImageDigestMirrorSet`, `name: cluster`; CPO/HCCO images recorded | mappings differ between HC and either output; mirrors of one source reordered/duplicated; `mirrorSourcePolicy: NeverContactSource` (not set by HyperShift — investigate) |
| 4 (opt.) | same summary as step 2; `check.sh junit` 6 PASS | a flaky second run → finding (the specs are read-only and should be repeatable) |
| 6 | `Destroying 1 clusters from manifest`; one `destroy cluster aws --name=image-mirroring-beaa1f2bd2 … --infra-id=image-mirroring-beaa1f2bd2`; `All clusters destroyed successfully`; `clusters` leftovers only from this HC (e.g. `user-ca-bundle`) before the ns deletion; `check.sh clean` 7 PASS | any leftover AWS resource or namespace → action item with the exact cleanup command; flag cost risk prominently |
| 6b | `KAS_LB`, `OIDC_BUCKET`, `ZONE_ID` printed (non-empty) before the destroy; the four S3/Route53/ELB/ELBv2 queries print nothing | an empty `KAS_LB` (the ELB query then lists every load balancer); any output → leftover, action item with the exact cleanup command |

## Cross-step consistency

- **Same HC everywhere**: manifest, create `Running:` line, `check.sh hc`, run-tests `against …`, both `Successfully waited`
  lines, CM namespace, destroy line. Same `HOST` everywhere (Route, ics.yaml, HC spec, IDMS, CM payload).
- **Oracle is the HC, not an output**: `check.sh guest`/`cm` compare each output with the HC spec separately; the HC spec
  itself matches the fixture file (`check.sh hc`). Both outputs agreeing with each other is not enough on its own.
- **Timeline**: create-guests end < run-tests < step 3 < destroy. Step 3 must run while the HC exists.
- **Context**: every management-cluster command on `mgmt` (CLI API URL `api.mgmt.hypershift.example.com:6443`).

## Known limitations (state them, do not count them as findings)

- The producers exercised are the CPO/HCCO of the **4.20.0** release payload, not code built from this branch. The 3927
  change is test-only, so this validates the tests against a real producer; current-main producers are covered by the
  CNTRLPLANE-3929 job.
- One run on one management cluster; not the "five consecutive reliable CI runs" asked by CNTRLPLANE-3922 for making the job required.
- Keycloak is deployed by the current AWS `PreCreate` even though only `image-mirroring` is selected (pre-existing behavior;
  mention it as a cost/flakiness note for CNTRLPLANE-3929, not a 3927 finding).
- Negative cases (wrong labels, missing/reordered mirrors, wrong CM, malformed payload) are covered by the unit tests in
  `hosted_cluster_image_mirroring_helpers_test.go`, not by this run.

## Output (`.work/cntrlplane-3927/reviews/live.md`)

Verdict (`PASS` / `PASS with notes` / `FAIL` / `INCOMPLETE`), step table with observed values, consistency results,
findings with severity, `check.sh` false negatives, leftovers, and a short PR evidence paragraph (commit, release,
HC, the two specs passed, independent check results, cleanup).
