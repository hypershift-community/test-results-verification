# CNTRLPLANE-3927 — Live propagation run review

Input: `propagation/RESULTS.md` Evidence (run 2026-10-19, 12:17–13:06 CEST), checked against `propagation/VERIFY.md`,
`RUNBOOK.md`, `check.sh`, `env.sh`, `test-plan.yaml`, the specs at `c9ad656db6`, and the 3926 T8 baseline.
No cluster/AWS access by the reviewer. Local read-only cross-checks: `out/run-tests*.log`, `out/artifacts/*.xml`,
`v4-positive.log`, the `server:` line of `out/mc.kubeconfig`, `git blame`, repo grep.

## Verdict: **PASS with notes**

All mandatory steps (0, 1, 2, 3, 6) are present, plus the optional step 4 and step 5 (run anyway). All `check.sh` blocks
end with `0 failure(s)` and the expected counts: fixture 12, hc 4, junit 6 (twice), guest 5, cm 6, clean 7.
Both specs executed live (DryRun=false) against the right HC and passed, twice. The independent `oc`/`jq` checks
confirm both outputs against the HC spec. Cleanup is clean. No finding blocks the PR. The notes cover a runbook grep
false negative, pre-existing noise and leftover checks outside `check.sh clean`. Those were run afterwards
(RESULTS.md step 6b) and found nothing.

## Secret hygiene

Clean. No kubeconfig contents, private keys, pull-secret `auths`, AWS keys or passwords in `RESULTS.md`. The only hit
for `password` is the `E2E_EXTERNAL_OIDC_TEST_USERS` env help text. The Keycloak UUIDs, OIDC issuer URL and ELB hostnames
are not secrets. **But** `propagation/out/` still holds `mc.kubeconfig` (admin credentials for mgmt) and the
`dump-guests` output under `out/artifacts/image-mirroring-beaa1f2bd2/`. Never attach `out/` to the PR or Jira. Delete
`out/mc.kubeconfig` when you no longer need it. `guest.kubeconfig` was already removed.

## Step table (observed)

| Step | Result | Observed |
|------|--------|----------|
| 0 | OK (1 note) | `c9ad656db6`, `git status --short` empty; 5 binaries built with commitHash c9ad656; dry run `Will run 2 of 1149 specs`; spec names **not** printed by the grep (N1), but they appear in `v4-positive.log` and the live run; `test-mirror-registry`/`keycloak`/`clusters` NotFound; no HC; client c9ad656, server e83d9072 supports 4.14–4.21; copier `ocp-v4.0-art-dev@sha256:0a9d58f9…`; ARN `…123456789012:user/tester`; zone public `False`; pull secret has quay.io; SHARED/ARTIFACTS empty; nodes 33–53 % memory |
| 1 | OK | plan `image-mirroring-propagation`; one cluster `image-mirroring-beaa1f2bd2`; Keycloak deployed; one `Running:` line with `--name=image-mirroring-beaa1f2bd2 --namespace=clusters --infra-id=… --node-pool-replicas=2 --release-image=…4.20.0-x86_64 --base-domain=hypershift.example.com --additional-trust-bundle=…/mirror-registry-ca.pem --image-content-sources=…/mirror-registry-ics.yaml`; no `--aws-creds`, no `--instance-type` (CLI default); no ERROR lines; Available 12:24:23, rollout Completed 12:33:04; `All clusters are ready`, exit=0; 12:17:29→12:33:04 = **15.5 min** (faster than the 25–45 min estimate); fixture 12/12; hc 4/4; ics.yaml has 2 entries `HOST/<source>` (virtual first); NodePool 2/2, 4.20.0; HC junit "version rollout succeeds" |
| 2 | OK | `Running image-mirroring tests against image-mirroring-beaa1f2bd2...`; `Will run 2 of 1149`; both `Successfully waited` lines (IDMS 1.075 s, CM 125 ms) with the right HC/namespace/target; `Ran 2 of 1149`, `2 Passed \| 0 Failed \| 2 Pending \| 1145 Skipped` (the 2 pending are unrelated `PIt` DNS specs, N4); `image-mirroring tests PASSED`, `All test groups passed`, exit=0; junit 6/6 |
| 3 | OK | 2 nodes Ready (v1.33.5); guest 5/5; cm 6/6; HC spec, hosted IDMS spec and CM payload show the same 2 sources, each with one mirror `HOST/<source>`, in the same order; IDMS labels `machineconfiguration.openshift.io/role: worker` (+ `hypershift.openshift.io/managed: "true"`); no `mirrorSourcePolicy`; CM label `core-ignition-config: "true"`; payload `config.openshift.io/v1` / `ImageDigestMirrorSet` / `name: cluster` / worker label / no namespace; CPO = HCCO = `ocp-v4.0-art-dev@sha256:5491113a…` (N5) |
| 4 | OK | IDMS 1.275 s, CM 150 ms; `Ran 2 of 1149`, `2 Passed`, `All test groups passed`; junit 6/6. Local `diff` of the two logs: only timestamps, seed and durations differ, so the specs are repeatable and read-only |
| 5 | Info only | dump-guests OK (5m39s). CPO logs `Reconciling ImageDigestMirrorSet` (`hostedcontrolplane_controller.go:2466`, the in-memory IDMS → ignition CM path) about every 1 s during the dump window. That is ordinary reconcile noise. HCCO grep is empty because HCCO does not log IDMS reconciles, which is expected |
| 6 | OK (notes) | manifest = the single image-mirroring entry; `Destroying 1 clusters from manifest`; one `destroy cluster aws --name=image-mirroring-beaa1f2bd2 --namespace=clusters --infra-id=image-mirroring-beaa1f2bd2 --cluster-grace-period=40m --region=us-east-1 --base-domain=hypershift.example.com`; normal `DependencyViolation` retries while NAT drained; VPC, IGW, subnets, route tables, EIP, DHCP, VPC endpoint, both private zones, OIDC provider, all IAM roles/policies and instance profile deleted; `All clusters destroyed successfully`, exit=0; 12:58:45→13:05:16 = **6.5 min** (T8: ~6 min); `clusters` leftovers = `user-ca-bundle` + OpenShift defaults only, then ns deleted; keycloak + test-mirror-registry deleted; clean 7/7 |

## Cross-step consistency

- **Same HC everywhere: OK.** `clusters/image-mirroring-beaa1f2bd2` (= sha256(`tester-cntrlplane-3927-run1`)[:10])
  appears in env.sh, Phase 0, the manifest (create and step 6), the `Running:` create line, `check.sh hc`, `against …`,
  both `Successfully waited` lines, the CM namespace `clusters-image-mirroring-beaa1f2bd2`, `check.sh cm` and the destroy
  line. The infra ID equals the name.
- **Same HOST everywhere: OK.** `mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com`
  appears in env.sh, the Route and `mirror-registry.json` (`check.sh fixture`), ics.yaml, the HC spec, the hosted IDMS and
  the CM payload. It is identical to the 3926 T8 host.
- **Oracle is the HC: OK.** `check.sh hc` makes the HC spec equal to the fixture ICS file. `check.sh guest` and `check.sh cm`
  then compare each output with the HC spec separately (`hc_ics`), never with each other. The specs do the same
  (`Successfully waited` messages name HC → target).
- **Timeline: OK.** create-guests ends 12:33:04 < run-tests 12:40:33–12:40:39 < step 3 (no timestamp; nodes aged 16 min,
  joined around 12:30, so roughly 12:41–12:47) < step 4 ends 12:47:34 < dump 12:55:41 < destroy 12:58:45–13:05:16
  < namespace deletion / clean. Step 3 ran while the HC existed: it read live objects from both clusters.
- **Context: OK.** Every `k` call uses `--context mgmt`. The binaries get `out/mc.kubeconfig`, whose only context
  is `mgmt`, server `https://api.mgmt.hypershift.example.com:6443`, which matches the
  expected `api.mgmt.hypershift.example.com`. The Keycloak issuer and mirror Route are on `apps.mgmt…`.

## Findings / notes

| # | Sev | Step | Note | Class | Action |
|---|-----|------|------|-------|--------|
| N1 | Low | 0 | The runbook grep `'Image Mirroring should'` matched no names. Ginkgo colours the output (`…Mirroring \e[0m\e[1mshould…`) even when piped. `Will run 2 of 1149` was printed. | runbook false negative | Raw proof: `v4-positive.log` lines 82/86, the live run output and the JUnit testcase names. For reuse, add `--ginkgo.no-color` to the dry run. |
| N2 | Info | 1 | create-guests prints a `[controller-runtime] log.SetLogger(...) was never called` stack trace at the start of Phase 3 (`create-guests/main.go:355`, `newMgmtClient`). | pre-existing (blame: 2026-05, not 3926/3927), cosmetic | Optional follow-up: set a logger in create-guests (CNTRLPLANE-3929 log readability). Not a 3927 finding. |
| N3 | Info | 1 | During the rollout, HC `Available` flipped True↔False several times on KAS ELB `/healthz` timeouts (terminal 2). | environment (nested mgmt cluster / new ELB) | None for 3927. CI note: create-guests tolerated it; the specs ran after `Completed`. |
| N4 | Info | 2/4 | The Ginkgo summary shows `2 Pending`. These are the `PIt` DNS specs in `hosted_cluster_dns_test.go:38/68`, which Ginkgo reports as pending regardless of the label filter. They are not in the JUnit file (`tests=2 skipped=0`). | pre-existing, harmless | None. |
| N5 | Info | 3 | CPO and HCCO run the same image `ocp-v4.0-art-dev@sha256:5491113a…`. That is expected: HCCO is a CPO-image binary. The digest is not in any repo override file, so it fits the 4.20.0 payload. Not independently proven without the release info. | expected | Optional: `oc adm release info quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 --image-for=hypershift` should print the same digest. |
| N6 | Low | 6 | `check.sh clean` only checks the VPC and instances. The destroy log covers the other resources, but three were not checked: the OIDC discovery documents in S3 `oidc-bucket/image-mirroring-beaa1f2bd2`, public-zone records for `*.apps.image-mirroring-beaa1f2bd2…` in `Z00000000000000000000`, and the management-side KAS ELB `kas-lb…` (it should go with the HCP namespace's Service). | coverage gap | **Resolved**: the four queries below were run after the review (RESULTS.md step 6b) and all printed nothing. |
| N7 | Info | 1 | Runbook bug: `oc get hostedcluster,nodepool -w` is rejected because `-w` takes a single resource type. The user split it into two terminals. | runbook | Fix the runbook if reused. |
| N8 | Info | — | `out/` holds `mc.kubeconfig` and an unredacted dump. | hygiene | Delete or keep local only, see above. |

No real (class a) failures. `check.sh` false negatives: none in `check.sh` itself. N1 is in a runbook grep.

Read-only leftover confirmation (run after the review; all four printed nothing, see RESULTS.md step 6b):
```bash
e2e aws s3 ls s3://oidc-bucket/image-mirroring-beaa1f2bd2/
e2e aws route53 list-resource-record-sets --hosted-zone-id Z00000000000000000000 --query "ResourceRecordSets[?contains(Name,'image-mirroring-beaa1f2bd2')].Name" --output text
e2e aws elb describe-load-balancers --region us-east-1 --query "LoadBalancerDescriptions[?starts_with(LoadBalancerName,'kas-lb')].LoadBalancerName" --output text
e2e aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?starts_with(LoadBalancerName,'kas-lb')].LoadBalancerName" --output text
```
Result: all four empty, so no S3 OIDC documents, public DNS records or management-side KAS load balancers remain.

## Known limitations (not findings)

- The producers exercised are the CPO/HCCO of the **4.20.0** release payload, not code built from this branch. The 3927
  change is test-only. Producers from current main are covered by the CNTRLPLANE-3929 job.
- This was one run on one management cluster, not the five consecutive CI runs CNTRLPLANE-3922 requires.
- Keycloak was deployed by AWS `PreCreate` although only `image-mirroring` was selected. That is a cost/flakiness note for
  CNTRLPLANE-3929.
- Negative cases are covered by the unit tests in `hosted_cluster_image_mirroring_helpers_test.go`, not by this run.

## PR evidence paragraph

> Live validation (manual, 2026-10-19) of `c9ad656db6` on a 4.20 management cluster (HO e83d9072) through the
> v2 lifecycle path CI will use: `create-guests` with `HYPERSHIFT_E2E_IMAGE_MIRRORING=true` and a one-group test plan
> (`variant: image-mirroring`, `labelFilter: "lifecycle && image-mirroring"`) set up the mirror registry fixture and
> created one AWS HostedCluster (`ocp-release:4.20.0-x86_64`, 2 workers) with the fixture CA and two
> imageContentSources (`quay.io/libpod/registry`, `mirror-source.hypershift-e2e.invalid/libpod/registry`), each
> mirrored to the fixture Route. Available and version rollout Completed in 15.5 min. `run-tests` ran **2 of 1149
> specs, 2 passed** (JUnit: 2 testcases `passed`, none skipped, DryRun=false):
> `…should propagate imageContentSources to the hosted cluster IDMS with the worker role` and
> `…should propagate imageContentSources independently to the control plane ignition ConfigMap`. A second run gave the
> same result. Independent `oc`/`jq` checks against the HostedCluster spec confirmed the hosted `ImageDigestMirrorSet/cluster`
> (worker role label, identical mappings, mirror order kept) and the HCP ConfigMap `ignition-config-40-image-content-source`
> (core-ignition label, `data.config` decodes to a `config.openshift.io/v1` IDMS `cluster` with worker label and
> identical mappings). The producers were the 4.20.0 payload CPO/HCCO. `destroy-guests` removed the cluster and its AWS
> infrastructure in 6.5 min. No HC, namespaces, PV, VPC or instances were left.
