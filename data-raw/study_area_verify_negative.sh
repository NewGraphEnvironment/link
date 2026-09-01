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
#   1. as-is                          -> expect PASS (exit 0)
#   2. one log_recompute row gone     -> expect FAIL (exit non-zero)
#   3. wrong expected_n               -> expect FAIL (exit non-zero)
#   4a. bcfp pin removed              -> expect FAIL
#   4b.  ... plus -v unpinned_ok=<why> -> expect PASS
#   4c.  ... plus a whitespace reason  -> expect FAIL
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
#
# SCRATCH_MADE is armed BEFORE the heredoc, not after. Adding ON_ERROR_STOP to
# the array above turned this from continue-and-exit-0 into abort-with-rc-3, so
# under `set -euo pipefail` a mid-heredoc failure exits INSIDE the window
# between CREATE SCHEMA and any later assignment -- and the trap would then
# decline to drop, leaking the schema. That is the exact leak the early trap was
# added to close: two individually-correct fixes, neither measured against the
# other. The flag means "this script may have created it", not "it finished";
# the heredoc's first statement is DROP SCHEMA IF EXISTS, so arming early is
# idempotent and free.
SCRATCH_MADE=1
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

# --- 4. the unpinned escape: must FAIL without a reason, PASS with one --------
# `unpinned_ok` SUPPRESSES a raise, so a mis-wiring fails silently -- verify
# simply stops failing on unpinned runs and nobody finds out. That is the one
# direction this file exists to catch, and it was the only control in it with
# no case of its own.
# Premise first. If the run under test is ALREADY unpinned -- precisely the
# situation unpinned_ok exists for, and one preflight_local() sanctions -- the
# UPDATE below is a no-op and 4a/4b/4c would exercise nothing while printing
# three ticks. Case 2 three blocks up sets the standard: absence reported as
# absence, counted as a failure, never as a pass.
N_PINNED=$("${PSQL[@]}" -c "SELECT count(*) FROM ${SCRATCH}.log
                             WHERE bcfp_model_version IS NOT NULL")
if [ "${N_PINNED:-0}" = "0" ]; then
  echo "  ⊘ 4. SKIPPED: run $RUN_UID is already unpinned on every row, so"
  echo "       removing the pin changes nothing and 4a-4c would test nothing."
  echo "       Absence reported as absence -- this is NOT a pass."
  fails=$((fails + 1))
else
"${PSQL[@]}" -c "UPDATE ${SCRATCH}.log SET bcfp_model_version = NULL" >/dev/null
if run_verify -v expected_n="$N_WSG"; then
  echo "  ✗ 4a. unpinned, no reason      -> PASSED, but should have FAILED."
  echo "       The bcfp pin assertion is not firing."
  show_verify
  fails=$((fails + 1))
else
  echo "  ✓ 4a. unpinned, no reason      -> FAIL (as expected)"
fi
if run_verify -v expected_n="$N_WSG" -v unpinned_ok='negative test'; then
  echo "  ✓ 4b. unpinned + written reason-> PASS (as expected)"
else
  echo "  ✗ 4b. unpinned + written reason-> FAILED, but the escape should allow it."
  echo "       An escape that never works is the same as no escape."
  show_verify
  fails=$((fails + 1))
fi
# Whitespace is not a written justification.
if run_verify -v expected_n="$N_WSG" -v unpinned_ok='   '; then
  echo "  ✗ 4c. unpinned + blank reason  -> PASSED; whitespace accepted as a reason."
  fails=$((fails + 1))
else
  echo "  ✓ 4c. unpinned + blank reason  -> FAIL (as expected)"
fi
# Restore CORRELATED, per row. `SET col = (SELECT ... LIMIT 1)` would write one
# arbitrary source row's value to every row -- flattening, not restoring. That
# is harmless only while nothing runs after this point, and it is harmless for a
# reason another check enforces (section 2 asserts the hosts agree on the pin).
# A case 5 appended below would inherit a table whose pin column is uniform by
# construction, making a per-host pin defect structurally untestable: the
# fixture-cannot-reach-the-failure shape, arriving through a cleanup step.
# Case 2's restore is already correlated; this matches it.
"${PSQL[@]}" -c "UPDATE ${SCRATCH}.log t SET bcfp_model_version = s.bcfp_model_version
   FROM ${SRC_SCHEMA}.log s
  WHERE s.run_uid = '${RUN_UID}'
    AND s.host = t.host
    AND s.watershed_group_code = t.watershed_group_code" >/dev/null
fi

# --- 5/6. the code-identity columns: must FAIL when NULL (link#264) ----------
# Both were tolerated-or-absent before this release: fresh_sha was excused on
# the dispatcher for a reason that turned out to be false, and bcfishobs_sha
# did not exist. Each now has an unconditional assertion, and an assertion
# nobody has watched go red is decoration -- these are the cases that watch.
#
# Driven by a loop rather than written twice, so a third column added later
# joins by adding one word and cannot quietly be given a case that is never
# run. Each iteration restores CORRELATED per row, matching cases 2 and 4:
# a `SET col = (SELECT ... LIMIT 1)` would flatten the column across hosts and
# leave the NEXT iteration a fixture that cannot reach its own failure.
n=5
for col in fresh_sha bcfishobs_sha; do
  n_present=$("${PSQL[@]}" -c "SELECT count(*) FROM ${SCRATCH}.log
                                WHERE ${col} IS NOT NULL")
  if [ "${n_present:-0}" = "0" ]; then
    echo "  ⊘ $n. SKIPPED: $col is already NULL on every row of $RUN_UID, so"
    echo "       nulling it changes nothing and this case would test nothing."
    echo "       Absence reported as absence -- this is NOT a pass. Expected"
    echo "       for any run logged before link v0.50.0."
    fails=$((fails + 1))
  else
    "${PSQL[@]}" -c "UPDATE ${SCRATCH}.log SET ${col} = NULL" >/dev/null
    if run_verify -v expected_n="$N_WSG"; then
      echo "  ✗ $n. $col NULLed -> PASSED, but should have FAILED."
      echo "       The $col assertion is not firing."
      show_verify
      fails=$((fails + 1))
    else
      echo "  ✓ $n. $col NULLed -> FAIL (as expected)"
    fi
    "${PSQL[@]}" -c "UPDATE ${SCRATCH}.log t SET ${col} = s.${col}
       FROM ${SRC_SCHEMA}.log s
      WHERE s.run_uid = '${RUN_UID}'
        AND s.host = t.host
        AND s.watershed_group_code = t.watershed_group_code" >/dev/null
  fi
  n=$((n + 1))
done

# --- 6b. fresh_dirty TRUE: must FAIL -----------------------------------------
# A different mutation from the NULL cases above, and the one the first draft
# of link#264 shipped with no arm at all: fresh_sha present but describing a
# modified tree. The columns being non-NULL is what made the run PASS, which
# is exactly why a NULL-only sweep cannot find it.
"${PSQL[@]}" -c "UPDATE ${SCRATCH}.log SET fresh_dirty = TRUE" >/dev/null
if run_verify -v expected_n="$N_WSG"; then
  echo "  ✗ 6b. fresh_dirty=TRUE         -> PASSED, but should have FAILED."
  echo "       A dirty fresh makes log.fresh_sha a lie and nothing caught it."
  show_verify
  fails=$((fails + 1))
else
  echo "  ✓ 6b. fresh_dirty=TRUE         -> FAIL (as expected)"
fi
"${PSQL[@]}" -c "UPDATE ${SCRATCH}.log t SET fresh_dirty = s.fresh_dirty
   FROM ${SRC_SCHEMA}.log s
  WHERE s.run_uid = '${RUN_UID}'
    AND s.host = t.host
    AND s.watershed_group_code = t.watershed_group_code" >/dev/null

# --- 6c. hosts disagreeing on an input: must FAIL ----------------------------
# Section 2b prints this verdict, so it needs an assertion behind it or the
# script prints the word FAIL and exits 0. Only runs where there IS a second
# host to disagree with -- on a single-host run the state is unreachable, and
# an unreachable case reported as a pass is the thing this file exists against.
N_HOSTS=$("${PSQL[@]}" -c "SELECT count(DISTINCT host) FROM ${SCRATCH}.log")
if [ "${N_HOSTS:-1}" -lt 2 ]; then
  echo "  ⊘ 6c. SKIPPED: run $RUN_UID used one host, so hosts cannot disagree."
  echo "       Absence reported as absence -- this is NOT a pass. Counted as a"
  echo "       failure, like cases 2, 4 and 5/6: without it the banner would"
  echo "       read 'the verify script fails when it should' about a brand-new"
  echo "       assertion this run never exercised."
  fails=$((fails + 1))
else
  ODD=$("${PSQL[@]}" -c "SELECT host FROM ${SCRATCH}.log ORDER BY host DESC LIMIT 1")
  "${PSQL[@]}" -c "UPDATE ${SCRATCH}.log SET fresh_sha = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
                    WHERE host = '${ODD}'" >/dev/null
  if run_verify -v expected_n="$N_WSG"; then
    echo "  ✗ 6c. $ODD on a different fresh -> PASSED, but should have FAILED."
    show_verify
    fails=$((fails + 1))
  else
    echo "  ✓ 6c. $ODD on a different fresh -> FAIL (as expected)"
  fi
  "${PSQL[@]}" -c "UPDATE ${SCRATCH}.log t SET fresh_sha = s.fresh_sha
     FROM ${SRC_SCHEMA}.log s
    WHERE s.run_uid = '${RUN_UID}'
      AND s.host = t.host
      AND s.watershed_group_code = t.watershed_group_code" >/dev/null
fi

# The healthy case again, LAST. Cases 2/4/5/6 each mutate the scratch schema
# and restore it, and a restore that silently did not restore would leave every
# later case running against damaged data while still printing ticks. Re-running
# case 1 at the end is what makes the restores load-bearing rather than assumed.
if run_verify -v expected_n="$N_WSG"; then
  echo "  ✓ 7. healthy data, post-restore-> PASS (as expected)"
else
  echo "  ✗ 7. healthy data, post-restore-> FAILED; a restore above did not restore."
  show_verify
  fails=$((fails + 1))
fi

echo ""
if [ "$fails" = "0" ]; then
  echo "=== negative test PASSED: the verify script fails when it should, and"
  echo "    passes when it should ==="
  exit 0
fi
echo "=== negative test FAILED ($fails case(s) wrong) ==="
exit 1
