#!/usr/bin/env bash
# recompute_parity.sh — prove the N-wide post-consolidate recompute produces
# byte-identical output to the serial one, and time both (link#250).
#
# Usage:
#   bash data-raw/recompute_parity.sh [WSG,WSG,...] [config] [parallel_width]
#
# Defaults to a small set so it is runnable on a dev box; pass a bigger one
# to make the timing meaningful.
#
# WHY THREE PASSES, not two. lnk_access(merge = TRUE) reads its OWN prior
# output — R/lnk_access.R has `WHEN t.access_<sp> = 2 THEN 2`, preserving
# observed access — so the recompute is NOT a pure function of untouched
# inputs. Reading the CASE arms says it reaches a fixed point after one
# application, but that is exactly the sort of thing to measure rather than
# assume, so it gets its own pass instead of being a premise:
#
#   A  serial, from the snapshot          the reference
#   B  serial again, on top of A          idempotence
#   C  parallel + SHUFFLED, from the      order- and width-invariance
#      SAME snapshot as A
#
# Acceptance is H_A == H_B == H_C. Decomposed this way a failure points at one
# thing: A != B means the recompute is not idempotent (nothing to do with
# parallelism); A == B != C means parallelism broke something.
#
# The shuffle in pass C is not decoration. A bug that only shows when WSG X
# runs before WSG Y is precisely what a fixed DS-first order reproduces by
# accident.
#
# The pool functions are EXTRACTED from study_area_run.sh rather than copied,
# so this cannot drift from what actually runs.

set -euo pipefail

WSGS="${1:-LKEL,CHWK,CHES,SALR}"
CONFIG="${2:-bcfishpass}"
WIDTH="${3:-4}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="$REPO_ROOT/data-raw/study_area_run.sh"
SCHEMA="${LNK_SCHEMA:-fresh}"
OUT_DIR="$REPO_ROOT/data-raw/logs/recompute_parity"
TS="$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"

PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg)
export PGPASSWORD=postgres

# csv_lines + the pool, verbatim from the shipped script.
eval "$(sed -n '/^csv_lines() {/p' "$RUN_SH")"
eval "$(awk '/^recompute_one\(\)/,/^}/'      "$RUN_SH")"
eval "$(awk '/^run_recompute_pool\(\)/,/^}/' "$RUN_SH")"

# These are BENCHMARKS, not dispatches: the same WSG set is recomputed
# repeatedly to measure the pool. LNK_LOG=0 keeps those passes out of
# <persist>.log_recompute, whose rows would otherwise be byte-indistinguishable
# from a real post-consolidate recompute — and study_area_verify.sql's "every
# WSG has both a model and a recompute record" check would then pass on
# benchmark noise (link#262). Mirrors lnk_pipeline_run(log = FALSE).
export LNK_LOG=0

BAK="zz_lnk_parity_bak"
N_WSG=$(csv_lines "$WSGS" | wc -l | tr -d ' ')
[ "$N_WSG" -gt 0 ] || { echo "FATAL: no WSGs given" >&2; exit 1; }

echo "=== recompute parity $TS ==="
echo "  schema:   $SCHEMA"
echo "  WSGs:     $WSGS ($N_WSG)"
echo "  config:   $CONFIG"
echo "  width C:  $WIDTH"
echo "  out:      $OUT_DIR"

wsg_sql_list() { csv_lines "$WSGS" | sed "s/.*/'&'/" | paste -sd, -; }
IN_LIST="$(wsg_sql_list)"

# The recompute settles streams_habitat_<sp> too since link#349 (the habitat
# gate, one-way), so a pass that does not restore them would start pass C from
# pass A's settled habitat and the digest would not see what the gate wrote.
HAB_TABLES="$("${PSQL[@]}" -At -c "SELECT table_name FROM information_schema.tables
  WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'
    AND table_name ~ '^streams_habitat_[a-z]+\$' ORDER BY 1")"
[ -n "$HAB_TABLES" ] || { echo "FATAL: no streams_habitat_<sp> tables in $SCHEMA" >&2; exit 1; }

snapshot() {
  "${PSQL[@]}" -q -v ON_ERROR_STOP=1 <<SQL
DROP SCHEMA IF EXISTS $BAK CASCADE;
CREATE SCHEMA $BAK;
CREATE TABLE $BAK.streams_access AS
  SELECT * FROM $SCHEMA.streams_access
   WHERE watershed_group_code IN ($IN_LIST);
CREATE TABLE $BAK.streams_mapping_code AS
  SELECT * FROM $SCHEMA.streams_mapping_code
   WHERE watershed_group_code IN ($IN_LIST);
$(for t in $HAB_TABLES; do
    printf 'CREATE TABLE %s.%s AS SELECT * FROM %s.%s WHERE watershed_group_code IN (%s);\n' \
      "$BAK" "$t" "$SCHEMA" "$t" "$IN_LIST"
  done)
SQL
}

restore() {
  # DELETE + INSERT rather than a table swap: the persist tables carry
  # constraints and indexes the snapshot copies do not, and the point is to
  # restore the ROWS, not to replace the objects.
  "${PSQL[@]}" -q -v ON_ERROR_STOP=1 <<SQL
BEGIN;
DELETE FROM $SCHEMA.streams_access       WHERE watershed_group_code IN ($IN_LIST);
INSERT INTO $SCHEMA.streams_access       SELECT * FROM $BAK.streams_access;
DELETE FROM $SCHEMA.streams_mapping_code WHERE watershed_group_code IN ($IN_LIST);
INSERT INTO $SCHEMA.streams_mapping_code SELECT * FROM $BAK.streams_mapping_code;
$(for t in $HAB_TABLES; do
    printf 'DELETE FROM %s.%s WHERE watershed_group_code IN (%s);\nINSERT INTO %s.%s SELECT * FROM %s.%s;\n' \
      "$SCHEMA" "$t" "$IN_LIST" "$SCHEMA" "$t" "$BAK" "$t"
  done)
COMMIT;
SQL
}

digest() {   # $1 = output csv
  "${PSQL[@]}" --csv -q -v schema="$SCHEMA" \
    -f "$REPO_ROOT/data-raw/recompute_checksum.sql" \
    | grep -E "^(tbl|[a-z_]+,($(csv_lines "$WSGS" | paste -sd'|' -)),)" > "$1"
}

run_pass() {   # $1 = label  $2 = wsg csv  $3 = width  -> prints elapsed seconds
  local label="$1" width="$3" t0 t1
  RC_DIR="$OUT_DIR/${TS}_${label}.d"
  ALL_WSGS="$2"
  rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
  t0=$(date +%s)
  run_recompute_pool "$width"
  t1=$(date +%s)
  # Gate on what actually ran. A pass that half-failed would otherwise be
  # compared as though it were a clean run, and matching digests would then
  # mean "both were equally broken".
  #
  # A REAL file, not <(find ...): process substitution hands R a fifo, whose
  # size does not stat reliably, so the judge's "empty file means nothing
  # ran" branch could fire on a pass that ran perfectly.
  local rc_tsv="$RC_DIR.tsv"
  : > "$rc_tsv"
  find "$RC_DIR" -name '*.rc' -exec cat {} + >> "$rc_tsv"
  if ! ( cd "$REPO_ROOT" && LNK_LOAD=loadall \
           Rscript data-raw/fanout_judge.R "$rc_tsv" "$2" "parity-$label" ); then
    echo "FATAL: pass $label did not complete; see $RC_DIR" >&2
    exit 1
  fi
  echo $((t1 - t0))
}

# Barrier views once, up front — the whole point of the hoist.
( cd "$REPO_ROOT" && LNK_LOAD=loadall LNK_SCHEMA="$SCHEMA" \
    Rscript data-raw/barriers_views_build.R "$CONFIG" ) >/dev/null
export LNK_SCHEMA="$SCHEMA"

echo "--- snapshotting pre-state"
snapshot

echo "--- pass A: serial (-j1), from snapshot"
SEC_A=$(run_pass A "$WSGS" 1)
digest "$OUT_DIR/${TS}_A.csv"

echo "--- pass B: serial (-j1) again, ON TOP OF A  [idempotence]"
SEC_B=$(run_pass B "$WSGS" 1)
digest "$OUT_DIR/${TS}_B.csv"

echo "--- restoring pre-state"
restore

SHUF=$(csv_lines "$WSGS" | awk 'BEGIN{srand(7)}{print rand()"\t"$0}' \
       | sort -k1,1 | cut -f2 | paste -sd, -)
echo "--- pass C: parallel (-j$WIDTH), shuffled ($SHUF), from snapshot"
SEC_C=$(run_pass C "$SHUF" "$WIDTH")
digest "$OUT_DIR/${TS}_C.csv"

# Leave the schema as it was found. The passes run with LNK_LOG=0, and the
# recompute's habitat gate is one-way (link#349): without this a benchmark on
# an unsettled schema would settle its habitat with no log row saying so.
echo "--- restoring pre-state"
restore

echo
echo "=== timing ==="
printf '  A serial   (-j1)        %4d s\n' "$SEC_A"
printf '  B serial   (-j1) again  %4d s\n' "$SEC_B"
printf '  C parallel (-j%-2d)       %4d s   speedup %.2fx\n' \
  "$WIDTH" "$SEC_C" "$(awk -v a="$SEC_A" -v c="$SEC_C" 'BEGIN{print (c>0)?a/c:0}')"

echo
echo "=== parity ==="
FAILED=0
if command diff -q "$OUT_DIR/${TS}_A.csv" "$OUT_DIR/${TS}_B.csv" >/dev/null; then
  echo "  ok   A == B  (recompute is idempotent)"
else
  echo "  FAIL A != B  — the recompute is NOT idempotent; nothing to do with"
  echo "                parallelism. diff:"
  command diff "$OUT_DIR/${TS}_A.csv" "$OUT_DIR/${TS}_B.csv" | head -20
  FAILED=1
fi
if command diff -q "$OUT_DIR/${TS}_A.csv" "$OUT_DIR/${TS}_C.csv" >/dev/null; then
  echo "  ok   A == C  (parallel, shuffled == serial, byte-identical)"
else
  echo "  FAIL A != C  — parallelism changed the output. diff:"
  command diff "$OUT_DIR/${TS}_A.csv" "$OUT_DIR/${TS}_C.csv" | head -20
  FAILED=1
fi

# A digest file with only a header would make every diff trivially equal --
# three identical empty results reported as a pass. Assert we measured
# something, and assert it at FULL STRENGTH.
#
# The digest emits one row per (table, WSG) over TWO tables, so the expected
# count is 2 x N_WSG, not N_WSG. `GROUP BY` over zero rows yields no groups,
# so a streams_mapping_code that is empty for every WSG drops out of the
# digest entirely -- all three passes then compare equal on streams_access
# alone, and a threshold of N_WSG still clears. That is the same
# "three identical empty results reported as a pass" this guard exists to
# prevent, surviving at half strength.
#
# Since link#349 the digest also covers each streams_habitat_<sp>, which holds
# rows only for the species a group models. Their share of the expected count
# is read from the pre-state snapshot, not from the digest it checks.
N_ROWS=$(($(wc -l < "$OUT_DIR/${TS}_A.csv") - 1))
N_HAB=0
for t in $HAB_TABLES; do
  n=$("${PSQL[@]}" -At -c "SELECT count(DISTINCT watershed_group_code) FROM $BAK.$t")
  N_HAB=$((N_HAB + n))
done
N_EXPECT=$((2 * N_WSG + N_HAB))
if [ "$N_ROWS" -ne "$N_EXPECT" ]; then
  echo "  FAIL digest covers $N_ROWS row(s), expected $N_EXPECT (2 tables x $N_WSG WSGs + $N_HAB habitat)"
  echo "       missing (table, WSG) pairs — the comparison is weaker than it looks:"
  awk -F, 'NR>1{seen[$1"|"$2]=1} END{for(k in seen) print "         have " k}' \
    "$OUT_DIR/${TS}_A.csv" | sort
  FAILED=1
else
  echo "  ok   digest covers $N_ROWS table-WSG row(s) (2 x $N_WSG + $N_HAB habitat)"
fi

"${PSQL[@]}" -q -c "DROP SCHEMA IF EXISTS $BAK CASCADE;"

echo
[ "$FAILED" -eq 0 ] && echo "=== recompute parity PASSED ===" \
                    || { echo "=== recompute parity FAILED ==="; exit 1; }
