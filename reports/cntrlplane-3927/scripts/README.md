# Reproduction kit — CNTRLPLANE-3927 image-content-source propagation tests

These are the runbook, check script, environment file, test plan and review checklist used for the live scenario of
this report. They are sanitized and differ from the originals only by the changes listed in `appendices.html`
(section "Kit changes"): inputs come from environment variables, the runbook fixes found during the run are applied,
the step 6b leftover queries are included, and a blank `RESULTS.template.md` is added.

| Scenario | Directory | What it needs |
|----------|-----------|---------------|
| 1 — Propagation (live lifecycle run) | `propagation/` | OpenShift management cluster with the HyperShift operator, AWS account, public Route53 zone, pull secret, a hypershift checkout with the tests |

## Prerequisites

- An **OpenShift** management cluster with the **HyperShift operator** installed (4.20 management cluster and operator
  `e83d9072…` were used; the operator must support the release you create), and a kubeconfig context for it. The
  `create-guests` step deploys the mirror fixture and Keycloak there (namespaces `test-mirror-registry`, `keycloak`) and
  creates the HostedCluster in `clusters`, so those namespaces must not exist.
- The management-cluster ingress must be reachable from your workstation (`check.sh fixture` curls the mirror) and from
  the hosted cluster's worker VPC.
- AWS credentials (default profile of a credentials file, used through the SDK default chain as in CI), a **public**
  Route53 zone, and a pull secret with `quay.io` access.
- Tools: `oc`, `go` (version from `go.mod`), `make`, `jq`, `yq` (v4), `xmllint`, `openssl`, `curl`, `aws`; `bash` or `zsh`.
- A checkout of [openshift/hypershift](https://github.com/openshift/hypershift) containing
  `test/e2e/v2/tests/hosted_cluster_image_mirroring_test.go` (commit `c9ad656db6` on top of #9996 was used) and the
  CNTRLPLANE-3926 lifecycle wiring (`HYPERSHIFT_E2E_IMAGE_MIRRORING`, variant `image-mirroring`).

## Install

```bash
cd <hypershift checkout>
mkdir -p .work/cntrlplane-3927
cp -r <this directory>/propagation .work/cntrlplane-3927/   # .work/ is gitignored in the hypershift repository
export CTX=<kubeconfig context of the management cluster>
export BASE_DOMAIN=<public Route53 zone> AWS_REGION=<region> AWS_CREDS=<credentials file> PULL_SECRET=<pull secret file>
# optional: RELEASE_IMAGE (default 4.20.0), NODE_COUNT (default 2), PROW_JOB_ID (determines the HostedCluster name)
```

Then follow `propagation/RUNBOOK.md` from the repository root, filling a copy of `propagation/RESULTS.template.md`.
To verify somebody else's evidence instead of re-running, use `propagation/VERIFY.md`: a read-only checklist that
needs no cluster.

## Notes

- Expected values in the runbook and `VERIFY.md` come from the original run, after sanitization (`mgmt`,
  `hypershift.example.com`, account `123456789012`). Compare their shape, not the literal values: hostnames, the
  HostedCluster name (`image-mirroring-<sha256(PROW_JOB_ID)[:10]>`), digests and durations will differ.
- `propagation/out/` is created at run time. It contains kubeconfigs, the fixture CA, logs and the optional
  `dump-guests` output: never share it.
- The run creates real AWS resources (VPC, NAT gateway, 2 workers, IAM roles, OIDC provider, Route53 private zones).
  Step 6 removes them; step 6b confirms what `check.sh clean` does not cover. The original run took about 50 minutes
  end to end.
- Titles and notes mention internal task IDs (T8, V1–V6, D1–D10, I1/R1); see the glossary in `appendices.html`.
