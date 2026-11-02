#!/usr/bin/env bash
# One arm of #432's measurement: model then recompute each group into zz432_<arm>.
# Usage: arm.sh <arm> <worktree> <WSG...>
set -u
arm=$1; wt=$2; shift 2
cd "$wt" || exit 1
export LNK_SCHEMA="zz432_$arm" LNK_RUN_UID="432_$arm" LNK_GUARD_DOWNSTREAM=warn LNK_LOAD=loadall
echo "[$arm] start $(date -u +%FT%TZ) at $(git rev-parse --short HEAD)"
for g in "$@"; do
  t0=$(date +%s)
  Rscript data-raw/wsg_run_one.R "$g" default > "../log_${arm}_${g}_model.txt" 2>&1; rc=$?
  echo "[$arm] $g model rc=$rc $(( $(date +%s) - t0 ))s"
done
for g in "$@"; do
  t0=$(date +%s)
  Rscript data-raw/wsg_recompute_one.R "$g" default > "../log_${arm}_${g}_recompute.txt" 2>&1; rc=$?
  echo "[$arm] $g recompute rc=$rc $(( $(date +%s) - t0 ))s"
done
echo "[$arm] end $(date -u +%FT%TZ)"
