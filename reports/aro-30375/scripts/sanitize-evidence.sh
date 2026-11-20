#!/usr/bin/env bash
# Sanitizes ARO-30375 validation evidence for publication.
# Replaces private registry hosts, DNS zones, namespaces, node names,
# subscription IDs, resource groups and local paths with placeholders.
# The literals below were removed before publication; substitute the real
# values from the private run folder when re-running.
# Usage: sanitize-evidence.sh <input> <output>
set -euo pipefail
in="$1"; out="$2"
sed -e 's/\x1b\[[0-9;]*m//g' \
    -e 's|<HC-NAMESPACE-LITERAL>|ocm-arohcppers-REDACTED|g' \
    -e 's|<SUBSCRIPTION-ID-LITERAL>|<subscription-id>|g' \
    -e 's|<DEV-REGISTRY-LITERAL>|<dev-registry>.azurecr.io|g' \
    -e 's|<SVC-REGISTRY-LITERAL>|<svc-registry>.azurecr.io|g' \
    -e 's|api-int\.cluster\.<CLUSTER-DNS-LITERAL>|api-int.cluster.<cluster-id>|g' \
    -e 's|<REGION-ACCOUNT-LITERAL>|<region-account>|g' \
    -e 's|<MGMT-KUBECONFIG-LITERAL>|<mgmt-kubeconfig>|g' \
    -e 's|/home/<USER>|/home/<user>|g' \
    -e 's|<USER>/hypershift|<user>/hypershift|g' \
    -e 's|aks-userswft[0-9]-[0-9]*-vmss[0-9]*|mgmt-node|g' \
    -e 's|<RESOURCE-GROUP-LITERAL>|<resource-group>|g' \
    -e 's|<ARM-CLUSTER-NAME-LITERAL>|<arm-cluster-name>|g' \
    -e 's|\b10\.128\.[0-9]\+\.[0-9]\+\b|10.128.x.x|g' \
    -e 's|\b10\.130\.[0-9]\+\.[0-9]\+\b|10.130.x.x|g' \
    "$in" > "$out"
