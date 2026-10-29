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

destination="$(new_run_dir "${EVIDENCE_ROOT}/t2" config)"
run_stamp="$(utc_stamp | tr '[:upper:]' '[:lower:]')"
marker="CNTRLPLANE-4826-T2-${run_stamp}"
configmap_name="test-cntrlplane-4826-t2-mc-${run_stamp}"
daemonset_name="test-cntrlplane-4826-t2-verify-${run_stamp}"
target_version="5.1.0-0.nightly-multi-2026-10-27-082258"

NP="${PATCHED_NODEPOOL}" OUT="${destination}/pre" GUEST_KUBECONFIG="${GUEST_KUBECONFIG}" "${SCRIPT_DIR}/snapshot.sh" >"${destination}/pre-path.txt"
pre_summary="${destination}/pre/summary.json"
pre_generation="$(jq -r '.nodePool.generation' "${pre_summary}")"
pre_status_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_spec_release="$(jq -r '.nodePool.release' "${pre_summary}")"
pre_current_config="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_platform_template="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"] // ""' "${pre_summary}")"

[[ "${pre_spec_release}" == "${RELEASE_B}" ]] || die "patched NodePool is not at release B"
[[ "${pre_status_version}" == "${target_version}" ]] || die "patched NodePool status is not ${target_version}"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingConfig") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not config-stable"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingVersion") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not version-stable"
[[ "$(jq -r '.nodePool.conditions[] | select(.type == "UpdatingPlatformMachineTemplate") | .status' "${pre_summary}")" == "False" ]] || die "patched NodePool is not platform-template-stable"

verification_image="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pods -n openshift-machine-config-operator -l k8s-app=kube-rbac-proxy-crio -o json | jq -r '[.items[] | select(.spec.nodeName | startswith("test-cntrlplane-4826-patched")) | .spec.containers[0].image][0] // ""')"
[[ -n "${verification_image}" ]] || die "could not find a kube-rbac-proxy-crio image on the patched NodePool"
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
printf 'kubectl patch nodepool %s -n %s --type=merge -p %q\n' "${PATCHED_NODEPOOL}" "${CLUSTER_NAMESPACE}" "{\"spec\":{\"config\":[{\"name\":\"${configmap_name}\"}]}}" >"${destination}/commands.txt"
kubectl patch nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" --type=merge -p "{\"spec\":{\"config\":[{\"name\":\"${configmap_name}\"}]}}" >"${destination}/patch.out"

post_patch="$(kubectl get nodepool "${PATCHED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
jq -e --arg configmap "${configmap_name}" --argjson previous "${pre_generation}" '.spec.config[0].name == $configmap and .metadata.generation == ($previous + 1)' <<<"${post_patch}" >/dev/null || die "NodePool config patch did not produce exactly one generation change"

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
        physicalRolloutComplete: (
          $desired > 0 and
          $md.status.replicas == $desired and
          $md.status.availableReplicas == $desired and
          $md.status.observedGeneration >= $md.metadata.generation and
          ($current.status.replicas // -1) == $desired and
          ($current.status.availableReplicas // -1) == $desired and
          ([ $sets.items[] | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0) ] | length) == 0 and
          ([ $machines.items[] | select(.status.nodeRef.name != null) | select(cond(.; "Ready").status == "True") ] | length) == $desired
        )
      }')"
  printf '%s\n' "${final_state}" >>"${destination}/monitor-state.ndjson"

  updating_config="$(jq -r '.nodePool.updatingConfig.status // ""' <<<"${final_state}")"
  updating_version="$(jq -r '.nodePool.updatingVersion.status // ""' <<<"${final_state}")"
  updating_platform="$(jq -r '.nodePool.updatingPlatformMachineTemplate.status // ""' <<<"${final_state}")"
  status_version="$(jq -r '.nodePool.version // ""' <<<"${final_state}")"
  physical_complete="$(jq -r '.physicalRolloutComplete' <<<"${final_state}")"
  up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' <<<"${final_state}")"
  current_config="$(jq -r '.nodePool.currentConfig // ""' <<<"${final_state}")"
  platform_template="$(jq -r '.nodePool.platformMachineTemplate // ""' <<<"${final_state}")"

  if [[ "${physical_complete}" == "true" && "${up_to_date}" == "0" && "${updating_config}" == "False" && "${updating_version}" == "False" && "${updating_platform}" == "False" && "${status_version}" == "${target_version}" && "${current_config}" != "${pre_current_config}" && "${platform_template}" == "${pre_platform_template}" ]]; then
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
  printf 'config rollout did not complete within 1800 seconds\n' >&2
  exit 1
fi

cat >"${destination}/verification-daemonset.yaml" <<EOF
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
        hypershift.openshift.io/nodePool: ${PATCHED_NODEPOOL}
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

kubectl --kubeconfig "${GUEST_KUBECONFIG}" create -f "${destination}/verification-daemonset.yaml" >"${destination}/create-verification-daemonset.out"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" rollout status daemonset "${daemonset_name}" -n default --timeout=10m >"${destination}/verification-rollout-status.out"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get daemonset "${daemonset_name}" -n default -o json >"${destination}/verification-daemonset.json"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pods -n default -l "app=${daemonset_name}" -o json >"${destination}/verification-pods.json"

mkdir -p "${destination}/verification-logs"
for pod in $(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get pods -n default -l "app=${daemonset_name}" -o name | sed 's|pod/||'); do
  kubectl --kubeconfig "${GUEST_KUBECONFIG}" logs "${pod}" -n default >"${destination}/verification-logs/${pod}.log" 2>&1 || true
done

marker_count="$(find "${destination}/verification-logs" -type f -exec grep -lF "${marker}" {} + | wc -l | tr -d ' ')"
[[ "${marker_count}" -eq 3 ]] || die "custom-config marker was found on ${marker_count} of 3 replacement workers"

completed_epoch="$(date +%s)"
cat >"${destination}/meta.txt" <<EOF
mode=config
nodepool=${CLUSTER_NAMESPACE}/${PATCHED_NODEPOOL}
marker=${marker}
configmap=${CLUSTER_NAMESPACE}/${configmap_name}
daemonset=default/${daemonset_name}
preGeneration=${pre_generation}
preStatusVersion=${pre_status_version}
preSpecRelease=${pre_spec_release}
preCurrentConfig=${pre_current_config}
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
