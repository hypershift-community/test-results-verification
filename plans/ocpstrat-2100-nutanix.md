---
id: TP-OCPSTRAT-2100-NUTANIX-001
version: "1.0"
date: 2026-10-15
title: "Agent HostedCluster with Nutanix worker VMs"
jira_issues:
  - key: OCPSTRAT-2100
    role: primary
    url: https://redhat.atlassian.net/browse/OCPSTRAT-2100
pull_requests:
  - repo: openshift/release
    number: 86870
    url: https://github.com/openshift/release/pull/86870
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

**Version:** 1.0

**Date:** 2026-10-15

**IEEE 829 Compliance:** This plan follows the IEEE 829-2008 structure for
software and system test documentation.

## 2. Introduction and Objectives

### 2.1 Purpose and Scope

Verify the **Nutanix workstreams** of OCPSTRAT-2100: an Agent HostedCluster
whose control plane runs on the existing baremetal-backed MCE management
cluster and whose guest workers are Nutanix VMs booted from an MCE InfraEnv
discovery ISO. The new `hypershift-mce-agent-nutanix-conformance` workflow is
the primary test vehicle. The default run provisions three workers, verifies
their identity and readiness, then runs guest-cluster conformance.

The plan covers Nutanix infrastructure allocation, HostedCluster worker
provisioning, Agent and NodePool membership, guest health, conformance, and
run-scoped cleanup. vSphere and other non-baremetal platforms, standalone
Nutanix cluster installation, and the existing Metal3 workflow are outside
this plan's scope.

### 2.2 Objectives

1. Prove that the Nutanix lease, subnet, credentials, Assisted Service, proxy,
   and discovery ISO are ready before worker provisioning.
2. Prove that exactly the intended Nutanix VMs become distinct, approved
   Agents and Ready guest Nodes in the intended NodePool.
3. Verify the guest proxy settings, HostedCluster and ManagedCluster health,
   and the guest conformance suite.
4. Verify that cleanup removes only run-owned resources and releases the
   Nutanix lease only after deletion is confirmed.

### 2.3 Acceptance Criteria Mapping

| Nutanix acceptance criterion | Test case |
| --- | --- |
| Separate, valid IPv4 Nutanix allocation | TC-001 |
| Assisted Service becomes ready | TC-002 |
| Proxy prerequisites and downloadable InfraEnv ISO | TC-003 |
| Expected worker VMs and unambiguous UUID/MAC records | TC-004 |
| Exact InfraEnv Agent discovery and requirements | TC-005 |
| One-to-one VM/Agent identity and run isolation | TC-006 |
| NodePool selects and installs only run-owned Agents | TC-007 |
| Exact guest Node count and readiness | TC-008 |
| Guest proxy fields and node-to-Squid TCP reachability | TC-009 |
| Guest, ManagedCluster, and HostedCluster health | TC-010 |
| Guest conformance and JUnit results | TC-011 |
| Run-scoped post-run cleanup and lease release | TC-012 |

### 2.4 Entry and Exit Criteria

Start with an allocated baremetal-backed management environment, MCE and
Nutanix test capacity, and a release under test. Record the release image,
workflow revision, worker count, and CI run identifier in the verification
report. The current workflow supports IPv4 and defaults `NUTANIX_WORKERS` to
`3`.

Acceptance requires evidence for TC-001 through TC-012, a successful selected
conformance run with JUnit results, and independently verified cleanup. A
missing check, untriaged conformance failure, extra Agent or Node, or
unverified deletion leaves verification incomplete. The workflow permits
best-effort post steps, so a green test phase alone does not establish cleanup
success.

## 3. Test Items and References

| Item | Reference and use |
| --- | --- |
| Feature | [OCPSTRAT-2100](https://redhat.atlassian.net/browse/OCPSTRAT-2100), limited here to Nutanix work |
| Implementation design | [openshift/release#86867](https://github.com/openshift/release/pull/86867), a review-only plan PR; it does not itself implement the workflow |
| Workflow | `ci-operator/step-registry/hypershift/mce/agent/nutanix/conformance/hypershift-mce-agent-nutanix-conformance-workflow.yaml` |
| Provisioning checks | Nutanix `lease-acquire`, `infraenv`, and `workers` steps under `ci-operator/step-registry/hypershift/mce/agent/nutanix/` |
| Cluster and test checks | `hypershift-agent-check-conditions` and `hypershift-conformance` steps in `openshift/release` |
| Cleanup checks | Nutanix `destroy` step under `ci-operator/step-registry/hypershift/mce/agent/nutanix/` |

## 4. Test Environment

| Property | Required state |
| --- | --- |
| Management cluster | Existing baremetal-backed OFCIR profile with MCE and Assisted Service; HostedCluster control plane remains here |
| Guest cluster | Agent-platform HostedCluster and NodePool; management and guest kubeconfigs remain distinct |
| Nutanix allocation | Separate `nutanix-quota-slice` lease, Prism credentials, one matching Prism Element cluster and leased subnet, and a derived IPv4 ingress VIP |
| Worker network | IPv4 subnet with usable worker addressing and routing to the required management, proxy, and guest endpoints; current workflow assumes a working DHCP path |
| Worker baseline | `NUTANIX_WORKERS=3` by default; verify the design's 8-vCPU, 16-GB RAM, and 120-GB disk baseline per VM |
| Proxy | Baremetal Squid endpoint, HostedCluster `noProxy` value, and Assisted Service route available for the discovery image and guest workers |
| Test tools | `oc`, Nutanix provisioning Ansible roles, `openshift-tests`, and artifact/JUnit collection supplied by the CI workflow |

Use sanitized resource summaries and CI artifacts as evidence. Do not copy
credentials, pull secrets, kubeconfigs, private endpoints, or complete VM
identifiers into the verification report.

## 5. Test Cases

Run the `hypershift-mce-agent-nutanix-conformance` workflow as the primary
method. The table in each case identifies the automated step and the pass
condition. Review the corresponding step log and sanitized resource state to
confirm the assertion ran; a skipped or unavailable step is not a pass.

### 5.1 TC-001: Nutanix Lease and Network Selection

**Preconditions:** The management allocation exists and the Nutanix lease
service and Prism credential mount are available.

| Automated action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-nutanix-lease-acquire` with IPv4 selected | A separate `nutanix-quota-slice` lease is recorded without replacing the management allocation; non-IPv4 input fails |
| Resolve Prism Element, leased subnet, and derived ingress VIP | Required credential fields are present; exactly one matching cluster and subnet exist; ingress VIP is valid IPv4 |

**Evidence:** Lease step log and sanitized lease/subnet selection record.

### 5.2 TC-002: Assisted Service Readiness

**Preconditions:** The management cluster and MCE are available.

| Automated action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-create-agentserviceconfig` | `AgentServiceConfig/agent` reaches `ReconcileCompleted` |
| Wait for Assisted Service components | The Assisted Service deployment is `Available` and an Assisted Image Service pod is `Ready` within the step timeouts |

**Evidence:** Step log and sanitized component conditions.

### 5.3 TC-003: Proxy Prerequisites and Discovery ISO

**Preconditions:** TC-002 passes; the intended Agent namespace, Squid
endpoint, and HostedCluster `noProxy` value are available.

| Automated action | Expected result |
| --- | --- |
| Run `hypershift-agent-create-proxy` | The Assisted Service route is discovered before Squid's allowlist is updated |
| Run `hypershift-mce-agent-nutanix-infraenv` | Run-owned InfraEnv has the intended proxy fields, reaches `ImageCreated`, and publishes an ISO download URL |
| Download the InfraEnv ISO | Download succeeds and the image is available for the Nutanix upload step |

**Evidence:** Proxy and InfraEnv step logs, redacted InfraEnv status, and ISO
download result. The ISO is generated by MCE InfraEnv, not by the standalone
Agent installer.

### 5.4 TC-004: Nutanix Worker VM Records

**Preconditions:** TC-003 passes and the Nutanix allocation is active.

| Automated action | Expected result |
| --- | --- |
| Run the Nutanix `workers` Ansible provisioning step | Exactly `NUTANIX_WORKERS` worker VMs are created from the InfraEnv ISO; the default is three and no Nutanix control-plane VM is created |
| Inspect provisioning records and each VM | Exactly one uploaded image UUID and one distinct UUID per worker are recorded; each queried VM yields one unambiguous NIC MAC |
| Compare VM shape with the design baseline | Each worker has the intended 8 vCPUs, 16 GB RAM, and 120 GB disk |

**Evidence:** Provisioning log and sanitized VM shape/UUID/MAC count summary.

### 5.5 TC-005: Agent Discovery and Requirements

**Preconditions:** TC-004 passes and the VMs boot the InfraEnv ISO.

| Automated action | Expected result |
| --- | --- |
| Wait for Agents associated with this run's InfraEnv | Exactly `NUTANIX_WORKERS` Agents register within the deadline; an extra Agent or timeout fails |
| Wait on each selected Agent | Every selected Agent reaches `RequirementsMet` |

**Evidence:** Workers step log and redacted Agent conditions.

### 5.6 TC-006: VM-to-Agent Identity and Run Isolation

**Preconditions:** TC-005 passes and worker VM MACs are recorded.

| Automated action | Expected result |
| --- | --- |
| Match each recorded VM MAC to Agent inventory | Every VM maps to exactly one distinct Agent; missing or ambiguous mappings fail |
| Label and count the matched Agents | The run label selects exactly `NUTANIX_WORKERS` Agents; unrelated Agents remain unselected and unapproved |

**Evidence:** Sanitized VM-to-Agent mapping and Agent label count.

### 5.7 TC-007: NodePool Membership and Installation

**Preconditions:** TC-006 passes; the intended NodePool starts at zero
replicas.

| Automated action | Expected result |
| --- | --- |
| Restrict the NodePool selector and approve the selected Agents | The selector matches only this run's label and only mapped Agents are approved |
| Scale the NodePool to `NUTANIX_WORKERS` | Its requested replica count is exact; every selected Agent reports `added-to-existing-cluster` within the deadline |

**Evidence:** Sanitized NodePool selector/replica summary and Agent states.

### 5.8 TC-008: Guest Node Count and Readiness

**Preconditions:** TC-007 passes and the guest kubeconfig is available.

| Automated action | Expected result |
| --- | --- |
| Poll guest Nodes with the guest kubeconfig | Exactly `NUTANIX_WORKERS` Nodes exist and all have `Ready=True` within the deadline; an extra Node or timeout fails |

**Evidence:** Workers step log and redacted guest Node condition summary.

### 5.9 TC-009: Guest Proxy Configuration and Reachability

**Preconditions:** TC-008 passes and the expected Squid URL is recorded.

| Automated action | Expected result |
| --- | --- |
| Read guest `Proxy/cluster` | Both `spec.httpProxy` and `spec.httpsProxy` equal the expected Squid URL |
| Probe the Squid listener from every guest Node with `oc debug node` | Each Node opens a TCP connection to the Squid host and port |

**Evidence:** Redacted Proxy specification and per-Node probe results. This
check establishes TCP reachability; it does not prove HTTPS requests traverse
Squid or that each Node has applied rendered proxy settings.

### 5.10 TC-010: Guest and HostedCluster Health

**Preconditions:** TC-008 passes and guest API access is stable.

| Automated action | Expected result |
| --- | --- |
| Run guest readiness checks | Guest `ClusterVersion/version` becomes `Available`; its ManagedCluster reports joined, available, and hub-accepted |
| Run `hypershift-agent-check-conditions` | Required HostedCluster API, ignition, etcd, release, configuration, and reconciliation conditions have the expected values; version-dependent data-plane and control-plane connection conditions pass when applicable |

**Evidence:** ClusterVersion, ManagedCluster, and HostedCluster condition
summaries with the release version used to select version-dependent checks.

### 5.11 TC-011: Guest Conformance

**Preconditions:** TC-010 passes and the guest kubeconfig is available.

| Automated action | Expected result |
| --- | --- |
| Run the `hypershift-conformance` test chain | `openshift-tests run openshift/conformance/parallel` targets the guest cluster and produces JUnit output |
| Review the selected test list, skips, exit status, and JUnit | Selected conformance tests pass; only the workflow's two declared exclusions are applied and any further failures are triaged before acceptance |

This workflow runs openshift/conformance/parallel against the hosted guest cluster, after Nutanix worker provisioning. It is broad OpenShift end-to-end coverage, not a Nutanix-specific test suite (ci-operator/step-registry/hypershift/mce/agent/nutanix/conformance/hypershift-mce-agent-nutanix-conformance-workflow.yaml:18).

The suite covers areas such as:

- Networking: workload connectivity, Services, routes, and OVN-related behavior.
- Workloads and nodes: pods, deployments, scheduling, and node behavior.
- Storage: volumes, CSI, and storage-related cluster checks.
- Security and APIs: authentication, RBAC, security constraints, and API resources.
- OpenShift features: builds, images, the registry, and oc commands.

**Evidence:** CI test-phase log, selected/skipped test list, and JUnit files.

### 5.12 TC-012: Run-Scoped Cleanup

**Preconditions:** The workflow reaches post steps after a successful or
failed test phase. Retain diagnostics before deletion.

| Automated action | Expected result |
| --- | --- |
| Run `hypershift-mce-agent-nutanix-destroy` | Run-owned Agents, InfraEnv, and pull secret are absent; resources without this run's ownership label are not deleted |
| Delete recorded Nutanix VM and image UUIDs, then query Prism Central | Each recorded UUID returns HTTP 404 after bounded polling; no broad subnet or name-prefix deletion occurs |
| Release the Nutanix lease | Lease release follows confirmed VM/image and management-resource absence; if deletion cannot be verified, the lease is retained and cleanup failure is reported |

**Evidence:** Post-step log, redacted UUID count/absence results, and lease
release or retention result. Review this case separately because the workflow
sets `allow_best_effort_post_steps: true`.

## 6. Risks and Mitigations

| Risk or coverage boundary | Mitigation or interpretation |
| --- | --- |
| Guest proxy check covers configuration fields and node-to-Squid TCP only | Report that limit; inspect rendered worker settings and an actual proxied HTTPS request in a supplemental verification if required for GA |
| No dedicated pre-conformance probe tests ingress VIP reachability from a Nutanix worker | Use a separate worker-to-ingress probe when this path is an acceptance gate; do not infer reachability from the derived VIP alone |
| The `info` step collects diagnostics but adds no pass/fail checks | Use its artifacts for investigation, not as proof of additional coverage |

## 7. Approvals

| Role | Name | Date |
| --- | --- | --- |
| Author | Martin Gencur | 2026-10-15 |
| Nutanix test reviewer |  |  |
