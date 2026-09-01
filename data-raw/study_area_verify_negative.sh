#!/usr/bin/env bash
# study_area_verify_negative.sh — prove data-raw/study_area_verify.sql can FAIL
# (link#262 acceptance: "negative-tested — delete a recompute row and confirm
# it fails").
#
# A guard nobody has seen fail is decoration, and a verify script is exactly the
# kind that accumulates checks nobody has ever watched go red. This runs the
# real script against real data in three states and asserts the answer each
# time — including the healthy one, because a guard that only ever returns one
# value is indistinguishable from a broken one.
#
#   1. as-is                        -> expect PASS (exit 0)
#   2. one log_recompute row gone   -> expect FAIL (exit non-zero)
#   3. wrong expected_n             -> expect FAIL (exit non-zero)
#
# Nothing durable is mutated: every case runs against a SCRATCH SCHEMA holding a
# copy of the run's rows, so the real persist is never touched at all. Not a
# transaction -- each `psql -f` is its own session, so a transaction opened here
# could not span the runs being tested.
#
# Usage:
#   bash data-raw/study_area_verify_negative.sh [run_uid] [source-schema]
#
# With no run_uid the most recent labelled run is used.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCHEMA="${2:-fresh}"
SCRATCH="zz_lnk_verify_negative"

export PGPASSWORD=postgres
# ON_ERROR_STOP is load-bearing on the SETUP heredoc below, not decoration:
# psql continues past a failed statement in a multi-statement script and still
# exits 0. Without it, a missing ${SRC_SCHEMA}.log_recompute (an older persist,
# pre-#262) would build a PARTIAL scratch schema silently, case 1 would report
# "healthy data FAILED", and the operator would be sent to debug
# study_area_verify.sql when the fault is in this script's own setup. Inert for
# the single-statement -c probes that share the array.
PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg -t -A -v ON_ERROR_STOP=1)

RUN_UID="${1:-}"
if [ -z "$RUN_UID" ]; then
  RUN_UID=$("${PSQL[@]}" -c "SELECT coalesce((SELECT run_uid FROM ${SRC_SCHEMA}.log
              WHERE run_uid IS NOT NULL ORDER BY date_start DESC LIMIT 1), '')")
fi
if [ -z "$RUN_UID" ]; then
  echo "FATAL: no run_uid given and none found in ${SRC_SCHEMA}.log." >&2
  echo "  This script needs a completed labelled run to test against." >&2
  echo "  Run data-raw/study_area_run.sh first, or pass a run_uid." >&2
  exit 1
fi
echo "=== negative test of study_area_verify.sql against run $RUN_UID ==="

# Register the EXIT trap BEFORE anything it cleans up exists. Installing it
# after `CREATE SCHEMA` leaves a window -- the mktemp and the N_WSG query --
# in which `set -euo pipefail` can exit with no trap registered, leaking the
# scratch schema into the database. SCRATCH_MADE exists precisely so the trap
# can be armed early and still know whether there is anything to drop.
SCRATCH_MADE=0
VERIFY_LOG=""
cleanup() {
  [ -z "$VERIFY_LOG" ] || rm -f "$VERIFY_LOG"
  [ "$SCRATCH_MADE" = "1" ] || return 0
  "${PSQL[@]}" -c "DROP SCHEMA IF EXISTS ${SCRATCH} CASCADE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A scratch copy: same shape, only this run's rows. The verify script takes
# -v schema=, so it runs against the copy unmodified — testing the shipped
# file, not a variant of it.
"${PSQL[@]}" >/dev/null <<SQL
DROP SCHEMA IF EXISTS ${SCRATCH} CASCADE;
CREATE SCHEMA ${SCRATCH};
CREATE TABLE ${SCRATCH}.log            AS SELECT * FROM ${SRC_SCHEMA}.log
  WHERE run_uid = '${RUN_UID}';
CREATE TABLE ${SCRATCH}.log_recompute  AS SELECT * FROM ${SRC_SCHEMA}.log_recompute
  WHERE run_uid = '${RUN_UID}';
CREATE TABLE ${SCRATCH}.streams        AS
  SELECT id_segment, watershed_group_code FROM ${SRC_SCHEMA}.streams
   WHERE watershed_group_code IN
     (SELECT watershed_group_code FROM ${SRC_SCHEMA}.log WHERE run_uid = '${RUN_UID}');
SQL

SCRATCH_MADE=1
N_WSG=$("${PSQL[@]}" -c "SELECT count(DISTINCT watershed_group_code) FROM ${SCRATCH}.log")
echo "  scratch schema $SCRATCH built: $N_WSG WSG(s)"

# Output goes to a file rather than /dev/null, and is REPLAYED whenever a case
# answers the wrong way. Discarding it entirely would leave "case 1 failed but
# should have passed" with nothing to act on — and that is the case an operator
# most needs to read, because it invalidates every case after it.
# One trap, armed above. A second `trap ... EXIT` would REPLACE the first
# rather than add to it, so both cleanups live in one handler.
VERIFY_LOG="$(mktemp "${TMPDIR:-/tmp}/lnk_verify_neg.XXXXXX")" || exit 1
[ -n "$VERIFY_LOG" ] || exit 1

run_verify() {   # $@ = extra psql -v flags; returns the exit code
  psql -h localhost -p 5432 -U postgres -d fwapg -q \
       -v ON_ERROR_STOP=1 -v run_uid="$RUN_UID" -v schema="$SCRATCH" "$@" \
       -f "$REPO_ROOT/data-raw/study_area_verify.sql" > "$VERIFY_LOG" 2>&1
}
show_verify() { sed 's/^/       | /' "$VERIFY_LOG" | tail -12; }

fails=0

# --- 1. healthy: must PASS ---------------------------------------------------
# Runs FIRST and is not optional. If this fails, the two cases below prove
# nothing — a script that always exits non-zero "detects" every defect.
if run_verify -v expected_n="$N_WSG"; then
  echo "  ✓ 1. healthy data              -> PASS (as expected)"
else
  echo "  ✗ 1. healthy data              -> FAILED, but should have passed."
  echo "       Every case below is meaningless until this one is green."
  show_verify
  fails=$((fails + 1))
fi

# --- 2. a missing recompute row: must FAIL -----------------------------------
# The acceptance criterion, literally. The DELETE hits the scratch copy only,
# and the EXIT trap drops that schema whatever happens.
VICTIM=$("${PSQL[@]}" -c "SELECT watershed_group_code FROM ${SCRATCH}.log_recompute
                           ORDER BY watershed_group_code LIMIT 1")
if [ -z "$VICTIM" ]; then
  echo "  ⊘ 2. SKIPPED: run $RUN_UID has no log_recompute rows to delete."
  echo "       Absence reported as absence -- this is NOT a pass. The check"
  echo "       under test is 'modelled but not recomputed', so a run with zero"
  echo "       recompute rows cannot exercise it."
  fails=$((fails + 1))
else
  "${PSQL[@]}" -c "DELETE FROM ${SCRATCH}.log_recompute
                    WHERE watershed_group_code = '${VICTIM}'" >/dev/null
  if run_verify -v expected_n="$N_WSG"; then
    echo "  ✗ 2. $VICTIM recompute deleted -> PASSED, but should have FAILED."
    echo "       The modelled-vs-recomputed assertion is not firing."
    show_verify
    fails=$((fails + 1))
  else
    echo "  ✓ 2. $VICTIM recompute deleted -> FAIL (as expected)"
  fi
  # Restore by re-copying, not by rolling back: each run_verify opens its own
  # psql session, so a transaction here could not span it.
  "${PSQL[@]}" >/dev/null -c "INSERT INTO ${SCRATCH}.log_recompute
     SELECT * FROM ${SRC_SCHEMA}.log_recompute
      WHERE run_uid = '${RUN_UID}' AND watershed_group_code = '${VICTIM}'"
fi

# --- 3. a wrong expected_n: must FAIL ----------------------------------------
# Guards the externality itself. Without this, expected_n could be ignored
# entirely and cases 1 and 2 would not notice.
if run_verify -v expected_n=$((N_WSG + 1)); then
  echo "  ✗ 3. expected_n=$((N_WSG + 1)) (wrong)  -> PASSED, but should have FAILED."
  echo "       The scope assertion is not firing; a WSG that never logged"
  echo "       would be invisible to every check."
  show_verify
  fails=$((fails + 1))
else
  echo "  ✓ 3. expected_n=$((N_WSG + 1)) (wrong)  -> FAIL (as expected)"
fi

echo ""
if [ "$fails" = "0" ]; then
  echo "=== negative test PASSED: the verify script fails when it should, and"
  echo "    passes when it should ==="
  exit 0
fi
echo "=== negative test FAILED ($fails of 3 cases wrong) ==="
exit 1
