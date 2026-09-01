#!/usr/bin/env bash
# recompute_sweep.sh — time the post-consolidate recompute across pool widths
# (link#250 acceptance: "watch Postgres connection count and work_mem at
# N-wide ... is the thing to measure, not assume").
#
# Usage:
#   bash data-raw/recompute_sweep.sh "WSG,WSG,..." [config] [widths...]
#
# Safe to run repeatedly without restoring state: the recompute reaches a
# fixed point after one application (proved as pass B of
# data-raw/recompute_parity.sh), so every width after the first operates on
# identical input and the comparison is fair.
#
# Reports peak backend count and peak parallel-worker count sampled from
# pg_stat_activity DURING each pass, because the scarce resource is not what
# it looks like from the host: the work is server-side, and a single recompute
# query can already saturate the cluster's whole parallel-worker pool.
#
# Extracts the shipped pool from study_area_run.sh rather than copying it.

set -euo pipefail

WSGS="${1:?usage: recompute_sweep.sh \"WSG,WSG,...\" [config] [widths...]}"
CONFIG="${2:-bcfishpass}"
shift 2 2>/dev/null || shift $#
WIDTHS=("$@")
[ ${#WIDTHS[@]} -gt 0 ] || WIDTHS=(1 2 4)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="$REPO_ROOT/data-raw/study_area_run.sh"
SCHEMA="${LNK_SCHEMA:-fresh}"
OUT_DIR="$REPO_ROOT/data-raw/logs/recompute_parity"
TS="$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
export PGPASSWORD=postgres
PSQL=(psql -h localhost -p 5432 -U postgres -d fwapg -t -A)

eval "$(sed -n '/^csv_lines() {/p' "$RUN_SH")"
eval "$(awk '/^recompute_one\(\)/,/^}/'      "$RUN_SH")"
eval "$(awk '/^run_recompute_pool\(\)/,/^}/' "$RUN_SH")"

export LNK_SCHEMA="$SCHEMA"
N_WSG=$(csv_lines "$WSGS" | wc -l | tr -d ' ')
# ${1:?} rejects an unset/empty arg but not "," -- and with N_WSG=0 the
# per-width failure marker below compares 0 reported against 0 expected and
# passes, printing a clean timing table over zero measured jobs. This is the
# only pool consumer that does not call lnk_fanout_judge, so it needs its own
# empty branch.
[ "$N_WSG" -gt 0 ] || { echo "FATAL: no WSGs resolved from '$WSGS'" >&2; exit 1; }

echo "=== recompute width sweep $TS ==="
echo "  WSGs:   $WSGS ($N_WSG)"
echo "  widths: ${WIDTHS[*]}"
"${PSQL[@]}" -c "SELECT '  pg: '||name||' = '||setting FROM pg_settings
  WHERE name IN ('max_parallel_workers','max_parallel_workers_per_gather',
                 'max_worker_processes','max_connections');"

( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/barriers_views_build.R "$CONFIG" ) >/dev/null

# Warm pass: first run pays cold cache and any not-yet-converged access rows.
# SWEEP_WARM=0 skips it when a previous sweep has already converged the state
# -- the recompute is idempotent, so a second sweep does not need it.
if [ "${SWEEP_WARM:-1}" = "1" ]; then
  echo "--- warm-up (-j1, not timed)"
  RC_DIR="$OUT_DIR/${TS}_warm.d"; rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
  ALL_WSGS="$WSGS"; run_recompute_pool 1 >/dev/null 2>&1
  rm -rf "$RC_DIR"
else
  echo "--- warm-up skipped (SWEEP_WARM=0)"
fi
# PGOPTIONS reaches every job's libpq connection, so a per-session Postgres
# setting can be swept WITHOUT touching the server's global config:
#   PGOPTIONS='-c max_parallel_workers_per_gather=0' bash data-raw/recompute_sweep.sh ...
[ -z "${PGOPTIONS:-}" ] || echo "  PGOPTIONS: $PGOPTIONS"

printf '\n%-6s %8s %8s %9s %10s %8s\n' width secs "per-WSG" speedup backends workers
BASE=0
for w in "${WIDTHS[@]}"; do
  RC_DIR="$OUT_DIR/${TS}_j${w}.d"; rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
  ALL_WSGS="$WSGS"
  SAMPLE="$OUT_DIR/${TS}_j${w}.samples"; : > "$SAMPLE"
  # Sample server-side concurrency while the pass runs. `leader_pid IS NOT
  # NULL` identifies a parallel worker, which is the number that actually
  # explains the scaling here -- host cores and connection count both look
  # abundant and neither is the constraint.
  ( while :; do
      "${PSQL[@]}" -c "SELECT count(*) FILTER (WHERE state='active' AND leader_pid IS NULL)
                            ||' '||count(*) FILTER (WHERE leader_pid IS NOT NULL)
                         FROM pg_stat_activity WHERE datname='fwapg'" >> "$SAMPLE" 2>/dev/null || true
      sleep 2
    done ) &
  SAMPLER=$!
  # disown so a bare `wait` anywhere cannot see it. run_recompute_pool waits
  # on its own pids only (link#250), but the sampler must not depend on that.
  disown "$SAMPLER" 2>/dev/null || true
  T0=$(date +%s); run_recompute_pool "$w" >/dev/null 2>&1; T1=$(date +%s)
  kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true
  SEC=$((T1 - T0)); [ "$BASE" = "0" ] && BASE=$SEC
  PEAK_B=$(awk '{if($1>m)m=$1}END{print m+0}' "$SAMPLE")
  PEAK_W=$(awk '{if($2>m)m=$2}END{print m+0}' "$SAMPLE")
  NFAIL=$(find "$RC_DIR" -name '*.rc' -exec cat {} + | awk -F'\t' '$2!="0"' | wc -l | tr -d ' ')
  NRC=$(find "$RC_DIR" -name '*.rc' | wc -l | tr -d ' ')
  printf '%-6s %8s %8.1f %8.2fx %10s %8s%s\n' "-j$w" "$SEC" \
    "$(awk -v s="$SEC" -v n="$N_WSG" 'BEGIN{print s/n}')" \
    "$(awk -v b="$BASE" -v s="$SEC" 'BEGIN{print (s>0)?b/s:0}')" \
    "$PEAK_B" "$PEAK_W" \
    "$([ "$NRC" = "$N_WSG" ] && [ "$NFAIL" = "0" ] || echo "  <-- $NFAIL failed / $NRC of $N_WSG reported")"
  # Per-job logs KEPT. The makespan of a pool is bounded below by its longest
  # single job, so "why did -jN not scale" is answered by the per-WSG times
  # and by nothing else -- deleting them here cost two wrong diagnoses
  # (a Postgres worker-pool theory and a Docker I/O theory) before the
  # distribution was looked at. link#250.
done

echo
echo "--- slowest jobs per width (the makespan floor is the slowest single one)"
for w in "${WIDTHS[@]}"; do
  D="$OUT_DIR/${TS}_j${w}.d"
  [ -d "$D" ] || continue
  printf '  -j%-3s ' "$w"
  # `|| true`: grep exits 1 when a width produced no per-job timings at all,
  # which is exactly the all-failed case this summary exists to explain --
  # under `set -euo pipefail` that would kill the script instead.
  TIMES=$(grep -ho 'recomputed in [0-9.]* min' "$D"/*.log 2>/dev/null | awk '{print $3}' || true)
  if [ -z "$TIMES" ]; then
    echo "(no per-job timings — every job failed, or none ran)"
  else
    printf '%s\n' "$TIMES" | sort -rn \
      | awk 'NR==1{mx=$1} NR<=3{printf "%s ", $1"min"} {s+=$1}
             END{printf " (sum %.1f min, slowest = %.0f%% of it)\n", s, (s>0)?100*mx/s:0}'
  fi
done
echo
echo "peak backends = concurrent non-worker sessions; peak workers = parallel"
echo "workers in flight (capped cluster-wide by max_parallel_workers)."
