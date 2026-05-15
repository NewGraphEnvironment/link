#!/usr/bin/env bash
# data-raw/wsgs_run_m4_offline.sh
#
# Run the link pipeline for a list of WSGs entirely on M4 — no cypher
# spin, no M1 ssh, no DO cost, no internet beyond what the pipeline
# itself uses for bcdata/bcfishpass reference queries.
#
# Use when you want to:
#   - recover a small set of WSGs locally without a full multi-host run
#   - smoke-test pipeline changes on a few WSGs before a full provincial run
#   - run additively against an existing schema (default) — pipeline's
#     per-WSG DELETE-WHERE-WSG idempotency handles replacement cleanly
#
# Compared to wsgs_run_pipeline.sh:
#   - skips Step 3+4 (cypher spin / prep)
#   - skips Step 5 cypher-side archive
#   - skips Step 7 multi-host LPT dispatch — runs wsgs_run_host.R directly
#   - skips Step 9 consolidate (no remote sources to pull from)
#   - skips Step 10 burn (no cyphers)
#
# Usage:
#   bash data-raw/wsgs_run_m4_offline.sh \
#     --wsgs=CARP,FINA,FOXR,MESI,OSPK,TOOD,UOMI \
#     --config=default \
#     --schema=fresh_default \
#     [--force] \
#     [--no-snapshot] \
#     [--with-mapping-code]
#
# Flags:
#   --wsgs=A,B,C        comma-separated WSG codes (REQUIRED)
#   --config=NAME       bundle config (default: bcfishpass)
#   --schema=NAME       destination schema (default: fresh)
#   --force             bypass the per-WSG PG-state + RDS resume gates
#   --no-snapshot       skip the snapshot_bcfp.sh --force step
#   --with-mapping-code build the mapping-code lens (slower; needed for
#                       lnk_compare_mapping_code follow-up work)

set -euo pipefail

# --- arg parse ---
WSGS=""
CONFIG="bcfishpass"
SCHEMA=""
FORCE_FLAG=""
SKIP_SNAPSHOT=0
MAPPING_CODE_FLAG=""

for arg in "$@"; do
  case "$arg" in
    --wsgs=*)            WSGS="${arg#*=}" ;;
    --config=*)          CONFIG="${arg#*=}" ;;
    --schema=*)          SCHEMA="${arg#*=}" ;;
    --force)             FORCE_FLAG="--force" ;;
    --no-snapshot)       SKIP_SNAPSHOT=1 ;;
    --with-mapping-code) MAPPING_CODE_FLAG="--with-mapping-code" ;;
    -h|--help)
      sed -n 's/^# \{0,1\}//p' "$0" | head -45
      exit 0 ;;
    *)
      echo "FATAL: unknown arg '$arg'" >&2
      exit 1 ;;
  esac
done

if [ -z "$WSGS" ]; then
  echo "FATAL: --wsgs=A,B,C is required" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$REPO_ROOT/data-raw/logs/wsgs_run_m4_offline"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${TS}_run.log"

exec > >(tee -a "$LOG") 2>&1

echo "=== wsgs_run_m4_offline.sh started at $(date '+%F %T %Z') ==="
echo "  wsgs:         $WSGS"
echo "  config:       $CONFIG"
echo "  schema:       ${SCHEMA:-<bundle default>}"
echo "  force:        $([ -n "$FORCE_FLAG" ] && echo YES || echo no)"
echo "  mapping-code: $([ -n "$MAPPING_CODE_FLAG" ] && echo YES || echo no)"
echo "  log:          $LOG"
echo

# --- Step 1: snapshot (skippable) ---
if [ "$SKIP_SNAPSHOT" -eq 0 ]; then
  echo "=== Step 1: snapshot_bcfp.sh --force ==="
  bash data-raw/snapshot_bcfp.sh --force > "$LOG_DIR/${TS}_snapshot.log" 2>&1 || {
    echo "FATAL: snapshot failed; see $LOG_DIR/${TS}_snapshot.log" >&2
    tail -20 "$LOG_DIR/${TS}_snapshot.log" >&2
    exit 1
  }
  echo "  ✓ snapshot done"
else
  echo "=== Step 1: SKIPPED (--no-snapshot) ==="
fi

# --- Step 2: run wsgs_run_host.R directly on M4 ---
echo
echo "=== Step 2: wsgs_run_host.R ==="
HOST_ARGS=(--wsgs="$WSGS" --config="$CONFIG")
[ -n "$SCHEMA" ]            && HOST_ARGS+=(--schema="$SCHEMA")
[ -n "$FORCE_FLAG" ]        && HOST_ARGS+=("$FORCE_FLAG")
[ -n "$MAPPING_CODE_FLAG" ] && HOST_ARGS+=("$MAPPING_CODE_FLAG")

cd "$REPO_ROOT/data-raw"
Rscript wsgs_run_host.R "${HOST_ARGS[@]}"
RC=$?
cd "$REPO_ROOT"

if [ "$RC" -ne 0 ]; then
  echo "FATAL: wsgs_run_host.R exited $RC" >&2
  exit "$RC"
fi

echo
echo "=== wsgs_run_m4_offline.sh complete at $(date '+%F %T %Z') ==="
echo "  log: $LOG"
