# ARO-30375 verification report

Verification of openshift/hypershift PR #10118 (idempotent etcd member reset
and recovery) against test plan TP-ARO-30375-001 v1.1, executed 2026-11-12 at
head commit 1e771d57285f5c8fd0d2115eae9839e3be476085 in an ARO-HCP personal
dev environment.

Verdict: PASS, 8/8 test cases. Start at index.html. TC-007 documents two
environment deviations (partial hosted control plane due to a pre-existing
main/GA-payload TLS flag incompatibility, and the port-forward client
adaptation for the marker specs); neither reduces etcd coverage.

All evidence under assets/evidence/ is sanitized; see
assets/provenance/sanitization.json and scripts/sanitize-evidence.sh.
