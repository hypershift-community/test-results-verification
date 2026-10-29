# Round 5 harness

These are the scripts used for the CAPI v1.13.4 run, copied from the private
run folder and sanitized. Differences from `scripts/harness/`:

- `common.sh` points at the round-5 evidence root, cluster name, infra ID and
  NodePool names, and pins `CAPI_IMAGE` to
  `registry.k8s.io/cluster-api/cluster-api-controller:v1.13.4`.
- `nodepool-template.json` uses the round-5 cluster name.
- `snapshot.sh` filters guest nodes by the `hypershift.openshift.io/nodePool`
  annotation, which fixes the round-4 cross-pool count.
- `verify-t8.sh` is new. It evaluates a round-5 T1 run directory with the
  pre-1.14 expectations and exits non-zero on any failed check.

`run-t1.sh patched` still encodes the CAPI 1.14 stall signature
(`upToDateReplicas == 0`) as its success gate. It cannot pass on 1.13.4 and is
used only to produce the trace, final snapshot and logs. `verify-t8.sh` is the
verdict authority for the round-5 scenario.
