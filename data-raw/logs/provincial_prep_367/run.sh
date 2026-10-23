#!/usr/bin/env bash
set -uo pipefail
L=<scratchpad>/p3
BR=<repo>
WM=<scratchpad>/wt_main
KO=<scratchpad>/bundle_knob_off
export LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn PGPASSWORD=postgres
{ echo "started $(date -u +%FT%TZ)"; echo "branch $(git -C $BR rev-parse --short HEAD) dirty_files=$(git -C $BR status --porcelain | wc -l | tr -d ' ')"; echo "main $(git -C $WM rev-parse --short HEAD)"; Rscript -e 'cat("fresh", as.character(packageVersion("fresh")), "\n")'; psql -h localhost -U postgres -d fwapg -Atc "select 'pscis_loaded', max(loaded_at) from provenance.source_artifact where table_name like 'whse_fish.pscis%'"; } > $L/stamp.txt 2>&1
lock()   { until mkdir "$L/locks/$1" 2>/dev/null; do sleep 10; done; }
unlock() { rmdir "$L/locks/$1"; }
# run <dir> <script> <schema> <wsg> <config> <tag>
run() { lock $4; ( cd $1 && LNK_SCHEMA=$3 Rscript data-raw/$2 $4 $5 > $L/$6_$3_$4.log 2>&1 ); r=$?; unlock $4; echo "$(date -u +%TZ) $6 $3 $4 exit $r" >> $L/status.txt; [ $r -eq 0 ] || echo FAIL >> $L/fail.txt; }
lane1() {
  for w in ADMS ELKR; do run $BR wsg_run_one.R fresh_367a $w default build; run $BR wsg_run_one.R fresh_367b $w default build; done
  run $BR wsg_run_one.R fresh_367a NATR default build
  run $WM wsg_run_one.R fresh_367m NATR default build
}
lane2() {
  for w in LARL KETL SKGT; do run $BR wsg_run_one.R fresh_367a $w default build; run $BR wsg_run_one.R fresh_367c $w $KO build; done
  for w in LARL KETL SKGT; do run $BR wsg_recompute_one.R fresh_367a $w default recompute; run $BR wsg_recompute_one.R fresh_367c $w $KO recompute; done
  for w in ADMS ELKR; do run $WM wsg_run_one.R fresh_367m $w default build; done
}
lane1 & p1=$!
lane2 & p2=$!
wait $p1; wait $p2
echo "ALLDONE fails=$(cat $L/fail.txt 2>/dev/null | wc -l | tr -d ' ') $(date -u +%FT%TZ)" >> $L/status.txt
