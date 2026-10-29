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

destination="$(new_run_dir "${EVIDENCE_ROOT}/t2" config)"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
np="${PATCHED_NODEPOOL}"
run_stamp="$(utc_stamp | tr '[:upper:]' '[:lower:]')"
marker="CNTRLPLANE-4826-T2-R4-${run_stamp}"
configmap_name="test-cntrlplane-4826-t2-mc-${run_stamp}"
daemonset_name="test-cntrlplane-4826-t2-verify-${run_stamp}"

snapshot_pool "${np}" "${destination}/pre" "${GUEST_KUBECONFIG}"
pre_summary="${destination}/pre/summary.json"
assert_pool_stable "${pre_summary}" "${RELEASE_B}" "${target_version}"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${pre_summary}")"
pre_platform="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"
pre_version="$(jq -r '.nodePool.version' "${pre_summary}")"
[[ -n "${pre_config}" && -n "${pre_config_version}" && -n "${pre_platform}" ]] || die "pre-state annotations are incomplete"

verification_image="$(verification_image_for_pool "${GUEST_KUBECONFIG}" "${np}")"
[[ -n "${verification_image}" ]] || die "could not find an image on the guest pool"
printf '%s\n' "${verification_image}" >"${destination}/verification-image.txt"

cat >"${destination}/machineconfig.yaml" <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: ${configmap_name}
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/custom-config
        mode: 420
        overwrite: true
        contents:
          source: data:,${marker}
EOF

kubectl create configmap "${configmap_name}" -n "${CLUSTER_NAMESPACE}" --from-file=config="${destination}/machineconfig.yaml" >"${destination}/create-configmap.out"

mkdir -p "${destination}/watch"
watch_deadline_epoch=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${np}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-rollout.log" 2>&1 &
rollout_pid=$!
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${np}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-machine-join.log" 2>&1 &
join_pid=$!
cleanup() {
  kill "${rollout_pid}" "${join_pid}" 2>/dev/null || true
  wait "${rollout_pid}" "${join_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 5
patch_epoch="$(date +%s)"
deadline_epoch=$(( patch_epoch + 1800 ))
patch_utc="$(date -u -r "${patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
deadline_utc="$(date -u -r "${deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${np}" "${CLUSTER_NAMESPACE}" "{\"spec\":{\"config\":[{\"name\":\"${configmap_name}\"}]}}" >"${destination}/commands.txt"
kubectl patch nodepool "${np}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "{\"spec\":{\"config\":[{\"name\":\"${configmap_name}\"}]}}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg configmap "${configmap_name}" --argjson previous "${pre_generation}" '.spec.config[0].name == $configmap and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool config patch did not produce exactly one generation change"

snapshot_pool "${np}" "${destination}/action" "${GUEST_KUBECONFIG}"

success_epoch=""
final_state='{}'
premature_count=0
premature_streak=0
max_premature_streak=0
version_changed_count=0
platform_changed_count=0
while :; do
  now_epoch="$(date +%s)"
  state="$(pool_state "${np}" "${GUEST_KUBECONFIG}")"
  printf '%s\n' "${state}" >>"${destination}/monitor-state.ndjson"

  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${state}")"
  current_config_version="$(jq -r '.nodePool.currentConfigVersion // ""' <<<"${state}")"
  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${state}")"

  if [[ "${current_config}" != "${pre_config}" || "${current_config_version}" != "${pre_config_version}" ]]; then
    if [[ "${physical_complete}" != "true" ]]; then
      printf '%s\n' "${state}" >>"${destination}/premature-completion.ndjson"
      premature_count=$(( premature_count + 1 ))
      premature_streak=$(( premature_streak + 1 ))
      if [[ "${premature_streak}" -gt "${max_premature_streak}" ]]; then max_premature_streak="${premature_streak}"; fi
    else
      premature_streak=0
    fi
  else
    premature_streak=0
  fi

  if [[ "${status_version}" != "${pre_version}" ]]; then
    printf '%s\n' "${state}" >>"${destination}/version-changed.ndjson"
    version_changed_count=$(( version_changed_count + 1 ))
  fi
  if [[ "${platform_template}" != "${pre_platform}" ]]; then
    printf '%s\n' "${state}" >>"${destination}/platform-changed.ndjson"
    platform_changed_count=$(( platform_changed_count + 1 ))
  fi

  if [[ "${physical_complete}" == "true" && "${current_config}" != "${pre_config}" && "${current_config_version}" != "${pre_config_version}" && "${updating_config}" == "False" && "${updating_version}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" && "${platform_template}" == "${pre_platform}" && "${up_to_date}" == "0" ]]; then
    success_epoch="$(date +%s)"
    printf '%s\n' "${success_epoch}" >"${destination}/success-epoch.txt"
    final_state="${state}"
    break
  fi

  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    final_state="${state}"
    break
  fi
  sleep 15
done

cleanup
trap - EXIT INT TERM

snapshot_pool "${np}" "${destination}/final" "${GUEST_KUBECONFIG}"
final_summary="${destination}/final/summary.json"

if [[ -z "${success_epoch}" ]]; then
  write_verdict "${destination}" "T2 config-only Replace rollout" "FAIL" '[{"name":"config rollout completed within deadline","passed":false,"detail":"No success state was observed within 1800 seconds."}]' "Config-only rollout did not complete; see monitor-state.ndjson and deadline snapshot."
  finalize_evidence "${destination}"
  printf 'config rollout did not complete within 1800 seconds\n' >&2
  exit 1
fi

marker_count=0
mkdir -p "${destination}/verification-logs"
if kubectl --kubeconfig "${GUEST_KUBECONFIG}" create -f - >"${destination}/create-verification-daemonset.out" 2>&1 <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${daemonset_name}
  namespace: default
  labels:
    app: ${daemonset_name}
spec:
  selector:
    matchLabels:
      app: ${daemonset_name}
  template:
    metadata:
      labels:
        app: ${daemonset_name}
    spec:
      nodeSelector:
        hypershift.openshift.io/nodePool: ${np}
      tolerations:
      - operator: Exists
      containers:
      - name: verify
        image: ${verification_image}
        command: ["/bin/sh", "-c", "cat /host/etc/custom-config; sleep infinity"]
        volumeMounts:
        - name: custom-config
          mountPath: /host/etc/custom-config
          readOnly: true
      volumes:
      - name: custom-config
        hostPath:
          path: /etc/custom-config
          type: File
EOF
then
  kubectl --kubeconfig "${GUEST_KUBECONFIG}" rollout status daemonset "${daemonset_name}" -n default --timeout=10m >"${destination}/verification-rollout-status.out" 2>&1 || true
  kubectl --kubeconfig "${GUEST_KUBECONFIG}" get daemonset "${daemonset_name}" -n default -o json >"${destination}/verification-daemonset.json" 2>&1 || true
  kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pods -n default -l "app=${daemonset_name}" -o json >"${destination}/verification-pods.json" 2>&1 || true
  : >"${destination}/marker-per-worker.tsv"
  for pod in $(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pods -n default -l "app=${daemonset_name}" -o json 2>/dev/null | jq -r '.items[].metadata.name'); do
    node_name="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pod "${pod}" -n default -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"
    kubectl --kubeconfig "${GUEST_KUBECONFIG}" logs "${pod}" -n default >"${destination}/verification-logs/${pod}.log" 2>&1 || true
    kubectl --kubeconfig "${GUEST_KUBECONFIG}" exec "${pod}" -n default -c verify -- cat /host/etc/custom-config >"${destination}/verification-logs/${pod}.exec" 2>&1 || true
    log_ok=false
    exec_ok=false
    grep -qF "${marker}" "${destination}/verification-logs/${pod}.log" 2>/dev/null && log_ok=true
    grep -qF "${marker}" "${destination}/verification-logs/${pod}.exec" 2>/dev/null && exec_ok=true
    if [[ "${exec_ok}" == "true" || "${log_ok}" == "true" ]]; then marker_count=$(( marker_count + 1 )); fi
    printf '%s\t%s\t%s\t%s\n' "${pod}" "${node_name}" "${log_ok}" "${exec_ok}" >>"${destination}/marker-per-worker.tsv"
  done
fi

final_generation="$(jq -r '.nodePool.generation' "${final_summary}")"
final_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${final_summary}")"
final_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${final_summary}")"
final_platform="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${final_summary}")"
final_version="$(jq -r '.nodePool.version' "${final_summary}")"
final_updating_config="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingConfig") | .status' "${final_summary}")"
final_updating_version="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingVersion") | .status' "${final_summary}")"
final_updating_platform="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingPlatformMachineTemplate") | .status' "${final_summary}")"
final_up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' "${final_summary}")"
final_guest_version="$(jq -r '.status.desired.version // ""' "${destination}/final/guest-clusterversion.json")"

c_generation=false; [[ "${final_generation}" -eq $(( pre_generation + 1 )) ]] && c_generation=true
c_config=false; [[ "${final_config}" != "${pre_config}" && "${final_config_version}" != "${pre_config_version}" ]] && c_config=true
c_config_cleared=false; [[ "${final_updating_config}" == "False" ]] && c_config_cleared=true
c_version_unchanged=false; [[ "${final_version}" == "${pre_version}" && "${version_changed_count}" -eq 0 && "${final_guest_version}" == "${target_version}" ]] && c_version_unchanged=true
c_platform_unchanged=false; [[ "${final_platform}" == "${pre_platform}" && "${platform_changed_count}" -eq 0 ]] && c_platform_unchanged=true
c_physical=false; [[ "$(jq -r '.physicalRolloutComplete' <<<"${final_state}")" == "true" ]] && c_physical=true
c_zero=false; [[ "${final_up_to_date}" == "0" ]] && c_zero=true
c_premature=false; [[ "${max_premature_streak}" -eq 0 ]] && c_premature=true
c_marker=false; [[ "${marker_count}" -eq 3 ]] && c_marker=true
c_operator=false; [[ "${actual_operator_image}" == "${PATCHED_IMAGE}" ]] && c_operator=true
c_release=false; [[ "$(jq -r '.nodePool.release' "${final_summary}")" == "${RELEASE_B}" ]] && c_release=true

checks="$(jq -n \
  --argjson generation "${c_generation}" --arg generationDetail "generation ${pre_generation} -> ${final_generation}" \
  --argjson config "${c_config}" --arg configDetail "${pre_config}/${pre_config_version} -> ${final_config}/${final_config_version}" \
  --argjson configCleared "${c_config_cleared}" --arg configClearedDetail "UpdatingConfig=${final_updating_config}" \
  --argjson versionUnchanged "${c_version_unchanged}" --arg versionDetail "status.version=${final_version}, guest=${final_guest_version}, changedObservations=${version_changed_count}" \
  --argjson platformUnchanged "${c_platform_unchanged}" --arg platformDetail "platform template ${pre_platform} -> ${final_platform}, changedObservations=${platform_changed_count}" \
  --argjson physical "${c_physical}" --arg physicalDetail "physicalRolloutComplete=$(jq -r '.physicalRolloutComplete' <<<"${final_state}")" \
  --argjson zero "${c_zero}" --arg zeroDetail "upToDateReplicas=${final_up_to_date}" \
  --argjson premature "${c_premature}" --arg prematureDetail "premature observations=${premature_count}, max consecutive=${max_premature_streak}" \
  --argjson marker "${c_marker}" --arg markerDetail "marker present on ${marker_count} of 3 workers" \
  --argjson operatorCheck "${c_operator}" --arg operatorDetail "${actual_operator_image}" \
  --argjson releaseCheck "${c_release}" --arg releaseDetail "$(jq -r '.nodePool.release' "${final_summary}")" \
  '[{name:"NodePool generation advanced by one",passed:$generation,detail:$generationDetail},
    {name:"config and config-version annotations advanced",passed:$config,detail:$configDetail},
    {name:"UpdatingConfig cleared",passed:$configCleared,detail:$configClearedDetail},
    {name:"release version unchanged",passed:$versionUnchanged,detail:$versionDetail},
    {name:"platform template unchanged",passed:$platformUnchanged,detail:$platformDetail},
    {name:"physical rollout complete",passed:$physical,detail:$physicalDetail},
    {name:"upToDateReplicas zero",passed:$zero,detail:$zeroDetail},
    {name:"no premature completion metadata",passed:$premature,detail:$prematureDetail},
    {name:"marker verified on every worker",passed:$marker,detail:$markerDetail},
    {name:"head operator image",passed:$operatorCheck,detail:$operatorDetail},
    {name:"release B fixed",passed:$releaseCheck,detail:$releaseDetail}]')"

result="PASS"
if [[ "${max_premature_streak}" -gt 0 ]]; then result="FAIL"; fi
if [[ "${marker_count}" -ne 3 ]]; then result="FAIL"; fi
if [[ "${c_generation}" != "true" || "${c_config}" != "true" || "${c_config_cleared}" != "true" || "${c_version_unchanged}" != "true" || "${c_platform_unchanged}" != "true" || "${c_physical}" != "true" || "${c_zero}" != "true" || "${c_operator}" != "true" || "${c_release}" != "true" ]]; then result="FAIL"; fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=config-only
nodepool=${CLUSTER_NAMESPACE}/${np}
hostedcluster=${CLUSTER_NAMESPACE}/${CLUSTER_NAME}
marker=${marker}
configmap=${CLUSTER_NAMESPACE}/${configmap_name}
daemonset=default/${daemonset_name}
preGeneration=${pre_generation}
preStatusVersion=${pre_version}
preSpecRelease=$(jq -r '.nodePool.release' "${pre_summary}")
preCurrentConfig=${pre_config}
preCurrentConfigVersion=${pre_config_version}
prePlatformMachineTemplate=${pre_platform}
targetVersion=${target_version}
operatorImage=${actual_operator_image}
patchUtc=${patch_utc}
deadlineUtc=${deadline_utc}
deadlineSeconds=1800
successEpoch=${success_epoch}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
elapsedSeconds=$(( completed_epoch - patch_epoch ))
result=${result}
prematureObservations=${premature_count}
maxPrematureStreak=${max_premature_streak}
markerWorkers=${marker_count}
EOF

write_verdict "${destination}" "T2 config-only Replace rollout" "${result}" "${checks}" "Config-only MachineConfig rollout on the head operator. ${premature_count} premature annotation observation(s), max consecutive ${max_premature_streak}. Marker verified on ${marker_count} of 3 workers. upToDateReplicas=${final_up_to_date}."
finalize_evidence "${destination}"

if [[ "${result}" != "PASS" ]]; then
  printf 'T2 failed: see %s/verdict.json\n' "${destination}" >&2
  exit 1
fi
printf '%s\n' "${destination}"
