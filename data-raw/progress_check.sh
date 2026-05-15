#!/usr/bin/env bash
# progress_check.sh — report live progress of an in-flight provincial dispatch.
#
# Reads each host's newest `_per_wsg_times.csv` (by mtime, NOT by date glob —
# cypher logs use UTC, M4/M1 use local TZ; date-globbing across hosts breaks
# at TZ rollover, see PWF gotcha #9).
#
# Safe to run anytime — reports per-host done counts vs expected bucket sizes,
# plus a sample of the most recent completions to see what each host is on.
#
# Usage:
#   bash data-raw/progress_check.sh [--cy-workspaces=job1,job2,job3] [--mtime-min=120]
#
# Honors /tmp/cy_ips.env if present (set by wsgs_dispatch.sh dispatch).
# Otherwise derives cypher IPs from tofu state per workspace.
#
# --mtime-min=N : only consider CSVs modified in the last N minutes (default 240
#                 = 4 hours; matches a typical dispatch + post-run window).

set -euo pipefail

CY_WORKSPACES="job1,job2,job3"
MTIME_MIN=240
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WORKSPACES="${arg#--cy-workspaces=}" ;;
    --mtime-min=*)     MTIME_MIN="${arg#--mtime-min=}" ;;
    *) echo "FATAL: unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# Resolve cypher IPs from /tmp/cy_ips.env (preferred — set by trifecta wrapper)
# or fall back to tofu state per workspace.
declare -A CY_IPS
if [ -f /tmp/cy_ips.env ]; then
  # shellcheck disable=SC1091
  source /tmp/cy_ips.env
  for WS in $(echo "$CY_WORKSPACES" | tr ',' ' '); do
    VAR="CY_${WS}_IP"
    [ -n "${!VAR:-}" ] && CY_IPS[$WS]="${!VAR}"
  done
else
  for WS in $(echo "$CY_WORKSPACES" | tr ',' ' '); do
    IP=$(cd ~/Projects/repo/rtj/env/do/dev/cypher && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) || continue
    [ -n "$IP" ] && CY_IPS[$WS]="$IP"
  done
fi

# --- Probe one host. Returns "<count>|<last 3 wsgs>" via stdout. ---
probe() {
  local label="$1" ssh_prefix="${2:-}"
  local find_cmd="find ~/Projects/repo/link/data-raw/logs/provincial_parity -maxdepth 1 -name '*_per_wsg_times.csv' -type f -mmin -$MTIME_MIN 2>/dev/null | sort | tail -1"
  local f
  if [ -z "$ssh_prefix" ]; then
    f=$(eval "$find_cmd")
    if [ -z "$f" ] || [ ! -f "$f" ]; then
      printf "%-10s %s\n" "$label" "no recent CSV"
      return
    fi
    local n=$(( $(wc -l < "$f") - 1 ))
    local last=$(tail -3 "$f" 2>/dev/null | awk -F, 'NF>=3 {printf "%s(%ds) ", $1, $3}')
    printf "%-10s %3d  recent: %s\n" "$label" "$n" "$last"
  else
    local out
    out=$($ssh_prefix "f=\$($find_cmd); [ -n \"\$f\" ] && [ -f \"\$f\" ] && { echo \"COUNT:\$(( \$(wc -l < \"\$f\") - 1 ))\"; echo \"LAST:\$(tail -3 \"\$f\" 2>/dev/null | awk -F, 'NF>=3 {printf \"%s(%ds) \", \$1, \$3}')\"; } || echo \"NONE\"" 2>/dev/null)
    if echo "$out" | grep -q NONE; then
      printf "%-10s %s\n" "$label" "no recent CSV"
    else
      local n=$(echo "$out" | grep COUNT | sed 's/COUNT://')
      local last=$(echo "$out" | grep LAST | sed 's/LAST://')
      printf "%-10s %3d  recent: %s\n" "$label" "$n" "$last"
    fi
  fi
}

echo "=== provincial dispatch progress at $(date '+%H:%M:%S %Z') ==="
echo "(only counting CSVs modified in last $MTIME_MIN min)"
echo

probe "M4" ""
probe "M1" "ssh m1"
for WS in "${!CY_IPS[@]}"; do
  probe "cy[$WS]" "ssh cypher@${CY_IPS[$WS]}"
done

echo
# Orchestrator-side state
if pgrep -f "wsgs_dispatch.sh" >/dev/null 2>&1; then
  PID=$(pgrep -f "wsgs_dispatch.sh" | head -1)
  echo "dispatch process: ✓ PID=$PID (running)"
  # Find latest orchestrator log to extract bucket sizes if possible
  LATEST_ORCH=$(find ~/Projects/repo/link/data-raw/logs -maxdepth 1 -name '*_wsgs_dispatch_orchestrator.txt' -mmin -$MTIME_MIN | sort | tail -1)
  if [ -n "$LATEST_ORCH" ]; then
    echo "orchestrator log: $LATEST_ORCH"
    grep -E "total WSGs|projected finish" "$LATEST_ORCH" 2>/dev/null | head -2
  fi
else
  echo "dispatch process: ✗ NOT RUNNING (or already completed)"
fi
