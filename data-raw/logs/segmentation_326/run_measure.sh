#!/usr/bin/env bash
# run_measure.sh — #326 Phase 4 measurements over the builds run_phase4.sh left.
set -uo pipefail
O=data-raw/logs/segmentation_326
ELEVEN="LKEL BULK KISP USKE MORR PCEA FINA PARS LFRA KOTR ELKR"
Rscript data-raw/breaks_diff.R $ELEVEN --schema=fresh --out=$O > $O/breaks_diff.log 2>&1; echo "breaks_diff exit=$?"
LNK_LOAD=loadall LNK_SCHEMA=fresh LNK_CONFIG=bcfishpass LNK_PARITY_OUT=$O/parity_crosssection.csv \
  Rscript data-raw/parity_crosssection.R $ELEVEN > $O/parity_crosssection.log 2>&1; echo "parity exit=$?"
for w in PCEA FINA PARS LKEL; do for f in rearing spawning; do
  LNK_OUT=$O/habitat_diff Rscript data-raw/habitat_diff_segments.R $w bt fresh $f > $O/habitat_diff_${w}_${f}.log 2>&1
  echo "habitat_diff $w $f exit=$?"
done; done
echo MEASURE_DONE
