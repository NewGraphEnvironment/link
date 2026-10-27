#!/usr/bin/env bash
# run_phase4.sh — #326 Phase 4 re-models on m4's local fwapg (dev state only).
#
# 1. Waits until no other session's `pcic` load has run on the database for
#    five minutes (a concurrent load stalled PARS's access walk past 2 h;
#    CLAUDE.md, OKAN), or three hours have passed.
# 2. `default` BEFORE: PCEA, FINA, PARS, LKEL at main (PRE worktree) into the
#    scratch schema zz326_default_pre, so `default` can be diffed against its
#    own pre-change build.
# 3. `default` AFTER: the same four at the branch (POST worktree) into
#    fresh_default.
# 4. `bcfishpass` AFTER: the 11 cross-section groups at the branch into fresh,
#    last, so each working_<wsg> holds the bcfishpass build breaks_diff.R reads.
# 5. The recompute (merge = TRUE) over each schema's groups.
# Each step logs to <dir>/<step>_<WSG>.log; a failed group is retried once and
# then named in <dir>/phase4_status.tsv, and the run goes on.
#
# Usage: bash run_phase4.sh <PRE worktree> <POST worktree>
set -uo pipefail
PRE="$1"; POST="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/phase4_status.tsv"
psqlq() { psql -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }

printf 'step\twsg\tstart_utc\tend_utc\texit\n' > "$STATUS"

echo "[phase4] $(stamp) waiting for a quiet database"
quiet=0; waited=0
while [ "$quiet" -lt 5 ] && [ "$waited" -lt 180 ]; do
  n=$(psqlq "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg'
             AND state = 'active' AND query ILIKE '%pcic%'
             AND pid <> pg_backend_pid()") || n=1
  if [ "$n" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
  sleep 60; waited=$((waited + 1))
done
echo "[phase4] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

run() {  # run <step> <worktree> <script> <wsg> <config> <schema>
  local step="$1" wt="$2" script="$3" wsg="$4" config="$5" schema="$6"
  local log="$DIR/${step}_${wsg}.log" s e rc try
  for try in 1 2; do
    s=$(stamp)
    ( cd "$wt" && LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="326_${step}" LNK_RUN_LABEL="326_${step}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript "data-raw/$script" "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp)
    printf '%s\t%s\t%s\t%s\t%s\n' "$step" "$wsg" "$s" "$e" "$rc" >> "$STATUS"
    echo "[phase4] $e $step $wsg exit=$rc (try $try)"
    [ "$rc" -eq 0 ] && return 0
  done
  return 1
}

FOUR="PCEA FINA PARS LKEL"
ELEVEN="LKEL BULK KISP USKE MORR PCEA FINA PARS LFRA KOTR ELKR"

for w in $FOUR; do run default_pre "$PRE" wsg_run_one.R "$w" default zz326_default_pre; done
for w in $FOUR; do run default_post "$POST" wsg_run_one.R "$w" default fresh_default; done
for w in $ELEVEN; do run bcfishpass_post "$POST" wsg_run_one.R "$w" bcfishpass fresh; done

for w in $FOUR; do run recompute_default_pre "$PRE" wsg_recompute_one.R "$w" default zz326_default_pre; done
for w in $FOUR; do run recompute_default_post "$POST" wsg_recompute_one.R "$w" default fresh_default; done
for w in $ELEVEN; do run recompute_bcfishpass_post "$POST" wsg_recompute_one.R "$w" bcfishpass fresh; done

echo "[phase4] $(stamp) PHASE4_DONE"
