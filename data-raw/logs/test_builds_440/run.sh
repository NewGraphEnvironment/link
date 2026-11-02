#!/usr/bin/env bash
# run.sh — #440: `default` at the minimal run's code on four test groups, into the
# scratch schema zz440_default on m4's local fwapg, built then recomputed, so
# compare.R can set it beside zz432_post (the same groups at fresh 0.52.0, link
# a6942b5d). MURT is the group where only paused species are present.
# Usage: bash data-raw/logs/test_builds_440/run.sh MURT KOTL BULK KETL
set -uo pipefail
[ "$#" -ge 1 ] || { echo "usage: run.sh <WSG> ..." >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
SCHEMA=zz440_default
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] || { echo "[run] tracked changes: not one commit" >&2; exit 1; }
echo "[run] $(date -u +%FT%TZ) link $(git -C "$REPO" rev-parse HEAD), groups: $*"
printf 'step\twsg\tstart_utc\tend_utc\texit\n' > "$HERE/status.tsv"
fail=0
step() { local s e rc; s=$(date -u +%FT%TZ)
  ( cd "$REPO" && env PGOPTIONS='-c statement_timeout=30min' LNK_STATEMENT_TIMEOUT_MIN=30 LNK_LOAD=loadall \
      LNK_GUARD_DOWNSTREAM=warn LNK_RUN_UID="440_$1" LNK_RUN_LABEL="440_$1_$2" LNK_SCHEMA="$SCHEMA" \
      Rscript "data-raw/$3" "$2" default ) > "$HERE/$1_$2.log" 2>&1; rc=$?
  e=$(date -u +%FT%TZ); printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$s" "$e" "$rc" >> "$HERE/status.tsv"
  echo "[run] $e $1 $2 exit=$rc"; return $rc; }
for w in "$@"; do step build "$w" wsg_run_one.R || fail=1; done
for w in "$@"; do step recompute "$w" wsg_recompute_one.R || fail=1; done
[ "$fail" = 0 ] && echo "[run] RUN440_DONE" || echo "[run] RUN440_FAILED"
