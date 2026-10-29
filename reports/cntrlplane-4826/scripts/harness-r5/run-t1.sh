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

readonly deadline_seconds=1800
readonly interval_seconds=5
readonly baseline_hold_seconds=180
readonly post_success_seconds=60
readonly target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
readonly start_version="5.0.0-rc.7"
readonly patch_field='{"spec":{"release":{"image":"'"${RELEASE_B}"'"}}}'

actual_operator_image="$(kubectl get deployment operator -n hypershift -o jsonpath='{.spec.template.spec.containers[?(@.name=="operator")].image}')"
[[ "${actual_operator_image}" == "${expected_operator_image}" ]] || die "operator image is ${actual_operator_image}, expected ${expected_operator_image}"

destination="$(new_run_dir "${EVIDENCE_ROOT}/t1" "${mode}")"
verdict="BLOCKED"
trap 'printf "verdict=%s\ncompleted_utc=%s\n" "${verdict}" "$(utc_now)" >"${destination}/verdict.txt"' EXIT

NP="${nodepool}" OUT="${destination}/pre" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-path.txt"
pre_summary="${destination}/pre/summary.json"
pre_uid="$(jq -r '.nodePool.uid' "${pre_summary}")"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_status_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_spec_release="$(jq -r '.nodePool.release' "${pre_summary}")"
pre_md_uid="$(jq -r '.machineDeployment.uid' "${pre_summary}")"
pre_md_revision="$(jq -r '.machineDeployment.revision' "${pre_summary}")"
pre_current_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_current_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${pre_summary}")"
pre_current_rollout_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentRolloutConfig"] // ""' "${pre_summary}")"
pre_platform_template="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"
jq -r '.ownedMachineSets[].uid' "${pre_summary}" | sort >"${destination}/pre-machineset-uids.txt"
jq -r '.ownedMachines[].uid' "${pre_summary}" | sort >"${destination}/pre-machine-uids.txt"
jq -r '.guestNodes[].uid' "${pre_summary}" | sort >"${destination}/pre-node-uids.txt"

[[ "${pre_spec_release}" == "${RELEASE_A}" ]] || die "${mode} NodePool is not at release A"
[[ "${pre_status_version}" == "${start_version}" ]] || die "${mode} NodePool status is not ${start_version}"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "Ready") | .status' "${pre_summary}")" == "True" ]] || die "${mode} NodePool is not Ready"
[[ "$(jq -r '.hostedControlPlane.available.status' "${pre_summary}")" == "True" ]] || die "HostedControlPlane is not Available"
[[ "$(jq -r '.machineDeployment.upToDateReplicas' "${pre_summary}")" != "null" ]] || die "MachineDeployment has no upToDateReplicas field"

mkdir -p "${destination}/watch"
watch_deadline_epoch=$(( $(date +%s) + deadline_seconds + post_success_seconds + 120 ))
INTERVAL_SECONDS="${interval_seconds}" DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${nodepool}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-rollout.log" 2>&1 &
rollout_pid=$!
INTERVAL_SECONDS="${interval_seconds}" DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${nodepool}" OUT="${destination}/watch" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-machine-join.log" 2>&1 &
join_pid=$!
cleanup() {
  kill "${rollout_pid}" "${join_pid}" 2>/dev/null || true
  wait "${rollout_pid}" "${join_pid}" 2>/dev/null || true
}
trap - EXIT
trap 'cleanup; printf "verdict=%s\ncompleted_utc=%s\n" "${verdict}" "$(utc_now)" >"${destination}/verdict.txt"' EXIT INT TERM

sleep 5
patch_epoch="$(date +%s)"
deadline_epoch=$(( patch_epoch + deadline_seconds ))
patch_utc="$(date -u -r "${patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
deadline_utc="$(date -u -r "${deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${nodepool}" "${CLUSTER_NAMESPACE}" "${patch_field}" >"${destination}/commands.txt"
kubectl patch nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "${patch_field}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg release "${RELEASE_B}" --argjson previous "${pre_generation}" '.spec.release.image == $release and .metadata.generation == ($previous + 1)' \
  <<<"${post_patch}" >/dev/null || die "NodePool patch did not produce exactly one generation change"

NP="${nodepool}" OUT="${destination}/action" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/action-path.txt"

stall_started_epoch=""
physical_complete_epoch=""
completion_observed_epoch=""
unexpected_epoch=""
watch_failed=0
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
          uid: $np.metadata.uid,
          generation: $np.metadata.generation,
          specRelease: $np.spec.release.image,
          statusVersion: $np.status.version,
          annotations: $np.metadata.annotations,
          ready: condition($np; "Ready"),
          updatingVersion: condition($np; "UpdatingVersion"),
          updatingConfig: condition($np; "UpdatingConfig"),
          updatingPlatformMachineTemplate: condition($np; "UpdatingPlatformMachineTemplate")
        },
        machineDeployment: {
          uid: $md.metadata.uid,
          generation: $md.metadata.generation,
          observedGeneration: $md.status.observedGeneration,
          revision: $revision,
          templateVersion: $md.spec.template.spec.version,
          bootstrapSecret: $md.spec.template.spec.bootstrap.dataSecretName,
          replicas: $md.status.replicas,
          availableReplicas: $md.status.availableReplicas,
          upToDateReplicas: $md.status.upToDateReplicas
        },
        currentMachineSet: {
          name: $current.metadata.name,
          uid: $current.metadata.uid,
          createdAt: $current.metadata.creationTimestamp,
          revision: $current.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"],
          templateVersion: $current.spec.template.spec.version,
          replicas: $current.status.replicas,
          availableReplicas: $current.status.availableReplicas
        },
        oldMachineSetsActive: ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length),
        machines: [ $machines.items[] | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          version: .spec.version,
          nodeName: .status.nodeRef.name,
          ready: condition(.; "Ready").status,
          upToDate: condition(.; "UpToDate")
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
          ($current.spec.template.spec.version // "") == $target and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0 and
          ([ $machines.items[] | select(.spec.version == $target) | select((.status.nodeRef.name // "") != "") | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length) == $desired and
          ([ $machines.items[] | select((.status.nodeRef.name // "") != "") | select(([.status.conditions[]? | select(.type == "Ready")][0].status // null) == "True") ] | length) == $desired
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-state.ndjson"

  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${final_state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.statusVersion // ""' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"
  current_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' <<<"${final_state}")"
  current_config_version="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' <<<"${final_state}")"
  current_rollout_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentRolloutConfig"] // ""' <<<"${final_state}")"

  if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && -z "${physical_complete_epoch}" ]]; then
    physical_complete_epoch="${now_epoch}"
    printf '%s\n' "${physical_complete_epoch}" >"${destination}/physical-complete-epoch.txt"
  fi

  if [[ "${mode}" == "baseline" ]]; then
    if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && "${status_version}" != "${target_version}" && "${updating_version}" == "True" ]]; then
      if [[ -z "${stall_started_epoch}" ]]; then
        stall_started_epoch="${now_epoch}"
        printf '%s\n' "${stall_started_epoch}" >"${destination}/stall-start-epoch.txt"
      fi
      if (( now_epoch - stall_started_epoch >= baseline_hold_seconds )); then
        verdict="PASS"
        break
      fi
    else
      stall_started_epoch=""
      rm -f "${destination}/stall-start-epoch.txt"
    fi
    if [[ "${status_version}" == "${target_version}" ]]; then
      unexpected_epoch="${now_epoch}"
      printf '%s\n' "${unexpected_epoch}" >"${destination}/unexpected-completion-epoch.txt"
      verdict="FAIL"
      break
    fi
  else
    completion_metadata_advanced="false"
    if [[ "${status_version}" == "${target_version}" || "${current_config}" != "${pre_current_config}" || "${current_config_version}" != "${pre_current_config_version}" ]]; then
      completion_metadata_advanced="true"
    fi
    if [[ "${completion_metadata_advanced}" == "true" && "${physical_complete}" != "true" ]]; then
      verdict="FAIL"
      printf 'completion metadata advanced before physical gates were satisfied at %s\n' "$(jq -r '.timestamp' <<<"${final_state}")" >"${destination}/premature-completion.txt"
      break
    fi
    if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && "${status_version}" == "${target_version}" && "${updating_version}" == "False" && "${current_config}" != "${pre_current_config}" && "${current_config_version}" != "${pre_current_config_version}" ]]; then
      completion_observed_epoch="${now_epoch}"
      printf '%s\n' "${completion_observed_epoch}" >"${destination}/completion-observed-epoch.txt"
      while (( $(date +%s) - completion_observed_epoch < post_success_seconds )); do
        sleep 5
      done
      post_state="$(kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" -o json)"
      post_status_version="$(jq -r '.status.version // ""' <<<"${post_state}")"
      post_updating_version="$(jq -r '[.status.conditions[]? | select(.type == "UpdatingVersion")][0].status // ""' <<<"${post_state}")"
      if [[ "${post_status_version}" == "${target_version}" && "${post_updating_version}" == "False" ]]; then
        verdict="PASS"
      else
        verdict="FAIL"
      fi
      break
    fi
  fi

  if ! kill -0 "${rollout_pid}" 2>/dev/null; then
    printf 'rollout watcher exited before the case reached a terminal state\n' >&2
    watch_failed=1
    break
  fi
  if ! kill -0 "${join_pid}" 2>/dev/null; then
    printf 'machine-join watcher exited before the case reached a terminal state\n' >&2
    watch_failed=1
    break
  fi
  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    verdict="FAIL"
    break
  fi
  sleep "${interval_seconds}"
done

cleanup
trap - EXIT INT TERM

NP="${nodepool}" OUT="${destination}/final" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/final-path.txt"

mkdir -p "${destination}/logs"
for pod in $(kubectl get pods -n hypershift -l name=operator -o json | jq -r '.items[] | select(.status.phase == "Running") | select(all(.status.containerStatuses[]?; .ready == true)) | .metadata.name'); do
  kubectl logs -n hypershift "${pod}" -c operator --since-time="${patch_utc}" >"${destination}/logs/${pod}-operator.log" 2>&1 || true
done
kubectl get events -n "${CLUSTER_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${destination}/logs/clusters-events.json"
kubectl get events -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${destination}/logs/hcp-events.json"

if [[ "${watch_failed}" -ne 0 ]]; then
  verdict="FAIL"
fi

final_summary="${destination}/final/summary.json"
jq -n \
  --arg verdict "${verdict}" \
  --arg mode "${mode}" \
  --arg operatorImage "${actual_operator_image}" \
  --arg patchUtc "${patch_utc}" \
  --arg deadlineUtc "${deadline_utc}" \
  --arg targetVersion "${target_version}" \
  --arg startRelease "${RELEASE_A}" \
  --arg targetRelease "${RELEASE_B}" \
  --arg preConfig "${pre_current_config}" \
  --arg preConfigVersion "${pre_current_config_version}" \
  --arg preRolloutConfig "${pre_current_rollout_config}" \
  --arg prePlatformTemplate "${pre_platform_template}" \
  --slurpfile pre "${pre_summary}" \
  --slurpfile final "${final_summary}" \
  --argjson stallStartEpoch "${stall_started_epoch:-0}" \
  --argjson physicalCompleteEpoch "${physical_complete_epoch:-0}" \
  --argjson completionObservedEpoch "${completion_observed_epoch:-0}" \
  '{
    verdict: $verdict,
    mode: $mode,
    operatorImage: $operatorImage,
    patchUtc: $patchUtc,
    deadlineUtc: $deadlineUtc,
    stallStartEpoch: (if $stallStartEpoch == 0 then null else $stallStartEpoch end),
    physicalCompleteEpoch: (if $physicalCompleteEpoch == 0 then null else $physicalCompleteEpoch end),
    completionObservedEpoch: (if $completionObservedEpoch == 0 then null else $completionObservedEpoch end),
    expected: {
      startRelease: $startRelease,
      startVersion: "5.0.0-rc.7",
      targetRelease: $targetRelease,
      targetVersion: $targetVersion,
      upToDateReplicasAtCompletion: 0
    },
    pre: $pre[0],
    final: $final[0],
    completionMetadata: {
      preCurrentConfig: $preConfig,
      finalCurrentConfig: $final[0].nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"],
      preCurrentConfigVersion: $preConfigVersion,
      finalCurrentConfigVersion: $final[0].nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"],
      preCurrentRolloutConfig: $preRolloutConfig,
      finalCurrentRolloutConfig: $final[0].nodePool.annotations["hypershift.openshift.io/nodePoolCurrentRolloutConfig"],
      prePlatformTemplate: $prePlatformTemplate,
      finalPlatformTemplate: $final[0].nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"]
    }
  }' >"${destination}/verdict.json"

if [[ "${verdict}" != "PASS" ]]; then
  find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
  printf '%s\n' "${destination}"
  exit 1
fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=${mode}
nodepool=${CLUSTER_NAMESPACE}/${nodepool}
nodePoolUID=${pre_uid}
preGeneration=${pre_generation}
preStatusVersion=${pre_status_version}
preSpecRelease=${pre_spec_release}
preMachineSetRevision=${pre_md_revision}
preMachineDeploymentUID=${pre_md_uid}
preCurrentConfig=${pre_current_config}
preCurrentConfigVersion=${pre_current_config_version}
preCurrentRolloutConfig=${pre_current_rollout_config}
prePlatformMachineTemplate=${pre_platform_template}
targetRelease=${RELEASE_B}
targetVersion=${target_version}
operatorImage=${actual_operator_image}
patchUtc=${patch_utc}
deadlineUtc=${deadline_utc}
deadlineSeconds=${deadline_seconds}
stallStartEpoch=${stall_started_epoch}
physicalCompleteEpoch=${physical_complete_epoch}
completionObservedEpoch=${completion_observed_epoch}
unexpectedCompletionEpoch=${unexpected_epoch}
verdict=${verdict}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
elapsedSeconds=$(( completed_epoch - patch_epoch ))
EOF

find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
