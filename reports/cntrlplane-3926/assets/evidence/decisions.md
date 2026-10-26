# CNTRLPLANE-3926 — Design decisions (PR-ready)

> Copy this section into the PR description so reviewers see the trade-offs.
> Status: agreed with the assignee on 2026-10-09; open to reviewer challenge.

## Context

[CNTRLPLANE-3926](https://redhat.atlassian.net/browse/CNTRLPLANE-3926) provides the in-cluster mirror
registry shared by the OCPSTRAT-3316 epics: CNTRLPLANE-3922 (`imageContentSources` → hosted cluster IDMS),
CNTRLPLANE-3923 (`--registry-overrides`) and CNTRLPLANE-3924 (management-cluster IDMS).
It is test infrastructure (a fixture), not image-resolution code.

## D1 — Location and shape

- Package `test/e2e/v2/util/mirrorregistry/`, **no build tag**, no Ginkgo/Gomega imports. Its unit tests
  therefore run in the standard `make test` (`go test ./...`, Prow `unit`), and the package is callable from
  Ginkgo tests, from `lifecycle` hooks and from any future CI step. The package is added to the `other`
  shard of the GitHub Actions unit-test workflow, which otherwise does not cover `test/e2e/v2/`.
- Not placed in `support/imageresolution/` (enhancement openshift/enhancements#1981): that package is for
  production resolution. The fixture must not import the production resolvers/providers
  (`support/releaseinfo`, `support/imageregistry`, `support/globalconfig`) so that the OCPSTRAT-3877
  refactor can change them without touching the fixture, and so the tests never compute their
  expectations with the code under test.
- The fixture only provisions and reports. It never asserts fallback policy (OCPBUGS-128661): that belongs
  in the consuming tests.
- Resources are reconciled with `support/upsert` (the repository's create-or-update pattern).

## D2 — Exposure: Route with TLS passthrough, explicit host

- `registry` serves TLS itself on port 5000; a `passthrough` Route exposes it.
- The Route host is set explicitly to `<name>-<namespace>.<ingress domain>` (ingress domain read from
  `ingresses.config.openshift.io/cluster`). This makes the hostname known before any resource exists, so the
  serving certificate (and, in the future, a CA distributed earlier in the pipeline) can be prepared in
  advance.
- Rationale: in CI (and on our dev setup) the management cluster is a *nested* hosted cluster whose ingress
  certificate is signed by an internal `root-ca`, so reusing the ingress certificate gives no trust
  advantage, and hosted-cluster nodes cannot reach the in-cluster Service.

### Network assumptions and boundaries

- **Hosted-cluster endpoint access does not matter.** `--endpoint-access` (Public / PublicAndPrivate /
  Private) only changes how control-plane endpoints are exposed. Nodes pull from the mirror through the worker
  VPC outbound path, which `hypershift create infra aws` builds identically in all three modes (private
  subnets + NAT). The manual validation used exactly that path. No OCPSTRAT-3316 issue asks for topology
  coverage.
- **Workers need outbound access to the management-cluster ingress** (NAT, internet gateway or cluster proxy;
  with a proxy, the mirror host must not be in `noProxy`). A fully disconnected VPC cannot reach the Route.
- **The management-cluster ingress must be external.** If it were internal (e.g. a Private management cluster
  with an NLB), guest VPCs could not reach it. `Setup` fails early in that case: it probes the public endpoint
  from the test process, which runs outside the management cluster.
- **OpenShift management cluster only.** The fixture uses a Route, `ingresses.config.openshift.io`, and relies on
  the `restricted-v2` SCC to assign a non-root UID (the registry image has no `USER`). The lifecycle reads the
  copier image from the `openshift/cli` ImageStream. This covers every current consumer, including the v2
  Azure self-managed suite (OpenShift management cluster). AKS-based management clusters (ARO HCP, other
  managed services) are not supported. Supporting them is additive and does not change the public API:
  optional `LoadBalancer` exposure (Service selecting only the read-only pod, to keep D4), IP SANs, an explicit
  pod `runAsUser`/`fsGroup` off OpenShift, and a caller-chosen copier image.

## D3 — TLS: helper CA by default, caller-supplied CA supported

- Default: the helper generates a CA and signs a serving certificate whose SANs are the Route host, the
  Service DNS names, and optional extra names (e.g. `*.apps.<domain>`).
- The CA (cert + key) is stored in a Secret `<name>-ca` in the fixture namespace and reused by later `Setup`
  calls, so trust already distributed to consumers (`additionalTrustBundle`) survives re-runs. The namespace is
  ephemeral and owned by the fixture; the key never leaves the management cluster except through the caller.
- A caller can pass an existing CA (cert + key). This is the hook for CNTRLPLANE-3923/3924: there, the
  management cluster's own nodes must trust the mirror, and their trust comes from the parent hosted
  cluster created *before* the mirror exists, so the CA must be generated earlier in the CI pipeline.
- Consumers receive the CA bundle and pass it to `HostedCluster.spec.additionalTrustBundle`
  (`hypershift create cluster --additional-trust-bundle`). Creating the hosted cluster with it from the
  start avoids a NodePool rollout. No `--insecure-registry` anywhere.

## D4 — No authentication; push only internally; read-only before exposure

- `registry` htpasswd auth is all-or-nothing (no anonymous read with authenticated write), and adding
  credentials would require merging them into the hosted cluster pull secret *and* (for 3923/3924) the
  management cluster pull secret owned by the parent cluster.
- Instead: images are copied through the internal Service while the registry is writable; the registry is
  then restarted with `storage.maintenance.readonly.enabled=true`; **only then** is the Route created.
  Invariant: the Route exists only while the registry is read-only. A repeated `Setup` first deletes the Route
  and waits until public routing is withdrawn before re-enabling writes.
  The public endpoint is anonymous and read-only and never accepts pushes.
- Residual risk: mirrored content is anonymously readable for the lifetime of the job at an unguessable
  per-job hostname on an ephemeral cluster. Reviewers may ask for htpasswd; it can be added later
  without changing the public API (new optional field).

## D5 — Copy: in-cluster Job running `oc`

- Copying runs as a Kubernetes Job in the registry namespace, using an image that contains `oc`
  (configurable; default chosen during the smoke test). It talks to the registry through the internal
  Service, trusting the CA, and reads sources with a caller-supplied pull secret (in presubmit CI the
  release under test lives in `registry.build*.ci.openshift.org`, which needs credentials).
- Avoids depending on `oc`/`skopeo` being present in the `hypershift-tests` image and keeps traffic
  in-cluster. The copier sits behind an `ImageCopier` interface so unit tests use a fake.
- Digests must be preserved: manifest lists are kept, no `--filter-by-os`. IDMS only redirects
  by-digest pulls, so consumers reference images by digest.
- Single images: `oc image mirror`. Full release payloads (needed by CNTRLPLANE-3931, two releases):
  `oc adm release mirror`.

## D6 — Mirror layout and image-content-source mapping

- Mirror repository for a source repository `<reg>/<path>` is `<host>/<reg>/<path>` (source registry
  host kept as first path component → no collisions between registries).
- The fixture returns `[]hyperv1.ImageContentSource` (the exact type used by
  `hypershift create cluster --image-content-sources`), one entry per source repository.
- A mapping can declare a **virtual source repository** that does not exist upstream (e.g.
  `mirror-source.hypershift-e2e.invalid/...`). A pod referencing `<virtual repo>@<digest>` can only start
  if the node pulled from the mirror — endpoint-specific evidence for CNTRLPLANE-3928 without blocking
  quay.io or parsing registry logs.

## D7 — Storage

- Always a PersistentVolumeClaim (size configurable, default 20Gi, default StorageClass). Deployment uses
  the `Recreate` strategy (RWO volume).
- No `emptyDir` option: the registry reads its configuration only at startup, so the read-only switch (D4)
  restarts the pod, and an `emptyDir` would lose everything that was just copied.
- The registry is configured with a mounted `config.yml` (ConfigMap); a config hash annotation on the pod
  template rolls the pod when read-only is toggled.
- Sizing for two full payloads (CNTRLPLANE-3931) is decided in that story; the fixture just exposes the
  knob.

## D8 — Registry image

- Configurable; default `quay.io/libpod/registry:2.8.2` pinned by manifest-list digest (non-Docker-Hub
  location, avoids rate limits in CI). Verified under the `restricted-v2` SCC (random UID) on a nested
  management cluster.

## D9 — CI integration (v2 lifecycle)

- The existing `PlatformConfig.PreCreate` hook in `create-guests` (already used for Keycloak on Azure)
  deploys the registry before any hosted cluster is created and writes to `SHARED_DIR`:
  CA bundle, `imageContentSources` YAML, and a small JSON with endpoint and mirrored image refs.
- A dedicated AWS cluster variant (`image-mirroring`) is added only when the mirroring lane is enabled
  (opt-in env var set by the new job from CNTRLPLANE-3929). Its extra args point at the files above
  (`--additional-trust-bundle`, `--image-content-sources`). Existing jobs and the default AWS plan are
  unaffected.
- Teardown: in CI the nested management cluster is destroyed with the job; `Teardown` (delete the owned
  namespace) exists for local runs and is idempotent.

## Out of scope for this PR (tracked elsewhere)

- Making management-cluster nodes trust the mirror (CNTRLPLANE-3923/3924): needs an openshift/release change
  to create the nested management cluster with the CA. This PR only provides the caller-supplied-CA hook.
- `--registry-overrides` HO installation wiring (3930/3931), test assertions (3927/3928/3932/3933), Prow job
  (3929).
