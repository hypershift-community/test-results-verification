# Day 1 verification index — OCPSTRAT-2653 / CNTRLPLANE-4574

Verification status for the Day 1 deterministic LoadBalancer IP feature, tracked
against [`plans/ocpstrat-2653.md`](../../plans/ocpstrat-2653.md). Each row links to
the pull request that carries the evidence — in every case the `/verified`
comment on that PR plus its CI results. Per-PR reports in this directory hold the
detail where they exist.

This index is not a report: it records no verdict of its own and carries no
report metadata.

## Implementation pull requests

| PR | Scope | Report | Verdict |
|---|---|---|---|
| [#9898](https://github.com/openshift/hypershift/pull/9898) | `DeterministicLBIP` gate, `TechPreviewNoUpgrade` only | [9898.md](9898.md) | Pass |
| [#9913](https://github.com/openshift/hypershift/pull/9913) | API fields, deepcopy, gated CRDs, CEL immutability | [9913.md](9913.md) | Pass |
| [#10043](https://github.com/openshift/hypershift/pull/10043) | `KubeletHAProxyRouting` gate | [10043.md](10043.md) | Pass |
| [#9988](https://github.com/openshift/hypershift/pull/9988) | kubelet through HAProxy on public HCPs | [9988.md](9988.md) | Pass |
| [#10133](https://github.com/openshift/hypershift/pull/10133) | CPO passthrough to the KAS Services | [10133.md](10133.md) | Pass |
| [#10142](https://github.com/openshift/hypershift/pull/10142) | `serviceAnnotations` allowlist and size bounds | [10142.md](10142.md) | Pass, with the OCP 4.17/4.18 caveat below |
| [#10207](https://github.com/openshift/hypershift/pull/10207) | User-facing documentation | [10207.md](10207.md) | Pass |
| [#10237](https://github.com/openshift/hypershift/pull/10237) | CLI flags, envtest suite, e2e v2 test | [10237.md](10237.md) | Pass |
| [#10146](https://github.com/openshift/hypershift/pull/10146) | Cleanup of the orphaned private KAS Service | none | No evidence — withdrawn by its author |

Notes:

- #10142 records a compatibility limit: on management clusters built from
  Kubernetes 1.30.3 or 1.31.2 (OpenShift 4.17/4.18), a HostedCluster created
  before the schema update with a now-disallowed annotation can fail later status
  requests even when the annotation is unchanged. New-resource admission passed
  across the whole matrix.
- #10237 was marked verified *later*. The end-to-end layer runs through
  [openshift/release#88475](https://github.com/openshift/release/pull/88475),
  which adds an optional presubmit. Its rehearsal
  ([job](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_release/88475/rehearse-88475-pull-ci-openshift-hypershift-main-e2e-v2-aws-deterministic-lb/2123000912807989248))
  ran the deterministic-lb spec green. The job remains optional and the spec is
  `Informing`, so the green run is evidence, not a gate.
- #10043 and #10237 merged with `e2e-kubevirt-aws-ovn-reduced` red; #10237 also
  shows `e2e-from-pr-aws` red. Both merged with tide green, so neither job was
  required.

## Test case coverage

| Test case | Status | Evidence |
|---|---|---|
| TC-001 Fixed IP via Service Annotation | Verified (automated, AWS EIP) | #10133 proved reserved-address selection on AWS. The [AWS lane rehearsal](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_release/88475/rehearse-88475-pull-ci-openshift-hypershift-main-e2e-v2-aws-deterministic-lb/2123000912807989248) reserved an EIP, passed it to the HostedCluster, and the KAS NLB resolved to that address. The MetalLB case remains pending the Agent/MetalLB lane |
| TC-002 `loadBalancerClass` passthrough (envtest) | Partial | The envtest reconciliation suite asserts the field on both KAS Services; no live provisioning run. AWS cannot exercise it: the cloud provider ignores classed Services and the KAS Service stays `Pending` |
| TC-003 Preservation across reconciliation | Verified (automated) | [Same rehearsal](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_release/88475/rehearse-88475-pull-ci-openshift-hypershift-main-e2e-v2-aws-deterministic-lb/2123000912807989248): the spec removed the control-plane component label, waited for the operator to restore it, and held UID, annotations, class and ingress stable for 30 s. The plan's 5-minute window is deferred to the next lane PR |
| TC-004 Legacy cluster without annotations | Covered implicitly | The `e2e-v2-aws` presubmit runs gate-on (`TECH_PREVIEW_NO_UPGRADE=true` plus `--feature-set=TechPreviewNoUpgrade`) with no annotations; the full AWS suite runs on that cluster. No dedicated "no annotations" assertion |
| TC-016 Kubelet through HAProxy (prerequisite) | Partial | #9988 verified the mechanism on AWS/NLB: both kubelets on the node-local HAProxy, plus restart, resolver-failure and partition tests. TC-016 requires an Agent cluster with MetalLB and a deterministic address, which has not run |
| TC-019 Allowlist and size bounds | Verified (automated) | YAML CEL suite: 48 admission cases including empty map, eleven entries and a value over 253 characters |
| TC-020 `loadBalancerClass` immutability | Verified (automated) | YAML CEL suite: changing the value is rejected |
| TC-021 `serviceAnnotations` immutability | Verified (automated) | YAML CEL suite: changing, adding or removing a key is rejected |
| TC-022 `loadBalancer` block anti-removal | Partial | The suite rejects a strategy-type change and a service-entry addition. Removing the whole `loadBalancer` block has no dedicated case; the whole-list equality rule covers it but nothing exercises it |
| TC-023 Optional field zero-value protection | Partial | Covered by whole-list equality; no dedicated null or absent case |
| TC-024 `loadBalancerClass` format | Verified (automated) | YAML CEL suite, including the 63/64-character boundaries |
| TC-028 Cilium LB IPAM | Partial | The allowlisted key is admitted; no Cilium periodic lane |
| TC-039 IBMCloud carve-out | Verified (automated) | YAML CEL suite IBMCloud cases, added with #10237 |
| TC-040 CPO-managed annotation precedence | Partial | #10133 verified the AWS skip guard, not the ordering: reconciliation skips the user-supplied `aws-load-balancer-type` and seeds `nlb` separately on create, so no user value is ever applied and then overwritten. The allowlist also makes the collision unreachable through admission |
| TC-042 Azure service routing | Partial | Unit coverage only; no Azure run |
| TC-017 Private cluster unaffected | Not separately exercised | Day 1 scope decision: the private and public-and-private AWS paths are covered by the public lane plus the envtest suite |
| TC-018 Cloud provider unaffected | Covered implicitly | Same gate-on `public` cluster as TC-004: the KAS Service gets its NLB and the NodePools reach `Ready` |

## Platforms affected

The feature applies to any HostedCluster whose APIServer service publishing
strategy is `LoadBalancer`, regardless of `spec.platform.type`. The platform
only changes the LB implementation and the annotation prefix.

| Platform / LB implementation | Affected | Day 1 coverage |
|---|---|---|
| AWS (NLB + EIP) | Yes | Live: TC-001, TC-003; non-regression TC-004/TC-018 |
| Azure (Azure LB) | Yes | TC-042 (unit); no live lane |
| Agent / bare metal (MetalLB) | Yes | Next: TC-001 (MetalLB), TC-002 |
| KubeVirt (management-cluster LB) | Yes | Last; no lane |
| IBMCloud | Carve-out only | TC-039 (CEL) |
| Agent / bare metal (Cilium LB IPAM) | Yes (LB implementation) | TC-028; periodic variant, not implemented |
| GKE, F5 and OpenStack prefixes | Allowlisted | No Day 1 lane |
| Private endpoint (internal LB) | Yes, private Service only | Covered by the public lane; envtest covers the private Service wiring; no separate case |
| APIServer strategy Route or NodePort | No | Non-regression TC-004/TC-018 |

## Outstanding

1. **End-to-end lane.** [openshift/release#88475](https://github.com/openshift/release/pull/88475)
   is open. It adds an optional, non-default presubmit for the AWS nested lane.
   The lane's rehearsal ran the deterministic-lb spec green; promote it to a
   full pass once the release PR merges and the job runs from the merged
   configuration. The Agent/MetalLB presubmit named in the plan does not exist
   yet.
2. **TC-040 has no test for the ordering it describes.** The #10133 run shows
   the AWS skip guard, not precedence: the user-supplied key is never applied and
   `nlb` is seeded separately on create, so nothing demonstrates CPO overwriting
   an applied user value. The allowlist makes that collision unreachable through
   admission, so only a unit case that injects it into reconciliation can cover
   the ordering.
3. **TC-023 has no dedicated null/absent case.** It relies on the whole-list
   equality rule.
4. **Provider runs.** AWS now has a live lane for TC-001 and TC-003. MetalLB/Agent
   (TC-001 on MetalLB and TC-002), Cilium (TC-028) and Azure (TC-042) have no live
   or periodic execution.
5. **Gate-on non-regression.** TC-004 and TC-018 are covered implicitly by the
   main AWS lane. TC-017 is not separately exercised: the private and
   public-and-private AWS paths are covered by that lane plus the envtest suite
   as a Day 1 scope decision.
6. **Orphaned private KAS Service.** OpenShift transition from Private to pure
   Public leaves the private Service holding the requested address. #10146 was
   withdrawn, so nothing verifies or fixes it, and no test case covers it.
7. **Day 2 cases are out of scope here.** TC-005 to TC-015, TC-025 to TC-027,
   TC-029 to TC-034, TC-035 to TC-038 and TC-041 belong to CNTRLPLANE-4796 and
   have no implementation to verify. TC-016 is recorded as partial in the #9988
   report: the mechanism is verified on AWS, the Agent/MetalLB acceptance case is
   not. TC-018 is covered implicitly by the main AWS lane; TC-017 is not
   separately exercised.
