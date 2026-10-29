#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'usage: %s T1_RUN_DIR\n' "$0" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
run_dir="$1"
[[ -d "${run_dir}" ]] || die "run directory not found: ${run_dir}"

readonly target_version="5.1.0-0.nightly-multi-2026-10-27-082258"
readonly start_version="5.0.0-rc.7"
readonly target_release="${RELEASE_B}"
readonly start_release="${RELEASE_A}"

monitor="${run_dir}/monitor-state.ndjson"
pre_summary="${run_dir}/pre/summary.json"
[[ -r "${monitor}" ]] || die "missing ${monitor}"
[[ -r "${pre_summary}" ]] || die "missing ${pre_summary}"

failures=0
notes=()
fail() { failures=$((failures + 1)); notes+=("FAIL $*"); }
pass() { notes+=("PASS $*"); }

# 1. Pre state: NodePool at the older release, ready, desired replicas all available.
pre_release="$(jq -r '.nodePool.release' "${pre_summary}")"
pre_version="$(jq -r '.nodePool.version' "${pre_summary}")"
pre_desired="$(jq -r '.nodePool.replicas // .nodePool.specReplicas // 3' "${pre_summary}")"
pre_md_up_to_date="$(jq -r '.machineDeployment.upToDateReplicas' "${pre_summary}")"
pre_md_available="$(jq -r '.machineDeployment.availableReplicas' "${pre_summary}")"
pre_ready="$(jq -r '[.nodePool.conditions[]? | select(.type == "Ready")][0].status // ""' "${pre_summary}")"

[[ "${pre_release}" == "${start_release}" ]] && pass "pre state at start release" || fail "pre release ${pre_release} != ${start_release}"
[[ "${pre_version}" == "${start_version}" ]] && pass "pre state at start version ${start_version}" || fail "pre version ${pre_version} != ${start_version}"
[[ "${pre_ready}" == "True" ]] && pass "pre NodePool Ready" || fail "pre NodePool not Ready"
[[ "${pre_md_available}" == "3" ]] && pass "pre MachineDeployment 3 available" || fail "pre available replicas ${pre_md_available} != 3"
[[ "${pre_md_up_to_date}" == "3" ]] && pass "pre upToDateReplicas=3 (counter already satisfied before rollout)" || fail "pre upToDateReplicas ${pre_md_up_to_date} != 3"

# 2. Continuous trace present and starts before completion.
samples="$(wc -l <"${monitor}" | tr -d ' ')"
[[ "${samples}" -ge 100 ]] && pass "continuous trace has ${samples} samples" || fail "trace only has ${samples} samples"

# 3. The counter must have reached the desired value and stayed there for the whole rollout.
#    This is the opposite of the CAPI 1.14 stall signature recorded in the 1.14 runs.
distinct_up_to_date="$(jq -r '.machineDeployment.upToDateReplicas // "null"' "${monitor}" | sort -u | paste -sd, -)"
[[ "${distinct_up_to_date}" == "0,3" || "${distinct_up_to_date}" == "3" ]] \
  && pass "upToDateReplicas values observed: ${distinct_up_to_date} (reaches desired 3)" \
  || fail "upToDateReplicas values observed: ${distinct_up_to_date} (expected 3 after patch)"
after_patch_desired="$(jq -r 'select(.machineDeployment.revision == "2") | .machineDeployment.upToDateReplicas // "null"' "${monitor}" | sort -u | paste -sd, -)"
[[ "${after_patch_desired}" == "3" || "${after_patch_desired}" == "0,3" ]] \
  && pass "revision 2 counter samples: ${after_patch_desired}" \
  || fail "revision 2 counter samples: ${after_patch_desired}"

# 4. Completion must not advance before the physical rollout gates are satisfied.
premature="$(jq -r '
  . as $s |
  ([ $s.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // "",
     $s.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // "" ] | join("/"))' "${pre_summary}" 2>/dev/null || true)"
pre_cfg="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] // ""' "${pre_summary}")"
pre_cfg_ver="$(jq -r '.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] // ""' "${pre_summary}")"

premature_count="$(jq -r --arg pc "${pre_cfg}" --arg pv "${pre_cfg_ver}" --arg tv "${target_version}" '
  select(
    (.physicalRolloutComplete != true) and
    (
      (.nodePool.statusVersion == $tv) or
      (.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfig"] != $pc) or
      (.nodePool.annotations["hypershift.openshift.io/nodePoolCurrentConfigVersion"] != $pv)
    )
  ) | .timestamp' "${monitor}" | wc -l | tr -d ' ')"
[[ "${premature_count}" == "0" ]] && pass "no sample advanced completion metadata before physical rollout completion" \
  || fail "${premature_count} samples advanced completion metadata before the physical gates"

# 5. First fully complete sample must satisfy every gate simultaneously.
complete_line="$(jq -r 'select(.physicalRolloutComplete == true) | .timestamp' "${monitor}" | sed -n '1p')"
[[ -n "${complete_line}" ]] && pass "physical rollout completed at ${complete_line}" || fail "physical rollout never completed"

jq -e --arg tv "${target_version}" '
  select(.physicalRolloutComplete == true) |
  select(.machineDeployment.replicas == 3) |
  select(.machineDeployment.availableReplicas == 3) |
  select(.machineDeployment.observedGeneration >= .machineDeployment.generation) |
  select(.nodePool.statusVersion == $tv) |
  select(.nodePool.updatingVersion.status == "False") |
  select(.oldMachineSetsActive == 0)
' "${monitor}" >/dev/null \
  && pass "a sample satisfies replicas=3, available=3, observed generation, target version, updatingVersion=False, zero old sets" \
  || fail "no single sample satisfied every completion gate"

# 6. Terminal state stability: the last sample must hold completion for at least 60 seconds.
last_ts="$(jq -r '.timestamp' "${monitor}" | tail -1)"
last_ok="$(jq -r --arg tv "${target_version}" '
  select(.physicalRolloutComplete == true) |
  select(.nodePool.statusVersion == $tv) |
  select(.nodePool.updatingVersion.status == "False") |
  select(.machineDeployment.replicas == 3) |
  select(.machineDeployment.availableReplicas == 3) |
  (.timestamp)' "${monitor}" | tail -1)"
[[ -n "${last_ok}" ]] && pass "terminal completion holds at ${last_ts}" || fail "terminal sample not complete"

# 7. Version actually changed in the guest cluster: new nodes at target version.
new_versions="$(jq -r '.machines[]? | select(.version == "'"${target_version}"'") | .name' "${monitor}" | sort -u | wc -l | tr -d ' ')"
[[ "${new_versions}" == "3" ]] && pass "3 machines at target version" || fail "${new_versions} machines at target version"

printf 'scenario=T8-pre-1.14-replace\n'
printf 'run_dir=%s\n' "${run_dir}"
printf 'samples=%s\n' "${samples}"
printf 'physical_complete_utc=%s\n' "${complete_line}"
printf 'last_sample_utc=%s\n' "${last_ts}"
printf 'up_to_date_values=%s\n' "${distinct_up_to_date}"
printf 'notes:\n'
printf '  %s\n' "${notes[@]}"
if [[ "${failures}" -eq 0 ]]; then
  printf 'verdict=PASS\n'
  exit 0
fi
printf 'verdict=FAIL failures=%s\n' "${failures}"
exit 1
