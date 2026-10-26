#!/usr/bin/env bash
# headroom.sh — link#374: does a -j8 recompute running beside the dispatcher's
# modelling slow the modelling? A-B-A on one database: model the same groups
# alone, then while a recompute pool runs, then alone again (so a cache that
# warms between passes cannot read as contention).
#
# Model groups go to scratch <model schema>, recompute jobs to scratch
# <recompute schema> (built by headroom_setup.R, views by
# barriers_views_build.R) with LNK_LOG=0. Neither touches fresh_default.
#
# Usage (repo root): bash data-raw/logs/recompute_early_374/headroom.sh \
#   <model schema> <model groups csv> <recompute schema> <recompute groups csv> <out dir> [width]
set -euo pipefail
MS="$1"; MG="$2"; RS="$3"; RG="$4"; OUT="$5"; W="${6:-8}"
case "$MS$RS" in *fresh_default*) echo "refusing fresh_default" >&2; exit 1 ;; esac
mkdir -p "$OUT/jobs"
STOP="$OUT/STOP"; rm -f "$STOP"
TSV="$OUT/headroom.tsv"
printf 'pass\twsg\tstart_utc\tend_utc\tminutes\trc\n' > "$TSV"

model_pass() {   # $1 = pass label
  local w s e si ei rc
  for w in $(printf '%s' "$MG" | tr ',' ' '); do
    s=$(date -u +%s); si=$(date -u +%FT%TZ); rc=0
    LNK_SCHEMA="$MS" LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 \
      Rscript data-raw/wsg_run_one.R "$w" default > "$OUT/model_$1_$w.log" 2>&1 || rc=$?
    e=$(date -u +%s); ei=$(date -u +%FT%TZ)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$w" "$si" "$ei" \
      "$(awk -v a="$s" -v b="$e" 'BEGIN { printf "%.2f", (b - a) / 60 }')" "$rc" >> "$TSV"
  done
}

echo "=== A1 alone $(date -u +%FT%TZ)"
model_pass A1

echo "=== B with a -j$W recompute $(date -u +%FT%TZ)"
# Twenty passes over the recompute groups, more than B needs; each job checks
# STOP before it starts, so the pool drains once B's modelling is done.
for i in $(seq 1 20); do printf '%s\n' "$RG" | tr ',' '\n' | sed "s/\$/ $i/"; done \
  | xargs -P "$W" -L 1 sh -c '
      [ -f "$0" ] && exit 0
      LNK_LOG=0 LNK_VIEWS_PREBUILT=1 LNK_LOAD=loadall LNK_SCHEMA="$1" \
        Rscript data-raw/wsg_recompute_one.R "$3" default > "$2/jobs/$3_$4.log" 2>&1 || true
    ' "$STOP" "$RS" "$OUT" &
POOL=$!
sleep 90
model_pass B
touch "$STOP"
echo "  draining the pool $(date -u +%FT%TZ)"
wait "$POOL" || true

echo "=== A2 alone $(date -u +%FT%TZ)"
model_pass A2
echo "=== done $(date -u +%FT%TZ)"
