#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

readonly HYPERSHIFT_BIN="/workspace/hypershift/bin/hypershift"

assert_management_kubeconfig
assert_hostedcluster_absent
[[ -x "${HYPERSHIFT_BIN}" ]] || die "hypershift CLI not found at ${HYPERSHIFT_BIN}"
[[ -r "${AZURE_CREDS}" ]] || die "Azure credentials are not readable"
[[ -r "${PULL_SECRET}" ]] || die "pull secret is not readable"
[[ -r "${SA_TOKEN_ISSUER_PRIVATE_KEY}" ]] || die "service account signer key is not readable"
[[ -r "${WORKLOAD_IDENTITIES_FILE}" ]] || die "workload identities file is not readable"

operator_image="$(kubectl get deployment operator -n hypershift -o jsonpath='{.spec.template.spec.containers[?(@.name=="operator")].image}')"
[[ "${operator_image}" == "${PATCHED_IMAGE}" ]] || die "create-hc requires the head operator ${PATCHED_IMAGE}; found ${operator_image}"

destination="$(new_run_dir "${EVIDENCE_ROOT}/cluster" create)"
export KUBECONFIG="${EXPECTED_KUBECONFIG}"

printf 'started_utc=%s\nhostedcluster=%s/%s\ninfra_id=%s\nmanaged_resource_group=%s\noperator_image=%s\nrelease=%s\ncapi_image=%s\n' \
  "$(utc_now)" "${CLUSTER_NAMESPACE}" "${CLUSTER_NAME}" "${INFRA_ID}" "${MANAGED_RG}" "${operator_image}" "${RELEASE_B}" "${CAPI_IMAGE}" >"${destination}/meta.txt"

cat >"${destination}/create-hc.command.txt" <<EOF
${HYPERSHIFT_BIN} create cluster azure --name ${CLUSTER_NAME} --namespace ${CLUSTER_NAMESPACE} --infra-id ${INFRA_ID} --azure-creds ${AZURE_CREDS} --location eastus --node-pool-replicas -1 --base-domain ${PARENT_DNS_ZONE} --pull-secret ${PULL_SECRET} --generate-ssh --release-image ${RELEASE_B} --resource-group-name ${MANAGED_RG} --vnet-id ${VNET_ID} --subnet-id ${SUBNET_ID} --network-security-group-id ${NSG_ID} --sa-token-issuer-private-key-path ${SA_TOKEN_ISSUER_PRIVATE_KEY} --oidc-issuer-url ${OIDC_ISSUER_URL} --dns-zone-rg-name ${DNS_RESOURCE_GROUP} --external-dns-domain ${CHILD_DNS_ZONE} --workload-identities-file ${WORKLOAD_IDENTITIES_FILE} --diagnostics-storage-account-type Managed --control-plane-availability-policy SingleReplica --infra-availability-policy SingleReplica --annotations hypershift.openshift.io/capi-manager-image=${CAPI_IMAGE}
EOF

"${HYPERSHIFT_BIN}" create cluster azure \
  --kubeconfig "${EXPECTED_KUBECONFIG}" \
  --name "${CLUSTER_NAME}" \
  --namespace "${CLUSTER_NAMESPACE}" \
  --infra-id "${INFRA_ID}" \
  --azure-creds "${AZURE_CREDS}" \
  --location eastus \
  --node-pool-replicas -1 \
  --base-domain "${PARENT_DNS_ZONE}" \
  --pull-secret "${PULL_SECRET}" \
  --generate-ssh \
  --release-image "${RELEASE_B}" \
  --resource-group-name "${MANAGED_RG}" \
  --vnet-id "${VNET_ID}" \
  --subnet-id "${SUBNET_ID}" \
  --network-security-group-id "${NSG_ID}" \
  --sa-token-issuer-private-key-path "${SA_TOKEN_ISSUER_PRIVATE_KEY}" \
  --oidc-issuer-url "${OIDC_ISSUER_URL}" \
  --dns-zone-rg-name "${DNS_RESOURCE_GROUP}" \
  --external-dns-domain "${CHILD_DNS_ZONE}" \
  --workload-identities-file "${WORKLOAD_IDENTITIES_FILE}" \
  --diagnostics-storage-account-type Managed \
  --control-plane-availability-policy SingleReplica \
  --infra-availability-policy SingleReplica \
  --annotations "hypershift.openshift.io/capi-manager-image=${CAPI_IMAGE}" \
  >"${destination}/create.out" 2>&1

kubectl get hostedcluster "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json >"${destination}/hostedcluster-after-create.json"
jq -e --arg image "${CAPI_IMAGE}" '.metadata.annotations["hypershift.openshift.io/capi-manager-image"] == $image' \
  "${destination}/hostedcluster-after-create.json" >/dev/null || die "CAPI manager override was not applied to the HostedCluster"

deadline=$(( $(date +%s) + 1800 ))
while :; do
  hc="$(kubectl get hostedcluster "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json)"
  available="$(jq -r '[.status.conditions[]? | select(.type == "Available")][0].status // ""' <<<"${hc}")"
  degraded="$(jq -r '[.status.conditions[]? | select(.type == "Degraded")][0].status // ""' <<<"${hc}")"
  printf '%s available=%s degraded=%s\n' "$(utc_now)" "${available}" "${degraded}" >>"${destination}/wait-available.log"
  if [[ "${available}" == "True" && "${degraded}" != "True" ]]; then
    break
  fi
  [[ "$(date +%s)" -lt "${deadline}" ]] || die "HostedCluster did not become Available within 30 minutes"
  sleep 15
done

kubectl get hostedcontrolplane -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${destination}/hostedcontrolplane.json"
kubectl get deployment cluster-api -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${destination}/cluster-api-deployment.json"
jq -e --arg image "${CAPI_IMAGE}" 'any(.spec.template.spec.containers[]; .name == "manager" and .image == $image)' \
  "${destination}/cluster-api-deployment.json" >/dev/null || die "cluster-api deployment is not using ${CAPI_IMAGE}"

create_guest_kubeconfig "${destination}/guest.kubeconfig"
kubectl --kubeconfig "${destination}/guest.kubeconfig" get clusterversion version -o json >"${destination}/guest-clusterversion.json"
kubectl --kubeconfig "${destination}/guest.kubeconfig" get nodes -o json >"${destination}/guest-nodes-empty.json"

printf 'completed_utc=%s\ncluster_api_image=%s\n' "$(utc_now)" "${CAPI_IMAGE}" >>"${destination}/meta.txt"
find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
