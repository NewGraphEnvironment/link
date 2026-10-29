#!/usr/bin/env bash
# model_run.sh — link#409 Phase 3: build ADMS, NATR and ELKR twice on one host,
# into fresh_409b with the shared library's fresh (v0.44.0) and into fresh_409a
# with fresh v0.46.0 put first by R_LIBS, from one worktree, so the two builds
# differ only in fresh. Interleaved b, a per group. compare.R digests them.
#   WT=<worktree> LIB046=<lib holding fresh 0.46.0> OUT=<log dir> bash model_run.sh
set -uo pipefail
: "${WT:?}" "${LIB046:?}" "${OUT:?}"
export LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn
mkdir -p "$OUT"
{
  echo "started $(date -u +%FT%TZ)"
  echo "link $(git -C "$WT" rev-parse HEAD) dirty_files=$(git -C "$WT" status --porcelain | wc -l | tr -d ' ')"
  Rscript -e 'cat("fresh_409b", as.character(packageVersion("fresh")), utils::packageDescription("fresh")$RemoteSha, "\n")'
  R_LIBS="$LIB046" Rscript -e 'cat("fresh_409a", as.character(packageVersion("fresh")), utils::packageDescription("fresh")$RemoteSha, "\n")'
} > "$OUT/stamp.txt" 2>&1
run() { # <schema> <wsg> [R_LIBS]
  local t0=$SECONDS r
  ( cd "$WT" && LNK_SCHEMA=$1 R_LIBS="${3:-}" Rscript data-raw/wsg_run_one.R "$2" default > "$OUT/build_$1_$2.log" 2>&1 )
  r=$?
  echo "$(date -u +%TZ) $1 $2 exit $r $((SECONDS - t0)) s" >> "$OUT/status.txt"
}
for w in ADMS NATR ELKR; do
  run fresh_409b "$w"
  run fresh_409a "$w" "$LIB046"
done
echo "ALLDONE $(date -u +%FT%TZ)" >> "$OUT/status.txt"
