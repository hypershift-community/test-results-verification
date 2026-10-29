#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=t-lib.sh
source "${SCRIPT_DIR}/t-lib.sh"

: "${GUEST_KUBECONFIG:?GUEST_KUBECONFIG is required}"
assert_management_kubeconfig
[[ -r "${GUEST_KUBECONFIG}" ]] || die "guest kubeconfig is not readable"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get --raw=/readyz >/dev/null || die "guest Kubernetes API is not ready"

actual_operator_image="$(kubectl get deployment operator -n hypershift -o jsonpath='{.spec.template.spec.containers[?(@.name=="operator")].image}')"
[[ "${actual_operator_image}" == "${PATCHED_IMAGE}" ]] || die "operator image is ${actual_operator_image}, expected ${PATCHED_IMAGE}"

destination="$(new_run_dir "${EVIDENCE_ROOT}/t6" scale)"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
np="${SCALE_NODEPOOL}"

if ! kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
  TEMPLATE_FILE="${SCRIPT_DIR}/nodepool-template.json" "${SCRIPT_DIR}/nodepool-create.sh" "${np}" "${RELEASE_B}" "${target_version}" 3 REPLACE --create >"${destination}/nodepool-create-path.txt"
fi

TIMEOUT_SECONDS=1800 EXPECTED_VERSION="${target_version}" NP="${np}" "${SCRIPT_DIR}/wait-nodepool-ready.sh" >"${destination}/wait-ready.log" 2>&1
snapshot_pool "${np}" "${destination}/pre-zero" "${GUEST_KUBECONFIG}"
pre_summary="${destination}/pre-zero/summary.json"
assert_pool_stable "${pre_summary}" "${RELEASE_B}" "${target_version}"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${pre_summary}")"
pre_platform="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"
pre_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_node_uids="$(jq -r '[.guestNodes[].uid] | sort | join(",")' "${pre_summary}")"
[[ -n "${pre_config}" && -n "${pre_config_version}" && -n "${pre_platform}" ]] || die "pre-state annotations are incomplete"

mkdir -p "${destination}/watch-zero"
zero_watch_deadline=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${zero_watch_deadline}" NP="${np}" OUT="${destination}/watch-zero" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-zero.log" 2>&1 &
zero_watch_pid=$!
cleanup_zero() {
  kill "${zero_watch_pid}" 2>/dev/null || true
  wait "${zero_watch_pid}" 2>/dev/null || true
}
trap cleanup_zero EXIT INT TERM

sleep 5
zero_patch_epoch="$(date +%s)"
zero_deadline_epoch=$(( zero_patch_epoch + 1800 ))
zero_patch_utc="$(date -u -r "${zero_patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
zero_deadline_utc="$(date -u -r "${zero_deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${np}" "${CLUSTER_NAMESPACE}" '{"spec":{"replicas":0}}' >"${destination}/commands-zero.txt"
kubectl patch nodepool "${np}" -n "${CLUSTER_NAMESPACE}" --type=merge -p '{"spec":{"replicas":0}}' >"${destination}/patch-zero.out"
post_zero_patch="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --argjson previous "${pre_generation}" '.spec.replicas == 0 and .metadata.generation == ($previous + 1)' <<<"${post_zero_patch}" >/dev/null || die "scale-to-zero did not produce exactly one generation change"

zero_success_epoch=""
zero_state='{}'
while :; do
  now_epoch="$(date +%s)"
  state="$(pool_state "${np}" "${GUEST_KUBECONFIG}")"
  printf '%s\n' "${state}" >>"${destination}/monitor-zero.ndjson"
  zero_complete="$(jq -r '.zeroComplete' <<<"${state}")"
  observed_ok="$(jq -r 'if .machineDeployment.observedGeneration == null or .machineDeployment.generation == null then false else (.machineDeployment.observedGeneration >= .machineDeployment.generation) end' <<<"${state}")"
  ready="$(jq -r '.nodePool.ready.status // ""' <<<"${state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${state}")"
  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${state}")"
  current_config_version="$(jq -r '.nodePool.currentConfigVersion // ""' <<<"${state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${state}")"
  if [[ "${zero_complete}" == "true" && "${observed_ok}" == "true" && "${ready}" == "True" && "${updating_version}" == "False" && "${updating_config}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${pre_version}" && "${current_config}" == "${pre_config}" && "${current_config_version}" == "${pre_config_version}" && "${platform_template}" == "${pre_platform}" ]]; then
    zero_success_epoch="$(date +%s)"
    printf '%s\n' "${zero_success_epoch}" >"${destination}/zero-success-epoch.txt"
    zero_state="${state}"
    break
  fi
  if [[ "${now_epoch}" -ge "${zero_deadline_epoch}" ]]; then
    zero_state="${state}"
    break
  fi
  sleep 15
done

cleanup_zero
trap - EXIT INT TERM
snapshot_pool "${np}" "${destination}/zero" "${GUEST_KUBECONFIG}"

if [[ -z "${zero_success_epoch}" ]]; then
  write_verdict "${destination}" "T6 scale-to-zero and scale-back" "FAIL" '[{"name":"scale-to-zero completed","passed":false,"detail":"No zero-desired success state within 1800 seconds."}]' "Scale-to-zero did not complete; see monitor-zero.ndjson and zero snapshot."
  finalize_evidence "${destination}"
  printf 'scale-to-zero did not complete within 1800 seconds\n' >&2
  exit 1
fi

zero_generation="$(jq -r '.nodePool.generation' "${destination}/zero/summary.json")"

mkdir -p "${destination}/watch-back"
back_watch_deadline=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${back_watch_deadline}" NP="${np}" OUT="${destination}/watch-back" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-back.log" 2>&1 &
back_watch_pid=$!
DEADLINE_EPOCH="${back_watch_deadline}" NP="${np}" OUT="${destination}/watch-back" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-back-join.log" 2>&1 &
back_join_pid=$!
cleanup_back() {
  kill "${back_watch_pid}" "${back_join_pid}" 2>/dev/null || true
  wait "${back_watch_pid}" "${back_join_pid}" 2>/dev/null || true
}
trap cleanup_back EXIT INT TERM

sleep 5
back_patch_epoch="$(date +%s)"
back_deadline_epoch=$(( back_patch_epoch + 1800 ))
back_patch_utc="$(date -u -r "${back_patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
back_deadline_utc="$(date -u -r "${back_deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${np}" "${CLUSTER_NAMESPACE}" '{"spec":{"replicas":3}}' >"${destination}/commands-back.txt"
kubectl patch nodepool "${np}" -n "${CLUSTER_NAMESPACE}" --type=merge -p '{"spec":{"replicas":3}}' >"${destination}/patch-back.out"
post_back_patch="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --argjson previous "${zero_generation}" '.spec.replicas == 3 and .metadata.generation == ($previous + 1)' <<<"${post_back_patch}" >/dev/null || die "scale-back did not produce exactly one generation change"

back_success_epoch=""
back_state='{}'
while :; do
  now_epoch="$(date +%s)"
  state="$(pool_state "${np}" "${GUEST_KUBECONFIG}")"
  printf '%s\n' "${state}" >>"${destination}/monitor-back.ndjson"
  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${state}")"
  ready="$(jq -r '.nodePool.ready.status // ""' <<<"${state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${state}")"
  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${state}")"
  current_config_version="$(jq -r '.nodePool.currentConfigVersion // ""' <<<"${state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${state}")"
  if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && "${ready}" == "True" && "${updating_version}" == "False" && "${updating_config}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${pre_version}" && "${current_config}" == "${pre_config}" && "${current_config_version}" == "${pre_config_version}" && "${platform_template}" == "${pre_platform}" ]]; then
    back_success_epoch="$(date +%s)"
    printf '%s\n' "${back_success_epoch}" >"${destination}/back-success-epoch.txt"
    back_state="${state}"
    break
  fi
  if [[ "${now_epoch}" -ge "${back_deadline_epoch}" ]]; then
    back_state="${state}"
    break
  fi
  sleep 15
done

cleanup_back
trap - EXIT INT TERM
snapshot_pool "${np}" "${destination}/back" "${GUEST_KUBECONFIG}"

if [[ -z "${back_success_epoch}" ]]; then
  write_verdict "${destination}" "T6 scale-to-zero and scale-back" "FAIL" '[{"name":"scale-back completed","passed":false,"detail":"No three-replica success state within 1800 seconds after scale-back."}]' "Scale-back did not complete; see monitor-back.ndjson and back snapshot."
  finalize_evidence "${destination}"
  printf 'scale-back did not complete within 1800 seconds\n' >&2
  exit 1
fi

zero_summary="${destination}/zero/summary.json"
back_summary="${destination}/back/summary.json"
zero_md_replicas="$(jq -r '.machineDeployment.replicas' "${zero_summary}")"
zero_md_available="$(jq -r '.machineDeployment.availableReplicas' "${zero_summary}")"
zero_machines="$(jq -r '.ownedMachines | length' "${zero_summary}")"
zero_nodes="$(jq -r '.guestNodes | length' "${zero_summary}")"
zero_current_set_name="$(jq -r '.currentMachineSet.name // ""' <<<"${zero_state}")"
zero_current_set_replicas="$(jq -r '.currentMachineSet.replicas // 0' <<<"${zero_state}")"
back_md_replicas="$(jq -r '.machineDeployment.replicas' "${back_summary}")"
back_md_available="$(jq -r '.machineDeployment.availableReplicas' "${back_summary}")"
back_nodes="$(jq -r '.guestNodes | length' "${back_summary}")"
back_node_uids="$(jq -r '[.guestNodes[].uid] | sort | join(",")' "${back_summary}")"
replaced_nodes=false
if [[ -n "${pre_node_uids}" && -n "${back_node_uids}" && "${pre_node_uids}" != "${back_node_uids}" ]]; then replaced_nodes=true; fi

join_violations=0
if [[ -f "${destination}/watch-back/machine-join-threshold.ndjson" ]]; then
  join_violations="$(jq -s '[.[] | (.violations // []) | length] | add // 0' "${destination}/watch-back/machine-join-threshold.ndjson")"
fi

zero_ready_reason="$(jq -r '.nodePool.conditions[] | select(.type == "Ready") | .reason' "${zero_summary}")"
back_up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' "${back_summary}")"

c_zero_inventory=false; [[ "${zero_md_replicas}" == "0" && "${zero_md_available}" == "0" && "${zero_machines}" == "0" && "${zero_nodes}" == "0" ]] && c_zero_inventory=true
c_zero_metadata=false; [[ "${zero_current_set_replicas}" == "0" && "$(jq -r '.nodePool.version' "${zero_summary}")" == "${pre_version}" && "$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"]' "${zero_summary}")" == "${pre_config}" && "$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"]' "${zero_summary}")" == "${pre_platform}" ]] && c_zero_metadata=true
c_back_complete=false; [[ "${back_md_replicas}" == "3" && "${back_md_available}" == "3" && "${back_nodes}" == "3" && "${back_up_to_date}" == "0" ]] && c_back_complete=true
c_replaced=false; [[ "${replaced_nodes}" == "true" ]] && c_replaced=true
c_join=false; [[ "${join_violations}" -eq 0 ]] && c_join=true
c_operator=false; [[ "${actual_operator_image}" == "${PATCHED_IMAGE}" ]] && c_operator=true

checks="$(jq -n \
  --argjson zeroInventory "${c_zero_inventory}" --arg zeroInventoryDetail "replicas=${zero_md_replicas}/${zero_md_available}, machines=${zero_machines}, nodes=${zero_nodes}" \
  --argjson zeroMetadata "${c_zero_metadata}" --arg zeroMetadataDetail "currentMachineSet=${zero_current_set_name} replicas=${zero_current_set_replicas}, version/config/platform unchanged" \
  --argjson backComplete "${c_back_complete}" --arg backCompleteDetail "replicas=${back_md_replicas}/${back_md_available}, nodes=${back_nodes}, upToDateReplicas=${back_up_to_date}" \
  --argjson replaced "${c_replaced}" --arg replacedDetail "pre node UIDs=${pre_node_uids}; back node UIDs=${back_node_uids}" \
  --argjson join "${c_join}" --arg joinDetail "12-minute join violations=${join_violations}" \
  --argjson operatorCheck "${c_operator}" --arg operatorDetail "${actual_operator_image}" \
  '[{name:"scale-to-zero inventory empty",passed:$zeroInventory,detail:$zeroInventoryDetail},
    {name:"zero-state metadata stable",passed:$zeroMetadata,detail:$zeroMetadataDetail},
    {name:"scale-back complete at three replicas",passed:$backComplete,detail:$backCompleteDetail},
    {name:"back workers are new identities",passed:$replaced,detail:$replacedDetail},
    {name:"workers joined within 12 minutes",passed:$join,detail:$joinDetail},
    {name:"head operator image",passed:$operatorCheck,detail:$operatorDetail}]')"

result="PASS"
if [[ "${c_zero_inventory}" != "true" || "${c_zero_metadata}" != "true" || "${c_back_complete}" != "true" || "${c_replaced}" != "true" || "${c_join}" != "true" || "${c_operator}" != "true" ]]; then result="FAIL"; fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=scale-zero-back
nodepool=${CLUSTER_NAMESPACE}/${np}
hostedcluster=${CLUSTER_NAMESPACE}/${CLUSTER_NAME}
preGeneration=${pre_generation}
preStatusVersion=${pre_version}
preSpecRelease=$(jq -r '.nodePool.release' "${pre_summary}")
preCurrentConfig=${pre_config}
preCurrentConfigVersion=${pre_config_version}
prePlatformMachineTemplate=${pre_platform}
targetVersion=${target_version}
zeroGeneration=${zero_generation}
zeroPatchUtc=${zero_patch_utc}
zeroDeadlineUtc=${zero_deadline_utc}
zeroSuccessEpoch=${zero_success_epoch}
zeroReadyReason=${zero_ready_reason}
zeroMachineDeploymentReplicas=${zero_md_replicas}
zeroMachineDeploymentAvailable=${zero_md_available}
zeroMachines=${zero_machines}
zeroNodes=${zero_nodes}
zeroCurrentMachineSet=${zero_current_set_name}
zeroCurrentMachineSetReplicas=${zero_current_set_replicas}
backPatchUtc=${back_patch_utc}
backDeadlineUtc=${back_deadline_utc}
backSuccessEpoch=${back_success_epoch}
backMachineDeploymentReplicas=${back_md_replicas}
backMachineDeploymentAvailable=${back_md_available}
backNodes=${back_nodes}
backUpToDateReplicas=${back_up_to_date}
operatorImage=${actual_operator_image}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
elapsedSeconds=$(( completed_epoch - zero_patch_epoch ))
result=${result}
joinViolations=${join_violations}
nodeIdentitiesReplaced=${replaced_nodes}
EOF

write_verdict "${destination}" "T6 scale-to-zero and scale-back" "${result}" "${checks}" "Regression check only: no release/config/platform change was in flight. Zero state retained current MachineSet ${zero_current_set_name} at ${zero_current_set_replicas} replicas; the desired=0 branch without a current MachineSet is covered only by unit tests. Scale-back nodes replaced identities: ${replaced_nodes}."
finalize_evidence "${destination}"

if [[ "${result}" != "PASS" ]]; then
  printf 'T6 failed: see %s/verdict.json\n' "${destination}" >&2
  exit 1
fi
printf '%s\n' "${destination}"
