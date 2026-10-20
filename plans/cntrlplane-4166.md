---
id: TP-CNTRLPLANE-4166-001
version: "1.1"
date: 2026-10-20
title: "Multi-Shard Etcd Backup and Restore Support"
status: draft
ieee_829: true
jira_issues:
  - key: CNTRLPLANE-4166
    role: primary
    url: https://redhat.atlassian.net/browse/CNTRLPLANE-4166
pull_requests:
  - repo: openshift/hypershift
    number: 9146
    url: https://github.com/openshift/hypershift/pull/9146
    role: implementation
tags:
  - etcd
  - sharding
  - backup
  - disaster-recovery
  - hcpetcdbackup
author: jhjaggars
---

# Test Plan: Multi-Shard Etcd Backup and Restore Support

## 1. Test Plan Identifier

**ID:** TP-CNTRLPLANE-4166-001
**Version:** 1.1
**Date:** 2026-10-20
**Standard:** This document follows the IEEE 829-2008 structure, adapted to
the feature under test.

## 2. Introduction and Objectives

### 2.1 Purpose

Verify that the `HCPEtcdBackup` controller snapshots and restores **all
persistent etcd shards** (not just the default `etcd`), that restore status is
correctly aggregated and surfaced on the HostedControlPlane, that concurrent
backups are serialized, and that version skew between the release payload CPO
and the deployed CPO override does not break multi-shard backup. Both
`EtcdSharding` and `HCPEtcdBackup` are `TechPreviewNoUpgrade`-gated.

### 2.2 Objectives

1. Shard discovery covers all persistent shards; EmptyDir shards are excluded
   from backup and restore.
2. Per-shard snapshots are uploaded as distinct S3 objects and tracked in
   `HCPEtcdBackupStatus.ShardSnapshots`.
3. Restore injects `etcd-init` per persistent shard; `EtcdSnapshotRestored`
   aggregates across shards and surfaces failures (with the shard named)
   independent of StatefulSet readiness.
4. Exactly one backup Job runs per HostedControlPlane at a time; concurrent
   requests are terminally rejected.
5. The backup Job resolves the same CPO image that is deployed in the control
   plane namespace (annotation mirror), preserving multi-shard uploads under
   payload/operator version skew.

### 2.3 Acceptance Criteria Mapping

| Acceptance Criterion | Test Case |
|----------------------|-----------|
| Persistent shards snapshotted/restored; EmptyDir excluded | TC-001, TC-002, TC-003, TC-007 |
| Concurrent backups serialized (one runs, other rejected) | TC-005 |
| Failed shard restore surfaces condition naming the shard | TC-008, TC-009 |
| Backup helper image follows CPO override across skew | TC-004 |
| API validations enforce at admission | TC-010 |
| Single-shard behavior unchanged | TC-011 |
| KMS metadata recorded | TC-012 |

## 3. Test Items and References

| Item | Reference |
|------|-----------|
| Implementation PR | [openshift/hypershift#9146](https://github.com/openshift/hypershift/pull/9146) |
| Feature Jira | [CNTRLPLANE-4166](https://redhat.atlassian.net/browse/CNTRLPLANE-4166) |
| Core sharding PR | [openshift/hypershift#8705](https://github.com/openshift/hypershift/pull/8705) |
| Design document | `docs/content/how-to/disaster-recovery/methods/etcd-snapshot/shard-backup-plan.md` (in PR) |
| API types | `api/hypershift/v1beta1/hostedcluster_types.go`, `api/hypershift/v1beta1/etcdbackup_types.go` |
| Backup controller | `hypershift-operator/controllers/etcdbackup/reconciler.go` |
| Restore logic | `control-plane-operator/controllers/hostedcontrolplane/v2/etcd/`, `hostedcontrolplane_controller.go` |

## 4. Test Environment

| Property | Value |
|----------|-------|
| Management cluster | ROSA on AWS (OpenShift), TechPreviewNoUpgrade feature set |
| Operator image | Branch build of HyperShift Operator (`Dockerfile.dev`) |
| Release payload | Stable OCP 4.22.x (older than branch CPO to exercise version skew) |
| HostedCluster topology | SingleReplica control plane; node pool replicas 0 acceptable |
| Storage | S3 bucket + static AWS credentials Secret (`credentials` key, ini format) in the `hypershift` namespace |
| CLI | Branch `hypershift` CLI built from the same commit as the operator image |

**Reference topology** (created via `hypershift create cluster aws --render
--render-sensitive --render-into hc.yaml`, then editing `spec.etcd.managed`
before applying — the CLI has no shard flags, and shards are immutable after
creation):

```yaml
  etcd:
    managed:
      shards:
      - name: configmaps          # persistent (PV inherited from parent storage)
        replicas: 1
        resources:
        - apiGroup: ""
          resource: configmaps
      - name: events               # ephemeral — excluded from backup/restore
        replicas: 1
        resources:
        - apiGroup: ""
          resource: events
        storage:
          type: EmptyDir
      storage:
        persistentVolume:
          size: 8Gi
          storageClassName: gp3-csi
        type: PersistentVolume
    managementType: Managed
```

Conventions below: `NS=clusters-<cluster-name>` (the HostedControlPlane
namespace), `HYP` = `hypershift` namespace.

## 5. Test Cases

### TC-001: Shard topology and routing

**Objective:** Shards deploy as independent StatefulSets and resource kinds
route to their designated shard.

**Steps:**
1. Create the sharded HostedCluster per the reference topology.
2. Wait for control plane rollout.

**Expected:**
- `oc get sts -n $NS` shows `etcd`, `etcd-configmaps`, `etcd-events`.
- `oc get pvc -n $NS` shows PVs for `etcd` and `etcd-configmaps` only.
- Objects written to the guest API land in the right shard (verify with
  `etcdctl get --prefix --keys-only /kubernetes.io/` inside each shard pod —
  note the HyperShift etcd key prefix is `/kubernetes.io`, not `/registry`).
- KAS config (`configmap/kas-config`) has
  `etcd-servers-overrides: ["/configmaps#https://etcd-client-configmaps...",
  "/events#https://etcd-client-events..."]`.

### TC-002: Backup Job and NetworkPolicy contents

**Objective:** Backup covers persistent shards only; network access is scoped
to them.

**Steps:**
1. Create the credential secret and an `HCPEtcdBackup` CR with S3 storage.
2. Capture the NetworkPolicy while the backup is in flight (it is deleted on
   completion).

**Expected:**
- Job init containers: `fetch-certs snapshot-etcd snapshot-etcd-configmaps`
  (no `snapshot-etcd-events`).
- NetworkPolicy `allow-etcd-backup` selects `app In [etcd etcd-configmaps]`,
  ingress from the `hypershift` namespace on port 2379.

### TC-003: Multi-shard backup success

**Expected:**
- `BackupSucceeded`; `status.shardSnapshots` lists exactly the persistent
  shards; `status.snapshotURL` equals the default `etcd` entry.
- Two distinct non-empty S3 objects (`etcd.db`, `etcd-configmaps.db`).
- `HC.status.lastSuccessfulEtcdBackupURL` persisted.

### TC-004: Version skew / backup Job image resolution

**Objective:** The backup Job uses the deployed CPO override, not the older
payload CPO.

**Steps:** create the HostedCluster with
`--control-plane-operator-image=<override>` and an older release payload; run
a multi-shard backup.

**Expected:**
- HCP carries the mirrored `hypershift.openshift.io/control-plane-operator-image`
  annotation.
- Job `fetch-certs` and `upload` containers use the override image.
- Multi-shard upload uses `--snapshot-dir` and succeeds.

### TC-005: Concurrent backup serialization

**Steps:** with a healthy cluster, submit two `HCPEtcdBackup` CRs in one
atomic `oc apply` (single multi-document file with `---` separators); after
completion, repeat with a second pair.

**Expected:**
- Exactly one of each pair reaches `BackupSucceeded`; the other is terminally
  rejected (`BackupRejected`) with a message naming the active Job.
- Exactly one Job per accepted backup; a completed prior Job does not block
  new backups.
- **Regression signal:** both backups reaching `BackupInProgress` with two
  active Jobs (the original race).

### TC-006: Unhealthy shard gating and recovery

**Steps:** delete a persistent shard StatefulSet; submit a backup during the
window; wait for the CPO to recreate it.

**Expected:**
- While the shard is missing/not ready, the backup is non-terminal with
  reason `EtcdUnhealthy` and requeues.
- After recovery, the same backup proceeds to `BackupSucceeded`.

### TC-007: Explicit default and named-shard restore

**Steps:**
1. Seed guest data: a Secret (default shard) and a ConfigMap (routed to the
   named shard); take a backup.
2. Create a new HostedCluster with the same shard topology plus restore URLs
   at creation (immutable fields): default
   `storage.restoreSnapshotURL` and per-shard `restoreSnapshotURL` (S3
   presigned GET URLs).

**Expected:**
- `etcd-init` injected into both persistent StatefulSets (visible in the STS
  ControllerRevision history), never into the EmptyDir shard.
- `EtcdSnapshotRestored=True` only after all shards complete; `etcd-init`
  removed from STS templates afterwards.
- Seeded objects readable in the restored guest with original values. Note:
  cross-cluster secret restore requires porting the source cluster's
  `etcd-encryption-key` Secret (standard DR step) — otherwise reads fail with
  "no matching key was found for the provided AES transformer".

### TC-008: Invalid named-shard restore reporting

**Steps:** create a HostedCluster whose named-shard `restoreSnapshotURL`
points at a nonexistent S3 object (presigned URL returning `NoSuchKey`);
default shard uses a valid snapshot.

**Expected:**
- The named shard's `etcd-init` crash-loops; the STS never becomes ready.
- The HCP publishes `EtcdSnapshotRestored=False` with a message **naming the
  failing shard** (e.g. `shard "etcd-configmaps": etcd-init container failed
  (exit code 1): ... NoSuchKey ...`) — independent of StatefulSet readiness.
- **Regression signal:** the condition being entirely absent while the init
  container fails.

### TC-009: Restore condition re-evaluation (no latch)

**Steps:** make the missing object appear (upload a valid snapshot to the
bogus key) and let `etcd-init` retry.

**Expected:** the condition flips to `True`/`AsExpected`, `etcd-init` is
removed from the STS template, and the shard becomes ready — a previously
observed failure must not latch `False`.

### TC-010: API / CEL validation

**Expected (against a TechPreviewNoUpgrade management cluster):**
- Adding/removing shards after creation rejected.
- Per-shard `restoreSnapshotURL` immutable; adding default
  `storage.restoreSnapshotURL` after creation rejected.
- `restoreSnapshotURL` rejected on EmptyDir shards; URL scheme must be
  `https` or `s3`.
- Resource overlap across shards rejected; shard names DNS1123; replicas
  restricted to 1 or 3.
- On clusters without the TechPreview gate, shard/backup fields rejected
  (feature-gated CRD variants).

### TC-011: Non-sharded compatibility

**Steps:** run backup and restore on a plain single-shard HostedCluster.

**Expected:** backup uses `--snapshot-path` (single-shard backward-compat
flag); single init container `snapshot-etcd`; `status.snapshotURL` set;
restore via `storage.restoreSnapshotURL` restores guest data.

### TC-012: AWS KMS encryption

**Steps:** `HCPEtcdBackup` with `spec.storage.s3.kmsKeyARN`.

**Expected:** all shard objects report `aws:kms` with the expected key;
`status.encryptionMetadata.aws.kmsKeyARN` recorded.

### TC-013: OADp integration (environment-dependent)

**Steps:** with OADp 1.6+ in the catalog, trigger a Velero backup of the
hosted cluster.

**Expected:** OADp creates an `HCPEtcdBackup` covering all persistent shards;
TC-003 assertions apply. If the catalog only offers OADp ≤1.5.x, run the
direct `HCPEtcdBackup` path and record OADp as skipped.

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Older payload konnectivity binary rejects newer CPO flags; HC never becomes `Available` | Verify via HCP conditions and management-cluster port-forward instead of waiting for `Available` |
| OADp 1.6+ unavailable in catalog | Exercise the direct `HCPEtcdBackup` path (what OADp drives) and record the skip |
| Cross-cluster secret restore fails without the source encryption key | Port the `etcd-encryption-key` Secret as part of the DR runbook |
| Restore URLs immutable; scenario misconfiguration requires a new cluster | Use render + edit + apply; plan cluster lifecycle before starting |

## 7. Approvals

| Role | Name | Date |
|------|------|------|
| Author | jhjaggars | 2026-10-20 |
| Reviewer | | |
