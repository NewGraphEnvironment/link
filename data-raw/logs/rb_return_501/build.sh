#!/usr/bin/env bash
# Phase 5 of link#501: build three groups under `default` in three states, each
# from its own git worktree, into scratch schemas on local fwapg, one at a time
# (the states share working_<wsg> schemas).
#   main   origin/main (RB paused, the record rule of #470)
#   paused this branch with RB paused again: the record rule and presence alone
#   ship   this branch as it ships
# Usage: bash build.sh <branch sha> <main sha> <scratch dir>
set -euo pipefail
SHIP=$1; MAIN=$2; TMP=$3
WSGS="LKEL GRNL NBNK"
mk() {  # name ref
  local d="$TMP/wt_$1"
  [ -d "$d" ] || git worktree add -q --detach "$d" "$2"
  echo "$d"
}
D_MAIN=$(mk main "$MAIN"); D_SHIP=$(mk ship "$SHIP"); D_PAUSED=$(mk paused "$SHIP")
# The paused state: RB back to f, and an acc row for its spec, both uncommitted
# in that worktree only (its builds log link_dirty TRUE).
( cd "$D_PAUSED"
  if ! grep -q '^RB,f,' inst/extdata/configs/default/species_modelled.csv; then
    sed -i '' 's/^RB,t,,,#497$/RB,f,"paused for the #501 three-state build",2026-11-23,#501/' \
      inst/extdata/configs/default/species_modelled.csv
    Rscript -e 'pkgload::load_all(quiet=TRUE); cfg<-lnk_config("default"); l<-suppressWarnings(lnk_load_overrides(cfg)); s<-.lnk_vocabulary_spec_acc(cfg,l); cat(sprintf("\"acc-tmp501\",\"acc\",\"#501 paused-state build only\",\"%s\",\"0.90.0\",\n", s), file="inst/extdata/vocabulary.csv", append=TRUE)'
  fi
  grep '^RB,' inst/extdata/configs/default/species_modelled.csv )
for state in main paused ship; do
  case $state in main) D=$D_MAIN;; paused) D=$D_PAUSED;; ship) D=$D_SHIP;; esac
  for w in $WSGS; do
    echo "=== $state $w $(date -u +%H:%M:%S)"
    ( cd "$D" && LNK_LOAD=loadall LNK_SCHEMA="fresh_rb501_$state" \
        LNK_RUN_LABEL="rb501-$state" LNK_GUARD_DOWNSTREAM=warn \
        LNK_GUARD_DOWNSTREAM_NOTE="link#501 three-state scratch build" \
        Rscript data-raw/wsg_run_one.R "$w" default ) 2>&1 | grep -E "done|ERROR|Error|TIMEOUT|tokens|warn" || true
  done
done
echo "=== all done $(date -u +%H:%M:%S)"
