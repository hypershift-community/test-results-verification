#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_KUBECONFIG="/home/tester/management.kubeconfig"
readonly EVIDENCE_ROOT="/workspace/hypershift/.test-evidence/CNTRLPLANE-4826-20261028-r2"
readonly CLUSTER_NAMESPACE="clusters"
readonly CLUSTER_NAME="test-cntrlplane-4826-hc"
readonly HOSTED_CONTROL_PLANE_NAMESPACE="clusters-test-cntrlplane-4826-hc"
readonly SEED_NODEPOOL="test-cntrlplane-4826-hc"
readonly UNPATCHED_NODEPOOL="test-cntrlplane-4826-unpatched"
readonly PATCHED_NODEPOOL="test-cntrlplane-4826-patched"
readonly SCALE_NODEPOOL="test-cntrlplane-4826-scale"
readonly INPLACE_NODEPOOL="test-cntrlplane-4826-inplace"
readonly RELEASE_A="quay.io/openshift-release-dev/ocp-release@sha256:502d2836c126b1a5c2f3f93cf6c43bbb9e0527530a0335ad8d3cbdb01bea8416"
readonly RELEASE_B="quay.io/openshift-release-dev/ocp-release-nightly@sha256:08f0905c06195a76138db7071aa77ae644aea401eb832d51ebbf4fb870698346"
readonly BASE_IMAGE="quay.io/example/hypershift@sha256:e848d7a892cbc144bfe0032ddeaccecde94a7c5e2d84f56c2953fb9e5e535834"
readonly PATCHED_IMAGE="quay.io/example/hypershift@sha256:7bbfc29f4283a5b76ba9d1ee9f6a74864dc874614b26741520ae52d6a887b4a2"
readonly CAPI_IMAGE="registry.k8s.io/cluster-api/cluster-api-controller:v1.14.3"
readonly CAPI_IMAGE_ID="registry.k8s.io/cluster-api/cluster-api-controller@sha256:1110ddb0f4a9cfc1b557f305199e2d56911fe442edef6361e12e5cc4b11e23fd"
readonly PARENT_DNS_ZONE="hcp.example.com"
readonly CHILD_DNS_ZONE="test.hcp.example.com"
readonly DNS_RESOURCE_GROUP="shared-resource-group"
readonly AZURE_SUBSCRIPTION_ID="redacted-subscription-id"
readonly MAX_JOIN_SECONDS=720
readonly JOIN_WARNING_SECONDS=600

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

utc_stamp() {
  date -u +%Y%m%dT%H%M%SZ
}

assert_management_kubeconfig() {
  [[ "${KUBECONFIG:-}" == "${EXPECTED_KUBECONFIG}" ]] || die "KUBECONFIG must be ${EXPECTED_KUBECONFIG}"
  [[ -r "${EXPECTED_KUBECONFIG}" ]] || die "management kubeconfig is not readable"
  kubectl get --raw=/readyz >/dev/null || die "management Kubernetes API is not ready"
  [[ "$(kubectl get hostedclusters.hypershift.openshift.io -A -o json | jq '.items | length')" == "1" ]] || die "expected exactly one HostedCluster on the management cluster"
}

new_evidence_dir() {
  local target="$1"
  [[ ! -e "${target}" ]] || die "refusing to overwrite evidence path ${target}"
  mkdir -p "${target}"
}

new_run_dir() {
  local parent="$1"
  local name="$2"
  local target="${parent}/${name}-$(utc_stamp)"
  new_evidence_dir "${target}"
  printf '%s\n' "${target}"
}

append_command() {
  local log_file="$1"
  shift
  printf '%s\t%s\n' "$(utc_now)" "$*" >>"${log_file}"
}

create_guest_kubeconfig() {
  local destination="$1"
  [[ ! -e "${destination}" ]] || die "guest kubeconfig target already exists: ${destination}"
  local encoded
  encoded="$(kubectl get secret -n "${CLUSTER_NAMESPACE}" "${CLUSTER_NAME}-admin-kubeconfig" -o jsonpath='{.data.kubeconfig}')"
  [[ -n "${encoded}" ]] || die "admin kubeconfig secret returned no data"
  umask 077
  printf '%s' "${encoded}" | base64 -d >"${destination}"
  chmod 0600 "${destination}"
  kubectl --kubeconfig "${destination}" get --raw=/readyz >/dev/null || die "guest Kubernetes API is not ready"
}

find_machinedeployment() {
  local nodepool="$1"
  kubectl get machinedeployments.cluster.x-k8s.io -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json \
    | jq -r --arg nodepool "${CLUSTER_NAMESPACE}/${nodepool}" '.items[] | select(.metadata.annotations["hypershift.openshift.io/nodePool"] == $nodepool) | .metadata.name' \
    | head -n 1
}
