#!/usr/bin/env bash
# run.sh — link#478's scratch re-models: groups holding a moved PSCIS pick or
# CABD dam, built once at main and once at the branch, under both configs, on
# the local docker fwapg. Scratch schemas only (zz478_build_<step>_<config>).
#
# Usage: [WSGS="..."] [CONFIGS="..."] bash run.sh <before|after|parity> <link worktree>
#
# before/after build WSGS (default: the seven groups below) under CONFIGS
# (default: default bcfishpass) into zz478_build_<step>_<config>. parity
# builds the bcfishpass-config closure link#321's parity reads (ADMS and BULK,
# MORR upstream of BULK, and their downstream groups, downstream first) into
# zz478_parity.
#
# Run the two steps one after the other, never at once: a build works in
# working_<wsg>, which both steps share.
#
# Each group by wsg_run_one.R under load_all from <worktree>, the downstream
# guard off with a note (the same in both steps; both sides lack the same
# downstream groups, so the comparison is like for like), the habitat gate at
# model time, no recompute. Another session was using the database, so there
# is no quiet gate; each row records the host's load. Logs to
# <dir>/<step>_<config>_<WSG>.log and a row in <dir>/status_<step>_<configs>.tsv.
set -uo pipefail
STEP="$1"; WT="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
WSGS="${WSGS:-NASR SHUL JERV KETL LILL GUIC USHU}"
CONFIGS="${CONFIGS:-default bcfishpass}"
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }
case "$STEP" in
  before|after) ;;
  parity) WSGS="LFRA HARR FRCN THOM STHM ADMS LSKE KLUM KISP BULK MORR"; CONFIGS="bcfishpass" ;;
  *) echo "step must be before, after or parity" >&2; exit 2 ;;
esac
STATUS="$DIR/status_${STEP}_$(echo $CONFIGS | tr ' ' '_').tsv"
echo "[run] $(stamp) $STEP: link $(git -C "$WT" rev-parse HEAD) dirty=$(git -C "$WT" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
printf 'step\tconfig\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"
for config in $CONFIGS; do
  for wsg in $WSGS; do
    log="$DIR/${STEP}_${config}_${wsg}.log"; s=$(stamp); l0=$(loadavg)
    ( cd "$WT" || exit 1
      LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=ignore \
        LNK_GUARD_DOWNSTREAM_NOTE="link#478 scratch proof: main and branch builds of the same groups" \
        LNK_RUN_UID="478_${STEP}" LNK_RUN_LABEL="478_${STEP}_${config}_${wsg}" \
        LNK_SCHEMA="$( [ "$STEP" = parity ] && echo zz478_parity || echo "zz478_build_${STEP}_${config}" )" \
        Rscript data-raw/wsg_run_one.R "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$STEP" "$config" "$wsg" "$s" "$(stamp)" "$rc" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $(stamp) $STEP $config $wsg exit=$rc"
  done
done
echo "[run] $(stamp) RUN478_${STEP}_DONE"
