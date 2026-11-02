#!/usr/bin/env bash
# check.sh — #418's checks on one rehearsal run, by hand (the gated rehearsal script is still owed on #418).
# Run from the repo root after the driver exits:
#   bash data-raw/logs/rehearsal_418/check.sh <TS> <run_uid> <schema> <driver exit> <n groups> <host>...
# <host> are the phases.tsv host keys expected (dispatcher worker1 job1 job2). Prints one line per check,
# PASS or FAIL with the reason, then the verdict; exits 1 on any FAIL. Writes its logs to a new temporary
# directory, or to $CHECK_OUT when set (the committed record used this directory), and the negative verify
# script builds and drops its own scratch schema.
set -uo pipefail
[ "$#" -ge 6 ] || { echo "usage: check.sh <TS> <run_uid> <schema> <driver exit> <n> <host>..." >&2; exit 2; }
TS=$1 UID_=$2 SCHEMA=$3 DRC=$4 N=$5; shift 5; HOSTS=("$@")
L=data-raw/logs/study_area_run; OUT=${CHECK_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/check418.XXXXXX")}
echo "logs: $OUT"
export PGPASSWORD=postgres
fail=0
say() { printf '%-28s %s\n' "$1" "$2"; case "$2" in FAIL*) fail=1 ;; esac; }

[ "$DRC" = 0 ] && say "driver exit" PASS || say "driver exit" "FAIL: $DRC"

psql -h localhost -U postgres -d fwapg -X -q -v ON_ERROR_STOP=1 -v schema="$SCHEMA" -v run_uid="$UID_" \
  -v expected_n="$N" -f data-raw/study_area_verify.sql > "$OUT/verify.log" 2>&1 \
  && grep -q '=== verify: OK ===' "$OUT/verify.log" && say "study_area_verify.sql" PASS \
  || say "study_area_verify.sql" "FAIL: see verify.log"

bash data-raw/study_area_verify_negative.sh "$UID_" "$SCHEMA" > "$OUT/verify_negative.log" 2>&1 \
  && say "verify negative cases" PASS || say "verify negative cases" "FAIL: see verify_negative.log"

ph="$L/${TS}_phases.tsv"
# <TS> and <run_uid> must name one run: phases.tsv's first column carries the run_uid.
if [ -s "$ph" ] && awk -F'\t' -v u="$UID_" 'NR > 1 && $1 != u { bad = 1 } END { exit bad }' "$ph"; then
  say "TS names the run_uid" PASS
else
  say "TS names the run_uid" "FAIL: $ph missing, or holds rows of another run"
fi

deps="$L/${TS}_recompute_deps.tsv"
missing=""
for f in "$deps" "$L/${TS}_run_wsgs.tsv" "$L/${TS}_consolidate_state.tsv" "$L/${TS}_recompute_launched.tsv"; do
  [ -s "$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then
  Rscript data-raw/recompute_audit.R "$SCHEMA" "$UID_" "$deps" "$L/${TS}_run_wsgs.tsv" \
    "$L/${TS}_consolidate_state.tsv" "$L/${TS}_recompute_launched.tsv" > "$OUT/recompute_audit.log" 2>&1
  arc=$?
  # Exit 0 is not enough: header-only inputs give "0 dependency pairs ... 0 EARLY" and exit 0.
  sum=$(grep -E 'dependency pairs in the run' "$OUT/recompute_audit.log" | tail -1)
  pairs=$(printf '%s' "$sum" | sed -nE 's/.* ([0-9]+) dependency pairs in the run: ([0-9]+) ok.*/\1/p')
  ok=$(printf '%s' "$sum" | sed -nE 's/.* ([0-9]+) dependency pairs in the run: ([0-9]+) ok.*/\2/p')
  if [ "$arc" = 0 ] && [ -n "$pairs" ] && [ "$pairs" -gt 0 ] && [ "$ok" = "$pairs" ]; then
    say "recompute_audit.R" "PASS ($ok of $pairs pairs ok)"
  else
    say "recompute_audit.R" "FAIL: exit $arc, pairs '${pairs:-?}', ok '${ok:-?}' (see recompute_audit.log)"
  fi
else
  # The audit reads a missing consolidate state or launch file as nothing landed or launched, and passes.
  say "recompute_audit.R" "FAIL: missing or empty:$missing"
fi

if [ -s "$ph" ]; then
  for h in "${HOSTS[@]}"; do
    n=$(awk -F'\t' -v h="$h" '$2 == "model" && $3 == h && $8 == "ok"' "$ph" | wc -l | tr -d ' ')
    [ "$n" -ge 1 ] && say "phases: model on $h" PASS || say "phases: model on $h" "FAIL: no ok model row"
  done
else
  say "phases.tsv" "FAIL: no $ph"
fi

kept="$L/${TS}_kept_hosts.tsv"
if [ ! -e "$kept" ]; then
  say "no host kept" PASS
elif ! nk=$(wc -l < "$kept" 2>/dev/null); then
  say "no host kept" "FAIL: $kept unreadable"
elif [ "$nk" -gt 1 ]; then
  say "no host kept" "FAIL: $kept lists a host"
else
  say "no host kept" PASS
fi
if dl=$(doctl compute droplet list --format Name --no-header 2>&1); then
  left=$(printf '%s\n' "$dl" | grep -c '^cypher-' || true)
  [ "$left" = 0 ] && say "cloud hosts burned" PASS || say "cloud hosts burned" "FAIL: $left cypher droplet(s) up"
else
  say "cloud hosts burned" "FAIL: doctl could not list droplets: $dl"
fi

[ -e "$L/${TS}_outside_readers.tsv" ] && say "outside_readers.tsv" PASS || say "outside_readers.tsv" "FAIL: not written"

[ "$fail" = 0 ] && echo "REHEARSAL: PASS" || echo "REHEARSAL: FAIL"
exit "$fail"
