#!/usr/bin/env bash
# Stage 1 trifecta smoke — 3-host parallel run, one WSG per host.
# Goal: prove cypher works in the distributed pipeline alongside M4 + M1
# without surprises. Smallest WSGs to keep wall-clock tight (~90-180s).
#
# Hosts:
#   m4 (local) → DEAD     (small, exercises barriers_definite_control)
#   m1 (ssh)   → ELKR     (small, parity baseline)
#   cypher (tunnel) → ADMS  (smallest, fresh host doing parity baseline)
#
# Outputs per host: data-raw/logs/<TS>_trifecta_<host>_<wsg>.{txt,rds}
#
# Run from link/ root or anywhere — paths resolve from this script's dir.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/data-raw/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d%H%M)
CFG="bcfishpass"

# Per-host (WSG, dispatch_method) assignments
declare -A HOST_WSG=(
  [m4]=DEAD
  [m1]=ELKR
  [cypher]=ADMS
)

# R workload identical across hosts — uploaded to each
WORKLOAD_R="$LOG_DIR/${TS}_trifecta_workload.R"
cat > "$WORKLOAD_R" <<'WORKLOAD_EOF'
args <- commandArgs(trailingOnly = TRUE)
wsg <- args[1]; cfg_name <- args[2]
host_name <- Sys.info()[["nodename"]]
setwd("~/Projects/repo/link/data-raw")
source("compare_bcfishpass_wsg.R")
cat(sprintf("=== %s on %s (%s bundle) ===\n", wsg, host_name, cfg_name))
cfg <- link::lnk_config(cfg_name)
t0 <- Sys.time()
res <- compare_bcfishpass_wsg(wsg = wsg, config = cfg)
dt <- as.numeric(Sys.time() - t0, units = "secs")
cat(sprintf("\n%s wall: %.1fs\n", wsg, dt))
print(res, n = Inf)
out_rds <- sprintf("logs/%s_trifecta_%s_%s_%s.rds",
                   format(Sys.time(), "%Y%m%d%H%M"),
                   host_name, cfg_name, wsg)
saveRDS(res, out_rds)
cat(sprintf("\nsaved: %s\n", out_rds))
WORKLOAD_EOF

# Cypher needs tunnel-wrapping shell — write it once
CYPHER_SHELL="$LOG_DIR/${TS}_trifecta_cypher.sh"
cat > "$CYPHER_SHELL" <<CYPHER_EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -L 63333:127.0.0.1:5432 db_newgraph -N &
TUNNEL_PID=\$!
trap 'kill \$TUNNEL_PID 2>/dev/null || true' EXIT
for _ in \$(seq 1 10); do
  nc -z localhost 63333 2>/dev/null && break
  sleep 0.5
done
Rscript ~/cypher-workloads/${TS}_trifecta_workload.R "${HOST_WSG[cypher]}" "$CFG"
CYPHER_EOF
chmod +x "$CYPHER_SHELL"

echo "============================================"
echo "[trifecta] dispatch start: $(date '+%H:%M:%S')"
echo "  m4     → ${HOST_WSG[m4]}"
echo "  m1     → ${HOST_WSG[m1]}"
echo "  cypher → ${HOST_WSG[cypher]}"
echo "============================================"

START=$(date +%s)

# --- Dispatch all 3 in parallel ---

# m4 (local)
M4_LOG="$LOG_DIR/${TS}_trifecta_m4_${HOST_WSG[m4]}.txt"
( Rscript "$WORKLOAD_R" "${HOST_WSG[m4]}" "$CFG" > "$M4_LOG" 2>&1 ) &
M4_PID=$!

# m1 (ssh, push workload script via stdin redirect)
M1_LOG="$LOG_DIR/${TS}_trifecta_m1_${HOST_WSG[m1]}.txt"
(
  scp -q "$WORKLOAD_R" m1:/tmp/trifecta_workload.R
  ssh m1 "Rscript /tmp/trifecta_workload.R '${HOST_WSG[m1]}' '$CFG'"
) > "$M1_LOG" 2>&1 &
M1_PID=$!

# cypher (scp workload + run wrapper via cypher_run.sh)
CYPHER_LOG="$LOG_DIR/${TS}_trifecta_cypher_${HOST_WSG[cypher]}.txt"
(
  scp -q "$WORKLOAD_R" cypher@100.72.81.25:/home/cypher/cypher-workloads/${TS}_trifecta_workload.R
  bash "$REPO_ROOT/../rtj/scripts/cypher/cypher_run.sh" "$CYPHER_SHELL"
) > "$CYPHER_LOG" 2>&1 &
CY_PID=$!

# Wait + collect exit codes
M4_EXIT=0; M1_EXIT=0; CY_EXIT=0
wait $M4_PID || M4_EXIT=$?
wait $M1_PID || M1_EXIT=$?
wait $CY_PID || CY_EXIT=$?

END=$(date +%s)
ELAPSED=$((END - START))

echo "============================================"
printf '[trifecta] elapsed: %dm%02ds\n' $((ELAPSED/60)) $((ELAPSED%60))
printf '  m4     %s exit=%d  log=%s\n' "${HOST_WSG[m4]}"     "$M4_EXIT" "$M4_LOG"
printf '  m1     %s exit=%d  log=%s\n' "${HOST_WSG[m1]}"     "$M1_EXIT" "$M1_LOG"
printf '  cypher %s exit=%d  log=%s\n' "${HOST_WSG[cypher]}" "$CY_EXIT" "$CYPHER_LOG"
echo "============================================"

# Pull rollup tail from each log
for L in "$M4_LOG" "$M1_LOG" "$CYPHER_LOG"; do
  echo
  echo "--- ${L##*/} (last 12 lines) ---"
  tail -12 "$L"
done

if [ $M4_EXIT -ne 0 ] || [ $M1_EXIT -ne 0 ] || [ $CY_EXIT -ne 0 ]; then
  exit 1
fi
