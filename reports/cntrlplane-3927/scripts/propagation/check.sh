#!/usr/bin/env bash
# CNTRLPLANE-3927 live checks, one PASS/FAIL line each. Source env.sh first.
#   check.sh fixture  mirror fixture + SHARED_DIR files written by create-guests PreCreate, Keycloak ready
#   check.sh hc       HostedCluster: ICS == fixture ICS, trust bundle == fixture CA, Available, rollout Completed
#   check.sh junit    run-tests JUnit: exactly the two 3927 specs, passed, nothing skipped/failed
#   check.sh guest    hosted IDMS cluster: worker label, mappings == HC   (independent of the Go test code)
#   check.sh cm       HCP ignition ConfigMap: core label, decoded IDMS == HC (independent of the Go test code)
#   check.sh clean    after step 6: no HC/HCP/AWS leftovers, fixture namespaces and mirror PV gone
# Mapping comparisons ignore the order of entries but keep mirror order (what the specs assert).
set -u
: "${CTX:?source env.sh first}" "${AWS_CREDS:?}" "${SHARED:?}" "${ARTIFACTS:?}" "${HC_NAME:?}" "${HC_NS:?}" "${HCP_NS:?}" "${HOST:?}"
PHASE="${1:?usage: check.sh fixture|hc|junit|guest|cm|clean}"
fails=0
check() { if [ "$2" = ok ]; then echo "PASS  $1"; else echo "FAIL  $1  ($3)"; fails=$((fails + 1)); fi; }
k() { oc --context "${CTX}" "$@"; }
guest() { oc --kubeconfig "${GUEST_KUBECONFIG}" "$@"; }
fp() { openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }   # first cert on stdin
norm='map({source, mirrors}) | sort_by(.source)'                             # jq: entries unordered, mirrors ordered
# AWS CLI with the same identity create-guests uses (default profile of $AWS_CREDS, no ambient keys).
awsx() { env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDS}" aws "$@"; }
hc_ics() { k -n "${HC_NS}" get hostedcluster "${HC_NAME}" -o json | jq -c ".spec.imageContentSources // [] | ${norm}"; }
want_idms() {   # $1 = IDMS JSON, $2 = label, $3 = expected normalized mappings; shared by guest and cm
  local obj="$1" what="$2" want="$3"
  got="$(jq -r '"\(.apiVersion) \(.kind) \(.metadata.name) ns=\(.metadata.namespace // "")"' <<<"${obj}")"
  [ "${got}" = "config.openshift.io/v1 ImageDigestMirrorSet cluster ns=" ] && r=ok || r=ko
  check "${what}: config.openshift.io/v1 ImageDigestMirrorSet 'cluster', cluster-scoped" "$r" "got '${got}'"
  got="$(jq -r '.metadata.labels["machineconfiguration.openshift.io/role"] // empty' <<<"${obj}")"
  [ "${got}" = worker ] && r=ok || r=ko; check "${what}: label machineconfiguration.openshift.io/role=worker" "$r" "got '${got}'"
  got="$(jq -c ".spec.imageDigestMirrors // [] | ${norm}" <<<"${obj}")"
  [ "${got}" = "${want}" ] && r=ok || r=ko; check "${what}: mappings == HC imageContentSources (mirror order kept)" "$r" "got ${got} want ${want}"
}
SPEC1='[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring should propagate imageContentSources to the hosted cluster IDMS with the worker role'
SPEC2='[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring should propagate imageContentSources independently to the control plane ignition ConfigMap'

case "${PHASE}" in
fixture)
  for f in cluster-manifests.json mirror-registry-ca.pem mirror-registry-ics.yaml mirror-registry.json; do
    [ -s "${SHARED}/${f}" ] && r=ok || r=ko; check "SHARED_DIR/${f} written" "$r" "missing/empty"
  done
  jq -e --arg n "${HC_NAME}" --arg ns "${HC_NS}" \
    '.clusters == [{variant:"image-mirroring",name:$n,infraID:$n,namespace:$ns}]' "${SHARED}/cluster-manifests.json" >/dev/null 2>&1 && r=ok || r=ko
  check "manifest: exactly one cluster, image-mirroring ${HC_NS}/${HC_NAME}" "$r" "$(jq -c .clusters "${SHARED}/cluster-manifests.json" 2>/dev/null)"
  got="$(k -n "${NS}" get route "${NAME}" -o jsonpath='{.spec.host} {.spec.tls.termination}' 2>/dev/null)"
  [ "${got}" = "${HOST} passthrough" ] && r=ok || r=ko; check "Route ${NS}/${NAME} host + passthrough" "$r" "got '${got}'"
  got="$(jq -r .Host "${SHARED}/mirror-registry.json" 2>/dev/null)"
  [ "${got}" = "${HOST}" ] && r=ok || r=ko; check "mirror-registry.json Host == Route host" "$r" "got '${got}'"
  want="$(jq -nc --arg h "${HOST}" --arg a "${TEST_SRC_REPO}" --arg b "${VIRTUAL_REPO}" "[\$a, \$b] | map({source: ., mirrors: [\$h + \"/\" + .]}) | ${norm}")"
  got="$(yq -o=json '.' "${SHARED}/mirror-registry-ics.yaml" 2>/dev/null | jq -c "${norm}")"
  [ "${got}" = "${want}" ] && r=ok || r=ko; check "mirror-registry-ics.yaml: real + virtual repo → HOST/<source>" "$r" "got ${got}"
  got="$(k -n "${NS}" get deploy "${NAME}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  [ "${got}" = 1 ] && r=ok || r=ko; check "registry Deployment ready" "$r" "readyReplicas='${got}'"
  got="$(openssl x509 -in "${SHARED}/mirror-registry-ca.pem" -noout -subject 2>/dev/null)"
  grep -q 'hypershift-e2e-mirror-registry-ca' <<<"${got}" && r=ok || r=ko; check "CA subject hypershift-e2e-mirror-registry-ca" "$r" "got '${got}'"
  got="$(curl -sS --max-time 20 --cacert "${SHARED}/mirror-registry-ca.pem" -w ' %{http_code}' "https://${HOST}/v2/" 2>&1)"
  [ "${got}" = "{} 200" ] && r=ok || r=ko; check "laptop → https://${HOST}/v2/ trusting only the fixture CA → {} 200" "$r" "got '${got}'"
  got="$(k -n "${KC_NS}" get statefulset keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
  [ "${got}" = 1 ] && r=ok || r=ko; check "Keycloak StatefulSet ready (side effect of AWS PreCreate)" "$r" "readyReplicas='${got}'"
  ;;
hc)
  hc="$(k -n "${HC_NS}" get hostedcluster "${HC_NAME}" -o json 2>/dev/null)"
  want="$(yq -o=json '.' "${SHARED}/mirror-registry-ics.yaml" | jq -c "${norm}")"
  got="$(jq -c ".spec.imageContentSources // [] | ${norm}" <<<"${hc}")"
  [ -n "${got}" ] && [ "${got}" = "${want}" ] && r=ok || r=ko; check "HC spec.imageContentSources == SHARED_DIR ICS" "$r" "got ${got}"
  cm="$(jq -r '.spec.additionalTrustBundle.name // empty' <<<"${hc}")"
  got="$(k -n "${HC_NS}" get cm "${cm:-none}" -o jsonpath='{.data.ca-bundle\.crt}' 2>/dev/null | fp)"
  [ -n "${got}" ] && [ "${got}" = "$(fp < "${SHARED}/mirror-registry-ca.pem")" ] && r=ok || r=ko
  check "HC additionalTrustBundle (${cm:-unset}) == fixture CA" "$r" "got '${got}'"
  got="$(jq -r '.status.conditions[]? | select(.type == "Available") | .status' <<<"${hc}")"
  [ "${got}" = True ] && r=ok || r=ko; check "HC Available=True" "$r" "got '${got}'"
  got="$(jq -r '[.status.version.history[]?.state] | join(",")' <<<"${hc}")"
  jq -e '[.status.version.history[]?.state] | length > 0 and all(. == "Completed")' <<<"${hc}" >/dev/null 2>&1 && r=ok || r=ko
  check "HC version history all Completed (create-guests Phase 6)" "$r" "got '${got}'"
  ;;
junit)
  f="${ARTIFACTS}/junit_image-mirroring.xml"
  [ -s "${f}" ] && r=ok || r=ko; check "JUnit ${f##*/} exists" "$r" "missing"
  n="$(xmllint --xpath 'count(//testcase)' "${f}" 2>/dev/null)"
  [ "${n}" = 2 ] && r=ok || r=ko; check "exactly 2 testcases" "$r" "got '${n}'"
  for s in "${SPEC1}" "${SPEC2}"; do
    st="$(xmllint --xpath "string(//testcase[@name='${s}']/@status)" "${f}" 2>/dev/null)"
    [ "${st}" = passed ] && r=ok || r=ko; check "testcase passed: ...${s##*Mirroring }" "$r" "status='${st}'"
  done
  n="$(xmllint --xpath 'count(//testcase/failure|//testcase/error|//testcase/skipped)' "${f}" 2>/dev/null)"
  [ "${n}" = 0 ] && r=ok || r=ko; check "no failure/error/skipped elements" "$r" "got '${n}'"
  got="$(xmllint --xpath 'string(//property[@name="DryRun"]/@value)' "${f}" 2>/dev/null)"
  [ "${got}" = false ] && r=ok || r=ko; check "suite property DryRun=false (live run)" "$r" "got '${got}'"
  ;;
guest)
  : "${GUEST_KUBECONFIG:?}"
  want="$(hc_ics)"
  [ "${want}" != "[]" ] && r=ok || r=ko; check "HC has imageContentSources (non-vacuous oracle)" "$r" "empty"
  obj="$(guest get imagedigestmirrorset cluster -o json 2>/dev/null)"
  [ -n "${obj}" ] && r=ok || { r=ko; obj='{}'; }; check "hosted ImageDigestMirrorSet/cluster exists" "$r" "not readable"
  want_idms "${obj}" "hosted IDMS" "${want}"
  ;;
cm)
  want="$(hc_ics)"
  obj="$(k -n "${HCP_NS}" get cm ignition-config-40-image-content-source -o json 2>/dev/null)"
  [ -n "${obj}" ] && r=ok || { r=ko; obj='{}'; }; check "ConfigMap ${HCP_NS}/ignition-config-40-image-content-source exists" "$r" "not found"
  got="$(jq -r '.metadata.labels["hypershift.openshift.io/core-ignition-config"] // empty' <<<"${obj}")"
  [ "${got}" = true ] && r=ok || r=ko; check "CM label hypershift.openshift.io/core-ignition-config=true" "$r" "got '${got}'"
  payload="$(jq -r '.data.config // empty' <<<"${obj}" | yq -p=yaml -o=json '.' 2>/dev/null)"
  [ -n "${payload}" ] && [ "${payload}" != null ] && r=ok || { r=ko; payload='{}'; }; check "CM data.config decodes as YAML" "$r" "empty or invalid"
  want_idms "${payload}" "CM payload" "${want}"
  ;;
clean)
  got="$(k -n "${HC_NS}" get hostedcluster,nodepool -o name 2>/dev/null)"
  [ -z "${got}" ] && r=ok || r=ko; check "no HostedCluster/NodePool in ${HC_NS}" "$r" "${got}"
  for ns in "${HCP_NS}" "${NS}" "${KC_NS}"; do
    got="$(k get ns "${ns}" -o name 2>&1)"
    grep -q NotFound <<<"${got}" && r=ok || r=ko; check "namespace ${ns} gone" "$r" "${got}"
  done
  got="$(k get pv -o json | jq -r --arg ns "${NS}" '.items[] | select(.spec.claimRef.namespace == $ns) | .metadata.name')"
  [ -z "${got}" ] && r=ok || r=ko; check "no PV bound to ${NS}" "$r" "${got}"
  got="$(awsx ec2 describe-vpcs --region "${AWS_REGION}" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" --query 'Vpcs[].VpcId' --output text 2>&1)"
  [ -z "${got}" ] && r=ok || r=ko; check "no VPC tagged for ${INFRA_ID}" "$r" "${got}"
  got="$(awsx ec2 describe-instances --region "${AWS_REGION}" --filters "Name=tag:kubernetes.io/cluster/${INFRA_ID},Values=owned" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text 2>&1)"
  [ -z "${got}" ] && r=ok || r=ko; check "no live instance tagged for ${INFRA_ID}" "$r" "${got}"
  ;;
*) echo "unknown phase ${PHASE}"; exit 2 ;;
esac
echo "check ${PHASE}: ${fails} failure(s)"
exit "${fails}"
