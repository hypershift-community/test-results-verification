# CNTRLPLANE-3927 — Live propagation runbook (mgmt)

Goal: run the two new specs of `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go` for real, through the
same lifecycle path CI will use (CNTRLPLANE-3929): `create-guests` (mirror fixture + one `image-mirroring`
HostedCluster) → `run-tests` (label `lifecycle && image-mirroring`) → `destroy-guests`. Then check the same
outputs independently with `oc` (`check.sh guest|cm`), so the evidence does not rely only on the Go code under test:

1. hosted cluster `ImageDigestMirrorSet/cluster` = HC `imageContentSources`, label `machineconfiguration.openshift.io/role: worker` (HCCO path);
2. HCP ConfigMap `ignition-config-40-image-content-source`, label `hypershift.openshift.io/core-ignition-config: "true"`,
   `data.config` = the same IDMS as YAML (CPO path).

This is also the first end-to-end run of the 3926 `create-guests` wiring (T8 fed the CLI by hand from the harness).

Copy `RESULTS.template.md` to `RESULTS.md` and fill it as you go (each step has a **Record** line) and paste command output under the matching
**Evidence** heading. No code changes expected. If something fails, capture the "On failure" commands of the step
**before** destroying anything, and always finish with step 6.

Scope and safety:
- Management-cluster changes only on `mgmt`: namespaces `test-mirror-registry` (fixture), `keycloak` (the AWS
  `PreCreate` always deploys Keycloak, even when only the `image-mirroring` variant is selected), `clusters` with the new
  HC `image-mirroring-beaa1f2bd2`, and its control-plane namespace `clusters-image-mirroring-beaa1f2bd2`. Parent cluster untouched.
- `create-guests`, `run-tests`, `destroy-guests` and the CLI get `out/mc.kubeconfig`, which contains **only** the
  `mgmt` context (the `e2e` and `hs` wrappers).
- AWS: the CLI creates VPC/NAT/IAM/Route53 for the HC in the account of the default profile in `~/.aws/credentials`
  (same as T8). As in CI, no `--aws-creds` flag: the SDK default chain reads that file. Step 6 removes it all.
- Cost: 2 × `m5.large` (CLI default) workers with 64Gi gp3 root volumes, plus a NAT gateway, for ~1.5–2 h.
- `out/` holds kubeconfigs, the fixture CA and logs. Local only, never paste kubeconfigs or the pull secret.
- Time: ~1.5–2 h, mostly waiting. `create-guests` waits for HC Available **and** a completed version rollout
  (T8 did not wait for that), with a 55 min overall limit.

Tools: `k` (= `oc --context mgmt`), `hs` (= branch-built `bin/hypershift` with `mc.kubeconfig`), `guest`
(= `oc` on the hosted cluster), `e2e <cmd>` (runs `<cmd>` with the CI environment: `SHARED_DIR`, `ARTIFACT_DIR`,
`PROW_JOB_ID`, `TEST_PLAN`, `HYPERSHIFT_E2E_IMAGE_MIRRORING=true`, …), `check.sh <phase>` (PASS/FAIL lines).
Run everything from the repository root, in the same terminal (except the optional watcher). The `exit=` lines print
the exit code of the command before `| tee` (works in zsh and bash).

---

## 0. Environment, preflight and local build

```bash
git status --short && git log --oneline -1          # expected: clean, c9ad656db6 test(e2e): verify image mirroring propagation …
source .work/cntrlplane-3927/propagation/env.sh
make hypershift e2ev2 e2ev2-create-guests e2ev2-run-tests e2ev2-destroy-guests
bin/test-e2e-v2 --ginkgo.dry-run --ginkgo.v --ginkgo.no-color --ginkgo.label-filter='lifecycle && image-mirroring' 2>&1 | grep -E 'Will run|Image Mirroring should'
k get ns "$NS" "$KC_NS" "$HC_NS"                    # expected: all three NotFound
k get hostedcluster -A                              # expected: No resources found
hs version                                          # expected: Client c9ad656… (Latest supported OCP 5.1.0); Server e83d9072…, supports 4.20
k -n openshift get imagestream cli -o jsonpath='{.status.tags[?(@.tag=="latest")].items[0].dockerImageReference}{"\n"}'
k adm top nodes
e2e aws sts get-caller-identity --query Arn --output text                    # expected: arn:aws:iam::123456789012:user/tester
e2e aws route53 list-hosted-zones-by-name --dns-name "$BASE_DOMAIN" --max-items 1 \
  --query 'HostedZones[0].[Name,Config.PrivateZone]' --output text              # expected: hypershift.example.com.  False
jq -e '.auths["quay.io"]' "$PULL_SECRET" >/dev/null && echo "pull secret has quay.io"
ls -A "$SHARED" "$ARTIFACTS"                        # expected: both empty (a fresh run)
```
Expected:
- `env.sh` prints `HC=clusters/image-mirroring-beaa1f2bd2 HCP_NS=clusters-image-mirroring-beaa1f2bd2 RELEASE=…4.20.0-x86_64 NODES=2`
  and `HOST=mirror-registry-test-mirror-registry.apps.mgmt…`;
- `make` builds `bin/hypershift`, `bin/test-e2e-v2`, `bin/create-guests`, `bin/run-tests`, `bin/destroy-guests`;
- dry run: `Will run 2 of <N> specs` and the two spec names (dry run only proves selection, not behavior);
- ImageStream: a `…@sha256:` reference (the copier image; `PreCreate` fails without a digest);
- `top nodes`: room for one more HCP (~10–15 pods of a single-replica control plane) + Keycloak + the small registry.

If `k` fails with `TLS handshake timeout` (seen on 2026/10/14), just retry: the mgmt API is occasionally slow.
If `$SHARED` is not empty, a previous run was not cleaned up: stop and finish its step 6 first.

**Record:** commit, CLI/HO versions, copier image digest, node headroom, anything unexpected.

## 1. Lifecycle create: fixture, Keycloak, one HC (`create-guests`)

Terminals 2 and 3 (optional; `source .work/cntrlplane-3927/propagation/env.sh` there too; Ctrl-C when step 1 ends;
`-w` accepts a single resource type):
```bash
k -n "$HC_NS" get hostedcluster -w                 # terminal 2
k -n "$HC_NS" get nodepool -w                      # terminal 3
```
Terminal 1:
```bash
date; e2e bin/create-guests 2>&1 | tee "$PROP_OUT/create.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
grep -E 'Using test plan|Phase [0-9]|Cluster image-mirroring|Keycloak deployed|Running: |is Available|Version rollout|All clusters are ready|ERROR' "$PROP_OUT/create.log"
.work/cntrlplane-3927/propagation/check.sh fixture
.work/cntrlplane-3927/propagation/check.sh hc
cat "$SHARED/mirror-registry-ics.yaml"
k -n "$HC_NS" get hostedcluster,nodepool
```
Expected:
- `Using test plan "image-mirroring-propagation"`; Phase 0 `Cluster image-mirroring: name=image-mirroring-beaa1f2bd2`
  and only that cluster; Phase 1 `Keycloak deployed: issuer=https://<keycloak route on mgmt>/realms/…` (a few minutes),
  then the mirror Setup (silent, ~1 min); Phase 2 one `Running: …/bin/hypershift [create cluster aws --name=image-mirroring-beaa1f2bd2
  … --additional-trust-bundle=…/shared/mirror-registry-ca.pem --image-content-sources=…/shared/mirror-registry-ics.yaml]`,
  then the CLI's VPC/NAT/IAM/OIDC lines and `Applied Kube resource` lines; Phases 4/6 progress lines
  `Cluster clusters/image-mirroring-beaa1f2bd2: Available=…, VersionState=…`; finally `All clusters are ready`, `exit=0`;
- duration: roughly 25–45 min (HC Available ~10–15 min, then guest operators until the rollout is `Completed`);
- `check.sh fixture`: 12 PASS (SHARED_DIR files, manifest, Route, ICS file, registry ready, CA, laptop → mirror TLS, Keycloak), `0 failure(s)`;
- `check.sh hc`: 4 PASS (HC ICS == fixture ICS, trust bundle == fixture CA, Available, rollout Completed), `0 failure(s)`;
- `mirror-registry-ics.yaml`: two entries (virtual repo first, then quay.io), one mirror each = `$HOST/<source>`;
- NodePool `image-mirroring-beaa1f2bd2-us-east-1a` 2/2.

On failure (keep `create.log`; do **not** re-run `create-guests` on top: it would re-run Keycloak/mirror setup):
```bash
k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
k -n "$HC_NS" get nodepool -o jsonpath='{range .items[0].status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
k -n "$HCP_NS" get pods | grep -v -E 'Running|Completed'
k -n "$NS" get deploy,pods,jobs,pvc,route; k -n "$NS" get events --sort-by=.lastTimestamp | tail -20
k -n "$KC_NS" get pods
ls "$ARTIFACTS"                                     # junit_hosted_cluster_<name>.xml carries the rollout diagnostics
```
- Failed before Phase 2 (Keycloak, mirror, ImageStream): no cloud resources yet; go to step 6.
- CLI create failed (e.g. a field the installed HO/CRDs reject; our CLI is newer than the HO): stop and investigate;
  T8 used `/usr/local/bin/hypershift` (cce02430) as a fallback candidate. Then step 6 (destroy cleans by infra ID).
- Only Phase 6 (rollout) timed out but the HC is Available: record the stuck operator, then **still run step 2**
  (the specs do not need a completed rollout) and note the deviation.

**Record:** start/end/duration, check outputs, HC name, NodePool, any ERROR line.

## 2. The actual tests (`run-tests`)

```bash
date; e2e bin/run-tests 2>&1 | tee "$PROP_OUT/run-tests.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
grep -E 'Using test plan|Running image-mirroring tests|Will run|Successfully waited for|\[PASSED\]|\[FAILED\]|\[SKIPPED\]|Ran [0-9]+ of|tests (PASSED|FAILED)|All test groups passed' "$PROP_OUT/run-tests.log"
.work/cntrlplane-3927/propagation/check.sh junit
```
Expected:
- `Running image-mirroring tests against image-mirroring-beaa1f2bd2...`, `Will run 2 of <N> specs`;
- two `Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 …` lines: one for `hosted ImageDigestMirrorSet/cluster mappings
  and worker role`, one for `ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels`
  (both should converge in seconds: the cluster is already rolled out);
- `Ran 2 of <N> Specs`, `2 Passed | 0 Failed`, `image-mirroring tests PASSED`, `All test groups passed`, `exit=0`;
- `check.sh junit`: 6 PASS (file, 2 testcases, both `passed`, no failure/skip, `DryRun=false`), `0 failure(s)`.

`run-tests` is read-only on the clusters (port-forward to the HCP kube-apiserver + GETs), so it can be repeated.

On failure: keep the log; the failing `It` prints the HC name, the target and `expected HC mappings … got …`.
Run step 3 anyway (it shows the real objects), then analyze both. Do **not** change the test to make it pass.

**Record:** duration, the two `Successfully waited` lines, Ran/Passed summary, check output.

## 3. Independent check of both outputs (hosted IDMS, HCP ignition ConfigMap)

```bash
k -n "$HC_NS" get secret "${HC_NAME}-admin-kubeconfig" -o jsonpath='{.data.kubeconfig}' | base64 -d > "$GUEST_KUBECONFIG"
chmod 600 "$GUEST_KUBECONFIG"
guest get nodes
.work/cntrlplane-3927/propagation/check.sh guest
.work/cntrlplane-3927/propagation/check.sh cm
k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.imageContentSources}{"\n"}'
guest get imagedigestmirrorset cluster -o yaml | yq '{"labels": .metadata.labels, "spec": .spec}'
k -n "$HCP_NS" get cm ignition-config-40-image-content-source -o jsonpath='{.metadata.labels}{"\n"}{.data.config}'
k -n "$HCP_NS" get deploy control-plane-operator hosted-cluster-config-operator \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```
Expected:
- 2 nodes `Ready`;
- `check.sh guest`: 5 PASS (HC ICS non-empty, IDMS exists, GVK/name/cluster-scoped, worker label, mappings == HC), `0 failure(s)`;
- `check.sh cm`: 6 PASS (CM exists, core label, YAML decodes, payload GVK/name, worker label, mappings == HC), `0 failure(s)`;
- HC spec, IDMS spec and CM payload all show the same two sources, each with the single mirror `$HOST/<source>`;
  IDMS has no `mirrorSourcePolicy`; the CM payload starts with `apiVersion: config.openshift.io/v1` / `kind: ImageDigestMirrorSet`;
- CPO and HCCO images come from the 4.20.0 release payload (`quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:…`):
  this run exercises the **4.20.0** producers, not CPO/HCCO built from this branch (the change is test-only, so that is fine;
  record it).

**Record:** check outputs, CPO/HCCO images.

## 4. (Quick, recommended) Repeat the tests

Shows the specs are repeatable and read-only (no state left between runs).
```bash
e2e bin/run-tests 2>&1 | tee "$PROP_OUT/run-tests-2.log" | grep -E 'Successfully waited for|Ran [0-9]+ of|[0-9]+ Passed|All test groups passed'
.work/cntrlplane-3927/propagation/check.sh junit
```
Expected: same as step 2 (the JUnit file is overwritten by this run; step 2's log is kept).

**Record:** summary line, check output.

## 5. (Only if something failed) Extra diagnostics before cleanup

```bash
make e2ev2-dump-guests && e2e bin/dump-guests 2>&1 | tail -5     # standard CI dump, written under $ARTIFACTS
k -n "$HCP_NS" logs deploy/control-plane-operator --since=2h | grep -iE 'imagedigestmirror|image content|ignition-config-40' | tail -20
k -n "$HCP_NS" logs deploy/hosted-cluster-config-operator --since=2h | grep -iE 'imagedigestmirror|idms' | tail -20
```
**Record:** relevant lines only.

## 6. Cleanup (HC first, then Keycloak and the mirror)

Same terminal (env already set). In a new terminal: `source .work/cntrlplane-3927/propagation/env.sh` first; it recomputes
the same HC name from `PROW_JOB_ID`, and `destroy-guests` reads `out/shared/cluster-manifests.json`.

```bash
jq -c .clusters "$SHARED/cluster-manifests.json"   # must be the image-mirroring-beaa1f2bd2 entry
# identifiers for the step 6b leftover queries (read them while the HC still exists)
KAS_LB="$(k -n "$HCP_NS" get svc kube-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | cut -d- -f1)"
OIDC_BUCKET="$(k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.issuerURL}' | sed -E 's#https://([^.]+)\..*#\1#')"
ZONE_ID="$(e2e aws route53 list-hosted-zones-by-name --dns-name "$BASE_DOMAIN" --max-items 1 --query 'HostedZones[0].Id' --output text | sed 's#/hostedzone/##')"
echo "KAS_LB=$KAS_LB OIDC_BUCKET=$OIDC_BUCKET ZONE_ID=$ZONE_ID"
date; e2e bin/destroy-guests 2>&1 | tee "$PROP_OUT/destroy.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
k -n "$HC_NS" get secret,cm                         # expected: only leftovers of this HC (user-ca-bundle, pull/ssh secrets) + OpenShift defaults
k delete ns "$HC_NS"                                # `clusters` did not exist before (only if the line above shows nothing else)
k delete ns "$KC_NS" "$NS" --wait=true --timeout=10m
.work/cntrlplane-3927/propagation/check.sh clean
rm -f "$GUEST_KUBECONFIG"
```
Expected:
- `destroy-guests`: `Destroying 1 clusters from manifest`, one `Running: …/bin/hypershift [destroy cluster aws --name=image-mirroring-beaa1f2bd2
  --namespace=clusters --infra-id=image-mirroring-beaa1f2bd2 --cluster-grace-period=40m --region=us-east-1 --base-domain=hypershift.example.com]`,
  the CLI deletion lines (NodePool, HC, instances, NAT, EIPs, subnets, VPC, Route53, IAM, OIDC), `All clusters destroyed successfully`, `exit=0`;
  ~10–15 min (T8: ~6 min);
- `check.sh clean`: 7 PASS (no HC/NodePool, HCP/mirror/Keycloak namespaces gone, no mirror PV, no VPC, no instances), `0 failure(s)`.

If `destroy-guests` fails: keep `destroy.log` and re-run it (idempotent). If it keeps failing, the manual equivalent
(same as T8, by infra ID) is:
`e2e hs destroy cluster aws --name "$HC_NAME" --namespace "$HC_NS" --infra-id "$INFRA_ID" --region "$AWS_REGION" --base-domain "$BASE_DOMAIN"`.

### 6b. Leftovers that `check.sh clean` does not cover

`check.sh clean` checks namespaces, PV, VPC and instances. Also confirm that the OIDC documents, public DNS records and
the management-side kube-apiserver load balancer are gone (read-only; every command must print nothing):
```bash
e2e aws s3 ls "s3://${OIDC_BUCKET}/${INFRA_ID}/"
e2e aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query "ResourceRecordSets[?contains(Name,'${HC_NAME}')].Name" --output text
e2e aws elb describe-load-balancers --region "$AWS_REGION" --query "LoadBalancerDescriptions[?starts_with(LoadBalancerName,'${KAS_LB}')].LoadBalancerName" --output text
e2e aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?starts_with(LoadBalancerName,'${KAS_LB}')].LoadBalancerName" --output text
```
If `KAS_LB` is empty (the service was already gone), take the ELB name from the HC condition messages in the step 1 watch
(`Get "https://<name>-<hash>.elb…/healthz"`).

**Record:** destroy duration, check output, leftovers (should be none).

Then review the evidence with `VERIFY.md`, in a fresh session or by another person, without cluster access.
