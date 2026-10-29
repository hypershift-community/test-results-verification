# CNTRLPLANE-4826 Retest Automation

Task-specific scripts for the CNTRLPLANE-4826 retest only.

Rules:

- Do not modify surrounding Azure helper scripts.
- Use only `/home/tester/management.kubeconfig`.
- Reuse the existing HostedCluster and Azure infrastructure.
- Switch the management operator by immutable image digest.
- Create and delete only named test NodePools.
- Never mutate Azure resource groups, DNS records, DNS zones, or role assignments.
- Never run a `destroy_hc.sh` or `hypershift destroy` command.
- Treat 12 minutes without a Machine joining as a hard failure.

The implementation scripts will be added here before execution and validated with shellcheck/dry-run checks where applicable.
