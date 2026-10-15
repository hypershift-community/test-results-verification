# T8a — Verification of the T8 run (checklist for a fresh session)

Input: `reachability/RESULTS.md` (Evidence sections pasted by the user after running `reachability/RUNBOOK.md`).
Reference: `reachability/RUNBOOK.md` (expected outcomes), `reachability/check.sh` (what each PASS line actually tests),
`reachability/env.sh` (constants), `harness/RESULTS.md` (T6 baseline: timings, output shapes).

The verifier is **read-only on clusters and code**: do not run `oc`, `hypershift`, `aws`, `harness` or anything
that contacts a cluster or AWS. The run is over and the HC is destroyed; judge only from the pasted evidence.
Allowed writes: `reviews/T8.md`, the table/verdict/"Problems"/"Surprises" parts of `reachability/RESULTS.md`
(never edit the Evidence blocks), and — only on PASS — `README.md` status and `HANDOFF.md` "Next".

## Constants to cross-check against the evidence

| Name | Value |
|------|-------|
| HOST | `mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com` |
| Virtual repo | `mirror-source.hypershift-e2e.invalid/libpod/registry` |
| Real repo | `quay.io/libpod/registry` |
| TEST_DIGEST | `sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f` |
| HC | `clusters/mirror-reach`, NodePool `mirror-reach-us-east-1a`, HCP ns `clusters-mirror-reach`, 2 replicas |
| Release | `quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64` |
| Mirror ns / name | `test-mirror-registry` / `mirror-registry` |
| Trust bundle CM | `clusters/user-ca-bundle` (written by the CLI) |
| Guest test ns / pods | `mirror-reach-check` / `mirror-by-digest` (positive), `mirror-by-tag` (negative) |

## Procedure

1. **Completeness.** Every Evidence section (steps 0–8) has output. Missing step 7 is acceptable (optional);
   any other missing section → verdict at most `INCOMPLETE` (list exactly what to re-run or paste; note that
   steps 2–7 cannot be re-run after step 8 without a new HC).
2. **Secret hygiene first.** Scan the whole file for kubeconfig contents (`client-key-data`, `token:`,
   `certificate-authority-data`), `-----BEGIN ... PRIVATE KEY-----`, pull-secret `auths`/`auth":`, AWS keys
   (`AKIA`, `aws_secret_access_key`). If found: report it at the top of `reviews/T8.md` as a **blocker for
   sharing** and tell the user which lines to redact; do not copy the secret into the review.
   (A CA *certificate* or its fingerprint is fine.)
3. **Per-step checks** (table below). For each `check.sh` block: the summary line must be `0 failure(s)` and
   the number of PASS lines must match (hc 3, guest 7, pods 5). A FAIL line is not automatically a product
   failure: read the raw evidence around it and decide whether it is (a) a real failure, (b) a `check.sh`
   false negative (e.g. log format different from the grep, reconciliation not finished yet and passed on a
   re-run), or (c) an environment problem (API timeout). Only (a) fails the verdict; (b)/(c) need the raw
   evidence to independently prove the same fact.
4. **Cross-step consistency** (section below).
5. **Verdict and report.**

## Per-step checks

| Step | Must see in the evidence | Red flags |
|------|--------------------------|-----------|
| 0 | `test-mirror-registry` NotFound; `No resources found` for HCs; `hs version` shows a server version (HO reachable) and support for 4.20; AWS ARN `…:user/tester`; zone `hypershift.example.com.` `False` (public); `pull secret has quay.io`; `harness builds` | an existing HC/namespace (stale state could make later checks pass for the wrong reason); a private zone |
| 1 | harness exit 0; `copier image: …ocp-v4.0-art-dev@sha256:…`; Result `Host` == HOST, `InternalHost` `mirror-registry.test-mirror-registry.svc:5000`, 2 Images with `MirrorRef` = `HOST/<repo>@TEST_DIGEST`; `verify: 0 failure(s)` with 5 PASS; `ics.yaml` exactly 2 entries (virtual first, then quay), each 1 mirror = `HOST/<source>`; CA subject `CN=hypershift-e2e-mirror-registry-ca`; a SHA-256 fingerprint recorded | `VIOLATION` in the optional watch log; Setup ≫ 2 min (T6: 28–55 s) — note, not a failure |
| 2 | CLI exit 0 (no `Error`/`failed` as last lines); `Applied Kube resource` lines incl. ConfigMap `user-ca-bundle`, HostedCluster, NodePool; `INFRA_ID=mirror-reach-<suffix>`; `check.sh hc` 3 PASS; the printed `spec.additionalTrustBundle` = `{"name":"user-ca-bundle"}` and `spec.imageContentSources` = the 2 entries of step 1 | create run against a context other than mgmt (API URL in logs must be the mgmt one: `api.mgmt.hypershift.example.com:6443`); ICS mismatch |
| 3 | HC `Available=True`; NodePool 2 desired / 2 current; `AllNodesHealthy` met | conditions mentioning the mirror, ICS, IDMS or `user-ca-bundle` (would mean our inputs broke the control plane) |
| 4 | 2 nodes `Ready`, RHCOS 9.6 / kubelet v1.33 / cri-o 1.33; node names recorded. ClusterVersion `Available=False`/`Progressing=True` with an empty VERSION and a message about a cluster operator (e.g. `monitoring`) still installing is **expected** at this point, not a finding | fewer than 2 Ready nodes (step 5/6 then only prove one node — acceptable if the tested node is Ready, note it) |
| 5 | `check.sh guest` 7 PASS; IDMS spec has both sources each mapped to `HOST/<source>` (and no `mirrorSourcePolicy: NeverContactSource`); registries.conf excerpt: `location = "<virtual repo>"` with a `[[registry.mirror]]` `location = "HOST/<virtual repo>"` and `pull-from-mirror = "digest-only"` (or `mirror-by-digest-only = true`) | node checks passing only on a node different from the one used in step 6 (compare node names); `curl` result not `{} 200` |
| 6 | `mirror-by-digest` `1/1 Running`; events in order `Pulling image "<virtual repo>@TEST_DIGEST"` → `Successfully pulled image …` (a real pull: must **not** be `already present on machine`); pod log `listening on [::]:5000`; `imageID` starts with `<virtual repo>@sha256:` (instance digest ≠ TEST_DIGEST is fine); `mirror-by-tag` `ErrImagePull`/`ImagePullBackOff` with a DNS/resolution error for `mirror-source.hypershift-e2e.invalid` (`no such host`, `lookup …`, or `pinging container registry …`); `check.sh pods` 5 PASS; mirror log lines: `GET`, uri `/v2/<virtual repo>/manifests/sha256:…`, user agent `cri-o/…`, status 200 | tag pod failing with an **x509 / TLS / 401 / 403** error mentioning HOST (would mean the mirror was contacted for a tag, i.e. not digest-only); digest pod `Running` but no CRI-O lines in the mirror log (pull did not come from the mirror — investigate before PASS); `PodSecurity` violation warning |
| 7 (opt.) | `after > before`; a new `Pulled` event for the recreated pod on the same node | `after == before` → `Always` did not re-contact the mirror: report as a finding for the CNTRLPLANE-3928 note in `plan.md` (not a T8 failure) |
| 8 | destroy exit 0; HC/NodePool `No resources found`; `clusters-mirror-reach` NotFound; VPC and instance queries empty for INFRA_ID; `clusters` ns deleted; `harness teardown` OK and `test-mirror-registry` NotFound | any leftover AWS resource or namespace → list it as an action item with the exact cleanup command (`hypershift destroy cluster aws … --infra-id`, or `aws ec2 …`); cost risk, flag prominently |

## Cross-step consistency

- **Same CA everywhere.** The fingerprint from step 1 must be what `check.sh hc` (CM), and `check.sh guest`
  (guest `user-ca-bundle`, node anchor) compared against. If the user re-ran `harness setup` after step 2 (a
  second Setup log, or a different fingerprint), the CA Secret is reused so the CA is unchanged — confirm the
  fingerprint is identical; otherwise nodes trust a stale CA and step 6 evidence is invalid.
- **Same HOST everywhere** (Result, ics.yaml, HC spec, IDMS, registries.conf, curl, mirror log host).
- **Same digest everywhere** (pod spec, Pulling event, mirror log uri `manifests/sha256:e642e860…`).
- **Same node** for the step 5 node checks and the step 6/7 pod (`spec.nodeName`), or both nodes checked.
- **Timeline.** Setup (step 1) < HC creation (step 2) < pod creation (step 6) < mirror log lines < destroy (step 8).
  The mirror registry pod must not have been restarted between step 1 and step 6 (its log would be truncated):
  if the step 6 log shows nothing before the pod creation, that is fine; if it shows a fresh `listening on`
  after step 2, ask why.
- **Context.** Every management-cluster command ran on `mgmt` (no `parent-cluster` context, no parent
  namespaces in the evidence).

## Known limitation (state it, do not count it as a finding)

T8 feeds the CLI from `harness setup` outputs (`ca-only/ca.crt`, `ics.yaml`), not from the T7 `PreCreate`
files (`mirror-registry-ca.pem`, `mirror-registry-ics.yaml`). Both are produced by `yaml.Marshal` of the same
`[]hyperv1.ImageContentSource` and the same `Result.CABundlePEM`; T7 unit tests cover the file contents. The
end-to-end `create-guests` path is exercised for the first time by the CNTRLPLANE-3929 job.

## Verdict values

- `PASS` — every mandatory step proven, no secrets in the file, cleanup complete.
- `PASS with notes` — proven, but with non-blocking notes (e.g. optional step 7 skipped, slow timings, a
  `check.sh` false negative independently disproved by raw evidence, a cleanup leftover already removed).
- `FAIL` — a real failure in steps 2, 5 or 6 (the acceptance criterion is not proven). Give the most likely root
  cause from the evidence and the minimal re-run (new HC needed).
- `INCOMPLETE` — evidence missing or ambiguous; list exactly what is needed.

## Output

`reviews/T8.md`:
- Verdict (one line) and secret-hygiene result;
- Table: step | expected | observed (exact value from the evidence) | OK/FAIL/NOTE;
- Cross-step consistency results (CA fingerprint, HOST, digest, node, timeline);
- Findings: severity (blocker / major / minor / nit) | step | problem | action;
- `check.sh` false negatives found (with a proposed fix to the script, for future reuse);
- **PR evidence paragraph** (5–8 lines, no secrets, no "guest cluster" wording) for the T9 PR description:
  HC version/size, inputs used, what the pod proved, negative control, mirror log line, cleanup.

Then in `reachability/RESULTS.md`: fill the table `Result`/`Notes` columns, the **Verdict** line, "Problems found" and
"Surprises" (leave Evidence untouched). On `PASS`/`PASS with notes`: tick T8 in `README.md` and point
`HANDOFF.md` "Next" to T9.
