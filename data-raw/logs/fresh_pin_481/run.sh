#!/usr/bin/env bash
# run.sh — #481's builds before and after the fresh pin moves (0.52.0 to
# 0.55.1), on m1's local fwapg, scratch schemas only (never fresh,
# fresh_default or fresh_default_minimal).
#
# Usage: bash run.sh <before|after> <link worktree> <R library holding fresh alone> <fresh sha>
#
# 1. Refuses unless the library's fresh is the version the step names, then
#    waits until no other client has run a query on the database for five
#    consecutive minutes, or an hour has passed.
# 2. `default` into fresh_pin481_<step>: ADMS, BULK.
#    `bcfishpass` into fresh_pin481_bcfp_<step>: ADMS.
# Each group from <worktree> by wsg_run_one.R under load_all with
# R_LIBS=<library> (fresh from it, everything else from the shared library),
# the downstream guard off with a note (the same in both steps), the habitat
# gate at model time, no recompute. The library is installed with
# `R CMD INSTALL -l`, which writes no RemoteSha, so FRESH_GIT_SHA carries the
# tag's commit into the stamps. Each group logs to <dir>/<step>_<config>_<WSG>.log
# and a row in <dir>/status_<step>.tsv. A failed step is retried once.
set -uo pipefail
STEP="$1"; WT="$2"; LIB="$3"; FSHA="$4"
DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$DIR/status_${STEP}.tsv"
export PGPASSWORD=postgres
psqlq() { psql -w -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }

case "$STEP" in
  before) want=0.52.0 ;;
  after)  want=0.55.1 ;;
  *) echo "step must be before or after" >&2; exit 2 ;;
esac
got=$(R_LIBS="$LIB" Rscript -e 'cat(as.character(packageVersion("fresh")))')
[ "$got" = "$want" ] || { echo "[run] fresh under R_LIBS is $got, want $want" >&2; exit 2; }
echo "[run] $(stamp) $STEP: link $(git -C "$WT" rev-parse HEAD), fresh $got ($FSHA)"

printf 'step\tconfig\twsg\tstart_utc\tend_utc\texit\tload_start\tload_end\n' > "$STATUS"

echo "[run] $(stamp) waiting for a quiet database"
quiet=0; waited=0
while [ "$quiet" -lt 5 ] && [ "$waited" -lt 60 ]; do
  n=$(psqlq "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg'
             AND state <> 'idle' AND backend_type = 'client backend'
             AND pid <> pg_backend_pid()") || n=1
  if [ "$n" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
  [ "$quiet" -lt 5 ] && { sleep 60; waited=$((waited + 1)); }
done
echo "[run] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

run() {  # run <config> <wsg>
  local config="$1" wsg="$2" schema log s e rc try l0
  if [ "$config" = default ]; then schema="fresh_pin481_${STEP}"; else schema="fresh_pin481_bcfp_${STEP}"; fi
  log="$DIR/${STEP}_${config}_${wsg}.log"
  for try in 1 2; do
    s=$(stamp); l0=$(loadavg)
    ( cd "$WT" || exit 1
      R_LIBS="$LIB" FRESH_GIT_SHA="$FSHA" LNK_LOAD=loadall \
        LNK_GUARD_DOWNSTREAM=ignore \
        LNK_GUARD_DOWNSTREAM_NOTE="link#481 scratch proof: before and after builds of the same groups" \
        LNK_RUN_UID="481_${STEP}" LNK_RUN_LABEL="481_${STEP}_${config}_${wsg}" \
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

run default ADMS
run default BULK
run bcfishpass ADMS

echo "[run] $(stamp) RUN481_${STEP}_DONE"
