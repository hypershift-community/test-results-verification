#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'usage: %s NAME RELEASE RELEASE_LABEL REPLICAS REPLACE|INPLACE --create\n' "$0" >&2
  exit 2
}

[[ $# -eq 6 ]] || usage
assert_management_kubeconfig

name="$1"
release="$2"
release_label="$3"
replicas="$4"
upgrade_type="$5"
extra_arg="$6"

[[ "${extra_arg}" == "--create" ]] || die "final argument must be --create"
[[ "${name}" == test-cntrlplane-4826-* ]] || die "unexpected NodePool name"
[[ "${replicas}" =~ ^[0-9]+$ ]] || die "replicas must be an integer"
[[ "${upgrade_type}" == "REPLACE" || "${upgrade_type}" == "INPLACE" ]] || die "upgrade type must be REPLACE or INPLACE"
if kubectl get nodepool "${name}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
  die "NodePool ${name} already exists"
fi

destination="${EVIDENCE_ROOT}/nodepools/${name}-create-$(utc_stamp)"
new_evidence_dir "${destination}"

if [[ -n "${TEMPLATE_FILE:-}" ]]; then
  [[ -r "${TEMPLATE_FILE}" ]] || die "template file is not readable: ${TEMPLATE_FILE}"
  seed_json="$(cat "${TEMPLATE_FILE}")"
else
  seed_json="$(kubectl get nodepool "${SEED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json)"
fi
jq -n \
  --argjson seed "${seed_json}" \
  --arg name "${name}" \
  --arg namespace "${CLUSTER_NAMESPACE}" \
  --arg release "${release}" \
  --argjson replicas "${replicas}" \
  --arg upgradeType "${upgrade_type}" '
    $seed
    | .metadata = {name: $name, namespace: $namespace}
    | .spec.release.image = $release
    | .spec.replicas = $replicas
    | if $upgradeType == "INPLACE" then
        .spec.management = {upgradeType: "InPlace"}
      else
        .spec.management = {
          upgradeType: "Replace",
          autoRepair: false,
          replace: {
            strategy: "RollingUpdate",
            rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
          }
        }
      end
    | del(.status)' >"${destination}/nodepool-request.json"

printf 'created_utc=%s\nname=%s\nrelease=%s\nrelease_label=%s\nreplicas=%s\nupgrade_type=%s\n' \
  "$(utc_now)" "${name}" "${release}" "${release_label}" "${replicas}" "${upgrade_type}" >"${destination}/meta.txt"
printf 'kubectl create -f nodepool-request.json\n' >"${destination}/commands.txt"
kubectl create -f "${destination}/nodepool-request.json" >"${destination}/create.out"
kubectl get nodepool "${name}" -n "${CLUSTER_NAMESPACE}" -o json >"${destination}/nodepool-after-create.json"
printf '%s\n' "${destination}"
