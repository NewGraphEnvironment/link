#!/usr/bin/env bash
# Smoke variant of trifecta_provincial.sh — one small WSG per host.
#
# Thin shim that calls the production orchestrator with explicit per-host
# bucket overrides. Goal: exercise EVERY code path the full provincial run
# would hit (preflight, dispatch, tunnel, RDS pull-back, annotation) in
# ~3 minutes wall instead of ~80, so a misconfiguration surfaces before
# you commit to a 200-WSG run.
#
# Usage:
#   ./trifecta_smoke.sh                                     # 3-host: M4 + M1 + 1 cypher
#   ./trifecta_smoke.sh --cy-workspaces=job1,job2,job3      # 5-host: same as full
#   ./trifecta_smoke.sh --with-mapping-code                 # exercise mapping_code branch
#
# Per-host smoke WSGs (smallest, also exercise specific code paths):
#   m4     → DEAD  (exercises barriers_definite_control)
#   m1     → ELKR  (parity baseline)
#   cy1    → ADMS  (mapping_code baseline)
#   cy2    → BABL  (small generic)
#   cy3    → BULL  (small generic)
#
# All other flags pass through to trifecta_provincial.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CY_WORKSPACES="default"
PASS_THROUGH=()
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --m4-bucket=*|--m1-bucket=*|--cy-bucket=*|--cy[1-9]-bucket=*)
      echo "ERROR: trifecta_smoke.sh does not accept manual bucket overrides." >&2
      echo "  Smoke picks one small WSG per host. Use trifecta_provincial.sh directly to override." >&2
      exit 2
      ;;
    *)
      PASS_THROUGH+=("$arg")
      ;;
  esac
done

# How many cypher workspaces?
IFS=',' read -r -a CY_WS_ARR <<< "$CY_WORKSPACES"
N_CY=${#CY_WS_ARR[@]}

# Per-cypher small WSGs (ordered by ascending size in the 2026-05-11 run).
CY_SMOKE_WSGS=(ADMS BABL BULL)
if [ "$N_CY" -gt "${#CY_SMOKE_WSGS[@]}" ]; then
  echo "ERROR: smoke supports up to ${#CY_SMOKE_WSGS[@]} cypher workspaces (got $N_CY)." >&2
  echo "  Extend CY_SMOKE_WSGS in $0 to add more." >&2
  exit 2
fi

CY_BUCKET_ARGS=()
for ((i=0; i<N_CY; i++)); do
  if [ "$N_CY" -eq 1 ]; then
    CY_BUCKET_ARGS+=("--cy-bucket=${CY_SMOKE_WSGS[$i]}")
  else
    CY_BUCKET_ARGS+=("--cy$((i+1))-bucket=${CY_SMOKE_WSGS[$i]}")
  fi
done

echo "[smoke] dispatching ${N_CY}-cypher smoke:"
echo "  m4 → DEAD"
echo "  m1 → ELKR"
for ((i=0; i<N_CY; i++)); do
  echo "  cypher[${CY_WS_ARR[$i]}] → ${CY_SMOKE_WSGS[$i]}"
done

exec bash "$SCRIPT_DIR/trifecta_provincial.sh" \
  --m4-bucket=DEAD \
  --m1-bucket=ELKR \
  --cy-workspaces="$CY_WORKSPACES" \
  "${CY_BUCKET_ARGS[@]}" \
  "${PASS_THROUGH[@]}"
