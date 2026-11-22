# Source from the repository root:  source .work/cntrlplane-3926/smoke/env.sh
# Every command targets the mgmt context explicitly. Nothing here touches the parent cluster.

export CTX="${CTX:-mgmt}"          # kubeconfig context of the management cluster
export NS=test-mirror-registry
export NAME=mirror-registry

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SMOKE_DIR
export OUT="${SMOKE_DIR}/out"          # generated keys/certs live here (gitignored via .work/)
mkdir -p "${OUT}/certs"

k() { oc --context "${CTX}" "$@"; }

# Registry server image (manifest list digest of quay.io/libpod/registry:2.8.2, resolved 2026-10-09).
export REGISTRY_IMAGE="quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"

# Image used as copy payload: the registry image itself (small, public, multi-arch).
export TEST_SRC_REPO="quay.io/libpod/registry"
export TEST_DIGEST="sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
export VIRTUAL_REPO="mirror-source.hypershift-e2e.invalid/libpod/registry"

DOMAIN="$(k get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
export DOMAIN
export HOST="${NAME}-${NS}.${DOMAIN}"
export INTERNAL="${NAME}.${NS}.svc:5000"

# Image providing `oc` for copy Jobs: the cluster's own `cli` ImageStream (by digest).
CLI_IMAGE="$(k get is -n openshift cli -o jsonpath='{.status.tags[?(@.tag=="latest")].items[0].dockerImageReference}')"
export CLI_IMAGE

# Release used for the payload dry-run: the management cluster's own release.
RELEASE_IMAGE="$(k get clusterversion version -o jsonpath='{.status.desired.image}')"
export RELEASE_IMAGE

# Only these variables are substituted into manifests (scripts inside them keep their own $vars).
export SUBST_VARS='$NS $NAME $REGISTRY_IMAGE $HOST $INTERNAL $CLI_IMAGE $RELEASE_IMAGE $READONLY $JOB_NAME $ARG1 $ARG2 $ARG3 $ARG4'
render() { envsubst "${SUBST_VARS}" < "${SMOKE_DIR}/manifests/$1"; }

echo "CTX=${CTX} NS=${NS} HOST=${HOST}"
echo "INTERNAL=${INTERNAL}"
echo "CLI_IMAGE=${CLI_IMAGE}"
echo "RELEASE_IMAGE=${RELEASE_IMAGE}"
