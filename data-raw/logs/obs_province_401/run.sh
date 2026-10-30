#!/usr/bin/env bash
# run.sh — #401 builds before and after, on m1's local fwapg, scratch schemas
# only (never fresh or fresh_default).
#
# 1. Waits until no other client has run a query on the database for five
#    consecutive minutes, or three hours have passed (PGPASSWORD is set: psql
#    on m1 reads the docker password from nowhere else, and a probe that
#    always fails reads every minute as busy).
# 2. `default`: LKEL, BULK, UPCE, PARS, ELKR, LNTH, BEFORE (PRE worktree, the
#    branch point) into zz401_default_pre and AFTER (POST worktree) into
#    zz401_default_post, back to back per group. UPCE runs before PARS, which
#    drains through it.
# 3. `bcfishpass`: BULK, PARS, UPCE the same way into zz401_bcfishpass_{pre,post}.
# AFTER reads fresh from <fresh lib>, a library holding only the fresh that
# carries frs_network_features(result = "distinct") (fresh#284); BEFORE reads
# the shared library's fresh 0.47.0.
# No recompute: lnk_access() passes no observations and keeps a prior 2.
# bcfishobs.observations is counted before and after (bcfishobs.txt), since
# the check reads it rebuilt.
# Each step logs to <dir>/<step>_<WSG>.log and a row in <dir>/status.tsv. A
# failed step is retried once and the run goes on.
#
# Usage: bash run.sh <PRE worktree> <POST worktree> <fresh lib>
set -uo pipefail
PRE="$1"; POST="$2"; FRESH_LIB="$3"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/status.tsv"
export PGPASSWORD=postgres
psqlq() { psql -w -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }
obs_state() { psqlq "SELECT count(*), md5(string_agg(observation_key::text, ',' ORDER BY observation_key)) FROM bcfishobs.observations"; }

printf 'step\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"
echo "before $(stamp) $(obs_state)" > "$DIR/bcfishobs.txt"

echo "[run] $(stamp) waiting for a quiet database"
quiet=0; waited=0
while [ "$quiet" -lt 5 ] && [ "$waited" -lt 180 ]; do
  n=$(psqlq "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg'
             AND state <> 'idle' AND backend_type = 'client backend'
             AND pid <> pg_backend_pid()") || n=1
  if [ "$n" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
  [ "$quiet" -lt 5 ] && { sleep 60; waited=$((waited + 1)); }
done
echo "[run] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

run() {  # run <step> <worktree> <wsg> <config> <schema> <R_LIBS or empty>
  local step="$1" wt="$2" wsg="$3" config="$4" schema="$5" libs="$6"
  local log="$DIR/${step}_${wsg}.log" s e rc try l0
  for try in 1 2; do
    s=$(stamp); l0=$(loadavg)
    ( cd "$wt" || exit 1
      [ -n "$libs" ] && export R_LIBS="$libs"
      LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="401_${step}" LNK_RUN_LABEL="401_${step}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript data-raw/wsg_run_one.R "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$step" "$wsg" "$s" "$e" "$rc" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $e $step $wsg exit=$rc (try $try)"
    [ "$rc" -eq 0 ] && return 0
  done
  return 1
}

for w in LKEL BULK UPCE PARS ELKR LNTH; do
  run default_pre "$PRE" "$w" default zz401_default_pre ""
  run default_post "$POST" "$w" default zz401_default_post "$FRESH_LIB"
done
for w in BULK UPCE PARS; do
  run bcfishpass_pre "$PRE" "$w" bcfishpass zz401_bcfishpass_pre ""
  run bcfishpass_post "$POST" "$w" bcfishpass zz401_bcfishpass_post "$FRESH_LIB"
done

echo "after $(stamp) $(obs_state)" >> "$DIR/bcfishobs.txt"
echo "[run] $(stamp) RUN401_DONE"
