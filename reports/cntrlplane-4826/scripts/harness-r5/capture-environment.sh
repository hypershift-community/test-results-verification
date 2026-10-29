#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

assert_management_kubeconfig
destination="$(new_run_dir "${EVIDENCE_ROOT}/environment" state)"

printf 'captured_utc=%s\nkubeconfig=%s\nazure_subscription=%s\n' \
  "$(utc_now)" "${EXPECTED_KUBECONFIG}" "${AZURE_SUBSCRIPTION_ID}" >"${destination}/meta.txt"

cat >"${destination}/commands.txt" <<EOF
KUBECONFIG=${EXPECTED_KUBECONFIG} kubectl get hostedclusters.hypershift.openshift.io -A -o json
KUBECONFIG=${EXPECTED_KUBECONFIG} kubectl get nodepools.hypershift.openshift.io -A -o json
KUBECONFIG=${EXPECTED_KUBECONFIG} kubectl get namespaces -o json
KUBECONFIG=${EXPECTED_KUBECONFIG} kubectl get nodes -o wide
KUBECONFIG=${EXPECTED_KUBECONFIG} kubectl -n hypershift get deployment operator -o json
az group show --subscription ${AZURE_SUBSCRIPTION_ID} -n ${MANAGED_RG}
az resource list --subscription ${AZURE_SUBSCRIPTION_ID} -g ${MANAGED_RG}
az network dns zone show --subscription ${AZURE_SUBSCRIPTION_ID} -g ${DNS_RESOURCE_GROUP} -n ${PARENT_DNS_ZONE}
az network dns zone show --subscription ${AZURE_SUBSCRIPTION_ID} -g ${DNS_RESOURCE_GROUP} -n ${CHILD_DNS_ZONE}
EOF
kubectl get hostedclusters.hypershift.openshift.io -A -o json >"${destination}/hostedclusters.json"
kubectl get nodepools.hypershift.openshift.io -A -o json >"${destination}/nodepools.json"
kubectl get namespaces -o json >"${destination}/namespaces.json"
kubectl get nodes -o wide >"${destination}/management-nodes.txt"
kubectl -n hypershift get deployment operator -o json >"${destination}/hypershift-operator-deployment.json"
kubectl -n hypershift get pods -l name=operator -o wide >"${destination}/hypershift-operator-pods.txt"
kubectl -n hypershift get pods -l name=operator -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name},status:{phase:.status.phase,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready}]}}]}' \
  >"${destination}/hypershift-operator-pods-sanitized.json"

az group show --subscription "${AZURE_SUBSCRIPTION_ID}" -n "${MANAGED_RG}" --query '{name:name,location:location,state:properties.provisioningState}' -o json >"${destination}/managed-resource-group.json"
az group show --subscription "${AZURE_SUBSCRIPTION_ID}" -n test-cntrlplane-4826-hc-vnet-test-cntrlplane-4826 --query '{name:name,location:location,state:properties.provisioningState}' -o json >"${destination}/vnet-resource-group.json"
az group show --subscription "${AZURE_SUBSCRIPTION_ID}" -n test-cntrlplane-4826-hc-nsg-test-cntrlplane-4826 --query '{name:name,location:location,state:properties.provisioningState}' -o json >"${destination}/nsg-resource-group.json"
az resource list --subscription "${AZURE_SUBSCRIPTION_ID}" -g "${MANAGED_RG}" --query '[].{name:name,type:type,location:location}' -o json >"${destination}/managed-resource-group-resources.json"
az network dns zone show --subscription "${AZURE_SUBSCRIPTION_ID}" -g "${DNS_RESOURCE_GROUP}" -n "${PARENT_DNS_ZONE}" --query '{name:name,recordSetCount:numberOfRecordSets,id:id}' -o json >"${destination}/parent-dns-zone.json"
az network dns zone show --subscription "${AZURE_SUBSCRIPTION_ID}" -g "${DNS_RESOURCE_GROUP}" -n "${CHILD_DNS_ZONE}" --query '{name:name,recordSetCount:numberOfRecordSets,id:id}' -o json >"${destination}/child-dns-zone.json"
az storage account show --subscription "${AZURE_SUBSCRIPTION_ID}" -g "${DNS_RESOURCE_GROUP}" -n examplesa --query '{name:name,location:location,state:provisioningState,id:id}' -o json >"${destination}/oidc-storage-account.json" 2>"${destination}/oidc-storage-account.err" || true
az identity list --subscription "${AZURE_SUBSCRIPTION_ID}" -g "${MANAGED_RG}" --query '[].{name:name,clientId:clientId}' -o json >"${destination}/workload-identities.json"
az vm list-usage --subscription "${AZURE_SUBSCRIPTION_ID}" --location eastus --query "[?localName=='Standard DSv5 Family vCPUs'].{name:localName,current:currentValue,limit:limit}" -o json >"${destination}/vcpu-usage.json"

podman images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' >"${destination}/podman-images.txt"
podman system df >"${destination}/podman-system-df.txt" 2>&1 || true
df -h / /home/tester >"${destination}/disk.txt"

find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
