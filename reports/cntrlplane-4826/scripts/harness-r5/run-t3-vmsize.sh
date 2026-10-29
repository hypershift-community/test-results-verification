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

destination="$(new_run_dir "${EVIDENCE_ROOT}/t3" vm-size)"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
target_vm_size="Standard_D4s_v4"
np="${PATCHED_NODEPOOL}"

snapshot_pool "${np}" "${destination}/pre" "${GUEST_KUBECONFIG}"
pre_summary="${destination}/pre/summary.json"
assert_pool_stable "${pre_summary}" "${RELEASE_B}" "${target_version}"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${pre_summary}")"
pre_platform="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"
pre_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_vm_size="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o jsonpath='{.spec.platform.azure.vmSize}')"
[[ "${pre_vm_size}" == "Standard_D4s_v5" ]] || die "expected pre-test vmSize Standard_D4s_v5, found ${pre_vm_size}"
[[ -n "${pre_config}" && -n "${pre_config_version}" && -n "${pre_platform}" ]] || die "pre-state annotations are incomplete"

kubectl get azuremachinetemplates.infrastructure.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${destination}/pre/azuremachinetemplates.json"

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
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${np}" "${CLUSTER_NAMESPACE}" "{\"spec\":{\"platform\":{\"azure\":{\"vmSize\":\"${target_vm_size}\"}}}}" >"${destination}/commands.txt"
kubectl patch nodepool "${np}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "{\"spec\":{\"platform\":{\"azure\":{\"vmSize\":\"${target_vm_size}\"}}}}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg vmSize "${target_vm_size}" --argjson previous "${pre_generation}" '.spec.platform.azure.vmSize == $vmSize and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool VM-size patch did not produce exactly one generation change"

snapshot_pool "${np}" "${destination}/action" "${GUEST_KUBECONFIG}"

success_epoch=""
final_state='{}'
premature_count=0
premature_streak=0
max_premature_streak=0
config_changed_count=0
version_changed_count=0
while :; do
  now_epoch="$(date +%s)"
  state="$(pool_state "${np}" "${GUEST_KUBECONFIG}")"
  printf '%s\n' "${state}" >>"${destination}/monitor-state.ndjson"

  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${state}")"
  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${state}")"
  current_config_version="$(jq -r '.nodePool.currentConfigVersion // ""' <<<"${state}")"
  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${state}")"
  azure_count="$(jq -r '[.azureMachines[]?] | length' <<<"${state}")"
  azure_target_count="$(jq -r --arg size "${target_vm_size}" '[.azureMachines[]? | select(.vmSize == $size)] | length' <<<"${state}")"

  if [[ "${platform_template}" != "${pre_platform}" && "${physical_complete}" != "true" ]]; then
    printf '%s\n' "${state}" >>"${destination}/premature-completion.ndjson"
    premature_count=$(( premature_count + 1 ))
    premature_streak=$(( premature_streak + 1 ))
    if [[ "${premature_streak}" -gt "${max_premature_streak}" ]]; then max_premature_streak="${premature_streak}"; fi
  else
    premature_streak=0
  fi

  if [[ "${current_config}" != "${pre_config}" || "${current_config_version}" != "${pre_config_version}" ]]; then
    printf '%s\n' "${state}" >>"${destination}/config-changed.ndjson"
    config_changed_count=$(( config_changed_count + 1 ))
  fi
  if [[ "${status_version}" != "${pre_version}" ]]; then
    printf '%s\n' "${state}" >>"${destination}/version-changed.ndjson"
    version_changed_count=$(( version_changed_count + 1 ))
  fi

  if [[ "${physical_complete}" == "true" && "${platform_template}" != "${pre_platform}" && "${current_config}" == "${pre_config}" && "${current_config_version}" == "${pre_config_version}" && "${updating_config}" == "False" && "${updating_version}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" && "${up_to_date}" == "0" && "${azure_count}" -eq 3 && "${azure_target_count}" -eq 3 ]]; then
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
kubectl get azuremachinetemplates.infrastructure.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${destination}/final/azuremachinetemplates.json"

if [[ -z "${success_epoch}" ]]; then
  write_verdict "${destination}" "T3 infrastructure-template-only Replace rollout" "FAIL" '[{"name":"VM-size rollout completed within deadline","passed":false,"detail":"No success state was observed within 1800 seconds."}]' "VM-size rollout did not complete; see monitor-state.ndjson and final snapshot."
  finalize_evidence "${destination}"
  printf 'VM-size rollout did not complete within 1800 seconds\n' >&2
  exit 1
fi

md_name="$(cat "${destination}/final/machinedeployment-name.txt")"
md_infra_ref="$(jq -r --arg md "${md_name}" '.items[] | select(.metadata.name == $md) | .spec.template.spec.infrastructureRef.name' "${destination}/final/machinedeployments.json")"
md_template_vm_size="$(jq -r --arg name "${md_infra_ref}" '.items[] | select(.metadata.name == $name) | .spec.template.spec.vmSize' "${destination}/final/azuremachinetemplates.json")"
printf '%s\n' "${md_infra_ref}" >"${destination}/machineDeployment-infrastructureRef.txt"
printf '%s\n' "${md_template_vm_size}" >"${destination}/machine-deployment-template-vmSize.txt"

mkdir -p "${destination}/azure-vm-verification"
azure_vm_verified=0
azure_vm_failed=0
: >"${destination}/azure-vm-verification/results.tsv"
for row in $(jq -r '.azureMachines[]? | @base64' <<<"${final_state}"); do
  machine_name="$(jq -r '.name' <<<"$(printf '%s' "${row}" | base64 -d)")"
  provider_id="$(jq -r '.providerID // ""' <<<"$(printf '%s' "${row}" | base64 -d)")"
  spec_vm_size="$(jq -r '.vmSize // ""' <<<"$(printf '%s' "${row}" | base64 -d)")"
  actual_vm_size=""
  azure_ok=false
  if [[ -n "${provider_id}" ]]; then
    resource_id="${provider_id#azure://}"
    if actual_vm_size="$(az vm show --subscription "${AZURE_SUBSCRIPTION_ID}" --ids "${resource_id}" --query hardwareProfile.vmSize -o tsv 2>"${destination}/azure-vm-verification/${machine_name}.err")"; then
      [[ "${actual_vm_size}" == "${target_vm_size}" ]] && azure_ok=true
    fi
  fi
  if [[ "${azure_ok}" == "true" ]]; then azure_vm_verified=$(( azure_vm_verified + 1 )); else azure_vm_failed=$(( azure_vm_failed + 1 )); fi
  printf '%s\t%s\t%s\t%s\t%s\n' "${machine_name}" "${provider_id}" "${spec_vm_size}" "${actual_vm_size}" "${azure_ok}" >>"${destination}/azure-vm-verification/results.tsv"
done

join_violations=0
if [[ -f "${destination}/watch/machine-join-threshold.ndjson" ]]; then
  join_violations="$(jq -s '[.[] | (.violations // []) | length] | add // 0' "${destination}/watch/machine-join-threshold.ndjson")"
fi

final_generation="$(jq -r '.nodePool.generation' "${final_summary}")"
final_platform="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${final_summary}")"
final_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${final_summary}")"
final_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${final_summary}")"
final_version="$(jq -r '.nodePool.version' "${final_summary}")"
final_updating_config="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingConfig") | .status' "${final_summary}")"
final_updating_version="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingVersion") | .status' "${final_summary}")"
final_updating_platform="$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingPlatformMachineTemplate") | .status' "${final_summary}")"
final_up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' "${final_summary}")"
final_guest_version="$(jq -r '.status.desired.version // ""' "${destination}/final/guest-clusterversion.json")"

c_generation=false; [[ "${final_generation}" -eq $(( pre_generation + 1 )) ]] && c_generation=true
c_platform_changed=false; [[ "${final_platform}" != "${pre_platform}" ]] && c_platform_changed=true
c_platform_cleared=false; [[ "${final_updating_platform}" == "False" ]] && c_platform_cleared=true
c_config_unchanged=false; [[ "${final_config}" == "${pre_config}" && "${final_config_version}" == "${pre_config_version}" && "${config_changed_count}" -eq 0 ]] && c_config_unchanged=true
c_version_unchanged=false; [[ "${final_version}" == "${pre_version}" && "${version_changed_count}" -eq 0 && "${final_guest_version}" == "${target_version}" ]] && c_version_unchanged=true
c_physical=false; [[ "$(jq -r '.physicalRolloutComplete' <<<"${final_state}")" == "true" ]] && c_physical=true
c_zero=false; [[ "${final_up_to_date}" == "0" ]] && c_zero=true
c_premature=false; [[ "${max_premature_streak}" -eq 0 ]] && c_premature=true
c_template=false; [[ "${md_template_vm_size}" == "${target_vm_size}" ]] && c_template=true
c_azure=false; [[ "${azure_vm_verified}" -eq 3 && "${azure_vm_failed}" -eq 0 ]] && c_azure=true
c_join=false; [[ "${join_violations}" -eq 0 ]] && c_join=true
c_operator=false; [[ "${actual_operator_image}" == "${PATCHED_IMAGE}" ]] && c_operator=true

checks="$(jq -n \
  --argjson generation "${c_generation}" --arg generationDetail "generation ${pre_generation} -> ${final_generation}" \
  --argjson platformChanged "${c_platform_changed}" --arg platformChangedDetail "platform template ${pre_platform} -> ${final_platform}" \
  --argjson platformCleared "${c_platform_cleared}" --arg platformClearedDetail "UpdatingPlatformMachineTemplate=${final_updating_platform}" \
  --argjson configUnchanged "${c_config_unchanged}" --arg configDetail "config ${pre_config}/${pre_config_version} -> ${final_config}/${final_config_version}, changedObservations=${config_changed_count}" \
  --argjson versionUnchanged "${c_version_unchanged}" --arg versionDetail "status.version=${final_version}, guest=${final_guest_version}, changedObservations=${version_changed_count}" \
  --argjson physical "${c_physical}" --arg physicalDetail "physicalRolloutComplete=$(jq -r '.physicalRolloutComplete' <<<"${final_state}")" \
  --argjson zero "${c_zero}" --arg zeroDetail "upToDateReplicas=${final_up_to_date}" \
  --argjson premature "${c_premature}" --arg prematureDetail "premature observations=${premature_count}, max consecutive=${max_premature_streak}" \
  --argjson template "${c_template}" --arg templateDetail "MachineDeployment ${md_name} -> ${md_infra_ref} vmSize=${md_template_vm_size}" \
  --argjson azure "${c_azure}" --arg azureDetail "Azure VM hardwareProfile verified=${azure_vm_verified}, failed=${azure_vm_failed}, target=${target_vm_size}" \
  --argjson join "${c_join}" --arg joinDetail "12-minute join violations=${join_violations}" \
  --argjson operatorCheck "${c_operator}" --arg operatorDetail "${actual_operator_image}" \
  '[{name:"NodePool generation advanced by one",passed:$generation,detail:$generationDetail},
    {name:"platform-template annotation advanced",passed:$platformChanged,detail:$platformChangedDetail},
    {name:"UpdatingPlatformMachineTemplate cleared",passed:$platformCleared,detail:$platformClearedDetail},
    {name:"config and config version unchanged",passed:$configUnchanged,detail:$configDetail},
    {name:"release version unchanged",passed:$versionUnchanged,detail:$versionDetail},
    {name:"physical rollout complete",passed:$physical,detail:$physicalDetail},
    {name:"upToDateReplicas zero",passed:$zero,detail:$zeroDetail},
    {name:"no premature platform metadata",passed:$premature,detail:$prematureDetail},
    {name:"MachineDeployment template uses target VM size",passed:$template,detail:$templateDetail},
    {name:"actual Azure VMs use target VM size",passed:$azure,detail:$azureDetail},
    {name:"workers joined within 12 minutes",passed:$join,detail:$joinDetail},
    {name:"head operator image",passed:$operatorCheck,detail:$operatorDetail}]')"

result="PASS"
if [[ "${max_premature_streak}" -gt 0 || "${azure_vm_verified}" -ne 3 || "${azure_vm_failed}" -ne 0 ]]; then result="FAIL"; fi
if [[ "${c_generation}" != "true" || "${c_platform_changed}" != "true" || "${c_platform_cleared}" != "true" || "${c_config_unchanged}" != "true" || "${c_version_unchanged}" != "true" || "${c_physical}" != "true" || "${c_zero}" != "true" || "${c_template}" != "true" || "${c_join}" != "true" || "${c_operator}" != "true" ]]; then result="FAIL"; fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=vm-size
nodepool=${CLUSTER_NAMESPACE}/${np}
hostedcluster=${CLUSTER_NAMESPACE}/${CLUSTER_NAME}
preVmSize=${pre_vm_size}
targetVmSize=${target_vm_size}
machineDeployment=${md_name}
machineDeploymentInfrastructureRef=${md_infra_ref}
machineDeploymentTemplateVmSize=${md_template_vm_size}
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
azureVmsVerified=${azure_vm_verified}
azureVmsFailed=${azure_vm_failed}
joinViolations=${join_violations}
EOF

write_verdict "${destination}" "T3 infrastructure-template-only Replace rollout" "${result}" "${checks}" "Azure VM-size-only Replace rollout on the head operator: ${pre_vm_size} -> ${target_vm_size}. ${premature_count} premature platform-annotation observation(s), max consecutive ${max_premature_streak}. Actual Azure VM hardwareProfile.vmSize verified for ${azure_vm_verified} of 3 workers."
finalize_evidence "${destination}"

if [[ "${result}" != "PASS" ]]; then
  printf 'T3 failed: see %s/verdict.json\n' "${destination}" >&2
  exit 1
fi
printf '%s\n' "${destination}"
