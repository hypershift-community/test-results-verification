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
output_file="${OUT}/machine-join-threshold.ndjson"
[[ ! -e "${output_file}" ]] || die "refusing to overwrite ${output_file}"
printf '{"timestamp":"%s","event":"watch-start","nodepool":"%s","thresholdSeconds":720}\n' "$(utc_now)" "${NP}" >"${output_file}"

while :; do
  now_epoch="$(date +%s)"
  timestamp="$(utc_now)"
  machinedeployment="$(find_machinedeployment "${NP}")"
  machines='{"items":[]}'
  if [[ -n "${machinedeployment}" ]]; then
    machines="$(kubectl get machines.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq --arg md "${machinedeployment}" '{items:[.items[]|select(.metadata.labels["cluster.x-k8s.io/deployment-name"] == $md)]}')"
  fi
  nodes='{"items":[]}'
  if [[ -n "${GUEST_KUBECONFIG:-}" && -r "${GUEST_KUBECONFIG}" ]]; then
    nodes="$(kubectl --kubeconfig "${GUEST_KUBECONFIG}" get nodes -o json 2>/dev/null || printf '{"items":[]}')"
  fi
  record="$(jq -cn \
    --arg timestamp "${timestamp}" \
    --arg nodepool "${NP}" \
    --argjson nowEpoch "${now_epoch}" \
    --argjson warningSeconds "${JOIN_WARNING_SECONDS}" \
    --argjson thresholdSeconds "${MAX_JOIN_SECONDS}" \
    --argjson machines "${machines}" \
    --argjson nodes "${nodes}" '
      [ $machines.items[] | . as $machine |
        ([ $nodes.items[]? | select(.metadata.name == $machine.status.nodeRef.name) ][0] // {}) as $node |
        {
          name: $machine.metadata.name,
          uid: $machine.metadata.uid,
          createdAt: $machine.metadata.creationTimestamp,
          ageSeconds: ($nowEpoch - ($machine.metadata.creationTimestamp | fromdateiso8601)),
          nodeName: ($machine.status.nodeRef.name // null),
          joined: (($machine.status.nodeRef.name // null) != null),
          nodeReady: (($node.status.conditions[]? | select(.type == "Ready") | .status) // null),
          machineReady: (([$machine.status.conditions[]? | select(.type == "Ready")][0].status) // null),
          nodeReadyTransition: (([$machine.status.conditions[]? | select(.type == "NodeReady")][0].lastTransitionTime) // null)
        }
      ] as $items |
      {
        timestamp: $timestamp,
        nodepool: $nodepool,
        thresholdSeconds: $thresholdSeconds,
        warningSeconds: $warningSeconds,
        machinedeployment: (if $items|length > 0 then $machines.items[0].metadata.labels["cluster.x-k8s.io/deployment-name"] else null end),
        machines: $items,
        warnings: [$items[] | select(.joined == false and .ageSeconds >= $warningSeconds)],
        violations: [$items[] | select(.joined == false and .ageSeconds >= $thresholdSeconds)]
      }')"
  printf '%s\n' "${record}" >>"${output_file}"
  if [[ "$(jq '.violations | length' <<<"${record}")" -gt 0 ]]; then
    printf '12-minute join threshold exceeded for nodepool %s\n' "${NP}" >&2
    exit 3
  fi
  if [[ "${now_epoch}" -ge "${DEADLINE_EPOCH}" ]]; then
    printf '{"timestamp":"%s","event":"watch-complete","nodepool":"%s"}\n' "$(utc_now)" "${NP}" >>"${output_file}"
    exit 0
  fi
  sleep "${INTERVAL_SECONDS}"
done
