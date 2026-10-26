# T8 — Hosted-node reachability runbook (mgmt)

Goal (3926 acceptance criterion): prove that nodes of a hosted cluster created with the fixture's outputs
(`--additional-trust-bundle`, `--image-content-sources`) pull from the mirror over verified TLS, anonymously.
Evidence that cannot come from anywhere else: a pod referencing the **virtual** repository
`mirror-source.hypershift-e2e.invalid/libpod/registry@<digest>` with `imagePullPolicy: Always` starts
(`.invalid` never resolves, so only the mirror can answer), and the mirror's own log shows the CRI-O requests.

Fill `RESULTS.md` as you go (each step has a **Record** line) and paste command output under the matching
**Evidence** heading. This is a manual proof: no code changes expected. If something fails, capture the
"On failure" commands of the step **before** destroying anything.

Scope and safety:
- Management-cluster changes only on `mgmt`: namespace `test-mirror-registry` (fixture) and the new
  HostedCluster `clusters/mirror-reach` (+ its `clusters-mirror-reach` control-plane namespace). Parent cluster untouched.
- The `hypershift` CLI gets `out/mc.kubeconfig`, which contains **only** the `mgmt` context (`hs` wrapper).
- AWS: the CLI creates VPC/NAT/IAM/Route53 for `mirror-reach` (account of `~/.aws/credentials`); step 8 removes them.
- `out/` holds kubeconfigs, the CA (and `harness/out` the CA keys of T6). Local only, never paste them.
- Time: ~1.5 h, mostly waiting (HC + nodes ~25–35 min, destroy ~10–15 min). Cost: 2 × default worker + NAT for that time.

Tools: `harness` (T6), `hs` (= `hypershift` with `mc.kubeconfig`), `guest` (= `oc` on the hosted cluster),
`k` (= `oc --context mgmt`), `pod <name> <image>` (renders `manifests/pod.yaml`), `check.sh <phase>`
(PASS/FAIL lines). Run everything from the repository root.

---

## 0. Environment and preflight

```bash
source .work/cntrlplane-3926/reachability/env.sh
k get ns "$NS"                                   # expected: NotFound (T6 tore it down)
k get hostedcluster -A                           # expected: No resources found
hs version                                       # expected: Client cce02430…, Server e83d9072…, supported up to 4.21
aws sts get-caller-identity --query Arn --output text                      # expected: arn:aws:iam::123456789012:user/tester
aws route53 list-hosted-zones-by-name --dns-name "$BASE_DOMAIN" --max-items 1 \
  --query 'HostedZones[0].[Name,Config.PrivateZone]' --output text           # expected: hypershift.example.com.  False
jq -e '.auths["quay.io"]' "$PULL_SECRET" >/dev/null && echo "pull secret has quay.io"
go build -o /dev/null ./.work/cntrlplane-3926/harness && echo "harness builds"
```
Expected: as commented; `env.sh` prints `HC=clusters/mirror-reach …` and `HOST=mirror-registry-test-mirror-registry.apps.mgmt…`.
If `k` fails with `TLS handshake timeout` (seen on 2026/10/14), just retry: the mgmt API is occasionally slow.

**Record:** versions, anything unexpected.

## 1. Fresh mirror (fixture Setup)

Terminal 2 (optional, same as T6; needs `source .work/cntrlplane-3926/reachability/env.sh` there too):
`.work/cntrlplane-3926/harness/watch.sh "$REACH_OUT/watch-setup.log"` — **stop it with Ctrl-C as soon as `harness setup`
exits**; it is not used after step 1 (its log is step 1 evidence).

Terminal 1:
```bash
harness setup -out "$RUN" 2>&1 | tee "$REACH_OUT/setup.log"
.work/cntrlplane-3926/harness/verify.sh "$RUN"
cat "$RUN/ics.yaml"
openssl x509 -in "$RUN/ca-only/ca.crt" -noout -subject -fingerprint -sha256
```
Expected:
- exit 0 in ~1 min, `copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:…`, `result.json` printed
  (same shape as T6 step 1); no `VIOLATION` in the watcher;
- `verify: 0 failure(s)` (5 PASS);
- `ics.yaml` has exactly two entries, in this order:
  ```yaml
  - mirrors:
    - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
    source: mirror-source.hypershift-e2e.invalid/libpod/registry
  - mirrors:
    - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
    source: quay.io/libpod/registry
  ```
- CA subject `CN=hypershift-e2e-mirror-registry-ca` (a **new** CA: the namespace and its `-ca` Secret were deleted in T6).

**Record:** Setup duration, verify result, CA fingerprint (it is compared in later checks).

> Leave the mirror running until step 8. Do **not** re-run `harness setup` with a different CA while the HC
> exists: nodes trust only the CA they were created with (changing it later means a NodePool rollout).

## 2. Create the hosted cluster with the fixture outputs

```bash
hs create cluster aws \
  --name "$HC_NAME" --namespace "$HC_NS" \
  --base-domain "$BASE_DOMAIN" --region "$AWS_REGION" --zones "${AWS_REGION}a" \
  --aws-creds "$AWS_CREDS" --pull-secret "$PULL_SECRET" \
  --release-image "$RELEASE_IMAGE" \
  --node-pool-replicas 2 --generate-ssh \
  --additional-trust-bundle "$RUN/ca-only/ca.crt" \
  --image-content-sources "$RUN/ics.yaml" \
  2>&1 | tee "$REACH_OUT/create.log"
export INFRA_ID="$(k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.infraID}')"; echo "INFRA_ID=$INFRA_ID"
echo "export INFRA_ID=$INFRA_ID" > "$REACH_OUT/infra-id.sh"     # re-source it in a new shell before step 8
.work/cntrlplane-3926/reachability/check.sh hc
k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.additionalTrustBundle}{"\n"}{.spec.imageContentSources}{"\n"}'
```
Expected:
- `--aws-creds` is deprecated/hidden but works (used for `an earlier cluster` on 2026/10/09). The CLI logs VPC/subnet/
  NAT/Route53/IAM/OIDC creation, then `Applied Kube resource` for Namespace `clusters`, the pull-secret Secret,
  ConfigMap `clusters/user-ca-bundle` (key `ca-bundle.crt`), HostedCluster and NodePool `mirror-reach-us-east-1a`; exit 0 in ~3–6 min;
- `INFRA_ID=mirror-reach-xxxxx`;
- `check.sh hc`: 3 PASS (`spec.additionalTrustBundle set`, ConfigMap CA == mirror CA, `spec.imageContentSources == harness ICS`),
  `check hc: 0 failure(s)`.

On failure: keep `create.log`; if infra was created but the HC was not applied, still run step 8 (destroy cleans by infra ID).

**Record:** duration, INFRA_ID, check output.

## 3. Wait for the control plane and the nodes

```bash
k -n "$HC_NS" wait hostedcluster/"$HC_NAME" --for=condition=Available --timeout=30m
k -n "$HC_NS" get hostedcluster,nodepool
k -n "$HC_NS" wait nodepool/"${HC_NAME}-${AWS_REGION}a" --for=condition=AllNodesHealthy --timeout=40m
```
Expected: HC `Available=True` after ~10–15 min (`PROGRESS` may stay `Partial` until the guest operators settle; not
needed here); NodePool `2/2` (`CURRENT NODES 2`), `AllNodesHealthy=True` after another ~10–15 min.
The control plane must reach Available without problems: our ICS entries only cover `quay.io/libpod/registry` and the
virtual repo, so release-image lookups are not affected.

On failure (before step 8):
```bash
k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
k -n "$HC_NS" get nodepool -o jsonpath='{range .items[0].status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
k -n "$HCP_NS" get pods | grep -v -E 'Running|Completed'
k -n "$HCP_NS" get machines.cluster.x-k8s.io,awsmachines
```
**Record:** times to Available / nodes ready, any non-True condition worth noting.

## 4. Hosted-cluster access

```bash
k -n "$HC_NS" get secret "${HC_NAME}-admin-kubeconfig" -o jsonpath='{.data.kubeconfig}' | base64 -d > "$GUEST_KUBECONFIG"
chmod 600 "$GUEST_KUBECONFIG"
guest get nodes -o wide
guest get clusterversion
```
Expected: 2 nodes `Ready`, `ROLES worker`, RHCOS 9.6 / kubelet v1.33 / cri-o 1.33 (OCP 4.20). ClusterVersion may still show an
empty `VERSION`, `AVAILABLE False`, `PROGRESSING True`, e.g. `Unable to apply 4.20.0: the cluster operator monitoring is not available`
for the first ~10–20 min after the nodes join: fine, steps 5–6 do not depend on it (seen on the 2026/10/14 run).

**Record:** node names.

## 5. Configuration reached the hosted cluster and its nodes

```bash
.work/cntrlplane-3926/reachability/check.sh guest
guest get imagedigestmirrorset cluster -o yaml | yq '.spec'
NODE="$(guest get nodes -o jsonpath='{.items[0].metadata.name}')"
guest debug -q "node/$NODE" -- chroot /host sh -c 'grep -B2 -A4 "hypershift-e2e.invalid" /etc/containers/registries.conf' 2>/dev/null
```
Expected:
- `check.sh guest`: 7 PASS — IDMS `cluster` maps both repos to `$HOST/<repo>`; `openshift-config/user-ca-bundle` == mirror CA;
  node `/etc/containers/registries.conf` maps the virtual repo to the mirror, digest-only;
  node anchor `/etc/pki/ca-trust/source/anchors/openshift-config-user-ca-bundle.crt` == mirror CA;
  `curl https://$HOST/v2/` **from the node, without `--cacert`** → `{} 200` (node reaches the Route and trusts our CA at OS level);
- IDMS spec: two `imageDigestMirrors` entries (`source` + one `mirrors` item each, no `mirrorSourcePolicy` → fallback allowed);
- `registries.conf` excerpt similar to:
  ```toml
  [[registry]]
    prefix = ""
    location = "mirror-source.hypershift-e2e.invalid/libpod/registry"

    [[registry.mirror]]
      location = "mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"
      pull-from-mirror = "digest-only"
  ```
`oc debug node` pulls the tools image from the release payload: the first call takes ~30 s.
If `check.sh guest` fails only on the node checks right after step 4, wait a few minutes (HCCO/MCO reconciliation) and re-run.

**Record:** check output, registries.conf excerpt.

## 6. The proof: pod from the virtual repository by digest, and a negative control

```bash
guest create ns "$GUEST_NS"
pod "$POD_DIGEST" "${VIRTUAL_REPO}@${TEST_DIGEST}" | guest apply -f -
guest -n "$GUEST_NS" wait pod/"$POD_DIGEST" --for=condition=Ready --timeout=5m
pod "$POD_TAG" "${VIRTUAL_REPO}:2.8.2" | guest apply -f -
sleep 60
guest -n "$GUEST_NS" get pods -o wide
guest -n "$GUEST_NS" get events --sort-by=.lastTimestamp | grep -E 'Pulling|Pulled|Failed|BackOff'
guest -n "$GUEST_NS" logs "$POD_DIGEST" | head -5
guest -n "$GUEST_NS" get pod "$POD_DIGEST" -o jsonpath='{.spec.nodeName}{"  "}{.status.containerStatuses[0].imageID}{"\n"}'
.work/cntrlplane-3926/reachability/check.sh pods
k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -F "$VIRTUAL_REPO" | tail -5
```
Expected:
- PSA may print a `Warning: would violate PodSecurity` line only if the manifest were non-compliant — it is compliant, so none;
- `mirror-by-digest` `Running` `1/1` within ~1 min; events `Pulling image "mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:e642e860…"`
  then `Successfully pulled image … in <n>s`; logs contain `listening on [::]:5000`;
- `mirror-by-tag` `ErrImagePull`/`ImagePullBackOff`; its `Failed` event says the virtual registry cannot be resolved
  (`… lookup mirror-source.hypershift-e2e.invalid … no such host` or similar). This proves the source does not exist, so the
  digest pod could only have been served by the mirror (and that the mirror is used for digests only);
- `imageID` references `mirror-source.hypershift-e2e.invalid/libpod/registry@sha256:…` (the digest may be the amd64
  instance digest instead of the manifest-list `e642e860…`; both are fine);
- `check.sh pods`: 5 PASS (Ready; image + `Always`; `Successfully pulled`; tag pod fails; mirror log has CRI-O
  `GET /v2/mirror-source.hypershift-e2e.invalid/libpod/registry/manifests/sha256:…` → 200; no tag lookups), `0 failure(s)`;
- mirror log lines: `http.request.method=GET`, `http.request.uri="/v2/mirror-source.hypershift-e2e.invalid/libpod/registry/manifests/sha256:…"`,
  `http.request.useragent="cri-o/1.33… "`, `http.response.status=200` (the remote address is the router pod: passthrough
  Routes do not forward the client IP).

**Record:** time to Running, events, imageID, check output, 2–3 mirror log lines.

## 7. (Quick, recommended) `imagePullPolicy: Always` hits the mirror again with a cached image

The node now has the image. Recreate the pod on the **same node** and check that the mirror gets a new manifest request.
```bash
NODE="$(guest -n "$GUEST_NS" get pod "$POD_DIGEST" -o jsonpath='{.spec.nodeName}')"
before="$(k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -cF "/v2/$VIRTUAL_REPO/manifests/")"
guest -n "$GUEST_NS" delete pod "$POD_DIGEST" --wait
pod "$POD_DIGEST" "${VIRTUAL_REPO}@${TEST_DIGEST}" | NODE="$NODE" yq '.spec.nodeName = strenv(NODE)' | guest apply -f -
guest -n "$GUEST_NS" wait pod/"$POD_DIGEST" --for=condition=Ready --timeout=5m
after="$(k -n "$NS" logs "deploy/$NAME" | grep cri-o | grep -cF "/v2/$VIRTUAL_REPO/manifests/")"
echo "manifest requests: before=$before after=$after"
guest -n "$GUEST_NS" get events --field-selector involvedObject.name="$POD_DIGEST" --sort-by=.lastTimestamp | tail -3
```
Expected: `after > before`; the new `Pulled` event says `Successfully pulled image …` (or `… already present` only for
layers, never skipping the manifest fetch). This confirms the note in `plan.md` for CNTRLPLANE-3928.

**Record:** before/after counts.

## 8. Cleanup (HC first, then the mirror)

Run in the **same terminal** as the previous steps (env and `INFRA_ID` are already set). Only if you are in a new
terminal, first run `source .work/cntrlplane-3926/reachability/env.sh && source "$REACH_OUT/infra-id.sh"`.
The step 1 watcher must already be stopped.

```bash
echo "INFRA_ID=$INFRA_ID"          # must be mirror-reach-xxxxx: the AWS leftover queries below filter on it
guest delete ns "$GUEST_NS" --wait=false 2>/dev/null
hs destroy cluster aws --name "$HC_NAME" --namespace "$HC_NS" \
  --aws-creds "$AWS_CREDS" --region "$AWS_REGION" 2>&1 | tee "$REACH_OUT/destroy.log"
k -n "$HC_NS" get hostedcluster,nodepool                  # expected: No resources found
k get ns "$HCP_NS"                                        # expected: NotFound
aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
  --query 'Vpcs[].VpcId' --output text                    # expected: empty
aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text   # expected: empty
k -n "$HC_NS" get secret,cm                               # expected: only leftovers of mirror-reach (user-ca-bundle, pull/ssh secrets) + OpenShift defaults
k delete ns "$HC_NS"                                      # `clusters` did not exist before T8 (only if the line above shows nothing else)
harness teardown 2>&1 | tee "$REACH_OUT/teardown.log"
k get ns "$NS"                                            # expected: NotFound
```
Expected: destroy exits 0 in ~10–15 min (logs deletion of NodePool, HC, then AWS resources: instances, NAT, EIPs, subnets,
VPC, Route53 records/zones, IAM roles/instance profiles, OIDC provider); every "expected" line as commented;
`harness teardown` ~20 s, then namespace NotFound.

**Record:** destroy duration, leftovers (should be none).

