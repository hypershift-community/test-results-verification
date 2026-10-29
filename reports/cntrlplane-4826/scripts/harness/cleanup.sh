#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

mode="${1:-dry-run}"
case "${mode}" in
  dry-run|apply) ;;
  *) die "usage: $0 dry-run|apply" ;;
esac

assert_management_kubeconfig
nodepools=("${UNPATCHED_NODEPOOL}" "${PATCHED_NODEPOOL}" "${SCALE_NODEPOOL}" "${INPLACE_NODEPOOL}")

printf 'The following Kubernetes resources would be deleted:\n'
for nodepool in "${nodepools[@]}"; do
  if kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
    printf 'NodePool %s/%s\n' "${CLUSTER_NAMESPACE}" "${nodepool}"
  fi
done

if [[ "${mode}" == "dry-run" ]]; then
  exit 0
fi

destination="${EVIDENCE_ROOT}/cleanup/$(utc_stamp)"
new_evidence_dir "${destination}"
for nodepool in "${nodepools[@]}"; do
  if kubectl get nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
    printf '%s kubectl delete nodepool %s -n %s --wait=false\n' "$(utc_now)" "${nodepool}" "${CLUSTER_NAMESPACE}" >>"${destination}/commands.txt"
    kubectl delete nodepool "${nodepool}" -n "${CLUSTER_NAMESPACE}" --wait=false >>"${destination}/delete.out" 2>&1
  fi
done

printf 'NodePools submitted for Kubernetes deletion. Azure infrastructure and DNS were not touched.\n'
