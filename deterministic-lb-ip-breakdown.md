# Deterministic LB IP Management — Epic Breakdown & Edge Case Analysis

**Date**: 2026-10-20
**Source**: Empirical code trace of `~/workspace/hypershift` (main branch)
**Enhancement PR**: https://github.com/openshift/enhancements/pull/2117
**Parent STRAT**: OCPSTRAT-2653

---

## Epic 1: Day 1 — Deterministic LB IP Assignment (OCP 5.1 TP)

Users specify `loadBalancerClass` and `serviceAnnotations` on the HostedCluster
at creation time. HyperShift passes them to the KAS Service. The LB controller
assigns the requested IP. No sidecar, no zero-rollout — if the IP changes
post-creation, existing rollout chain handles it (worker rollout, same as today).

---

### Story 1.1: FeatureGate — Register DeterministicLBIP

**What**: Register the feature gate and wire it to API field visibility.

**Where**:
- `hypershift-operator/featuregate/feature.go:64` — already registered as TechPreviewNoUpgrade
- API fields need `+openshift:enable:FeatureGate=DeterministicLBIP` markers
- CEL rules need `FeatureGateAwareXValidation` where applicable

**Acceptance**:
- CRD includes new fields when gate enabled
- CRD excludes new fields when gate disabled
- CEL rules tied to the gate only fire when enabled

---

### Story 1.2: API + CEL — New fields, allowlist, immutability migration

Single PR covering all API-level changes. These are tightly coupled — you
can't ship the fields without the validation, and you can't test the CEL
without the fields.

#### A) New fields on LoadBalancerPublishingStrategy

**Where**: `api/hypershift/v1beta1/hostedcluster_types.go:1125-1134`
Current struct has only `Hostname`.

Add:
- `LoadBalancerClass *string` — optional, pointer for omitempty + immutability
- `ServiceAnnotations map[string]string` — optional, mutable
- Both gated behind `+openshift:enable:FeatureGate=DeterministicLBIP`

#### B) Annotation allowlist (CEL on ServiceAnnotations)

Only annotation keys matching known provider prefixes accepted:

| Prefix | Provider |
|--------|----------|
| `metallb.io/` | MetalLB v0.13+ |
| `metallb.universe.tf/` | MetalLB legacy |
| `service.beta.kubernetes.io/aws-load-balancer-eip` | AWS NLB EIP |
| `service.beta.kubernetes.io/aws-load-balancer-subnet` | AWS NLB subnet |
| `service.beta.kubernetes.io/aws-load-balancer-target-group` | AWS NLB TG |
| `service.beta.kubernetes.io/azure-load-balancer-ipv` | Azure LB |
| `service.beta.kubernetes.io/azure-load-balancer-resource-group` | Azure LB RG |
| `networking.gke.io/` | GCP |
| `cis.f5.com/` | F5 BIG-IP CIS |
| `lbipam.cilium.io/` | Cilium LB IPAM |
| `loadbalancer.openstack.org/` | OpenStack Octavia |

**CPO-managed annotations to BLOCK** (or document CPO precedence):
- `service.beta.kubernetes.io/aws-load-balancer-type` — CPO sets `nlb` on CREATE
- `service.beta.kubernetes.io/aws-load-balancer-cross-zone-*` — CPO sets on PublicAndPrivate AWS
- `hypershift.openshift.io/external-dns-hostname` — CPO sets from `strategy.LoadBalancer.Hostname`

#### C) spec.services immutability migration (atomic → map)

**Current rule** (line 543):
```
self.platform.type != "IBMCloud" ? self.services == oldSelf.services : true
```

**IBMCloud carve-out** — CRITICAL: per-field rules at nested struct level can't
access `self.platform.type` (wrong CEL scope). The IBMCloud guard MUST stay at
`HostedClusterSpec` level alongside per-field rules.

Changes:
1. `+listType=atomic` → `+listType=map`, `+listMapKey=service`
2. `MaxItems=6` already set. 6 ServiceType values confirmed.
3. List-level rules: no adding entries, no removing entries
4. Per-field immutability on each field that must stay immutable:
   - `service`, `type`, `nodePort`, `route`: `self == oldSelf`
   - `hostname`, `loadBalancerClass`: immutable once set (parent-scope rules to prevent set→unset→set bypass)
5. `serviceAnnotations`: NO immutability rule (mutable)

#### D) Immutability rules for optional pointer fields

On `LoadBalancerPublishingStrategy` (parent scope, not on fields themselves):
```
!has(oldSelf.hostname) || (has(self.hostname) && self.hostname == oldSelf.hostname)
!has(oldSelf.loadBalancerClass) || (has(self.loadBalancerClass) && self.loadBalancerClass == oldSelf.loadBalancerClass)
```

Parent scope prevents the set→unset→set-different bypass that CEL allows on
optional/pointer fields.

**Edge cases for this story**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E1 | IBMCloud CEL scope | Per-field rules can't access `platform.type` | Keep spec-level IBMCloud guard |
| E2 | listType migration — duplicate service keys | Existing HCs with duplicates become invalid on ANY update | Pre-upgrade validation script |
| E3 | Validation ratcheting excluded | K8s excludes `x-kubernetes-list-type` from ratcheting | Pre-upgrade validation |
| E4 | SSA ownership change | atomic→map changes SSA ownership model | Low risk (HyperShift uses CreateOrUpdate, not SSA) |
| E5 | No precedent in codebase | No existing atomic→map migration in HyperShift | Extra testing, E2E upgrade test |
| E6 | CEL cost budget | Per-field rules × maxItems must stay under 10M | `MaxItems=6` already set, cost ≈30 |

**Tests**:
- Allowed prefix accepted, unknown prefix rejected
- CPO-managed annotation keys blocked
- All existing fields immutable after migration
- `serviceAnnotations` mutable after migration
- Cannot add/remove service entries
- IBMCloud carve-out still works
- set→unset→set-different blocked for hostname and loadBalancerClass
- E2E upgrade: old CRD (atomic) → new CRD (map), HC valid, reconciliation continues

---

### Story 1.3: CPO — Annotation passthrough and loadBalancerClass

**What**: Modify `kas.ReconcileService()` to apply user annotations and set
`loadBalancerClass` on the KAS Service.

**Where**:
- `control-plane-operator/controllers/hostedcontrolplane/kas/service.go:34-119`
- Only caller: `infra/infra.go:231`

**Details**:
- Read `serviceAnnotations` from APIServer's `LoadBalancerPublishingStrategy`
- Apply each key-value as `svc.Annotations[key] = value` (per-key write)
- Set `svc.Spec.LoadBalancerClass` from `loadBalancerClass` (only on create — K8s immutability)
- Apply user annotations AFTER CPO's own (CPO takes precedence), or block via CEL

**Annotation deletion**: When user removes a key from `serviceAnnotations`, CPO
must remove it from the Service. On reconcile, diff allowlist-matching Service
annotations against current `serviceAnnotations`. Delete orphans.

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E7 | Private cluster serviceAnnotations | `ReconcilePrivateService()` does NOT yet receive `serviceAnnotations`. | Day 1 covers public AND private. Wire `serviceAnnotations` to both `ReconcileService()` and `ReconcilePrivateService()` in Story 1.3. |
| E8 | AWS annotation conflicts | CPO hardcodes `aws-load-balancer-type: nlb`, cross-zone annotations. User values silently overwritten. | Block CPO-managed keys in CEL (Story 1.2) or document precedence. |
| E9 | Annotation deletion tracking | Per-key write only adds. Removed keys persist on Service. | Diff current Service annotations (allowlist-matching) against spec. Delete orphans. |
| E10 | loadBalancerClass on existing Service | K8s `loadBalancerClass` immutable on Services. Can't add to existing HC. | Document: requires new HC. Set only on Service creation. |
| E11 | Azure separate service (port 7443) | Azure public creates `KubeAPIServerServiceAzureLB`. Annotations go there. | Verify correct Service object receives annotations. |
| E12 | Dual-stack Service status | `ReconcileServiceStatus()` reads `Ingress[0]` — primary IP family only. | Document: deterministic IP targets primary family. |
| E13 | Concurrent annotation updates | User changes before LB finishes processing. | CPO always writes latest. No race — LB sees latest annotations. |
| E14 | MetalLB status annotations | MetalLB writes `ip-allocated-from-pool` etc. | Per-key write preserves them. Verify in tests. |

**Tests**:
- Annotations from `serviceAnnotations` present on KAS Service
- `loadBalancerClass` set on KAS Service
- Existing CPO annotations preserved alongside user annotations
- Annotation removal works (key removed from spec → removed from Service)
- Nil `serviceAnnotations` → no user annotations, existing preserved
- Nil `loadBalancerClass` → `svc.Spec.LoadBalancerClass` not set
- MetalLB status annotations survive reconciliation

---

### Story 1.4: Testing — Day 1 unit + E2E

**Unit tests** (all in Story 1.2 and 1.3 test lists above, consolidated here):
- CEL allowlist validation (accept/reject)
- CEL immutability migration (all fields immutable, serviceAnnotations mutable)
- IBMCloud carve-out preserved
- Optional field immutability (set→unset→set blocked)
- ReconcileService annotation passthrough
- ReconcileService loadBalancerClass
- Annotation deletion/orphan cleanup
- CRD generation with/without feature gate

**E2E tests**:
- Day 1 MetalLB: create HC with `serviceAnnotations`, verify annotations on KAS
  Service, verify MetalLB assigns expected IP, verify cluster functional
- loadBalancerClass: create HC with `loadBalancerClass`, verify set on Service,
  correct LB controller processes it
- Immutability regression: existing fields cannot be changed after CRD upgrade
- Upgrade: create HC with old CRD (atomic list), upgrade CRD (map list), verify
  HC valid, reconciliation continues

**Dependencies**: MetalLB availability in CI (requires CI team coordination)

---

### Story 1.5: Documentation — Day 1

**What**: User-facing docs in openshift-docs for Day 1 capabilities.

**Content**:
- How to configure `serviceAnnotations` per provider (MetalLB, AWS, Azure, GCP, F5, Cilium, OpenStack)
- How to use `loadBalancerClass` for multi-controller management clusters
- Allowlist: which annotation prefixes are accepted, how to request a new one
- Limitations: public KAS Service only (no private LB), primary IP family only (dual-stack),
  `loadBalancerClass` requires new HC (cannot add to existing)
- Troubleshooting: Service stays Pending, annotation format errors
- Support procedures: `oc get svc`, check conditions

---

## Epic 2: Day 2 — Zero-Rollout IP Migration via Sidecar (Future Release)

Change the kube-apiserver LB IP on a running cluster without worker rollout. A
sidecar in the HAProxy static pod polls `/kas-ip` on the ignition server and
hot-reloads HAProxy when the IP changes. Feature gate graduates from TP to GA.

---

### Story 2.1: Prerequisite — Kubelet → HAProxy routing (bare-metal public)

**What**: Make kubelet connect to KAS through HAProxy (`172.20.0.1:6443`) instead
of directly to the LB IP.

**Where**:
- `control-plane-operator/controllers/hostedcontrolplane/v2/kas/kubeconfig.go:169-185`
- `adaptBootstrapKubeconfigSecret()` — currently uses `externalURL(infraStatus)` for public clusters

**Scope**: Agent + KubeVirt platforms with Public endpoint access ONLY.
AWS/Azure/GCP use hostname-based kubeconfigs (DNS handles IP changes).

**Details**:
- `172.20.0.1` already in KAS cert SANs (`support/pki/kas.go:39`, `support/config/constants.go:32`)
- IPv6: use `fd00::1` (`DefaultAdvertiseIPv6Address`)
- Private clusters already go through HAProxy — no change
- This is INDEPENDENT of the feature gate (infrastructural improvement)

**Impact**: HAProxy becomes kubelet connectivity dependency. Accepted tradeoff
(HAProxy is a static pod, runs as long as kubelet runs).

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E15 | Platform scope ambiguity | Cloud platforms don't need this change | Scope to Agent + KubeVirt only |
| E16 | Shared ingress clusters | haproxy.go:160-176 has separate path | Verify shared ingress unaffected |

**Tests**:
- Unit: Agent + Public → kubeconfig uses `172.20.0.1`
- Unit: Agent + Private → unchanged (internal URL)
- Unit: AWS + Public → unchanged (LB hostname)
- E2E: Agent public cluster, kubelet connects via `172.20.0.1`

---

### Story 2.2: Ignition server `/kas-ip` endpoint

**What**: New unauthenticated endpoint returning current KAS IP from
`HCP.Status.ControlPlaneEndpoint.Host`.

**Where**:
- `ignition-server/cmd/start.go` — add `mux.HandleFunc("/kas-ip", ...)`
- Auth is inline in `/ignition` handler, NOT middleware. `/healthz` exists without auth (line 313).
- `mgr.GetClient()` already reads HCP (`local_ignitionprovider.go:837-845`)

**~10 lines of code.**

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E17 | HCP not found | 500 error, sidecar retries | Return 503, sidecar retries |
| E18 | ControlPlaneEndpoint empty | LB hasn't assigned IP yet | Return 503, sidecar retries |
| E19 | IPv6 response format | Sidecar needs raw IP | Return raw string, sidecar handles brackets |
| E20 | Private ignition Route | Workers need internal Route to poll | Workers used it to boot — verify reachable post-boot |
| E21 | Security | KAS IP discoverable via DNS | No auth needed, same as /healthz |

**Tests**:
- Unit: correct IP from HCP status, no auth, handles missing HCP (503), handles empty endpoint (503)
- E2E: verify workers can reach `/kas-ip` via ignition Route

---

### Story 2.3: HAProxy sidecar + init container + hash stability

Single story because these are inseparable — the sidecar without hash stability
triggers rollouts, and hash stability without the sidecar leaves HAProxy with
`0.0.0.0`.

#### A) HAProxy static pod modification

**Where**: `haproxy.go:411` — `generateHAProxyStaticPod()`
Current: single container, single hostPath, NO `-W`, NO `shareProcessNamespace`.

Changes (when feature gate enabled):
1. `-W` flag on HAProxy command (master-worker mode, SIGUSR2 = seamless reload)
2. `shareProcessNamespace: true` (sidecar signals HAProxy)
3. Three-volume design:
   - `config-template`: hostPath `/etc/kubernetes/apiserver-proxy-config` (READ-ONLY)
   - `config-runtime`: emptyDir (HAProxy reads from here)
   - `override`: emptyDir (current KAS IP)
4. Init container `kas-ip-init`: polls `/kas-ip`, writes IP to override, `sed` template → config-runtime
5. Sidecar `kas-ip-poller`: polls `/kas-ip` every 30s, on change → write + sed + SIGUSR2

#### B) Hash stability

**Where**: `haproxy.go:81-114` — `reconcileHAProxyIgnitionConfig()`

When gate enabled, skip reading kubeconfig and use placeholder `0.0.0.0` for
`ExternalAPIAddress`. Hash chain (confirmed):
```
haproxyRawConfig → parse() (config.go:320) → mcoRawConfig → Hash() (config.go:166-168)
```
Placeholder → haproxyRawConfig stable → hash stable → no rollout.

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E22 | SIGUSR2 without `-W` | Kills HAProxy | `-W` is mandatory |
| E23 | IPv6 in haproxy.cfg backend | `server controlplane 2001:db8::1:6443` invalid | Sidecar sed must detect IPv6 and bracket: `[2001:db8::1]:6443` |
| E24 | Init container ignition unreachable | Falls back to `0.0.0.0`, HAProxy unreachable | Exponential backoff retry before fallback. Sidecar retries after. |
| E25 | InPlace upgrade clears emptyDir | HAProxy loses runtime config | Init container re-polls `/kas-ip`, restores correct IP |
| E26 | Feature gate ON but no sidecar (pre-5.1 NP) | Template has `0.0.0.0`, no sidecar to fix | `ValidLoadBalancerIPConfiguration` condition blocks this (Story 2.4) |
| E27 | Scale-up after IP change | New node boots with stale placeholder | Init container gets current IP from `/kas-ip` before HAProxy starts |
| E28 | Sidecar resource overhead | Runs on every worker | Minimal: 8Mi memory, 5m CPU |
| E29 | HAProxy PID discovery | Sidecar needs HAProxy master PID for SIGUSR2 | `pidof haproxy` or parse `/proc/*/cmdline` with shareProcessNamespace |
| E30 | Mixed NP versions | Per-NP config generation needed | Feature gate check per-NodePool, not global |

**Tests**:
- Unit: manifest includes init, sidecar, 3 volumes, `-W`, shareProcessNamespace (gate ON)
- Unit: manifest unchanged (gate OFF)
- Unit: hash stable when kubeconfig IP changes (gate ON)
- Unit: hash changes when kubeconfig IP changes (gate OFF)
- E2E: sidecar detects IP change, HAProxy reloads, no rollout triggered
- E2E: scale-up after IP change, new node joins with correct IP
- E2E: InPlace upgrade, HAProxy gets correct IP after restart

---

### Story 2.4: ValidLoadBalancerIPConfiguration condition

**What**: Cross-resource condition on HostedCluster validating all NodePools
support the sidecar.

**Where**:
- HC controller — follow `syncKVLiveMigratableCondition()` pattern (hostedcluster_controller.go:5426-5467)
- NP controller — set `ValidLoadBalancerIPSupport` per NodePool based on release image version

**Pattern**:
1. `listNodePools()` (line 3813)
2. `FindNodePoolStatusCondition()` (line 5968) per NP
3. Collect non-compliant NPs
4. Set HC condition: True (all support) / False (listing names)

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E31 | NP condition absent (not reconciled) | Unknown support status | Treat absent as unsupported (conservative) |
| E32 | NP with 0 replicas | Could be scaled up later | Still check |
| E33 | NP being deleted | Irrelevant | Skip terminating NPs |
| E34 | Gate disabled | Condition irrelevant | Don't set condition |
| E35 | No serviceAnnotations configured | Feature not in use | Don't set condition |

**Tests**:
- Unit: True when all NPs supported, False listing non-compliant
- Unit: absent condition = unsupported
- Unit: not set when gate disabled or no serviceAnnotations

---

### Story 2.5: Day 2 end-to-end flow

**What**: Integration of Stories 2.1-2.4. Full Day 2 flow:

```
1. User changes serviceAnnotations on HC
2. HO mirrors to HCP (hostedcluster_controller.go:3005)
3. CPO applies new annotations to KAS Service
4. LB assigns new IP → Service.Status updated
5. CPO reconcileInfrastructureStatus() reads new IP
6. CPO sets HCP.Status.ControlPlaneEndpoint = new IP
7. CPO regenerates KAS cert with new IP SAN (automatic via ValidateKeyPair)
8. KAS restarts with new cert
9. GET /kas-ip returns new IP
10. Sidecar detects → write → sed → SIGUSR2 → HAProxy reloads
11. Kubelet (172.20.0.1) → HAProxy → new IP
```

**Edge cases**:

| # | Edge Case | Impact | Mitigation |
|---|-----------|--------|------------|
| E36 | Brief connectivity window (steps 4-10) | ~30s, kubelet retries | Accepted tradeoff. Document. |
| E37 | Cert-to-sidecar race (steps 7-10) | Sidecar picks up IP before KAS has new cert. Brief TLS errors. | Kubelet retries. Document. |
| E38 | OAuth cascade | OAuth reads ControlPlaneEndpoint. Config change → restart. | Automatic. Brief OAuth unavailability. |
| E39 | CNO/Karpenter cascade | Get new API address from endpoint. Restart. | Automatic. |
| E40 | CAPI cluster endpoint | Platform CAPI clusters updated. CAPI controllers react. | Automatic. |
| E41 | Guest Infrastructure CR | `apiServerURL` updated. Informational only — workers use HAProxy. | No functional impact. |
| E42 | MetalLB partial processing | User changes annotations while LB processes previous. | CPO writes latest. MetalLB handles gracefully. |

**Tests**: Covered by E2E in Stories 2.3 and this story's integration test.

---

### Story 2.6: FeatureGate graduation — TP → GA

**What**: Graduate `DeterministicLBIP` from TechPreviewNoUpgrade to GA.
Remove feature gate. Fields become always-visible in CRD.

**Where**: `hypershift-operator/featuregate/feature.go:64`

**Prerequisites** (all must pass before graduation):
- Day 2 zero-rollout verified in E2E
- ValidLoadBalancerIPConfiguration condition working
- Load testing with multiple concurrent HCs
- F5 one-time validation completed
- All E2E tests passing in CI
- User-facing docs complete

**Tests**:
- Fields visible without any gate configuration
- All Day 1 + Day 2 tests pass without gate

---

### Story 2.7: Testing — Day 2 unit + E2E

**Unit tests** (consolidated from all Day 2 stories):
- `/kas-ip` endpoint: correct IP, no auth, handles missing HCP, handles empty endpoint
- HAProxy manifest: init, sidecar, volumes, `-W`, shareProcessNamespace (gate ON/OFF)
- Hash stability: hash unchanged on IP change (gate ON), hash changes (gate OFF)
- ValidLoadBalancerIPConfiguration: True/False/absent/gate-off logic
- Kubelet→HAProxy: kubeconfig uses `172.20.0.1` for Agent+Public

**E2E tests**:
- Day 2 MetalLB: change IP, verify sidecar reload, verify no rollout, verify connectivity
- Scale-up after IP change: new node joins with current IP
- InPlace upgrade: HAProxy gets correct IP after pod restart
- ValidLoadBalancerIPConfiguration: blocks Day 2 when pre-5.1 NP exists, transitions to True after upgrade
- Private ignition Route: sidecar can reach `/kas-ip` on private cluster

---

### Story 2.8: Documentation — Day 2

**What**: User-facing docs in openshift-docs for Day 2 capabilities.

**Content**:
- How to change kube-apiserver LB IP on a running cluster
- Prerequisites: all NodePools at 5.1+, ValidLoadBalancerIPConfiguration condition
- Expected behavior: brief connectivity window (~30s), kubelet retries
- Cascading effects: OAuth/CNO/Karpenter restart automatically
- Troubleshooting: ValidLoadBalancerIPConfiguration=False, ignition unreachable, cert errors
- Support procedures: check sidecar logs, verify `/kas-ip` endpoint, check conditions

---

## Edge Cases — Complete Inventory

### Blocking (must fix)

| # | Edge Case | Epic | Details |
|---|-----------|------|---------|
| E7 | Private cluster serviceAnnotations | 1 | Day 1 covers public AND private. Wire to both `ReconcileService()` and `ReconcilePrivateService()`. |
| E2 | IBMCloud CEL carve-out scope | 1 | Per-field rules can't access `platform.type`. Keep spec-level guard. |
| E23 | IPv6 haproxy.cfg backend | 2 | Backend `server` directive needs brackets for IPv6. Sidecar sed must handle. |
| E9 | Annotation deletion tracking | 1 | CPO must diff and remove orphaned annotations. |

### Important (should fix or document)

| # | Edge Case | Epic | Details |
|---|-----------|------|---------|
| E8 | AWS annotation conflicts | 1 | CPO hardcodes NLB type, cross-zone. Block in CEL or document precedence. |
| E37 | Cert-to-sidecar race | 2 | Brief TLS errors between cert update and sidecar pickup. Kubelet retries. |
| E24 | Init container ignition fallback | 2 | InPlace upgrade + ignition unreachable → `0.0.0.0`. Add exponential backoff. |
| E5 | No listType migration precedent | 1 | No atomic→map migration exists. Extra testing needed. |
| E10 | loadBalancerClass on existing Service | 1 | K8s immutable. Requires new HC. Document. |
| E38 | OAuth cascade | 2 | IP change → OAuth restart. Brief unavailability. Document. |
| E15 | Platform scope for kubelet→HAProxy | 2 | Scope to Agent + KubeVirt only. |
| E12 | Dual-stack Service status | 1 | `Ingress[0]` = primary family only. Document. |

### Minor (test coverage)

| # | Edge Case | Epic | Details |
|---|-----------|------|---------|
| E20 | Private ignition Route reachability | 2 | Verify sidecar reaches internal Route post-boot. |
| E13 | Concurrent annotation updates | 1 | CPO writes latest. No race. |
| E31 | ValidLoadBalancerIPConfiguration — absent NP condition | 2 | Treat as unsupported. |
| E11 | Azure separate service (port 7443) | 1 | Verify annotations on correct Azure service. |
| E16 | SharedIngress clusters | 2 | Verify sidecar works with shared ingress. |
| E41 | Guest Infrastructure CR update | 2 | Informational only. Verify no functional impact. |
| E4 | SSA ownership change | 1 | Low risk (CreateOrUpdate, not SSA). |
| E14 | MetalLB status annotations | 1 | Per-key write preserves them. Verify. |
| E32 | NP with 0 replicas | 2 | Still check in condition. |
| E30 | Mixed NP versions | 2 | Per-NP config generation, not global. |

---

## Enhancement Gaps Found

| # | Gap | Epic | Fix |
|---|-----|------|-----|
| G1 | Private cluster `serviceAnnotations` — EP doesn't mention private path | 1 | Add to Implementation Details: wire to both `ReconcileService()` and `ReconcilePrivateService()` |
| G2 | Annotation deletion semantics unspecified | 1 | Add paragraph in Implementation Details |
| G3 | CPO-managed annotation conflicts not mentioned | 1 | Add table in Risks section |
| G4 | `loadBalancerClass` on existing Services (K8s immutability) | 1 | Add to Upgrade section |
| G5 | Platform scope for kubelet→HAProxy not explicit | 2 | Clarify: Agent + KubeVirt only |
| G6 | Dual-stack behavior not mentioned | 1 | Document: primary IP family only |
| G7 | IBMCloud CEL scope constraint not addressed | 1 | Document: guard stays at HostedClusterSpec level |
