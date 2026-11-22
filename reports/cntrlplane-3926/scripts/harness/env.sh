# Source from the repository root:  source .work/cntrlplane-3926/harness/env.sh
# Every command targets the mgmt context explicitly. Nothing here touches the parent cluster.

export CTX="${CTX:-mgmt}"          # kubeconfig context of the management cluster
export NS=test-mirror-registry      # mirrorregistry.DefaultNamespace
export NAME=mirror-registry         # mirrorregistry.DefaultName

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export HARNESS_DIR
export OUT="${HARNESS_DIR}/out"     # results and CA keys — local only, never share
mkdir -p "${OUT}"

k() { oc --context "${CTX}" "$@"; }
harness() { go run ./.work/cntrlplane-3926/harness "$@"; }

export TEST_SRC_REPO="quay.io/libpod/registry"
export TEST_DIGEST="sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
export VIRTUAL_REPO="mirror-source.hypershift-e2e.invalid/libpod/registry"

DOMAIN="$(k get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
export DOMAIN
export HOST="${NAME}-${NS}.${DOMAIN}"

echo "CTX=${CTX} NS=${NS} HOST=${HOST}"
echo "OUT=${OUT}"
