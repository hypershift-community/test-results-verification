#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

snapshot_pool() {
  local np="$1" out="$2" guest="$3"
  NP="${np}" OUT="${out}" GUEST_KUBECONFIG="${guest}" "${SCRIPT_DIR}/snapshot.sh" >/dev/null
}

pool_nodes_json() {
  local guest="$1" np="$2"
  kubectl --kubeconfig "${guest}" get nodes -l "hypershift.openshift.io/nodePool=${np}" -o json
}

verification_image_for_pool() {
  local guest="$1" np="$2"
  local node_names
  node_names="$(pool_nodes_json "${guest}" "${np}" | jq -r '[.items[].metadata.name] | join(",")')"
  [[ -n "${node_names}" ]] || die "no guest nodes found for ${np}"
  kubectl --kubeconfig "${guest}" get pods -n openshift-machine-config-operator -l k8s-app=kube-rbac-proxy-crio -o json \
    | jq -r --arg nodes "${node_names}" '($nodes|split(",")) as $n | [.items[] | select(.spec.nodeName as $x | ($n|index($x)) != null) | .spec.containers[0].image][0] // ""'
}

assert_pool_stable() {
  local summary="$1" expected_release="$2" expected_version="$3"
  jq -e --arg release "${expected_release}" --arg version "${expected_version}" '
    .nodePool.release == $release and
    .nodePool.version == $version and
    .nodePool.replicas == 3 and
    ([.nodePool.conditions[] | select(.type == "Ready")][0].status == "True") and
    ([.nodePool.conditions[] | select(.type == "UpdatingVersion")][0].status == "False") and
    ([.nodePool.conditions[] | select(.type == "UpdatingConfig")][0].status == "False") and
    ([.nodePool.conditions[] | select(.type == "UpdatingPlatformMachineTemplate")][0].status == "False") and
    .machineDeployment.replicas == 3 and
    .machineDeployment.availableReplicas == 3
  ' "${summary}" >/dev/null || die "NodePool is not in the expected stable three-replica state"
}

write_verdict() {
  local dir="$1" scenario="$2" result="$3" checks_json="$4" notes="$5"
  jq -n \
    --arg scenario "${scenario}" \
    --arg result "${result}" \
    --argjson checks "${checks_json}" \
    --arg notes "${notes}" \
    --arg headCommit "${HEAD_COMMIT}" \
    --arg baseCommit "${BASE_COMMIT}" \
    --arg operatorImage "${PATCHED_IMAGE}" \
    --arg capiImage "${CAPI_IMAGE}" \
    --arg hostedCluster "${CLUSTER_NAMESPACE}/${CLUSTER_NAME}" \
    '{scenario:$scenario,result:$result,checks:$checks,notes:$notes,headCommit:$headCommit,baseCommit:$baseCommit,operatorImage:$operatorImage,capiImage:$capiImage,hostedCluster:$hostedCluster,generatedAt:(now|todate)}' \
    > "${dir}/verdict.json"
}

finalize_evidence() {
  local dir="$1"
  find "${dir}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort > "${dir}/SHA256SUMS"
}

pool_state() {
  local np="$1" guest="$2"
  local nodepool_json md_name md_json sets_json machines_json nodes_json azure_json azure_templates_json
  nodepool_json="$(kubectl get nodepool "${np}" -n "${CLUSTER_NAMESPACE}" -o json)"
  md_name="$(find_machinedeployment "${np}")"
  md_json='{}'
  sets_json='{"items":[]}'
  machines_json='{"items":[]}'
  azure_json='{"items":[]}'
  azure_templates_json='{"items":[]}'
  if [[ -n "${md_name}" ]]; then
    md_json="$(kubectl get machinedeployment "${md_name}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    sets_json="$(kubectl get machinesets.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.ownerReferences[]?.name == $md)]}')"
    machines_json="$(kubectl get machines.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${md_name}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
    azure_json="$(kubectl get azuremachines.infrastructure.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
    azure_templates_json="$(kubectl get azuremachinetemplates.infrastructure.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json)"
  fi
  nodes_json="$(pool_nodes_json "${guest}" "${np}" 2>/dev/null || printf '{"items":[]}')"

  jq -cn \
    --arg timestamp "$(utc_now)" \
    --arg nodepoolName "${np}" \
    --argjson nodepool "${nodepool_json}" \
    --argjson md "${md_json}" \
    --argjson sets "${sets_json}" \
    --argjson machines "${machines_json}" \
    --argjson nodes "${nodes_json}" \
    --argjson azure "${azure_json}" \
    --argjson azureTemplates "${azure_templates_json}" '
      def cond($object; $type): ([$object.status.conditions[]? | select(.type == $type)][0] // {}) | {status, reason, message, observedGeneration, lastTransitionTime};
      ($nodepool.spec.replicas // 0) as $desired |
      ($md.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] // "") as $revision |
      ([$sets.items[]? | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] == $revision)][0] // {}) as $current |
      ($machines.items | map(.spec.infrastructureRef.name) | map(select(. != null))) as $machineInfraNames |
      {
        timestamp: $timestamp,
        nodepoolName: $nodepoolName,
        nodePool: {
          generation: $nodepool.metadata.generation,
          release: $nodepool.spec.release.image,
          version: $nodepool.status.version,
          replicas: $nodepool.status.replicas,
          desiredReplicas: $desired,
          vmSize: $nodepool.spec.platform.azure.vmSize,
          currentConfig: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolCurrentConfig"],
          currentConfigVersion: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"],
          platformMachineTemplate: $nodepool.metadata.annotations["hypershift.openshift.io/nodePoolPlatformMachineTemplate"],
          ready: cond($nodepool; "Ready"),
          updatingVersion: cond($nodepool; "UpdatingVersion"),
          updatingConfig: cond($nodepool; "UpdatingConfig"),
          updatingPlatformMachineTemplate: cond($nodepool; "UpdatingPlatformMachineTemplate")
        },
        machineDeployment: {
          name: ($md.metadata.name // null),
          generation: ($md.metadata.generation // null),
          observedGeneration: ($md.status.observedGeneration // null),
          revision: ($revision // null),
          replicas: ($md.status.replicas // null),
          availableReplicas: ($md.status.availableReplicas // null),
          updatedReplicas: ($md.status.updatedReplicas // null),
          upToDateReplicas: ($md.status.upToDateReplicas // null),
          infrastructureRef: ($md.spec.template.spec.infrastructureRef.name // null)
        },
        currentMachineSet: {
          name: ($current.metadata.name // null),
          revision: ($current.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] // null),
          replicas: ($current.status.replicas // null),
          availableReplicas: ($current.status.availableReplicas // null)
        },
        machineSets: [$sets.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          revision: .metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"],
          replicas: (.status.replicas // 0),
          availableReplicas: (.status.availableReplicas // 0),
          infrastructureRef: .spec.template.spec.infrastructureRef.name
        }],
        oldActiveReplicas: ([$sets.items[]? | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | (.status.replicas // 0)] | add // 0),
        machines: [$machines.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          version: .spec.version,
          nodeName: .status.nodeRef.name,
          infrastructureRef: .spec.infrastructureRef.name,
          ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null)
        }],
        nodes: [$nodes.items[]? | {
          name: .metadata.name,
          uid: .metadata.uid,
          createdAt: .metadata.creationTimestamp,
          kubeletVersion: .status.nodeInfo.kubeletVersion,
          ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null)
        }],
        azureMachines: [$azure.items[]? | select(.metadata.name as $n | ($machineInfraNames | index($n)) != null) | {
          name: .metadata.name,
          vmSize: .spec.vmSize,
          providerID: .spec.providerID,
          provisioningState: (.status.provisioningState // null),
          ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null)
        }],
        azureMachineTemplates: [$azureTemplates.items[]? | {
          name: .metadata.name,
          vmSize: .spec.template.spec.vmSize
        }],
        physicalRolloutComplete: (
          $desired > 0 and
          $md.status.replicas == $desired and
          $md.status.availableReplicas == $desired and
          $md.status.observedGeneration >= $md.metadata.generation and
          ($current.status.replicas // -1) == $desired and
          ($current.status.availableReplicas // -1) == $desired and
          ([$sets.items[]? | select(.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"] != $revision) | select((.status.replicas // 0) > 0)] | length) == 0 and
          ([$machines.items[]? | select(.status.nodeRef.name != null) | select(([.status.conditions[]? | select(.type == "Ready")][0].status // "") == "True")] | length) == $desired and
          ([$nodes.items[]? | select(([.status.conditions[]? | select(.type == "Ready")][0].status // "") == "True")] | length) == $desired
        ),
        zeroComplete: (
          $desired == 0 and
          ($md.status.replicas // 0) == 0 and
          ($md.status.availableReplicas // 0) == 0 and
          ($current.status.replicas // 0) == 0 and
          ([$sets.items[]? | select((.status.replicas // 0) > 0)] | length) == 0 and
          ([$machines.items[]?] | length) == 0 and
          ([$nodes.items[]?] | length) == 0
        )
      }'
}
