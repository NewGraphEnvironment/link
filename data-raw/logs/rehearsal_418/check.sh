#!/usr/bin/env bash
# check.sh — #418's checks on one rehearsal run, by hand (the gated rehearsal script is still owed on #418).
# Run from the repo root after the driver exits:
#   bash data-raw/logs/rehearsal_418/check.sh <TS> <run_uid> <schema> <driver exit> <n groups> <host>...
# <host> are the phases.tsv host keys expected (dispatcher worker1 job1 job2). Prints one line per check,
# PASS or FAIL with the reason, then the verdict; exits 1 on any FAIL. Reads only.
set -uo pipefail
[ "$#" -ge 6 ] || { echo "usage: check.sh <TS> <run_uid> <schema> <driver exit> <n> <host>..." >&2; exit 2; }
TS=$1 UID_=$2 SCHEMA=$3 DRC=$4 N=$5; shift 5; HOSTS=("$@")
L=data-raw/logs/study_area_run; OUT=data-raw/logs/rehearsal_418
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

deps="$L/${TS}_recompute_deps.tsv"
if [ -s "$deps" ]; then
  Rscript data-raw/recompute_audit.R "$SCHEMA" "$UID_" "$deps" "$L/${TS}_run_wsgs.tsv" \
    "$L/${TS}_consolidate_state.tsv" "$L/${TS}_recompute_launched.tsv" > "$OUT/recompute_audit.log" 2>&1 \
    && say "recompute_audit.R" PASS || say "recompute_audit.R" "FAIL: exit $? (see recompute_audit.log)"
else
  say "recompute_audit.R" "FAIL: no $deps"
fi

ph="$L/${TS}_phases.tsv"
if [ -s "$ph" ]; then
  for h in "${HOSTS[@]}"; do
    n=$(awk -F'\t' -v h="$h" '$2 == "model" && $3 == h && $8 == "ok"' "$ph" | wc -l | tr -d ' ')
    [ "$n" -ge 1 ] && say "phases: model on $h" PASS || say "phases: model on $h" "FAIL: no ok model row"
  done
else
  say "phases.tsv" "FAIL: no $ph"
fi

kept="$L/${TS}_kept_hosts.tsv"
if [ -s "$kept" ] && [ "$(wc -l < "$kept")" -gt 1 ]; then say "no host kept" "FAIL: $kept"; else say "no host kept" PASS; fi
if dl=$(doctl compute droplet list --format Name --no-header 2>&1); then
  left=$(printf '%s\n' "$dl" | grep -c '^cypher-' || true)
  [ "$left" = 0 ] && say "cloud hosts burned" PASS || say "cloud hosts burned" "FAIL: $left cypher droplet(s) up"
else
  say "cloud hosts burned" "FAIL: doctl could not list droplets: $dl"
fi

[ -e "$L/${TS}_outside_readers.tsv" ] && say "outside_readers.tsv" PASS || say "outside_readers.tsv" "FAIL: not written"

[ "$fail" = 0 ] && echo "REHEARSAL: PASS" || echo "REHEARSAL: FAIL"
exit "$fail"
