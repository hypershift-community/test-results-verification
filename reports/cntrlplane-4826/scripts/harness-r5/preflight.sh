#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

assert_management_kubeconfig
mkdir -p "${EVIDENCE_ROOT}"
destination="$(new_run_dir "${EVIDENCE_ROOT}/preflight" "preflight")"

printf 'started_utc=%s\nkubeconfig=%s\nhostedcluster=%s/%s\nsource_commit=%s\nrelease_a=%s\nrelease_b=%s\nbase_image=%s\npatched_image=%s\ncapi_image=%s\nazure_subscription=%s\n' \
  "$(utc_now)" "${EXPECTED_KUBECONFIG}" "${CLUSTER_NAMESPACE}" "${CLUSTER_NAME}" \
  "$(git -C /workspace/hypershift rev-parse HEAD)" \
  "${RELEASE_A}" "${RELEASE_B}" "${BASE_IMAGE}" "${PATCHED_IMAGE}" "${CAPI_IMAGE}" "${AZURE_SUBSCRIPTION_ID}" >"${destination}/meta.txt"
git -C /workspace/hypershift status --short >"${destination}/source-git-status.txt"
find "${SCRIPT_DIR}" -maxdepth 1 -type f -print0 | xargs -0 shasum -a 256 | sort >"${destination}/test-script-hashes-before.sha256"
kubectl config view --minify -o json \
  | jq '{kind,apiVersion,clusters:[.clusters[]|{name,cluster:{server:.cluster.server}}],contexts,"current-context":.["current-context"]}' \
  >"${destination}/kubeconfig-sanitized.json"
kubectl get hostedclusters.hypershift.openshift.io -A -o json >"${destination}/hostedclusters-all.json"
kubectl get nodepools.hypershift.openshift.io -A -o json >"${destination}/nodepools-all.json"
kubectl get hostedcontrolplanes.hypershift.openshift.io -A -o json >"${destination}/hostedcontrolplanes-all.json"
kubectl get namespaces -o json >"${destination}/namespaces.json"
kubectl get hostedcluster "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json >"${destination}/hostedcluster.json"
kubectl get nodepool "${SEED_NODEPOOL}" -n "${CLUSTER_NAMESPACE}" -o json >"${destination}/seed-nodepool.json"
kubectl get deployment cluster-api -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json >"${destination}/capi-deployment.json"
kubectl get pods -n "${HOSTED_CONTROL_PLANE_NAMESPACE}" -o json | jq '{items:[.items[]|select(any(.metadata.labels|to_entries[]?; .key=="name" and .value=="cluster-api"))|{metadata:{name:.metadata.name},status:{phase:.status.phase,containerStatuses:[.status.containerStatuses[]?|{image,imageID,ready}]}}]}' >"${destination}/capi-pods.json"
kubectl get deployment operator -n hypershift -o json >"${destination}/operator-deployment.json"
kubectl get pods -n hypershift -l name=operator -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
  >"${destination}/operator-pods-sanitized.json"

jq -e '.items | length == 1' "${destination}/hostedclusters-all.json" >/dev/null || die "expected exactly one HostedCluster"
jq -e --arg name "${CLUSTER_NAME}" '.items[0].metadata.name == $name' "${destination}/hostedclusters-all.json" >/dev/null || die "unexpected HostedCluster inventory"
jq -e '.spec.template.spec.containers[0].image == "registry.k8s.io/cluster-api/cluster-api-controller:v1.14.3"' "${destination}/capi-deployment.json" >/dev/null || die "CAPI deployment is not v1.14.3"
jq -e --arg imageID "${CAPI_IMAGE_ID}" '.items[0].status.containerStatuses[0].imageID == $imageID' "${destination}/capi-pods.json" >/dev/null || die "CAPI pod imageID does not match the verified digest"

cp /workspace/hypershift/.test-evidence/CNTRLPLANE-4826-20261027-1740/scripts/custom-ingress-scripts-before.sha256 "${destination}/existing-scripts-before.sha256"
while IFS= read -r expected_hash && IFS= read -r path; do
  actual_hash="$(shasum -a 256 "${path}" | awk '{print $1}')"
  [[ "${actual_hash}" == "${expected_hash}" ]] || die "existing custom-ingress script changed: ${path}"
done < <(awk '{print $1"\n"$2}' "${destination}/existing-scripts-before.sha256")
find /workspace/private-hypershift-scripts/azure/custom-ingress -maxdepth 1 -type f -print0 \
  | xargs -0 shasum -a 256 | sort >"${destination}/existing-directory-live-inventory.sha256"
comm -13 \
  <(awk '{print $2}' "${destination}/existing-scripts-before.sha256" | sort) \
  <(awk '{print $2}' "${destination}/existing-directory-live-inventory.sha256" | sort) \
  >"${destination}/existing-script-directory-new-files.txt"
printf 'existing tracked scripts verified unchanged; added non-script files: %s\n' "$(wc -l <"${destination}/existing-script-directory-new-files.txt" | tr -d ' ')" >"${destination}/existing-scripts-check.txt"

printf 'base_image_inspect_utc=%s\n' "$(utc_now)" >"${destination}/image-provenance.txt"
skopeo inspect --authfile /home/tester/all-the-pull-secrets.json "docker://${BASE_IMAGE}" 2>>"${destination}/image-provenance.err" | jq '{Digest,Architecture,Os,Created}' >>"${destination}/image-provenance.txt"
printf 'base_commit_utc=%s\n' "$(utc_now)" >>"${destination}/image-provenance.txt"
podman run --rm --platform linux/amd64 --entrypoint /usr/bin/hypershift "${BASE_IMAGE}" version 2>&1 | sed -n '1p' >>"${destination}/image-provenance.txt"
printf 'patched_image_inspect_utc=%s\n' "$(utc_now)" >>"${destination}/image-provenance.txt"
skopeo inspect --authfile /home/tester/all-the-pull-secrets.json "docker://${PATCHED_IMAGE}" 2>>"${destination}/image-provenance.err" | jq '{Digest,Architecture,Os,Created}' >>"${destination}/image-provenance.txt"
printf 'patched_commit_utc=%s\n' "$(utc_now)" >>"${destination}/image-provenance.txt"
podman run --rm --platform linux/amd64 --entrypoint /usr/bin/hypershift "${PATCHED_IMAGE}" version 2>&1 | sed -n '1p' >>"${destination}/image-provenance.txt"
rg -q 'dbe3111415dc623f9d75a99e4afc21e3c73463f9' "${destination}/image-provenance.txt" || die "base image commit is not dbe3111415"
rg -q 'ff673589287e8f7685435f117cfec1f14c067def' "${destination}/image-provenance.txt" || die "patched image commit is not ff67358928"

printf 'release_verification_utc=%s\n' "$(utc_now)" >"${destination}/release-provenance.txt"
oc adm release info -a /home/tester/all-the-pull-secrets.json "${RELEASE_A}" -o json >"${destination}/release-a.json"
oc adm release info -a /home/tester/all-the-pull-secrets.json "${RELEASE_B}" -o json >"${destination}/release-b.json"
jq '{image:.image,digest:.digest,version:.metadata.version}' "${destination}/release-a.json" >>"${destination}/release-provenance.txt"
jq '{image:.image,digest:.digest,version:.metadata.version}' "${destination}/release-b.json" >>"${destination}/release-provenance.txt"
jq -e '.metadata.version == "5.0.0-rc.7"' "${destination}/release-a.json" >/dev/null || die "release A is not 5.0.0-rc.7"
jq -e '.metadata.version == "5.1.0-0.nightly-multi-2026-10-27-082258"' "${destination}/release-b.json" >/dev/null || die "release B is not the expected 5.1 nightly"

printf 'azure_snapshot_utc=%s\n' "$(utc_now)" >"${destination}/azure-dns-meta.txt"
az group show --subscription "${AZURE_SUBSCRIPTION_ID}" --name "${DNS_RESOURCE_GROUP}" -o json >"${destination}/azure-rg-shared-resource-group.json"
az network dns zone show --subscription "${AZURE_SUBSCRIPTION_ID}" --resource-group "${DNS_RESOURCE_GROUP}" --name "${PARENT_DNS_ZONE}" -o json >"${destination}/azure-dns-parent-zone.json"
az network dns zone show --subscription "${AZURE_SUBSCRIPTION_ID}" --resource-group "${DNS_RESOURCE_GROUP}" --name "${CHILD_DNS_ZONE}" -o json >"${destination}/azure-dns-child-zone.json"
child_zone_id="$(jq -r '.id' "${destination}/azure-dns-child-zone.json")"
parent_zone_id="$(jq -r '.id' "${destination}/azure-dns-parent-zone.json")"
az role assignment list --subscription "${AZURE_SUBSCRIPTION_ID}" --scope "${child_zone_id}" --include-inherited -o json >"${destination}/azure-dns-child-role-assignments.json"
az role assignment list --subscription "${AZURE_SUBSCRIPTION_ID}" --scope "${parent_zone_id}" --include-inherited -o json >"${destination}/azure-dns-parent-role-assignments.json"
az vm list-usage --subscription "${AZURE_SUBSCRIPTION_ID}" --location eastus -o json >"${destination}/azure-vm-usage.json"
jq '{id,location,managedBy,tags}' "${destination}/azure-rg-shared-resource-group.json" >"${destination}/azure-rg-shared-resource-group-stable.json"
jq '{id,etag,name,numberOfRecordSets}' "${destination}/azure-dns-parent-zone.json" >"${destination}/azure-dns-parent-zone-stable.json"
jq '{id,etag,name,numberOfRecordSets}' "${destination}/azure-dns-child-zone.json" >"${destination}/azure-dns-child-zone-stable.json"
jq 'sort_by(.id) | map({id,roleDefinitionId,principalId,scope})' "${destination}/azure-dns-child-role-assignments.json" >"${destination}/azure-dns-child-role-assignments-stable.json"
jq 'sort_by(.id) | map({id,roleDefinitionId,principalId,scope})' "${destination}/azure-dns-parent-role-assignments.json" >"${destination}/azure-dns-parent-role-assignments-stable.json"
shasum -a 256 \
  "${destination}/azure-rg-shared-resource-group-stable.json" \
  "${destination}/azure-dns-parent-zone-stable.json" \
  "${destination}/azure-dns-child-zone-stable.json" \
  "${destination}/azure-dns-child-role-assignments-stable.json" \
  "${destination}/azure-dns-parent-role-assignments-stable.json" \
  >"${destination}/azure-dns-stable.sha256"

printf 'completed_utc=%s\n' "$(utc_now)" >>"${destination}/meta.txt"
find "${destination}" -type f ! -name SHA256SUMS -print0 | xargs -0 shasum -a 256 | sort >"${destination}/SHA256SUMS"
printf '%s\n' "${destination}"
