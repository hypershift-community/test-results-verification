# CNTRLPLANE-3927 — Live propagation results (template)

Date:  Cluster: mgmt (OCP …)  HC: `clusters/<HC_NAME>` (…, 2 nodes)  Branch/commit: `CNTRLPLANE-3927` @ `<commit>`  Run by:

Keep table cells to one line. Put command output in the **Evidence** section below, under the matching step,
inside a fenced code block. Never paste kubeconfigs, the pull secret or keys.

**Verdict:** _(filled by the verification session, `VERIFY.md`)_

| Step | Item | Result | Notes / exact values |
|------|------|--------|----------------------|
| 0 | Clean tree at the commit under test; binaries built; dry run selects 2 specs | | |
| 0 | Preflight (ns absent, no HC, CLI/HO versions, copier image digest, AWS identity, public zone, pull secret, headroom) | | |
| 1 | `create-guests` exit 0, `All clusters are ready` (plan `image-mirroring-propagation`, one cluster) | | |
| 1 | `check.sh fixture` 12/12 (SHARED_DIR files, manifest, Route, ICS, registry, CA, laptop TLS, Keycloak) | | |
| 1 | `check.sh hc` 4/4 (ICS == fixture, trust bundle == CA, Available, rollout Completed) | | |
| 2 | `run-tests`: 2 specs ran, 2 passed, `All test groups passed` | | |
| 2 | Two `Successfully waited for` lines (hosted IDMS; HCP ConfigMap) | | |
| 2 | `check.sh junit` 6/6 (2 testcases passed, no skip/failure, DryRun=false) | | |
| 3 | `check.sh guest` 5/5 (hosted IDMS: GVK/name, worker label, mappings == HC) | | |
| 3 | `check.sh cm` 6/6 (CM core label, payload GVK/name, worker label, mappings == HC) | | |
| 3 | CPO / HCCO images (producers exercised) | | |
| 4 | (opt.) Repeat `run-tests`: 2 passed; `check.sh junit` 6/6 | | |
| 6 | `destroy-guests` exit 0; `clusters` ns removed; Keycloak + mirror ns deleted | | |
| 6 | `check.sh clean` 7/7 (no HC/HCP/ns/PV/VPC/instances left) | | |
| 6b | S3 OIDC docs, public DNS records, KAS ELB (classic + v2): all queries empty | | |

## Problems found

| # | Step | Symptom | Root cause | Action |
|---|------|---------|------------|--------|

## Surprises / follow-ups

-

## Evidence

### Step 0 — git, build, dry run, preflight

```text
```

### Step 1 — create-guests (grep + tail of create.log), check.sh fixture, check.sh hc, ics.yaml, HC/NodePool

```text
```

### Step 2 — run-tests (grep of run-tests.log), check.sh junit

```text
```

### Step 3 — guest nodes, check.sh guest, check.sh cm, HC spec, IDMS yaml, CM payload, CPO/HCCO images

```text
```

### Step 4 — repeat run-tests, check.sh junit

```text
```

### Step 5 — diagnostics (only if something failed)

```text
```

### Step 6 — destroy-guests (tail of destroy.log), leftovers, namespace deletion, check.sh clean

```text
```

### Step 6b — leftover identifiers and S3/Route53/ELB queries

```text
```
