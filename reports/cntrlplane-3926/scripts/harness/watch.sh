#!/usr/bin/env bash
# Records registry state transitions during Setup and checks the D4 invariant:
# the Route must never exist while the registry is (configured) writable.
#   watch.sh <logfile>      run in a second terminal; Ctrl-C to stop
# Prints a line only when the state changes. "VIOLATION" marks a broken invariant.
# The ConfigMap value is checked (not the running pod): it is written before the pod restarts,
# so it is the stricter signal for "writes are about to be enabled".
set -u
LOG="${1:?usage: watch.sh <logfile>}"
: "${CTX:?source env.sh first}" "${NS:?}" "${NAME:?}"
prev=""
while true; do
  json=$(oc --context "${CTX}" -n "${NS}" get route,configmap,deployment,job,pod -o json 2>/dev/null || echo '{"items":[]}')
  state=$(jq -r --arg n "${NAME}" '
    def one(k; nm): [.items[] | select(.kind == k and .metadata.name == nm)][0];
    (one("Route"; $n)) as $r
    | (one("ConfigMap"; $n + "-config")) as $c
    | (one("Deployment"; $n)) as $d
    | ($c.data["config.yml"] // "" | capture("readonly:\\s*\\n\\s*enabled: (?<v>\\w+)").v // "-") as $ro
    | ([.items[] | select(.kind == "Job") | .metadata.name + ":" + ((.status.conditions // []) | map(select(.status == "True") | .type) | join(",") | if . == "" then "Running" else . end)] | join(" ")) as $jobs
    | ([.items[] | select(.kind == "Pod" and .metadata.labels["app.kubernetes.io/name"] == $n) | .metadata.name[-5:] + ":" + .status.phase + (if .metadata.deletionTimestamp then "(terminating)" else "" end)] | join(" ")) as $pods
    | "route=" + (if $r == null then "none" else (if ($r.status.ingress // [] | map(.conditions // [] | map(select(.type == "Admitted" and .status == "True"))) | flatten | length) > 0 then "admitted" else "pending" end) end)
      + " readonly=" + $ro
      + " deploy=" + (if $d == null then "none" else "gen\($d.metadata.generation)/obs\($d.status.observedGeneration // 0)/avail\($d.status.availableReplicas // 0)" end)
      + " pods=[" + $pods + "] jobs=[" + $jobs + "]"
      + (if $r != null and $ro == "false" then "  VIOLATION" else "" end)
  ' <<<"${json}")
  if [ "${state}" != "${prev}" ]; then
    echo "$(date +%H:%M:%S) ${state}" | tee -a "${LOG}"
    prev="${state}"
  fi
  sleep 1
done
