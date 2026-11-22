# T8 — Hosted-node reachability results

Date: 2026-10-14  Cluster: mgmt (OCP 4.20.0, nested hosted cluster)  HC: `clusters/mirror-reach` (4.20.0, 2 nodes)  Branch/commit: `CNTRLPLANE-3926` @ `38342d4965`  Run by: @Nirshal

Keep table cells to one line. Put command output in the **Evidence** section below, under the matching step,
inside a fenced code block. Never paste kubeconfigs or keys.

**Verdict:** PASS with notes (T8a, `reviews/T8.md`)

| Step | Item | Result | Notes / exact values |
|------|------|--------|----------------------|
| 0 | Preflight (ns absent, no HC, CLI/HO versions, AWS identity, public zone, pull secret) | OK | Client cce02430, Server e83d9072 (4.14–4.21), user/tester, zone public |
| 1 | Fresh `harness setup` succeeds; verify.sh 5/5 | OK | 46s; 5/5; CA SHA-256 `AA:83:E6:32:…:D6:81:1F:B9`; no VIOLATION |
| 1 | `ics.yaml` two entries (virtual + real repo) | OK | virtual first, then quay.io; 1 mirror each = `HOST/<source>` |
| 2 | `hypershift create cluster aws` with `--additional-trust-bundle` / `--image-content-sources` | OK | ~26s (15:37:46→15:38:12); INFRA_ID `mirror-reach-kn775` |
| 2 | `check.sh hc` 3/3 (trust bundle CM == CA, ICS == harness) | OK | 3/3; `{"name":"user-ca-bundle"}`, 2 ICS entries |
| 3 | HC Available | OK | Available=True, PROGRESS Partial (expected); no mirror-related conditions |
| 3 | NodePool 2/2, AllNodesHealthy | OK | ~9 minutes; 2/2, 4.20.0 |
| 4 | Guest kubeconfig, 2 nodes Ready | OK | ip-10-0-130-125, ip-10-0-134-84; RHCOS 9.6, v1.33.5, cri-o 1.33.4 |
| 5 | `check.sh guest` 7/7 (IDMS, user-ca-bundle, registries.conf digest-only, node anchor, node → mirror TLS) | OK | 7/7 on ip-10-0-130-125; `pull-from-mirror = "digest-only"` |
| 6 | Pod `virtual repo@digest`, `imagePullPolicy: Always` Running | OK | pulled in 807ms, 1/1 Running; imageID `…invalid/libpod/registry@sha256:da1fbcd1…` |
| 6 | Negative pod `virtual repo:tag` fails to pull (`.invalid` unresolvable) | OK | ErrImagePull: `lookup mirror-source.hypershift-e2e.invalid on 10.0.0.2:53: no such host` |
| 6 | Mirror log shows CRI-O manifest GETs → 200 for the virtual repo; no tag lookups | OK (note) | 4/4 lines (2 requests) via check.sh; raw tail shows blob GETs only; `cri-o/1.33.4`; 0 tag lookups |
| 6 | `check.sh pods` 5/5 | OK | 6/6 (script has 6 checks), 0 failure(s) |
| 7 | `Always` re-contacts the mirror with the image cached on the node | OK | before=4 after=8; Successfully pulled in 67ms |
| 8 | HC destroyed; no HC/NodePool/HCP ns; no VPC/instances for INFRA_ID | OK | ~6 min (16:05:57→16:12:04); all queries empty |
| 8 | `clusters` ns removed; `harness teardown`; ns `test-mirror-registry` NotFound | OK | only `user-ca-bundle` CM left, removed with ns; teardown 21s; NotFound |

## Problems found

| # | Step | Symptom | Root cause | Action |
|---|------|---------|------------|--------|
| 1 | 6 | Raw mirror-log excerpt (`tail -5`) shows only blob GETs; manifest GETs proven only by check.sh (4/4) and step 7 (4→8) | RUNBOOK greps all cri-o lines, so the tail ends on blobs | Kit: grep `/v2/$VIRTUAL_REPO/manifests/` in RUNBOOK step 6 (non-blocking) |
| 2 | 6 | VERIFY/RUNBOOK say `check.sh pods` 5 PASS; the script prints 6 | Doc count | Fix the count in VERIFY.md |

## Surprises / follow-ups (T9 PR description, CNTRLPLANE-3927/3928)

- `hypershift destroy cluster` leaves the `user-ca-bundle` ConfigMap (fixed name) in the HC namespace: for CNTRLPLANE-3929, check that cleanup removes it so a later HC does not inherit a stale CA.
- `imagePullPolicy: Always` re-fetches manifests from the mirror with the image cached (4→8): confirms the CNTRLPLANE-3928 note.
- Each registry request is logged twice (logfmt + access log): `4/4 lines` = 2 manifest requests (list + amd64 instance).
- The create CLI took ~26s (runbook said 3–6 min) and logs the HostedCluster with `"kind":""` (upstream quirk).

## Evidence

### Step 0 — preflight

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) source .work/cntrlplane-3926/reachability/env.sh
CTX=mgmt NS=test-mirror-registry HOST=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com
HC=clusters/mirror-reach BASE_DOMAIN=hypershift.example.com RELEASE=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64
REACH_OUT=~/hypershift/.work/cntrlplane-3926/reachability/out
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get ns "$NS"
Error from server (NotFound): namespaces "test-mirror-registry" not found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get hostedcluster -A
No resources found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) hs version
Client Version: openshift/hypershift: cce02430ccc1c322e0698bb36421ed003873edef. Latest supported OCP: 4.22.0
Server Version: e83d907270ba8545b371edfa7b69989da2903214
Server Supports OCP Versions: 4.21, 4.20, 4.19, 4.18, 4.17, 4.16, 4.15, 4.14
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) aws sts get-caller-identity --query Arn --output text
arn:aws:iam::123456789012:user/tester
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) aws route53 list-hosted-zones-by-name --dns-name "$BASE_DOMAIN" --max-items 1 \
  --query 'HostedZones[0].[Name,Config.PrivateZone]' --output text
hypershift.example.com.   False  
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) jq -e '.auths["quay.io"]' "$PULL_SECRET" >/dev/null && echo "pull secret has quay.io"
pull secret has quay.io
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) go build -o /dev/null ./.work/cntrlplane-3926/harness && echo "harness builds"
harness builds

```

### Step 1 — harness setup, verify.sh, ics.yaml, CA

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness setup -out "$RUN" 2>&1 | tee "$REACH_OUT/setup.log"
15:34:46 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
15:34:46 harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
15:34:46 harness: Setup started
{
  "Host": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com",
  "InternalHost": "mirror-registry.test-mirror-registry.svc:5000",
  "CABundlePEM": null,
  "ImageContentSources": [
    {
      "source": "mirror-source.hypershift-e2e.invalid/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      ]
    },
    {
      "source": "quay.io/libpod/registry",
      "mirrors": [
        "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"
      ]
    }
  ],
  "Images": [
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    },
    {
      "From": "quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "SourceRef": "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f",
      "MirrorRef": "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
    }
  ]
}
15:35:31 harness: setup finished in 46s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/verify.sh "$RUN"
PASS  anonymous /v2/ with CA → {} 200
PASS  TLS refused without CA (curl exit 60)
PASS  digest preserved quay.io/libpod/registry
PASS  digest preserved mirror-source.hypershift-e2e.invalid/libpod/registry
PASS  push via Route rejected (405)
verify: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) cat "$RUN/ics.yaml"
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
  source: mirror-source.hypershift-e2e.invalid/libpod/registry
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
  source: quay.io/libpod/registry
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) openssl x509 -in "$RUN/ca-only/ca.crt" -noout -subject -fingerprint -sha256
subject=OU=hypershift-e2e-mirror-registry, CN=hypershift-e2e-mirror-registry-ca
sha256 Fingerprint=AA:83:E6:32:65:AF:C0:8C:71:CF:1B:63:70:0A:23:DB:A3:DB:CB:8A:BC:A4:F3:E4:A1:69:29:F3:D6:81:1F:B9
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)

Terminal 2 logs:
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) source .work/cntrlplane-3926/reachability/env.sh
CTX=mgmt NS=test-mirror-registry HOST=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com
HC=clusters/mirror-reach BASE_DOMAIN=hypershift.example.com RELEASE=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64
REACH_OUT=~/hypershift/.work/cntrlplane-3926/reachability/out
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/harness/watch.sh "$REACH_OUT/watch-setup.log"
15:34:22 route=none readonly=- deploy=none pods=[] jobs=[]
15:34:49 route=none readonly=false deploy=gen1/obs1/avail0 pods=[v2qlh:Pending] jobs=[]
15:34:58 route=none readonly=false deploy=gen1/obs1/avail1 pods=[v2qlh:Running] jobs=[]
15:35:00 route=none readonly=false deploy=gen1/obs1/avail1 pods=[v2qlh:Running] jobs=[mirror-registry-copy-95da31410c:Running]
15:35:19 route=none readonly=false deploy=gen1/obs1/avail1 pods=[v2qlh:Running] jobs=[mirror-registry-copy-95da31410c:SuccessCriteriaMet,Complete]
15:35:21 route=none readonly=false deploy=gen1/obs1/avail1 pods=[v2qlh:Running(terminating)] jobs=[]
15:35:23 route=none readonly=true deploy=gen2/obs2/avail0 pods=[55b5m:Pending] jobs=[]
15:35:27 route=none readonly=true deploy=gen2/obs2/avail1 pods=[55b5m:Running] jobs=[]
15:35:33 route=admitted readonly=true deploy=gen2/obs2/avail1 pods=[55b5m:Running] jobs=[]
^C
```

### Step 2 — create log (tail), INFRA_ID, check.sh hc

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) hs create cluster aws \
  --name "$HC_NAME" --namespace "$HC_NS" \
  --base-domain "$BASE_DOMAIN" --region "$AWS_REGION" --zones "${AWS_REGION}a" \
  --aws-creds "$AWS_CREDS" --pull-secret "$PULL_SECRET" \
  --release-image "$RELEASE_IMAGE" \
  --node-pool-replicas 2 --generate-ssh \
  --additional-trust-bundle "$RUN/ca-only/ca.crt" \
  --image-content-sources "$RUN/ics.yaml" \
  2>&1 | tee "$REACH_OUT/create.log"
Flag --aws-creds has been deprecated, please use '--sts-creds' with '--role-arn' instead
{"level":"info","ts":"2026-10-14T15:37:46+02:00","msg":"Creating infrastructure","id":"mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T15:37:47+02:00","msg":"Created VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:47+02:00","msg":"Enabled DNS support on VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:48+02:00","msg":"Enabled DNS hostnames on VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:48+02:00","msg":"Created DHCP options","id":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:48+02:00","msg":"Associated DHCP options with VPC","vpc":"vpc-0000000000000000","dhcp options":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:49+02:00","msg":"Created internet gateway","id":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:49+02:00","msg":"Attached internet gateway to VPC","internet gateway":"igw-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:50+02:00","msg":"Created subnet","name":"mirror-reach-kn775-private-us-east-1a","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:51+02:00","msg":"Created subnet","name":"mirror-reach-kn775-public-us-east-1a","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:53+02:00","msg":"Created elastic IP for NAT gateway","id":"eipalloc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:54+02:00","msg":"Created NAT gateway","id":"nat-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:54+02:00","msg":"Created route table","name":"mirror-reach-kn775-private-us-east-1a","id":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:59+02:00","msg":"Created route to NAT gateway","route table":"rtb-0000000000000000","nat gateway":"nat-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:37:59+02:00","msg":"Associated subnet with route table","route table":"rtb-0000000000000000","subnet":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:00+02:00","msg":"Created route table","name":"mirror-reach-kn775-public","id":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:00+02:00","msg":"Set main VPC route table","route table":"rtb-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:00+02:00","msg":"Created route to internet gateway","route table":"rtb-0000000000000000","internet gateway":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:01+02:00","msg":"Associated route table with subnet","route table":"rtb-0000000000000000","subnet":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:02+02:00","msg":"Created s3 VPC endpoint","id":"vpce-0000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:03+02:00","msg":"Found existing public zone","name":"hypershift.example.com","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:04+02:00","msg":"Created private zone","name":"mirror-reach.hypershift.example.com","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:05+02:00","msg":"Created private zone","name":"mirror-reach.hypershift.local","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-14T15:38:05+02:00","msg":"Detected Issuer URL","issuer":"https://oidc-bucket.s3.us-east-1.amazonaws.com/mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T15:38:06+02:00","msg":"Created OIDC provider","provider":"arn:aws:iam::123456789012:oidc-provider/oidc-bucket.s3.us-east-1.amazonaws.com/mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T15:38:06+02:00","msg":"Created role","name":"mirror-reach-kn775-cloud-controller"}
{"level":"info","ts":"2026-10-14T15:38:07+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-cloud-controller"}
{"level":"info","ts":"2026-10-14T15:38:07+02:00","msg":"Created role","name":"mirror-reach-kn775-node-pool"}
{"level":"info","ts":"2026-10-14T15:38:07+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-node-pool"}
{"level":"info","ts":"2026-10-14T15:38:08+02:00","msg":"Created role","name":"mirror-reach-kn775-control-plane-operator"}
{"level":"info","ts":"2026-10-14T15:38:08+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-control-plane-operator"}
{"level":"info","ts":"2026-10-14T15:38:08+02:00","msg":"Created role","name":"mirror-reach-kn775-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-14T15:38:08+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-14T15:38:09+02:00","msg":"Created role","name":"mirror-reach-kn775-openshift-ingress"}
{"level":"info","ts":"2026-10-14T15:38:09+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-openshift-ingress"}
{"level":"info","ts":"2026-10-14T15:38:09+02:00","msg":"Created role","name":"mirror-reach-kn775-openshift-image-registry"}
{"level":"info","ts":"2026-10-14T15:38:09+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-openshift-image-registry"}
{"level":"info","ts":"2026-10-14T15:38:10+02:00","msg":"Created role","name":"mirror-reach-kn775-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-14T15:38:10+02:00","msg":"Added/Updated role policy","name":"mirror-reach-kn775-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-14T15:38:10+02:00","msg":"Created role","name":"mirror-reach-kn775-worker-role"}
{"level":"info","ts":"2026-10-14T15:38:10+02:00","msg":"Created instance profile","name":"mirror-reach-kn775-worker"}
{"level":"info","ts":"2026-10-14T15:38:11+02:00","msg":"Added role to instance profile","role":"mirror-reach-kn775-worker-role","profile":"mirror-reach-kn775-worker"}
{"level":"info","ts":"2026-10-14T15:38:11+02:00","msg":"Created role policy","name":"mirror-reach-kn775-worker-policy"}
{"level":"info","ts":"2026-10-14T15:38:11+02:00","msg":"Created IAM profile","name":"mirror-reach-kn775-worker","region":"us-east-1"}
{"level":"info","ts":"2026-10-14T15:38:11+02:00","msg":"Applied Kube resource","kind":"Namespace","namespace":"","name":"clusters"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"ConfigMap","namespace":"clusters","name":"user-ca-bundle"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"mirror-reach-pull-secret"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"mirror-reach-ssh-key"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"mirror-reach-etcd-encryption-key"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T15:38:12+02:00","msg":"Applied Kube resource","kind":"NodePool","namespace":"clusters","name":"mirror-reach-us-east-1a"}
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) export INFRA_ID="$(k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.infraID}')"; echo "INFRA_ID=$INFRA_ID"
INFRA_ID=mirror-reach-kn775
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) echo "export INFRA_ID=$INFRA_ID" > "$REACH_OUT/infra-id.sh"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/reachability/check.sh hc
PASS  spec.additionalTrustBundle set
PASS  trust bundle ConfigMap user-ca-bundle == mirror CA
PASS  spec.imageContentSources == harness ICS
check hc: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.additionalTrustBundle}{"\n"}{.spec.imageContentSources}{"\n"}'
{"name":"user-ca-bundle"}
[{"mirrors":["mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"],"source":"mirror-source.hypershift-e2e.invalid/libpod/registry"},{"mirrors":["mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"],"source":"quay.io/libpod/registry"}]
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 3 — HC / NodePool status

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" wait hostedcluster/"$HC_NAME" --for=condition=Available --timeout=30m
hostedcluster.hypershift.openshift.io/mirror-reach condition met
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get hostedcluster,nodepool
NAME                                                 VERSION   KUBECONFIG                      PROGRESS   AVAILABLE   PROGRESSING   MESSAGE
hostedcluster.hypershift.openshift.io/mirror-reach             mirror-reach-admin-kubeconfig   Partial    True        False         The hosted control plane is available

NAME                                                       CLUSTER        DESIRED NODES   CURRENT NODES   AUTOSCALING   AUTOREPAIR   VERSION   UPDATINGVERSION   UPDATINGCONFIG   MESSAGE
nodepool.hypershift.openshift.io/mirror-reach-us-east-1a   mirror-reach   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" wait nodepool/"${HC_NAME}-${AWS_REGION}a" --for=condition=AllNodesHealthy --timeout=40m
nodepool.hypershift.openshift.io/mirror-reach-us-east-1a condition met
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get hostedcluster,nodepool
NAME                                                 VERSION   KUBECONFIG                      PROGRESS   AVAILABLE   PROGRESSING   MESSAGE
hostedcluster.hypershift.openshift.io/mirror-reach             mirror-reach-admin-kubeconfig   Partial    True        False         The hosted control plane is available

NAME                                                       CLUSTER        DESIRED NODES   CURRENT NODES   AUTOSCALING   AUTOREPAIR   VERSION   UPDATINGVERSION   UPDATINGCONFIG   MESSAGE
nodepool.hypershift.openshift.io/mirror-reach-us-east-1a   mirror-reach   2               2               False         False        4.20.0    False             False
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 4 — nodes, clusterversion

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get secret "${HC_NAME}-admin-kubeconfig" -o jsonpath='{.data.kubeconfig}' | base64 -d > "$GUEST_KUBECONFIG"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) chmod 600 "$GUEST_KUBECONFIG"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest get nodes -o wide
NAME                           STATUS   ROLES    AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                                                KERNEL-VERSION                 CONTAINER-RUNTIME
ip-10-0-130-125.ec2.internal   Ready    worker   4m21s   v1.33.5   10.0.130.125   <none>        Red Hat Enterprise Linux CoreOS 9.6.20250925-0 (Plow)   5.14.0-570.49.1.el9_6.x86_64   cri-o://1.33.4-4.rhaos4.20.gitc8e7df2.el9
ip-10-0-134-84.ec2.internal    Ready    worker   4m29s   v1.33.5   10.0.134.84    <none>        Red Hat Enterprise Linux CoreOS 9.6.20250925-0 (Plow)   5.14.0-570.49.1.el9_6.x86_64   cri-o://1.33.4-4.rhaos4.20.gitc8e7df2.el9
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version             False       True          7m38s   Unable to apply 4.20.0: the cluster operator monitoring is not available
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 5 — check.sh guest, IDMS spec, registries.conf excerpt

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/reachability/check.sh guest
PASS  guest IDMS cluster: mirror-source.hypershift-e2e.invalid/libpod/registry → mirror
PASS  guest IDMS cluster: quay.io/libpod/registry → mirror
PASS  guest openshift-config/user-ca-bundle == mirror CA
INFO  node under test: ip-10-0-130-125.ec2.internal
PASS  node registries.conf maps mirror-source.hypershift-e2e.invalid/libpod/registry → mirror
PASS  node registries.conf mirror is digest-only
PASS  node trust anchor == mirror CA
PASS  node → https://mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/v2/ with system trust → {} 200
check guest: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest get imagedigestmirrorset cluster -o yaml | yq '.spec'
imageDigestMirrors:
  - mirrors:
      - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
    source: mirror-source.hypershift-e2e.invalid/libpod/registry
  - mirrors:
      - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
    source: quay.io/libpod/registry
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) NODE="$(guest get nodes -o jsonpath='{.items[0].metadata.name}')"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest debug -q "node/$NODE" -- chroot /host sh -c 'grep -B2 -A4 "hypershift-e2e.invalid" /etc/containers/registries.conf' 2>/dev/null
[[registry]]
  prefix = ""
  location = "mirror-source.hypershift-e2e.invalid/libpod/registry"

  [[registry.mirror]]
    location = "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
    pull-from-mirror = "digest-only"

[[registry]]
  prefix = ""
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 6 — pods, events, logs, imageID, check.sh pods, mirror log lines

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest create ns "$GUEST_NS"
namespace/mirror-reach-check created
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) pod "$POD_DIGEST" "${VIRTUAL_REPO}@${TEST_DIGEST}" | guest apply -f -
pod/mirror-by-digest created
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" wait pod/"$POD_DIGEST" --for=condition=Ready --timeout=5m
pod/mirror-by-digest condition met
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) pod "$POD_TAG" "${VIRTUAL_REPO}:2.8.2" | guest apply -f -
pod/mirror-by-tag created
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) sleep 60
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" get pods -o wide
NAME               READY   STATUS         RESTARTS   AGE   IP            NODE                           NOMINATED NODE   READINESS GATES
mirror-by-digest   1/1     Running        0          87s   10.133.0.25   ip-10-0-130-125.ec2.internal   <none>           <none>
mirror-by-tag      0/1     ErrImagePull   0          68s   10.133.0.26   ip-10-0-130-125.ec2.internal   <none>           <none>
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" get events --sort-by=.lastTimestamp | grep -E 'Pulling|Pulled|Failed|BackOff'
95s         Normal    Pulling          pod/mirror-by-digest   Pulling image "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
94s         Normal    Pulled           pod/mirror-by-digest   Successfully pulled image "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f" in 807ms (807ms including waiting). Image size: 24613466 bytes.
35s         Normal    Pulling          pod/mirror-by-tag      Pulling image "mirror-source.hypershift-e2e.invalid/libpod/registry:2.8.2"
35s         Warning   Failed           pod/mirror-by-tag      Failed to pull image "mirror-source.hypershift-e2e.invalid/libpod/registry:2.8.2": unable to pull image or OCI artifact: pull image err: initializing source docker://mirror-source.hypershift-e2e.invalid/libpod/registry:2.8.2: pinging container registry mirror-source.hypershift-e2e.invalid: Get "https://mirror-source.hypershift-e2e.invalid/v2/": dial tcp: lookup mirror-source.hypershift-e2e.invalid on 10.0.0.2:53: no such host; artifact err: get manifest: build image source: pinging container registry mirror-source.hypershift-e2e.invalid: Get "https://mirror-source.hypershift-e2e.invalid/v2/": dial tcp: lookup mirror-source.hypershift-e2e.invalid on 10.0.0.2:53: no such host
35s         Warning   Failed           pod/mirror-by-tag      Error: ErrImagePull
7s          Normal    BackOff          pod/mirror-by-tag      Back-off pulling image "mirror-source.hypershift-e2e.invalid/libpod/registry:2.8.2"
7s          Warning   Failed           pod/mirror-by-tag      Error: ImagePullBackOff
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" logs "$POD_DIGEST" | head -5
time="2026-10-14T13:56:53.875036901Z" level=warning msg="No HTTP secret provided - generated random secret. This may cause problems with uploads if multiple registries are behind a load-balancer. To provide a shared secret, fill in http.secret in the configuration file or set the REGISTRY_HTTP_SECRET environment variable." go.version=go1.19.9 instance.id=10607cec-3f7b-4198-b66a-18e8bff90c16 service=registry version=2.8.2
time="2026-10-14T13:56:53.875097376Z" level=info msg="redis not configured" go.version=go1.19.9 instance.id=10607cec-3f7b-4198-b66a-18e8bff90c16 service=registry version=2.8.2
time="2026-10-14T13:56:53.875216686Z" level=info msg="using inmemory blob descriptor cache" go.version=go1.19.9 instance.id=10607cec-3f7b-4198-b66a-18e8bff90c16 service=registry version=2.8.2
time="2026-10-14T13:56:53.875310111Z" level=info msg="Starting upload purge in 29m0s" go.version=go1.19.9 instance.id=10607cec-3f7b-4198-b66a-18e8bff90c16 service=registry version=2.8.2
time="2026-10-14T13:56:53.875600019Z" level=info msg="listening on [::]:5000" go.version=go1.19.9 instance.id=10607cec-3f7b-4198-b66a-18e8bff90c16 service=registry version=2.8.2
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" get pod "$POD_DIGEST" -o jsonpath='{.spec.nodeName}{"  "}{.status.containerStatuses[0].imageID}{"\n"}'
ip-10-0-130-125.ec2.internal  mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) .work/cntrlplane-3926/reachability/check.sh pods
PASS  pod mirror-by-digest (virtual repo @digest) Ready
PASS  pod mirror-by-digest image/pullPolicy
PASS  event Pulled 'Successfully pulled' for mirror-by-digest
PASS  pod mirror-by-tag (virtual repo :tag) fails to pull
PASS  mirror log: CRI-O GET mirror-source.hypershift-e2e.invalid/libpod/registry manifests → 200 (4/4 lines)
PASS  mirror log: no tag lookups (digest-only)
check pods: 0 failure(s)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -F "$VIRTUAL_REPO" | tail -5
10.132.0.15 - - [14/Oct/2026:13:56:53 +0000] "GET /v2/mirror-source.hypershift-e2e.invalid/libpod/registry/blobs/sha256:121f958bea53668d782691e643e9401ea21dd36c9d81078b51964d2e82b51376 HTTP/1.1" 200 399 "" "cri-o/1.33.4 os/linux arch/amd64"
time="2026-10-14T13:56:53.061295114Z" level=info msg="response completed" go.version=go1.19.9 http.request.host=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com http.request.id=22e02872-7575-4220-a29c-da34b1f54000 http.request.method=GET http.request.remoteaddr="10.132.0.15:35742" http.request.uri="/v2/mirror-source.hypershift-e2e.invalid/libpod/registry/blobs/sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e" http.request.useragent="cri-o/1.33.4 os/linux arch/amd64" http.response.contenttype="application/octet-stream" http.response.duration=15.334673ms http.response.status=200 http.response.written=284693
10.132.0.15 - - [14/Oct/2026:13:56:53 +0000] "GET /v2/mirror-source.hypershift-e2e.invalid/libpod/registry/blobs/sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e HTTP/1.1" 200 284693 "" "cri-o/1.33.4 os/linux arch/amd64"
time="2026-10-14T13:56:53.072867568Z" level=info msg="response completed" go.version=go1.19.9 http.request.host=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com http.request.id=1641ec1f-1805-4e24-83b1-707f568fdc57 http.request.method=GET http.request.remoteaddr="10.132.0.15:35744" http.request.uri="/v2/mirror-source.hypershift-e2e.invalid/libpod/registry/blobs/sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a" http.request.useragent="cri-o/1.33.4 os/linux arch/amd64" http.response.contenttype="application/octet-stream" http.response.duration=33.825875ms http.response.status=200 http.response.written=5908098
10.132.0.15 - - [14/Oct/2026:13:56:53 +0000] "GET /v2/mirror-source.hypershift-e2e.invalid/libpod/registry/blobs/sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a HTTP/1.1" 200 5908098 "" "cri-o/1.33.4 os/linux arch/amd64"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 7 — re-pull counts and events

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) NODE="$(guest -n "$GUEST_NS" get pod "$POD_DIGEST" -o jsonpath='{.spec.nodeName}')"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) before="$(k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -cF "/v2/$VIRTUAL_REPO/manifests/")"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" delete pod "$POD_DIGEST" --wait
pod "mirror-by-digest" deleted from mirror-reach-check namespace
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) pod "$POD_DIGEST" "${VIRTUAL_REPO}@${TEST_DIGEST}" | NODE="$NODE" yq '.spec.nodeName = strenv(NODE)' | guest apply -f -
pod/mirror-by-digest created
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" wait pod/"$POD_DIGEST" --for=condition=Ready --timeout=5m
pod/mirror-by-digest condition met
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) after="$(k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -cF "/v2/$VIRTUAL_REPO/manifests/")"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) echo "manifest requests: before=$before after=$after"
manifest requests: before=4 after=8
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest -n "$GUEST_NS" get events --field-selector involvedObject.name="$POD_DIGEST" --sort-by=.lastTimestamp | tail -3
22s         Normal   Pulled           pod/mirror-by-digest   Successfully pulled image "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f" in 67ms (67ms including waiting). Image size: 24613466 bytes.
22s         Normal   Created          pod/mirror-by-digest   Created container: registry
22s         Normal   Started          pod/mirror-by-digest   Started container registry
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

### Step 8 — destroy log (tail), leftover checks, teardown

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) echo "INFRA_ID=$INFRA_ID"
INFRA_ID=mirror-reach-kn775
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) guest delete ns "$GUEST_NS" --wait=false 2>/dev/null
namespace "mirror-reach-check" deleted
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) hs destroy cluster aws --name "$HC_NAME" --namespace "$HC_NS" \
  --aws-creds "$AWS_CREDS" --region "$AWS_REGION" 2>&1 | tee "$REACH_OUT/destroy.log"
Flag --aws-creds has been deprecated, please use '--sts-creds' with '--role-arn' instead
{"level":"info","ts":"2026-10-14T16:05:57+02:00","msg":"Found hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:05:57+02:00","msg":"Setting client finalizer for hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:05:57+02:00","msg":"Marking cleanup of cloud resources for hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:05:57+02:00","msg":"Updated hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:05:57+02:00","msg":"Deleting hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:10:46+02:00","msg":"Destroying infrastructure","infraID":"mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T16:10:53+02:00","msg":"Revoked security group ingress permissions","group":"sg-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:53+02:00","msg":"Revoked security group egress permissions","group":"sg-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:54+02:00","msg":"Deleted VPC endpoints","IDs":"vpce-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:54+02:00","msg":"Deleted private hosted zone","id":"Z00000000000000000000","name":"mirror-reach.hypershift.example.com."}
{"level":"info","ts":"2026-10-14T16:10:55+02:00","msg":"Deleted private hosted zone","id":"Z00000000000000000000","name":"mirror-reach.hypershift.local."}
{"level":"info","ts":"2026-10-14T16:10:55+02:00","msg":"Deleted route from route table","table":"rtb-0000000000000000","destination":"0.0.0.0/0"}
{"level":"info","ts":"2026-10-14T16:10:55+02:00","msg":"Removed route table association","table":"rtb-0000000000000000","association":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:56+02:00","msg":"Deleted route from route table","table":"rtb-0000000000000000","destination":"0.0.0.0/0"}
{"level":"info","ts":"2026-10-14T16:10:56+02:00","msg":"Removed route table association","table":"rtb-0000000000000000","association":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:56+02:00","msg":"Deleted route table","table":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:57+02:00","msg":"Deleted route table","table":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:10:57+02:00","msg":"WARNING: error during destroy, will retry","error":"deleting NAT gateway nat-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:04+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:11+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:17+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:24+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:30+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:36+02:00","msg":"WARNING: error during destroy, will retry","error":"NAT gateway nat-0000000000000000 still deleting"}
{"level":"info","ts":"2026-10-14T16:11:44+02:00","msg":"Deleted subnet","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:45+02:00","msg":"Deleted subnet","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:45+02:00","msg":"WARNING: error during destroy, will retry","error":"failed to delete vpc with id vpc-0000000000000000: DependencyViolation: The vpc 'vpc-0000000000000000' has dependencies and cannot be deleted.\n\tstatus code: 400, request id: 37c8e181-bf0a-4f1a-bff3-5fe2f2530d53"}
{"level":"info","ts":"2026-10-14T16:11:46+02:00","msg":"Detached internet gateway from VPC","gateway id":"igw-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:47+02:00","msg":"Deleted internet gateway","id":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:53+02:00","msg":"Deleted VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:54+02:00","msg":"Deleted EIP","id":"eipalloc-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:55+02:00","msg":"Deleted DHCP options","id":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-14T16:11:55+02:00","msg":"Destroying IAM","infraID":"mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T16:11:55+02:00","msg":"Deleted OIDC provider","providerARN":"arn:aws:iam::123456789012:oidc-provider/oidc-bucket.s3.us-east-1.amazonaws.com/mirror-reach-kn775"}
{"level":"info","ts":"2026-10-14T16:11:55+02:00","msg":"Role already deleted!","role":"mirror-reach-kn775-shared-role"}
{"level":"info","ts":"2026-10-14T16:11:56+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-openshift-ingress","policy":"mirror-reach-kn775-openshift-ingress"}
{"level":"info","ts":"2026-10-14T16:11:56+02:00","msg":"Deleted role","role":"mirror-reach-kn775-openshift-ingress"}
{"level":"info","ts":"2026-10-14T16:11:57+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-openshift-image-registry","policy":"mirror-reach-kn775-openshift-image-registry"}
{"level":"info","ts":"2026-10-14T16:11:57+02:00","msg":"Deleted role","role":"mirror-reach-kn775-openshift-image-registry"}
{"level":"info","ts":"2026-10-14T16:11:58+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-aws-ebs-csi-driver-controller","policy":"mirror-reach-kn775-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-14T16:11:58+02:00","msg":"Deleted role","role":"mirror-reach-kn775-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-14T16:11:59+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-cloud-controller","policy":"mirror-reach-kn775-cloud-controller"}
{"level":"info","ts":"2026-10-14T16:11:59+02:00","msg":"Deleted role","role":"mirror-reach-kn775-cloud-controller"}
{"level":"info","ts":"2026-10-14T16:12:00+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-node-pool","policy":"mirror-reach-kn775-node-pool"}
{"level":"info","ts":"2026-10-14T16:12:00+02:00","msg":"Deleted role","role":"mirror-reach-kn775-node-pool"}
{"level":"info","ts":"2026-10-14T16:12:00+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-control-plane-operator","policy":"mirror-reach-kn775-control-plane-operator"}
{"level":"info","ts":"2026-10-14T16:12:01+02:00","msg":"Deleted role","role":"mirror-reach-kn775-control-plane-operator"}
{"level":"info","ts":"2026-10-14T16:12:01+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-cloud-network-config-controller","policy":"mirror-reach-kn775-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-14T16:12:01+02:00","msg":"Deleted role","role":"mirror-reach-kn775-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-14T16:12:02+02:00","msg":"Role already deleted!","role":"mirror-reach-kn775-kms-provider"}
{"level":"info","ts":"2026-10-14T16:12:02+02:00","msg":"Role already deleted!","role":"mirror-reach-kn775-karpenter"}
{"level":"info","ts":"2026-10-14T16:12:02+02:00","msg":"Removed role from instance profile","profile":"mirror-reach-kn775-worker","role":"mirror-reach-kn775-worker-role"}
{"level":"info","ts":"2026-10-14T16:12:02+02:00","msg":"Deleted instance profile","profile":"mirror-reach-kn775-worker"}
{"level":"info","ts":"2026-10-14T16:12:03+02:00","msg":"Deleted role policy","role":"mirror-reach-kn775-worker-role","policy":"mirror-reach-kn775-worker-policy"}
{"level":"info","ts":"2026-10-14T16:12:03+02:00","msg":"Deleted role","role":"mirror-reach-kn775-worker-role"}
{"level":"info","ts":"2026-10-14T16:12:03+02:00","msg":"Deleting Secrets","namespace":"clusters"}
{"level":"info","ts":"2026-10-14T16:12:03+02:00","msg":"Deleted CLI generated secrets"}
{"level":"info","ts":"2026-10-14T16:12:04+02:00","msg":"Finalized hosted cluster","namespace":"clusters","name":"mirror-reach"}
{"level":"info","ts":"2026-10-14T16:12:04+02:00","msg":"Successfully destroyed cluster and infrastructure","namespace":"clusters","name":"mirror-reach","infraID":"mirror-reach-kn775"}
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get hostedcluster,nodepool
No resources found in clusters namespace.
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get ns "$HCP_NS"
Error from server (NotFound): namespaces "clusters-mirror-reach" not found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
  --query 'Vpcs[].VpcId' --output text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k -n "$HC_NS" get secret,cm
NAME                              TYPE                      DATA   AGE
secret/builder-dockercfg-7dnkv    kubernetes.io/dockercfg   1      35m
secret/default-dockercfg-sljps    kubernetes.io/dockercfg   1      35m
secret/deployer-dockercfg-ggbwv   kubernetes.io/dockercfg   1      35m

NAME                                 DATA   AGE
configmap/kube-root-ca.crt           1      35m
configmap/openshift-service-ca.crt   1      35m
configmap/user-ca-bundle             1      35m
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k delete ns "$HC_NS"
namespace "clusters" deleted
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) harness teardown 2>&1 | tee "$REACH_OUT/teardown.log"
16:14:17 harness: context mgmt → https://api.mgmt.hypershift.example.com:6443
16:14:38 harness: teardown finished in 21s
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) k get ns "$NS"
Error from server (NotFound): namespaces "test-mirror-registry" not found
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926)
```

