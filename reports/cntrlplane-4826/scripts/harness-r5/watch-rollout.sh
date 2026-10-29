#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${NP:?NP is required}"
: "${OUT:?OUT is required}"
: "${DEADLINE_EPOCH:?DEADLINE_EPOCH is required}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-10}"

assert_management_kubeconfig
mkdir -p "${OUT}"
output_file="${OUT}/rollout-watch.ndjson"
[[ ! -e "${output_file}" ]] || die "refusing to overwrite ${output_file}"
printf '{"timestamp":"%s","event":"watch-start","nodepool":"%s"}\n' "$(utc_now)" "${NP}" >"${output_file}"

while :; do
  timestamp="$(utc_now)"
  now_epoch="$(date +%s)"
  nodepool="$(kubectl get nodepool "${NP}" -n "${CLUSTER_NAMESPACE}" -o json 2>/dev/null || printf '{}')"
  machinedeployment_name="$(find_machinedeployment "${NP}")"
  machinedeployment='{}'
  if [[ -n "${machinedeployment_name}" ]]; then
    machinedeployment="$(kubectl get machinedeployment "${machinedeployment_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json 2>/dev/null || printf '{}')"
  fi
  machinesets="$(kubectl get machinesets.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${machinedeployment_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
  machines="$(kubectl get machines.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${machinedeployment_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
  nodes='{"items":[]}'
  if [[ -n "${GUEST_KUBECONFIG:-}" && -r "${GUEST_KUBECONFIG}" ]]; then
    nodes="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -o json 2>/dev/null || printf '{"items":[]}')"
  fi
  operator="$(kubectl get deployment operator -n hypershift -o json)"
  capi="$(kubectl get deployment cluster-api -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
  record="$(jq -cn \
    --arg timestamp "${timestamp}" \
    --arg nodepoolName "${NP}" \
    --argjson nodepool "${nodepool}" \
    --argjson machinedeployment "${machinedeployment}" \
    --argjson machinesets "${machinesets}" \
    --argjson machines "${machines}" \
    --argjson nodes "${nodes}" \
    --argjson operator "${operator}" \
    --argjson capi "${capi}" '
      def cond($object; $type): ([$object.status.conditions[]? | select(.type == $type)][0] // {}) | {status, reason, message, observedGeneration, lastTransitionTime};
      {
        timestamp: $timestamp,
        nodepool: {
          name: $nodepoolName,
          uid: ($nodepool.metadata.uid // null),
          generation: ($nodepool.metadata.generation // null),
          resourceVersion: ($nodepool.metadata.resourceVersion // null),
          release: ($nodepool.spec.release.image // null),
          version: ($nodepool.status.version // null),
          replicas: ($nodepool.status.replicas // null),
          annotations: ($nodepool.metadata.annotations // {}),
          ready: cond($nodepool; "Ready"),
          updatingVersion: cond($nodepool; "UpdatingVersion"),
          updatingConfig: cond($nodepool; "UpdatingConfig"),
          updatingPlatformMachineTemplate: cond($nodepool; "UpdatingPlatformMachineTemplate"),
          allMachinesReady: cond($nodepool; "AllMachinesReady"),
          allNodesHealthy: cond($nodepool; "AllNodesHealthy")
        },
        machinedeployment: {
          name: ($machinedeployment.metadata.name // null),
          uid: ($machinedeployment.metadata.uid // null),
          generation: ($machinedeployment.metadata.generation // null),
          observedGeneration: ($machinedeployment.status.observedGeneration // null),
          revision: ($machinedeployment.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] // null),
          templateVersion: ($machinedeployment.spec.template.spec.version // null),
          replicas: ($machinedeployment.status.replicas // null),
          availableReplicas: ($machinedeployment.status.availableReplicas // null),
          updatedReplicas: ($machinedeployment.status.updatedReplicas // null),
          upToDateReplicas: ($machinedeployment.status.upToDateReplicas // null),
          machinesReady: cond($machinedeployment; "MachinesReady"),
          machinesUpToDate: cond($machinedeployment; "MachinesUpToDate")
        },
        machinesets: [$machinesets.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          revision: .metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"],
          templateVersion: .spec.template.spec.version,
          replicas: .status.replicas,
          availableReplicas: .status.availableReplicas,
          readyReplicas: .status.readyReplicas
        }],
        machines: [$machines.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          version: .spec.version,
          nodeName: .status.nodeRef.name,
          providerID: .spec.providerID,
          ready: cond(.; "Ready"),
          nodeReady: cond(.; "NodeReady"),
          upToDate: cond(.; "UpToDate")
        }],
        nodes: [$nodes.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          kubeletVersion: .status.nodeInfo.kubeletVersion,
          ready: cond(.; "Ready")
        }],
        managementOperator: {
          generation: ($operator.metadata.generation // null),
          observedGeneration: ($operator.status.observedGeneration // null),
          readyReplicas: ($operator.status.readyReplicas // null),
          images: [($operator.spec.template.spec.containers[]? | {name, image}), ($operator.spec.template.spec.initContainers[]? | {name, image})]
        },
        capi: {
          image: ($capi.spec.template.spec.containers[0].image // null),
          readyReplicas: ($capi.status.readyReplicas // null)
        }
      }')"
  printf '%s\n' "${record}" >>"${output_file}"
  if [[ "${now_epoch}" -ge "${DEADLINE_EPOCH}" ]]; then
    printf '{"timestamp":"%s","event":"watch-complete","nodepool":"%s"}\n' "$(utc_now)" "${NP}" >>"${output_file}"
    exit 0
  fi
  sleep "${INTERVAL_SECONDS}"
done

