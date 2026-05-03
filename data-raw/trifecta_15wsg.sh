#!/usr/bin/env bash
# Stage 2 trifecta: 15 WSGs distributed 3-way (M4 + M1 + cypher).
# Each host runs its bucket of 5 WSGs sequentially; hosts run in parallel.
# Wall = max-host-bucket. Bucketing puts one heavy WSG (BULK/BABL/HARR)
# per host plus 4 lighter to balance load.
#
# Per-WSG rollup RDS saved on each host; final summary tibble built
# locally from all 15 RDS files.
#
# Run from anywhere — paths resolve from this script's dir.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/data-raw/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d%H%M)
CFG="bcfishpass"

# Per-host WSG buckets (5 each, 1 heavy + 4 lighter)
M4_WSGS="BULK HORS ADMS KISP MORR"
M1_WSGS="BABL LFRA ELKR NATR PARS"
CY_WSGS="HARR VICT LILL KOTL DEAD"

# R workload — iterates WSG list, saves per-WSG RDS, prints walls
WORKLOAD_R="$LOG_DIR/${TS}_trifecta15_workload.R"
cat > "$WORKLOAD_R" <<'WORKLOAD_EOF'
args <- commandArgs(trailingOnly = TRUE)
cfg_name <- args[1]
wsgs <- args[-1]
host_name <- Sys.info()[["nodename"]]
setwd("~/Projects/repo/link/data-raw")
source("compare_bcfishpass_wsg.R")
cfg <- link::lnk_config(cfg_name)

cat(sprintf("=== %s on %s — %d WSGs (%s bundle) ===\n",
            paste(wsgs, collapse = ","), host_name, length(wsgs), cfg_name))

results <- list()
walls <- numeric(length(wsgs))
for (i in seq_along(wsgs)) {
  w <- wsgs[i]
  t0 <- Sys.time()
  res <- tryCatch(
    compare_bcfishpass_wsg(wsg = w, config = cfg),
    error = function(e) { cat(sprintf("[%s] ERROR: %s\n", w, conditionMessage(e))); NULL })
  walls[i] <- as.numeric(Sys.time() - t0, units = "secs")
  results[[w]] <- res
  status <- if (is.null(res)) "FAIL" else sprintf("%d rows", nrow(res))
  cat(sprintf("[%s] %.1fs  %s\n", w, walls[i], status))
  if (!is.null(res)) {
    saveRDS(res, sprintf("logs/%s_trifecta15_%s_%s_%s.rds",
                         format(Sys.time(), "%Y%m%d%H%M"),
                         host_name, cfg_name, w))
  }
}
cat(sprintf("\nhost total: %.1fs (%d/%d ok)\n",
            sum(walls), sum(!vapply(results, is.null, logical(1))), length(wsgs)))
WORKLOAD_EOF

# cypher tunnel-wrapping shell
CYPHER_SHELL="$LOG_DIR/${TS}_trifecta15_cypher.sh"
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
Rscript ~/cypher-workloads/${TS}_trifecta15_workload.R "$CFG" $CY_WSGS
CYPHER_EOF
chmod +x "$CYPHER_SHELL"

echo "============================================"
echo "[trifecta15] dispatch start: $(date '+%H:%M:%S')"
echo "  m4     → $M4_WSGS"
echo "  m1     → $M1_WSGS"
echo "  cypher → $CY_WSGS"
echo "============================================"

START=$(date +%s)

M4_LOG="$LOG_DIR/${TS}_trifecta15_m4.txt"
( Rscript "$WORKLOAD_R" "$CFG" $M4_WSGS > "$M4_LOG" 2>&1 ) &
M4_PID=$!

M1_LOG="$LOG_DIR/${TS}_trifecta15_m1.txt"
(
  scp -q "$WORKLOAD_R" m1:/tmp/trifecta15_workload.R
  ssh m1 "Rscript /tmp/trifecta15_workload.R '$CFG' $M1_WSGS"
) > "$M1_LOG" 2>&1 &
M1_PID=$!

CY_LOG="$LOG_DIR/${TS}_trifecta15_cypher.txt"
(
  scp -q "$WORKLOAD_R" cypher@100.72.81.25:/home/cypher/cypher-workloads/${TS}_trifecta15_workload.R
  bash "$REPO_ROOT/../rtj/scripts/cypher/cypher_run.sh" "$CYPHER_SHELL"
) > "$CY_LOG" 2>&1 &
CY_PID=$!

M4_EXIT=0; M1_EXIT=0; CY_EXIT=0
wait $M4_PID || M4_EXIT=$?
wait $M1_PID || M1_EXIT=$?
wait $CY_PID || CY_EXIT=$?

END=$(date +%s)
ELAPSED=$((END - START))

echo "============================================"
printf '[trifecta15] elapsed: %dm%02ds\n' $((ELAPSED/60)) $((ELAPSED%60))
printf '  m4     exit=%d  log=%s\n' "$M4_EXIT" "$M4_LOG"
printf '  m1     exit=%d  log=%s\n' "$M1_EXIT" "$M1_LOG"
printf '  cypher exit=%d  log=%s\n' "$CY_EXIT" "$CY_LOG"
echo "============================================"

# Per-host bucket summary
for L in "$M4_LOG" "$M1_LOG" "$CY_LOG"; do
  echo
  echo "--- ${L##*/} (per-WSG walls) ---"
  grep -E "^\[[A-Z]+\] [0-9]+\.[0-9]+s|host total:" "$L" || tail -10 "$L"
done

# Pull cypher's RDS files back so the rollup tibble can be assembled locally
echo
echo "[trifecta15] pulling cypher rollup RDS files"
scp -q cypher@100.72.81.25:/home/cypher/cypher-workloads/logs/*_trifecta15_cypher_${CFG}_*.rds \
    "$REPO_ROOT/data-raw/logs/" 2>&1 | tail -5 || true

# Pull m1's RDS files back too
echo "[trifecta15] pulling m1 rollup RDS files"
scp -q "m1:~/Projects/repo/link/data-raw/logs/*_trifecta15_*_${CFG}_*.rds" \
    "$REPO_ROOT/data-raw/logs/" 2>&1 | tail -5 || true

if [ $M4_EXIT -ne 0 ] || [ $M1_EXIT -ne 0 ] || [ $CY_EXIT -ne 0 ]; then
  exit 1
fi
