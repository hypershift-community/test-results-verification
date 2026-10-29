#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'usage: %s baseline|patched\n' "$0" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
mode="$1"
case "${mode}" in
  baseline)
    expected_operator_image="${BASE_IMAGE}"
    nodepool="${UNPATCHED_NODEPOOL}"
    ;;
  patched)
    expected_operator_image="${PATCHED_IMAGE}"
    nodepool="${PATCHED_NODEPOOL}"
    ;;
  *)
    usage
    ;;
esac

: "${GUEST_KUBECONFIG:?GUEST_KUBECONFIG is required}"
assert_management_kubeconfig
[[ -r "${GUEST_KUBECONFIG}" ]] || die "guest kubeconfig is not readable"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get --raw=/readyz >/dev/null || die "guest Kubernetes API is not ready"

actual_operator_image="$(kubectl get deployment operator -n hypershift -o jsonpath='{.spec.template.spec.containers[?(@.name=="operator")].image}')"
[[ "${actual_operator_image}" == "${expected_operator_image}" ]] || die "operator image is ${actual_operator_image}, expected ${expected_operator_image}"

destination="$(new_run_dir "${EVIDENCE_ROOT}/t1" "${mode}")"
deadline_seconds=1800
interval_seconds=15
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
patch_field='{"spec":{"release":{"image":"'"${RELEASE_B}"'"}}}'

NP="${nodepool}" OUT="${destination}/pre" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-path.txt"
pre_summary="${destination}/pre/summary.json"
pre_uid="$(jq -r '.nodePool.uid' "${pre_summary}")"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_status_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_spec_release="$(jq -r '.nodePool.release' "${pre_summary}")"
pre_md_uid="$(jq -r '.machineDeployment.uid' "${pre_summary}")"
pre_md_revision="$(jq -r '.machineDeployment.revision' "${pre_summary}")"
jq -r '.ownedMachineSets[].uid' "${pre_summary}" | sort >"${destination}/pre-machineset-uids.txt"
jq -r '.ownedMachines[].uid' "${pre_summary}" | sort >"${destination}/pre-machine-uids.txt"
jq -r '.guestNodes[].uid' "${pre_summary}" | sort >"${destination}/pre-node-uids.txt"

if [[ "${mode}" == "baseline" ]]; then
  [[ "${pre_spec_release}" == "${RELEASE_A}" ]] || die "baseline NodePool is not at release A"
  [[ "${pre_status_version}" == "5.0.0-rc.7" ]] || die "baseline NodePool status is not 5.0.0-rc.7"
else
  [[ "${pre_spec_release}" == "${RELEASE_A}" ]] || die "patched NodePool is not at release A"
  [[ "${pre_status_version}" == "5.0.0-rc.7" ]] || die "patched NodePool status is not 5.0.0-rc.7"
fi

mkdir -p "${destination}/watch"
watch_deadline_epoch=$(( $(date +%s) + deadline_seconds + 10 ))
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${nodepool}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-rollout.log" 2>&1 &
rollout_pid=$!
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${nodepool}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-machine-join.log" 2>&1 &
join_pid=$!
cleanup() {
  kill "${rollout_pid}" "${join_pid}" 2>/dev/null || true
  wait "${rollout_pid}" "${join_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 5
patch_epoch="$(date +%s)"
deadline_epoch=$(( patch_epoch + deadline_seconds ))
patch_utc="$(date -u -r "${patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
deadline_utc="$(date -u -r "${deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${nodepool}" "${CLUSTER_NAMESPACE}" "${patch_field}" >"${destination}/commands.txt"
kubectl patch nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "${patch_field}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg release "${RELEASE_B}" --argjson previous "${pre_generation}" '.spec.release.image == $release and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool patch did not produce exactly one generation change"

NP="${nodepool}" OUT="${destination}/action" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/action-path.txt"

stall_epoch=""
unexpected_epoch=""
success_epoch=""
final_state='{}'
while :; do
  now_epoch="$(date +%s)"
  nodepool_json="$(kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" -o json)"
  md_name="$(find_machinedeployment "${nodepool}")"
  md_json='{}'
  sets_json='{"items":[]}'
  machines_json='{"items":[]}'
  nodes_json='{"items":[]}'
  if [[ -n "${md_name}" ]]; then
    md_json="$(kubectl get machinedeployment "${md_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    sets_json="$(kubectl get machinesets -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
    machines_json="$(kubectl get machines -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
    nodes_json="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -o json)"
  fi
  final_state="$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson np "${nodepool_json}" \
    --argjson md "${md_json}" \
    --argjson sets "${sets_json}" \
    --argjson machines "${machines_json}" \
    --argjson nodes "${nodes_json}" \
    --arg target "${target_version}" '
      def condition($object; $type): ([$object.status.conditions[]? | select(.type == $type)][0] // {});
      ($md.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] // "") as $revision |
      ($md.spec.replicas // 0) as $desired |
      ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] == $revision) ][0] // {}) as $current |
      {
        timestamp: $timestamp,
        nodePool: {
          generation: $np.metadata.generation,
          specRelease: $np.spec.release.image,
          statusVersion: $np.status.version,
          ready: condition($np; "Ready"),
          updatingVersion: condition($np; "UpdatingVersion")
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
        oldMachineSetsActive: ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length),
        machines: [ $machines.items[] | {
          uid: .metadata.uid,
          version: .spec.version,
          nodeName: .status.nodeRef.name,
          ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null)
        } ],
        targetMachinesReady: ([ $machines.items[] | select(.spec.version == $target) | select((.status.nodeRef.name // "") != "") | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length),
        nodesReady: ([ $nodes.items[] | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length),
        physicalRolloutComplete: (
          $desired > 0 and
          $md.status.replicas == $desired and
          $md.status.availableReplicas == $desired and
          $md.status.observedGeneration >= $md.metadata.generation and
          ($current.status.replicas // -1) == $desired and
          ($current.status.availableReplicas // -1) == $desired and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0 and
          ([ $machines.items[] | select(.spec.version == $target) | select((.status.nodeRef.name // "") != "") | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length) == $desired and
          ([ $machines.items[] | select((.status.nodeRef.name // "") != "") | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length) == $desired
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-state.ndjson"

  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${final_state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.statusVersion' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"

  if ! kill -0 "${rollout_pid}" 2>/dev/null || ! kill -0 "${join_pid}" 2>/dev/null; then
    printf 'watch process exited before the case reached a terminal state\n' >&2
    break
  fi

  if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" ]]; then
    if [[ "${mode}" == "baseline" && "${status_version}" != "${target_version}" && "${updating_version}" == "True" && -z "${stall_epoch}" ]]; then
      stall_epoch="$(date +%s)"
      printf '%s\n' "${stall_epoch}" >"${destination}/stall-epoch.txt"
    fi
    if [[ "${mode}" == "patched" && "${status_version}" == "${target_version}" && "${updating_version}" == "False" ]]; then
      success_epoch="$(date +%s)"
      printf '%s\n' "${success_epoch}" >"${destination}/success-epoch.txt"
      break
    fi
  fi

  if [[ "${mode}" == "baseline" && "${status_version}" == "${target_version}" ]]; then
    unexpected_epoch="$(date +%s)"
    printf '%s\n' "${unexpected_epoch}" >"${destination}/unexpected-completion-epoch.txt"
    break
  fi

  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    break
  fi
  sleep "${interval_seconds}"
done

cleanup
trap - EXIT INT TERM

NP="${nodepool}" OUT="${destination}/deadline" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/deadline-path.txt"

mkdir -p "${destination}/logs"
for pod in $(kubectl get pods -n hypershift -l name=operator -o json | jq -r '.items[] | select(.status.phase == "Running") | select(all(.status.containerStatuses[]?; .ready == true)) | .metadata.name'); do
  kubectl logs -n hypershift "${pod}" -c operator --since-time="${patch_utc}" >"${destination}/logs/${pod}-operator.log" 2>&1 || true
done
kubectl get events -n "${CLUSTER_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${destination}/logs/clusters-events.json"
kubectl get events -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${destination}/logs/hcp-events.json"

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=${mode}
nodepool=${CLUSTER_NAMESPACE}/${nodepool}
nodePoolUID=${pre_uid}
preGeneration=${pre_generation}
preStatusVersion=${pre_status_version}
preSpecRelease=${pre_spec_release}
machineSetRevision=${pre_md_revision}
machineDeploymentUID=${pre_md_uid}
targetRelease=${RELEASE_B}
targetVersion=${target_version}
operatorImage=${actual_operator_image}
patchUtc=${patch_utc}
deadlineUtc=${deadline_utc}
deadlineSeconds=${deadline_seconds}
stallEpoch=${stall_epoch}
unexpectedCompletionEpoch=${unexpected_epoch}
successEpoch=${success_epoch}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
elapsedSeconds=$(( completed_epoch - patch_epoch ))
EOF

find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
