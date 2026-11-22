# T0 — Smoke test runbook (mgmt)

Goal: verify the assumptions behind `decisions.md` with real resources, and record the facts the delegated
tasks (T3 builders, T4 copier) need. Fill `RESULTS.md` as you go (each step has a **Record** line).

Scope and safety:
- Only context `mgmt`, only namespace `test-mirror-registry` (+ one cluster-scoped read of the ingress
  domain, ImageStream and ClusterVersion). Nothing on the parent cluster, no HostedCluster changes.
- Every `oc` call goes through `k` (= `oc --context mgmt`).
- `out/` holds a private key: it stays under `.work/` (gitignored). Never paste it anywhere.
- Step 10 copies the management cluster pull secret into the test namespace: do not print it; it is deleted
  with the namespace in step 12.
- Time: ~1–2 hours. Steps 1–9 are the must-haves; 10–11 are discovery for later stories.

All commands are run from the repository root in a bash/zsh shell.

---

## 0. Environment

```bash
source .work/cntrlplane-3926/smoke/env.sh
k get ns "$NS"            # expected: NotFound (start clean)
```
Expected: the echo shows `HOST=mirror-registry-test-mirror-registry.apps.mgmt...`, a `CLI_IMAGE` by digest
in `quay.io/openshift-release-dev/ocp-v4.0-art-dev`, and a `RELEASE_IMAGE` by digest.

## 1. CA and serving certificate (local, openssl)

```bash
cd "$OUT/certs"
cat > ca.ext <<'EOF'
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF
openssl genrsa -out ca.key 4096
openssl req -new -key ca.key -subj "/CN=hypershift-e2e-mirror-registry-ca" -out ca.csr
openssl x509 -req -in ca.csr -signkey ca.key -days 30 -extfile ca.ext -out ca.crt

cat > tls.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${HOST},DNS:${NAME},DNS:${NAME}.${NS},DNS:${NAME}.${NS}.svc,DNS:${NAME}.${NS}.svc.cluster.local
EOF
openssl genrsa -out tls.key 2048
# CN is limited to 64 characters (RFC 5280) and $HOST is longer; clients match the SANs, so keep CN short.
openssl req -new -key tls.key -subj "/CN=${NAME}" -out tls.csr
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile tls.ext -out tls.crt
openssl verify -CAfile ca.crt tls.crt          # expected: tls.crt: OK
cd - >/dev/null
```
These mirror what T2 will do in Go (`support/certs`).

## 2. Namespace, TLS Secret, CA ConfigMap, registry config (writable)

```bash
k create namespace "$NS"
k label namespace "$NS" app.kubernetes.io/part-of=hypershift-e2e-mirror-registry
k -n "$NS" create secret tls "${NAME}-tls" --cert="$OUT/certs/tls.crt" --key="$OUT/certs/tls.key"
k -n "$NS" create configmap "${NAME}-ca" --from-file=ca.crt="$OUT/certs/ca.crt"
READONLY=false render registry-config.yaml | k apply -f -
render pvc.yaml | k apply -f -
render service.yaml | k apply -f -
```

## 3. Registry Deployment (restricted-v2, PVC)

```bash
render deployment.yaml | k apply -f -
k -n "$NS" rollout status deploy/"$NAME" --timeout=5m
POD=$(k -n "$NS" get pod -l app.kubernetes.io/name="$NAME" -o jsonpath='{.items[0].metadata.name}')
k -n "$NS" get pod "$POD" -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"  uid="}{.spec.containers[0].securityContext.runAsUser}{"\n"}'
k -n "$NS" logs "$POD" | grep -m1 -i 'listening on'   # startup line (tail would only show probe noise)
```
Expected:
- rollout succeeds; no PodSecurity admission warnings on apply;
- SCC `restricted-v2`, a high random UID;
- log line similar to `listening on [::]:5000, tls`.

If the pod crash-loops: check `k -n "$NS" logs "$POD"` (config path/permissions) and `k -n "$NS" describe pod "$POD"`.

**Record:** SCC, UID, any change needed to the Deployment, log line.

## 4. Copy one image twice (real + virtual source) via the internal Service

```bash
export JOB_NAME=mirror-test \
  ARG1="${TEST_SRC_REPO}@${TEST_DIGEST}" ARG2="${INTERNAL}/quay.io/libpod/registry" \
  ARG3="${TEST_SRC_REPO}@${TEST_DIGEST}" ARG4="${INTERNAL}/${VIRTUAL_REPO}"
render job-mirror.yaml | k apply -f -
k -n "$NS" wait --for=condition=complete job/mirror-test --timeout=10m \
  || k -n "$NS" wait --for=condition=failed job/mirror-test --timeout=1s
k -n "$NS" logs job/mirror-test
```
Expected: Job `Complete`; logs show both mirrors and the manifest list `sha256:e642e860...` plus per-arch manifests;
no TLS errors (proves the combined CA bundle via `SSL_CERT_FILE` works for `oc`).

Checks:
- `oc image mirror` accepted a destination **without tag** for a by-digest source (if not, record the error and
  what destination form works, e.g. adding `:mirror`);
- the repository layout `<registry>/<source-registry>/<path>` (D6) is accepted, including the `.invalid` host
  as a path component.

**Record:** `oc` client version from the log, exact working command line, any flag changes.

## 5. Switch to read-only and prove pushes are rejected

```bash
READONLY=true render registry-config.yaml | k apply -f -
k -n "$NS" rollout restart deploy/"$NAME"
k -n "$NS" rollout status deploy/"$NAME" --timeout=5m

export JOB_NAME=mirror-readonly-check \
  ARG1="${TEST_SRC_REPO}@${TEST_DIGEST}" ARG2="${INTERNAL}/readonly-check/registry" ARG3="" ARG4=""
render job-mirror.yaml | k apply -f -
k -n "$NS" wait --for=condition=failed job/mirror-readonly-check --timeout=10m
k -n "$NS" logs job/mirror-readonly-check | tail -n 10
```
Expected: Job **Failed**; the error mentions the registry being read-only / method not allowed / unavailable.
Content from step 4 survived the restart (checked in step 7) — this is why storage must be a PVC.

**Record:** exact error text (T4 can match it in diagnostics), restart duration.

## 6. Expose with a passthrough Route (explicit host)

```bash
render route.yaml | k apply -f -
k -n "$NS" get route "$NAME" -o jsonpath='{.spec.host}{"  "}{.status.ingress[0].conditions[0].type}={.status.ingress[0].conditions[0].status}{"\n"}'
```
Expected: host equals `$HOST`, `Admitted=True`.

**Record:** whether setting `spec.host` explicitly needed anything special.

## 7. Verify from the laptop: anonymous, read-only, TLS verified, digest preserved

```bash
# TLS verified against our CA only; anonymous; expect HTTP 200 and body {}
curl -sS --cacert "$OUT/certs/ca.crt" -w '  HTTP %{http_code}\n' "https://${HOST}/v2/"

# Without our CA the TLS handshake must fail (proves verification is real)
curl -sS -o /dev/null "https://${HOST}/v2/" ; echo "exit=$? (expected non-zero, certificate error)"

# skopeo needs a directory with ONLY the CA: a *.key without a matching *.cert there is an error.
mkdir -p "$OUT/ca-only" && cp "$OUT/certs/ca.crt" "$OUT/ca-only/ca.crt"

# Digest preserved for both repositories (manifest list digest == TEST_DIGEST)
for repo in quay.io/libpod/registry "${VIRTUAL_REPO}"; do
  echo "$repo: sha256:$(skopeo inspect --raw --no-creds --cert-dir "$OUT/ca-only" \
    "docker://${HOST}/${repo}@${TEST_DIGEST}" | shasum -a 256 | cut -d' ' -f1)"
done
echo "expected: ${TEST_DIGEST}"

# Pushing through the public Route must fail (read-only)
skopeo copy --all --dest-no-creds --dest-cert-dir "$OUT/ca-only" \
  "docker://${TEST_SRC_REPO}@${TEST_DIGEST}" "docker://${HOST}/route-push-check/registry:x" ; echo "exit=$? (expected non-zero)"
```
**Record:** all four outcomes.

## 8. Idempotency of the manifests

```bash
for f in registry-config pvc service deployment route; do READONLY=true render $f.yaml | k apply -f -; done
```
Expected: everything `unchanged` (or `configured` without a pod restart). Tells T5 which fields the API server
defaults and the create-or-update logic must tolerate.

**Record:** objects reported as `configured` and why.

## 9. Pod-level facts for the builders

```bash
k -n "$NS" get pod -l app.kubernetes.io/name="$NAME" -o yaml | grep -A12 'securityContext:' | head -40
k -n "$NS" get pvc "$NAME" -o jsonpath='{.spec.storageClassName} {.status.capacity.storage}{"\n"}'
```
**Record:** the effective securityContext injected by the SCC (fsGroup, runAsUser range), StorageClass.

## 10. (Discovery) Full release payload — size and source repositories, dry-run only

```bash
# Copy the management cluster pull secret into the test namespace without printing it.
k get secret pull-secret -n openshift-config -o json \
  | jq --arg ns "$NS" '{apiVersion, kind, type, data, metadata: {name: "source-pull-secret", namespace: $ns}}' \
  | k apply -f - >/dev/null && echo "source-pull-secret created"
render job-release-dryrun.yaml | k apply -f -
k -n "$NS" wait --for=condition=complete job/release-dryrun --timeout=15m \
  || k -n "$NS" wait --for=condition=failed job/release-dryrun --timeout=1s
k -n "$NS" logs job/release-dryrun
```
Expected: payload size summary, the unique component repositories (typically
`quay.io/openshift-release-dev/ocp-v4.0-art-dev`), and an IDMS snippet listing the source repositories
(`ocp-release` and `ocp-v4.0-art-dev`) mapped to the mirror repository. Nothing is pushed (`--dry-run`, and
the registry is read-only anyway).

Note: `oc adm release mirror` prints a deprecation warning (removal planned in `oc` 6.0, replaced by
`oc-mirror`). Record it; it affects CNTRLPLANE-3931 later, not this PR.

**Record:** total payload size (for PVC sizing in 3931), source repository list, whether parsing the IDMS
output is a reasonable way to fill `CopyResult.ReleaseSourceRepositories` or whether `--pullspecs` is simpler.

## 11. (Discovery, optional) Does the CI test image contain `oc`?

Needs a login to `registry.ci.openshift.org` (your `ci-registry` context):
```bash
oc --context ci-registry-context registry login --registry registry.ci.openshift.org --to="$OUT/ci-auth.json"
podman run --rm --authfile "$OUT/ci-auth.json" --entrypoint /bin/sh \
  registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.26-openshift-5.1 -c 'command -v oc && oc version --client || echo "no oc"'
rm -f "$OUT/ci-auth.json"
```
**Record:** present / absent. (The in-cluster Job design does not depend on it; it matters only if we ever
want to resolve the `cli` image from the CI pod instead of the `openshift/cli` ImageStream.)

## 12. Teardown

```bash
k delete namespace "$NS" --wait=true --timeout=5m
k get pv | grep "${NS}/${NAME}" || echo "PV gone (reclaimPolicy Delete)"
```
Optionally keep the namespace until `RESULTS.md` is filled; nothing else depends on it.
