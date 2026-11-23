#!/usr/bin/env bash
# run.sh — link#478's scratch re-models: groups holding a moved PSCIS pick or
# CABD dam, built once at main and once at the branch, under both configs, on
# the local docker fwapg. Scratch schemas only (zz478_build_<step>_<config>).
#
# Usage: bash run.sh <before|after> <link worktree>
#
# Each group by wsg_run_one.R under load_all from <worktree>, the downstream
# guard off with a note (the same in both steps; both sides lack the same
# downstream groups, so the comparison is like for like), the habitat gate at
# model time, no recompute. Another session was using the database, so there
# is no quiet gate; each row records the host's load. Logs to
# <dir>/<step>_<config>_<WSG>.log and a row in <dir>/status_<step>.tsv.
set -uo pipefail
STEP="$1"; WT="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/status_${STEP}.tsv"
WSGS="NASR SHUL JERV KETL LILL GUIC USHU"
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }
case "$STEP" in before|after) ;; *) echo "step must be before or after" >&2; exit 2 ;; esac
echo "[run] $(stamp) $STEP: link $(git -C "$WT" rev-parse HEAD) dirty=$(git -C "$WT" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
printf 'step\tconfig\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"
for config in default bcfishpass; do
  for wsg in $WSGS; do
    log="$DIR/${STEP}_${config}_${wsg}.log"; s=$(stamp); l0=$(loadavg)
    ( cd "$WT" || exit 1
      LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=ignore \
        LNK_GUARD_DOWNSTREAM_NOTE="link#478 scratch proof: main and branch builds of the same groups" \
        LNK_RUN_UID="478_${STEP}" LNK_RUN_LABEL="478_${STEP}_${config}_${wsg}" \
        LNK_SCHEMA="zz478_build_${STEP}_${config}" \
        Rscript data-raw/wsg_run_one.R "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$STEP" "$config" "$wsg" "$s" "$(stamp)" "$rc" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $(stamp) $STEP $config $wsg exit=$rc"
  done
done
echo "[run] $(stamp) RUN478_${STEP}_DONE"
