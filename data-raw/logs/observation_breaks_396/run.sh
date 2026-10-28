#!/usr/bin/env bash
# run.sh — #396 Phase 4 re-models on m4's local fwapg (dev state only).
#
# 1. Waits until no other session's `pcic` load has run on the database for
#    five minutes (a concurrent load stalled PARS's access walk past 2 h;
#    CLAUDE.md, OKAN), or three hours have passed.
# 2. `default` BEFORE: LKEL, BULK, UPCE, PARS, ELKR at main (PRE worktree)
#    into the scratch schema zz396_default_pre (every observation breaks).
# 3. `default` AFTER: the same five at the branch (POST worktree) into
#    zz396_default_post (each species' top observation per line breaks).
# 4. `bcfishpass` AFTER: BULK and PARS at the branch into fresh, last, so each
#    working_<wsg> holds the bcfishpass build breaks_diff.R reads; it must
#    match #326's round 2 (BULK 42,989 and PARS 43,776 segments).
# 5. The recompute (wsg_recompute_one.R always merges) over each schema's
#    groups. In the dev schemas it fails on its last step, the downstream-dam
#    post-condition, after its work has committed (groups below each are not
#    held); that is the expected outcome and the pass rule.
# Each step logs to <dir>/<step>_<WSG>.log and a row in <dir>/status.tsv. A
# failed model step is retried once and the run goes on. A recompute is not
# retried: its expected post-condition failure would re-run the whole
# recompute and double its minutes.
#
# Usage: bash run.sh <PRE worktree> <POST worktree>
set -uo pipefail
PRE="$1"; POST="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/status.tsv"
psqlq() { psql -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }

printf 'step\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }

echo "[run] $(stamp) waiting for a quiet database"
quiet=0; waited=0
while [ "$quiet" -lt 5 ] && [ "$waited" -lt 180 ]; do
  n=$(psqlq "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg'
             AND state = 'active' AND query ILIKE '%pcic%'
             AND pid <> pg_backend_pid()") || n=1
  if [ "$n" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
  sleep 60; waited=$((waited + 1))
done
echo "[run] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

run() {  # run <step> <worktree> <script> <wsg> <config> <schema> [tries]
  local step="$1" wt="$2" script="$3" wsg="$4" config="$5" schema="$6"
  local tries="${7:-2}"
  local log="$DIR/${step}_${wsg}.log" s e rc try l0
  for try in $(seq 1 "$tries"); do
    s=$(stamp); l0=$(loadavg)
    ( cd "$wt" && LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="396_${step}" LNK_RUN_LABEL="396_${step}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript "data-raw/$script" "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$step" "$wsg" "$s" "$e" "$rc" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $e $step $wsg exit=$rc (try $try)"
    [ "$rc" -eq 0 ] && return 0
  done
  return 1
}

# UPCE is built for question 3 only (its FISS sites give visits without fish);
# it drains below PARS, so it runs first and both builds read the same rows.
FIVE="LKEL BULK UPCE PARS ELKR"
TWO="BULK PARS"

# BEFORE and AFTER of each group run back to back, so both sides of a timing
# see the same load from any other session on this host (status.tsv records
# the 1-minute load average at each step's start and end).
for w in $FIVE; do
  run default_pre "$PRE" wsg_run_one.R "$w" default zz396_default_pre
  run default_post "$POST" wsg_run_one.R "$w" default zz396_default_post
done
for w in $TWO; do run bcfishpass_post "$POST" wsg_run_one.R "$w" bcfishpass fresh; done

for w in $FIVE; do
  run recompute_default_pre "$PRE" wsg_recompute_one.R "$w" default zz396_default_pre 1
  run recompute_default_post "$POST" wsg_recompute_one.R "$w" default zz396_default_post 1
done
for w in $TWO; do run recompute_bcfishpass_post "$POST" wsg_recompute_one.R "$w" bcfishpass fresh 1; done

echo "[run] $(stamp) RUN396_DONE"
