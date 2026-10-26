# Source from the repository root (bash or zsh):  source .work/cntrlplane-3927/propagation/env.sh
# Standalone (does not source any 3926 file). Management-cluster changes only on context mgmt;
# the parent cluster is never touched. Sourcing this file is passive except for writing out/mc.kubeconfig
# (a copy of the mgmt context, as in 3926 T8).
#
# Helpers: k (oc on mgmt), hs (branch-built hypershift CLI on mgmt only),
#          guest (oc on the hosted cluster), e2e <cmd> (runs <cmd> with the same env the CI steps set).
# Names are chosen not to clash with common zsh aliases (oh-my-zsh defines g=git, gk=gitk).

REPO_ROOT="$(git rev-parse --show-toplevel)" || return 1
export REPO_ROOT
export PROP_DIR="${REPO_ROOT}/.work/cntrlplane-3927/propagation"
export PROP_OUT="${PROP_DIR}/out"        # kubeconfigs, logs, SHARED_DIR, artifacts — local only, never share
export SHARED="${PROP_OUT}/shared"       # SHARED_DIR: cluster manifest + mirror CA/ICS written by create-guests
export ARTIFACTS="${PROP_OUT}/artifacts" # ARTIFACT_DIR: create-guests and run-tests JUnit files
mkdir -p "${SHARED}" "${ARTIFACTS}"

for _n in k hs guest e2e; do unalias "${_n}" 2>/dev/null; done; unset _n

# Management cluster and mirror fixture (mirrorregistry defaults, created by create-guests PreCreate).
export CTX="${CTX:-mgmt}"              # kubeconfig context of the management cluster
export NS=test-mirror-registry          # mirrorregistry.DefaultNamespace
export NAME=mirror-registry             # mirrorregistry.DefaultName
export KC_NS=keycloak                   # Keycloak: the AWS PreCreate always deploys it (external-OIDC setup)
k() { oc --context "${CTX}" "$@"; }
export TEST_SRC_REPO="quay.io/libpod/registry"
export VIRTUAL_REPO="mirror-source.hypershift-e2e.invalid/libpod/registry"

# Run identity. create-guests derives the HC name from PROW_JOB_ID: image-mirroring-<sha256(PROW_JOB_ID)[:10]>.
# Change PROW_JOB_ID only for a brand-new attempt AFTER the previous one is fully cleaned up (step 6):
# destroy-guests finds the cluster through out/shared/cluster-manifests.json.
export PROW_JOB_ID="${PROW_JOB_ID:-tester-cntrlplane-3927-run1}"
if command -v sha256sum >/dev/null 2>&1; then _sha=(sha256sum); else _sha=(shasum -a 256); fi
HC_NAME="image-mirroring-$(printf %s "${PROW_JOB_ID}" | "${_sha[@]}" | cut -c1-10)"; unset _sha
export HC_NAME                          # original run: image-mirroring-beaa1f2bd2
export HC_NS=clusters                   # create-guests default namespace (HYPERSHIFT_NAMESPACE unset)
export HCP_NS="${HC_NS}-${HC_NAME}"
export INFRA_ID="${HC_NAME}"            # create-guests sets --infra-id=<name>

# Hosted cluster inputs (same values as 3926 T8, which worked on this management cluster).
export BASE_DOMAIN="${BASE_DOMAIN:-hypershift.example.com}"   # public Route53 zone
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_CREDS="${AWS_CREDS:-${HOME}/.aws/credentials}"   # default profile, as T8's --aws-creds
export PULL_SECRET="${PULL_SECRET:-${HOME}/pull-secret}"
export RELEASE_IMAGE="${RELEASE_IMAGE:-quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64}"   # HO supports 4.14–4.21
export NODE_COUNT="${NODE_COUNT:-2}"                    # Prow guest-step default (create-guests' own default is 3)

# The CLI has no --context flag: give it (and the lifecycle binaries) a kubeconfig with only mgmt.
export MC_KUBECONFIG="${PROP_OUT}/mc.kubeconfig"
oc config view --minify --flatten --context "${CTX}" > "${MC_KUBECONFIG}" && chmod 600 "${MC_KUBECONFIG}"
hs() { KUBECONFIG="${MC_KUBECONFIG}" "${REPO_ROOT}/bin/hypershift" "$@"; }

# Hosted cluster access (file written in step 3).
export GUEST_KUBECONFIG="${PROP_OUT}/guest.kubeconfig"
guest() { oc --kubeconfig "${GUEST_KUBECONFIG}" "$@"; }

# e2e: run a command in a subshell with the environment the CI steps provide to create-guests / run-tests /
# destroy-guests (see hypershift-aws-create-guests-commands.sh). Nothing leaks into your shell.
# AWS: like CI, no --aws-creds flag; the CLI uses the SDK default chain = default profile of $AWS_CREDS.
e2e() (
  export KUBECONFIG="${MC_KUBECONFIG}" SHARED_DIR="${SHARED}" ARTIFACT_DIR="${ARTIFACTS}" PROW_JOB_ID
  export HYPERSHIFT_PLATFORM=aws HYPERSHIFT_E2E_IMAGE_MIRRORING=true TEST_PLAN="${PROP_DIR}/test-plan.yaml"
  export RELEASE_IMAGE_LATEST="${RELEASE_IMAGE}" PULL_SECRET HYPERSHIFT_NODE_COUNT="${NODE_COUNT}"
  export HYPERSHIFT_BASE_DOMAIN="${BASE_DOMAIN}" HYPERSHIFT_AWS_REGION="${AWS_REGION}" HYPERSHIFT_AWS_ZONES="${AWS_REGION}a"
  export HYPERSHIFT_BINARY="${REPO_ROOT}/bin/hypershift" E2EV2_BIN_DIR="${REPO_ROOT}/bin"
  export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDS}" GINKGO_TIMEOUT=30m EVENTUALLY_VERBOSE=true
  unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  unset EXTRA_ARGS HYPERSHIFT_NAMESPACE HYPERSHIFT_EXTERNAL_DNS_DOMAIN HYPERSHIFT_ETCD_STORAGE_CLASS OCP_IMAGE_N1
  "$@"
)

DOMAIN="$(k get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
if [ -z "${DOMAIN}" ]; then
  echo "ERROR: could not read the ingress domain from ${CTX} (API slow? retry: source the file again)" >&2
  return 1
fi
export DOMAIN
export HOST="${NAME}-${NS}.${DOMAIN}"

echo "CTX=${CTX} HOST=${HOST}"
echo "HC=${HC_NS}/${HC_NAME} HCP_NS=${HCP_NS} RELEASE=${RELEASE_IMAGE} NODES=${NODE_COUNT}"
echo "PROP_OUT=${PROP_OUT}"
