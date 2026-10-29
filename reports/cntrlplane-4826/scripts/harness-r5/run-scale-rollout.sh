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

destination="$(new_run_dir "${EVIDENCE_ROOT}/t6" scale)"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"

if ! kubectl get nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
  template_file="${destination}/scale-nodepool-template.json"
  kubectl get nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json >"${template_file}"
  TEMPLATE_FILE="${template_file}" "${SCRIPT_DIR}/nodepool-create.sh" "${SCALE_NODEPOOL}" "${RELEASE_B}" "${target_version}" 3 REPLACE --create >"${destination}/scale-nodepool-create-path.txt"
fi

NP="${SCALE_NODEPOOL}" OUT="${destination}/pre-create" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-create-path.txt"
TIMEOUT_SECONDS=1800 EXPECTED_VERSION="${target_version}" NP="${SCALE_NODEPOOL}" "${SCRIPT_DIR}/wait-nodepool-ready.sh" >"${destination}/wait-ready.log" 2>&1

NP="${SCALE_NODEPOOL}" OUT="${destination}/pre-zero" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-zero-path.txt"
pre_zero_summary="${destination}/pre-zero/summary.json"
pre_generation="$(jq -r '.nodePool.generation' "${pre_zero_summary}")"
pre_status_version="$(jq -r '.nodePool.version' "${pre_zero_summary}")"
pre_spec_release="$(jq -r '.nodePool.release' "${pre_zero_summary}")"
pre_current_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_zero_summary}")"
pre_platform_template="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_zero_summary}")"

[[ "${pre_spec_release}" == "${RELEASE_B}" ]] || die "scale NodePool is not at release B"
[[ "${pre_status_version}" == "${target_version}" ]] || die "scale NodePool status is not ${target_version}"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "Ready") | .status' "${pre_zero_summary}")" == "True" ]] || die "scale NodePool is not Ready"

mkdir -p "${destination}/watch-zero"
watch_deadline_epoch=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${SCALE_NODEPOOL}" OUT="${destination}/watch-zero" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-zero.log" 2>&1 &
rollout_pid=$!
cleanup() {
  kill "${rollout_pid}" 2>/dev/null || true
  wait "${rollout_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 5
patch_epoch="$(date +%s)"
deadline_epoch=$(( patch_epoch + 1800 ))
patch_utc="$(date -u -r "${patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
deadline_utc="$(date -u -r "${deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${SCALE_NODEPOOL}" "${CLUSTER_NAMESPACE}" '{"spec":{"replicas":0}}' >"${destination}/commands-zero.txt"
kubectl patch nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" --type=merge -p '{"spec":{"replicas":0}}' >"${destination}/patch-zero.out"

post_patch="$(kubectl get nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --argjson previous "${pre_generation}" '.spec.replicas == 0 and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool scale-to-zero patch did not produce exactly one generation change"

zero_success_epoch=""
final_state='{}'
while :; do
  now_epoch="$(date +%s)"
  nodepool_json="$(kubectl get nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
  md_name="$(find_machinedeployment "${SCALE_NODEPOOL}")"
  md_json='{}'
  sets_json='{"items":[]}'
  machines_json='{"items":[]}'
  if [[ -n "${md_name}" ]]; then
    md_json="$(kubectl get machinedeployment "${md_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    sets_json="$(kubectl get machinesets -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
    machines_json="$(kubectl get machines -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
  fi

  final_state="$(jq -cn \
    --arg timestamp "$(utc_now)" \
    --argjson nodepool "${nodepool_json}" \
    --argjson md "${md_json}" \
    --argjson sets "${sets_json}" \
    --argjson machines "${machines_json}" '
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
        zeroComplete: (
          $desired == 0 and
          $md.status.replicas == 0 and
          $md.status.availableReplicas == 0 and
          $md.status.observedGeneration >= $md.metadata.generation and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-zero-state.ndjson"

  zero_complete="$(jq -r '.zeroComplete' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${final_state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${final_state}")"

  if [[ "${zero_complete}" == "true" && "${updating_version}" == "False" && "${updating_config}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" ]]; then
    zero_success_epoch="$(date +%s)"
    printf '%s\n' "${zero_success_epoch}" >"${destination}/zero-success-epoch.txt"
    break
  fi

  if [[ "${now_epoch}" -ge "${deadline_epoch}" ]]; then
    break
  fi
  sleep 15
done

cleanup
trap - EXIT INT TERM

NP="${SCALE_NODEPOOL}" OUT="${destination}/zero" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/zero-path.txt"

if [[ -z "${zero_success_epoch}" ]]; then
  printf 'scale-to-zero did not complete within 1800 seconds\n' >&2
  exit 1
fi

mkdir -p "${destination}/watch-back"
watch_deadline_epoch=$(( $(date +%s) + 1810 ))
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${SCALE_NODEPOOL}" OUT="${destination}/watch-back" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-rollout.sh" >"${destination}/watch-back.log" 2>&1 &
rollout_pid=$!
DEADLINE_EPOCH="${watch_deadline_epoch}" NP="${SCALE_NODEPOOL}" OUT="${destination}/watch-back" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/watch-machine-join.sh" >"${destination}/watch-back-machine-join.log" 2>&1 &
join_pid=$!
cleanup() {
  kill "${rollout_pid}" "${join_pid}" 2>/dev/null || true
  wait "${rollout_pid}" "${join_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 5
back_patch_epoch="$(date +%s)"
back_deadline_epoch=$(( back_patch_epoch + 1800 ))
back_patch_utc="$(date -u -r "${back_patch_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
back_deadline_utc="$(date -u -r "${back_deadline_epoch}" +%Y-%m-%dT%H:%M:%SZ)"
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${SCALE_NODEPOOL}" "${CLUSTER_NAMESPACE}" '{"spec":{"replicas":3}}' >"${destination}/commands-back.txt"
kubectl patch nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" --type=merge -p '{"spec":{"replicas":3}}' >"${destination}/patch-back.out"

post_back_patch="$(kubectl get nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e '.spec.replicas == 3' <<<"${post_back_patch}" >/dev/null || die "NodePool scale-back patch did not set replicas to 3"

back_success_epoch=""
final_state='{}'
while :; do
  now_epoch="$(date +%s)"
  nodepool_json="$(kubectl get nodepool "${SCALE_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
  md_name="$(find_machinedeployment "${SCALE_NODEPOOL}")"
  md_json='{}'
  sets_json='{"items":[]}'
  machines_json='{"items":[]}'
  nodes_json='{"items":[]}'
  if [[ -n "${md_name}" ]]; then
    md_json="$(kubectl get machinedeployment "${md_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    sets_json="$(kubectl get machinesets -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
    machines_json="$(kubectl get machines -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
  fi
  nodes_json="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -o json)"

  final_state="$(jq -cn \
    --arg timestamp "$(utc_now)" \
    --argjson nodepool "${nodepool_json}" \
    --argjson md "${md_json}" \
    --argjson sets "${sets_json}" \
    --argjson machines "${machines_json}" \
    --argjson nodes "${nodes_json}" '
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
        backComplete: (
          $desired == 3 and
          $md.status.replicas == 3 and
          $md.status.availableReplicas == 3 and
          $md.status.observedGeneration >= $md.metadata.generation and
          ($current.status.replicas // -1) == 3 and
          ($current.status.availableReplicas // -1) == 3 and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0 and
          ([ $machines.items[] | select(.status.nodeRef.name != null) | select(cond(.; "Ready").status == "True") ] | length) == 3
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-back-state.ndjson"

  back_complete="$(jq -r '.backComplete' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"
  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${final_state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${final_state}")"
  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${final_state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${final_state}")"

  if [[ "${back_complete}" == "true" && "${updating_version}" == "False" && "${updating_config}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" && "${current_config}" == "${pre_current_config}" && "${platform_template}" == "${pre_platform_template}" ]]; then
    back_success_epoch="$(date +%s)"
    printf '%s\n' "${back_success_epoch}" >"${destination}/back-success-epoch.txt"
    break
  fi

  if [[ "${now_epoch}" -ge "${back_deadline_epoch}" ]]; then
    break
  fi
  sleep 15
done

cleanup
trap - EXIT INT TERM

NP="${SCALE_NODEPOOL}" OUT="${destination}/back" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/back-path.txt"

if [[ -z "${back_success_epoch}" ]]; then
  printf 'scale-back did not complete within 1800 seconds\n' >&2
  exit 1
fi

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=scale
nodepool=${CLUSTER_NAMESPACE}/${SCALE_NODEPOOL}
preGeneration=${pre_generation}
preStatusVersion=${pre_status_version}
preSpecRelease=${pre_spec_release}
preCurrentConfig=${pre_current_config}
prePlatformMachineTemplate=${pre_platform_template}
targetVersion=${target_version}
operatorImage=${actual_operator_image}
zeroPatchUtc=${patch_utc}
zeroDeadlineUtc=${deadline_utc}
zeroSuccessEpoch=${zero_success_epoch}
backPatchUtc=${back_patch_utc}
backDeadlineUtc=${back_deadline_utc}
backSuccessEpoch=${back_success_epoch}
completedUtc=$(date -u -r "${completed_epoch}" +%Y-%m-%dT%H:%M:%SZ)
EOF

find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
