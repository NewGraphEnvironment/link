#!/usr/bin/env bash
# verify_evidence.sh — run study_area_verify.sql's evidence check (link#434)
# against the AFTER builds, healthy and broken.
#
#   bash data-raw/logs/record_rule_470/verify_evidence.sh
#
# The full verify script asks for recompute rows, a bcfp pin and loaded-input
# rows that these scratch builds do not carry, so the evidence block is cut
# out of the shipped file by its own comment lines and run alone, in a DO
# block declaring what it reads, over a copy of zz470_default_post's log,
# barrier_overrides and barrier_override_evidence in zz470_verify_ev. The
# copy's link_version is raised to 0.84.0 (the builds ran at 0.83.0, which
# the check leaves unjudged). Expected: healthy PASS, a lift's evidence
# deleted FAIL, an evidence row beside no lift FAIL, a lift listing fewer
# records than its threshold FAIL.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
export PGPASSWORD=postgres
PSQL=(psql -h localhost -U postgres -d fwapg -X -q -t -A -v ON_ERROR_STOP=1)
S=zz470_verify_ev
SRC=zz470_default_post
trap '"${PSQL[@]}" -c "DROP SCHEMA IF EXISTS $S CASCADE" >/dev/null 2>&1 || true' EXIT

BLOCK=$(awk '/-- What each lift rests on \(link#434\)/{p=1} /-- The bcfp pin, with the sanctioned-unpinned escape/{p=0} p' \
  "$ROOT/data-raw/study_area_verify.sql")
[ -n "$BLOCK" ] || { echo "evidence block not found"; exit 1; }

"${PSQL[@]}" >/dev/null <<SQL
DROP SCHEMA IF EXISTS $S CASCADE;
CREATE SCHEMA $S;
CREATE TABLE $S.log AS SELECT * FROM $SRC.log WHERE run_uid = '470_post';
UPDATE $S.log SET link_version = '0.84.0';
CREATE TABLE $S.barrier_overrides AS SELECT * FROM $SRC.barrier_overrides;
CREATE TABLE $S.barrier_override_evidence AS SELECT * FROM $SRC.barrier_override_evidence;
SQL

check() {  # check <label> <expect PASS|FAIL>
  local out rc
  set +e
  out=$("${PSQL[@]}" 2>&1 <<SQL
DO \$\$
DECLARE
  v_run text := '470_post';
  v_sch text := '$S';
  n_ev int; n_evthr int; bad text;
BEGIN
$BLOCK
  RAISE NOTICE 'evidence check passed';
END \$\$;
SQL
)
  rc=$?
  set -e
  local got=PASS; [ "$rc" -eq 0 ] || got=FAIL
  if [ "$got" = "$2" ]; then echo "  ok   $1 -> $got"; else echo "  WRONG $1 -> $got (expected $2)"; echo "$out" | tail -3; fails=$((fails + 1)); fi
}
fails=0
n=$("${PSQL[@]}" -c "SELECT count(*) || ' lifts, ' || (SELECT count(*) FROM $S.barrier_override_evidence) || ' evidence rows, ' || count(DISTINCT watershed_group_code) || ' groups' FROM $S.barrier_overrides")
echo "copy of $SRC: $n"
check "healthy" PASS
ROW=$("${PSQL[@]}" -c "SELECT watershed_group_code || '|' || species_code || '|' || blue_line_key || '|' || downstream_route_measure FROM $S.barrier_override_evidence WHERE evidence = 'observation' ORDER BY 1 LIMIT 1")
[ -n "$ROW" ] || { echo "no observation lift to break"; exit 1; }
IFS='|' read -r W SP BLK DRM <<< "$ROW"
WHERE="watershed_group_code = '$W' AND species_code = '$SP' AND blue_line_key = $BLK AND downstream_route_measure = $DRM"
"${PSQL[@]}" -c "CREATE TABLE $S.held AS SELECT * FROM $S.barrier_override_evidence WHERE $WHERE; DELETE FROM $S.barrier_override_evidence WHERE $WHERE" >/dev/null
check "$W $SP lift with no evidence" FAIL
"${PSQL[@]}" -c "INSERT INTO $S.barrier_override_evidence SELECT * FROM $S.held; CREATE TABLE $S.held_bo AS SELECT * FROM $S.barrier_overrides WHERE $WHERE; DELETE FROM $S.barrier_overrides WHERE $WHERE" >/dev/null
check "$W $SP evidence for no lift" FAIL
"${PSQL[@]}" -c "INSERT INTO $S.barrier_overrides SELECT * FROM $S.held_bo" >/dev/null
check "healthy, restored" PASS
"${PSQL[@]}" -c "UPDATE $S.barrier_override_evidence SET observation_threshold = 99 WHERE $WHERE AND evidence = 'observation'" >/dev/null
check "$W $SP lift below its threshold" FAIL
echo "wrong: $fails"
[ "$fails" -eq 0 ]
