#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${NP:?NP is required}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-15}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
deadline_epoch=$(( $(date +%s) + TIMEOUT_SECONDS ))

assert_management_kubeconfig
while :; do
  nodepool="$(kubectl get nodepool "${NP}" -n "${CLUSTER_NAMESPACE}" -o json 2>/dev/null || printf '{}')"
  summary="$(jq -c '{generation:.metadata.generation,version:.status.version,replicas:.status.replicas,desired:.spec.replicas,ready:([.status.conditions[]?|select(.type=="Ready")][0]//{}|{status,reason,message,observedGeneration}),validRelease:([.status.conditions[]?|select(.type=="ValidReleaseImage")][0]//{}|{status,reason,message,observedGeneration}),supportedSkew:([.status.conditions[]?|select(.type=="SupportedVersionSkew")][0]//{}|{status,reason,message,observedGeneration}),updatingVersion:([.status.conditions[]?|select(.type=="UpdatingVersion")][0]//{}|{status,reason,message}),updatingConfig:([.status.conditions[]?|select(.type=="UpdatingConfig")][0]//{}|{status,reason,message})}' <<<"${nodepool}")"
  printf '%s %s\n' "$(utc_now)" "${summary}"
  ready="$(jq -r '([.status.conditions[]?|select(.type=="Ready")][0].status)//""' <<<"${nodepool}")"
  desired="$(jq -r '.spec.replicas // 0' <<<"${nodepool}")"
  current="$(jq -r '.status.replicas // 0' <<<"${nodepool}")"
  observed_ok="$(jq -r '. as $np | all($np.status.conditions[]? | select(.type == "Ready" or .type == "ValidReleaseImage" or .type == "SupportedVersionSkew"); .observedGeneration >= $np.metadata.generation)' <<<"${nodepool}")"
  valid_release="$(jq -r '([.status.conditions[]?|select(.type=="ValidReleaseImage")][0].status)//""' <<<"${nodepool}")"
  supported_skew="$(jq -r '([.status.conditions[]?|select(.type=="SupportedVersionSkew")][0].status)//""' <<<"${nodepool}")"
  version_ok="true"
  if [[ -n "${EXPECTED_VERSION}" ]]; then
    [[ "$(jq -r '.status.version // ""' <<<"${nodepool}")" == "${EXPECTED_VERSION}" ]] || version_ok="false"
  fi
  if [[ "${ready}" == "True" && "${desired}" == "${current}" && "${observed_ok}" == "true" && "${valid_release}" == "True" && "${supported_skew}" == "True" && "${version_ok}" == "true" ]]; then
    exit 0
  fi
  if [[ "$(date +%s)" -ge "${deadline_epoch}" ]]; then
    printf 'NodePool %s did not become Ready within %s seconds\n' "${NP}" "${TIMEOUT_SECONDS}" >&2
    exit 1
  fi
  sleep "${INTERVAL_SECONDS}"
done
