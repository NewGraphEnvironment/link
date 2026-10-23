#!/usr/bin/env bash
# split_test.sh — can a drainage component be modelled across hosts in any
# order, once the post-consolidate recompute has settled it? (link#361)
#
# Models the Peace component (26 groups) as two "hosts" would in the WORST
# order, then recomputes, and digests every persisted table against the
# reference build of the same groups: the provincial run's, where the whole
# component ran on one host downstream-first (`study_area_run.sh`).
#
#   host A = fresh_361a   odd positions of the DS-first order, REVERSED
#   host B = fresh_361b   even positions of the DS-first order, REVERSED
#
# so every group is modelled before the groups downstream of it that the
# same host holds, and half of its downstream groups are on the other host.
# Each schema is a separate database state at model time, as two cypher
# databases are; `LNK_GUARD_DOWNSTREAM=warn` and `LNK_HABITAT_GATE=0` are
# what the driver sets on both legs. B is then consolidated into A the way
# `schema_consolidate.R` does for persist tables (delete the bucket, insert
# it), the barrier views are built once, and every group is recomputed in A
# with the guard in its default `error` mode: a guard failure there is a
# finding, not something to retry.
#
# The digests (`split_compare.R`) are per group and per table, so a
# difference names what the component rule protects. `log*` tables are
# excluded: they differ by construction (timestamps, hosts, the guard's notes).
#
# Usage (from the repo root, tree clean, on the branch the run was built from):
#   /opt/homebrew/bin/bash data-raw/logs/provincial_361/split_test.sh [--force]
#
#   --force   drop fresh_361a / fresh_361b if they exist (a re-run)
#
# Reads: the local docker fwapg (localhost:5432), <REF>.log for the link SHA
#        the reference groups were built at.
# Writes: schemas fresh_361a, fresh_361b; files under this directory
#        (stamp.txt, status.txt, build_<schema>_<wsg>.log, recompute_<wsg>.log,
#         split_test.csv, split_test_summary.txt).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$REPO_ROOT/data-raw/logs/provincial_361"
A=fresh_361a
B=fresh_361b
REF=${SPLIT_REF:-fresh_default}
CONTROL=${SPLIT_CONTROL:-fresh_default_20261017}
CONFIG=default
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

export PGPASSWORD=postgres
PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg -v ON_ERROR_STOP=1 -qAt)
export LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0
export LNK_RUN_LABEL=split-test-361

say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$OUT/status.txt"; }
die() { say "FATAL: $*"; exit 1; }

cd "$REPO_ROOT" || die "cd $REPO_ROOT"

# --- preconditions, all cheap -------------------------------------------------
[ -z "$(git status --porcelain)" ] || die "working tree is dirty; the build stamps link_dirty"
SHA=$(git rev-parse --short=8 HEAD)
REF_SHA=$("${PSQL[@]}" -c "SELECT string_agg(DISTINCT left(link_sha, 8), ',')
  FROM (SELECT DISTINCT ON (watershed_group_code) link_sha FROM $REF.log
         WHERE date_end IS NOT NULL ORDER BY watershed_group_code, date_start DESC) l") \
  || die "cannot read $REF.log"
[ "$REF_SHA" = "$SHA" ] || die "HEAD $SHA is not the reference build's link SHA ($REF_SHA); check out that commit"
for s in $A $B; do
  if [ "$("${PSQL[@]}" -c "SELECT count(*) FROM information_schema.schemata WHERE schema_name='$s'")" = "1" ]; then
    [ "$FORCE" = "1" ] || die "schema $s exists; pass --force to drop it"
    "${PSQL[@]}" -c "DROP SCHEMA $s CASCADE" || die "drop $s"
    say "dropped $s"
  fi
done

# --- the order ------------------------------------------------------------------
PEACE=CARP,CRKD,FINA,FINL,FIRE,FOXR,INGR,KISK,LBTN,LHAF,LOMI,LPCE,MESI,MILL,MURR,NATR,OSPK,PARA,PARS,PCEA,PINE,TOOD,UBTN,UHAF,UOMI,UPCE
DS=$(Rscript data-raw/study_area_wsgs.R "$PEACE" $CONFIG 2>/dev/null | tr -d '[:space:]') || die "study_area_wsgs.R"
[ "$(echo "$DS" | tr ',' '\n' | wc -l | tr -d ' ')" = "26" ] || die "expected 26 groups DS-first, got: $DS"
# positions 1,3,5,... -> A; 2,4,6,... -> B; each reversed so upstream runs first
rev_lines() { awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }'; }   # tail -r is BSD-only
ORDER_A=$(echo "$DS" | tr ',' '\n' | awk 'NR % 2 == 1' | rev_lines | paste -sd' ' -)
ORDER_B=$(echo "$DS" | tr ',' '\n' | awk 'NR % 2 == 0' | rev_lines | paste -sd' ' -)
RUN_UID="$(date -u +%Y%m%d_%H%M%S)-$SHA"

{
  echo "started $(date -u +%FT%TZ)"
  echo "link $SHA (branch $(git rev-parse --abbrev-ref HEAD)); reference $REF at $REF_SHA"
  Rscript -e 'cat("fresh", as.character(packageVersion("fresh")), "\n")'
  echo "run_uid $RUN_UID"
  echo "ds_first $DS"
  echo "host_A $A: $ORDER_A"
  echo "host_B $B: $ORDER_B"
  "${PSQL[@]}" -c "SELECT 'primitives_loaded ' || max(loaded_at) FROM provenance.source_artifact WHERE recorded_by = 'loader'"
} > "$OUT/stamp.txt"
say "stamp written; A=[$ORDER_A] B=[$ORDER_B]"

# --- model, two lanes -------------------------------------------------------------
build() {  # $1 schema, $2 wsg
  local r
  LNK_SCHEMA=$1 LNK_RUN_UID=$RUN_UID Rscript data-raw/wsg_run_one.R "$2" $CONFIG \
    > "$OUT/build_$1_$2.log" 2>&1; r=$?
  say "build $1 $2 exit $r"
  [ $r -eq 0 ] || echo "build $1 $2" >> "$OUT/fail.txt"
}
lane() { for w in $2; do build "$1" "$w"; done; }
: > "$OUT/fail.txt"
lane $A "$ORDER_A" & pa=$!
lane $B "$ORDER_B" & pb=$!
wait $pa; wait $pb
[ ! -s "$OUT/fail.txt" ] || die "builds failed: $(paste -sd';' "$OUT/fail.txt")"
say "both lanes built"

# --- consolidate B -> A (persist tables; log tables travel too, A holds none of B's groups)
B_LIST=$(echo "$ORDER_B" | tr ' ' '\n' | sed "s/.*/'&'/" | paste -sd, -)
TABLES=$("${PSQL[@]}" -c "SELECT t.table_name FROM information_schema.tables t
  WHERE t.table_schema = '$B' AND t.table_type = 'BASE TABLE'
    AND EXISTS (SELECT 1 FROM information_schema.columns c
                 WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name
                   AND c.column_name = 'watershed_group_code')
    AND EXISTS (SELECT 1 FROM information_schema.tables a
                 WHERE a.table_schema = '$A' AND a.table_name = t.table_name)
  ORDER BY 1")
for t in $TABLES; do
  COLS=$("${PSQL[@]}" -c "SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    FROM information_schema.columns WHERE table_schema = '$A' AND table_name = '$t'")
  "${PSQL[@]}" -1 -c "DELETE FROM $A.$t WHERE watershed_group_code IN ($B_LIST);
    INSERT INTO $A.$t ($COLS) SELECT $COLS FROM $B.$t WHERE watershed_group_code IN ($B_LIST);" \
    || die "consolidate $t"
  say "consolidated $t: $("${PSQL[@]}" -c "SELECT count(*) FROM $A.$t WHERE watershed_group_code IN ($B_LIST)") rows"
done
# every group must now be in A once
N=$("${PSQL[@]}" -c "SELECT count(DISTINCT watershed_group_code) FROM $A.streams")
[ "$N" = "26" ] || die "$A.streams holds $N groups after consolidate, expected 26"

# --- recompute in A, guard in error mode, DS-first (the driver's order) -------------
unset LNK_GUARD_DOWNSTREAM LNK_HABITAT_GATE
LNK_SCHEMA=$A Rscript data-raw/barriers_views_build.R $CONFIG > "$OUT/recompute_views.log" 2>&1 \
  || die "barriers_views_build.R (see recompute_views.log)"
for w in $(echo "$DS" | tr ',' ' '); do
  LNK_SCHEMA=$A LNK_VIEWS_PREBUILT=1 LNK_RUN_UID=$RUN_UID \
    Rscript data-raw/wsg_recompute_one.R "$w" $CONFIG > "$OUT/recompute_$w.log" 2>&1; r=$?
  say "recompute $w exit $r"
  [ $r -eq 0 ] || echo "recompute $w" >> "$OUT/fail.txt"
done
[ ! -s "$OUT/fail.txt" ] || die "recomputes failed: $(paste -sd';' "$OUT/fail.txt")"

# --- evidence the order was bad: the guard's warn notes, per group ------------------
"${PSQL[@]}" -F $'\t' -c "SELECT watershed_group_code, host, notes FROM $A.log
  WHERE run_uid = '$RUN_UID' AND notes LIKE '%guard(warn)%' ORDER BY 1" > "$OUT/guard_warnings.tsv"
say "guard warned on $(wc -l < "$OUT/guard_warnings.tsv" | tr -d ' ') groups at model time (guard_warnings.tsv)"

# --- digests ---------------------------------------------------------------------------
Rscript "$OUT/split_compare.R" "$OUT" "$A" "$REF" "$CONTROL" "$DS" > "$OUT/split_compare.log" 2>&1; r=$?
say "split_compare.R exit $r"
cat "$OUT/split_test_summary.txt" 2>/dev/null | tee -a "$OUT/status.txt"
say "ALLDONE"
