#!/usr/bin/env bash
# run.sh — #463: each group built under `default` into a scratch control schema
# and under `default_parent` into fresh_default_parent, from one commit, on the
# local fwapg (m4, which holds fresh_default, fresh_default_minimal and
# fresh_default.streams_parent).
#
# Usage: bash run.sh <WSG> [WSG ...]
#   LNK463_OUT=<dir>       where logs and status.tsv go (default: this directory)
#   LNK463_QUIET_MIN=<n>   quiet database minutes to wait for first (default 5, 0 skips)
#
# Serial, because both bundles share working_<wsg>. Same environment for both
# builds: LNK_LOAD=loadall, LNK_GUARD_DOWNSTREAM=warn (neither schema holds the
# groups below), the habitat gate at model time (wsg_run_one.R's default), a
# 30 min statement bound. The tree must be clean, or the builds are not of one
# commit. No recompute: both builds read the same persisted barriers, and the
# comparison is between them.
set -uo pipefail
[ "$#" -ge 1 ] || { echo "usage: run.sh <WSG> [WSG ...]" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
DIR="${LNK463_OUT:-$HERE}"
QUIET_MIN="${LNK463_QUIET_MIN:-5}"
CONTROL=zz469_control
PARENT=fresh_default_parent
case "$QUIET_MIN" in
  ''|*[!0-9]*) echo "[run] LNK463_QUIET_MIN must be a whole number of minutes" >&2; exit 2 ;;
esac
mkdir -p "$DIR" || exit 1
STATUS="$DIR/status.tsv"
export PGPASSWORD="${PGPASSWORD:-postgres}"
psqlq() { psql -h localhost -U postgres -d fwapg -Atc "$1"; }
stamp() { date -u +%FT%TZ; }
loadavg() { sysctl -n vm.loadavg | awk '{print $2}'; }

if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
  echo "[run] tracked changes in $REPO: builds would not be of one commit" >&2
  exit 1
fi
SHA="$(git -C "$REPO" rev-parse HEAD)" || exit 1
echo "[run] $(stamp) link $SHA, groups: $*"
psqlq "SELECT 1" > /dev/null || { echo "[run] database probe failed" >&2; exit 1; }

# A probe that fails stops the run: read as busy, it would wait out the cap.
quiet=0; waited=0
while [ "$quiet" -lt "$QUIET_MIN" ] && [ "$waited" -lt 180 ]; do
  n=$(psqlq "SELECT count(*) FROM pg_stat_activity WHERE datname = 'fwapg'
             AND state = 'active' AND pid <> pg_backend_pid()") \
    || { echo "[run] database probe failed" >&2; exit 1; }
  if [ "$n" = "0" ]; then quiet=$((quiet + 1)); else quiet=0; fi
  sleep 60; waited=$((waited + 1))
done
if [ "$quiet" -lt "$QUIET_MIN" ]; then
  echo "[run] $(stamp) database still busy after $waited min: not building beside it" >&2
  exit 1
fi
echo "[run] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

printf 'step\twsg\tschema\tstart_utc\tend_utc\tminutes\texit\tn_segments\tload_start\tload_end\n' > "$STATUS"

# run <step> <wsg> <config> <schema>
run() {
  local step="$1" wsg="$2" config="$3" schema="$4"
  local log="$DIR/${step}_${wsg}.log" s e t0 t1 rc l0 n
  s=$(stamp); t0=$(date +%s); l0=$(loadavg)
  ( cd "$REPO" || exit 1
    env PGOPTIONS='-c statement_timeout=30min' LNK_STATEMENT_TIMEOUT_MIN=30 \
      LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
      LNK_RUN_UID="463_${step}" LNK_RUN_LABEL="463_${step}_${wsg}" \
      LNK_SCHEMA="$schema" \
      Rscript data-raw/wsg_run_one.R "$wsg" "$config" ) > "$log" 2>&1
  rc=$?
  e=$(stamp); t1=$(date +%s)
  n=$(psqlq "SELECT count(*) FROM ${schema}.streams
             WHERE watershed_group_code = '${wsg}'") || n=NA
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$step" "$wsg" "$schema" "$s" "$e" \
    "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", (b - a) / 60 }')" \
    "$rc" "$n" "$l0" "$(loadavg)" >> "$STATUS"
  echo "[run] $e $step $wsg exit=$rc segments=$n"
  return "$rc"
}

fail=0
for w in "$@"; do
  run control "$w" default "$CONTROL" || fail=1
  run parent "$w" default_parent "$PARENT" || fail=1
done
if [ "$fail" -ne 0 ]; then
  echo "[run] $(stamp) RUN463_FAILED; see status.tsv"
  exit 1
fi
echo "[run] $(stamp) RUN463_DONE at $SHA"
