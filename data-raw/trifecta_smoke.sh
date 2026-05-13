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

# Inject --fail-fast unless the caller already passed it. Smoke's goal is
# "did host X's WSG #1 work?" — running 30 more after #1 failed wastes
# compute on a confirmed-bad host.
if ! printf '%s\n' "${PASS_THROUGH[@]}" | grep -qx -- '--fail-fast'; then
  PASS_THROUGH+=("--fail-fast")
fi

# Smoke RDS dir — same as the orchestrator picks for bcfishpass.
SMOKE_DIR="$SCRIPT_DIR/logs/provincial_parity"
mkdir -p "$SMOKE_DIR"   # find aborts under set -euo pipefail if dir doesn't exist

# Snapshot pre-existing RDS so the post-check only inspects WSGs the
# smoke wrote (resume-safe orchestrators skip cached RDS; we don't
# want to flag a leftover ADMS.rds from yesterday as a smoke failure).
PRE_RDS_LIST=$(mktemp)
find "$SMOKE_DIR" -maxdepth 1 -name '*.rds' 2>/dev/null | sort > "$PRE_RDS_LIST" || true

# Run the orchestrator. Don't exec — we want control flow back so we
# can run the smoke-pass assertion afterward.
ORCH_RC=0
bash "$SCRIPT_DIR/trifecta_provincial.sh" \
  --m4-bucket=DEAD \
  --m1-bucket=ELKR \
  --cy-workspaces="$CY_WORKSPACES" \
  "${CY_BUCKET_ARGS[@]}" \
  "${PASS_THROUGH[@]}" || ORCH_RC=$?

# Smoke-pass assertion: every NEW RDS file the smoke produced must be
# a successful tibble (or list(rollup, mapping_code)), NOT an error
# stub. ANY error stub means the test caught a real failure mode that
# would otherwise have wasted a 90-minute provincial run.
POST_RDS_LIST=$(mktemp)
find "$SMOKE_DIR" -maxdepth 1 -name '*.rds' 2>/dev/null | sort > "$POST_RDS_LIST" || true
NEW_RDS=$(comm -23 "$POST_RDS_LIST" "$PRE_RDS_LIST")
rm -f "$PRE_RDS_LIST" "$POST_RDS_LIST"

if [ -z "$NEW_RDS" ]; then
  echo "[smoke] ERROR: no new RDS files produced. Orchestrator rc=$ORCH_RC" >&2
  exit 4
fi

# Use a sentinel marker prefix to extract the result line — robust to
# any R startup messages, warnings, or notices that might appear in
# stdout before our `cat()`.
ERR_LINE=$(Rscript -e '
suppressWarnings(suppressMessages({
  files <- commandArgs(trailingOnly = TRUE)
  n_err <- 0; err_wsgs <- character(0)
  for (f in files) {
    x <- tryCatch(readRDS(f), error = function(e) NULL); if (is.null(x)) next
    if (is.list(x) && !is.data.frame(x) && "error" %in% names(x)) {
      n_err <- n_err + 1
      err_wsgs <- c(err_wsgs, sub("[.]rds$", "", basename(f)))
    }
  }
  if (n_err > 0L) cat("SMOKE_ERR:", n_err, paste(err_wsgs, collapse=","))
}))
' $NEW_RDS 2>&1 | grep '^SMOKE_ERR:' || true)

if [ -n "$ERR_LINE" ]; then
  N=$(echo "$ERR_LINE" | awk '{print $2}')
  WSGS=$(echo "$ERR_LINE" | awk '{print $3}')
  echo "" >&2
  echo "[smoke] FAILED: $N WSG(s) errored: $WSGS" >&2
  echo "[smoke] inspect logs:" >&2
  echo "  data-raw/logs/<TS>_trifecta_provincial_*.txt (orchestrator-side)" >&2
  echo "  rtj/scripts/cypher/logs/<TS>_cypher-run_*.txt (cypher-side R output)" >&2
  echo "[smoke] DO NOT dispatch trifecta_provincial.sh until these are fixed." >&2
  exit 5
fi

echo "[smoke] PASS: all $(echo "$NEW_RDS" | wc -l | tr -d ' ') new RDS are successful tibbles. Safe to dispatch trifecta_provincial.sh."
exit $ORCH_RC
