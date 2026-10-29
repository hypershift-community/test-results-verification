#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${NP:?NP is required}"
: "${OUT:?OUT is required}"
: "${GUEST_KUBECONFIG:?GUEST_KUBECONFIG is required}"

assert_management_kubeconfig
[[ "${NP}" == test-cntrlplane-4826-* ]] || die "unexpected NodePool name"
new_evidence_dir "${OUT}"

captured_at="$(utc_now)"
printf '%s\n' "${captured_at}" >"${OUT}/captured-at.txt"
printf 'KUBECONFIG=%s\nNP=%s\ncaptured_at=%s\n' "${EXPECTED_KUBECONFIG}" "${NP}" "${captured_at}" >"${OUT}/meta.txt"

kubectl get hostedclusters.hypershift.openshift.io "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json >"${OUT}/hostedcluster.json"
kubectl get hostedcontrolplanes.hypershift.openshift.io "${CLUSTER_NAME}" -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/hostedcontrolplane.json"
kubectl get nodepools.hypershift.openshift.io "${NP}" -n "${CLUSTER_NAMESPACE}" -o json >"${OUT}/nodepool.json"
kubectl get machinedeployments.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/machinedeployments.json"
kubectl get machinesets.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/machinesets.json"
kubectl get machines.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/machines.json"
kubectl get azuremachines.infrastructure.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/azuremachines.json"
kubectl get deployments.apps -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${OUT}/hcp-deployments.json"
kubectl get pods -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name,namespace:.metadata.namespace,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
  >"${OUT}/hcp-pods-sanitized.json"
kubectl get deployment operator -n hypershift -o json >"${OUT}/hypershift-operator-deployment.json"
kubectl get pods -n hypershift -l name=operator -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
  >"${OUT}/hypershift-operator-pods-sanitized.json"
kubectl get events -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${OUT}/hcp-events.json"
kubectl get events -n "${CLUSTER_NAMESPACE}" --sort-by=.lastTimestamp -o json >"${OUT}/clusters-events.json"

kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -l "hypershift.openshift.io/nodePool=${NP}" -o json >"${OUT}/guest-nodes.json"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get clusterversion version -o json >"${OUT}/guest-clusterversion.json"
kubectl --kubeconfig "${GUEST_KUBECONFIG}" get clusteroperators.config.openshift.io -o json >"${OUT}/guest-clusteroperators.json"

md_name="$(find_machinedeployment "${NP}")"
[[ -n "${md_name}" ]] || die "no MachineDeployment found for ${NP}"
printf '%s\n' "${md_name}" >"${OUT}/machinedeployment-name.txt"

jq -n \
  --arg capturedAt "${captured_at}" \
  --arg nodepoolName "${NP}" \
  --arg machinedeploymentName "${md_name}" \
  --slurpfile hc "${OUT}/hostedcluster.json" \
  --slurpfile hcp "${OUT}/hostedcontrolplane.json" \
  --slurpfile np "${OUT}/nodepool.json" \
  --slurpfile mds "${OUT}/machinedeployments.json" \
  --slurpfile sets "${OUT}/machinesets.json" \
  --slurpfile machines "${OUT}/machines.json" \
  --slurpfile nodes "${OUT}/guest-nodes.json" \
  --slurpfile operator "${OUT}/hypershift-operator-deployment.json" '
    def cond($object; $type): ([$object.status.conditions[]? | select(.type == $type)][0] // {}) | {status, reason, message, observedGeneration, lastTransitionTime};
    ($hc[0]) as $hc | ($hcp[0]) as $hcp | ($np[0]) as $np |
    ($mds[0].items[] | select(.metadata.name == $machinedeploymentName)) as $md |
    ($sets[0].items | map(select(.metadata.ownerReferences[]?.name == $machinedeploymentName))) as $ownedSets |
    ($machines[0].items | map(select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $machinedeploymentName))) as $ownedMachines |
    {
      capturedAt: $capturedAt,
      nodepoolName: $nodepoolName,
      machinedeploymentName: $machinedeploymentName,
      hostedCluster: {
        uid: $hc.metadata.uid,
        generation: $hc.metadata.generation,
        release: $hc.spec.release.image,
        version: $hc.status.version.desired.version,
        available: cond($hc; "Available"),
        degraded: cond($hc; "Degraded")
      },
      hostedControlPlane: {
        uid: $hcp.metadata.uid,
        generation: $hcp.metadata.generation,
        available: cond($hcp; "Available"),
        version: $hcp.status.version
      },
      nodePool: {
        uid: $np.metadata.uid,
        generation: $np.metadata.generation,
        release: $np.spec.release.image,
        version: $np.status.version,
        replicas: $np.status.replicas,
        annotations: $np.metadata.annotations,
        conditions: [$np.status.conditions[]? | {type, status, reason, message, observedGeneration, lastTransitionTime}]
      },
      machineDeployment: {
        uid: $md.metadata.uid,
        generation: $md.metadata.generation,
        observedGeneration: $md.status.observedGeneration,
        revision: $md.metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"],
        replicas: $md.status.replicas,
        availableReplicas: $md.status.availableReplicas,
        updatedReplicas: $md.status.updatedReplicas,
        upToDateReplicas: $md.status.upToDateReplicas,
        conditions: [$md.status.conditions[]? | {type, status, reason, message, observedGeneration, lastTransitionTime}]
      },
      ownedMachineSets: [$ownedSets[] | {
        name: .metadata.name,
        uid: .metadata.uid,
        creationTimestamp: .metadata.creationTimestamp,
        revision: .metadata.annotations["machinedeployment.clusters.x-k8s.io/revision"],
        replicas: .status.replicas,
        availableReplicas: .status.availableReplicas
      }],
      ownedMachines: [$ownedMachines[] | {
        name: .metadata.name,
        uid: .metadata.uid,
        creationTimestamp: .metadata.creationTimestamp,
        nodeName: .status.nodeRef.name,
        version: .spec.version,
        ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null),
        nodeReady: (([.status.conditions[]? | select(.type == "NodeReady")][0] // {}) | {status, lastTransitionTime, reason, message}),
        upToDate: ([.status.conditions[]? | select(.type == "UpToDate")][0] // {} | {status, lastTransitionTime, reason, message})
      }],
      guestNodes: [$nodes[0].items[]? | {
        name: .metadata.name,
        uid: .metadata.uid,
        created: .metadata.creationTimestamp,
        kubeletVersion: .status.nodeInfo.kubeletVersion,
        ready: ([.status.conditions[]? | select(.type == "Ready")][0].status // null)
      }],
      managementOperator: {
        uid: $operator[0].metadata.uid,
        generation: $operator[0].metadata.generation,
        observedGeneration: $operator[0].status.observedGeneration,
        readyReplicas: $operator[0].status.readyReplicas,
        images: [$operator[0].spec.template.spec.containers[]? | {name, image}]
      }
    }' >"${OUT}/summary.json"

find "${OUT}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${OUT}/SHA256SUMS"
printf '%s\n' "${OUT}"
