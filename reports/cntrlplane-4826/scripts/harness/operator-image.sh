#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'usage: %s capture|base|patched|restore\n' "$0" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
assert_management_kubeconfig

action="$1"
base_dir="${EVIDENCE_ROOT}/operator"
original_deployment="${base_dir}/original-deployment.json"
mkdir -p "${base_dir}"

if [[ "${action}" == "capture" ]]; then
  destination="$(new_run_dir "${base_dir}" capture)"
  kubectl get deployment operator -n hypershift -o json >"${original_deployment}.tmp"
  mv "${original_deployment}.tmp" "${original_deployment}"
  cp "${original_deployment}" "${destination}/deployment.json"
  kubectl get pods -n hypershift -l name=operator -o json \
    | jq '{items:[.items[]|{metadata:{name:.metadata.name,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
    >"${destination}/pods-sanitized.json"
  jq '{images:[.spec.template.spec.containers[]?|{name,image}]+[.spec.template.spec.initContainers[]?|{name,image}],generation:.metadata.generation,observedGeneration:.status.observedGeneration,readyReplicas:.status.readyReplicas}' "${original_deployment}" >"${destination}/summary.json"
  printf '%s\n' "${destination}"
  exit 0
fi

[[ -r "${original_deployment}" ]] || die "run operator-image.sh capture before changing the operator"

case "${action}" in
  base)
    target_image="${BASE_IMAGE}"
    ;;
  patched)
    target_image="${PATCHED_IMAGE}"
    ;;
  restore)
    target_image="$(jq -r '.spec.template.spec.containers[] | select(.name == "operator") | .image' "${original_deployment}")"
    ;;
  *)
    usage
    ;;
esac

init_image="$(jq -r '.spec.template.spec.initContainers[] | select(.name == "init-environment") | .image' "${original_deployment}")"
if [[ "${action}" != "restore" ]]; then
  init_image="${target_image}"
fi

destination="$(new_run_dir "${base_dir}" "${action}")"
printf 'started_utc=%s\noperator_image=%s\ninit_image=%s\n' "$(utc_now)" "${target_image}" "${init_image}" >"${destination}/meta.txt"
kubectl get deployment operator -n hypershift -o json >"${destination}/deployment-before.json"
kubectl get pods -n hypershift -l name=operator -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
  >"${destination}/pods-before-sanitized.json"

printf 'kubectl -n hypershift set image deployment/operator operator=%s init-environment=%s\n' "${target_image}" "${init_image}" >>"${destination}/commands.txt"
kubectl -n hypershift set image deployment/operator "operator=${target_image}" "init-environment=${init_image}" >"${destination}/set-image.out"
kubectl -n hypershift rollout status deployment/operator --timeout=10m >"${destination}/rollout-status.out"
kubectl wait --for=condition=available deployment/operator -n hypershift --timeout=2m >"${destination}/wait-available.out"

kubectl get deployment operator -n hypershift -o json >"${destination}/deployment-after.json"
kubectl get pods -n hypershift -l name=operator -o json \
  | jq '{items:[.items[]|{metadata:{name:.metadata.name,labels:.metadata.labels,creationTimestamp:.metadata.creationTimestamp},status:{phase:.status.phase,startTime:.status.startTime,containerStatuses:[.status.containerStatuses[]?|{name,image,imageID,ready,restartCount}],initContainerStatuses:[.status.initContainerStatuses[]?|{name,image,imageID,ready,restartCount}]}}]}' \
  >"${destination}/pods-after-sanitized.json"

ready_pods="$(kubectl get pods -n hypershift -l name=operator -o json | jq '[.items[] | select(.status.phase == "Running") | select(all(.status.containerStatuses[]?; .ready == true))] | length')"
[[ "${ready_pods}" -ge 2 ]] || die "fewer than two operator pods are Running and Ready"

if [[ "${action}" != "restore" ]]; then
  actual_deployment_image="$(jq -r '.spec.template.spec.containers[] | select(.name == "operator") | .image' "${destination}/deployment-after.json")"
  [[ "${actual_deployment_image}" == "${target_image}" ]] || die "operator deployment image is ${actual_deployment_image}, expected ${target_image}"
  actual_image_ids="$(kubectl get pods -n hypershift -l name=operator -o json | jq -r '[.items[] | select(.status.phase == "Running") | select(all(.status.containerStatuses[]?; .ready == true)) | .status.containerStatuses[]? | select(.name == "operator") | .imageID] | unique')"
  [[ "$(jq 'length' <<<"${actual_image_ids}")" -eq 1 ]] || die "operator pods did not converge on one imageID: ${actual_image_ids}"
  jq -r '.[]' <<<"${actual_image_ids}" >"${destination}/operator-image-ids.txt"
  for operator_pod in $(kubectl get pods -n hypershift -l name=operator -o json | jq -r '.items[] | select(.status.phase == "Running") | select(all(.status.containerStatuses[]?; .ready == true)) | .metadata.name'); do
    kubectl exec -n hypershift "${operator_pod}" -c operator -- /usr/bin/hypershift version >>"${destination}/embedded-version.txt" 2>&1 || true
  done
fi

printf 'completed_utc=%s\n' "$(utc_now)" >>"${destination}/meta.txt"
printf '%s\n' "${destination}"
