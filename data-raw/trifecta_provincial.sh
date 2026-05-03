#!/usr/bin/env bash
# Stage 3 trifecta: provincial run distributed 3-way.
# Each host runs `run_provincial_parity.R --wsgs=<bucket> --config=<bundle> --schema=<schema>`
# (resume-safe; skips WSGs whose RDS already exists). Buckets are sequential
# M4-M1-cy slices so resumes from interruption are clean.
#
# Usage:
#   ./trifecta_provincial.sh                                    # bcfishpass bundle → fresh schema
#   ./trifecta_provincial.sh --config=default --schema=fresh_default  # default bundle → fresh_default
#
# Estimated wall: ~2-3 hours. Tee the orchestrator output to
# data-raw/logs/<TS>_trifecta_provincial_orchestrator.txt as it runs.

set -euo pipefail

# Parse args
CONFIG="bcfishpass"
SCHEMA=""
for arg in "$@"; do
  case "$arg" in
    --config=*) CONFIG="${arg#--config=}" ;;
    --schema=*) SCHEMA="${arg#--schema=}" ;;
  esac
done
EXTRA_ARGS="--config=$CONFIG"
[ -n "$SCHEMA" ] && EXTRA_ARGS="$EXTRA_ARGS --schema=$SCHEMA"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/data-raw/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d%H%M)
ORCH_LOG="$LOG_DIR/${TS}_trifecta_provincial_orchestrator.txt"

# Compute the WSG list + 3-way split deterministically here so the
# orchestrator log records the assignment up front.
SPLIT_R="$LOG_DIR/${TS}_trifecta_provincial_split.R"
cat > "$SPLIT_R" <<'SPLIT_EOF'
suppressPackageStartupMessages({})
loaded <- link::lnk_load_overrides(link::lnk_config("bcfishpass"))
wsg_pres <- loaded$wsg_species_presence
spp_cols <- c("ch","cm","co","pk","sk","st","bt","wct","ct","dv","rb")
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1,
                 function(r) any(r %in% c("t","TRUE",TRUE)))
all_wsgs <- sort(wsg_pres$watershed_group_code[has_spp])
n <- length(all_wsgs)
m4_n <- ceiling(n/3)
m1_n <- ceiling((n - m4_n)/2)
m4 <- all_wsgs[1:m4_n]
m1 <- all_wsgs[(m4_n + 1):(m4_n + m1_n)]
cy <- all_wsgs[(m4_n + m1_n + 1):n]
cat("M4=", paste(m4, collapse=","), "\n", sep="")
cat("M1=", paste(m1, collapse=","), "\n", sep="")
cat("CY=", paste(cy, collapse=","), "\n", sep="")
SPLIT_EOF

SPLIT_OUT=$(Rscript "$SPLIT_R" 2>&1 | grep -E "^(M4|M1|CY)=")
M4_WSGS=$(echo "$SPLIT_OUT" | awk -F'=' '$1=="M4" {print $2}')
M1_WSGS=$(echo "$SPLIT_OUT" | awk -F'=' '$1=="M1" {print $2}')
CY_WSGS=$(echo "$SPLIT_OUT" | awk -F'=' '$1=="CY" {print $2}')

M4_COUNT=$(echo "$M4_WSGS" | tr ',' '\n' | wc -l)
M1_COUNT=$(echo "$M1_WSGS" | tr ',' '\n' | wc -l)
CY_COUNT=$(echo "$CY_WSGS" | tr ',' '\n' | wc -l)
TOTAL=$((M4_COUNT + M1_COUNT + CY_COUNT))

# Tee everything from here on
exec > >(tee -a "$ORCH_LOG") 2>&1

echo "============================================"
echo "[trifecta-provincial] dispatch start: $(date '+%H:%M:%S')"
echo "  total WSGs: $TOTAL  (m4=$M4_COUNT  m1=$M1_COUNT  cypher=$CY_COUNT)"
echo "  m4     bucket: $M4_WSGS"
echo "  m1     bucket: $M1_WSGS"
echo "  cypher bucket: $CY_WSGS"
echo "============================================"

# cypher tunnel-wrapping shell (long-running — keep tunnel alive throughout)
CYPHER_SHELL="$LOG_DIR/${TS}_trifecta_provincial_cypher.sh"
cat > "$CYPHER_SHELL" <<CYPHER_EOF
#!/usr/bin/env bash
set -euo pipefail
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -L 63333:127.0.0.1:5432 db_newgraph -N &
TUNNEL_PID=\$!
trap 'kill \$TUNNEL_PID 2>/dev/null || true' EXIT
for _ in \$(seq 1 10); do
  nc -z localhost 63333 2>/dev/null && break
  sleep 0.5
done
cd ~/Projects/repo/link/data-raw
Rscript run_provincial_parity.R "--wsgs=$CY_WSGS" $EXTRA_ARGS
CYPHER_EOF
chmod +x "$CYPHER_SHELL"

START=$(date +%s)

# m4 (local) — run from data-raw/ so out_dir resolves correctly
M4_LOG="$LOG_DIR/${TS}_trifecta_provincial_m4.txt"
( cd "$REPO_ROOT/data-raw" && Rscript run_provincial_parity.R "--wsgs=$M4_WSGS" $EXTRA_ARGS > "$M4_LOG" 2>&1 ) &
M4_PID=$!

# m1 (ssh) — same recipe, remote-side
M1_LOG="$LOG_DIR/${TS}_trifecta_provincial_m1.txt"
( ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10 m1 \
    "cd ~/Projects/repo/link/data-raw && Rscript run_provincial_parity.R '--wsgs=$M1_WSGS' $EXTRA_ARGS" \
    > "$M1_LOG" 2>&1 ) &
M1_PID=$!

# cypher
CY_LOG="$LOG_DIR/${TS}_trifecta_provincial_cypher.txt"
( bash "$REPO_ROOT/../rtj/scripts/cypher/cypher_run.sh" "$CYPHER_SHELL" > "$CY_LOG" 2>&1 ) &
CY_PID=$!

echo "[dispatch] m4 PID=$M4_PID  m1 PID=$M1_PID  cypher PID=$CY_PID"
echo "[dispatch] tail logs:"
echo "  $M4_LOG"
echo "  $M1_LOG"
echo "  $CY_LOG"

M4_EXIT=0; M1_EXIT=0; CY_EXIT=0
wait $M4_PID || M4_EXIT=$?
wait $M1_PID || M1_EXIT=$?
wait $CY_PID || CY_EXIT=$?

END=$(date +%s)
ELAPSED=$((END - START))

echo "============================================"
printf '[trifecta-provincial] elapsed: %dh%02dm%02ds\n' \
       $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))
printf '  m4     exit=%d  log=%s\n' "$M4_EXIT" "$M4_LOG"
printf '  m1     exit=%d  log=%s\n' "$M1_EXIT" "$M1_LOG"
printf '  cypher exit=%d  log=%s\n' "$CY_EXIT" "$CY_LOG"
echo "============================================"

# Pull cypher's RDS files back to M4
echo
echo "[trifecta-provincial] pulling cypher RDS files"
mkdir -p "$REPO_ROOT/data-raw/logs/provincial_parity"
scp -q "cypher@100.72.81.25:/home/cypher/Projects/repo/link/data-raw/logs/provincial_parity/*.rds" \
    "$REPO_ROOT/data-raw/logs/provincial_parity/" 2>&1 | tail -3 || true

# Pull m1's RDS files back too
echo "[trifecta-provincial] pulling m1 RDS files"
scp -q "m1:~/Projects/repo/link/data-raw/logs/provincial_parity/*.rds" \
    "$REPO_ROOT/data-raw/logs/provincial_parity/" 2>&1 | tail -3 || true

# Final inventory
echo
TOTAL_RDS=$(ls "$REPO_ROOT/data-raw/logs/provincial_parity/"*.rds 2>/dev/null | wc -l)
echo "[trifecta-provincial] local RDS file count: $TOTAL_RDS / $TOTAL"

if [ $M4_EXIT -ne 0 ] || [ $M1_EXIT -ne 0 ] || [ $CY_EXIT -ne 0 ]; then
  exit 1
fi
