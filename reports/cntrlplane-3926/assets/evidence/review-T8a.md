# Review — T8 Hosted-node reachability (evidence verification, T8a)

Evidence: `reachability/RESULTS.md` (run of 2026-10-14 on `mgmt`, HC `clusters/mirror-reach`, INFRA_ID `mirror-reach-kn775`).
Spec: `reachability/VERIFY.md`. Read-only: no cluster or AWS calls. Local file `out/mirror/` listed only, not read.

## Verdict: PASS with notes

**Secret hygiene: clean.** No `client-key-data`, `token:`, `certificate-authority-data`, `PRIVATE KEY`, `auths`/`auth":`,
`AKIA`, `aws_secret_access_key` or PEM blocks in `RESULTS.md`. The account ID `123456789012` and AWS resource IDs are
present: they are not secrets, but strip them from anything posted publicly (the PR paragraph below has none).

Completeness: Evidence for steps 0–8 is all present, including the optional step 7.

## Per-step results

| Step | Expected | Observed | |
|---|---|---|---|
| 0 | ns absent, no HC, HO up with 4.20, ARN tester, public zone, pull secret, harness builds | `namespaces "test-mirror-registry" not found`; `No resources found`; Server `e83d9072…` supports `4.21, 4.20, …`; `arn:aws:iam::123456789012:user/tester`; `hypershift.example.com.   False`; `pull secret has quay.io`; `harness builds` | OK |
| 1 | Setup exit 0, copier image, Result shape, verify 5/5, ics.yaml 2 entries, CA subject, fingerprint | `setup finished in 46s`; `copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9…`; `Host` = HOST, `InternalHost` `mirror-registry.test-mirror-registry.svc:5000`; 2 Images, `MirrorRef` `HOST/quay.io/libpod/registry@sha256:e642e860…` and `HOST/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e860…`; 5 PASS, `verify: 0 failure(s)`; ics.yaml virtual first, then quay, each 1 mirror `HOST/<source>`; `CN=hypershift-e2e-mirror-registry-ca`; `AA:83:E6:32:…:1F:B9`; watcher: no `VIOLATION`, route admitted 15:35:33 | OK |
| 2 | CLI ok, Applied CM/HC/NodePool, INFRA_ID, check hc 3/3, spec values | `Applied Kube resource` ConfigMap `clusters/user-ca-bundle`, `mirror-reach` (kind printed as `""`), NodePool `mirror-reach-us-east-1a`; no error lines; `INFRA_ID=mirror-reach-kn775`; 3 PASS, `check hc: 0 failure(s)`; `{"name":"user-ca-bundle"}`; ICS has the same 2 entries as step 1 | OK (see note N2) |
| 3 | HC Available, NodePool 2/2, AllNodesHealthy | `condition met` ×2; HC `AVAILABLE True` "The hosted control plane is available"; NodePool `2 2 … 4.20.0 False False`; no condition mentions the mirror, ICS, IDMS or user-ca-bundle | OK |
| 4 | 2 Ready nodes, RHCOS 9.6 / v1.33 / cri-o 1.33 | `ip-10-0-130-125.ec2.internal`, `ip-10-0-134-84.ec2.internal` both `Ready worker v1.33.5`, RHCOS `9.6.20250925-0`, `cri-o://1.33.4-4.rhaos4.20…`; CV `False True … monitoring is not available` (expected) | OK |
| 5 | check guest 7/7, IDMS, registries.conf digest-only | 7 PASS, `check guest: 0 failure(s)`, node under test `ip-10-0-130-125`; IDMS 2 entries mapped to `HOST/<source>`, no `mirrorSourcePolicy`; `location = "mirror-source.hypershift-e2e.invalid/libpod/registry"` → `[[registry.mirror]] location = "HOST/mirror-source…/libpod/registry"`, `pull-from-mirror = "digest-only"`; curl PASS (`{} 200`) | OK |
| 6 | digest pod Running after a real pull, tag pod fails on DNS, check pods 5/5, mirror log CRI-O manifests 200 | `mirror-by-digest 1/1 Running`; `Pulling image "…invalid/libpod/registry@sha256:e642e860…"` → `Successfully pulled image … in 807ms`; pod log `listening on [::]:5000`; imageID `…invalid/libpod/registry@sha256:da1fbcd1…` (instance digest); `mirror-by-tag ErrImagePull` → `lookup mirror-source.hypershift-e2e.invalid on 10.0.0.2:53: no such host` (no TLS/401/403 to HOST); no PodSecurity warning; check pods 6 PASS (the spec says 5; the script has 6 checks), `0 failure(s)`, `manifests → 200 (4/4 lines)`, `no tag lookups`; raw mirror lines: `GET /v2/mirror-source…/libpod/registry/blobs/sha256:…`, `http.request.host=HOST`, `useragent="cri-o/1.33.4 os/linux arch/amd64"`, `status=200` | OK (see note N1) |
| 7 | after > before, new Pulled event | `before=4 after=8`; `Successfully pulled image … in 67ms` for the recreated pod pinned with `spec.nodeName` to the same node | OK |
| 8 | destroy ok, no HC/NP/HCP ns, no VPC/instances, `clusters` deleted, teardown, ns NotFound | `Successfully destroyed cluster and infrastructure … mirror-reach-kn775` (16:05:57→16:12:04, ~6 min; NAT/VPC retries were transient); `No resources found`; `clusters-mirror-reach` NotFound; VPC and instance queries empty; `namespace "clusters" deleted`; `teardown finished in 21s`; `test-mirror-registry` NotFound | OK (see note N3) |

## Cross-step consistency

- **CA:** there is a single `harness setup` run (one Setup log, one copy job). `check.sh` builds `CA_FP` from the same
  `$RUN/ca-only/ca.crt` that step 1 fingerprinted (`AA:83:E6:32…1F:B9`). The HC ConfigMap, the guest
  `user-ca-bundle` and the node anchor all matched that CA. Consistent.
- **HOST:** `mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com`
  is the same in the Result, ics.yaml, HC spec, IDMS, registries.conf, curl and the mirror log `http.request.host`. Consistent.
- **Digest:** `sha256:e642e860…` is the same in the pod spec (check pods PASS), the Pulling/Pulled events and the
  step 7 event. The raw mirror log URI with the manifest digest was not pasted (N1). The imageID `da1fbcd1…` is the
  amd64 instance digest, as the spec allows.
- **Node:** `ip-10-0-130-125.ec2.internal` is used for the step 5 node checks, both step 6 pods and step 7. Consistent.
- **Timeline** (local +02:00): Setup 15:34:46–15:35:31 < create 15:37:46–15:38:12 < pod pull 15:56:53 (mirror log
  13:56:53Z) < destroy 16:05:57–16:12:04 < teardown 16:14:38. The step 6 count (4 manifest lines) equals the step 7
  `before=4`, so the mirror log was not truncated between the two steps. The `listening on [::]:5000` line in step 6
  comes from the test pod's own log (the test image is itself a registry), not from the mirror.
- **Context:** the harness logs show the mgmt API (`api.mgmt.hypershift.example.com:6443`). `hs`
  only receives the `mc.kubeconfig` from `env.sh`, which contains just mgmt. All prompts show `mgmt`.
  The parent cluster does not appear anywhere.

## Findings

| Sev | Step | Problem | Action |
|---|---|---|---|
| minor | 6 | The raw mirror-log excerpt (`… \| tail -5`) shows only blob GETs. The manifest GET line is proven only by the `check.sh pods` PASS (`4/4 lines`) and by step 7 (`4→8`). Blob GETs from the virtual-repo path also imply that a manifest was resolved first. | Not blocking. For future runs, change the runbook command to `grep -F "/v2/$VIRTUAL_REPO/manifests/"` (see below). |
| nit | 6 | `VERIFY.md` expects "check pods 5 PASS", but `check.sh pods` prints 6 checks. `4/4 lines` means 2 requests (manifest list + amd64 manifest), because each request is logged twice (logfmt + access log). | Fix the count in VERIFY/RUNBOOK. |
| nit | 2 | The CLI logs the HostedCluster as `"kind":""`. This is an upstream CLI quirk, and `check.sh hc` confirms the HC exists. Create took ~26 s (runbook said 3–6 min). | None. |
| note | 8 | `hypershift destroy` deletes the CLI-generated Secrets but leaves the `clusters/user-ca-bundle` ConfigMap behind. The name is fixed per namespace. It was removed here by deleting the `clusters` namespace. | Follow-up for CNTRLPLANE-3929: confirm that destroy-guests or namespace cleanup removes it, so a later HC in the same namespace does not inherit a stale CA. |

No leftovers: the VPC, instances, NAT/EIP, subnets, IGW, Route53 private zones, IAM roles, instance profile and OIDC
provider were all deleted (destroy log + empty queries). The VPC delete succeeded, which also rules out leftover
non-default security groups.

## `check.sh` false negatives

None (every line PASS). Suggested improvements for reuse:
- RUNBOOK step 6: `k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -F "/v2/$VIRTUAL_REPO/manifests/" | tail -4`
  so that the manifest GET lines are pasted.
- `check.sh pods`: report requests, not lines, e.g. count only `http.response.status=200` lines. Optionally also assert
  that `http.request.host` == HOST.

## Known limitation (not a finding)

T8 fed the CLI from the `harness setup` outputs (`ca-only/ca.crt`, `ics.yaml`), not from the T7 `PreCreate` files.
Both come from `yaml.Marshal` of the same `[]hyperv1.ImageContentSource` and the same `Result.CABundlePEM`, and T7 unit
tests cover the file contents. The CNTRLPLANE-3929 job will be the first end-to-end run of `create-guests`.

## PR evidence paragraph

> Manually validated on a dedicated AWS HostedCluster (OCP 4.20.0, 2 workers, RHCOS 9.6 / CRI-O 1.33) created with
> `hypershift create cluster aws --additional-trust-bundle <fixture CA> --image-content-sources <fixture ICS>`, using
> the outputs of a fresh fixture `Setup` (46 s). The HostedCluster carried the CA ConfigMap and both ICS entries.
> In the hosted cluster, the IDMS, `openshift-config/user-ca-bundle`, the node trust anchor and a digest-only
> `registries.conf` mirror entry were all present, and `curl https://<mirror>/v2/` from a node with system trust
> returned `{} 200`. A pod referencing `mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e860…` with
> `imagePullPolicy: Always` pulled in 807 ms and ran. The mirror logged CRI-O (`cri-o/1.33.4`) anonymous `GET` requests
> for that repository → 200. Negative control: the same repository by tag failed with `no such host`, and the mirror
> logged no tag lookup. Recreating the pod on the same node produced new manifest requests (4→8). Cleanup:
> HostedCluster, AWS infrastructure and fixture namespace removed, no leftovers.
