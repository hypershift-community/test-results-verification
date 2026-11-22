# CNTRLPLANE-3927 — Live propagation results

Date: 2026-10-19 (12:17–13:06 CEST)  Cluster: mgmt (OCP 4.20.0, nested hosted cluster)  HC: `clusters/image-mirroring-beaa1f2bd2` (4.20.0, 2 nodes)  Branch/commit: `CNTRLPLANE-3927` @ `c9ad656db6`  Run by: @Nirshal

Keep table cells to one line. Put command output in the **Evidence** section below, under the matching step,
inside a fenced code block. Never paste kubeconfigs, the pull secret or keys.

**Verdict:** **PASS with notes**: see `../reviews/live.md` (no real failures; notes are a runbook grep false negative, pre-existing noise and leftover checks outside `check.sh clean`, closed by step 6b)

| Step | Item | Result | Notes / exact values |
|------|------|--------|----------------------|
| 0 | Clean tree at c9ad656; binaries built; dry run selects 2 specs | OK | `Will run 2 of 1149`; names not shown by the grep because of ANSI codes (P1), present in `v4-positive.log` and the live run |
| 0 | Preflight (ns absent, no HC, CLI/HO versions, copier image digest, AWS identity, public zone, pull secret, headroom) | OK | 3 ns NotFound, no HC; client c9ad656 / server e83d9072 (4.14–4.21); copier `@sha256:0a9d58f9…`; user/tester; zone public; mem 33–53 % |
| 1 | `create-guests` exit 0, `All clusters are ready` (plan `image-mirroring-propagation`, one cluster) | OK | 12:17:29→12:33:04 (15.5 min); Available 12:24:23; one `create cluster aws` with CA + ICS flags, no `--aws-creds`; no ERROR |
| 1 | `check.sh fixture` 12/12 (SHARED_DIR files, manifest, Route, ICS, registry, CA, laptop TLS, Keycloak) | OK | 12 PASS, 0 failure(s) |
| 1 | `check.sh hc` 4/4 (ICS == fixture, trust bundle == CA, Available, rollout Completed) | OK | 4 PASS, 0 failure(s); NodePool 2/2 4.20.0 |
| 2 | `run-tests`: 2 specs ran, 2 passed, `All test groups passed` | OK | `Ran 2 of 1149`, 2 Passed, 0 Failed (2 Pending = unrelated DNS `PIt`), exit=0 |
| 2 | Two `Successfully waited for` lines (hosted IDMS; HCP ConfigMap) | OK | IDMS 1.075 s; CM `clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source` 125 ms |
| 2 | `check.sh junit` 6/6 (2 testcases passed, no skip/failure, DryRun=false) | OK | 6 PASS, 0 failure(s) |
| 3 | `check.sh guest` 5/5 (hosted IDMS: GVK/name, worker label, mappings == HC) | OK | 5 PASS; 2 nodes Ready; no `mirrorSourcePolicy` |
| 3 | `check.sh cm` 6/6 (CM core label, payload GVK/name, worker label, mappings == HC) | OK | 6 PASS; payload `config.openshift.io/v1` IDMS `cluster` |
| 3 | CPO / HCCO images (producers exercised) | OK | both `ocp-v4.0-art-dev@sha256:5491113a…` (4.20.0 payload hypershift image; not in repo overrides) |
| 4 | (opt.) Repeat `run-tests`: 2 passed; `check.sh junit` 6/6 | OK | IDMS 1.275 s, CM 150 ms; 2 Passed; 6 PASS; logs differ only in timestamps/seed/durations |
| 6 | `destroy-guests` exit 0; `clusters` ns removed; Keycloak + mirror ns deleted | OK | 12:58:45→13:05:16 (6.5 min); leftovers only `user-ca-bundle` + defaults; 3 ns deleted |
| 6 | `check.sh clean` 7/7 (no HC/HCP/ns/PV/VPC/instances left) | OK | 7 PASS; step 6b: S3 OIDC docs, public-zone records, mgmt KAS ELB (classic + v2) all empty |

## Problems found

| # | Step | Symptom | Root cause | Action |
|---|------|---------|------------|--------|
| P1 | 0 | Dry-run grep printed no spec names | Ginkgo colour codes split `Mirroring` / `should` even when piped | Use `--ginkgo.no-color` in the runbook; the names are proven by other evidence |
| P2 | 1 | `oc get hostedcluster,nodepool -w` rejected | `-w` takes a single resource type | Runbook fix (split into two watches, as done) |
| P3 | 6 | `check.sh clean` covers only the VPC and instances | check scope | Resolved: step 6b queries (S3, Route53, ELB, ELBv2) all empty |

## Surprises / follow-ups (PR description, CNTRLPLANE-3929)

- First end-to-end run of the 3926 `create-guests` wiring: fixture → SHARED_DIR → CLI flags → HC worked without manual steps.
- create-guests took 15.5 min including the full rollout (estimate was 25–45 min); destroy took 6.5 min.
- The `log.SetLogger(...) was never called` stack trace in create-guests Phase 3 (`main.go:355`) is pre-existing noise; worth fixing for CI log readability (3929).
- HC `Available` flipped on KAS ELB `/healthz` timeouts during the rollout; create-guests tolerated it.
- Keycloak is deployed by AWS `PreCreate` even for an image-mirroring-only plan (cost/flakiness for 3929).
- `out/` still holds `mc.kubeconfig` and the dump-guests output: keep local, delete when done.

## Evidence

### Step 0 — git, build, dry run, preflight

```text
git status --short && git log --oneline -1
c9ad656db6 (HEAD -> CNTRLPLANE-3927) test(e2e): verify image mirroring propagation through independent paths
$ source .work/cntrlplane-3927/propagation/env.sh
CTX=mgmt HOST=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com
HC=clusters/image-mirroring-beaa1f2bd2 HCP_NS=clusters-image-mirroring-beaa1f2bd2 RELEASE=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 NODES=2
PROP_OUT=~/hypershift/.work/cntrlplane-3927/propagation/out
$ make hypershift e2ev2 e2ev2-create-guests e2ev2-run-tests e2ev2-destroy-guests
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go build -gcflags=all='-N -l' -ldflags '-X github.com/openshift/hypershift/support/supportedversion.commitHash=c9ad656db618ee953923cb5f8ec91e3566885d95' -o bin/hypershift .
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go test -gcflags=all='-N -l' -tags e2ev2 -c -o bin/test-e2e-v2 ./test/e2e/v2/tests
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go build -gcflags=all='-N -l' -ldflags '-X github.com/openshift/hypershift/support/supportedversion.commitHash=c9ad656db618ee953923cb5f8ec91e3566885d95' -tags e2ev2 -o bin/create-guests ./test/e2e/v2/cmd/create-guests
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go build -gcflags=all='-N -l' -ldflags '-X github.com/openshift/hypershift/support/supportedversion.commitHash=c9ad656db618ee953923cb5f8ec91e3566885d95' -tags e2ev2 -o bin/run-tests ./test/e2e/v2/cmd/run-tests
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go build -gcflags=all='-N -l' -ldflags '-X github.com/openshift/hypershift/support/supportedversion.commitHash=c9ad656db618ee953923cb5f8ec91e3566885d95' -tags e2ev2 -o bin/destroy-guests ./test/e2e/v2/cmd/destroy-guests
$ bin/test-e2e-v2 --ginkgo.dry-run --ginkgo.v --ginkgo.label-filter='lifecycle && image-mirroring' 2>&1 | grep -E 'Will run|Image Mirroring should'
Will run 2 of 1149 specs
$ k get ns "$NS" "$KC_NS" "$HC_NS"
Error from server (NotFound): namespaces "test-mirror-registry" not found
Error from server (NotFound): namespaces "keycloak" not found
Error from server (NotFound): namespaces "clusters" not found
$ k get hostedcluster -A
No resources found
$ hs version
Client Version: openshift/hypershift: c9ad656db618ee953923cb5f8ec91e3566885d95. Latest supported OCP: 5.1.0
Server Version: e83d907270ba8545b371edfa7b69989da2903214
Server Supports OCP Versions: 4.21, 4.20, 4.19, 4.18, 4.17, 4.16, 4.15, 4.14
$ k -n openshift get imagestream cli -o jsonpath='{.status.tags[?(@.tag=="latest")].items[0].dockerImageReference}{"\n"}'
quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0a9d58f9d8dd969c7bd107319a2498a674fe4e6477185a44558f168d994b39a5
$ k adm top nodes
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
ip-10-0-10-47.ec2.internal   74m          4%       3231Mi          48%
ip-10-0-11-95.ec2.internal   64m          4%       2700Mi          40%
ip-10-0-2-125.ec2.internal   78m          5%       3419Mi          51%
ip-10-0-4-230.ec2.internal   126m         8%       3556Mi          53%
ip-10-0-5-85.ec2.internal    66m          4%       2195Mi          33%
$ e2e aws sts get-caller-identity --query Arn --output text
arn:aws:iam::123456789012:user/tester
$ e2e aws route53 list-hosted-zones-by-name --dns-name "$BASE_DOMAIN" --max-items 1 \
  --query 'HostedZones[0].[Name,Config.PrivateZone]' --output text
hypershift.example.com.   False
$ jq -e '.auths["quay.io"]' "$PULL_SECRET" >/dev/null && echo "pull secret has quay.io"
pull secret has quay.io
$ ls -A "$SHARED" "$ARTIFACTS"
~/hypershift/.work/cntrlplane-3927/propagation/out/artifacts:

~/hypershift/.work/cntrlplane-3927/propagation/out/shared:
$
```

### Step 1 — create-guests (grep + tail of create.log), check.sh fixture, check.sh hc, ics.yaml, HC/NodePool

```text
$ date; e2e bin/create-guests 2>&1 | tee "$PROP_OUT/create.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
Mon Oct 19 12:17:29 CEST 2026
2026/10/19 12:17:31 AWS platform config: region=us-east-1, zones=[us-east-1a], additionalTags=[expirationDate=2026-10-19T14:17:31Z hypershift.openshift.io/prow-job-id=tester-cntrlplane-3927-run1]
2026/10/19 12:17:31 Using test plan "image-mirroring-propagation"
2026/10/19 12:17:31 Phase 0: Computing cluster identities and writing manifest
2026/10/19 12:17:31 Cluster image-mirroring: name=image-mirroring-beaa1f2bd2
2026/10/19 12:17:31 Wrote cluster manifest to ~/hypershift/.work/cntrlplane-3927/propagation/out/shared/cluster-manifests.json
2026/10/19 12:17:31 Phase 1: Running platform pre-create hooks
2026/10/19 12:18:33 Keycloak pod is ready, running setup script via exec...
2026/10/19 12:19:10 Keycloak setup completed: Authenticating to Keycloak...
Keycloak is ready
Created CLI client: oc-cli-test
Created console client: console-test
Added group mapper to CLI client
Added audience mapper to CLI client
Added group mapper to console client
Added audience mapper to console client
Created group: keycloak-testgroup-1
Created user: keycloak-testuser-1 in group keycloak-testgroup-1
Keycloak setup complete
Logging into http://localhost:8080 as user admin of realm master
Created new client with id '3f058bdc-e420-4899-bc1f-a704678b356c'
Created new client with id 'bedb8990-656c-46b1-ab1a-1aa657556184'
Created new model with id 'cc773a62-ae8b-471d-aebd-35da8d2bc4ad'
Created new model with id '4a7124b3-bd26-45ea-b485-5481c136d250'
Created new model with id 'ddd28258-1bc9-49b3-8800-f1130d64a21a'
Created new model with id '4c4661ad-8a09-48e4-83b5-7c2bb887d37e'
Created new group with id '51507bed-b9ec-411d-bd92-53716f94e53d'
Created new user with id 'a7fa525e-e61c-40c4-9fea-beb6eda6ffda'
2026/10/19 12:19:11 Keycloak deployed: issuer=https://keycloak-keycloak.apps.mgmt.hypershift.example.com/realms/master
2026/10/19 12:19:51 Phase 2: Creating 1 clusters in parallel
2026/10/19 12:19:51 Creating image-mirroring cluster image-mirroring-beaa1f2bd2
2026/10/19 12:19:51 Running: ~/hypershift/bin/hypershift [create cluster aws --name=image-mirroring-beaa1f2bd2 --namespace=clusters --infra-id=image-mirroring-beaa1f2bd2 --node-pool-replicas=2 --base-domain=hypershift.example.com --pull-secret=~/pull-secret --release-image=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 --generate-ssh --region=us-east-1 --zones=us-east-1a --root-volume-size=64 --root-volume-type=gp3 --pods-labels=hypershift-e2e-test-label=test --toleration=key=hypershift-e2e-test-toleration,operator=Equal,value=true,effect=NoSchedule --annotations=hypershift.openshift.io/cleanup-cloud-resources=true --annotations=hypershift.openshift.io/skip-release-image-validation=true --additional-tags=expirationDate=2026-10-19T14:17:31Z --additional-tags=hypershift.openshift.io/prow-job-id=tester-cntrlplane-3927-run1 --additional-trust-bundle=~/hypershift/.work/cntrlplane-3927/propagation/out/shared/mirror-registry-ca.pem --image-content-sources=~/hypershift/.work/cntrlplane-3927/propagation/out/shared/mirror-registry-ics.yaml]
{"level":"info","ts":"2026-10-19T12:19:53+02:00","msg":"Creating infrastructure","id":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:19:55+02:00","msg":"Created VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:55+02:00","msg":"Enabled DNS support on VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:55+02:00","msg":"Enabled DNS hostnames on VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:56+02:00","msg":"Created DHCP options","id":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:56+02:00","msg":"Associated DHCP options with VPC","vpc":"vpc-0000000000000000","dhcp options":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:57+02:00","msg":"Created internet gateway","id":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:57+02:00","msg":"Attached internet gateway to VPC","internet gateway":"igw-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:58+02:00","msg":"Created subnet","name":"image-mirroring-beaa1f2bd2-private-us-east-1a","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:19:59+02:00","msg":"Created subnet","name":"image-mirroring-beaa1f2bd2-public-us-east-1a","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:01+02:00","msg":"Created elastic IP for NAT gateway","id":"eipalloc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:01+02:00","msg":"Created NAT gateway","id":"nat-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:02+02:00","msg":"Created route table","name":"image-mirroring-beaa1f2bd2-private-us-east-1a","id":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:06+02:00","msg":"Created route to NAT gateway","route table":"rtb-0000000000000000","nat gateway":"nat-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:06+02:00","msg":"Associated subnet with route table","route table":"rtb-0000000000000000","subnet":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:07+02:00","msg":"Created route table","name":"image-mirroring-beaa1f2bd2-public","id":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:07+02:00","msg":"Set main VPC route table","route table":"rtb-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:08+02:00","msg":"Created route to internet gateway","route table":"rtb-0000000000000000","internet gateway":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:08+02:00","msg":"Associated route table with subnet","route table":"rtb-0000000000000000","subnet":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:09+02:00","msg":"Created s3 VPC endpoint","id":"vpce-0000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:10+02:00","msg":"Found existing public zone","name":"hypershift.example.com","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:11+02:00","msg":"Created private zone","name":"image-mirroring-beaa1f2bd2.hypershift.example.com","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:12+02:00","msg":"Created private zone","name":"image-mirroring-beaa1f2bd2.hypershift.local","id":"Z00000000000000000000"}
{"level":"info","ts":"2026-10-19T12:20:13+02:00","msg":"Detected Issuer URL","issuer":"https://oidc-bucket.s3.us-east-1.amazonaws.com/image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:20:14+02:00","msg":"Created OIDC provider","provider":"arn:aws:iam::123456789012:oidc-provider/oidc-bucket.s3.us-east-1.amazonaws.com/image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:20:14+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-19T12:20:14+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-19T12:20:15+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-cloud-controller"}
{"level":"info","ts":"2026-10-19T12:20:15+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-cloud-controller"}
{"level":"info","ts":"2026-10-19T12:20:16+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-node-pool"}
{"level":"info","ts":"2026-10-19T12:20:16+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-node-pool"}
{"level":"info","ts":"2026-10-19T12:20:16+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-control-plane-operator"}
{"level":"info","ts":"2026-10-19T12:20:16+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-control-plane-operator"}
{"level":"info","ts":"2026-10-19T12:20:17+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-19T12:20:17+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-19T12:20:17+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-openshift-ingress"}
{"level":"info","ts":"2026-10-19T12:20:17+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-openshift-ingress"}
{"level":"info","ts":"2026-10-19T12:20:18+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-openshift-image-registry"}
{"level":"info","ts":"2026-10-19T12:20:18+02:00","msg":"Added/Updated role policy","name":"image-mirroring-beaa1f2bd2-openshift-image-registry"}
{"level":"info","ts":"2026-10-19T12:20:18+02:00","msg":"Created role","name":"image-mirroring-beaa1f2bd2-worker-role"}
{"level":"info","ts":"2026-10-19T12:20:19+02:00","msg":"Created instance profile","name":"image-mirroring-beaa1f2bd2-worker"}
{"level":"info","ts":"2026-10-19T12:20:19+02:00","msg":"Added role to instance profile","role":"image-mirroring-beaa1f2bd2-worker-role","profile":"image-mirroring-beaa1f2bd2-worker"}
{"level":"info","ts":"2026-10-19T12:20:19+02:00","msg":"Created role policy","name":"image-mirroring-beaa1f2bd2-worker-policy"}
{"level":"info","ts":"2026-10-19T12:20:19+02:00","msg":"Created IAM profile","name":"image-mirroring-beaa1f2bd2-worker","region":"us-east-1"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"Namespace","namespace":"","name":"clusters"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"ConfigMap","namespace":"clusters","name":"user-ca-bundle"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"image-mirroring-beaa1f2bd2-pull-secret"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"image-mirroring-beaa1f2bd2-ssh-key"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"Secret","namespace":"clusters","name":"image-mirroring-beaa1f2bd2-etcd-encryption-key"}
{"level":"info","ts":"2026-10-19T12:20:20+02:00","msg":"Applied Kube resource","kind":"","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:20:21+02:00","msg":"Applied Kube resource","kind":"NodePool","namespace":"clusters","name":"image-mirroring-beaa1f2bd2-us-east-1a"}
2026/10/19 12:20:21 Cluster image-mirroring-beaa1f2bd2 (image-mirroring) creation command completed
2026/10/19 12:20:21 Phase 3: Running platform post-create hooks
[controller-runtime] log.SetLogger(...) was never called; logs will not be displayed.
Detected at:
	>  goroutine 1 [running]:
	>  runtime/debug.Stack()
	>  	~/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.26.3.darwin-arm64/src/runtime/debug/stack.go:26 +0x74
	>  sigs.k8s.io/controller-runtime/pkg/log.eventuallyFulfillRoot()
	>  	~/hypershift/vendor/sigs.k8s.io/controller-runtime/pkg/log/log.go:60 +0xa0
	>  sigs.k8s.io/controller-runtime/pkg/log.(*delegatingLogSink).WithName(0x1acc281daf40, {0x105c9320c, 0x6})
	>  	~/hypershift/vendor/sigs.k8s.io/controller-runtime/pkg/log/deleg.go:147 +0x38
	>  github.com/go-logr/logr.Logger.WithName({{0x1091d6c40, 0x1acc281daf40}, 0x0}, {0x105c9320c, 0x6})
	>  	~/hypershift/vendor/github.com/go-logr/logr/logr.go:345 +0x60
	>  sigs.k8s.io/controller-runtime/pkg/client.newClient(0x1acc28329208, {0x1acc28bd4e70, 0x1acc28000c40, {0x1091d9d60, 0x1acc28a4c910}, 0x0, 0x0, {0x0, 0x0}, {0x0, ...}, ...})
	>  	~/hypershift/vendor/sigs.k8s.io/controller-runtime/pkg/client/client.go:207 +0x354
	>  sigs.k8s.io/controller-runtime/pkg/client.NewWithWatch(0x1acc2827a6c8, {0x0, 0x1acc28000c40, {0x0, 0x0}, 0x0, 0x0, {0x0, 0x0}, {0x0, ...}, ...})
	>  	~/hypershift/vendor/sigs.k8s.io/controller-runtime/pkg/client/watch.go:31 +0xb8
	>  main.newMgmtClient()
	>  	~/hypershift/test/e2e/v2/cmd/create-guests/main.go:355 +0x308
	>  main.run({0x1091d09d8, 0x1acc28000f50}, {{0x1acc27c3028a, 0x71}, {0x1acc27c2018c, 0x1d}, {0x1acc27c3018b, 0x6d}, {0x1acc27c3020d, 0x70}, ...})
	>  	~/hypershift/test/e2e/v2/cmd/create-guests/main.go:215 +0x1028
	>  main.main()
	>  	~/hypershift/test/e2e/v2/cmd/create-guests/main.go:103 +0x10c
2026/10/19 12:20:21 Phase 4: Waiting for all clusters to become Available
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=Unknown, VersionState=<none>
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:22 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:24 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:24 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:25 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:25 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:25 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:26 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:27 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:27 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:28 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:20:54 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:10 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:10 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:10 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:10 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:11 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:40 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:40 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:40 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:22:40 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:16 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:20 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:25 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:31 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:52 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:23:54 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:24:23 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:24:23 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:24:23 Cluster image-mirroring-beaa1f2bd2 (image-mirroring) is Available
2026/10/19 12:24:23 Phase 5: Running platform post-available hooks
2026/10/19 12:24:23 Phase 6: Waiting for version rollout completion on all clusters
2026/10/19 12:24:24 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:24:29 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:24:34 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:24:38 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:24:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:24:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:25:02 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:25:04 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:25:13 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:19 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:34 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:35 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:37 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:40 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:42 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:25:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:26:04 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:26:04 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:26:15 Cluster clusters/image-mirroring-beaa1f2bd2: Available=False, VersionState=Partial
2026/10/19 12:26:16 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:26:35 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:26:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:27:17 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:29:34 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:29:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:30:12 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:30:27 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:30:28 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:30:34 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:31:34 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:31:49 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Partial
2026/10/19 12:33:04 Cluster clusters/image-mirroring-beaa1f2bd2: Available=True, VersionState=Completed
2026/10/19 12:33:04 Version rollout completed for image-mirroring-beaa1f2bd2 (image-mirroring)
2026/10/19 12:33:04 Phase 7: Running platform post-version-rollout hooks (day-2 operations)
2026/10/19 12:33:04 All clusters are ready
exit=0
Mon Oct 19 12:33:04 CEST 2026
$ grep -E 'Using test plan|Phase [0-9]|Cluster image-mirroring|Keycloak deployed|Running: |is Available|Version rollout|All clusters are ready|ERROR' "$PROP_OUT/create.log"
2026/10/19 12:17:31 Using test plan "image-mirroring-propagation"
2026/10/19 12:17:31 Phase 0: Computing cluster identities and writing manifest
2026/10/19 12:17:31 Cluster image-mirroring: name=image-mirroring-beaa1f2bd2
2026/10/19 12:17:31 Phase 1: Running platform pre-create hooks
2026/10/19 12:19:11 Keycloak deployed: issuer=https://keycloak-keycloak.apps.mgmt.hypershift.example.com/realms/master
2026/10/19 12:19:51 Phase 2: Creating 1 clusters in parallel
2026/10/19 12:19:51 Running: ~/hypershift/bin/hypershift [create cluster aws --name=image-mirroring-beaa1f2bd2 --namespace=clusters --infra-id=image-mirroring-beaa1f2bd2 --node-pool-replicas=2 --base-domain=hypershift.example.com --pull-secret=~/pull-secret --release-image=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 --generate-ssh --region=us-east-1 --zones=us-east-1a --root-volume-size=64 --root-volume-type=gp3 --pods-labels=hypershift-e2e-test-label=test --toleration=key=hypershift-e2e-test-toleration,operator=Equal,value=true,effect=NoSchedule --annotations=hypershift.openshift.io/cleanup-cloud-resources=true --annotations=hypershift.openshift.io/skip-release-image-validation=true --additional-tags=expirationDate=2026-10-19T14:17:31Z --additional-tags=hypershift.openshift.io/prow-job-id=tester-cntrlplane-3927-run1 --additional-trust-bundle=~/hypershift/.work/cntrlplane-3927/propagation/out/shared/mirror-registry-ca.pem --image-content-sources=~/hypershift/.work/cntrlplane-3927/propagation/out/shared/mirror-registry-ics.yaml]
2026/10/19 12:20:21 Cluster image-mirroring-beaa1f2bd2 (image-mirroring) creation command completed
2026/10/19 12:20:21 Phase 3: Running platform post-create hooks
2026/10/19 12:20:21 Phase 4: Waiting for all clusters to become Available
2026/10/19 12:24:23 Cluster image-mirroring-beaa1f2bd2 (image-mirroring) is Available
2026/10/19 12:24:23 Phase 5: Running platform post-available hooks
2026/10/19 12:24:23 Phase 6: Waiting for version rollout completion on all clusters
2026/10/19 12:33:04 Version rollout completed for image-mirroring-beaa1f2bd2 (image-mirroring)
2026/10/19 12:33:04 Phase 7: Running platform post-version-rollout hooks (day-2 operations)
2026/10/19 12:33:04 All clusters are ready
$ .work/cntrlplane-3927/propagation/check.sh fixture
PASS  SHARED_DIR/cluster-manifests.json written
PASS  SHARED_DIR/mirror-registry-ca.pem written
PASS  SHARED_DIR/mirror-registry-ics.yaml written
PASS  SHARED_DIR/mirror-registry.json written
PASS  manifest: exactly one cluster, image-mirroring clusters/image-mirroring-beaa1f2bd2
PASS  Route test-mirror-registry/mirror-registry host + passthrough
PASS  mirror-registry.json Host == Route host
PASS  mirror-registry-ics.yaml: real + virtual repo → HOST/<source>
PASS  registry Deployment ready
PASS  CA subject hypershift-e2e-mirror-registry-ca
PASS  laptop → https://mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/v2/ trusting only the fixture CA → {} 200
PASS  Keycloak StatefulSet ready (side effect of AWS PreCreate)
check fixture: 0 failure(s)
$ .work/cntrlplane-3927/propagation/check.sh hc
PASS  HC spec.imageContentSources == SHARED_DIR ICS
PASS  HC additionalTrustBundle (user-ca-bundle) == fixture CA
PASS  HC Available=True
PASS  HC version history all Completed (create-guests Phase 6)
check hc: 0 failure(s)
$ cat "$SHARED/mirror-registry-ics.yaml"
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
  source: mirror-source.hypershift-e2e.invalid/libpod/registry
- mirrors:
  - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
  source: quay.io/libpod/registry
$ k -n "$HC_NS" get hostedcluster,nodepool
NAME                                                               VERSION   KUBECONFIG                                    PROGRESS    AVAILABLE   PROGRESSING   MESSAGE
hostedcluster.hypershift.openshift.io/image-mirroring-beaa1f2bd2   4.20.0    image-mirroring-beaa1f2bd2-admin-kubeconfig   Completed   True        False         The hosted control plane is available

NAME                                                                     CLUSTER                      DESIRED NODES   CURRENT NODES   AUTOSCALING   AUTOREPAIR   VERSION   UPDATINGVERSION   UPDATINGCONFIG   MESSAGE
nodepool.hypershift.openshift.io/image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               2               False         False        4.20.0    False             False

```

Terminal #2: just hostedclusters because "-w" can't monitor more than 1 resource at a time
```text
$ source .work/cntrlplane-3927/propagation/env.sh
CTX=mgmt HOST=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com
HC=clusters/image-mirroring-beaa1f2bd2 HCP_NS=clusters-image-mirroring-beaa1f2bd2 RELEASE=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 NODES=2
PROP_OUT=~/hypershift/.work/cntrlplane-3927/propagation/out
$ k -n "$HC_NS" get hostedcluster,nodepool -w
error: you may only specify a single resource type
$ split_tab
$ k -n "$HC_NS" get hostedcluster -w
NAME                         VERSION   KUBECONFIG   PROGRESS   AVAILABLE   PROGRESSING   MESSAGE
image-mirroring-beaa1f2bd2
image-mirroring-beaa1f2bd2
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane to be healthy
image-mirroring-beaa1f2bd2                          Partial    False       False         Cluster infrastructure is still provisioning
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 0s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 1s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 2s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 2s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 3s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 3s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         kube-apiserver load balancer is not provisioned; 3s since creation.
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2                          Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Waiting for hosted control plane kubeconfig to be created
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Waiting for Kube APIServer deployment to become available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Waiting for Kube APIServer deployment to become available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    False       False         Get "https://kas-lb.elb.example.com:6443/healthz": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2             image-mirroring-beaa1f2bd2-admin-kubeconfig   Partial    True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2   4.20.0    image-mirroring-beaa1f2bd2-admin-kubeconfig   Completed   True        False         The hosted control plane is available
image-mirroring-beaa1f2bd2   4.20.0    image-mirroring-beaa1f2bd2-admin-kubeconfig   Completed   True        False         The hosted control plane is available
^C%
```
Terminal #3: just nodepools because "-w" can't monitor more than 1 resource at a time
```text
$ source .work/cntrlplane-3927/propagation/env.sh
CTX=mgmt HOST=mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com
HC=clusters/image-mirroring-beaa1f2bd2 HCP_NS=clusters-image-mirroring-beaa1f2bd2 RELEASE=quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64 NODES=2
PROP_OUT=~/hypershift/.work/cntrlplane-3927/propagation/out
$  k -n "$HC_NS" get nodepool -w
NAME                                    CLUSTER                      DESIRED NODES   CURRENT NODES   AUTOSCALING   AUTOREPAIR   VERSION   UPDATINGVERSION   UPDATINGCONFIG   MESSAGE
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False                                True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False                                True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False                                True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False                                True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False                                True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2                               False         False                  True              True             Minimum availability requires 2 replicas, current 0 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               1               False         False                  True              True             Minimum availability requires 2 replicas, current 1 available
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               1               False         False                  True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               1               False         False                  True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               2               False         False        4.20.0    True              True
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               2               False         False        4.20.0    True              False
image-mirroring-beaa1f2bd2-us-east-1a   image-mirroring-beaa1f2bd2   2               2               False         False        4.20.0    False             False
^C
```

### Step 2 — run-tests (grep of run-tests.log), check.sh junit

```text
$ date; e2e bin/run-tests 2>&1 | tee "$PROP_OUT/run-tests.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
Mon Oct 19 12:40:33 CEST 2026
2026/10/19 12:40:35 AWS platform config: region=us-east-1, zones=[us-east-1a], additionalTags=[expirationDate=2026-10-19T14:40:35Z hypershift.openshift.io/prow-job-id=tester-cntrlplane-3927-run1]
2026/10/19 12:40:35 Using test plan "image-mirroring-propagation"
2026/10/19 12:40:35 Waiting for all test suites to complete...
2026/10/19 12:40:35 Running image-mirroring tests against image-mirroring-beaa1f2bd2...
Environment Variables:
================================================================================

ARTIFACT_DIR (optional) [default: /tmp/artifacts]
  Directory for test artifacts. Defaults to /tmp/artifacts.
  Current value: ~/hypershift/.work/cntrlplane-3927/propagation/out/artifacts

AWS_GUEST_INFRA_CREDENTIALS_FILE (optional) [default: ~/.aws/credentials]
  Path to the AWS guest infrastructure credentials file. Defaults to ~/.aws/credentials.

AWS_MULTI_ARCH (optional)
  Enable multi-arch cluster tests on AWS

AZURE_PRIVATE_ADDITIONAL_ALLOWED_SUBSCRIPTIONS (optional)
  Comma-separated list of Azure subscription IDs permitted to create Private Endpoints.

AZURE_PRIVATE_NAT_SUBNET_ID (optional)
  Azure resource ID of the NAT subnet for Private Link Service. Auto-created by PLS controller if not set.

E2E_AZURE_CREDENTIALS_FILE (optional)
  Path to Azure service principal credentials JSON file for platform-specific tests (auto-repair, disk encryption).

E2E_AZURE_DISK_ENCRYPTION_SET_ID (optional)
  Azure DiskEncryptionSet resource ID for disk encryption NodePool tests.

E2E_EXTERNAL_OIDC_CA_BUNDLE_FILE (optional)
  Path to the CA bundle file for the External OIDC issuer (Keycloak). Written by the lifecycle PostCreate.

E2E_EXTERNAL_OIDC_TEST_USERS (optional)
  Comma-separated list of test users in user:password format for External OIDC testing. Written by the lifecycle PostCreate.

E2E_HOSTED_CLUSTER_NAME (optional)
  Name of the HostedCluster to test. Required for tests that interact with a hosted cluster.
  Current value: image-mirroring-beaa1f2bd2

E2E_HOSTED_CLUSTER_NAMESPACE (optional)
  Namespace of the HostedCluster to test. Required for tests that interact with a hosted cluster.
  Current value: clusters

E2E_LATEST_RELEASE_IMAGE (optional)
  Latest OCP release image for control plane upgrade tests.
  Current value: quay.io/openshift-release-dev/ocp-release:4.20.0-x86_64

E2E_N1_RELEASE_IMAGE (optional)
  N-1 minor release image for NodePool previous-release tests.

E2E_N2_RELEASE_IMAGE (optional)
  N-2 minor release image for NodePool previous-release tests.

E2E_PREVIOUS_RELEASE_IMAGE (optional)
  N-1 OCP release image (previous minor) for control plane upgrade tests.

E2E_SERVICE_DOMAIN (optional)
  Service domain used for custom DNS endpoint testing. Optional; test is skipped when empty.

E2E_SHOW_ENV_HELP (optional)
  When set to any non-empty value, displays environment variable help and exits without running tests.

PULL_SECRET_FILE (optional)
  Path to pull secret file for release image lookups. Used by Karpenter version field tests.

RUN_KARPENTER_TESTS (optional)
  When the value is exactly "true", it lowers the minimum hosted-cluster version from 4.23 to 4.22.

Running Suite: hypershift-e2e - ~/hypershift
================================================================================================
Random Seed: 1792406436

Will run 2 of 1149 specs
------------------------------
[BeforeSuite]
~/hypershift/test/e2e/v2/tests/suite_test.go:79
[BeforeSuite] PASSED [0.001 seconds]
------------------------------
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
P [PENDING]
[sig-hypershift][Jira:Hypershift][Feature:DNS] Hosted Cluster DNS when KubeAPIDNSName and custom certificate are configured should make KAS reachable via the custom DNS endpoint [hosted-cluster-dns, Informing]
~/hypershift/test/e2e/v2/tests/hosted_cluster_dns_test.go:38
------------------------------
P [PENDING]
[sig-hypershift][Jira:Hypershift][Feature:DNS] Hosted Cluster DNS when KubeAPIDNSName and custom certificate are configured should keep KAS reachable via the internal SVC URL [hosted-cluster-dns, Informing]
~/hypershift/test/e2e/v2/tests/hosted_cluster_dns_test.go:68
------------------------------
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
------------------------------
[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring should propagate imageContentSources to the hosted cluster IDMS with the worker role [lifecycle, image-mirroring]
~/hypershift/test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go:28
  Waiting for HC clusters/image-mirroring-beaa1f2bd2 hosted ImageDigestMirrorSet/cluster mappings and worker role
  observed valid **v1.ImageDigestMirrorSet state after 1.075s
   - observed **v1.ImageDigestMirrorSet collection valid:
   - observed **v1.ImageDigestMirrorSet /cluster valid:
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 hosted ImageDigestMirrorSet/cluster mappings and worker role in 1.075s
• [2.955 seconds]
------------------------------
[sig-hypershift][Jira:Hypershift][Feature:ImageMirroring] Hosted Cluster Image Mirroring should propagate imageContentSources independently to the control plane ignition ConfigMap [lifecycle, image-mirroring]
~/hypershift/test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go:57
  Waiting for HC clusters/image-mirroring-beaa1f2bd2 ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels
  observed valid **v1.ConfigMap state after 125ms
   - observed **v1.ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source valid:
   - observed **v1.ConfigMap collection valid:
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels in 125ms
• [0.551 seconds]
------------------------------
SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
------------------------------
[ReportAfterSuite] Write unified JUnit
~/hypershift/test/e2e/v2/tests/suite_test.go:70
[ReportAfterSuite] PASSED [0.003 seconds]
------------------------------

Ran 2 of 1149 Specs in 3.522 seconds
SUCCESS! -- 2 Passed | 0 Failed | 2 Pending | 1145 Skipped
PASS
2026/10/19 12:40:39 image-mirroring tests PASSED
2026/10/19 12:40:39 PASS: image-mirroring
2026/10/19 12:40:39 All test groups passed
exit=0
Mon Oct 19 12:40:39 CEST 2026
$ grep -E 'Using test plan|Running image-mirroring tests|Will run|Successfully waited for|\[PASSED\]|\[FAILED\]|\[SKIPPED\]|Ran [0-9]+ of|tests (PASSED|FAILED)|All test groups passed' "$PROP_OUT/run-tests.log"
2026/10/19 12:40:35 Using test plan "image-mirroring-propagation"
2026/10/19 12:40:35 Running image-mirroring tests against image-mirroring-beaa1f2bd2...
Will run 2 of 1149 specs
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 hosted ImageDigestMirrorSet/cluster mappings and worker role in 1.075s
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels in 125ms
Ran 2 of 1149 Specs in 3.522 seconds
2026/10/19 12:40:39 image-mirroring tests PASSED
2026/10/19 12:40:39 All test groups passed
$ .work/cntrlplane-3927/propagation/check.sh junit
PASS  JUnit junit_image-mirroring.xml exists
PASS  exactly 2 testcases
PASS  testcase passed: ...should propagate imageContentSources to the hosted cluster IDMS with the worker role
PASS  testcase passed: ...should propagate imageContentSources independently to the control plane ignition ConfigMap
PASS  no failure/error/skipped elements
PASS  suite property DryRun=false (live run)
check junit: 0 failure(s)
$
```

### Step 3 — guest nodes, check.sh guest, check.sh cm, HC spec, IDMS yaml, CM payload, CPO/HCCO images

```text
$ guest get nodes
NAME                           STATUS   ROLES    AGE   VERSION
ip-10-0-136-202.ec2.internal   Ready    worker   16m   v1.33.5
ip-10-0-138-49.ec2.internal    Ready    worker   16m   v1.33.5
$ .work/cntrlplane-3927/propagation/check.sh guest
PASS  HC has imageContentSources (non-vacuous oracle)
PASS  hosted ImageDigestMirrorSet/cluster exists
PASS  hosted IDMS: config.openshift.io/v1 ImageDigestMirrorSet 'cluster', cluster-scoped
PASS  hosted IDMS: label machineconfiguration.openshift.io/role=worker
PASS  hosted IDMS: mappings == HC imageContentSources (mirror order kept)
check guest: 0 failure(s)
$ .work/cntrlplane-3927/propagation/check.sh cm
PASS  ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source exists
PASS  CM label hypershift.openshift.io/core-ignition-config=true
PASS  CM data.config decodes as YAML
PASS  CM payload: config.openshift.io/v1 ImageDigestMirrorSet 'cluster', cluster-scoped
PASS  CM payload: label machineconfiguration.openshift.io/role=worker
PASS  CM payload: mappings == HC imageContentSources (mirror order kept)
check cm: 0 failure(s)
$ k -n "$HC_NS" get hostedcluster "$HC_NAME" -o jsonpath='{.spec.imageContentSources}{"\n"}'
[{"mirrors":["mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry"],"source":"mirror-source.hypershift-e2e.invalid/libpod/registry"},{"mirrors":["mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry"],"source":"quay.io/libpod/registry"}]
$ guest get imagedigestmirrorset cluster -o yaml | yq '{"labels": .metadata.labels, "spec": .spec}'
labels:
  hypershift.openshift.io/managed: "true"
  machineconfiguration.openshift.io/role: worker
spec:
  imageDigestMirrors:
    - mirrors:
        - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
      source: mirror-source.hypershift-e2e.invalid/libpod/registry
    - mirrors:
        - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
      source: quay.io/libpod/registry
$ k -n "$HCP_NS" get cm ignition-config-40-image-content-source -o jsonpath='{.metadata.labels}{"\n"}{.data.config}'
{"hypershift.openshift.io/core-ignition-config":"true"}
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  creationTimestamp: null
  labels:
    machineconfiguration.openshift.io/role: worker
  name: cluster
spec:
  imageDigestMirrors:
  - mirrors:
    - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/mirror-source.hypershift-e2e.invalid/libpod/registry
    source: mirror-source.hypershift-e2e.invalid/libpod/registry
  - mirrors:
    - mirror-registry-test-mirror-registry.apps.mgmt.hypershift.example.com/quay.io/libpod/registry
    source: quay.io/libpod/registry
status: {}
$ k -n "$HCP_NS" get deploy control-plane-operator hosted-cluster-config-operator \
  -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
control-plane-operator  quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:5491113af1d9626f249d8c61c33ca0cbe8751a534a15cf366ab5eb0bf5396aef
hosted-cluster-config-operator  quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:5491113af1d9626f249d8c61c33ca0cbe8751a534a15cf366ab5eb0bf5396aef
$
```

### Step 4 — repeat run-tests, check.sh junit

```text
$ e2e bin/run-tests 2>&1 | tee "$PROP_OUT/run-tests-2.log" | grep -E 'Successfully waited for|Ran [0-9]+ of|[0-9]+ Passed|All test groups passed'
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 hosted ImageDigestMirrorSet/cluster mappings and worker role in 1.275s
  Successfully waited for HC clusters/image-mirroring-beaa1f2bd2 ConfigMap clusters-image-mirroring-beaa1f2bd2/ignition-config-40-image-content-source decoded IDMS mappings and labels in 150ms
Ran 2 of 1149 Specs in 3.631 seconds
SUCCESS! -- 2 Passed | 0 Failed | 2 Pending | 1145 Skipped
2026/10/19 12:47:34 All test groups passed
$ .work/cntrlplane-3927/propagation/check.sh junit
PASS  JUnit junit_image-mirroring.xml exists
PASS  exactly 2 testcases
PASS  testcase passed: ...should propagate imageContentSources to the hosted cluster IDMS with the worker role
PASS  testcase passed: ...should propagate imageContentSources independently to the control plane ignition ConfigMap
PASS  no failure/error/skipped elements
PASS  suite property DryRun=false (live run)
check junit: 0 failure(s)
$
```

### Step 5 — diagnostics (only if something failed)
I am doing this even if nothing failed, just for additional data, in case they are needed. 
```text
$ make e2ev2-dump-guests && e2e bin/dump-guests 2>&1 | tail -5
CGO_ENABLED=1 GO111MODULE=on GOWORK=off GOFLAGS=-mod=vendor go build -gcflags=all='-N -l' -ldflags '-X github.com/openshift/hypershift/support/supportedversion.commitHash=c9ad656db618ee953923cb5f8ec91e3566885d95' -tags e2ev2 -o bin/dump-guests ./test/e2e/v2/cmd/dump-guests
{"level":"info","ts":"2026-10-19T12:55:40+02:00","msg":"Successfully dumped guest cluster","duration":"5m39.473705125s"}
{"level":"info","ts":"2026-10-19T12:55:40+02:00","msg":"Archiving dump","command":"tar","args":["-cvzf","hypershift-dump.tar.gz","aggregated-discovery-api.yaml","aggregated-discovery-apis.yaml","cluster-scoped-resources","event-filter.html","hostedcluster-image-mirroring-beaa1f2bd2","namespaces","network_logs","timestamp"]}
{"level":"info","ts":"2026-10-19T12:55:41+02:00","msg":"Successfully archived dump","duration":"1.289783791s"}
2026/10/19 12:55:41 Successfully dumped cluster image-mirroring-beaa1f2bd2
2026/10/19 12:55:41 All cluster dumps complete
$ k -n "$HCP_NS" logs deploy/control-plane-operator --since=2h | grep -iE 'imagedigestmirror|image content|ignition-config-40' | tail -20
Defaulted container "control-plane-operator" out of: control-plane-operator, cloud-token-minter
{"level":"info","ts":"2026-10-19T10:53:45Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"ed215556-5ea1-4f9f-bbe3-73bee69531eb"}
{"level":"info","ts":"2026-10-19T10:53:46Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"e65a6838-133e-4b47-a216-764a4980ba0c"}
{"level":"info","ts":"2026-10-19T10:53:47Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"afbe820d-4d1e-4934-9d01-3eecbe098c9e"}
{"level":"info","ts":"2026-10-19T10:53:47Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"651eadd7-39d3-4bd4-8eb2-667cd126b913"}
{"level":"info","ts":"2026-10-19T10:53:48Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"285ce2ac-36e8-4983-a184-286197e31a7c"}
{"level":"info","ts":"2026-10-19T10:53:49Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"b70f594b-fef8-4566-ac00-a19b582c1a0c"}
{"level":"info","ts":"2026-10-19T10:53:50Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"35e95f71-86a4-4a8b-a591-eaeb467d09b3"}
{"level":"info","ts":"2026-10-19T10:53:50Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"68b4e5d1-dc55-4590-974b-f68a86cb6a7d"}
{"level":"info","ts":"2026-10-19T10:53:51Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"3b86dc8e-16d9-4f0c-a78f-5e68dfb2f100"}
{"level":"info","ts":"2026-10-19T10:53:52Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"f6982a4b-43ec-4aee-8757-a3c70f13318c"}
{"level":"info","ts":"2026-10-19T10:53:53Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"84c4805c-3a6b-4734-a7fb-7af339c5d36d"}
{"level":"info","ts":"2026-10-19T10:53:53Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"49e1fcb5-4935-4d8d-b0f0-2d8ef737ea05"}
{"level":"info","ts":"2026-10-19T10:53:54Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"e9abb0e4-d358-4fc3-935b-0ef8cc0bcd5c"}
{"level":"info","ts":"2026-10-19T10:53:55Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"cf2bda8d-a555-44c4-aede-3c29ce1305dc"}
{"level":"info","ts":"2026-10-19T10:54:21Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"22eb2494-f098-4217-bc10-2a92a4c67124"}
{"level":"info","ts":"2026-10-19T10:54:30Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"164d446d-0454-4d2d-9a17-7a7a05b7497f"}
{"level":"info","ts":"2026-10-19T10:54:31Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"4027b9ad-c4f0-4e9d-b222-f70b1dc61203"}
{"level":"info","ts":"2026-10-19T10:55:22Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"95a90096-1c46-48ea-8893-a9750f726ea3"}
{"level":"info","ts":"2026-10-19T10:55:31Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"3e2f692f-2dc2-44d1-b568-724ce0983bd0"}
{"level":"info","ts":"2026-10-19T10:55:31Z","msg":"Reconciling ImageDigestMirrorSet","controller":"hostedcontrolplane","controllerGroup":"hypershift.openshift.io","controllerKind":"HostedControlPlane","HostedControlPlane":{"name":"image-mirroring-beaa1f2bd2","namespace":"clusters-image-mirroring-beaa1f2bd2"},"namespace":"clusters-image-mirroring-beaa1f2bd2","name":"image-mirroring-beaa1f2bd2","reconcileID":"e4c1adc4-4f91-4c51-9675-f7b76cad0924"}
$ k -n "$HCP_NS" logs deploy/hosted-cluster-config-operator --since=2h | grep -iE 'imagedigestmirror|idms' | tail -20
Defaulted container "hosted-cluster-config-operator" out of: hosted-cluster-config-operator, availability-prober (init)
$
```


### Step 6 — destroy-guests (tail of destroy.log), leftovers, namespace deletion, check.sh clean

```text
$ jq -c .clusters "$SHARED/cluster-manifests.json"
[{"variant":"image-mirroring","name":"image-mirroring-beaa1f2bd2","infraID":"image-mirroring-beaa1f2bd2","namespace":"clusters"}]
$ date; e2e bin/destroy-guests 2>&1 | tee "$PROP_OUT/destroy.log"; echo "exit=${pipestatus[1]:-${PIPESTATUS[0]}}"; date
Mon Oct 19 12:58:45 CEST 2026
2026/10/19 12:58:47 AWS platform config: region=us-east-1, zones=[us-east-1a], additionalTags=[expirationDate=2026-10-19T14:58:47Z hypershift.openshift.io/prow-job-id=tester-cntrlplane-3927-run1]
2026/10/19 12:58:47 Destroying 1 clusters from manifest
2026/10/19 12:58:47 Destroying cluster image-mirroring-beaa1f2bd2 (image-mirroring, infraID=image-mirroring-beaa1f2bd2)
2026/10/19 12:58:47 Running: ~/hypershift/bin/hypershift [destroy cluster aws --name=image-mirroring-beaa1f2bd2 --namespace=clusters --infra-id=image-mirroring-beaa1f2bd2 --cluster-grace-period=40m --region=us-east-1 --base-domain=hypershift.example.com]
{"level":"info","ts":"2026-10-19T12:58:49+02:00","msg":"Found hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:58:49+02:00","msg":"Setting client finalizer for hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:58:49+02:00","msg":"Marking cleanup of cloud resources for hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:58:49+02:00","msg":"Updated hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T12:58:49+02:00","msg":"Deleting hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T13:03:53+02:00","msg":"Destroying infrastructure","infraID":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T13:04:03+02:00","msg":"Revoked security group ingress permissions","group":"sg-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:03+02:00","msg":"Revoked security group egress permissions","group":"sg-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:04+02:00","msg":"Deleted VPC endpoints","IDs":"vpce-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:05+02:00","msg":"Deleted private hosted zone","id":"Z00000000000000000000","name":"image-mirroring-beaa1f2bd2.hypershift.example.com."}
{"level":"info","ts":"2026-10-19T13:04:05+02:00","msg":"Deleted private hosted zone","id":"Z00000000000000000000","name":"image-mirroring-beaa1f2bd2.hypershift.local."}
{"level":"info","ts":"2026-10-19T13:04:05+02:00","msg":"Deleted route from route table","table":"rtb-0000000000000000","destination":"0.0.0.0/0"}
{"level":"info","ts":"2026-10-19T13:04:06+02:00","msg":"Removed route table association","table":"rtb-0000000000000000","association":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:06+02:00","msg":"Deleted route from route table","table":"rtb-0000000000000000","destination":"0.0.0.0/0"}
{"level":"info","ts":"2026-10-19T13:04:06+02:00","msg":"Removed route table association","table":"rtb-0000000000000000","association":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:07+02:00","msg":"Deleted route table","table":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:07+02:00","msg":"Deleted route table","table":"rtb-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:07+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: edcb6912-daa5-4bc8-9232-2985e9208aba, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., deleting NAT gateway nat-0000000000000000]"}
{"level":"info","ts":"2026-10-19T13:04:16+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: 32ebfafc-843f-4cdd-8861-863e417807b6, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., NAT gateway nat-0000000000000000 still deleting]"}
{"level":"info","ts":"2026-10-19T13:04:26+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: 7f4daf60-5eb6-4fa3-9273-958497869668, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., NAT gateway nat-0000000000000000 still deleting]"}
{"level":"info","ts":"2026-10-19T13:04:35+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: ad0e5edd-df97-409b-9ed3-bf96d1de0790, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., NAT gateway nat-0000000000000000 still deleting]"}
{"level":"info","ts":"2026-10-19T13:04:44+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: 939d9935-2ed2-4bed-bce2-5b917e5910d3, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., NAT gateway nat-0000000000000000 still deleting]"}
{"level":"info","ts":"2026-10-19T13:04:54+02:00","msg":"Deleted subnet","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:55+02:00","msg":"Deleted subnet","id":"subnet-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:55+02:00","msg":"WARNING: error during destroy, will retry","error":"[operation error EC2: DetachInternetGateway, https response error StatusCode: 400, RequestID: ae290f43-6aaa-405f-a9f0-4876c290f1bd, api error DependencyViolation: Network vpc-0000000000000000 has some mapped public address(es). Please unmap those public address(es) before detaching the gateway., failed to delete vpc with id vpc-0000000000000000: operation error EC2: DeleteVpc, https response error StatusCode: 400, RequestID: a984e9fe-bf95-4fc0-bad2-0188cb8da82c, api error DependencyViolation: The vpc 'vpc-0000000000000000' has dependencies and cannot be deleted.]"}
{"level":"info","ts":"2026-10-19T13:04:56+02:00","msg":"Detached internet gateway from VPC","gateway id":"igw-0000000000000000","vpc":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:04:57+02:00","msg":"Deleted internet gateway","id":"igw-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:05:05+02:00","msg":"Deleted VPC","id":"vpc-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:05:06+02:00","msg":"Deleted EIP","id":"eipalloc-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:05:06+02:00","msg":"Deleted DHCP options","id":"dopt-0000000000000000"}
{"level":"info","ts":"2026-10-19T13:05:06+02:00","msg":"Destroying IAM","infraID":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T13:05:07+02:00","msg":"Deleted OIDC provider","providerARN":"arn:aws:iam::123456789012:oidc-provider/oidc-bucket.s3.us-east-1.amazonaws.com/image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T13:05:07+02:00","msg":"Role already deleted!","role":"image-mirroring-beaa1f2bd2-shared-role"}
{"level":"info","ts":"2026-10-19T13:05:08+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-openshift-ingress","policy":"image-mirroring-beaa1f2bd2-openshift-ingress"}
{"level":"info","ts":"2026-10-19T13:05:08+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-openshift-ingress"}
{"level":"info","ts":"2026-10-19T13:05:09+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-openshift-image-registry","policy":"image-mirroring-beaa1f2bd2-openshift-image-registry"}
{"level":"info","ts":"2026-10-19T13:05:09+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-openshift-image-registry"}
{"level":"info","ts":"2026-10-19T13:05:10+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-aws-ebs-csi-driver-controller","policy":"image-mirroring-beaa1f2bd2-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-19T13:05:10+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-aws-ebs-csi-driver-controller"}
{"level":"info","ts":"2026-10-19T13:05:11+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-cloud-controller","policy":"image-mirroring-beaa1f2bd2-cloud-controller"}
{"level":"info","ts":"2026-10-19T13:05:11+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-cloud-controller"}
{"level":"info","ts":"2026-10-19T13:05:12+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-node-pool","policy":"image-mirroring-beaa1f2bd2-node-pool"}
{"level":"info","ts":"2026-10-19T13:05:12+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-node-pool"}
{"level":"info","ts":"2026-10-19T13:05:12+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-control-plane-operator","policy":"image-mirroring-beaa1f2bd2-control-plane-operator"}
{"level":"info","ts":"2026-10-19T13:05:13+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-control-plane-operator"}
{"level":"info","ts":"2026-10-19T13:05:13+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-cloud-network-config-controller","policy":"image-mirroring-beaa1f2bd2-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-19T13:05:14+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-cloud-network-config-controller"}
{"level":"info","ts":"2026-10-19T13:05:14+02:00","msg":"Role already deleted!","role":"image-mirroring-beaa1f2bd2-kms-provider"}
{"level":"info","ts":"2026-10-19T13:05:14+02:00","msg":"Role already deleted!","role":"image-mirroring-beaa1f2bd2-karpenter"}
{"level":"info","ts":"2026-10-19T13:05:14+02:00","msg":"Removed role from instance profile","profile":"image-mirroring-beaa1f2bd2-worker","role":"image-mirroring-beaa1f2bd2-worker-role"}
{"level":"info","ts":"2026-10-19T13:05:14+02:00","msg":"Deleted instance profile","profile":"image-mirroring-beaa1f2bd2-worker"}
{"level":"info","ts":"2026-10-19T13:05:15+02:00","msg":"Deleted role policy","role":"image-mirroring-beaa1f2bd2-worker-role","policy":"image-mirroring-beaa1f2bd2-worker-policy"}
{"level":"info","ts":"2026-10-19T13:05:15+02:00","msg":"Deleted role","role":"image-mirroring-beaa1f2bd2-worker-role"}
{"level":"info","ts":"2026-10-19T13:05:15+02:00","msg":"Deleting Secrets","namespace":"clusters"}
{"level":"info","ts":"2026-10-19T13:05:16+02:00","msg":"Deleted CLI generated secrets"}
{"level":"info","ts":"2026-10-19T13:05:16+02:00","msg":"Finalized hosted cluster","namespace":"clusters","name":"image-mirroring-beaa1f2bd2"}
{"level":"info","ts":"2026-10-19T13:05:16+02:00","msg":"Successfully destroyed cluster and infrastructure","namespace":"clusters","name":"image-mirroring-beaa1f2bd2","infraID":"image-mirroring-beaa1f2bd2"}
2026/10/19 13:05:16 Finished destroying cluster: image-mirroring-beaa1f2bd2
2026/10/19 13:05:16 All clusters destroyed successfully
exit=0
Mon Oct 19 13:05:16 CEST 2026
$ k -n "$HC_NS" get secret,cm
NAME                              TYPE                      DATA   AGE
secret/builder-dockercfg-8zgmh    kubernetes.io/dockercfg   1      45m
secret/default-dockercfg-q4j8v    kubernetes.io/dockercfg   1      45m
secret/deployer-dockercfg-chlsf   kubernetes.io/dockercfg   1      45m

NAME                                 DATA   AGE
configmap/kube-root-ca.crt           1      45m
configmap/openshift-service-ca.crt   1      45m
configmap/user-ca-bundle             1      45m
$ k delete ns "$HC_NS"
namespace "clusters" deleted
$ k delete ns "$KC_NS" "$NS" --wait=true --timeout=10m
namespace "keycloak" deleted
namespace "test-mirror-registry" deleted
$ .work/cntrlplane-3927/propagation/check.sh clean
PASS  no HostedCluster/NodePool in clusters
PASS  namespace clusters-image-mirroring-beaa1f2bd2 gone
PASS  namespace test-mirror-registry gone
PASS  namespace keycloak gone
PASS  no PV bound to test-mirror-registry
PASS  no VPC tagged for image-mirroring-beaa1f2bd2
PASS  no live instance tagged for image-mirroring-beaa1f2bd2
check clean: 0 failure(s)
$ rm -f "$GUEST_KUBECONFIG"
```

### Step 6b — additional leftover checks (after review N6, all empty = nothing left)

```text
$ e2e aws s3 ls s3://oidc-bucket/image-mirroring-beaa1f2bd2/
$ e2e aws route53 list-resource-record-sets --hosted-zone-id Z00000000000000000000 --query "ResourceRecordSets[?contains(Name,'image-mirroring-beaa1f2bd2')].Name" --output text
$ e2e aws elb describe-load-balancers --region us-east-1 --query "LoadBalancerDescriptions[?starts_with(LoadBalancerName,'kas-lb')].LoadBalancerName" --output text
$ e2e aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?starts_with(LoadBalancerName,'kas-lb')].LoadBalancerName" --output text
$
```
