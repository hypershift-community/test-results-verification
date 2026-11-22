#!/usr/bin/env bash
# Laptop checks of the public endpoint (RUNBOOK step 7 of T0), one PASS/FAIL line each.
#   verify.sh <run-dir>     e.g. verify.sh "$OUT/run1"   (uses <run-dir>/ca-only/ca.crt)
# Needs HOST, TEST_SRC_REPO, TEST_DIGEST, VIRTUAL_REPO from env.sh.
set -u
RUN="${1:?usage: verify.sh <run-dir>}"
CERTS="${RUN}/ca-only"
fails=0
check() { if [ "$2" = ok ]; then echo "PASS  $1"; else echo "FAIL  $1  ($3)"; fails=$((fails + 1)); fi; }

body=$(curl -sS --cacert "${CERTS}/ca.crt" -w ' %{http_code}' "https://${HOST}/v2/" 2>&1)
[ "${body}" = "{} 200" ] && r=ok || r=ko; check "anonymous /v2/ with CA → {} 200" "$r" "${body}"

curl -sS -o /dev/null "https://${HOST}/v2/" 2>/dev/null; rc=$?
[ "${rc}" = 60 ] && r=ok || r=ko; check "TLS refused without CA (curl exit 60)" "$r" "exit ${rc}"

for repo in "${TEST_SRC_REPO}" "${VIRTUAL_REPO}"; do
  got="sha256:$(skopeo inspect --raw --no-creds --cert-dir "${CERTS}" "docker://${HOST}/${repo}@${TEST_DIGEST}" | shasum -a 256 | cut -d' ' -f1)"
  [ "${got}" = "${TEST_DIGEST}" ] && r=ok || r=ko; check "digest preserved ${repo}" "$r" "got ${got}"
done

push=$(skopeo copy --all --dest-no-creds --dest-cert-dir "${CERTS}" \
  "docker://${TEST_SRC_REPO}@${TEST_DIGEST}" "docker://${HOST}/route-push-check/registry:x" 2>&1); rc=$?
if [ "${rc}" != 0 ] && grep -q '405' <<<"${push}"; then r=ok; else r=ko; fi
check "push via Route rejected (405)" "$r" "exit ${rc}: $(grep -m1 -E 'FATA|405' <<<"${push}")"

echo "verify: ${fails} failure(s)"
exit "${fails}"
