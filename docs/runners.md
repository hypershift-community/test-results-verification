# Shared Self-Hosted Actions Runners

The validation workflow targets **`arc-runner-set`** on the shared ARM64 ARC
cluster, not GitHub-hosted runners. Workflow permissions remain read-only;
report scripts and embedded JavaScript are never executed by the checks.

The existing pool is registered only to `openshift/hypershift`. Sharing its
cluster does not automatically authorize another repository, especially one
in the separate `hypershift-community` organization. This repository needs
its own GitHub registration and RunnerScaleSet on that shared controller.

**Live GitHub App, secret, namespace, and Helm changes require separate operator
approval.** The commands below are an onboarding procedure, not actions taken
by CI. Adding these files does not provision a runner or grant access.

## Deployment Contract

- Reuse the existing ARC controller in `arc-systems`; do not upgrade or
  retarget its `openshift/hypershift` RunnerScaleSet.
- Use scale-set chart **0.14.2**, matching the inspected controller/chart
  version. Reconfirm compatibility before a later installation or upgrade.
- Use Helm release **`arc-test-results-verification`** in the new namespace
  **`arc-test-results`**, with GitHub scale-set name **`arc-runner-set`**.
- That name is also used for Kubernetes resource names in this chart. A
  different Helm release name alone does not prevent collisions in the
  existing `arc-runners` namespace; the separate namespace is intentional.
- Provision namespace-local Secret **`github-app`** with credentials for an
  installation authorized for this community repository. Do not blindly
  copy the existing OpenShift installation's credentials.
- Start at **0 idle / 2 maximum** job runners, using the pinned shared ARM64 image
  and its 4 CPU / 16 GiB request and limit per runner. Listener/controller
  overhead remains even when no job runners are active.
- Job runners use the chart's no-permission service account and do not
  automount Kubernetes API credentials. The GitHub App secret is for ARC,
  not a credential supplied to workflow steps.

The values are in
[`hack/github-actions-runner/values.yaml`](../hack/github-actions-runner/values.yaml).
They follow the
[shared HyperShift runner configuration](https://github.com/openshift/hypershift/tree/main/hack/github-actions-runner).
The values pin the image digest checked by the diagnostic Pod, rather than
following the mutable `latest` tag. Before live deployment, confirm that digest,
image-pull access, admission/SCC behavior, and namespace/network isolation.
Policies in `arc-runners` do not automatically protect a new namespace.

## Read-Only Preflight

Use an explicitly approved runner-cluster kubeconfig, not an unrelated current
context. Keep credentials out of the repository and command output.

```sh
export KUBECONFIG=/path/to/approved-runner-kubeconfig
helm list --all-namespaces
oc get autoscalingrunnersets.actions.github.com -A \
  -o 'custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,GITHUB:.spec.githubConfigUrl'
```

Confirm the controller watches the new namespace and that the proposed release
does not conflict with existing resources. The current controller service
account is `arc-systems/arc-gha-rs-controller`; the values name it explicitly
so rendering does not depend on cluster discovery.

## GitHub App Prerequisite

An administrator must authorize a GitHub App installation for
`hypershift-community/test-results-verification`, with the required repository
permissions: Administration read/write, Actions read, and Metadata read.
If the existing App cannot be installed in the community organization, a
separate approved App is required. Installation IDs are organization-specific.

Obtain the App ID, correct installation ID, and existing App key through the
approved credential-management process. A new installation does not require
a new App key. If credentials already exist in the cluster, verify the source
App ID and obtain explicit approval to reuse its App ID/key with the new
installation ID; leave the original Secret unchanged. Never commit or print
private keys or access tokens.
Retain fork-contributor workflow approval and review public-PR isolation before
enabling execution on a self-hosted pool.

## Apply Only After Separate Approval

The following commands change the cluster. They are **not** part of `make`,
the validation workflow, or an automatic bootstrap step.

For a new pool, first create the namespace and its installation-specific secret.
Inspect existing resources rather than overwriting them. The following example
uses an approved local key file; secure reuse of an existing cluster credential
is also possible as described above. `APP_ID`,
`INSTALLATION_ID`, and `APP_KEY_FILE` must already refer to approved credentials;
the private-key file stays outside this repository.

```sh
oc create namespace arc-test-results
oc -n arc-test-results create secret generic github-app \
  --from-literal=github_app_id="$APP_ID" \
  --from-literal=github_app_installation_id="$INSTALLATION_ID" \
  --from-file=github_app_private_key="$APP_KEY_FILE"
```

After separate policy approval, create the
[namespace isolation policies](../hack/github-actions-runner/networkpolicies.yaml)
before any job runners start:

```sh
oc create -f hack/github-actions-runner/networkpolicies.yaml
```

The policies default-deny Pod ingress/egress in `arc-test-results`. Only labeled
runner pods receive cluster-DNS and public IPv4 HTTPS egress allowances. Private,
link-local, shared, and reserved destination ranges are excluded from the HTTPS
rule. Controller/listener traffic in `arc-systems` is outside this scope.

This is not a GitHub-only domain allowlist or a complete sandbox: public HTTPS
remains broad, NetworkPolicy node/loopback exceptions apply, and policies are
additive. Review any other applicable policy before relying on these limits.

Review the rendered manifest before installing the new pool. This command
renders locally without cluster access:

```sh
helm template arc-test-results-verification \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 --namespace arc-test-results --kubeconfig /dev/null \
  -f hack/github-actions-runner/values.yaml
```

After reviewing the result and obtaining deployment approval:

```sh
helm install arc-test-results-verification \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 --namespace arc-test-results \
  -f hack/github-actions-runner/values.yaml \
  --skip-crds --wait --timeout 5m
```

Use the confirmed cluster kubeconfig for installation. Leave the existing
`arc` and `arc-runner-set` releases unchanged. Verify the new listener registers
against the community repo and a validation job can complete on ARM64. With
the approved image, confirm Node 24 support for `actions/checkout@v6`, the
Go 1.26 setup, and the native compiler/toolchain needed by `make test`'s race
detector. A local cross-build alone does not establish runner readiness. With
`minRunners: 0`, an idle repository may show no individual runners; inspect the
scale-set/listener state and an actual queued job rather than runner count alone.

Only after onboarding and a successful workflow run should the validation job
be made required as described in [validation](validation.md#enforcement).

## Isolation and Image Verification

The approved bootstrap used the pinned image in a temporary ARM64 diagnostic
Pod admitted under `restricted-v2`, without API-token or credential mounts.
Public and service DNS resolved, and GitHub/API/Go proxy/checksum HTTPS checks
returned HTTP 200. A private Kubernetes API TCP connection timed out. The
link-local metadata TCP connection was refused; that result alone does not
establish that a NetworkPolicy caused the refusal. No metadata HTTP request or
credential retrieval was performed, and the diagnostic Pod was deleted.

The image provides Go 1.26.4, ARM64 GCC, and Node 24. These observations and a
healthy ARC listener do not replace an actual validation workflow run. Pushing
an update to an open PR emits the `pull_request` `synchronize` activity handled
by the validation workflow; observe that run and check any approval gate rather
than assuming that an idle scale-to-zero pool is broken.
