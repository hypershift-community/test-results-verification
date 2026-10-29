#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${GUEST_KUBECONFIG:?GUEST_KUBECONFIG is required}"
assert_management_kubeconfig
[[ -r "${GUEST_KUBECONFIG}" ]] || die "guest kubeconfig is not readable"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get --raw=/readyz >/dev/null || die "guest Kubernetes API is not ready"

actual_operator_image="$(kubectl get deployment operator -n hypershift -o jsonpath='{.spec.template.spec.containers[?(@.name=="operator")].image}')"
[[ "${actual_operator_image}" == "${PATCHED_IMAGE}" ]] || die "operator image is ${actual_operator_image}, expected ${PATCHED_IMAGE}"

destination="$(new_run_dir "${EVIDENCE_ROOT}/t3" vm-size)"
target_vm_size="Standard_D4s_v5"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"

NP="${PATCHED_NODEPOOL}" OUT="${destination}/pre" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-path.txt"
pre_summary="${destination}/pre/summary.json"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_status_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_spec_release="$(jq -r '.nodePool.release' "${pre_summary}")"
pre_platform_template="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"

[[ "${pre_spec_release}" == "${RELEASE_B}" ]] || die "patched NodePool is not at release B"
[[ "${pre_status_version}" == "${target_version}" ]] || die "patched NodePool status is not ${target_version}"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingConfig") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not config-stable"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingVersion") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not version-stable"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingPlatformMachineTemplate") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not platform-template-stable"

mkdir -p "${destination}/watch"
watch_deadline_epoch=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${PATCHED_NODEPOOL}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-rollout.log" 2>&1 &
rollout_pid=$!
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${PATCHED_NODEPOOL}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-machine-join.log" 2>&1 &
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
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${PATCHED_NODEPOOL}" "${CLUSTER_NAMESPACE}" "{\"spec\":{\"platform\":{\"azure\":{\"vmSize\":\"${target_vm_size}\"}}}}" >"${destination}/commands.txt"
kubectl patch nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "{\"spec\":{\"platform\":{\"azure\":{\"vmSize\":\"${target_vm_size}\"}}}}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg vmSize "${target_vm_size}" --argjson previous "${pre_generation}" '.spec.platform.azure.vmSize == $vmSize and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool VM-size patch did not produce exactly one generation change"

NP="${PATCHED_NODEPOOL}" OUT="${destination}/action" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/action-path.txt"

success_epoch=""
final_state='{}'
while :; do
  now_epoch="$(date +%s)"
  nodepool_json="$(kubectl get nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
  md_name="$(find_machinedeployment "${PATCHED_NODEPOOL}")"
  md_json='{}'
  sets_json='{"items":[]}'
  machines_json='{"items":[]}'
  nodes_json='{"items":[]}'
  azure_machines_json='{"items":[]}'
  if [[ -n "${md_name}" ]]; then
    md_json="$(kubectl get machinedeployment "${md_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    sets_json="$(kubectl get machinesets -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
    machines_json="$(kubectl get machines -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
  fi
  nodes_json="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -o json)"
  azure_machines_json="$(kubectl get azuremachines -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"

  final_state="$(jq -cn \
    --arg timestamp "$(utc_now)" \
    --arg targetVmSize "${target_vm_size}" \
    --argjson nodepool "${nodepool_json}" \
    --argjson md "${md_json}" \
    --argjson sets "${sets_json}" \
    --argjson machines "${machines_json}" \
    --argjson nodes "${nodes_json}" \
    --argjson azureMachines "${azure_machines_json}" '
      def cond($object; $type): ([$object.status.conditions[]? | select(.type == $type)][0] // {}) | {status, reason, message, observedGeneration, lastTransitionTime};
      ($nodepool.spec.replicas // 0) as $desired |
      ($md.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] // "") as $revision |
      ([$sets.items[]? | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] == $revision)][0] // {}) as $current |
      {
        timestamp: $timestamp,
        nodePool: {
          generation: $nodepool.metadata.generation,
          release: $nodepool.spec.release.image,
          version: $nodepool.status.version,
          replicas: $nodepool.status.replicas,
          currentConfig: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolCurrentConfig"],
          currentConfigVersion: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"],
          platformMachineTemplate: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"],
          ready: cond($nodepool; "Ready"),
          updatingVersion: cond($nodepool; "UpdatingVersion"),
          updatingConfig: cond($nodepool; "UpdatingConfig"),
          updatingPlatformMachineTemplate: cond($nodepool; "UpdatingPlatformMachineTemplate")
        },
        machineDeployment: {
          generation: $md.metadata.generation,
          observedGeneration: $md.status.observedGeneration,
          revision: $revision,
          replicas: $md.status.replicas,
          availableReplicas: $md.status.availableReplicas,
          upToDateReplicas: $md.status.upToDateReplicas
        },
        currentMachineSet: {
          name: $current.metadata.name,
          replicas: $current.status.replicas,
          availableReplicas: $current.status.availableReplicas
        },
        machines: [$machines.items[]? | {uid, name, version, nodeName, ready: cond(.; "Ready")}],
        nodes: [$nodes.items[]? | {name, ready: cond(.; "Ready")}],
        azureMachines: [$azureMachines.items[]? | select(.metadata.name | startswith("test-cntrlplane-4826-patched")) | select(.spec.vmSize == $targetVmSize) | {name, vmSize: .spec.vmSize}],
        physicalRolloutComplete: (
          $desired > 0 and
          $md.status.replicas == $desired and
          $md.status.availableReplicas == $desired and
          $md.status.observedGeneration >= $md.metadata.generation and
          ($current.status.replicas // -1) == $desired and
          ($current.status.availableReplicas // -1) == $desired and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0 and
          ([ $machines.items[] | select(.status.nodeRef.name != null) | select(cond(.; "Ready").status == "True") ] | length) == $desired and
          ([ $azureMachines.items[]? | select(.spec.vmSize == $targetVmSize) ] | length) == $desired
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-state.ndjson"

  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${final_state}")"
  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${final_state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${final_state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${final_state}")"

  if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && "${updating_config}" == "False" && "${updating_version}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" && "${platform_template}" != "${pre_platform_template}" ]]; then
    success_epoch="$(date +%s)"
    printf '%s\n' "${success_epoch}" >"${destination}/success-epoch.txt"
    break
  fi

  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    break
  fi
  sleep 15
done

cleanup
trap - EXIT INT TERM

NP="${PATCHED_NODEPOOL}" OUT="${destination}/deadline" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/deadline-path.txt"

if [[ -z "${success_epoch}" ]]; then
  printf 'VM-size rollout did not complete within 1800 seconds\n' >&2
  exit 1
fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=vm-size
nodepool=${CLUSTER_NAMESPACE}/${PATCHED_NODEPOOL}
targetVmSize=${target_vm_size}
preGeneration=${pre_generation}
preStatusVersion=${pre_status_version}
preSpecRelease=${pre_spec_release}
prePlatformMachineTemplate=${pre_platform_template}
targetVersion=${target_version}
operatorImage=${actual_operator_image}
patchUtc=${patch_utc}
deadlineUtc=${deadline_utc}
deadlineSeconds=1800
successEpoch=${success_epoch}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
elapsedSeconds=$(( completed_epoch - patch_epoch ))
EOF

find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
