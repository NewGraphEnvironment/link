#!/usr/bin/env bash
# run_round2.sh — #326 Phase 4 round 2: the same re-models as run_phase4.sh at
# the unify fix (21e0fea2), `default` AFTER and `bcfishpass` AFTER only (the
# BEFORE build is main's and does not change), then the measurements.
# Logs go to <dir>/round2/. LARL was re-modelled at the branch in round 1, so
# ELKR's downstream barriers are current.
# Usage: bash run_round2.sh <POST worktree>   (run from the repo root)
set -uo pipefail
POST="$1"
DIR="$(cd "$(dirname "$0")" && pwd)/round2"
mkdir -p "$DIR"
STATUS="$DIR/status.tsv"
stamp() { date -u +%FT%TZ; }
printf 'step\twsg\tstart_utc\tend_utc\texit\n' > "$STATUS"
run() {  # run <step> <script> <wsg> <config> <schema>
  local step="$1" script="$2" wsg="$3" config="$4" schema="$5"
  local log="$DIR/${step}_${wsg}.log" s e rc try
  for try in 1 2; do
    s=$(stamp)
    ( cd "$POST" && LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
        LNK_RUN_UID="326_r2_${step}" LNK_RUN_LABEL="326_r2_${step}_${wsg}" \
        LNK_SCHEMA="$schema" \
        Rscript "data-raw/$script" "$wsg" "$config" ) > "$log" 2>&1
    rc=$?
    e=$(stamp)
    printf '%s\t%s\t%s\t%s\t%s\n' "$step" "$wsg" "$s" "$e" "$rc" >> "$STATUS"
    echo "[round2] $e $step $wsg exit=$rc (try $try)"
    [ "$rc" -eq 0 ] && return 0
    # The `default` recompute's last check fails on the Peace dams in UPCE,
    # which no dev schema here holds; its work is done by then. Do not retry.
    grep -q "BLOCKED (link#227)" "$log" && return 1
  done
  return 1
}
FOUR="PCEA FINA PARS LKEL"
ELEVEN="LKEL BULK KISP USKE MORR PCEA FINA PARS LFRA KOTR ELKR"
for w in $FOUR; do run default_post wsg_run_one.R "$w" default fresh_default; done
for w in $ELEVEN; do run bcfishpass_post wsg_run_one.R "$w" bcfishpass fresh; done
for w in $FOUR; do run recompute_default_post wsg_recompute_one.R "$w" default fresh_default; done
for w in $ELEVEN; do run recompute_bcfishpass_post wsg_recompute_one.R "$w" bcfishpass fresh; done

O=data-raw/logs/segmentation_326/round2
Rscript data-raw/breaks_diff.R $ELEVEN --schema=fresh --out=$O > $O/breaks_diff.log 2>&1; echo "breaks_diff exit=$?"
LNK_LOAD=loadall LNK_SCHEMA=fresh LNK_CONFIG=bcfishpass LNK_PARITY_OUT=$O/parity_crosssection.csv \
  Rscript data-raw/parity_crosssection.R $ELEVEN > $O/parity_crosssection.log 2>&1; echo "parity exit=$?"
for w in $FOUR; do for f in rearing spawning; do
  LNK_OUT=$O/habitat_diff Rscript data-raw/habitat_diff_segments.R $w bt fresh $f > $O/habitat_diff_${w}_${f}.log 2>&1
  echo "habitat_diff $w $f exit=$?"
done; done
for sp in bt ch co st wct sk cm pk; do
  psql -h localhost -U postgres -d fwapg -At -F, -v schema=fresh -v view=barriers_${sp}_access \
    -v acc=access_${sp} -v sp=$sp -f data-raw/logs/segmentation_326/unbroken_frontiers.sql
done > $O/unbroken_frontiers.csv; echo "unbroken exit=$?"
echo ROUND2_DONE
