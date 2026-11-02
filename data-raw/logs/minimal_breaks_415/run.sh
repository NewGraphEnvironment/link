#!/usr/bin/env bash
# run.sh — #415: `default` and `default_minimal` built from one commit into two
# scratch schemas on the local fwapg, then recomputed (dev state only).
#
# Usage: bash run.sh <WSG> [WSG ...]    (downstream-first)
#   LNK415_OUT=<dir>       where logs and status.tsv go (default: this directory)
#   LNK415_QUIET_MIN=<n>   quiet minutes to wait for first (default 5, 0 skips)
#
# Serial, because both bundles share working_<wsg>. In each group `default`
# runs first, so working_<wsg> holds the minimal build proof.R's census reads.
# The tree must be clean, or the builds are not of one commit.
#
# Recompute pass rule (written before any run): exit 0, or exit 1 with the
# downstream-dam post-condition as the only failure, because that check runs
# after the recompute's work has committed and a scratch schema holds no groups
# below the ones built. It fails the same way for both schemas or neither.
set -uo pipefail
[ "$#" -ge 1 ] || { echo "usage: run.sh <WSG> [WSG ...]" >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
DIR="${LNK415_OUT:-$HERE}"
QUIET_MIN="${LNK415_QUIET_MIN:-5}"
FULL=zz415_default
MINIMAL=zz415_minimal
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
echo "[run] $(stamp) gate passed (quiet minutes $quiet, waited $waited min)"

printf 'step\twsg\tschema\tstart_utc\tend_utc\tminutes\texit\tpass\tn_segments\tload_start\tload_end\n' > "$STATUS"

# run <step> <script> <wsg> <config> <schema> <tries>
run() {
  local step="$1" script="$2" wsg="$3" config="$4" schema="$5" tries="$6"
  local log="$DIR/${step}_${wsg}.log" try s e t0 t1 rc l0 pass n extra
  for try in $(seq 1 "$tries"); do
    s=$(stamp); t0=$(date +%s); l0=$(loadavg)
    extra=()
    case "$script" in
      wsg_run_one.R) extra=(PGOPTIONS='-c statement_timeout=30min' LNK_STATEMENT_TIMEOUT_MIN=30) ;;
    esac
    ( cd "$REPO" || exit 1
      env "${extra[@]+"${extra[@]}"}" LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="415_${step}" LNK_RUN_LABEL="415_${step}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript "data-raw/$script" "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp); t1=$(date +%s)
    pass=no
    if [ "$rc" -eq 0 ]; then
      pass=yes
    elif [ "$script" = wsg_recompute_one.R ] && [ "$rc" -eq 1 ] &&
         LC_ALL=C grep -q "BLOCKED (link#227)" "$log"; then
      pass=postcondition
    fi
    n=$(psqlq "SELECT count(*) FROM ${schema}.streams
               WHERE watershed_group_code = '${wsg}'") || n=NA
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$step" "$wsg" "$schema" "$s" "$e" \
      "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", (b - a) / 60 }')" \
      "$rc" "$pass" "$n" "$l0" "$(loadavg)" >> "$STATUS"
    echo "[run] $e $step $wsg exit=$rc pass=$pass segments=$n (try $try)"
    [ "$pass" != no ] && return 0
  done
  return 1
}

fail=0
for w in "$@"; do
  run default wsg_run_one.R "$w" default "$FULL" 2 || fail=1
  run minimal wsg_run_one.R "$w" default_minimal "$MINIMAL" 2 || fail=1
done
# One try: its expected post-condition failure would re-run the whole recompute.
for w in "$@"; do
  run recompute_default wsg_recompute_one.R "$w" default "$FULL" 1 || fail=1
  run recompute_minimal wsg_recompute_one.R "$w" default_minimal "$MINIMAL" 1 || fail=1
done
if [ "$fail" -ne 0 ]; then
  echo "[run] $(stamp) RUN415_FAILED; see status.tsv"
  exit 1
fi
echo "[run] $(stamp) RUN415_DONE at $SHA"
