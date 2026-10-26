# T6 — Live validation runbook (mgmt)

Goal: prove that the Go helper `test/e2e/v2/util/mirrorregistry` (T1–T5a) does on a real cluster what T0 did
by hand, plus what only the Go code does: idempotent re-runs, the D4 invariant (Route only while read-only)
across re-runs, CA persistence (D3), caller-supplied CA, and Teardown. Fill `RESULTS.md` as you go (each step
has a **Record** line). Bugs found → one fix commit each, `gate.sh` must pass, then repeat the failed step.

Scope and safety:
- Only context `$CTX` (default `mgmt`, see `env.sh`), only namespace `test-mirror-registry`
  (+ cluster-scoped reads of the ingress domain and the `openshift/cli` ImageStream).
- No pull secret is used: the test image is public (`SourcePullSecret` is out of scope for T6).
- `out/` holds CA private keys (`out/caller-ca*`): it stays under `.work/` (gitignored). Never paste them.
- Time: ~1 hour. Part A (steps 1–5) is the must-have; Part B (6–10) covers the caller-supplied CA.

Tools: `harness` (= `go run ./.work/cntrlplane-3926/harness`), `watch.sh` (state transitions + invariant
check, second terminal), `verify.sh` (laptop checks, one PASS/FAIL line each). Run from the repository root.

---

## 0. Environment (both terminals)

```bash
source .work/cntrlplane-3926/harness/env.sh
k get ns "$NS"                                  # expected: NotFound (start clean)
go build -o /dev/null ./.work/cntrlplane-3926/harness && echo "harness builds"
```

# Part A — helper-generated CA

## 1. First Setup (fresh namespace)

Terminal 2:
```bash
.work/cntrlplane-3926/harness/watch.sh "$OUT/watch-run1.log"
```
Terminal 1:
```bash
harness setup -out "$OUT/run1" 2>&1 | tee "$OUT/run1.log"
```
Expected:
- `harness: copier image: quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:…` (ImageStream lookup works);
- exit 0, `result.json` printed with `Host == $HOST`, `InternalHost == mirror-registry.test-mirror-registry.svc:5000`,
  two `Images` (`SourceRef` = real and virtual repo, `MirrorRef` = `$HOST/<source repo>@$TEST_DIGEST`),
  two `ImageContentSources` (sorted: `mirror-source…invalid/…` then `quay.io/…`), each with one mirror;
- watch log order: `readonly=false`, pod Running, copy Job appears and disappears (cleaned up on success),
  `readonly=true` with a new pod, then `route=pending` → `route=admitted`; **no `VIOLATION`** line.
  Stop the watcher (Ctrl-C) after the harness exits.

**Record:** Setup duration, copier image digest, watch log, any error.

## 2. Verify from the laptop and from the cluster

```bash
.work/cntrlplane-3926/harness/verify.sh "$OUT/run1"
cat "$OUT/run1/ics.yaml"
openssl x509 -in "$OUT/run1/ca-only/ca.crt" -noout -subject -enddate
# Serving cert: SANs, issuer = our CA, short CN
openssl s_client -connect "${HOST}:443" -servername "$HOST" -CAfile "$OUT/run1/ca-only/ca.crt" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
# Stored CA Secret matches the CA returned in Result
k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/run1/ca-only/ca.crt" && echo "stored CA == Result CA"
# Cluster state: no leftover copy Job/Secret, read-only config, pod under restricted-v2
k -n "$NS" get job,secret,route,pvc
k -n "$NS" get cm "${NAME}-config" -o jsonpath='{.data.config\.yml}' | grep -A1 'readonly:'
k -n "$NS" get pod -l app.kubernetes.io/name="$NAME" -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'
```
Expected: `verify: 0 failure(s)`; SANs contain `$HOST` and the Service names; issuer = CA subject;
`stored CA == Result CA`; only Secrets `${NAME}-ca` and `${NAME}-tls` (no `*-copy-*` Secret, no Job);
`enabled: true`; SCC `restricted-v2`.

**Record:** verify output, SANs, leftovers (should be none).

## 3. Second Setup (idempotency, Route withdrawn first, CA unchanged)

Terminal 2: `.work/cntrlplane-3926/harness/watch.sh "$OUT/watch-run2.log"`

Terminal 1:
```bash
harness setup -out "$OUT/run2" 2>&1 | tee "$OUT/run2.log"
cmp "$OUT/run1/ca-only/ca.crt" "$OUT/run2/ca-only/ca.crt" && echo "CA unchanged"
diff "$OUT/run1/result.json" "$OUT/run2/result.json" && echo "Result unchanged"
.work/cntrlplane-3926/harness/verify.sh "$OUT/run2"
```
Expected:
- watch log starts with `route=admitted readonly=true`, then `route=none readonly=true` **before** any
  `readonly=false`; then the same sequence as step 1; **no `VIOLATION`**;
- `CA unchanged`, `Result unchanged`, `verify: 0 failure(s)`;
- content is still served (PVC reused; the copy re-pushes the same digests).

**Record:** Setup duration, watch log, CA/Result comparison, verify output.

## 4. Teardown and idempotent Teardown

```bash
harness teardown 2>&1 | tee "$OUT/teardown1.log"
k get ns "$NS"                                                   # expected: NotFound
k get pv | grep "${NS}/${NAME}" || echo "PV gone (reclaimPolicy Delete)"
curl -sS -o /dev/null -w '%{http_code}\n' --cacert "$OUT/run1/ca-only/ca.crt" "https://${HOST}/v2/"   # expected: exit 60 (no Route: router serves its default cert)
harness teardown 2>&1 | tee "$OUT/teardown2.log"                 # expected: exit 0 immediately (namespace absent)
```
**Record:** durations, NotFound, PV gone, second teardown exit code.

## 5. Part A verdict

All of steps 1–4 OK → Part A PASS. On failure: capture the harness error and `k -n "$NS" get all,cm,secret,route -o wide`
and `k -n "$NS" get events --sort-by=.lastTimestamp | tail -30` **before** tearing down.

# Part B — caller-supplied CA (`Options.CA`)

## 6. Generate two CAs locally (PKCS#8 keys, as OpenSSL 3 writes them)

```bash
for ca in caller-ca caller-ca2; do
  mkdir -p "$OUT/$ca" && (
    cd "$OUT/$ca"
    openssl genrsa -out ca.key 4096 2>/dev/null
    openssl req -x509 -new -key ca.key -days 30 -subj "/CN=hypershift-e2e-${ca}" \
      -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ca.crt
    head -1 ca.key; openssl x509 -in ca.crt -noout -subject
  )
done
```
Expected: `[PKCS#8 key header line]` (PKCS#8 → exercises `parsePrivateKey`'s PKCS#8 path), two subjects.

## 7. Setup with a caller-supplied CA on a fresh namespace

```bash
harness setup -out "$OUT/runB1" -ca-cert "$OUT/caller-ca/ca.crt" -ca-key "$OUT/caller-ca/ca.key" 2>&1 | tee "$OUT/runB1.log"
cmp "$OUT/caller-ca/ca.crt" "$OUT/runB1/ca-only/ca.crt" && echo "Result CA == caller CA"
k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/caller-ca/ca.crt" && echo "stored CA == caller CA"
.work/cntrlplane-3926/harness/verify.sh "$OUT/runB1"
```
Expected: both `==` lines, `verify: 0 failure(s)`. (A watcher is optional here.)

## 8. Setup without `-ca` reuses the stored caller CA

```bash
harness setup -out "$OUT/runB2" 2>&1 | tee "$OUT/runB2.log"
cmp "$OUT/caller-ca/ca.crt" "$OUT/runB2/ca-only/ca.crt" && echo "stored caller CA reused"
.work/cntrlplane-3926/harness/verify.sh "$OUT/runB2"
```
Expected: `stored caller CA reused`, `verify: 0 failure(s)`.

## 9. Setup with a different caller CA (rotation; withdrawal uses the stored CA)

Terminal 2: `.work/cntrlplane-3926/harness/watch.sh "$OUT/watch-runB3.log"`

```bash
harness setup -out "$OUT/runB3" -ca-cert "$OUT/caller-ca2/ca.crt" -ca-key "$OUT/caller-ca2/ca.key" 2>&1 | tee "$OUT/runB3.log"
cmp "$OUT/caller-ca2/ca.crt" "$OUT/runB3/ca-only/ca.crt" && echo "Result CA == caller CA2"
k -n "$NS" get secret "${NAME}-ca" -o jsonpath='{.data.ca\.crt}' | base64 -d | cmp - "$OUT/caller-ca2/ca.crt" && echo "stored CA replaced by CA2"
.work/cntrlplane-3926/harness/verify.sh "$OUT/runB3"
curl -sS -o /dev/null --cacert "$OUT/caller-ca/ca.crt" "https://${HOST}/v2/"; echo "exit=$? (expected 60: old CA no longer trusted)"
```
Expected: Setup succeeds (the Route withdrawal check trusted the *old* CA served by the running pod — this is
the `clientForWithdrawal` path), no `VIOLATION`, both `==` lines, verify passes with CA2, old CA rejected.

**Record:** outcome, Setup duration, watch log.

## 10. Teardown

```bash
harness teardown 2>&1 | tee "$OUT/teardownB.log"
k get ns "$NS"                                                   # expected: NotFound
k get pv | grep "${NS}/${NAME}" || echo "PV gone"
```
