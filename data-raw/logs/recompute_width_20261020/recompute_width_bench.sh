#!/usr/bin/env bash
# recompute_width_bench.sh — time the post-consolidate recompute pool at two
# widths on the same groups, restoring the schema's rows between and after
# (recompute_parity.sh's snapshot/restore; the habitat gate is one-way).
# Usage: bash recompute_width_bench.sh <WSG,...> <config> <schema> <out_dir> <width> <width>
set -euo pipefail
WSGS="$1"; CONFIG="$2"; SCHEMA="$3"; OUT_DIR="$4"; W1="$5"; W2="$6"
REPO_ROOT=/Users/airvine/Projects/repo/link
RUN_SH="$REPO_ROOT/data-raw/study_area_run.sh"
TS="$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg)
export PGPASSWORD=postgres LNK_LOG=0
eval "$(sed -n '/^csv_lines() {/p' "$RUN_SH")"
eval "$(awk '/^recompute_one\(\)/,/^}/'      "$RUN_SH")"
eval "$(awk '/^run_recompute_pool\(\)/,/^}/' "$RUN_SH")"
BAK="zz_lnk_width_bak"
IN_LIST="$(csv_lines "$WSGS" | sed "s/.*/'&'/" | paste -sd, -)"
HAB_TABLES="$("${PSQL[@]}" -At -c "SELECT table_name FROM information_schema.tables
  WHERE table_schema = '$SCHEMA' AND table_type = 'BASE TABLE'
    AND table_name ~ '^streams_habitat_[a-z]+\$' ORDER BY 1")"
[ -n "$HAB_TABLES" ] || { echo "FATAL: no habitat tables" >&2; exit 1; }
snapshot() {
  "${PSQL[@]}" -q -v ON_ERROR_STOP=1 <<SQL
DROP SCHEMA IF EXISTS $BAK CASCADE;
CREATE SCHEMA $BAK;
CREATE TABLE $BAK.streams_access AS SELECT * FROM $SCHEMA.streams_access WHERE watershed_group_code IN ($IN_LIST);
CREATE TABLE $BAK.streams_mapping_code AS SELECT * FROM $SCHEMA.streams_mapping_code WHERE watershed_group_code IN ($IN_LIST);
$(for t in $HAB_TABLES; do printf 'CREATE TABLE %s.%s AS SELECT * FROM %s.%s WHERE watershed_group_code IN (%s);\n' "$BAK" "$t" "$SCHEMA" "$t" "$IN_LIST"; done)
SQL
}
restore() {
  "${PSQL[@]}" -q -v ON_ERROR_STOP=1 <<SQL
BEGIN;
DELETE FROM $SCHEMA.streams_access WHERE watershed_group_code IN ($IN_LIST);
INSERT INTO $SCHEMA.streams_access SELECT * FROM $BAK.streams_access;
DELETE FROM $SCHEMA.streams_mapping_code WHERE watershed_group_code IN ($IN_LIST);
INSERT INTO $SCHEMA.streams_mapping_code SELECT * FROM $BAK.streams_mapping_code;
$(for t in $HAB_TABLES; do printf 'DELETE FROM %s.%s WHERE watershed_group_code IN (%s);\nINSERT INTO %s.%s SELECT * FROM %s.%s;\n' "$SCHEMA" "$t" "$IN_LIST" "$SCHEMA" "$t" "$BAK" "$t"; done)
COMMIT;
SQL
}
digest() {
  "${PSQL[@]}" --csv -q -v schema="$SCHEMA" -f "$REPO_ROOT/data-raw/recompute_checksum.sql" \
    | grep -E "^(tbl|[a-z_]+,($(csv_lines "$WSGS" | paste -sd'|' -)),)" > "$1"
}
run_pass() {
  local label="$1" width="$2" t0 t1
  RC_DIR="$OUT_DIR/${TS}_${label}.d"; ALL_WSGS="$WSGS"
  rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
  t0=$(date +%s); run_recompute_pool "$width"; t1=$(date +%s)
  local rc_tsv="$RC_DIR.tsv"; : > "$rc_tsv"
  find "$RC_DIR" -name '*.rc' -exec cat {} + >> "$rc_tsv"
  ( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/fanout_judge.R "$rc_tsv" "$WSGS" "width-$label" ) >&2 \
    || { echo "FATAL: pass $label incomplete" >&2; restore; exit 1; }
  echo $((t1 - t0))
}
( cd "$REPO_ROOT" && LNK_LOAD=loadall LNK_SCHEMA="$SCHEMA" Rscript data-raw/barriers_views_build.R "$CONFIG" ) >/dev/null
export LNK_SCHEMA="$SCHEMA"
echo "=== width bench $TS: $SCHEMA $CONFIG, $(csv_lines "$WSGS" | wc -l | tr -d ' ') groups, widths $W1 $W2"
digest "$OUT_DIR/${TS}_pre.csv"
snapshot
SEC1=$(run_pass "j$W1" "$W1"); echo "  -j$W1: $SEC1 s  (load: $(uptime | sed 's/.*averages: //'))"
restore
SEC2=$(run_pass "j$W2" "$W2"); echo "  -j$W2: $SEC2 s  (load: $(uptime | sed 's/.*averages: //'))"
restore
digest "$OUT_DIR/${TS}_post.csv"
if cmp -s "$OUT_DIR/${TS}_pre.csv" "$OUT_DIR/${TS}_post.csv"; then echo "  restore: rows identical to before"; else echo "  RESTORE MISMATCH: compare ${TS}_pre.csv and ${TS}_post.csv"; fi
"${PSQL[@]}" -q -c "DROP SCHEMA $BAK CASCADE"
printf '  speedup -j%s over -j%s: %.2fx\n' "$W2" "$W1" "$(awk -v a="$SEC1" -v b="$SEC2" 'BEGIN{print (b>0)?a/b:0}')"
