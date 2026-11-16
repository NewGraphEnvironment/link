#!/usr/bin/env bash
# run.sh — #470 builds before or after the record rule, on m1's local fwapg,
# scratch schemas only (never fresh or fresh_default).
#
# Usage: bash run.sh <pre|post> <worktree>
#
# 1. Waits until no other client has run a query on the database for five
#    consecutive minutes, or three hours have passed.
# 2. `default` into zz470_default_<step>: LSKE, KLUM (drains into LSKE), SQAM,
#    HOMA, VICT, MFRA, UFRT, FINA.
# 3. `bcfishpass` into zz470_bcfishpass_<step>: BULK, PARS, SQAM.
# Each group from <worktree> by wsg_run_one.R under load_all, the habitat gate
# at model time, no recompute. Each step logs to <dir>/<step>_<config>_<WSG>.log
# and a row in <dir>/status_<step>.tsv. A failed step is retried once.
set -uo pipefail
STEP="$1"; WT="$2"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/status_${STEP}.tsv"
export PGPASSWORD=postgres
psqlq() { psql -w -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }
obs_state() { psqlq "SELECT count(*), md5(string_agg(observation_key::text, ',' ORDER BY observation_key)) FROM bcfishobs.observations"; }

printf 'step\tconfig\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"
echo "$STEP start $(stamp) $(git -C "$WT" rev-parse HEAD) $(obs_state)" >> "$DIR/bcfishobs.txt"

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

run() {  # run <config> <wsg>
  local config="$1" wsg="$2" schema="zz470_$1_${STEP}"
  local log="$DIR/${STEP}_${config}_${wsg}.log" s e rc try l0
  for try in 1 2; do
    s=$(stamp); l0=$(loadavg)
    ( cd "$WT" || exit 1
      LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="470_${STEP}" LNK_RUN_LABEL="470_${STEP}_${config}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript data-raw/wsg_run_one.R "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$STEP" "$config" "$wsg" "$s" "$e" "$rc" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $e $STEP $config $wsg exit=$rc (try $try)"
    [ "$rc" -eq 0 ] && return 0
  done
  return 1
}

for w in LSKE KLUM SQAM HOMA VICT MFRA UFRT FINA; do run default "$w"; done
for w in BULK PARS SQAM; do run bcfishpass "$w"; done

echo "$STEP end $(stamp) $(obs_state)" >> "$DIR/bcfishobs.txt"
echo "[run] $(stamp) RUN470_${STEP}_DONE"
