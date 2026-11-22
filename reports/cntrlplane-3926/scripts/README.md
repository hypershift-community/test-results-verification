# Reproduction kit — CNTRLPLANE-3926 mirror registry fixture

These are the runbooks, scripts and manifests used for the three scenarios of this report. They are sanitized,
and they differ from the originals only by the minimal changes listed in `appendices.html` (section "Kit changes").
Context, domain and paths come from environment variables instead of being hard-coded.

| Scenario | Directory | What it needs |
|----------|-----------|---------------|
| 1 — Smoke (design validation) | `smoke/` | OpenShift management cluster |
| 2 — Harness (fixture code) | `harness/` | OpenShift management cluster, a hypershift checkout |
| 3 — Reachability (hosted nodes) | `reachability/` (+ `harness/`) | Above, plus the HyperShift operator, AWS account, public Route53 zone, pull secret |

## Prerequisites

- An **OpenShift** management cluster (4.20 was used) and a kubeconfig context for it. You need permission to create a
  namespace, a PVC (default StorageClass), Deployments, Jobs, Secrets, ConfigMaps and Routes, and to read
  `ingresses.config.openshift.io/cluster`, the `openshift/cli` ImageStream and `clusterversion/version`.
  The management-cluster ingress must be reachable from where you run the checks (and, for scenario 3, from the hosted cluster's worker VPC).
- Tools: `oc`, `go` (version from `go.mod`), `jq`, `yq`, `openssl`, `curl`, `skopeo`, `envsubst`;
  scenario 3 also needs `hypershift` and `aws`; smoke step 11 (optional) needs `podman` and a `registry.ci.openshift.org` login.
- A checkout of [openshift/hypershift](https://github.com/openshift/hypershift) at the PR head (`8d54f7ab32`) or any
  later commit that contains `test/e2e/v2/util/mirrorregistry`.

## Install

```bash
cd <hypershift checkout>
cp -r <this directory> .work/cntrlplane-3926        # .work/ is gitignored in the hypershift repository
export CTX=<kubeconfig context of the management cluster>
# scenario 3 only:
export BASE_DOMAIN=<public Route53 zone> AWS_REGION=<region> AWS_CREDS=<credentials file> PULL_SECRET=<pull secret file>
```

Then follow `smoke/RUNBOOK.md`, `harness/RUNBOOK.md` and `reachability/RUNBOOK.md`, in that order. All commands are run from
the repository root. To verify somebody else's evidence instead of re-running, use `reachability/VERIFY.md`.
It is a read-only checklist and needs no cluster.

## Notes

- Expected values in the runbooks come from the original run, after sanitization (`mgmt`, `hypershift.example.com`,
  account `123456789012`). Compare their shape, not the literal values: hostnames, fingerprints, durations and infra IDs will differ.
- `*/out/` directories are created at run time. They contain CA private keys and kubeconfigs: never share them.
- Scenario 3 creates real AWS resources (VPC, NAT gateway, 2 instances). Step 8 removes them. Cost is about 1.5 hours of 2 workers plus a NAT gateway.
- Runbook titles and notes mention internal task IDs (T0–T9); see the glossary in `appendices.html`.
