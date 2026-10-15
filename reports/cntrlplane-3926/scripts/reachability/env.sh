# Source from the repository root (bash or zsh):  source .work/cntrlplane-3926/reachability/env.sh
# Standalone: does not source harness/env.sh. Management-cluster changes only on context mgmt;
# the parent cluster is never touched.
#
# Helpers: k (oc on mgmt), harness (T6 Go harness), hs (hypershift CLI on mgmt only),
#          guest (oc on the hosted cluster), pod <name> <image> (renders manifests/pod.yaml).
# Names are chosen not to clash with common zsh aliases (oh-my-zsh defines g=git, gk=gitk).

REPO_ROOT="$(git rev-parse --show-toplevel)" || return 1
export REPO_ROOT
export REACH_DIR="${REPO_ROOT}/.work/cntrlplane-3926/reachability"
export HARNESS_DIR="${REPO_ROOT}/.work/cntrlplane-3926/harness"    # watch.sh, verify.sh, main.go
export REACH_OUT="${REACH_DIR}/out"     # mirror inputs, kubeconfigs, logs — local only, never share
export RUN="${REACH_OUT}/mirror"        # harness setup -out dir: ca-only/ca.crt, ics.yaml, result.json
mkdir -p "${REACH_OUT}"

# Remove any same-named alias in this shell so the function definitions below parse.
for _n in k harness hs guest pod; do unalias "${_n}" 2>/dev/null; done; unset _n

# Management cluster and mirror fixture (mirrorregistry defaults).
export CTX="${CTX:-mgmt}"              # kubeconfig context of the management cluster
export NS=test-mirror-registry          # mirrorregistry.DefaultNamespace
export NAME=mirror-registry             # mirrorregistry.DefaultName
k() { oc --context "${CTX}" "$@"; }
harness() { (cd "${REPO_ROOT}" && go run ./.work/cntrlplane-3926/harness "$@"); }

# Mirrored test image (DefaultRegistryImage) and its virtual source repository.
export TEST_SRC_REPO="quay.io/libpod/registry"
export TEST_DIGEST="sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f"
export VIRTUAL_REPO="mirror-source.hypershift-e2e.invalid/libpod/registry"

DOMAIN="$(k get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
if [ -z "${DOMAIN}" ]; then
  echo "ERROR: could not read the ingress domain from ${CTX} (API slow? retry: source the file again)" >&2
  return 1
fi
export DOMAIN
export HOST="${NAME}-${NS}.${DOMAIN}"

# Hosted cluster under test (new, dedicated, destroyed at the end).
export HC_NAME=mirror-reach
export HC_NS=clusters
export HCP_NS="${HC_NS}-${HC_NAME}"
export BASE_DOMAIN="${BASE_DOMAIN:-hypershift.example.com}"   # public Route53 zone (same as the parent HC)
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_CREDS="${AWS_CREDS:-${HOME}/.aws/credentials}"
export PULL_SECRET="${PULL_SECRET:-${HOME}/pull-secret}"
export RELEASE_IMAGE="${RELEASE_IMAGE:-quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64}"   # HO supports 4.14–4.21

# The hypershift CLI has no --context flag: give it a kubeconfig that only contains mgmt.
export MC_KUBECONFIG="${REACH_OUT}/mc.kubeconfig"
oc config view --minify --flatten --context "${CTX}" > "${MC_KUBECONFIG}" && chmod 600 "${MC_KUBECONFIG}"
hs() { KUBECONFIG="${MC_KUBECONFIG}" hypershift "$@"; }

# Hosted cluster access (file written in step 4).
export GUEST_KUBECONFIG="${REACH_OUT}/guest.kubeconfig"
export GUEST_NS=mirror-reach-check
guest() { oc --kubeconfig "${GUEST_KUBECONFIG}" "$@"; }

# Pod manifests: only these variables are substituted.
pod() { POD_NAME="$1" IMAGE="$2" envsubst '$POD_NAME $IMAGE $GUEST_NS' < "${REACH_DIR}/manifests/pod.yaml"; }
export POD_DIGEST=mirror-by-digest      # positive: virtual repo by digest → must start
export POD_TAG=mirror-by-tag            # negative: virtual repo by tag → must fail (IDMS is digest-only)

echo "CTX=${CTX} NS=${NS} HOST=${HOST}"
echo "HC=${HC_NS}/${HC_NAME} BASE_DOMAIN=${BASE_DOMAIN} RELEASE=${RELEASE_IMAGE}"
echo "REACH_OUT=${REACH_OUT}"
