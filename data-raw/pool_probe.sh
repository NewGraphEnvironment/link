#!/usr/bin/env bash
# pool_probe.sh — exercise study_area_run.sh's recompute pool against known
# answers, on whichever bash you invoke it with (link#250).
#
# This repo has no shell test harness, and the convention is to move a
# PREDICATE into R and test it there — which is what lnk_fanout_judge() is.
# But the pool's MECHANICS are irreducibly shell: bounded width without
# `wait -n` (unavailable on the bash 3.2.57 that macOS ships as /bin/bash),
# empty-list handling, and per-job rc capture. Those need shell to test.
#
# It extracts the SHIPPED function bodies with sed/awk rather than copying
# them, so it cannot silently drift from what actually runs.
#
# Run it under BOTH interpreters — passing under one proves nothing about the
# other, and the shebang resolves to whichever bash is first on PATH:
#   bash      data-raw/pool_probe.sh data-raw/study_area_run.sh
#   /bin/bash data-raw/pool_probe.sh data-raw/study_area_run.sh
#
# Measured 2026-08-31: PASS=22 FAIL=0 on 5.3.9 and on 3.2.57.
set -euo pipefail
SRC="${1:?usage: pool_probe.sh <path to study_area_run.sh>}"

# csv_lines + run_recompute_pool, verbatim from the script.
eval "$(sed -n '/^csv_lines() {/p' "$SRC")"
eval "$(awk '/^run_recompute_pool\(\)/,/^}/' "$SRC")"

PASS=0; FAIL=0
check() { # $1 label  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1 ($3)"
  else FAIL=$((FAIL+1)); echo "  FAIL $1: expected '$2' got '$3'"; fi
}

# Stub standing in for the real per-WSG job. Same contract: writes its own
# log, writes the rc row LAST, never returns non-zero.
recompute_one() {
  local w="$1" rc=0
  { echo "job $w start"; sleep "${STUB_SLEEP:-0}"; } > "$RC_DIR/$w.log" 2>&1
  case " ${STUB_FAIL:-} " in *" $w "*) rc=1 ;; esac
  printf '%s\t%s\n' "$w" "$rc" > "$RC_DIR/$w.rc"
  return 0
}

run_case() { # $1 label  $2 wsgs  $3 width  $4 expected_rc_count  $5 expected_fail_count
  RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX")
  ALL_WSGS="$2"
  run_recompute_pool "$3"
  local n_rc n_fail
  n_rc=$(find "$RC_DIR" -name '*.rc' | wc -l | tr -d ' ')
  # find -exec, not `cat dir/*.rc`: the glob matches nothing in the empty
  # case, cat then errors, and under `set -euo pipefail` that aborts the
  # probe rather than reporting a result. Same reason the real script uses
  # find here.
  n_fail=$(find "$RC_DIR" -name '*.rc' -exec cat {} + | awk -F'\t' '$2!="0"' | wc -l | tr -d ' ')
  check "$1 rc-files"  "$4" "$n_rc"
  check "$1 failures"  "$5" "$n_fail"
  rm -rf "$RC_DIR"
}

echo "bash $BASH_VERSION"

STUB_FAIL=""
run_case "6 jobs / width 4"      "A,B,C,D,E,F" 4 6 0
run_case "3 jobs / width 4"      "A,B,C"       4 3 0
run_case "1 job  / width 4"      "A"           4 1 0
run_case "1 job  / width 1"      "A"           1 1 0
run_case "empty list"            ""            4 0 0
run_case "trailing comma"        "A,B,"        4 2 0

STUB_FAIL="C E"
run_case "6 jobs, 2 fail"        "A,B,C,D,E,F" 4 6 2
STUB_FAIL="A B C"
run_case "3 jobs, all fail"      "A,B,C"       2 3 3

# Concurrency actually bounded? 8 jobs x 1s at width 4 must take >=2s; the
# same at width 8 must not. A pool that ignored its width would pass the
# first and fail nothing, so both directions are asserted.
STUB_FAIL=""; STUB_SLEEP=1
T0=$(date +%s); run_case "8 jobs / width 4 (timed)" "A,B,C,D,E,F,G,H" 4 8 0
W4=$(( $(date +%s) - T0 ))
T0=$(date +%s); run_case "8 jobs / width 8 (timed)" "A,B,C,D,E,F,G,H" 8 8 0
W8=$(( $(date +%s) - T0 ))
echo "  width 4: ${W4}s   width 8: ${W8}s"
[ "$W4" -ge 2 ] && { PASS=$((PASS+1)); echo "  ok   width 4 serialised (>=2s)"; } \
                || { FAIL=$((FAIL+1)); echo "  FAIL width 4 was not bounded (${W4}s)"; }
[ "$W8" -lt "$W4" ] && { PASS=$((PASS+1)); echo "  ok   width 8 faster than width 4"; } \
                    || { FAIL=$((FAIL+1)); echo "  FAIL width 8 (${W8}s) not faster than width 4 (${W4}s)"; }

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
