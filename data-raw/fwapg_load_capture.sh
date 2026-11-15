#!/usr/bin/env bash
# fwapg_load_capture.sh — run fwapg's load.sh and record what it fetched (link#270).
#
#   DATABASE_URL=postgresql://... bash data-raw/fwapg_load_capture.sh <fwapg checkout>
#   DATABASE_URL=... bash data-raw/fwapg_load_capture.sh --trace=<captured log> <fwapg checkout>
#
# fwapg's load.sh runs under `set -euxo pipefail`, so its stderr is a trace of
# every command with its variables expanded: every object-store URL it fetched,
# each watershed group's partition included. A version id nobody recorded at
# load time cannot be named later (the bucket refuses ?versions), so this tees
# that trace to a dated log under data-raw/logs/fwapg_load/, then records each
# FWA primitive object it names as a `loader` row in
# provenance.source_artifact (data-raw/artifact_record.R --fwa-trace), which
# replaces the probe row snapshot_bcfp.sh writes. No change to fwapg.
#
# The checkout's commit goes in each row's notes (fwapg_commit=<sha>, with
# -dirty when its tree is not clean): log.fwapg_sha is the checkout's HEAD when
# a model runs, not the loader's commit.
#
# --trace= records from a trace captured earlier (its start and end are the
# file's first and last modification times as given by --start= and --end=,
# else the file's mtime for both) without running a load.
#
# Exits non-zero when load.sh fails (nothing is recorded: a partial load is not
# what a row would name) or when recording fails.
set -euo pipefail
cd "$(dirname "$0")/.."

TRACE=""
START=""
END=""
FW=""
for arg in "$@"; do
  case "$arg" in
    --trace=*) TRACE="${arg#--trace=}" ;;
    --start=*) START="${arg#--start=}" ;;
    --end=*) END="${arg#--end=}" ;;
    -*) echo "Unknown arg: $arg" >&2; exit 2 ;;
    *) FW="$arg" ;;
  esac
done
[ -n "$FW" ] || { echo "usage: fwapg_load_capture.sh [--trace=<log> [--start=Z --end=Z]] <fwapg checkout>" >&2; exit 2; }
[ -f "$FW/load.sh" ] || { echo "FATAL: no load.sh in $FW" >&2; exit 2; }
: "${DATABASE_URL:?DATABASE_URL must name the database load.sh writes}"

commit=$(git -C "$FW" rev-parse HEAD 2>/dev/null) || commit=""
if [ -n "$commit" ]; then
  dirty=$(git -C "$FW" status --porcelain 2>/dev/null) || dirty="unknown"
  [ -z "$dirty" ] || commit="${commit}-dirty"
fi

if [ -z "$TRACE" ]; then
  mkdir -p data-raw/logs/fwapg_load
  TRACE="$PWD/data-raw/logs/fwapg_load/$(date -u +%Y%m%dT%H%M%SZ)_load_trace.log"
  START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "fwapg_load_capture: running $FW/load.sh (fwapg ${commit:-unknown}); trace -> $TRACE"
  rc=0
  # A pipeline, not a process substitution: the shell waits for tee, so the trace is
  # whole before it is read. stdout goes to fd 3 (the terminal), stderr into tee.
  { (cd "$FW" && DATABASE_URL="$DATABASE_URL" ./load.sh) 2>&1 1>&3 | tee "$TRACE" >&2; } 3>&1 || rc=$?
  END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  [ "$rc" = 0 ] || { echo "FATAL: load.sh exited $rc; nothing recorded (trace kept: $TRACE)" >&2; exit "$rc"; }
else
  [ -f "$TRACE" ] || { echo "FATAL: no trace at $TRACE" >&2; exit 2; }
  m=$(date -u -r "$TRACE" +%Y-%m-%dT%H:%M:%SZ)
  START="${START:-$m}"
  END="${END:-$m}"
fi

DATABASE_URL="$DATABASE_URL" Rscript data-raw/artifact_record.R --fwa-trace "$TRACE" "$START" "$END" "$commit"
echo "fwapg_load_capture: recorded from $TRACE"
