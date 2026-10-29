#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_KUBECONFIG="/home/tester/management.kubeconfig"
readonly EVIDENCE_ROOT="/workspace/hypershift/.test-evidence/CNTRLPLANE-4826-20261028-r5"
readonly CLUSTER_NAMESPACE="clusters"
readonly CLUSTER_NAME="test-cntrlplane-4826-r5-hc"
readonly HOSTED_CONTROL_PLANE_NAMESPACE="clusters-test-cntrlplane-4826-r5-hc"
readonly INFRA_ID="test-cntrlplane-4826-r5"
readonly SEED_NODEPOOL="test-cntrlplane-4826-r5-seed"
readonly UNPATCHED_NODEPOOL="test-cntrlplane-4826-r5-base"
readonly PATCHED_NODEPOOL="test-cntrlplane-4826-r5-head"
readonly SCALE_NODEPOOL="test-cntrlplane-4826-r5-scale"
readonly INPLACE_NODEPOOL="test-cntrlplane-4826-r5-inplace"
readonly RELEASE_A="quay.io/openshift-release-dev/ocp-release@sha256:502d2836c126b1a5c2f3f93cf6c43bbb9e0527530a0335ad8d3cbdb01bea8416"
readonly RELEASE_B="quay.io/openshift-release-dev/ocp-release-nightly@sha256:08f0905c06195a76138db7071aa77ae644aea401eb832d51ebbf4fb870698346"
readonly BASE_IMAGE="quay.io/example/hypershift@sha256:a8848bd5281ac07a23eb2f583f506e59aaa60702ff6aa0cb4530884479821839"
readonly PATCHED_IMAGE="quay.io/example/hypershift@sha256:7a2248fdc9d50e99e8b444aa887cea96bdf0023e2e81062f9de21266ddb492a6"
readonly HEAD_COMMIT="ee5691233b08e3271f030ebd24055faa6857fd39"
readonly BASE_COMMIT="ee327075b155839511edc3779510ceb95c93a658"
readonly CAPI_IMAGE="registry.k8s.io/cluster-api/cluster-api-controller:v1.13.4"
readonly CAPI_IMAGE_ID="registry.k8s.io/cluster-api/cluster-api-controller@sha256:7a70942e0b45ae59514ee03cf448b64dbd2d77ef2fd7104e6c104f1c6b6b2013"
readonly PARENT_DNS_ZONE="hcp.example.com"
readonly CHILD_DNS_ZONE="test.hcp.example.com"
readonly DNS_RESOURCE_GROUP="shared-resource-group"
readonly AZURE_SUBSCRIPTION_ID="redacted-subscription-id"
readonly AZURE_CREDS="/home/tester/.azure/self-managed-azure-credentials"
readonly PULL_SECRET="/home/tester/all-the-pull-secrets.json"
readonly OIDC_ISSUER_URL="https://examplesa.blob.core.windows.net/examplesa"
readonly SA_TOKEN_ISSUER_PRIVATE_KEY="/home/tester/tester-dev-azure-self-managed/serviceaccount-signer.private"
readonly MANAGED_RG="test-cntrlplane-4826-hc-test-cntrlplane-4826"
readonly VNET_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/test-cntrlplane-4826-hc-vnet-test-cntrlplane-4826/providers/Microsoft.Network/virtualNetworks/test-cntrlplane-4826-hc-test-cntrlplane-4826"
readonly SUBNET_ID="${VNET_ID}/subnets/default"
readonly NSG_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/test-cntrlplane-4826-hc-nsg-test-cntrlplane-4826/providers/Microsoft.Network/networkSecurityGroups/test-cntrlplane-4826-hc-test-cntrlplane-4826-nsg"
readonly WORKLOAD_IDENTITIES_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workload-identities.json"
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
  local hostedclusters
  hostedclusters="$(kubectl get hostedclusters.hypershift.openshift.io -A -o json | jq '.items | length')"
  [[ "${hostedclusters}" -le 1 ]] || die "expected at most one HostedCluster on the management cluster, found ${hostedclusters}"
}

assert_hostedcluster_exists() {
  kubectl get hostedcluster "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1 || die "HostedCluster ${CLUSTER_NAMESPACE}/${CLUSTER_NAME} does not exist"
}

assert_hostedcluster_absent() {
  if kubectl get hostedcluster "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" >/dev/null 2>&1; then
    die "HostedCluster ${CLUSTER_NAMESPACE}/${CLUSTER_NAME} already exists"
  fi
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
