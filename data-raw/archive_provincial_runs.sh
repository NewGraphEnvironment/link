#!/usr/bin/env bash
# Archive per-run artifacts in data-raw/logs/provincial_<bundle>/ to
# data-raw/logs/provincial_<bundle>/archive/<TS>/ so the LPT planner
# (both trifecta_provincial.sh inline and balance_provincial_buckets.R)
# sees only the LATEST run's _per_wsg_times.csv files in the top level.
#
# Operator cadence: run this BEFORE kicking off a new provincial run if
# you want the LPT to plan against the most recent run only. Skip if
# you want the planner to median-over multiple runs (helpful for
# smoothing out noisy one-offs but slower to react to host changes).
#
# Usage:
#   ./archive_provincial_runs.sh                          # bcfishpass (default)
#   ./archive_provincial_runs.sh --config=default         # different bundle
#
# What's archived:
#   - *_per_wsg_times.csv  (drives LPT)
#   - *.rds                (per-WSG rollups — these would be skipped on
#                            the next run as "cached"; archive forces re-runs)
#   - *_annotated.csv      (post-pull annotation outputs)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="bcfishpass"
for arg in "$@"; do
  case "$arg" in
    --config=*) CONFIG="${arg#--config=}" ;;
    *) echo "usage: $0 [--config=<bundle>]" >&2; exit 2 ;;
  esac
done

RDS_DIR_NAME="provincial_${CONFIG}"
[ "$CONFIG" = "bcfishpass" ] && RDS_DIR_NAME="provincial_parity"
SRC_DIR="$REPO_ROOT/data-raw/logs/$RDS_DIR_NAME"

if [ ! -d "$SRC_DIR" ]; then
  echo "[archive] $SRC_DIR does not exist — nothing to archive."
  exit 0
fi

# Find the top-level artifacts. find -maxdepth 1 so we don't touch
# existing archive/ subdirs.
SHOPT_GLOB=$(shopt -p nullglob || true)
shopt -s nullglob
csv_files=("$SRC_DIR"/*_per_wsg_times.csv "$SRC_DIR"/*_annotated.csv)
rds_files=("$SRC_DIR"/*.rds)
eval "$SHOPT_GLOB"

n_csv=${#csv_files[@]}
n_rds=${#rds_files[@]}
if [ "$n_csv" -eq 0 ] && [ "$n_rds" -eq 0 ]; then
  echo "[archive] $SRC_DIR has no top-level artifacts to archive."
  exit 0
fi

TS=$(date +%Y%m%d_%H%M)
DEST_DIR="$SRC_DIR/archive/$TS"
mkdir -p "$DEST_DIR"

echo "[archive] $SRC_DIR -> archive/$TS/"
echo "  per_wsg_times CSVs: $n_csv"
echo "  rollup RDS files:   $n_rds"

[ "$n_csv" -gt 0 ] && mv "${csv_files[@]}" "$DEST_DIR/"
[ "$n_rds" -gt 0 ] && mv "${rds_files[@]}" "$DEST_DIR/"

echo "[archive] done. Top level now empty; next provincial run starts clean."
