# T0 — Smoke test results

Date: 2026/10/12  Cluster: mgmt (OCP 4.20.0, nested hosted cluster)  Run by: @Nirshal

Keep table cells to one line. Put command output (logs, errors, YAML) in the **Evidence** section below,
under the matching step, inside a fenced code block.

| Step | Item | Result | Notes / exact values |
|------|------|--------|----------------------|
| 3 | Registry image runs under restricted-v2 | OK | SCC `restricted-v2`, UID `1000630000`; HTTPS probes return 200 (evidence 3) |
| 3 | Deployment changes needed | NONE | `manifests/deployment.yaml` works as written; startup log `listening on [::]:5000, tls`, registry 2.8.2 |
| 4 | Copy Job succeeds (real + `.invalid` virtual repo) | OK | `openshift/cli` image, oc `4.20.0-202509230043`; 2 × (7 manifests, 36 blobs, 51.88 MiB) in ~6.5 s each |
| 4 | Destination without tag accepted for by-digest source | OK | `oc image mirror --keep-manifest-list=true <repo>@sha256:… <internal>/<src-registry>/<path>` (pushed by digest, no tag) |
| 4 | CA trust via combined `SSL_CERT_FILE` works | OK | no TLS errors to quay.io (system CAs) nor to the internal Service (our CA) |
| 5 | Read-only config value works (`storage.maintenance.readonly.enabled`) | OK | ConfigMap toggle + `rollout restart`; Job Failed as expected |
| 5 | Push rejected in read-only, error text | OK | every blob upload gets `HTTP 405` `Method not allowed` (evidence 5) |
| 6 | Passthrough Route with explicit host admitted | OK | explicit `spec.host` accepted as-is, nothing special needed |
| 7 | `/v2/` 200 anonymous with CA | OK | `{}  HTTP 200` with `--cacert ca.crt`, no credentials |
| 7 | TLS fails without CA | OK | curl exit 60 `unable to get local issuer certificate` |
| 7 | Digest preserved (both repos) | OK | both repos serve `sha256:e642e860…` = source manifest-list digest; content survived the read-only restart |
| 7 | Push via Route rejected | OK | skopeo exit 1, `StatusCode: 405, "Method not allowed"` on blob upload |
| 8 | Re-apply idempotent | OK | all 5 objects `unchanged`, no pod restart |
| 9 | Effective securityContext / StorageClass | OK | SCC injects `runAsUser: 1000630000` (container), `fsGroup: 1000630000` + SELinux `s0:c25,c15` (pod); PVC `gp3-csi` 5Gi |
| 10 | Payload size | OK | 4.20.0 x86_64: 192 manifests, 444 blobs, **22.08 GiB** to transfer/store (`--size`: 23.7 GB, 251 layers) |
| 10 | Release source repositories | OK | `quay.io/openshift-release-dev/ocp-release` (release) + `quay.io/openshift-release-dev/ocp-v4.0-art-dev` (components), both → one mirror repo |
| 10 | Best way to get them (IDMS output vs `--pullspecs`) | OK | `--pullspecs` (release repo + unique component repos): stable, not tied to the deprecated mirror command's text output |
| 11 | `oc` in CI test image | ABSENT | base image `openshift/release:rhel-9-release-golang-1.26-openshift-5.1` has no `oc` on PATH; `Dockerfile.e2e` adds none → in-cluster copy Job is required |

## Values to copy into code

- `DefaultRegistryImage`: `quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f` — confirmed, set in `api.go`
- Copier image default: `openshift/cli` ImageStream `latest` — confirmed (steps 4, 10); CI test image has no `oc` (step 11)
- Final manifests: `manifests/` worked **unchanged** — they are the golden reference for T3/T4

Step 12 (teardown): namespace deleted, PV released (reclaim `Delete`). Run completed 2026/10/12.

## Surprises / decisions to revisit

- Step 10: one payload is ~22 GiB stored. Two consecutive payloads for CNTRLPLANE-3931 share many layers but
  should be budgeted at ~45 GiB → PVC ~60 Gi there. The default 20 Gi stays right for the guest-IDMS lane
  (single small images). Mirror **time** for 22 GiB was not measured (dry-run); 3931 must measure it against
  the Prow job timeout.
- Step 10: `CopyResult.ReleaseSourceRepositories` shape confirmed: per release, the release repository plus the
  unique component repositories (here 2 entries), all mapped to one mirror repository.
- Step 4: `--keep-manifest-list=true` copies **all architectures** of a manifest list (here 6 manifests,
  51.88 MiB instead of a few MiB for amd64 only). It is required to keep the list digest. Fine for small
  test images; for release payloads (CNTRLPLANE-3931) the standard `ocp-release` images are single-arch, so
  size stays per-payload. Keep in mind for PVC sizing if multi-arch payloads are ever mirrored.
- Step 4: the second copy re-uploaded all blobs (`mounts=0`) although they already existed in the first
  repository. Storage is content-addressed (no double disk usage), only transfer time is spent. Not worth
  optimizing for test images.
- Step 1: the serving certificate CN cannot be the Route host (> 64 characters, RFC 5280). Use a short CN
  (`mirror-registry`) and put hostnames only in the SANs. Folded into `RUNBOOK.md` and `plan.md` T2.

## Evidence

### Step 3 — registry pod logs

Registry version `go1.19.9` build; kubelet HTTPS probes on `/v2/` answered 200 over HTTP/2 (HTTP/2 is only
negotiated over TLS, so the registry is serving TLS with our certificate).

```text
10.133.0.2 - - [12/Oct/2026:08:58:51 +0000] "GET /v2/ HTTP/2.0" 200 2 "" "kube-probe/1.33"
time="2026-10-12T08:58:53.597323518Z" level=info msg="response completed" go.version=go1.19.9 http.request.host="10.133.1.247:5000" http.request.id=67db714b-dc62-4193-9b0e-49a1800f380f http.request.method=GET http.request.remoteaddr="10.133.0.2:37684" http.request.uri="/v2/" http.request.useragent="kube-probe/1.33" http.response.contenttype="application/json; charset=utf-8" http.response.duration=1.561024ms http.response.status=200 http.response.written=2
10.133.0.2 - - [12/Oct/2026:08:58:53 +0000] "GET /v2/ HTTP/2.0" 200 2 "" "kube-probe/1.33"
time="2026-10-12T08:58:56.190554648Z" level=info msg="response completed" go.version=go1.19.9 http.request.host="10.133.1.247:5000" http.request.id=3144f94a-e258-4e4d-ba86-5d05d5c157f4 http.request.method=GET http.request.remoteaddr="10.133.0.2:49024" http.request.uri="/v2/" http.request.useragent="kube-probe/1.33" http.response.contenttype="application/json; charset=utf-8" http.response.duration=1.015674ms http.response.status=200 http.response.written=2
10.133.0.2 - - [12/Oct/2026:08:58:56 +0000] "GET /v2/ HTTP/2.0" 200 2 "" "kube-probe/1.33"
```

Startup line:

```text
time="2026-10-12T08:54:15.191612123Z" level=info msg="listening on [::]:5000, tls" go.version=go1.19.9 instance.id=8770d4e2-b38c-435d-948d-0520dcd8c92f service=registry version=2.8.2
```

### Step 4 — copy Job logs

Both copies completed. Manifest list `sha256:e642e860…` plus its 6 per-architecture manifests were pushed by
digest to both `quay.io/libpod/registry` and `mirror-source.hypershift-e2e.invalid/libpod/registry`, i.e. the
D6 layout (including the `.invalid` host as a path component) is accepted. Digest equality on the public
endpoint is checked in step 7.

```text
Client Version: 4.20.0-202509230043.p2.ga434281.assembly.stream.el9-a434281
Kustomize Version: v5.6.0
=== mirror quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f -> mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
mirror-registry.test-mirror-registry.svc:5000/
quay.io/libpod/registry
blobs:
quay.io/libpod/registry sha256:356f0e046603015c84a7d938f4737b363a2760ac2099f484dcc1d6ec3dd844ac 214B
quay.io/libpod/registry sha256:3745f5e7cc696592c982fb456207ad8a32889e9a5a5b8f17525a469397aa5aab 214B
quay.io/libpod/registry sha256:7417fa3c6d923a722787ff60825c3c40f74621ab2e4abcc120e25b10a35e4811 214B
quay.io/libpod/registry sha256:af0cc111bdb4ccbcbe9e1d7fcdd884315e9d108ae06718871fbccea824878c20 214B
quay.io/libpod/registry sha256:b58a5a1ef3b60d92194b55c0fabaf01e31cdc2671f4198dee4162ad3a922507e 214B
quay.io/libpod/registry sha256:2cbeb3fe0742f6fcada760aa65bc6d3bf83b16a8190cc936f2bde2477a2770d7 215B
quay.io/libpod/registry sha256:5259fb81414efda435e8c80ae21d277a27b149f488b6c7f55216119025b2444c 398B
quay.io/libpod/registry sha256:6f22f5bf08e6a4c52dcaa0f76c001116ca484b811f4aabe2e1114ede0473768d 398B
quay.io/libpod/registry sha256:9c0525345bde84293b274deb702098f1a0dbffc62e1b7270e06f8eea0f1c1a29 398B
quay.io/libpod/registry sha256:121f958bea53668d782691e643e9401ea21dd36c9d81078b51964d2e82b51376 399B
quay.io/libpod/registry sha256:89015d87ad663ad7dc3c895507a48abf75af42d5aa96f45cf58774376507ef39 399B
quay.io/libpod/registry sha256:9d2d3fd2527f6cdd52276d364a2cabb589e3bbc8a745e9c20469086ae906d95e 399B
quay.io/libpod/registry sha256:a7014e8ccc173fe30110a1dcfc70dc51f019db33b9c55714472ff9c440ddec60 4.024KiB
quay.io/libpod/registry sha256:0030ba3d620c647159c935ee778991c68ef3e51a274703753b0bc530104ef5e5 4.026KiB
quay.io/libpod/registry sha256:8e3c88d183641f876f31f8e1597dd4a1eb58a0f912c450094b9fa5054c369159 4.029KiB
quay.io/libpod/registry sha256:20b02a79df1e04210278fa01c2f0386a50d5118808176a8601acd1149afcfbfc 4.039KiB
quay.io/libpod/registry sha256:5339f63f9a359dc7afd94a5c68c51eb22c4cfd631cdb62f41065983a30d5838a 4.04KiB
quay.io/libpod/registry sha256:3c11102b94173ff36b94a107731091ea1b4d68d51acce12c7d7a02f863b444a9 4.042KiB
quay.io/libpod/registry sha256:a47bd95d78f565e902bafd0264a979eb4f6f71e22c0464011bf9db6feb0579e6 277.4KiB
quay.io/libpod/registry sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e 278KiB
quay.io/libpod/registry sha256:8564ce36feee688566265012773f1c8c7c046ceefe86ca763eb702682f4e6e75 278.2KiB
quay.io/libpod/registry sha256:175521994a5932158dbd78d2153c38836ab5e1db0ceb4af91113d4c49c5caba2 278.4KiB
quay.io/libpod/registry sha256:5d54e960e981301b0098c80d2e61d694333b5ab480a007a3a8d0fa629662d377 279.6KiB
quay.io/libpod/registry sha256:c966ad2cdd35689da92e7c8fd39bd37cd6080c484e6ccaf00672c154cd4f6c2a 279.9KiB
quay.io/libpod/registry sha256:f8dec92eec42224ef9e6ca9c6207ea6b9195dcf93d06bd5ceff0f814b62bf064 2.765MiB
quay.io/libpod/registry sha256:af09961d4a43b504efc76e38b50918977c28be73eeb8b926247783a00e8b9f2f 2.999MiB
quay.io/libpod/registry sha256:998cc98447b44e5f0fe799dce691412796ba586ab22eb7c99aebf9d45f34833b 3.065MiB
quay.io/libpod/registry sha256:9fda8d8052c61740409c4bea888859c141fd8cc3f58ac61943144ff6d1681b2d 3.176MiB
quay.io/libpod/registry sha256:55353ca330e9474ce7b858eca6842bb540ef4a70b2981c2ed47eefb9ef4253ad 3.191MiB
quay.io/libpod/registry sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de 3.244MiB
quay.io/libpod/registry sha256:1c079a77918c61cc345bb0ae4562cc6899919358575cce027348d0d152129519 5.001MiB
quay.io/libpod/registry sha256:cb9be1f8a1947aa58bb268c308b33b52ab00c239d020b6230ef9accdcebfcfd2 5.134MiB
quay.io/libpod/registry sha256:5b6190aef38cde840b7e3d42e994f80ada99568850af79c76d02de250bdbf822 5.311MiB
quay.io/libpod/registry sha256:93cca240aafc896515ff6b5406baf949e4054d981f863022f3471a389e425967 5.312MiB
quay.io/libpod/registry sha256:4ef77a110d155ae5e1170b2dd0199770fcf951614ae89fe3de52643dfc68f1da 5.389MiB
quay.io/libpod/registry sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a 5.634MiB
manifests:
sha256:4cab339812e3bfa9e2242292f46ca2a99e804a4604d29f342f2b935381ebad3c
sha256:a353b4af55af90d0d30511d2191edb9da38f174390ce91e2329fa1839b6c2408
sha256:d72af0ec30bf3a5531f2d4dc4d0893f11b40cfd0a5dcbcbdcc19adde233847d2
sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27
sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
sha256:ea32c4ea1ffa10d85c25b55e3e775a72013e685bf80f8da79ec5c5ddc4a4a63f
sha256:fab2c6a4bb4acf3ee3ae611943e2596a73e9adb4da74432b1bcd686539f7f56f
stats: shared=0 unique=36 size=51.88MiB ratio=1.00

phase 0:
mirror-registry.test-mirror-registry.svc:5000 quay.io/libpod/registry blobs=36 mounts=0 manifests=7 shared=0

info: Planning completed in 950ms
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e 278KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:a47bd95d78f565e902bafd0264a979eb4f6f71e22c0464011bf9db6feb0579e6 277.4KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:5d54e960e981301b0098c80d2e61d694333b5ab480a007a3a8d0fa629662d377 279.6KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:55353ca330e9474ce7b858eca6842bb540ef4a70b2981c2ed47eefb9ef4253ad 3.191MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:cb9be1f8a1947aa58bb268c308b33b52ab00c239d020b6230ef9accdcebfcfd2 5.134MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:175521994a5932158dbd78d2153c38836ab5e1db0ceb4af91113d4c49c5caba2 278.4KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de 3.244MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a 5.634MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:1c079a77918c61cc345bb0ae4562cc6899919358575cce027348d0d152129519 5.001MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:4ef77a110d155ae5e1170b2dd0199770fcf951614ae89fe3de52643dfc68f1da 5.389MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:af09961d4a43b504efc76e38b50918977c28be73eeb8b926247783a00e8b9f2f 2.999MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:c966ad2cdd35689da92e7c8fd39bd37cd6080c484e6ccaf00672c154cd4f6c2a 279.9KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:f8dec92eec42224ef9e6ca9c6207ea6b9195dcf93d06bd5ceff0f814b62bf064 2.765MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:998cc98447b44e5f0fe799dce691412796ba586ab22eb7c99aebf9d45f34833b 3.065MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:8564ce36feee688566265012773f1c8c7c046ceefe86ca763eb702682f4e6e75 278.2KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:93cca240aafc896515ff6b5406baf949e4054d981f863022f3471a389e425967 5.312MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:5b6190aef38cde840b7e3d42e994f80ada99568850af79c76d02de250bdbf822 5.311MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry sha256:9fda8d8052c61740409c4bea888859c141fd8cc3f58ac61943144ff6d1681b2d 3.176MiB
sha256:ea32c4ea1ffa10d85c25b55e3e775a72013e685bf80f8da79ec5c5ddc4a4a63f mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:fab2c6a4bb4acf3ee3ae611943e2596a73e9adb4da74432b1bcd686539f7f56f mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:4cab339812e3bfa9e2242292f46ca2a99e804a4604d29f342f2b935381ebad3c mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:d72af0ec30bf3a5531f2d4dc4d0893f11b40cfd0a5dcbcbdcc19adde233847d2 mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:a353b4af55af90d0d30511d2191edb9da38f174390ce91e2329fa1839b6c2408 mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27 mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f mirror-registry.test-mirror-registry.svc:5000/quay.io/libpod/registry
info: Mirroring completed in 6.56s (8.29MB/s)
=== mirror quay.io/libpod/registry@sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f -> mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
mirror-registry.test-mirror-registry.svc:5000/
mirror-source.hypershift-e2e.invalid/libpod/registry
blobs:
quay.io/libpod/registry sha256:356f0e046603015c84a7d938f4737b363a2760ac2099f484dcc1d6ec3dd844ac 214B
quay.io/libpod/registry sha256:3745f5e7cc696592c982fb456207ad8a32889e9a5a5b8f17525a469397aa5aab 214B
quay.io/libpod/registry sha256:7417fa3c6d923a722787ff60825c3c40f74621ab2e4abcc120e25b10a35e4811 214B
quay.io/libpod/registry sha256:af0cc111bdb4ccbcbe9e1d7fcdd884315e9d108ae06718871fbccea824878c20 214B
quay.io/libpod/registry sha256:b58a5a1ef3b60d92194b55c0fabaf01e31cdc2671f4198dee4162ad3a922507e 214B
quay.io/libpod/registry sha256:2cbeb3fe0742f6fcada760aa65bc6d3bf83b16a8190cc936f2bde2477a2770d7 215B
quay.io/libpod/registry sha256:5259fb81414efda435e8c80ae21d277a27b149f488b6c7f55216119025b2444c 398B
quay.io/libpod/registry sha256:6f22f5bf08e6a4c52dcaa0f76c001116ca484b811f4aabe2e1114ede0473768d 398B
quay.io/libpod/registry sha256:9c0525345bde84293b274deb702098f1a0dbffc62e1b7270e06f8eea0f1c1a29 398B
quay.io/libpod/registry sha256:121f958bea53668d782691e643e9401ea21dd36c9d81078b51964d2e82b51376 399B
quay.io/libpod/registry sha256:89015d87ad663ad7dc3c895507a48abf75af42d5aa96f45cf58774376507ef39 399B
quay.io/libpod/registry sha256:9d2d3fd2527f6cdd52276d364a2cabb589e3bbc8a745e9c20469086ae906d95e 399B
quay.io/libpod/registry sha256:a7014e8ccc173fe30110a1dcfc70dc51f019db33b9c55714472ff9c440ddec60 4.024KiB
quay.io/libpod/registry sha256:0030ba3d620c647159c935ee778991c68ef3e51a274703753b0bc530104ef5e5 4.026KiB
quay.io/libpod/registry sha256:8e3c88d183641f876f31f8e1597dd4a1eb58a0f912c450094b9fa5054c369159 4.029KiB
quay.io/libpod/registry sha256:20b02a79df1e04210278fa01c2f0386a50d5118808176a8601acd1149afcfbfc 4.039KiB
quay.io/libpod/registry sha256:5339f63f9a359dc7afd94a5c68c51eb22c4cfd631cdb62f41065983a30d5838a 4.04KiB
quay.io/libpod/registry sha256:3c11102b94173ff36b94a107731091ea1b4d68d51acce12c7d7a02f863b444a9 4.042KiB
quay.io/libpod/registry sha256:a47bd95d78f565e902bafd0264a979eb4f6f71e22c0464011bf9db6feb0579e6 277.4KiB
quay.io/libpod/registry sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e 278KiB
quay.io/libpod/registry sha256:8564ce36feee688566265012773f1c8c7c046ceefe86ca763eb702682f4e6e75 278.2KiB
quay.io/libpod/registry sha256:175521994a5932158dbd78d2153c38836ab5e1db0ceb4af91113d4c49c5caba2 278.4KiB
quay.io/libpod/registry sha256:5d54e960e981301b0098c80d2e61d694333b5ab480a007a3a8d0fa629662d377 279.6KiB
quay.io/libpod/registry sha256:c966ad2cdd35689da92e7c8fd39bd37cd6080c484e6ccaf00672c154cd4f6c2a 279.9KiB
quay.io/libpod/registry sha256:f8dec92eec42224ef9e6ca9c6207ea6b9195dcf93d06bd5ceff0f814b62bf064 2.765MiB
quay.io/libpod/registry sha256:af09961d4a43b504efc76e38b50918977c28be73eeb8b926247783a00e8b9f2f 2.999MiB
quay.io/libpod/registry sha256:998cc98447b44e5f0fe799dce691412796ba586ab22eb7c99aebf9d45f34833b 3.065MiB
quay.io/libpod/registry sha256:9fda8d8052c61740409c4bea888859c141fd8cc3f58ac61943144ff6d1681b2d 3.176MiB
quay.io/libpod/registry sha256:55353ca330e9474ce7b858eca6842bb540ef4a70b2981c2ed47eefb9ef4253ad 3.191MiB
quay.io/libpod/registry sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de 3.244MiB
quay.io/libpod/registry sha256:1c079a77918c61cc345bb0ae4562cc6899919358575cce027348d0d152129519 5.001MiB
quay.io/libpod/registry sha256:cb9be1f8a1947aa58bb268c308b33b52ab00c239d020b6230ef9accdcebfcfd2 5.134MiB
quay.io/libpod/registry sha256:5b6190aef38cde840b7e3d42e994f80ada99568850af79c76d02de250bdbf822 5.311MiB
quay.io/libpod/registry sha256:93cca240aafc896515ff6b5406baf949e4054d981f863022f3471a389e425967 5.312MiB
quay.io/libpod/registry sha256:4ef77a110d155ae5e1170b2dd0199770fcf951614ae89fe3de52643dfc68f1da 5.389MiB
quay.io/libpod/registry sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a 5.634MiB
manifests:
sha256:4cab339812e3bfa9e2242292f46ca2a99e804a4604d29f342f2b935381ebad3c
sha256:a353b4af55af90d0d30511d2191edb9da38f174390ce91e2329fa1839b6c2408
sha256:d72af0ec30bf3a5531f2d4dc4d0893f11b40cfd0a5dcbcbdcc19adde233847d2
sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27
sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
sha256:ea32c4ea1ffa10d85c25b55e3e775a72013e685bf80f8da79ec5c5ddc4a4a63f
sha256:fab2c6a4bb4acf3ee3ae611943e2596a73e9adb4da74432b1bcd686539f7f56f
stats: shared=0 unique=36 size=51.88MiB ratio=1.00

phase 0:
mirror-registry.test-mirror-registry.svc:5000 mirror-source.hypershift-e2e.invalid/libpod/registry blobs=36 mounts=0 manifests=7 shared=0

info: Planning completed in 470ms
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:8564ce36feee688566265012773f1c8c7c046ceefe86ca763eb702682f4e6e75 278.2KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:5b6190aef38cde840b7e3d42e994f80ada99568850af79c76d02de250bdbf822 5.311MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:5d54e960e981301b0098c80d2e61d694333b5ab480a007a3a8d0fa629662d377 279.6KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:1c079a77918c61cc345bb0ae4562cc6899919358575cce027348d0d152129519 5.001MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:cb9be1f8a1947aa58bb268c308b33b52ab00c239d020b6230ef9accdcebfcfd2 5.134MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:c4d48a809fc2256f8aa0aeee47998488d64409855adba00a7cb3007ab9f3286e 278KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:a47bd95d78f565e902bafd0264a979eb4f6f71e22c0464011bf9db6feb0579e6 277.4KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:175521994a5932158dbd78d2153c38836ab5e1db0ceb4af91113d4c49c5caba2 278.4KiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:4ef77a110d155ae5e1170b2dd0199770fcf951614ae89fe3de52643dfc68f1da 5.389MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:55353ca330e9474ce7b858eca6842bb540ef4a70b2981c2ed47eefb9ef4253ad 3.191MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:9fda8d8052c61740409c4bea888859c141fd8cc3f58ac61943144ff6d1681b2d 3.176MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de 3.244MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:88b450dec42ebc9659f10c6fd6d2326706fec4ab7aadf0c38973d930c23c546a 5.634MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:af09961d4a43b504efc76e38b50918977c28be73eeb8b926247783a00e8b9f2f 2.999MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:998cc98447b44e5f0fe799dce691412796ba586ab22eb7c99aebf9d45f34833b 3.065MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:93cca240aafc896515ff6b5406baf949e4054d981f863022f3471a389e425967 5.312MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:f8dec92eec42224ef9e6ca9c6207ea6b9195dcf93d06bd5ceff0f814b62bf064 2.765MiB
uploading: mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry sha256:c966ad2cdd35689da92e7c8fd39bd37cd6080c484e6ccaf00672c154cd4f6c2a 279.9KiB
sha256:a353b4af55af90d0d30511d2191edb9da38f174390ce91e2329fa1839b6c2408 mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:fab2c6a4bb4acf3ee3ae611943e2596a73e9adb4da74432b1bcd686539f7f56f mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27 mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:d72af0ec30bf3a5531f2d4dc4d0893f11b40cfd0a5dcbcbdcc19adde233847d2 mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:ea32c4ea1ffa10d85c25b55e3e775a72013e685bf80f8da79ec5c5ddc4a4a63f mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:4cab339812e3bfa9e2242292f46ca2a99e804a4604d29f342f2b935381ebad3c mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f mirror-registry.test-mirror-registry.svc:5000/mirror-source.hypershift-e2e.invalid/libpod/registry
info: Mirroring completed in 6.55s (8.304MB/s)
```

### Step 5 — read-only push rejection

The registry answers blob uploads with `HTTP 405 Method not allowed` (plain-text body, hence oc's JSON parse
message). T4 can match `HTTP 405` / `Method not allowed` to report "registry is read-only" in diagnostics.

```text
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:a7014e8ccc173fe30110a1dcfc70dc51f019db33b9c55714472ff9c440ddec60: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:6f22f5bf08e6a4c52dcaa0f76c001116ca484b811f4aabe2e1114ede0473768d: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:7417fa3c6d923a722787ff60825c3c40f74621ab2e4abcc120e25b10a35e4811: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:89015d87ad663ad7dc3c895507a48abf75af42d5aa96f45cf58774376507ef39: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to upload blob sha256:a47bd95d78f565e902bafd0264a979eb4f6f71e22c0464011bf9db6feb0579e6 to mirror-registry.test-mirror-registry.svc:5000/readonly-check/registry: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to upload blob sha256:cb9be1f8a1947aa58bb268c308b33b52ab00c239d020b6230ef9accdcebfcfd2 to mirror-registry.test-mirror-registry.svc:5000/readonly-check/registry: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:3745f5e7cc696592c982fb456207ad8a32889e9a5a5b8f17525a469397aa5aab: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
error: unable to push quay.io/libpod/registry: failed to upload blob sha256:b58a5a1ef3b60d92194b55c0fabaf01e31cdc2671f4198dee4162ad3a922507e: error parsing HTTP 405 response body: invalid character 'M' looking for beginning of value: "Method not allowed\n"
info: Mirroring completed in 6.49s (0B/s)
error: one or more errors occurred while uploading images
```

### Step 7 — laptop checks

Anonymous `/v2/` OK with our CA, TLS refused without it, virtual-repository digest matches, push through the
Route rejected with 405. The `quay.io/libpod/registry` digest line was lost in the paste and re-run separately
(see the end of this block).

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ curl -sS --cacert "$OUT/certs/ca.crt" -w '  HTTP %{http_code}\n' "https://${HOST}/v2/"
{}  HTTP 200
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ curl -sS -o /dev/null "https://${HOST}/v2/" ; echo "exit=$? (expected non-zero, certificate error)"
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
exit=60 (expected non-zero, certificate error)
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ mkdir -p "$OUT/ca-only" && cp "$OUT/certs/ca.crt" "$OUT/ca-only/ca.crt"
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ for repo in quay.io/libpod/registry "${VIRTUAL_REPO}"; do
echo "$repo: sha256:$(skopeo inspect --raw --no-creds --cert-dir "$OUT/ca-only" \
"docker://${HOST}/${repo}@${TEST_DIGEST}" | shasum -a 256 | cut -d' ' -f1)"
done
quay.io/libpod/registry: sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
mirror-source.hypershift-e2e.invalid/libpod/registry: sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ echo "expected: ${TEST_DIGEST}"
expected: sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ skopeo copy --all --dest-no-creds --dest-cert-dir "$OUT/ca-only" \
"docker://${TEST_SRC_REPO}@${TEST_DIGEST}" "docker://${HOST}/route-push-check/registry:x" ; echo "exit=$? (expected non-zero)"
Getting image list signatures
Copying 6 images generated from 6 images in list
Copying image sha256:da1fbcd13a7ddc77d0d964a5c5c4cb707b5d440a028b0b42fe574b9e99077e27 (1/6)
Getting image source signatures
Copying blob 121f958bea53 [>-------------------------------------] 8.0b / 399.0b | 6.1 KiB/s
Copying blob c4d48a809fc2 [--------------------------------------] 8.0b / 278.0KiB | 91.5 KiB/s
Copying blob 7264a8db6415 [--------------------------------------] 8.0b / 3.2MiB | 176.4 KiB/s
Copying blob 7417fa3c6d92 [>-------------------------------------] 8.0b / 214.0b | 416.7 KiB/s
Copying blob 88b450dec42e [--------------------------------------] 8.0b / 5.6MiB | 310.4 KiB/s
FATA[0003] copying image 1/6 from manifest list: writing blob: initiating layer upload to /v2/route-push-check/registry/blobs/uploads/ in mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com: StatusCode: 405, "Method not allowed\n"
exit=1 (expected non-zero)
$ # re-run for quay.io/libpod/registry
$ echo "sha256:$(skopeo inspect --raw --no-creds --cert-dir "$OUT/ca-only" "docker://${HOST}/quay.io/libpod/registry@${TEST_DIGEST}" | shasum -a 256 | cut -d' ' -f1)"
sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
$ echo "expected: ${TEST_DIGEST}"
expected: sha256:e642e8604d305a3b82c8c1807b5df7a1a84cc650d57a60f9c5c2b78efec54b3f
```

### Step 8 — re-apply output

All objects `unchanged`; registry pod not restarted.

```text
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ k -n "$NS" get pods
NAME                               READY   STATUS      RESTARTS   AGE
mirror-readonly-check-bg7vw        0/1     Error       0          11m
mirror-registry-67bc44dc59-qz9dk   1/1     Running     0          12m
mirror-test-pmtxt                  0/1     Completed   0          19m
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ for f in registry-config pvc service deployment route; do READONLY=true render $f.yaml | k apply -f -; done
configmap/mirror-registry-config unchanged
persistentvolumeclaim/mirror-registry unchanged
service/mirror-registry unchanged
deployment.apps/mirror-registry unchanged
route.route.openshift.io/mirror-registry unchanged
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗ k -n "$NS" get pods
NAME                               READY   STATUS      RESTARTS   AGE
mirror-readonly-check-bg7vw        0/1     Error       0          12m
mirror-registry-67bc44dc59-qz9dk   1/1     Running     0          13m
mirror-test-pmtxt                  0/1     Completed   0          20m
(⎈|mgmt:default)➜  hypershift-fork git:(CNTRLPLANE-3926) ✗
```

### Step 9 — effective securityContext

Defaults injected by `restricted-v2` (not set in our manifest): container `runAsUser`, pod `fsGroup` and
SELinux level. Our manifest sets `runAsNonRoot`, `seccompProfile`, `allowPrivilegeEscalation`, `drop: ALL`.
The builders (T3) must **not** set a fixed UID/fsGroup.

```text
$ k -n "$NS" get pod -l app.kubernetes.io/name="$NAME" -o yaml | grep -A12 'securityContext:' | head -40
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
          - ALL
        runAsUser: 1000630000
      terminationMessagePath: /dev/termination-log
      terminationMessagePolicy: File
      volumeMounts:
      - mountPath: /etc/registry
        name: config
        readOnly: true
      - mountPath: /certs
--
    securityContext:
      fsGroup: 1000630000
      runAsNonRoot: true
      seLinuxOptions:
        level: s0:c25,c15
      seccompProfile:
        type: RuntimeDefault
    serviceAccount: default
    serviceAccountName: default
    terminationGracePeriodSeconds: 30
    tolerations:
    - effect: NoExecute
      key: node.kubernetes.io/not-ready

$ k -n "$NS" get pvc "$NAME" -o jsonpath='{.spec.storageClassName} {.status.capacity.storage}{"\n"}'
gp3-csi 5Gi
```

### Step 10 — release dry-run output

Dry-run only (nothing pushed). Release = the management cluster's own 4.20.0 x86_64 payload. Size is the
compressed transfer/storage size reported by the mirror planner. Both source repositories map to a single
mirror repository (`<host>/quay.io/openshift-release-dev/ocp-release`), consistent with D6.

```text
$ k -n "$NS" logs job/release-dryrun
=== size
  service-ca-operator                              1y       4    185.8       54.5  A
  telemeter                                        1y       4    174.7       43.4  A
  tests                                            1y       5    428.6      122.1  A
  thanos                                           1y       4    179.5       48.2  A
  tools                                            1y       4    306.4      175.1  A
  volume-data-source-validator                     1y       4    158.1       26.8  A
  vsphere-cloud-controller-manager                 1y       4    154.2       22.9  A
  vsphere-cluster-api-controllers                  1y       4    152.1       20.7  A
  vsphere-csi-driver                               1y       4    162.8       31.4  A
  vsphere-csi-driver-operator                      1y       4    182.8       51.5  A
  vsphere-csi-driver-syncer                        1y       4    153.3       21.9  A
  vsphere-problem-detector                         1y       4    179.8       48.5  A

  23.7GB across 251 layers, 3 different base images

=== component repositories (unique)
quay.io/openshift-release-dev/ocp-v4.0-art-dev
=== mirror dry-run
      sha256:fc832d6c086430f7b4841101512c95fa6788f84a9b8e89ebabfda1bcad6073f8 -> 4.20.0-x86_64-insights-operator
      sha256:fd8aa5e47d7d104e9db12009963556175580f41cb6be2feaf561a24a4b92d22b -> 4.20.0-x86_64-telemeter
      sha256:fd999c36faf3fffb2242648b2738733ab143ce62dd278f0795d01af4aec39790 -> 4.20.0-x86_64-cluster-cloud-controller-manager-operator
  stats: shared=4 unique=440 size=22.08GiB ratio=0.99

phase 0:
  mirror-registry.test-mirror-registry.svc:5000 quay.io/openshift-release-dev/ocp-release blobs=444 mounts=0 manifests=192 shared=4

info: Planning completed in 37.32s
info: Dry run complete

Success
Update image:  mirror-registry.test-mirror-registry.svc:5000/quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64
Mirror prefix: mirror-registry.test-mirror-registry.svc:5000/quay.io/openshift-release-dev/ocp-release

imageDigestSources:
- mirrors:
  - mirror-registry.test-mirror-registry.svc:5000/quay.io/openshift-release-dev/ocp-release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - mirror-registry.test-mirror-registry.svc:5000/quay.io/openshift-release-dev/ocp-release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Step 11 — `oc` in the CI test image

Base of the final stage of `Dockerfile.e2e`. `Dockerfile.e2e` only copies HyperShift binaries and installs
`azure-cli` on top, so the `hypershift-tests` image has no `oc` either. This confirms D5: copying must run
in-cluster (Job with the `openshift/cli` image), not from the CI pod.

```text
$ podman run --rm --authfile "$OUT/ci-auth.json" --entrypoint /bin/sh \
    registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.26-openshift-5.1 -c 'command -v oc && oc version --client || echo "no oc"'
...
Writing manifest to image destination
no oc
```
