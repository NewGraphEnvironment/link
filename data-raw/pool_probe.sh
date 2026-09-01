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
# Measured 2026-09-01: PASS=32 FAIL=0 on 5.3.9 and on 3.2.57.
set -euo pipefail
SRC="${1:?usage: pool_probe.sh <path to study_area_run.sh>}"

# csv_lines + run_recompute_pool, verbatim from the script.
eval "$(sed -n '/^csv_lines() {/p' "$SRC")"
eval "$(awk '/^run_recompute_pool\(\)/,/^}/' "$SRC")"


# Run a command with a deadline, portably. `timeout` is GNU coreutils and is
# not on a stock macOS, so a probe that depended on it would SKIP the very
# assertions it exists for -- and a guard that cannot run is not a weaker
# guard, it is an absent one. Returns 124 on deadline, like timeout does.
with_deadline() {  # $1 = seconds, rest = command
  local secs="$1"; shift
  "$@" & local cmd_pid=$!
  ( sleep "$secs"; kill -9 "$cmd_pid" 2>/dev/null ) & local killer=$!
  local rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  [ "$rc" -ge 128 ] && return 124
  return "$rc"
}

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

# Same stub, but recording START and END as an ordered event stream. Peak
# concurrency is then the max running total of (+1 start, -1 end) -- an EXACT
# measurement of the width the pool actually used, not a timing proxy. Each
# write is a single small append, which O_APPEND makes atomic.
recompute_one_traced() {
  local w="$1"
  printf '+\n' >> "$RC_DIR/events"
  sleep "${STUB_SLEEP:-0}"
  printf -- '-\n' >> "$RC_DIR/events"
  printf '%s\t0\n' "$w" > "$RC_DIR/$w.rc"
  return 0
}

peak_concurrency() {  # reads $RC_DIR/events
  awk '$0=="+"{n++; if(n>m)m=n} $0=="-"{n--} END{print m+0}' "$RC_DIR/events"
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

# Concurrency actually bounded? 12 jobs x 1s at width 4 is 3 waves (>=3s);
# the same at width 12 is one (~1s). A pool that ignored its width would pass
# the first assertion and fail nothing, so both directions are asserted.
#
# 12 jobs rather than 8: at 8 the two arms differ by ~1s, which IS the sample
# period, so the comparison flipped under load from a concurrent run. A
# timing assertion whose margin is the same size as the noise is a flaky
# test, and a flaky guard gets ignored.
STUB_FAIL=""; STUB_SLEEP=1
JOBS12="A,B,C,D,E,F,G,H,I,J,K,L"
T0=$(date +%s); run_case "12 jobs / width 4 (timed)" "$JOBS12" 4 12 0
W4=$(( $(date +%s) - T0 ))
T0=$(date +%s); run_case "12 jobs / width 12 (timed)" "$JOBS12" 12 12 0
W8=$(( $(date +%s) - T0 ))
echo "  width 4: ${W4}s   width 12: ${W8}s"
[ "$W4" -ge 3 ] && { PASS=$((PASS+1)); echo "  ok   width 4 serialised (>=3s)"; } \
                || { FAIL=$((FAIL+1)); echo "  FAIL width 4 was not bounded (${W4}s)"; }
[ "$W8" -lt "$W4" ] && { PASS=$((PASS+1)); echo "  ok   width 12 faster than width 4"; } \
                    || { FAIL=$((FAIL+1)); echo "  FAIL width 12 (${W8}s) not faster than width 4 (${W4}s)"; }


# The pool must wait for ITS OWN children only. A bare `wait` waits for every
# background job in the calling shell, so an unrelated long-lived one hangs it
# with all the work already done. Measured 2026-09-01: a sampler loop in
# recompute_sweep.sh wedged the pool indefinitely.
#
# Backgrounded HERE, in the same shell that calls the pool, because that is
# the only arrangement in which a bare `wait` can see it.
STUB_SLEEP=0
( while :; do sleep 1; done ) &
UNRELATED=$!
T0=$(date +%s)
run_case "unrelated background job present" "A,B,C" 2 3 0
ELAPSED=$(( $(date +%s) - T0 ))
kill "$UNRELATED" 2>/dev/null || true
wait "$UNRELATED" 2>/dev/null || true
[ "$ELAPSED" -lt 20 ] && { PASS=$((PASS+1)); echo "  ok   pool ignored the unrelated job (${ELAPSED}s)"; } \
                      || { FAIL=$((FAIL+1)); echo "  FAIL pool waited on an unrelated job (${ELAPSED}s)"; }


# Width 0 must FAIL FAST, not hang. `seq 0 -1` is empty, so without a guard
# the slot scan never runs, `break 2` is unreachable, and the outer
# `while :; sleep 1` spins forever -- with the work never starting and no
# output to say so. --recompute-jobs validates its own input, but
# recompute_parity.sh and recompute_sweep.sh pass a width straight through.
RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX")
ALL_WSGS="A,B"
# WITH A DEADLINE. Without one this assertion can only pass or hang -- it is
# never reached when the guard fails, so it could not have caught the very
# defect it was added for. Restoring the round-1 guard makes `abc` never
# return, and the probe would have sat there rather than reporting FAIL.
with_deadline 6 run_recompute_pool 0 >/dev/null 2>&1 && RC0=0 || RC0=$?
rm -rf "$RC_DIR"
[ "$RC0" != "0" ] && [ "$RC0" != "124" ] \
  && { PASS=$((PASS+1)); echo "  ok   width 0 refused (rc=$RC0)"; } \
  || { FAIL=$((FAIL+1)); echo "  FAIL width 0 rc=$RC0 (124 = hung)"; }

# ...and a NON-NUMERIC width, which fails a DIFFERENT arm: `[ abc -lt 1 ]`
# exits 2 ("integer expression expected") rather than returning true, so a
# guard that only compares numerically treats it as "condition false", falls
# through, and hangs -- the exact failure the guard exists to prevent. The
# first version of that guard refused 0 and -1 and still hung on abc.
for BADW in abc 2x "" -1 1e1 " 2" 4x; do
  RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX"); ALL_WSGS="A,B"
  with_deadline 6 run_recompute_pool "$BADW" >/dev/null 2>&1 && RCB=0 || RCB=$?
  rm -rf "$RC_DIR"
  if [ "$RCB" != "0" ] && [ "$RCB" != "124" ]; then
    PASS=$((PASS+1)); echo "  ok   width '$BADW' refused (rc=$RCB)"
  else
    FAIL=$((FAIL+1)); echo "  FAIL width '$BADW' rc=$RCB (124 = hung, 0 = accepted)"
  fi
done

# Leading zeros: `test`/`case` read base 10, `$(( ))` reads OCTAL. "08" died
# in $((width-1)) and hung; "010" SILENTLY became an 8-slot pool.
#
# The silent half is the dangerous one, and a job-count assertion cannot see
# it: 12 jobs all complete at width 8 exactly as they do at width 10. So this
# measures the width the pool ACTUALLY used, via an ordered start/end event
# stream -- exact, and independent of timing. Verified to discriminate: with
# the octal bug restored, '010' yields peak 8 and this reports FAIL.
STUB_SLEEP=1
for OKW in 010 016; do
  EXPECT_W=$((10#$OKW))
  RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX")
  : > "$RC_DIR/events"
  ALL_WSGS="A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R"
  _real_one=$(declare -f recompute_one)
  eval "${_real_one/recompute_one/recompute_one_ORIG}"
  eval "$(declare -f recompute_one_traced | sed '1s/recompute_one_traced/recompute_one/')"
  with_deadline 30 run_recompute_pool "$OKW" >/dev/null 2>&1 && RCZ=0 || RCZ=$?
  PEAK=$(peak_concurrency)
  eval "$(declare -f recompute_one_ORIG | sed '1s/recompute_one_ORIG/recompute_one/')"
  rm -rf "$RC_DIR"
  if [ "$RCZ" = "0" ] && [ "$PEAK" = "$EXPECT_W" ]; then
    PASS=$((PASS+1)); echo "  ok   width '$OKW' ran $PEAK-wide (decimal $EXPECT_W)"
  else
    FAIL=$((FAIL+1)); echo "  FAIL width '$OKW' rc=$RCZ, ran $PEAK-wide, expected $EXPECT_W"
  fi
done
STUB_SLEEP=0

# Overflow: 10# wraps silently, so a huge width normalises to a positive
# integer that passes >= 1 and then sends seq off for the afternoon.
for BIGW in 65 99999999999999999999; do
  RC_DIR=$(mktemp -d "${TMPDIR:-/tmp}/poolprobe.XXXXXX"); ALL_WSGS="A,B"
  with_deadline 6 run_recompute_pool "$BIGW" >/dev/null 2>&1 && RCO=0 || RCO=$?
  rm -rf "$RC_DIR"
  if [ "$RCO" != "0" ] && [ "$RCO" != "124" ]; then
    PASS=$((PASS+1)); echo "  ok   width '$BIGW' refused (rc=$RCO)"
  else
    FAIL=$((FAIL+1)); echo "  FAIL width '$BIGW' rc=$RCO (124 = hung, 0 = accepted)"
  fi
done
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
