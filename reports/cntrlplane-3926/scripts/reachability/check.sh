#!/usr/bin/env bash
# T8 checks, one PASS/FAIL line each. Source env.sh first.
#   check.sh hc      management side: HostedCluster carries our CA and image content sources
#   check.sh guest   hosted cluster: IDMS, user-ca-bundle, node registries.conf + trust anchor, node → mirror TLS
#   check.sh pods    positive pod running, negative pod failing, mirror log shows CRI-O pulls
set -u
: "${CTX:?source env.sh first}" "${RUN:?}" "${HC_NAME:?}" "${HC_NS:?}" "${GUEST_KUBECONFIG:?}" "${GUEST_NS:?}"
PHASE="${1:?usage: check.sh hc|guest|pods}"
fails=0
check() { if [ "$2" = ok ]; then echo "PASS  $1"; else echo "FAIL  $1  ($3)"; fails=$((fails + 1)); fi; }
k() { oc --context "${CTX}" "$@"; }
guest() { oc --kubeconfig "${GUEST_KUBECONFIG}" "$@"; }
fp() { openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }   # first cert on stdin
CA_FP="$(fp < "${RUN}/ca-only/ca.crt")"
WANT_ICS="$(jq -cS '.ImageContentSources' "${RUN}/result.json")"
node_sh() { guest debug -q "node/$1" -- chroot /host sh -c "$2" 2>/dev/null; }

case "${PHASE}" in
hc)
  hc="$(k -n "${HC_NS}" get hostedcluster "${HC_NAME}" -o json)"
  cm="$(jq -r '.spec.additionalTrustBundle.name // empty' <<<"${hc}")"
  [ -n "${cm}" ] && r=ok || r=ko; check "spec.additionalTrustBundle set" "$r" "empty"
  got="$(k -n "${HC_NS}" get cm "${cm:-none}" -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null | fp)"
  [ "${got}" = "${CA_FP}" ] && r=ok || r=ko; check "trust bundle ConfigMap ${cm} == mirror CA" "$r" "got '${got}'"
  got="$(jq -cS '.spec.imageContentSources' <<<"${hc}")"
  [ "${got}" = "${WANT_ICS}" ] && r=ok || r=ko; check "spec.imageContentSources == harness ICS" "$r" "got ${got}"
  ;;
guest)
  idms="$(guest get imagedigestmirrorset cluster -o json 2>/dev/null)"
  for repo in "${VIRTUAL_REPO}" "${TEST_SRC_REPO}"; do
    got="$(jq -r --arg s "${repo}" '.spec.imageDigestMirrors[]? | select(.source == $s) | .mirrors | join(",")' <<<"${idms}")"
    [ "${got}" = "${HOST}/${repo}" ] && r=ok || r=ko; check "guest IDMS cluster: ${repo} → mirror" "$r" "got '${got}'"
  done
  got="$(guest -n openshift-config get cm user-ca-bundle -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null | fp)"
  [ "${got}" = "${CA_FP}" ] && r=ok || r=ko; check "guest openshift-config/user-ca-bundle == mirror CA" "$r" "got '${got}'"
  NODE="${NODE:-$(guest get nodes -o jsonpath='{.items[0].metadata.name}')}"
  echo "INFO  node under test: ${NODE}"
  conf="$(node_sh "${NODE}" 'cat /etc/containers/registries.conf')"
  if grep -qF "location = \"${VIRTUAL_REPO}\"" <<<"${conf}" && grep -qF "location = \"${HOST}/${VIRTUAL_REPO}\"" <<<"${conf}"; then r=ok; else r=ko; fi
  check "node registries.conf maps ${VIRTUAL_REPO} → mirror" "$r" "see 'cat /etc/containers/registries.conf'"
  grep -qE 'pull-from-mirror = "digest-only"|mirror-by-digest-only = true' <<<"${conf}" && r=ok || r=ko
  check "node registries.conf mirror is digest-only" "$r" "no digest-only marker"
  got="$(node_sh "${NODE}" 'cat /etc/pki/ca-trust/source/anchors/openshift-config-user-ca-bundle.crt' | fp)"
  [ "${got}" = "${CA_FP}" ] && r=ok || r=ko; check "node trust anchor == mirror CA" "$r" "got '${got}'"
  got="$(node_sh "${NODE}" "curl -sS -w ' %{http_code}' https://${HOST}/v2/")"
  [ "${got}" = "{} 200" ] && r=ok || r=ko; check "node → https://${HOST}/v2/ with system trust → {} 200" "$r" "got '${got}'"
  ;;
pods)
  ready="$(guest -n "${GUEST_NS}" get pod "${POD_DIGEST}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)"
  [ "${ready}" = true ] && r=ok || r=ko; check "pod ${POD_DIGEST} (virtual repo @digest) Ready" "$r" "ready='${ready}'"
  img="$(guest -n "${GUEST_NS}" get pod "${POD_DIGEST}" -o jsonpath='{.spec.containers[0].image} {.spec.containers[0].imagePullPolicy}')"
  [ "${img}" = "${VIRTUAL_REPO}@${TEST_DIGEST} Always" ] && r=ok || r=ko; check "pod ${POD_DIGEST} image/pullPolicy" "$r" "got '${img}'"
  pulled="$(guest -n "${GUEST_NS}" get events --field-selector "involvedObject.name=${POD_DIGEST},reason=Pulled" -o jsonpath='{.items[*].message}')"
  grep -q 'Successfully pulled' <<<"${pulled}" && r=ok || r=ko; check "event Pulled 'Successfully pulled' for ${POD_DIGEST}" "$r" "got '${pulled}'"
  why="$(guest -n "${GUEST_NS}" get pod "${POD_TAG}" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)"
  case "${why}" in ErrImagePull|ImagePullBackOff) r=ok ;; *) r=ko ;; esac
  check "pod ${POD_TAG} (virtual repo :tag) fails to pull" "$r" "reason='${why}'"
  log="$(k -n "${NS}" logs "deploy/${NAME}" 2>/dev/null | grep 'cri-o')"
  n="$(grep -cF "/v2/${VIRTUAL_REPO}/manifests/" <<<"${log}")"
  n200="$(grep -F "/v2/${VIRTUAL_REPO}/manifests/" <<<"${log}" | grep -cE 'http.response.status=200|" 200 ')"
  [ "${n200}" -gt 0 ] && r=ok || r=ko; check "mirror log: CRI-O GET ${VIRTUAL_REPO} manifests → 200 (${n200}/${n} lines)" "$r" "none"
  n="$(grep -cF "/v2/${VIRTUAL_REPO}/manifests/2.8.2" <<<"${log}")"
  [ "${n}" = 0 ] && r=ok || r=ko; check "mirror log: no tag lookups (digest-only)" "$r" "${n} lines"
  ;;
*) echo "unknown phase ${PHASE}"; exit 2 ;;
esac
echo "check ${PHASE}: ${fails} failure(s)"
exit "${fails}"
