#!/usr/bin/env bash
# measure.sh — link#260: the fixed per-job prologue cost of the recompute pool.
# Run from anywhere; writes timings.tsv and env.txt beside itself.
#   seq:  N fresh Rscript processes one after another, per mode
#   conc: WAVES waves of WIDTH concurrent prologues, per mode (-j8's shape,
#         every slot in its prologue at once)
#   busy: N/2 sequential prologues per mode beside BUSY CPU-bound R processes
#         (-j8's other shape: one slot starting while seven compute)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
N="${N:-20}"; WIDTH="${WIDTH:-8}"; WAVES="${WAVES:-3}"; BUSY="${BUSY:-7}"
OUT="$HERE/timings.tsv"; ENV="$HERE/env.txt"
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
one() {  # $1 mode, $2 label
  ( cd "$REPO" && LNK_T_SHELL="$(now)" Rscript "$HERE/prologue.R" "$1" "$2" )
}
{
  echo "date_utc	$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "link_head	$(git -C "$REPO" rev-parse --short HEAD)"
  echo "link_dirty	$(git -C "$REPO" status --porcelain | wc -l | tr -d ' ') paths"
  echo "installed_link	$(Rscript -e 'cat(as.character(packageVersion("link")))')"
  echo "r	$(Rscript -e 'cat(R.version.string)')"
  echo "ncpu	$(sysctl -n hw.ncpu)"
  echo "uptime_before	$(uptime | sed 's/.*load/load/')"
  echo "pg_active_before	$(psql "postgresql://postgres:postgres@localhost:5432/fwapg" -Atc \
    "select count(*) from pg_stat_activity where backend_type='client backend' and state='active' and pid<>pg_backend_pid()")"
} > "$ENV"
printf 'label\tmode\tr_start\tload\tdb_libs\tconnect\tset\tconfig\toverrides\tspecies\ttotal\n' > "$OUT"
for mode in loadall library; do
  for i in $(seq 1 "$N"); do one "$mode" "seq$i" >> "$OUT"; done
done
for mode in loadall library; do
  for w in $(seq 1 "$WAVES"); do
    pids=()
    for s in $(seq 1 "$WIDTH"); do
      one "$mode" "conc_w${w}_s${s}" > "$HERE/.conc_${mode}_${w}_${s}.tmp" &
      pids+=("$!")
    done
    for p in "${pids[@]}"; do wait "$p"; done
    cat "$HERE"/.conc_*.tmp >> "$OUT"; rm -f "$HERE"/.conc_*.tmp
  done
done
busy_pids=()
cleanup() { for p in "${busy_pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
for b in $(seq 1 "$BUSY"); do
  Rscript -e 'x <- 0; repeat x <- x + sum(sqrt(seq_len(1e5)))' >/dev/null 2>&1 &
  busy_pids+=("$!")
done
sleep 2
for mode in loadall library; do
  for i in $(seq 1 $((N / 2))); do one "$mode" "busy$i" >> "$OUT"; done
done
cleanup; busy_pids=()
echo "uptime_after	$(uptime | sed 's/.*load/load/')" >> "$ENV"
echo "wrote $OUT ($(($(wc -l < "$OUT") - 1)) rows)"
