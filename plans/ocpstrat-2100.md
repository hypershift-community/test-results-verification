---
id: TP-OCPSTRAT-2100-NUTANIX-001
version: "1.1"
date: 2026-11-12
title: "Agent HostedCluster with Nutanix worker VMs"
jira_issues:
  - key: OCPSTRAT-2100
    role: primary
    url: https://redhat.atlassian.net/browse/OCPSTRAT-2100
pull_requests:
  - repo: openshift/release
    number: 86870
    url: https://github.com/openshift/release/pull/86870
    role: implementation
status: draft
tags:
  - nutanix
  - hypershift
  - agent
  - conformance
ieee_829: true
---

# Test Plan: Agent HostedCluster with Nutanix Worker VMs

## 1. Test Plan Identifier

**ID:** TP-OCPSTRAT-2100-NUTANIX-001

**Version:** 1.1

**Date:** 2026-11-12

**IEEE 829 Compliance:** This plan follows the IEEE 829-2008 structure for
software and system test documentation.

## 2. Introduction and Objectives

### 2.1 Purpose and Scope

Verify the **Nutanix workstreams** of OCPSTRAT-2100: an Agent HostedCluster
whose control plane runs on the existing baremetal-backed MCE management
cluster and whose guest workers are Nutanix VMs booted from an MCE InfraEnv
discovery ISO. The `hypershift-mce-agent-nutanix-conformance` workflow is the
primary test vehicle. It also provisions an ingress tunnel gateway and worker
DNS. The default run provisions three workers, verifies their identity and
readiness, then runs guest-cluster conformance.

The plan covers Nutanix infrastructure allocation, HostedCluster worker
provisioning, Agent and NodePool membership, guest health, conformance, and
run-scoped cleanup. A separate manual Prism case verifies the customer
provisioning path without the CI Ansible steps. vSphere and other non-baremetal
platforms, standalone Nutanix cluster installation, and the existing Metal3
workflow are outside this plan's scope. vSphere has been excluded from
OCPSTRAT-2100 and will be tracked separately in a next release.

### 2.2 Objectives

1. Prove that the declarative Nutanix lease, selected subnet, credentials,
   Assisted Service, proxy, ingress gateway, worker DNS, NMStateConfigs, and
   discovery ISO are ready before worker provisioning.
2. Prove that exactly the intended Nutanix VMs become distinct, approved
   Agents and Ready guest Nodes in the intended NodePool; verify scale-out,
   scale-in, application recovery, and reuse of released capacity.
3. Verify worker-origin HTTPS, endpoint ports, direct-path DNS, certificate
   trust, applied proxy settings, ingress, HostedCluster and ManagedCluster
   health, and the guest conformance suite. Verify manual Prism provisioning
   through Agent registration, NodePool membership, and workload execution.
4. Track CI resource hygiene by checking cleanup of run-owned workers, gateway,
   DNS, and management resources. Optionally exercise provisioning failure
   cleanup and failed cleanup verification with retained diagnostics; report
   any cleanup failure even though CI-operator releases the Nutanix lease when
   the workflow ends.

### 2.3 Acceptance Criteria Mapping

| Product or CI hygiene criterion | Test case |
| --- | --- |
| Declarative Nutanix lease and valid IPv4 context | TC-001 |
| Assisted Service becomes ready | TC-002 |
| Proxy, ingress gateway, worker DNS, NMStateConfigs, and InfraEnv ISO | TC-003 |
| Expected worker VMs and unambiguous UUID/MAC records | TC-004 |
| Exact InfraEnv Agent discovery and inventory | TC-005 |
| One-to-one VM/Agent identity and run isolation | TC-006 |
| NodePool selects and installs only run-owned validated Agents | TC-007 |
| Exact guest Node count and readiness after installation | TC-008 |
| Worker-origin HTTPS, endpoint ports, DNS, trust, and applied proxy settings | TC-009 |
| Ingress canary, guest, ManagedCluster, and HostedCluster health | TC-010 |
| Guest conformance and JUnit results | TC-011 |
| Workload continuity, Agent unbinding, and VM reuse across NodePool scaling | TC-012 |
| CI hygiene: run-scoped worker, DNS, and gateway cleanup; lease release | TC-013 |
| Documented manual Prism provisioning through a running guest workload | TC-014 |

### 2.4 Entry and Exit Criteria

Start with an allocated baremetal-backed management environment, MCE and
Nutanix test capacity, and a release under test. Record the release image,
`openshift/release` workflow commit, worker count, and CI run identifier in the
verification report. At the implementation revision below, the workflow sets
`IP_STACK=v4` and defaults `NUTANIX_WORKERS` to `3`.

Product verification requires evidence for TC-001 through TC-012 and TC-014,
and a successful selected conformance run with JUnit results. A missing product
check, untriaged conformance failure, or extra Agent or Node leaves product
verification incomplete.

TC-013 records CI resource hygiene separately. Verify normal-run cleanup and
lease release independently; unverified deletion or residual resources leave
the CI hygiene result incomplete. The six pre-test failure exercises and the
cleanup-verification failure exercise in TC-013 are optional: record each as
run or not run and report any findings, without changing the product
verification result. The workflow permits best-effort post steps, so a green
test phase alone does not establish cleanup success.
CI-operator releases the Nutanix lease when the workflow ends even if post-step
cleanup fails.

## 3. Test Items and References

| Item | Reference and use |
| --- | --- |
| Feature | [OCPSTRAT-2100](https://redhat.atlassian.net/browse/OCPSTRAT-2100), limited here to Nutanix work |
| Implementation design | [openshift/release#86867](https://github.com/openshift/release/pull/86867), a review-only plan PR; it does not itself implement the workflow |
| Implementation revision | [openshift/release@cadcee28fc8b](https://github.com/openshift/release/commit/cadcee28fc8be3fbd6649cf5dd96ef81ada15c19) (2026-11-09); this plan targets the tracked files at this commit |
| Nutanix periodic | [Pinned CI configuration](https://github.com/openshift/release/blob/cadcee28fc8be3fbd6649cf5dd96ef81ada15c19/ci-operator/config/openshift/hypershift/openshift-hypershift-release-5.1__periodics-mce.yaml) selects OCP 5.1 CI candidates and MCE 5.1 for Nutanix conformance |
| Agent manual workflow | [HyperShift Agent guide](https://github.com/openshift/hypershift/blob/51bfaf4a8d2a8b4cb3e80987b2748623c642f8ea/docs/content/how-to/agent/create-agent-cluster.md) describes HostedCluster and InfraEnv creation, manual ISO boot, Agent approval, NodePool scaling, and discovery-image boot before reuse; the Nutanix worker and destroy refs manage CI VMs separately |
| Workflow | `ci-operator/step-registry/hypershift/mce/agent/nutanix/conformance/hypershift-mce-agent-nutanix-conformance-workflow.yaml`; declares the `NUTANIX_QUOTA_SLICE` lease and runs the Nutanix create chain |
| Creation chain | `ci-operator/step-registry/hypershift/mce/agent/nutanix/create/hypershift-mce-agent-nutanix-create-chain.yaml` |
| Provisioning refs | `hypershift-mce-agent-nutanix-context`, `hypershift-mce-agent-nutanix-ingress-tunnel-setup`, `hypershift-mce-agent-nutanix-worker-dns`, `hypershift-mce-agent-nutanix-infraenv`, and `hypershift-mce-agent-nutanix-workers` |
| Validation refs | `hypershift-mce-agent-nutanix-ingress-tunnel-verify`, `hypershift-agent-check-conditions`, and the `hypershift-conformance` test chain |
| Cleanup refs | `hypershift-mce-agent-nutanix-discard-agents`, `hypershift-mce-agent-destroy`, `hypershift-mce-agent-nutanix-destroy`, `hypershift-mce-agent-nutanix-worker-dns-cleanup`, `hypershift-mce-agent-nutanix-ingress-tunnel-cleanup`, and `ofcir-release` |

## 4. Test Environment

| Property | Required state |
| --- | --- |
| Cluster type | Agent-platform HostedCluster with its control plane on the baremetal-backed MCE management cluster and guest Nodes on Nutanix worker VMs |
| Platform | Nutanix Prism Element for worker VMs; OFCIR baremetal management cluster |
| Version or build | OCP 5.1 CI candidate and MCE 5.1 in the pinned Nutanix periodic configuration; record the exact guest release image and MCE build for each run |
| Prerequisites or tooling | Allocated OFCIR management cluster and Nutanix quota slice, Prism credentials, MCE Assisted Service, IPv4 subnet and proxy access; use `oc`, Nutanix provisioning Ansible roles, `openshift-tests`, and CI artifact collection |
| Management cluster | Existing baremetal-backed OFCIR profile with MCE and Assisted Service; HostedCluster control plane remains here |
| Guest cluster | Agent-platform HostedCluster and NodePool; management and guest kubeconfigs remain distinct |
| Nutanix allocation | Separate declarative `nutanix-quota-slice` lease, Prism credentials, one matching Prism Element cluster and selected subnet, and a derived IPv4 ingress VIP outside its DHCP pools |
| Worker network | IPv4 subnet with usable DHCP worker addressing and routing to the gateway, proxy, and guest endpoints; shared subnet DHCP options remain unchanged |
| Ingress path | Lease-owned Nutanix gateway VM, WireGuard tunnel to the baremetal proxy host, host `/32` route to the ingress VIP, and MetalLB ingress Service |
| Worker DNS | Run-scoped dnsmasq on the baremetal WireGuard IP, gateway forwarding on UDP/TCP 53, and worker NMStateConfigs with DHCP addressing and the gateway DNS IP |
| Worker baseline | `NUTANIX_WORKERS=3` by default; verify the design's 8-vCPU, 16-GB RAM, and 120-GB disk baseline per VM |
| Scale test capacity | One additional worker VM slot and a discovery ISO with its matching NMStateConfig for TC-012; track its VM and any image for cleanup |
| Proxy | Baremetal Squid endpoint, HostedCluster `noProxy` value, Assisted Service routes, observed endpoint ports, and any required CA trust bundle available for discovery and guest workers |
| Test tools | `oc`, Nutanix provisioning Ansible roles, `openshift-tests`, and artifact/JUnit collection supplied by the CI workflow |
| Manual provisioning tools | Prism UI access and the customer-facing Agent HostedCluster, InfraEnv, NodePool, and Nutanix VM instructions used for TC-014 |

**Architecture scope:** Only `x86_64` will be tested for Nutanix because
Assisted Service supports Nutanix on that architecture.

**IP stack:** Only IPv4 is supported and will be tested on Nutanix, as with
standalone OpenShift on Nutanix.

Use sanitized resource summaries and CI artifacts as evidence. Do not copy
credentials, pull secrets, kubeconfigs, private endpoints, or complete VM
identifiers into the verification report.

## 5. Test Cases

Run the `hypershift-mce-agent-nutanix-conformance` workflow as the primary
method, then run TC-014 separately through Prism. The tables identify workflow
steps and supplemental actions or checks with their pass conditions. Review
step logs and sanitized resource state to confirm each assertion ran; a skipped
or unavailable check is not a pass.

### 5.1 TC-001: Declarative Nutanix Lease and Context

**Objective:** Confirm the Nutanix lease and IPv4 context identify one Prism
cluster and selected subnet before provisioning.

**Preconditions:** The management allocation exists, and the Nutanix lease
service and Prism credential mount are available.

| Action | Expected result |
| --- | --- |
| CI-operator assigns the workflow's `nutanix-quota-slice` lease to `NUTANIX_QUOTA_SLICE` | A separate Nutanix allocation is present without replacing the baremetal management allocation |
| Run `hypershift-mce-agent-nutanix-context` | Non-IPv4 input fails; the lease, CI run ID, and Prism credential fields are present; exactly one matching Prism Element cluster and selected subnet resolve |
| Derive the subnet CIDR, ingress VIP, and gateway identity | The VIP is valid IPv4 and comes from the selected subnet's allocation rule; the run-owned gateway VM, image, and WireGuard interface identities are recorded before provisioning |

**Evidence:** Workflow lease declaration and CI lease allocation, context step
log, and sanitized subnet/VIP and gateway-identity summaries. Do not include
the private Nutanix context file.

### 5.2 TC-002: Assisted Service Readiness

**Objective:** Confirm Assisted Service reaches its required readiness
conditions before the InfraEnv is created.

**Preconditions:** The management cluster and MCE are available.

| Action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-create-agentserviceconfig` | `AgentServiceConfig/agent` reaches `ReconcileCompleted` |
| Wait for Assisted Service components | The Assisted Service deployment is `Available` and an Assisted Image Service pod is `Ready` within the step timeouts |

**Evidence:** Step log and sanitized component conditions.

### 5.3 TC-003: Proxy, Ingress Gateway, Worker DNS, and Discovery ISO

**Objective:** Verify the proxy, ingress gateway, worker DNS, network
configuration, and discovery ISO are ready for Nutanix worker discovery.

**Preconditions:** TC-001 and TC-002 pass; the intended Agent namespace,
Squid endpoint, and HostedCluster `noProxy` value are available.

| Action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-create-hostedcluster` | The HostedCluster proxy uses Squid and includes the context step's selected Nutanix subnet CIDR in `noProxy` |
| Run `hypershift-agent-create-proxy` | The Assisted Service route is discovered before Squid's allowlist is updated |
| Run `hypershift-mce-agent-nutanix-ingress-tunnel-setup` | The derived VIP is outside every reported subnet DHCP pool before gateway creation; a run-owned gateway VM and image are recorded, the gateway gets a distinct DHCP address, its forwarding service is active, and the baremetal host has a WireGuard handshake and `/32` VIP route |
| Run `hypershift-mce-agent-nutanix-worker-dns` | Run-scoped dnsmasq is active only on the host's WireGuard IP; UDP/TCP 53 firewall rules admit the gateway tunnel peer, and the gateway forwards worker DNS without changing shared subnet DHCP options |
| Check resolver answers | `api` and `api-int` resolve to the management address, `*.apps` resolves to the ingress VIP, and unrelated names forward upstream; obtain equivalent query evidence if `dig` is absent from the host, because the step's query check is conditional |
| Run `hypershift-mce-agent-nutanix-infraenv` | Exactly `NUTANIX_WORKERS` distinct MACs have run-labeled NMStateConfigs with IPv4 DHCP, `auto-dns: false`, IPv6 disabled, and the gateway DNS IP; the InfraEnv selects those configs, uses `x86_64` and the expected proxy fields, reaches `ImageCreated`, and publishes an ISO download URL |

**Evidence:** HostedCluster proxy configuration; proxy, tunnel setup, worker
DNS, and InfraEnv step logs;
sanitized gateway and DNS state, firewall/service/route checks, resolver
answers, NMStateConfig count and network fields, and redacted InfraEnv status.
The ISO is generated by MCE InfraEnv. TC-007 checks the DNS path from the
Agents after worker boot.

### 5.4 TC-004: Nutanix Worker VM Records

**Objective:** Verify provisioning creates only the expected worker VMs with
traceable image, VM, and NIC identities and the intended hardware shape.

**Preconditions:** TC-003 passes and the Nutanix allocation is active.

| Action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-nutanix-workers` | The step confirms tunnel and worker DNS state, downloads the InfraEnv ISO through Squid, uploads one image, and creates exactly `NUTANIX_WORKERS` worker VMs; the default is three and no Nutanix control-plane VM is created |
| Inspect provisioning records and each VM | Exactly one uploaded image UUID and one distinct UUID per worker are recorded; each queried VM has one unambiguous NIC MAC matching its reserved NMStateConfig MAC |
| Compare VM shape with the design baseline | Each worker has the intended 8 vCPUs, 16 GB RAM, and 120 GB disk |

**Evidence:** Provisioning log and sanitized VM shape/UUID/MAC count summary.

### 5.5 TC-005: Agent Discovery and Inventory

**Objective:** Verify the expected Agents register through this run's InfraEnv
and report NIC inventories before identity matching.

**Preconditions:** TC-004 passes and the VMs boot the InfraEnv ISO.

| Action | Expected result |
| --- | --- |
| Wait for Agents associated with this run's InfraEnv | Exactly `NUTANIX_WORKERS` Agents register within the deadline; an extra Agent or timeout fails |
| Wait for each Agent's interface inventory | Every Agent reports NIC MAC information before VM-to-Agent matching begins |

**Evidence:** Workers step log and sanitized InfraEnv Agent count and NIC
inventory status.

### 5.6 TC-006: VM-to-Agent Identity and Run Isolation

**Objective:** Prove each run-owned VM maps to exactly one Agent and unrelated
Agents remain outside the run's selection and approval.

**Preconditions:** TC-005 passes and worker VM MACs are recorded.

| Action | Expected result |
| --- | --- |
| Match each recorded VM MAC to Agent inventory | Every VM maps to exactly one distinct Agent; missing or ambiguous mappings fail |
| Label and count the matched Agents | The run label selects exactly `NUTANIX_WORKERS` Agents; unrelated Agents remain unselected and unapproved |

**Evidence:** Sanitized VM-to-Agent mapping and Agent label count.

### 5.7 TC-007: NodePool Membership and Installation

**Objective:** Verify only the matched Agents are approved and installed into
the intended NodePool after network and proxy validation.

**Preconditions:** TC-006 passes; the intended NodePool starts at zero
replicas.

| Action | Expected result |
| --- | --- |
| Restrict the NodePool selector to this run's Agent label | The selector matches only the mapped Agents |
| Apply the Ignition proxy override and approve the selected Agents | Each selected Agent retains the expected HTTP and HTTPS proxy settings and is approved before installation |
| Scale the NodePool to `NUTANIX_WORKERS` | Its requested replica count is exact |
| Check each selected Agent after scaling | API, API-int, and apps DNS plus `ignition-downloadable` validations report success; every Agent reaches `Validated`, `RequirementsMet`, and `added-to-existing-cluster` within the deadlines |

**Evidence:** Sanitized NodePool selector/replica summary and Agent approval,
Ignition override, network validations, conditions, and installation states.

### 5.8 TC-008: Guest Node Count and Readiness

**Objective:** Verify installation completes its disk reboot and exactly the
expected guest Nodes become Ready.

**Preconditions:** TC-007 passes and the guest kubeconfig is available.

| Action | Expected result |
| --- | --- |
| Poll guest Nodes with the guest kubeconfig | Exactly `NUTANIX_WORKERS` Nodes exist and all have `Ready=True` within the deadline; an extra Node or timeout fails |

The `hypershift-mce-agent-nutanix-workers` step sets VM boot order to `DISK`,
then `CDROM`. The empty disk causes the first boot to use the InfraEnv discovery
ISO. Agent installation writes RHCOS to disk and reboots the VM; the next boot
uses the installed disk. The selected Agents must reach
`added-to-existing-cluster` in TC-007 before this step waits for Ready guest
Nodes. That readiness covers the installation reboot and disk boot.

**Evidence:** Workers step log, the VM boot order in the workflow revision,
and redacted Agent installation state and guest Node condition summaries.

### 5.9 TC-009: Worker Proxy, HTTPS, DNS, and Trust

**Objective:** Verify every worker reaches required endpoints through the
configured proxy or direct path with working DNS and certificate trust.

**Preconditions:** TC-008 passes. Record the configured Squid IP and listener
port, and derive required destination hostnames and ports from the InfraEnv and
Assisted Service routes, ISO/rootfs URLs, guest kubeconfig, HostedCluster
services, and registry/test configuration. Do not assume every TLS endpoint
uses port 443; include the observed API, ignition, OAuth, and Konnectivity
NodePorts where applicable.

| Action | Expected result |
| --- | --- |
| Read guest `Proxy/cluster` | Both `spec.httpProxy` and `spec.httpsProxy` equal the expected Squid URL |
| Probe the Squid listener from every guest Node with `oc debug node` | Each Node opens a TCP connection to the Squid host and port |
| Inventory the actual destination host, port, and proxy or direct path for each required endpoint | Assisted Service and image/rootfs, guest API, ignition, OAuth/OIDC, Konnectivity, registry, and conformance dependencies are accounted for; Squid's domain and CONNECT-port ACLs match the observed proxied destinations without broad allow-all rules |
| From each Nutanix worker, make HTTPS requests through Squid to HTTPS destinations and protocol-specific TLS requests to other proxied services at their actual ports | Squid accepts CONNECT, resolves and reaches the destination, TLS verifies with the worker trust store, and the endpoint returns its expected authenticated, unauthenticated, or protocol-specific result; a proxy denial, TLS error, or listener-only success fails |
| From each worker, resolve and request destinations that bypass the proxy | The worker resolver returns the expected addresses for actual `noProxy`/direct names, and requests to their observed ports succeed without Squid; the proxy bypass list does not divert required proxied endpoints |
| Verify certificate trust in discovery and installed worker environments | Any required private CA bundle is present in both environments; worker HTTPS succeeds with certificate verification enabled, without `--insecure` or TLS interception |

**Evidence:** Sanitized endpoint/port/path inventory; redacted Proxy,
InfraEnv, worker proxy file, service configuration, MachineConfigPool, and CA
summaries; per-worker DNS, CONNECT, TLS, and service-response results; and
redacted Squid ACL and access-log evidence. Do not copy private endpoint URLs,
credentials, or certificates into the report.

The pinned `hypershift-mce-agent-nutanix-workers` step checks the Proxy fields
and TCP listener only. The other checks are required before full conformance
under phase 6 of the implementation design. Run them from the worker host
network, for example through `oc debug node` with `chroot /host`, using
certificate verification and runtime credentials where required. Use a retained
environment that runs these checks before conformance, or add a workflow gate.
The evidence must come from the workers used for that conformance run.

### 5.10 TC-010: Ingress, Guest, and HostedCluster Health

**Objective:** Verify ingress, guest ClusterVersion, ManagedCluster, and
HostedCluster health after the Nutanix workers become Ready.

**Preconditions:** TC-008 passes and guest API access is stable.

| Action | Expected result |
| --- | --- |
| Run `hypershift-agent-create-metallb` and `hypershift-mce-agent-nutanix-ingress-tunnel-verify` | The MetalLB ingress Service has the selected VIP and ready router endpoints; the proxy host resolves the canary Route to that VIP and routes it over the WireGuard `/32` path with a recent handshake; the gateway uses its worker-subnet address and has active forwarding |
| Probe the ingress canary in `hypershift-mce-agent-nutanix-ingress-tunnel-verify` | Direct HTTPS from the gateway and baremetal host, plus HTTPS through Squid, return 2xx/3xx; direct port 80 probes respond; the ingress operator is available, not degraded, and reports `CanaryChecksSucceeding=True` |
| Wait for the hosted ManagedCluster in `hypershift-mce-agent-nutanix-ingress-tunnel-verify` | The run's ManagedCluster reports joined, available, and hub-accepted before conformance |
| Inspect guest `ClusterVersion/version` for the report | The guest reports `Available=True`; this is a report check because the Nutanix MetalLB step skips its earlier ClusterVersion wait |
| Run `hypershift-agent-check-conditions` | Required HostedCluster API, ignition, etcd, release, configuration, and reconciliation conditions have the expected values; version-dependent data-plane and control-plane connection conditions pass when applicable |

**Evidence:** `nutanix-ingress-*` artifacts (VIP, route, handshake, canary
status, gateway forwarding, and operator conditions), sanitized guest
ClusterVersion, ManagedCluster, and HostedCluster condition summaries, and the
release version used to select version-dependent checks.

### 5.11 TC-011: Guest Conformance

**Objective:** Run the selected guest conformance suite and account for its
results, skipped tests, and disabled monitors.

**Preconditions:** TC-009 and TC-010 pass and the guest kubeconfig is available.

| Action | Expected result |
| --- | --- |
| Run the `hypershift-conformance` test chain | `openshift-tests run openshift/conformance/parallel` targets the guest cluster and produces JUnit output |
| Review the selected test list, skips, exit status, and JUnit | Selected conformance tests pass; compare the applied skips with the workflow's three `TEST_SKIPS` patterns and two disabled monitors in `TEST_ARGS`, and triage other skips or failures before acceptance |

The workflow's `test` phase runs `openshift/conformance/parallel` against the
hosted guest cluster after the Nutanix create chain. It provides broad
OpenShift end-to-end coverage rather than a Nutanix-specific test suite.

The [pinned workflow exclusions](https://github.com/openshift/release/blob/cadcee28fc8be3fbd6649cf5dd96ef81ada15c19/ci-operator/step-registry/hypershift/mce/agent/nutanix/conformance/hypershift-mce-agent-nutanix-conformance-workflow.yaml#L39-L50)
leave these behaviors outside the selected suite:

| Mechanism | Exclusion | Bug IDs cited in workflow | Behavior not verified |
| --- | --- | --- | --- |
| `TEST_ARGS` disabled monitors | `apiserver-incluster-availability`, `legacy-node-invariants` | `OCPBUGS-138703`, `ACM-50151` (cited together for both monitors) | In-cluster API availability and legacy node invariants |
| `TEST_SKIPS` | `etcd leader changes are not excessive` | None cited | Excessive etcd leader changes |
| `TEST_SKIPS` | `check registry.redhat.io is available and samples operator can import sample imagestreams` | None cited | Registry availability and sample imagestream import |
| `TEST_SKIPS` | `Prevent openshift node labeling on update by the node TestOpenshiftNodeLabeling` | `OCPBUGS-138700` | Node labeling during update through the worker's hosted-API path |

The workflow notes that API pollers and MCE add-on agents crash because Nutanix
workers cannot directly reach private API VIPs. A passing reduced suite does
not establish direct worker access to those VIPs or verify those agents.
Report this limitation separately from TC-009's configured worker proxy-path
checks.

The suite covers areas such as:

- Networking: workload connectivity, Services, routes, and OVN-related behavior.
- Workloads and nodes: pods, deployments, scheduling, and node behavior.
- Storage: volumes, CSI, and storage-related cluster checks.
- Security and APIs: authentication, RBAC, security constraints, and API resources.
- OpenShift features: builds, images, the registry, and oc commands.

**Evidence:** CI test-phase log, selected/skipped test list, and JUnit files.

### 5.12 TC-012: NodePool Scale-Out, Scale-In, and Agent Reuse

**Objective:** Verify NodePool scaling and released Agent capacity preserve
workload availability and VM-to-Agent identity across reuse.

**Preconditions:** Use a retained verification environment built with the same
setup steps and three Ready workers after TC-008, capacity for one more Nutanix
VM, and the same proxy, gateway, DNS, and InfraEnv configuration. Track any
extra VM and image by exact identity in private run state for TC-013 cleanup.
The pinned workflow scales once from zero to the fixed `NUTANIX_WORKERS` count;
it does not execute this scenario.

| Action | Expected result |
| --- | --- |
| Run a four-replica HTTP application behind a Service, with a `minAvailable: 3` PodDisruptionBudget and placement that permits rescheduling; probe the Service continuously | The application is healthy on the initial three Nodes and the probe establishes a baseline before scaling |
| Reserve a fourth worker MAC, create its run-labeled NMStateConfig, boot a fourth run-owned VM from an InfraEnv ISO containing that configuration, and map its Agent | The new Agent has the expected MAC, proxy and DNS settings, passes validations, and receives the same Ignition proxy override and approval as the original workers; record the VM and any new image in private run state for exact cleanup |
| Scale the NodePool from three to four | The new Agent binds, the NodePool and guest cluster reach four Ready Nodes within the TC-007/TC-008 installation and readiness deadlines, and a Node-targeted canary runs on the new worker |
| Place one application replica on each of the four Nodes while keeping its placement flexible | Every Node carries a replica before scale-in, and the Service probe remains healthy |
| Scale the NodePool from four back to three and identify the selected Machine, Agent, Node, and VM | The removed Node is drained through pod eviction, its application replica reschedules onto a remaining Ready Node, four application replicas recover within 10 minutes, and the Service remains reachable; the NodePool and guest cluster settle at three Ready Nodes |
| Inspect the removed Agent and its Nutanix VM separately | The Agent is unbound from the HostedCluster and its Machine and guest Node are gone; the externally managed VM still exists in Prism until explicit cleanup |
| Scale from three to four | The released capacity is rediscovered through one Agent matched by MAC, becomes eligible and binds to the NodePool again, and returns as one Ready guest Node that accepts a Node-targeted workload; no duplicate Agent or Node remains |

**Evidence:** Time-ordered NodePool, Machine, Agent, Node, VM, and application
summaries; sanitized MAC mapping and VM identity; pod placement and eviction
events; application replica/PDB status and continuous Service probe results;
rediscovery and reuse status; and a sanitized cleanup inventory summary.
Record the retained environment's run ID and implementation revision separately
from the conformance run.

### 5.13 TC-013: Run-Scoped Cleanup

This case records CI resource hygiene separately from product verification.

**Objective:** Verify run-owned resources are removed and residual resources
are reported independently of Nutanix lease release.

**Preconditions:** The workflow reaches post steps after a successful or
failed pre or test phase, or the retained TC-012 environment is ready for
teardown. Retain diagnostics before deletion.

| Action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-nutanix-discard-agents` before `hypershift-mce-agent-destroy` | Run-owned disposable Agents, including those registered before run-label assignment, and InfraEnv are removed before HostedCluster destruction |
| Run `hypershift-mce-agent-destroy` | The run's HostedCluster, NodePool, and ManagedCluster are absent after bounded polling; check independently because the chain tolerates an `hcp destroy` error |
| Run `hypershift-mce-agent-nutanix-destroy` | Run-owned Agents, InfraEnv, NMStateConfigs, and pull secret are absent; unrelated resources remain untouched; each recorded or exact-name-recovered worker VM and discovery image UUID returns HTTP 404 after bounded polling |
| Remove any additional TC-012 VM or image by its recorded identity | Dynamically provisioned resources absent from the fixed-count workflow records are deleted and independently verified absent; no broad subnet or name-prefix deletion occurs |
| Run `hypershift-mce-agent-nutanix-worker-dns-cleanup` | The run's baremetal dnsmasq service is inactive; its unit file, config, and marker are absent; its UDP/TCP 53 rich rules are absent from runtime and permanent firewall configuration; shared subnet DHCP options remain unchanged |
| Run `hypershift-mce-agent-nutanix-ingress-tunnel-cleanup` | The proxy-host WireGuard service is inactive and its interface, config, key, unit file, and marker are absent; the run's ingress VIP `/32` route and WireGuard UDP firewall port are absent; the gateway VM and image UUIDs return HTTP 404 in Prism; unrelated lease resources remain untouched |
| Review `ofcir-release` and the CI-operator Nutanix lease result | The management lease is released by its post step; CI-operator releases the declarative Nutanix lease when the workflow ends even if cleanup fails, so any residual resources are recorded as a cleanup failure |

#### Optional provisioning failure exercises

The six cases below are optional CI cleanup checks. Record each as run or not
run and report cleanup findings separately from the product result. Exercise
lease acquisition failure before any pre step can run.

For any selected case, use a separate disposable run. Inject one controlled
failure at the stated boundary and record the injection method,
workflow revision, run ID, and exact run-owned resource identities in private
run state. The pinned workflow has no built-in fault-injection controls, so
use a dedicated test configuration. Capture resource inventories before the
run and before cleanup. For each executed case, confirm the test phase did not
start, retain the failing step's diagnostics, verify absence of every run-owned
resource created before failure, and compare the inventories to prove cleanup
did not delete or modify unrelated resources. A missing expected post step or
required diagnostic artifact does not count as a pass.

| Failure boundary | Retained diagnostics | Cleanup assertion |
| --- | --- | --- |
| Nutanix lease acquisition fails or times out before provisioning | CI-operator lease events and failure log; before/after lease occupancy and resource inventory | No Nutanix lease remains held and no run-owned resources were created; do not assume pre or post steps ran |
| InfraEnv image creation fails or `ImageCreated` times out | InfraEnv conditions and events, creation-step log, and gateway/DNS state before cleanup | InfraEnv, NMStateConfigs, pull secret, gateway, DNS, and other resources created earlier in the run are removed; no worker VM or Nutanix discovery image remains |
| Discovery ISO downloads but Nutanix image upload fails | Worker/Ansible upload logs, InfraEnv status, and exact-name Prism image lookup before cleanup | Any partially uploaded Nutanix image is removed by its recorded or recovered UUID; no worker VM remains |
| Worker provisioning fails after at least one VM is created but before all UUIDs are recorded | Worker/Ansible failure log and exact-name/UUID Prism inventory of the partial VM set | Every created worker VM and the uploaded image are removed, including VMs recovered by exact run-owned name |
| Agent registration or inventory matching fails after worker VMs boot | Worker log, InfraEnv and Agent conditions/events, Agent count, and available MAC-to-VM mapping | Registered Agents are removed even if they received no run label; all run-owned VMs and images are removed |
| NodePool installation or guest Node readiness fails after Agent approval and NodePool scaling | Worker log and Agent validation/state, NodePool, Machine, and guest Node conditions and events | The run's HostedCluster, NodePool, ManagedCluster, Agents, workers, and image are absent after teardown |

#### Optional cleanup-verification failure exercise

In a separate disposable run, inject a failure after provisioning so
`hypershift-mce-agent-nutanix-destroy` cannot confirm that a run-owned worker
VM, discovery image, or management resource is gone. Allow the workflow to
finish and inspect the Nutanix lease afterward. The destroy step's failure
establishes a CI cleanup failure; it does not establish that the lease remains
held.

| Action | Expected result |
| --- | --- |
| Inspect the destroy step and remaining post steps | The destroy step exits nonzero and reports that deletion cannot be verified; CI-operator attempts to release the lease after the workflow returns despite the cleanup error |
| Independently inspect the resource and the lease after workflow completion | Record whether the resource is absent, present, or unconfirmed, and query the lease service for the run's lease state and holder; the lease is no longer held by this run. Report a held lease as a separate release failure and preserve unrelated resources |

**Evidence:** Logs for each post step; zero run-labeled NMStateConfigs;
sanitized management-resource counts; worker, supplemental, and gateway
VM/image absence results; worker DNS service, unit, config, marker, and runtime
and permanent firewall-rule absence checks; proxy-host WireGuard service,
interface, config, key, unit, marker, route, and firewall-port absence checks;
and lease release results. The gateway VM absence also removes its in-VM
forwarding and NAT rules.

For each executed failure case, retain the injected-failure record,
failing-step log, pre-cleanup status and inventory, available `info` artifacts,
post-step logs, and independent post-cleanup inventory and lease checks.
Lease acquisition may fail before `info` or other post steps can run; use the
CI-operator lease log and independent inventory for that case. Review cleanup
separately because the workflow sets `allow_best_effort_post_steps: true`.

### 5.14 TC-014: Manual Prism Provisioning and Guest Workload

**Objective:** Verify the documented customer procedure provisions three
Nutanix workers through Prism and runs a workload on the guest cluster.

**Execution:** Required manual product case in a separate, customer-like
Nutanix environment. Follow the customer-facing Agent platform and Prism
instructions, recording their titles and revisions. Do not invoke the CI
Nutanix step scripts or Ansible roles, source the CI shared directory, or reuse
CI-generated InfraEnv images and network resources. If a required setup step
exists only in a CI script, record the documentation gap and do not pass this
case.

**Preconditions:** An isolated Nutanix allocation has capacity for three
`x86_64` worker VMs. MCE, Assisted Service, and the documented IPv4, DNS,
proxy, certificate trust, and ingress prerequisites are available. Use the
documented customer procedure to create a separate Agent HostedCluster and an
initially empty NodePool.

| Action | Expected result |
| --- | --- |
| Create and inspect the HostedCluster, NodePool, and InfraEnv using the documented Agent platform procedure | The NodePool starts at zero replicas; the InfraEnv reaches `ImageCreated` and provides a downloadable discovery ISO with the documented network and proxy settings |
| In Prism, upload the InfraEnv ISO and create three worker VMs with an empty installation disk, a NIC on the intended subnet, and the ISO attached as a virtual CD-ROM | Each VM has the planned CPU, memory, and disk size; its UUID and NIC MAC are unique and recorded; the first boot loads the discovery ISO |
| Boot the VMs and inspect InfraEnv Agents | Exactly three Agents register in the intended namespace; each Agent inventory MAC maps to one recorded Prism VM, passes required network and installation validations, and unrelated Agents remain unselected |
| Approve the three Agents using the documented procedure and scale the NodePool to three | Only the three mapped Agents bind to the NodePool, reach `added-to-existing-cluster`, reboot from their installed disks, and become three Ready guest Nodes; no extra Agent or Node joins |
| Run a guest HTTP workload with one Ready Pod on each Nutanix worker and a Service | Each Pod executes on its intended worker and serves the expected response; Service requests succeed and the workload stays healthy |

**Evidence:** The customer documentation and revision used, a redacted manual
action log, Prism VM shape and identity count, InfraEnv and Agent conditions,
sanitized VM-to-Agent MAC mapping, NodePool and guest Node states, Pod placement,
and per-Pod and Service responses. Record any undocumented workaround as a
failed case. Keep VM and image identifiers in private run state for exact
post-test cleanup; verify the manual resources are removed without changing
unrelated resources.

## 6. Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| The pinned worker step checks proxy fields and TCP reachability but not the full worker request path | Complete all worker-origin checks in TC-009 before conformance; a green workflow run alone does not pass this gate |
| CI provisions Nutanix VMs through Ansible and may hide manual prerequisites | Execute required TC-014 through Prism using customer-facing instructions; record any setup available only in CI scripts as a documentation gap and a failed manual case |
| The worker DNS step checks resolver answers only when `dig` is installed | Obtain equivalent query results when that check is skipped; use the Agent DNS validations to verify the worker-side path |
| The fixed-count conformance workflow has no dynamic NodePool scaling step | Execute TC-012 in a retained environment; record its run evidence and keep exact cleanup identities in private run state |
| CI-operator releases the Nutanix lease even if best-effort cleanup fails | Review every available post step and track residual resources as a CI hygiene failure; use the optional TC-013 failure exercises to assess cleanup resilience |
| The `info` step collects diagnostics but adds no pass/fail checks | Use its artifacts for investigation, not as proof of additional coverage |

## 7. Approvals

| Role | Name | Date |
| --- | --- | --- |
| Author | Martin Gencur | 2026-10-15 |
| Reviewer |  |  |
