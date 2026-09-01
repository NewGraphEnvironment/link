#!/usr/bin/env bash
# study_area_run.sh — tunnel-free, M1-dispatch study-area mapping_code parity.
#
# Productionizes the proven smoke flow (cypher_up -> cypher_prep ->
# lnk_pipeline_run(mapping_code=TRUE) per WSG -> schema_consolidate ->
# wsg_compare_mapping_code -> cypher_down). NOT a refactor of the old
# M4-centric wsgs_run_pipeline.sh — it reuses the simple local flow the
# 3-WSG smoke validated (link#175).
#
# Host model: the local machine is the dispatcher (M1) and the consolidate
# destination; cyphers are the remote workers. No M4, no `ssh m1`, no bcfp
# tunnel (`:63333`/PG_PASS_SHARE) — the compare reference is the LOCAL bcfp
# snapshot fresh.streams_vw_bcfp (snapshot_bcfp.sh --with-bcfp-views).
#
# Cross-WSG `;DAM` correctness WITHOUT a post-consolidate recompute: each
# host gets a DRAINAGE-CLOSED bucket (focal WSGs + every WSG they drain
# through, via study_area_wsgs.R / lnk_wsg_resolve) run DOWNSTREAM-FIRST,
# so a WSG's downstream dam barriers are persisted before its access /
# mapping_code is computed. One study area (closed) per host.
#
# Usage:
#   bash data-raw/study_area_run.sh \
#     --cy-workspaces=job1,job2 \
#     --focal=<dispatcher focal csv> \
#     --focal=<cy1 focal csv> \
#     --focal=<cy2 focal csv> \
#     [--config=bcfishpass] [--schema=<persist-schema>] [--keep-cyphers]
#
#   bash data-raw/study_area_run.sh --preflight-only    # gates only, no spend
#
# The number of --focal flags MUST equal 1 (dispatcher) + N cyphers, in
# order: first --focal -> dispatcher, the rest -> cyphers in --cy-workspaces
# order. Put the LARGEST area on the dispatcher (first --focal): it is the
# fast, free local host, while cyphers are slower + paid — give them the
# smaller areas so they finish + burn sooner. Cyphers burn right after
# consolidate (minimise idle); a trap EXIT is the safety net.
#
# Pre-flight gates (link#246) — two blocks, because they answer two
# different questions:
#
#   preflight_local()  before the spin. Everything knowable without a
#                      droplet: fwapg up, bcfp view present, dispatcher's
#                      fresh complete, branch pushed + tree clean, fwapg
#                      SHA resolvable, primitive vintage, and BOTH DO
#                      credentials forced through a real API call.
#   preflight_hosts()  after prep, before any WSG writes: cross-host
#                      version parity and cypher primitive vintage. Cannot
#                      run earlier — the hosts do not exist yet. A failure
#                      burns via the EXIT trap.
#
# Post-conditions: every host must account for its whole bucket before
# consolidate, and every run WSG must have rows in the persist afterwards.
#
# Extra flags:
#   --preflight-only        run the local gates and exit (no spend)
#   --refresh-primitives    snapshot_bcfp.sh --force first (default off)
#   --auto-install          on a parity mismatch, re-run the cyphers'
#                           install stage and re-check once
#   --vintage-max-days=N    primitive staleness window (default 7)
#   --recompute-jobs=N      width of the post-consolidate recompute pool
#                           (default 4, max 16). The recompute was >50% of
#                           run wall clock single-threaded (link#250). N=1
#                           reproduces the serial path and is the control arm
#                           of data-raw/recompute_parity.sh.
#   --prep-ssh-wait=N       seconds to wait for a fresh droplet to accept a
#                           connection as the `cypher` user (default 600).
#                           cypher_up returns early on snapshot spins
#                           (NewGraphEnvironment/rtj#248), so this wait — not
#                           cypher_up's — is what covers cloud-init's runcmd.
#   --run-label="text"      operator name for this campaign, written to
#                           <persist>.log.run_label and
#                           <persist>.log_recompute.run_label on every row of
#                           every host. Free text; never assumed unique.
#   --preflight-note="why"  downgrade ONLY vintage + parity to warnings,
#                           and only with a written reason. There is no
#                           global bypass on purpose.
#
# Run identity (link#262). Three levels, and only the middle one is new:
#
#   run_id     minted per lnk_pipeline_run() call, i.e. ONE PER WSG, and the
#              log's PK. A 217-WSG dispatch mints 217 of them, so it cannot
#              answer "everything from that run".
#   run_uid    minted ONCE below and exported to every host. Makes a dispatch
#              a single queryable unit — `WHERE run_uid = '...'` instead of a
#              time window plus a host list, which is fragile at 34 WSGs on
#              three hosts and ambiguous the moment two runs overlap.
#   run_label  --run-label=, for humans.
#
# Both are exported on BOTH legs — the local Rscript loop and the ssh command
# string. Exporting only the local leg is the LNK_GUARD_DOWNSTREAM trap
# (link#227): the cyphers silently write NULL and the run is half-labelled,
# with nothing to say so.

set -euo pipefail

# --- args ---
CY_WS=""
CONFIG="bcfishpass"
SCHEMA_OVERRIDE=""
KEEP_CYPHERS=0
PREFLIGHT_ONLY=0
REFRESH_PRIMITIVES=0
AUTO_INSTALL=0
VINTAGE_MAX_DAYS=7
PREFLIGHT_NOTE=""
RUN_LABEL=""
# How long to wait for a fresh droplet to accept a connection as the `cypher`
# user. 600s, not the old effective ~150s: cypher_up returns early on snapshot
# spins (rtj#248), so this wait is what actually covers cloud-init's runcmd —
# Docker, apt, micromamba and Tailscale all run before the SSH keys are copied
# to the cypher user. cypher_up's own comment puts a snapshot spin at 3-5 min.
PREP_SSH_WAIT_S=600
# Width of the post-consolidate recompute pool (link#250). Conservative by
# default: each job is an R process holding one Postgres connection and
# building zz_lnk_streams_<wsg> as a real table with 2 GiST + 2 btree indexes,
# so the scarce resource is maintenance_work_mem per concurrent index build,
# not connections (4 against a default max_connections of 100 is nothing).
# 10-core dispatcher. Raise only on a measurement.
RECOMPUTE_JOBS=4
# Set when the recompute did not complete for every WSG. Initialised here, not
# at the recompute, so `set -u` cannot bite on any earlier exit path.
RECOMPUTE_FAIL=0
RECOMPUTE_FAIL_STAGE=""
FOCAL_ARR=()
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WS="${arg#--cy-workspaces=}" ;;
    --config=*)        CONFIG="${arg#--config=}" ;;
    --schema=*)        SCHEMA_OVERRIDE="${arg#--schema=}"
                       [ -n "$SCHEMA_OVERRIDE" ] || { echo "FATAL: --schema= requires a non-empty value" >&2; exit 1; } ;;
    --focal=*)         FOCAL_ARR+=("${arg#--focal=}") ;;
    --keep-cyphers)    KEEP_CYPHERS=1 ;;
    --preflight-only)  PREFLIGHT_ONLY=1 ;;
    --refresh-primitives) REFRESH_PRIMITIVES=1 ;;
    --auto-install)    AUTO_INSTALL=1 ;;
    --prep-ssh-wait=*) PREP_SSH_WAIT_S="${arg#--prep-ssh-wait=}"
                       case "$PREP_SSH_WAIT_S" in
                         ''|*[!0-9]*) echo "FATAL: --prep-ssh-wait= needs a positive integer (got '$PREP_SSH_WAIT_S')" >&2; exit 1 ;;
                       esac
                       [ "$PREP_SSH_WAIT_S" -gt 0 ] || { echo "FATAL: --prep-ssh-wait must be > 0" >&2; exit 1; } ;;
    --recompute-jobs=*)
                       RECOMPUTE_JOBS="${arg#--recompute-jobs=}"
                       case "$RECOMPUTE_JOBS" in
                         ''|*[!0-9]*) echo "FATAL: --recompute-jobs= needs a positive integer (got '$RECOMPUTE_JOBS')" >&2; exit 1 ;;
                       esac
                       # Base-10 normalise before the bounds: $(( )) reads a
                       # leading zero as octal, so --recompute-jobs=010 would
                       # pass a <=16 check on the value 10 and then build an
                       # 8-slot pool.
                       RECOMPUTE_JOBS=$((10#$RECOMPUTE_JOBS))
                       [ "$RECOMPUTE_JOBS" -gt 0 ] || { echo "FATAL: --recompute-jobs must be > 0" >&2; exit 1; }
                       # Upper bound: past this the Postgres side is the
                       # constraint, not the cores. Each job builds two GiST
                       # indexes, each taking its own maintenance_work_mem.
                       [ "$RECOMPUTE_JOBS" -le 16 ] || { echo "FATAL: --recompute-jobs must be <= 16" >&2; exit 1; } ;;
    --vintage-max-days=*)
                       VINTAGE_MAX_DAYS="${arg#--vintage-max-days=}"
                       case "$VINTAGE_MAX_DAYS" in
                         ''|*[!0-9]*) echo "FATAL: --vintage-max-days= needs a positive integer (got '$VINTAGE_MAX_DAYS')" >&2; exit 1 ;;
                       esac
                       [ "$VINTAGE_MAX_DAYS" -gt 0 ] || { echo "FATAL: --vintage-max-days must be > 0" >&2; exit 1; } ;;
    # Downgrades ONLY the vintage and parity gates to warnings, and only
    # with a written reason. Mirrors lnk_wsg_downstream_check(override=):
    # the justification IS the mechanism, so a bare boolean is rejected.
    # There is deliberately no global --skip-preflight — an unconditional
    # bypass is the affordance that let #246 happen in the first place.
    --preflight-note=*)
                       PREFLIGHT_NOTE="${arg#--preflight-note=}"
                       [ -n "$PREFLIGHT_NOTE" ] || { echo "FATAL: --preflight-note= requires a written justification, not an empty value" >&2; exit 1; } ;;
    # Refuse an empty value rather than accepting it. `--run-label=` with
    # nothing after it would export LNK_RUN_LABEL="" — SET BUT EMPTY, which
    # Sys.getenv(x, NA) returns as "" rather than NA. R normalises it back to
    # NULL (.lnk_blank_to_na), but an operator who typed the flag meant to
    # label the run, so silently recording nothing is the wrong answer.
    --run-label=*)     RUN_LABEL="${arg#--run-label=}"
                       [ -n "$RUN_LABEL" ] || { echo "FATAL: --run-label= requires a non-empty value" >&2; exit 1; }
                       # The label is interpolated into the cypher ssh command
                       # string inside single quotes, so a value containing one
                       # would terminate the quote and re-parse the remainder on
                       # the remote shell. Restrict the charset rather than rely
                       # on quoting surviving a local-shell -> ssh-argv ->
                       # remote-shell round trip: a label is an identifier, and
                       # refusing a bad one costs a retype where getting it
                       # wrong corrupts the whole remote invocation.
                       case "$RUN_LABEL" in
                         *[!A-Za-z0-9._-]*)
                           echo "FATAL: --run-label= accepts only A-Z a-z 0-9 . _ - (got '$RUN_LABEL')" >&2
                           echo "  It is interpolated into the cypher ssh command string." >&2
                           exit 1 ;;
                       esac ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

# --preflight-only needs no --focal set: it exits before the buckets are
# resolved, and demanding them would make the cheap dry check as awkward as
# the real thing.
if [ "$PREFLIGHT_ONLY" = "0" ]; then
  IFS=',' read -ra CY_WS_ARR <<< "$CY_WS"
  [ -n "$CY_WS" ] || CY_WS_ARR=()
  N_CY=${#CY_WS_ARR[@]}
  N_FOCAL=${#FOCAL_ARR[@]}
  EXPECT=$((N_CY + 1))
  if [ "$N_FOCAL" -ne "$EXPECT" ]; then
    echo "FATAL: need exactly $EXPECT --focal flags (1 dispatcher + $N_CY cyphers); got $N_FOCAL" >&2
    exit 1
  fi
else
  IFS=',' read -ra CY_WS_ARR <<< "$CY_WS"
  [ -n "$CY_WS" ] || CY_WS_ARR=()
  N_CY=${#CY_WS_ARR[@]}
fi

# --- persist-schema guard (link#246) ---
# Both `bcfishpass` and `default` resolve $pipeline$schema to `fresh`
# (measured 2026-08-30), so `--config=default` with no --schema= persists a
# DIFFERENT bundle's output into the SAME tables as the bcfishpass run and
# overwrites it in place. There is no recovery and no signal: the tables
# look fine, they are just a mixture of two methodologies.
if [ "$CONFIG" != "bcfishpass" ] && [ -z "$SCHEMA_OVERRIDE" ]; then
  echo "FATAL: --config=$CONFIG requires an explicit --schema=." >&2
  echo "  '$CONFIG' resolves pipeline\$schema to the same target as" >&2
  echo "  --config=bcfishpass, so running it bare would overwrite the" >&2
  echo "  bcfishpass persist in place." >&2
  echo "  e.g. --config=$CONFIG --schema=fresh_${CONFIG}" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$(date -u +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/data-raw/logs/study_area_run"
mkdir -p "$LOG_DIR"
CYPHER_DIR="$HOME/Projects/repo/rtj/scripts/cypher"
CYPHER_TF="$HOME/Projects/repo/rtj/env/do/dev/cypher"
# Cyphers must run the SAME git ref as the dispatcher so they carry these
# driver scripts (wsg_run_one.R etc.) + a matching link install. cypher_prep
# reads CYPHER_PREP_BRANCH (default main, which lacks these scripts); pass the
# dispatcher's current branch. The branch MUST be pushed to origin first —
# cypher_prep does `git fetch origin && git reset --hard origin/$BRANCH`.
LINK_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"

# Resolve persist schema: --schema= overrides the config's YAML default
# (e.g. for side-by-side bundle compares: --config=default --schema=fresh_default
# keeps the bcfp-config run intact in `fresh`). All R scripts read LNK_SCHEMA
# below and override `cfg$pipeline$schema` if it is non-empty.
resolve_schema() {   # $1 = config name; prints the schema, non-zero on R failure
  (cd "$REPO_ROOT" && Rscript -e \
    'cat(link::lnk_config(commandArgs(TRUE)[1])$pipeline$schema)' "$1")
}

if [ -n "$SCHEMA_OVERRIDE" ]; then
  SCHEMA="$SCHEMA_OVERRIDE"
else
  # `2>/dev/null || true` is correct here and only looks like the bug shape:
  # an R failure yields an empty $SCHEMA, which the FATAL below catches.
  SCHEMA=$(resolve_schema "$CONFIG" 2>/dev/null || true)
  # There was a "second layer" collision check here comparing $SCHEMA to
  # bcfishpass's. It was unreachable and has been removed rather than left
  # as decoration: this branch runs only when --schema= is absent, and the
  # guard above already exited for every non-bcfishpass config in that case,
  # so its `[ "$CONFIG" != "bcfishpass" ]` test was always false. A guard
  # that cannot go red is worse than none — it reads as coverage.
  # The name-based guard above is the real one and covers every config.
fi
[ -n "$SCHEMA" ] || { echo "FATAL: could not resolve persist schema for --config=$CONFIG"; exit 1; }
export LNK_SCHEMA="$SCHEMA"

# --- run identity (link#262) ---
# Minted ONCE, here, before anything forks. $TS is already the run's own
# UTC stamp and is what every log file in this run is named after, so the uid
# is greppable back to its artifacts. The random suffix is what makes it an
# identifier rather than a timestamp: two dispatches started in the same
# second — a re-run fired immediately after a failure, most plausibly — would
# otherwise share a uid and merge into one "run", which is precisely the
# ambiguity this replaces.
#
# $RANDOM is fine for that job (collision avoidance within a second, not
# secrecy). Padded to a fixed width so the ids sort and eyeball consistently.
RUN_UID="${TS}-$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
export LNK_RUN_UID="$RUN_UID"
export LNK_RUN_LABEL="$RUN_LABEL"

echo "=== study_area_run $TS ==="
echo "  run_uid:      $RUN_UID"
echo "  run_label:    ${RUN_LABEL:-<none>}"
echo "  config:       $CONFIG"
echo "  branch:       $LINK_BRANCH (cyphers run this ref)"
echo "  persist:      $SCHEMA"
echo "  cyphers:      ${CY_WS_ARR[*]:-<none>} ($N_CY)"
echo "  log dir:      $LOG_DIR"
echo "  vintage max:  ${VINTAGE_MAX_DAYS} d"
echo "  recompute -j: $RECOMPUTE_JOBS"
[ "$PREFLIGHT_ONLY" = "0" ] || echo "  MODE:         --preflight-only (no spend, no writes)"
[ -z "$PREFLIGHT_NOTE" ] || echo "  OVERRIDE:     vintage+parity downgraded to warnings — $PREFLIGHT_NOTE"

# --- trap: burn cyphers on exit (safety net; explicit burn after consolidate) ---
CYPHERS_UP=0
burn_cyphers() {
  local rc=$?
  if [ "$CYPHERS_UP" = "0" ]; then return $rc; fi
  if [ "$KEEP_CYPHERS" = "1" ]; then
    echo "=== trap EXIT: --keep-cyphers; NOT burning (${CY_WS_ARR[*]}) ==="
    return $rc
  fi
  echo "=== BURN CYPHERS (trap EXIT) ==="
  ( cd "$CYPHER_DIR"
    for WS in "${CY_WS_ARR[@]}"; do
      ./cypher_down.sh --workspace "$WS" > "$LOG_DIR/${TS}_burn_$WS.log" 2>&1 &
    done
    wait )
  local clean=1
  for WS in "${CY_WS_ARR[@]}"; do
    local n
    # `|| n="?"` so a tofu hiccup (pipefail) can't abort the verification
    # loop when burn_cyphers runs via the EXIT trap (set -e active there).
    n=$(cd "$CYPHER_TF" && TF_WORKSPACE="$WS" tofu state list 2>/dev/null | wc -l | tr -d ' ') || n="?"
    echo "  cy[$WS]: $n tofu resources (expect 0)"; [ "$n" = "0" ] || clean=0
  done
  # Three outcomes, not two. The old form piped doctl into grep, so a doctl
  # failure produced no output, grep found no match, and a leaked droplet
  # billing indefinitely was reported as "✓ no cypher droplets". Capture
  # first, test the exit status, then test the value (link#246).
  local dl
  if dl=$(doctl compute droplet list --no-header 2>/dev/null); then
    if printf '%s' "$dl" | grep -qi cypher; then
      echo "  ✗ doctl still shows cypher droplets"; clean=0
    else
      echo "  ✓ doctl: no cypher droplets"
    fi
  else
    echo "  ✗ could not query doctl — droplet state UNKNOWN, check manually"; clean=0
  fi
  [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate"
  CYPHERS_UP=0
  return $rc
}

# Host addresses must not reach a public repo. The logs below are committed
# deliberately as evidence (soul#129), but a worker's address is infrastructure
# identity, not evidence -- nothing in a log is less useful for its removal.
#
# Runs from the EXIT trap so it covers every path, including the one where the
# driver is killed partway. That is not hypothetical: on 2026-08-31 a killed run
# left its addresses in logs that were then committed to this public repo.
#
# Loopback and 0.0.0.0 are meaningful and kept. The negative lookaheads also
# spare R version strings -- `0.0.0.9000` matches an IPv4 pattern, and blanket
# substitution silently corrupts every DESCRIPTION-style version it meets.
redact_log_addresses() {
  [ -d "${LOG_DIR:-}" ] || return 0
  local n=0 f
  # Two patterns, because the recompute pool writes per-job logs into
  # ${TS}_recompute.d/ (parallel writers must not share one fd). The first
  # glob matches only files, so without the second a killed run would leave
  # every per-job log unredacted -- and being killed partway is exactly the
  # case this function exists for. A non-matching glob expands to itself and
  # is discarded by the -f test below.
  for f in "$LOG_DIR"/"${TS:-}"_* "$LOG_DIR"/"${TS:-}"_*/*; do
    [ -f "$f" ] || continue
    perl -i -pe 's/(?<![\d.])(?!0\.0\.0\.0)(?!127\.0\.0\.1)(?!0\.0\.0\.9)(\d{1,3}\.){3}\d{1,3}(?![\d.])/<host>/g' \
      "$f" 2>/dev/null && n=$((n + 1))
  done
  [ "$n" -gt 0 ] && echo "  ✓ redacted host addresses in $n log file(s)"
  return 0
}

on_exit() {
  local rc=$?
  burn_cyphers || rc=$?
  redact_log_addresses
  return $rc
}
trap on_exit EXIT

# --- pre-flight, local: everything answerable before a droplet exists ------
#
# A cypher's software is PREDICTABLE from here: its link comes from
# `git reset --hard origin/$LINK_BRANCH`, its fresh from link's DESCRIPTION.
# So the pre-spin gate validates what the cyphers are GOING to get, and
# preflight_hosts() below confirms they actually got it. Predict before
# spend; verify before write (link#246).
#
# Accumulate into `fail` rather than exiting early, so one run reports every
# problem — an operator fixing an expired token should not then discover the
# branch is unpushed on the next attempt.
preflight_local() {
  echo "=== pre-flight (local; pre-spend) ==="
  local fail=0

  pg_isready -h localhost -p 5432 >/dev/null 2>&1 \
    || { echo "  ✗ local fwapg down (:5432)"; fail=1; }

  # bcfp reference view is a constant (fresh.streams_vw_bcfp) — it lives in
  # its own schema independent of $SCHEMA (the persist target). All compare
  # code paths (R/lnk_compare_mapping_code.R:78 default) read it from `fresh`.
  local has_vw
  has_vw=$(PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -t -A -c \
    "SELECT 1 FROM information_schema.tables WHERE table_schema='fresh' AND table_name='streams_vw_bcfp'" 2>/dev/null || true)
  [ "$has_vw" = "1" ] \
    || { echo "  ✗ fresh.streams_vw_bcfp missing (run snapshot_bcfp.sh --with-bcfp-views)"; fail=1; }

  # --- gate: dispatcher's fresh provides what the pipeline calls ----------
  # The same assertion cypher_prep runs on each worker, run here too so the
  # dispatcher cannot be the odd one out.
  #
  # The expression loads the package itself — LNK_LOAD is only read by the
  # driver scripts, so an `-e` relying on it finds no such function, exits
  # non-zero, and reports "missing symbols" for a broken invocation rather
  # than a broken fresh. Exit 2 separates those two states, because sending
  # someone to debug fresh when the harness is what failed is its own bug.
  local fresh_out fresh_rc
  fresh_out=$(cd "$REPO_ROOT" && Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
res <- lnk_preflight_fresh(quiet = TRUE)
cat(res$message, "\n", sep = "")
quit(status = if (isTRUE(res$ok)) 0L else 1L)
' 2>&1) && fresh_rc=0 || fresh_rc=$?
  case "$fresh_rc" in
    0) echo "  ✓ dispatcher fresh exports what the pipeline calls" ;;
    1) printf '%s\n' "$fresh_out" | sed 's/^/    /'
       echo "  ✗ dispatcher fresh is missing required symbols"; fail=1 ;;
    *) printf '%s\n' "$fresh_out" | sed 's/^/    /'
       echo "  ✗ could not run the fresh check (R error, not a fresh problem)"; fail=1 ;;
  esac

  # --- gate: branch pushed + worktree clean (link#246) --------------------
  # Cyphers do `git fetch origin && git reset --hard origin/$BRANCH`
  # (cypher_prep.sh). Anything unpushed does not exist on them, and the host
  # silently runs older driver scripts against a newer dispatcher.
  if [ "$N_CY" -gt 0 ]; then
    # Fetch FIRST: @{upstream} is a LOCAL ref, so without this the check
    # compares against a stale copy and is a false green. And a FAILED fetch
    # leaves exactly that stale ref, so it cannot be waved through with
    # `|| true` — that would print "origin/$BRANCH is at HEAD" on the
    # strength of a comparison against a ref that was never updated, and the
    # run would spin droplets before cypher_prep's own
    # `git reset --hard origin/$BRANCH` discovered the problem.
    if ! git -C "$REPO_ROOT" fetch --quiet origin "$LINK_BRANCH" 2>/dev/null; then
      echo "  ✗ could not fetch origin/$LINK_BRANCH — cannot verify the cyphers' ref"
      fail=1
    elif ! git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      echo "  ✗ branch '$LINK_BRANCH' has no upstream — git push -u origin $LINK_BRANCH"
      fail=1
    else
      # Assign, test the EXIT STATUS, then test the value. A rev-list error
      # prints nothing, and empty must never read as "0 commits ahead".
      local ahead
      if ahead=$(git -C "$REPO_ROOT" rev-list --count '@{upstream}..HEAD' 2>/dev/null); then
        if [ "$ahead" != "0" ]; then
          echo "  ✗ $ahead local commit(s) not on origin/$LINK_BRANCH — cyphers would run older code"
          fail=1
        else
          echo "  ✓ origin/$LINK_BRANCH is at HEAD"
        fi
      else
        echo "  ✗ could not compare HEAD to @{upstream}"
        fail=1
      fi
    fi
  fi

  # Uncommitted work is unpushable by definition, so for a multi-host run it
  # is the same failure. With no cyphers there is no drift axis, only a
  # provenance-honesty concern, so it warns rather than blocks local dev.
  #
  # Excludes data-raw/logs (link#257). That directory is TRACKED on purpose —
  # run logs are contemporaneous evidence — and this very script writes ~15
  # files into it, plus snapshot_bcfp.sh stamps bcfp_baselines.csv there. So
  # the run dirties its own checkout by operating, and the bare predicate
  # blocked every second run. Untracked files elsewhere still count: a new
  # uncommitted R/*.R is invisible to a cypher, which is the drift being
  # detected. Same pathspec as .lnk_pkg_git_dirty(), and `:(exclude)` in long
  # form for the same reason — `:!` aborts, and an aborted git status returns
  # empty, which reads as clean.
  local dirty
  if dirty=$(git -C "$REPO_ROOT" status --porcelain -- ':(top,exclude)data-raw/logs' 2>/dev/null); then
    if [ -n "$dirty" ]; then
      if [ "$N_CY" -gt 0 ]; then
        echo "  ✗ dispatcher checkout dirty; cyphers reset to origin/$LINK_BRANCH and cannot see it"
        fail=1
      else
        echo "  WARN: dispatcher checkout dirty — log.link_sha will not describe what ran"
      fi
    fi
  else
    echo "  ✗ could not read git status"; fail=1
  fi

  # --- gate: fwapg SHA resolvable and exported (link#246) -----------------
  # .lnk_fwapg_sha() reads FWAPG_GIT_SHA, then FWAPG_DIR, then
  # ~/Projects/repo/fwapg, else NA. Cyphers have NO fwapg checkout, so
  # without this export every cypher row lands fwapg_sha = NA — the exact
  # provenance hole this issue exists to close. Resolve once here and hand
  # the same value to every host.
  local fwapg_dir fwdirty
  fwapg_dir="${FWAPG_DIR:-$HOME/Projects/repo/fwapg}"
  if FWAPG_SHA=$(git -C "$fwapg_dir" rev-parse HEAD 2>/dev/null) && [ -n "$FWAPG_SHA" ]; then
    if fwdirty=$(git -C "$fwapg_dir" status --porcelain 2>/dev/null); then
      [ -z "$fwdirty" ] \
        || { echo "  ✗ fwapg checkout dirty ($fwapg_dir) — the SHA stamped into log.fwapg_sha would be a lie"; fail=1; }
    fi
    export FWAPG_GIT_SHA="$FWAPG_SHA"
    echo "  ✓ fwapg_sha ${FWAPG_SHA:0:12} (exported to all hosts)"
  else
    echo "  ✗ no fwapg checkout at $fwapg_dir — set FWAPG_DIR, or every row lands fwapg_sha=NA"
    fail=1
  fi

  # --- gate: bcfp reference pinned, and exported to all hosts (link#262) --
  # The compare reference is the LOCAL snapshot fresh.streams_vw_bcfp, and the
  # build it was loaded from is recorded by snapshot_bcfp.sh in
  # data-raw/logs/bcfp_baselines.csv. That ledger is PER HOST, and a cypher has
  # no row of its own — it git-resets the repo (so the CSV is present) but never
  # snapshots under its own hostname. Without this export every cypher row lands
  # bcfp_model_version NULL: 13 of 34 rows last field run, the majority at 217.
  #
  # Exactly the FWAPG_GIT_SHA shape above, for exactly the same reason. Resolve
  # once here from the dispatcher's ledger; hand the same value to every host.
  local bcfp_ver
  if bcfp_ver=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
v <- link:::.lnk_bcfp_log_ledger()
cat(if (is.null(v)) "" else v$model_version)
' 2>/dev/null) && [ -n "$bcfp_ver" ]; then
    export LNK_BCFP_MODEL_VERSION="$bcfp_ver"
    echo "  ✓ bcfp reference pinned at $bcfp_ver (exported to all hosts)"
  else
    # A warning, not a failure. An unpinned run is worse provenance but still
    # correct modelling, and refusing to run over it would make the pin a
    # blocker rather than a record. It IS reported, because a silent NULL is
    # how this column stayed empty for 37 rows without anyone noticing.
    echo "  WARN: no bcfp baseline row for this host — bcfp_model_version will"
    echo "        be NULL on every row. Run: bash data-raw/snapshot_bcfp.sh --with-bcfp-views"
  fi

  # --- gate: primitive vintage on the dispatcher --------------------------
  # The predicate lives in R (lnk_preflight_vintage) because "absent is not
  # fresh" and the NULL-timestamp branch are what testthat can prove and
  # shell cannot. `last_analyze` alone is NULL on every primitive; the R
  # side uses GREATEST(last_analyze, last_autoanalyze).
  if (cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/host_vintage.R "$VINTAGE_MAX_DAYS" 2>&1 | sed 's/^/    /'); then
    echo "  ✓ dispatcher primitives within ${VINTAGE_MAX_DAYS} d"
  else
    if [ -n "$PREFLIGHT_NOTE" ]; then
      echo "  WARN: dispatcher primitives stale — proceeding on --preflight-note"
    else
      echo "  ✗ dispatcher primitives stale/absent — re-run with --refresh-primitives,"
      echo "    or: bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force"
      fail=1
    fi
  fi

  # --- gate: BOTH DigitalOcean credentials, each forced to a real API call -
  if [ "$N_CY" -gt 0 ]; then
    # Leg 1 — doctl's own token. This DOES call the API; its weakness was
    # asserting only an exit status on a command whose healthy answer is an
    # empty list, so branch on status and never on the output.
    if doctl compute droplet list --no-header >/dev/null 2>&1; then
      echo "  ✓ doctl token valid (DO API reachable)"
    else
      echo "  ✗ doctl token invalid/expired — doctl auth init"
      fail=1
    fi

    # Leg 2 — the token tofu actually spins droplets with. A DIFFERENT
    # credential; both were minted 2026-05-18 and both expired 2026-08-30,
    # and probing only leg 1 lets leg 2 surface mid-spin with half-created
    # droplets and a held state lock.
    #
    # `tofu plan` is NOT a valid probe: against a workspace with no
    # resources it returns "Plan: N to add" without ever contacting DO.
    # BSD sed on this PATH, so POSIX classes only — no \s, no \+.
    local tok code do_url
    # Test seam. Restricted to https so a stray value cannot send a live
    # bearer token to an arbitrary host over plaintext.
    do_url="${LNK_PREFLIGHT_DO_URL:-https://api.digitalocean.com/v2/account}"
    case "$do_url" in
      https://*) ;;
      *) echo "  ✗ LNK_PREFLIGHT_DO_URL must be https (got '$do_url')"; fail=1; do_url="" ;;
    esac
    tok="${LNK_PREFLIGHT_DO_TOKEN:-$(sed -nE \
      's/^[[:space:]]*do_token[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
      "$CYPHER_TF/terraform.tfvars" 2>/dev/null | head -1)}"
    [ -n "$do_url" ] || tok=""
    if [ -z "$tok" ]; then
      echo "  ✗ could not read do_token from $CYPHER_TF/terraform.tfvars"
      fail=1
    else
      # --config - keeps the token out of argv, which `ps` exposes.
      code=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" \
        | curl -sS --config - --max-time 20 -o /dev/null -w '%{http_code}' \
               "$do_url" 2>/dev/null) || code="000"
      case "$code" in
        200) echo "  ✓ tofu do_token valid (HTTP 200 /v2/account)" ;;
        401) echo "  ✗ tofu do_token expired/revoked (HTTP 401) — mint a new PAT and update $CYPHER_TF/terraform.tfvars"; fail=1 ;;
        000) echo "  ✗ could not reach the DO API (network/DNS)"; fail=1 ;;
        *)   echo "  ✗ tofu do_token probe returned HTTP $code"; fail=1 ;;
      esac
    fi
    unset tok

    # Leg 3 — the s3 state backend. This exercises the AWS credentials, NOT
    # DigitalOcean. Labelling it a DO check is what kept the old pre-flight
    # green through a dead DO token.
    if (cd "$CYPHER_TF" && tofu workspace list >/dev/null 2>&1); then
      echo "  ✓ tofu s3 backend reachable"
    else
      echo "  ✗ tofu s3 backend unreachable (aws creds / not initialized)"
      fail=1
    fi
  fi

  return "$fail"
}

# --- pre-flight, hosts: post-prep, pre-write -------------------------------
# Cannot run earlier — the cyphers do not exist before the spin and their
# packages are not installed before prep. It still runs before any
# wsg_run_one.R touches the persist, so it is a "fail before WRITE" gate
# even though it is not a "fail before SPEND" one. A failure here exits 1,
# which trips the EXIT trap and burns the cyphers, bounding the loss at
# prep time rather than a whole run.
collect_stamps() {   # $1 = destination tsv
  local tsv="$1" out ws
  : > "$tsv"
  # Assign first, THEN test the exit status. `out=$(... || echo ERROR)`
  # would make a failed collector look like a row.
  if ! out=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/host_stamp.R "$CONFIG" 2>/dev/null); then
    echo "  ✗ dispatcher stamp failed"; return 1
  fi
  [ -n "$out" ] || { echo "  ✗ dispatcher returned an empty stamp"; return 1; }
  printf '%s\n' "$out" >> "$tsv"
  for ws in "${CY_WS_ARR[@]}"; do
    if ! out=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "cypher@${CY_IP[$ws]}" \
        "cd ~/Projects/repo/link && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && Rscript data-raw/host_stamp.R '$CONFIG'" 2>/dev/null); then
      echo "  ✗ cy[$ws] stamp failed (ssh or Rscript) — treated as a FAILURE, not a skip"
      return 1
    fi
    [ -n "$out" ] || { echo "  ✗ cy[$ws] returned an empty stamp"; return 1; }
    printf '%s\n' "$out" >> "$tsv"
  done
  return 0
}

judge_stamps() {     # $1 = tsv
  (cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
a <- commandArgs(TRUE)
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
# Column names come from .lnk_preflight_stamp_cols(), the SAME function
# lnk_preflight_stamp() builds its output from — deliberately not a second
# list in this file. A shell-side copy would be an invariant enforced only
# by two lists happening to agree: drop a field from the R stamp and
# read.delim silently left-shifts the rest, padding the last column, so a
# cypher on a different commit passes as "parity OK". No test written in R
# can catch that, because both sides of the comparison would be R.
#
# na.strings = character(0) is load-bearing too. lnk_preflight_stamp() emits
# the literal string "NA" for anything it could not resolve; read.delim
# defaults to na.strings = "NA" and would turn that sentinel back into a
# real NA, which the unresolved check would not match — so a run with
# fwapg_sha unresolved on every host reported "host parity clean". (The R
# side treats NA as unresolved now as well; this keeps the data faithful.)
s <- utils::read.delim(a[1], header = FALSE, colClasses = "character",
                       na.strings = character(0),
                       col.names = .lnk_preflight_stamp_cols())
# forbid_dirty = FALSE here, and ONLY here. The pre-spin check in
# preflight_local() already required a clean dispatcher tree, which is the
# meaningful moment. By the time this runs, BOTH hosts are dirty by their own
# normal operation: the dispatcher has written five run logs into the tracked
# data-raw/logs/study_area_run/, and snapshot_bcfp.sh has stamped
# data-raw/logs/bcfp_baselines.csv on the cypher. Leaving it on made the gate
# fire on every real run — it passed its tests only because the fixtures set
# dirty = "FALSE", a fixture that could not reach the failure mode.
#
# repo_sha equality still proves both hosts are on the same commit, which is
# what parity is actually asserting.
res <- lnk_preflight_parity(s, n_expected = as.integer(a[2]),
                            forbid_dirty = FALSE)
quit(status = if (isTRUE(res$ok)) 0L else 1L)
' "$1" "$((N_CY + 1))")
}

preflight_hosts() {
  [ "$N_CY" -gt 0 ] || { echo "  ✓ host pre-flight: no cyphers, nothing to compare"; return 0; }
  echo "=== pre-flight (hosts; post-prep, pre-write) ==="
  local fail=0 ws
  local tsv="$LOG_DIR/${TS}_stamps.tsv"

  if collect_stamps "$tsv" && judge_stamps "$tsv"; then
    echo "  ✓ host parity clean ($((N_CY + 1)) hosts)"
  elif [ "$AUTO_INSTALL" = "1" ]; then
    # Remediation, NOT a skip: re-run cypher_prep's install stage — which
    # re-runs the fresh export assertion — then re-check exactly once.
    echo "  → --auto-install: reinstalling on cyphers and re-checking once"
    for ws in "${CY_WS_ARR[@]}"; do
      ssh "cypher@${CY_IP[$ws]}" \
        "CYPHER_PREP_BRANCH='$LINK_BRANCH' CYPHER_PREP_STAGE=install bash /tmp/cypher_prep.sh" \
        >> "$LOG_DIR/${TS}_autoinstall.log" 2>&1 \
        || { echo "  ✗ cy[$ws] reinstall failed; see $LOG_DIR/${TS}_autoinstall.log"; fail=1; }
    done
    if [ "$fail" = "0" ] && collect_stamps "$tsv" && judge_stamps "$tsv"; then
      echo "  ✓ host parity clean after reinstall"
    else
      echo "  ✗ host parity STILL failing after --auto-install"
      fail=1
    fi
  elif [ -n "$PREFLIGHT_NOTE" ]; then
    echo "  WARN: host parity failed — proceeding on --preflight-note"
  else
    echo "  ✗ host parity failed (re-run with --auto-install to remediate)"
    fail=1
  fi

  # Cypher primitive vintage. Not a formality: prep just ran
  # snapshot_bcfp.sh, and this verifies the primitives actually landed
  # rather than trusting the prep sentinel.
  for ws in "${CY_WS_ARR[@]}"; do
    if ssh -o BatchMode=yes -o ConnectTimeout=15 "cypher@${CY_IP[$ws]}" \
         "cd ~/Projects/repo/link && Rscript data-raw/host_vintage.R '$VINTAGE_MAX_DAYS'" \
         >> "$LOG_DIR/${TS}_vintage.log" 2>&1; then
      echo "  ✓ cy[$ws] primitives within ${VINTAGE_MAX_DAYS} d"
    else
      if [ -n "$PREFLIGHT_NOTE" ]; then
        echo "  WARN: cy[$ws] primitives stale — proceeding on --preflight-note"
      else
        echo "  ✗ cy[$ws] primitives stale/absent — see $LOG_DIR/${TS}_vintage.log"
        fail=1
      fi
    fi
  done

  return "$fail"
}

# --- optional: refresh the dispatcher's primitives before anything else ----
# Default OFF. Auto-running an ~8-minute data pull inside a paid-droplet
# orchestration is worse than stopping with the exact remediation printed.
if [ "$REFRESH_PRIMITIVES" = "1" ]; then
  echo "=== --refresh-primitives: snapshot_bcfp.sh --with-bcfp-views --force ==="
  ( cd "$REPO_ROOT" && PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost \
      PGPORT=5432 PGDATABASE=fwapg \
      bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force ) \
    > "$LOG_DIR/${TS}_snapshot.log" 2>&1 \
    || { echo "FATAL: snapshot_bcfp.sh failed; see $LOG_DIR/${TS}_snapshot.log"; exit 1; }
  echo "  ✓ primitives refreshed (see $LOG_DIR/${TS}_snapshot.log)"
fi

preflight_local || { echo "FATAL: pre-flight failed; aborting before spend"; exit 1; }
echo "  ✓ pre-flight clean (tunnel-free)"

if [ "$PREFLIGHT_ONLY" = "1" ]; then
  echo "=== --preflight-only: local gates passed; exiting before spin ==="
  # Report what was NOT checked. Several gates are gated on N_CY > 0, so a
  # bare --preflight-only silently skips the credential probes — which are
  # the highest-value ones, since an expired token is what motivated them.
  # Absence of evidence has to be reported as absence, not read as a pass.
  if [ "$N_CY" -eq 0 ]; then
    echo "  NOT CHECKED (no --cy-workspaces given, so no cypher gates ran):"
    echo "    - doctl credential, tofu do_token, tofu s3 backend"
    echo "    - branch-pushed assertion"
    echo "    - host parity and cypher primitive vintage (need live cyphers)"
    echo "  For the full pre-spend set, pass the workspaces you intend to use:"
    echo "    bash data-raw/study_area_run.sh --preflight-only --cy-workspaces=job1,job2,job3"
  else
    echo "  NOT CHECKED (require live cyphers): host parity, cypher primitive vintage."
  fi
  exit 0
fi

# --- resolve drainage-closed DS-first buckets ---
echo "=== resolve drainage-closed DS-first buckets ==="
DISP_BUCKET=$(cd "$REPO_ROOT" && Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[0]}")
DISP_BUCKET=$(echo "$DISP_BUCKET" | tr -d '[:space:]')
echo "  dispatcher (focal=${FOCAL_ARR[0]}): $DISP_BUCKET"
declare -A CY_BUCKET
for i in "${!CY_WS_ARR[@]}"; do
  WS="${CY_WS_ARR[$i]}"
  B=$(cd "$REPO_ROOT" && Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[$((i+1))]}")
  CY_BUCKET[$WS]=$(echo "$B" | tr -d '[:space:]')
  echo "  cy[$WS] (focal=${FOCAL_ARR[$((i+1))]}): ${CY_BUCKET[$WS]}"
done

# Non-fatal: warn if buckets overlap. A WSG in two hosts' closures is
# computed on both and consolidate is last-writer-wins. Harmless when focal
# sets are drainage-independent (Peace/Fraser/Skeena are distinct roots), but
# surface an accidental overlap so it's visible rather than silent.
# sed, not `grep -v '^$'`: grep exits 1 when it selects nothing, which under
# `set -euo pipefail` aborts a plain assignment. Both instances here are
# provably unreachable today (study_area_wsgs.R stop()s on an empty resolve,
# so a bucket cannot be blank), but the unsafe form has already caused two
# real aborts in this script and is exactly what gets copied next.
DUP=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | sed '/^[[:space:]]*$/d' | sort | uniq -d | paste -sd, - )
[ -z "$DUP" ] || echo "  WARN: buckets overlap on: $DUP (computed on multiple hosts; consolidate last-writer-wins)"

# --- spin + prep cyphers ---
declare -A CY_IP
if [ "$N_CY" -gt 0 ]; then
  echo "=== spin cyphers: ${CY_WS_ARR[*]} ==="
  ( cd "$CYPHER_DIR"
    for WS in "${CY_WS_ARR[@]}"; do
      ./cypher_up.sh --workspace "$WS" > "$LOG_DIR/${TS}_up_$WS.log" 2>&1 &
    done
    wait )
  for WS in "${CY_WS_ARR[@]}"; do
    IP=$(cd "$CYPHER_TF" && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) \
      || { echo "FATAL: tofu droplet_ip failed for $WS"; exit 1; }
    [ -n "$IP" ] || { echo "FATAL: empty droplet_ip for $WS"; exit 1; }
    CY_IP[$WS]="$IP"; echo "  cy[$WS] = $IP"
  done
  CYPHERS_UP=1

  echo "=== prep cyphers (cypher_prep.sh) ==="
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    ( # Wait until the droplet accepts a connection AS THE cypher USER before
      # scp. `cypher_up` reporting "ready" is not sufficient: it polls for
      # /var/lib/cloud/cypher-provisioned, which is baked into the snapshot
      # image, so on a snapshot spin the marker is already present at first
      # contact and the check returns before runcmd has copied root's SSH keys
      # to the cypher user (NewGraphEnvironment/rtj#248). root@ works the whole
      # time — DO injects keys every boot — so probing anything but `cypher@`
      # would be a false green.
      #
      # Exhausting the wait must FAIL, not fall through. The previous loop ran
      # its 30 attempts and then ran scp regardless, so a host that never
      # accepted a connection produced one line — `scp: Connection closed` —
      # pointing at scp rather than at the 150s of refusals before it. Measured
      # 2026-08-31: all 30 attempts failed in 162s total, ~0.1s each, i.e. fast
      # rejections rather than connect timeouts.
      #
      # DEADLINE not iteration count, because attempts differ in cost by two
      # orders of magnitude: a refusal returns instantly, an unreachable host
      # burns the full ConnectTimeout. 30 iterations meant anywhere from 2.5 to
      # 5 minutes depending on failure mode, which is not a budget.
      ssh_deadline=$(( $(date +%s) + PREP_SSH_WAIT_S ))
      ssh_ok=0
      ssh_last=""
      while [ "$(date +%s)" -lt "$ssh_deadline" ]; do
        if ssh_last=$(ssh -o ConnectTimeout=10 -o BatchMode=yes \
             -o StrictHostKeyChecking=accept-new \
             "cypher@$IP" 'true' 2>&1); then
          ssh_ok=1
          break
        fi
        sleep 10
      done
      if [ "$ssh_ok" != "1" ]; then
        echo "FATAL: cypher@$IP never accepted a connection within ${PREP_SSH_WAIT_S}s." >&2
        echo "  Last ssh error: ${ssh_last:-<none>}" >&2
        echo "  root@ almost certainly works — cypher_up injects keys for root on" >&2
        echo "  every boot, while the cypher user's authorized_keys is copied by" >&2
        echo "  cloud-init runcmd. Check with:" >&2
        echo "    ssh root@$IP 'ls -l /home/cypher/.ssh/authorized_keys; cloud-init status'" >&2
        echo "  See NewGraphEnvironment/rtj#248. Raise the wait with --prep-ssh-wait=<seconds>." >&2
        exit 1
      fi
      scp -q "$REPO_ROOT/data-raw/cypher_prep.sh" "cypher@$IP:/tmp/cypher_prep.sh" \
        && ssh "cypher@$IP" "CYPHER_PREP_BRANCH='$LINK_BRANCH' bash /tmp/cypher_prep.sh" ) > "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
  done
  wait
  # Grep the ANCHORED "=== READY" (cypher_prep.sh's last line), not
  # "snapshot_bcfp.sh: complete" (link#246). The old sentinel was wrong in
  # both directions:
  #
  #   fail-toward-PASS — snapshot_bcfp.sh prints "complete." and
  #   cypher_prep.sh's `tail -5` copies it into this log BEFORE
  #   lnk_persist_init runs. A persist_init FATAL therefore exits 1 with the
  #   sentinel already logged, this grep succeeds, and WSGs run against a
  #   half-prepped cypher.
  #
  #   fail-toward-stop — the snapshot's skip-if-current path prints
  #   "snapshot_bcfp: ... skipping." (no ".sh") and exits 0 without ever
  #   emitting the sentinel, so a legitimately-skipped load read as FATAL.
  #
  # -x so "=== READY (install stage only; ...)" cannot satisfy a full-prep
  # check. Only a complete prep prints the bare line.
  for WS in "${CY_WS_ARR[@]}"; do
    grep -qx "=== READY" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null \
      || { echo "FATAL: cypher[$WS] prep failed; see $LOG_DIR/${TS}_prep_$WS.log"; exit 1; }
  done
  echo "  ✓ cyphers prepped"

  # Post-prep, pre-write. exit 1 here trips the EXIT trap, which burns the
  # cyphers — the loss is bounded at spin + prep rather than a whole run of
  # two mixed model versions landing in one schema.
  preflight_hosts \
    || { echo "FATAL: host pre-flight failed; aborting before any WSG writes"; exit 1; }
fi

# --- run buckets DS-first (dispatcher local + cyphers, parallel) ---
# Per-WSG SOFT-FAIL (mirrors wsgs_run_host.R resume-safe behaviour): a single
# WSG error logs a warning and the loop CONTINUES. It must NEVER abort the host
# and trip the trap-burn before consolidate — that lost a whole run + the
# cyphers' data on 2026-05-25 (one species-less WSG -> exit 1 -> FATAL -> burn).
# Missing WSGs surface as gaps in the final compare, not as data loss.
echo "=== run buckets (DS-first) ==="
( cd "$REPO_ROOT"
  for w in $(echo "$DISP_BUCKET" | tr ',' ' '); do
    LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn \
      Rscript data-raw/wsg_run_one.R "$w" "$CONFIG" \
      || echo "[WARN] dispatcher WSG $w failed (continuing)"
  done ) > "$LOG_DIR/${TS}_run_local.log" 2>&1 &
LOCAL_PID=$!
declare -A CY_PID
for WS in "${CY_WS_ARR[@]}"; do
  IP="${CY_IP[$WS]}"; B_SPACE=$(echo "${CY_BUCKET[$WS]}" | tr ',' ' ')
  # FWAPG_GIT_SHA is resolved once on the dispatcher (preflight_local) and
  # handed to every host: cyphers have no ~/Projects/repo/fwapg, so without
  # it .lnk_fwapg_sha() returns NA and every cypher row lands with a NULL
  # fwapg_sha (link#246 Phase 5).
  #
  # LINK_GIT_SHA / FRESH_GIT_SHA are deliberately NOT exported here. Each
  # cypher writes its OWN observed values into ~/.Renviron during prep;
  # pushing the dispatcher's values across would launder a claim into the
  # worker's provenance and make the parity gate circular.
  # LNK_RUN_UID / LNK_RUN_LABEL must be exported HERE as well as on the local
  # leg (link#262). An export in the dispatcher's environment does not cross
  # ssh, so setting only the local one lands run_uid on the dispatcher's WSGs
  # and NULL on every cypher's — a half-labelled run that looks fine until
  # someone queries it. This is the same both-legs trap LNK_GUARD_DOWNSTREAM
  # hit in link#227, where the missed second leg made cyphers hard-fail and
  # silently skip WSGs.
  ssh "cypher@$IP" "cd ~/Projects/repo/link && export LNK_SCHEMA='$SCHEMA' && export LNK_GUARD_DOWNSTREAM=warn && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export LNK_RUN_UID='$RUN_UID' && export LNK_RUN_LABEL='$RUN_LABEL' && export LNK_BCFP_MODEL_VERSION='${LNK_BCFP_MODEL_VERSION:-}' && for w in $B_SPACE; do Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done" \
    > "$LOG_DIR/${TS}_run_$WS.log" 2>&1 &
  CY_PID[$WS]=$!
done
# A non-zero host exit (e.g. ssh dropped) is logged, NOT fatal — we still
# consolidate whatever each host persisted so a late failure can't lose the
# other hosts' work.
wait $LOCAL_PID || echo "  WARN: dispatcher run returned non-zero; see $LOG_DIR/${TS}_run_local.log"
for WS in "${CY_WS_ARR[@]}"; do
  wait "${CY_PID[$WS]}" || echo "  WARN: cy[$WS] run returned non-zero; see $LOG_DIR/${TS}_run_$WS.log"
done
echo "  ✓ host runs finished (per-WSG soft-fail; gaps surface in compare)"

# --- completeness accounting, per host, BEFORE consolidate (link#246) ------
# The per-WSG soft-fail above is deliberate, but it means "0 of 28 succeeded"
# and "28 of 28 succeeded" produce the same exit status. That is exactly the
# 2026-05 failure: every WSG on every cypher errored, the hosts exited 0, and
# nothing said so until the compare.
#
# It must NOT abort here, though. An abort at this point runs with
# CYPHERS_UP=1, so the EXIT trap burns the cyphers and destroys the WSGs that
# *did* succeed — one bad WSG on one host throwing away the whole paid run,
# which is the exact accident the soft-fail comment above exists to prevent.
#
# Instead, narrow each host's consolidate bucket to the WSGs it actually
# reported. That also removes the reason the abort was here: schema_consolidate
# DELETEs its bucket before COPYing, and a bucket containing only WSGs that are
# about to be re-COPYed cannot delete anything it does not replace. The gap
# then surfaces at the coverage post-condition after the burn, by which point
# the successful work is safely on the dispatcher.
# Split a CSV into lines, dropping blanks. `sed` deleting every line still
# exits 0, where `grep -v '^$'` exits 1 — and under `set -euo pipefail` that
# aborts the script from inside a plain assignment. That trap has now bitten
# this diff twice (cypher_prep's ~/.Renviron filter, then the consolidate
# bucket builder below), so the safe form lives in one helper rather than
# being remembered at each call site.
#
# `printf '%s\n'`, not `printf '%s'`: without the trailing newline `wc -l`
# counts separators rather than items and reports one fewer than there is, so
# a host that completed its whole bucket would be reported incomplete. The
# empty case still yields 0, because sed drops the resulting blank line.
csv_lines() { printf '%s\n' "${1:-}" | tr ',' '\n' | sed '/^[[:space:]]*$/d'; }
csv_count() { csv_lines "${1:-}" | wc -l | tr -d ' '; }

# --- post-consolidate recompute pool (link#250) ----------------------------
# recompute_one runs ONE WSG and never returns non-zero: the pool must not be
# able to abort under `set -e`, and the exit status is carried by the .rc file
# rather than by this function's return.
#
# One log per job, not a shared fd. Parallel appends to one file interleave
# mid-record once a record exceeds the stdio buffer (~64 KB), which a full R
# traceback comfortably does.
#
# The .rc file holds the finished TSV ROW, not a bare number, so collection is
# one `find -exec cat` with no basename loop. It is also written LAST, so a
# job killed partway leaves no row and is judged "never reported" rather than
# silently counted as fine.
recompute_one() {   # $1 = WSG
  local w="$1" rc=0
  ( cd "$REPO_ROOT"
    LNK_LOAD=loadall LNK_VIEWS_PREBUILT=1 \
      Rscript data-raw/wsg_recompute_one.R "$w" "$CONFIG"
  ) > "$RC_DIR/$w.log" 2>&1 || rc=$?
  [ "$rc" = "0" ] || echo "[WARN] recompute WSG $w failed (rc=$rc; continuing)" \
    >> "$RC_DIR/$w.log"
  printf '%s\t%s\n' "$w" "$rc" > "$RC_DIR/$w.rc"
  return 0
}

# Order the pool's work list LONGEST-FIRST from previously recorded times.
#
# A pool's makespan is bounded below by its slowest single job, so a long job
# that starts last extends the whole phase. Measured 2026-09-01: CHWK is 226 s
# against 11 s for SALR, and one WSG was 74% of a four-WSG set. LPT is already
# this repo's answer for packing components onto hosts (study_area_buckets.R,
# wsgs_dispatch.sh); this is the same rule one level down, inside one host.
#
# Ordered on prior RECOMPUTE times, never on segment count. Segments are a
# reasonable proxy for modelling work (R^2 0.64 over 104 WSGs) and a bad one
# here: SALR has 20% MORE segments than CHWK and finishes 20x faster, so a
# segment ordering would actively run the cheap job first.
#
# Times come from previous runs' committed ${TS}_recompute.log files, newest
# wins. A WSG with no recorded time gets the MEDIAN of those that have one --
# the same rule study_area_buckets.R uses for a WSG missing from the network
# table, so an unknown never sorts as free.
#
# With NO prior times at all this returns the input order and SAYS SO. The
# ops-hardening record (planning/archive/2026-05-ops-hardening-20260514) has
# the precedent: an LPT fallback that silently degraded to a naive split and
# ignored host speeds went unnoticed across a 217-WSG run.
recompute_order() {   # $1 = csv of WSGs -> prints WSGs, longest-first
  local wsgs="$1" tf med n
  tf=$(mktemp "${TMPDIR:-/tmp}/lnk_rc_times.XXXXXX") || { csv_lines "$wsgs"; return 0; }
  # sort -r on TS-prefixed names is newest-first; awk keeps the first sighting
  # of each WSG, so a later run's time wins.
  find "$LOG_DIR" -maxdepth 1 -name '*_recompute.log' -type f 2>/dev/null \
    | sort -r \
    | while IFS= read -r f; do
        sed -nE 's/^\[wsg_recompute_one\] ([A-Z]{4}) recomputed in ([0-9.]+) min.*/\1 \2/p' "$f"
      done | awk '!seen[$1]++' > "$tf"
  n=$(wc -l < "$tf" | tr -d ' ')
  if [ "${n:-0}" -eq 0 ]; then
    echo "  note: no prior recompute times in $LOG_DIR — running in input order" >&2
    rm -f "$tf"; csv_lines "$wsgs"; return 0
  fi
  med=$(cut -d' ' -f2 "$tf" | sort -n \
        | awk '{a[NR]=$1} END{print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}')
  echo "  ordering ${n} known WSG time(s) longest-first (median ${med} min for the rest)" >&2
  csv_lines "$wsgs" \
    | awk -v tf="$tf" -v med="$med" '
        BEGIN { while ((getline l < tf) > 0) { split(l, a, " "); t[a[1]] = a[2] } }
        { printf "%s %s\n", ($1 in t ? t[$1] : med), $1 }' \
    | sort -k1,1nr -k2,2 \
    | cut -d' ' -f2
  rm -f "$tf"
}

# Bounded-width pool. `wait -n` is bash 4.3+ and /bin/bash on macOS is 3.2.57,
# so a free slot is found by polling liveness with `kill -0` and reaping the
# finished child with `wait <pid>` (which returns immediately for a child that
# has already exited). We deliberately do NOT read the rc from `wait`: the .rc
# file is the single source of truth, which also means the evidence survives a
# killed dispatcher.
run_recompute_pool() {   # $1 = width
  local width="$1" slot pid w all_pids=""
  local SLOT_PID
  # Width must be a positive integer or this HANGS rather than failing:
  # `seq 0 -1` is empty, so the slot scan never runs, `break 2` is
  # unreachable, and the outer `while :; sleep 1` spins forever.
  # --recompute-jobs validates its own input, but recompute_parity.sh and
  # recompute_sweep.sh pass a width straight through, so the guard belongs
  # HERE where all three callers meet it.
  #
  # SHAPE FIRST, then value. `[ abc -lt 1 ]` exits 2 ("integer expression
  # expected") rather than returning true, so a numeric-only guard treats a
  # non-numeric width as "condition false", falls through, and hangs -- which
  # is the exact failure it was written to prevent. Measured: 0 and -1 were
  # refused while abc and 2x still hung.
  case "${width:-}" in
    ''|*[!0-9]*)
      echo "FATAL: run_recompute_pool needs a positive integer width (got '${width:-}')" >&2
      return 1 ;;
  esac
  # NORMALISE THE BASE ONCE, before anything consumes it. `test` and `case`
  # read base 10; `$(( ))` reads a leading zero as OCTAL. So "08" passes both
  # validators and then dies in `$((width - 1))` with "value too great for
  # base" -> empty seq -> the same hang; and "010" quietly becomes 8, giving
  # a pool two slots narrower than the operator asked for and than the banner
  # reports. Three rounds of this bug were three predicates disagreeing about
  # the grammar; one normalisation ends the class.
  width=$((10#$width))
  # Upper bound HERE, not only on the CLI flag. `10#` wraps silently on
  # overflow -- 10#99999999999999999999 is 7766279631452241919, which passes
  # the shape check and the >= 1 test and then sends `seq` off for the rest of
  # the afternoon. --recompute-jobs is saved by its own <= 16, but
  # recompute_parity.sh and recompute_sweep.sh pass an operator width straight
  # through, and this function is what all three callers meet.
  if [ "$width" -lt 1 ] || [ "$width" -gt 64 ]; then
    echo "FATAL: run_recompute_pool needs 1 <= width <= 64 (got '$width')" >&2
    return 1
  fi
  # Pre-seed every slot. Referencing an unset array element under `set -u` is
  # an unbound-variable error on bash 3.2.
  SLOT_PID=()
  for slot in $(seq 0 $((width - 1))); do SLOT_PID[$slot]=0; done

  for w in $(csv_lines "$ALL_WSGS"); do
    while :; do
      for slot in $(seq 0 $((width - 1))); do
        pid=${SLOT_PID[$slot]}
        [ "$pid" = "0" ] && break 2
        if ! kill -0 "$pid" 2>/dev/null; then
          wait "$pid" 2>/dev/null || true
          SLOT_PID[$slot]=0
          break 2
        fi
      done
      sleep 1
    done
    recompute_one "$w" &
    SLOT_PID[$slot]=$!
    all_pids="$all_pids ${SLOT_PID[$slot]}"
  done
  # Drain the last partial wave, waiting on OUR children only.
  #
  # A bare `wait` waits for every background job in the calling shell, not
  # just the ones this pool started -- so it silently couples the pool to
  # whatever else the caller has backgrounded, and hangs outright if any of
  # those is long-lived. Measured 2026-09-01: a 2-second sampler loop
  # backgrounded by data-raw/recompute_sweep.sh wedged the pool indefinitely,
  # with every job already finished and nothing to show for it.
  #
  # An empty WSG list means zero iterations and no pids -- that emptiness is
  # NOT judged here, it is judged in R by lnk_fanout_judge(), where the
  # branch can be tested.
  for pid in $all_pids; do wait "$pid" 2>/dev/null || true; done
}

bucket_done() {   # $1 = logfile; prints the WSGs the host reported, one per line
  # Matches the WSG code, not the surrounding prose, so a reworded cat() in
  # wsg_run_one.R degrades to "this host reported nothing" — handled loudly
  # below — rather than to a wrong set.
  #
  # The readability test is not decorative: `sed` on a missing file exits
  # non-zero, which under `set -e` would abort into the EXIT trap and burn
  # the cyphers that DID succeed. An unreadable log means "reported nothing".
  [ -r "$1" ] || return 0
  sed -nE 's/^\[wsg_run_one\] ([A-Z]{4}) .*(done|SKIP).*/\1/p' "$1" | sort -u
}

report_completeness() {   # $1 = label, $2 = logfile, $3 = expected csv
  local exp_n got_n warn_n
  exp_n=$(csv_count "$3")
  # bucket_done's `sort -u` terminates its last line, so wc -l is right here;
  # counted the same way as exp_n regardless, so the two cannot drift.
  got_n=$(csv_count "$(bucket_done "$2" | paste -sd, -)")
  warn_n=$(grep -c '^\[WARN\] ' "$2" 2>/dev/null) || warn_n=0
  if [ "$got_n" = "$exp_n" ]; then
    echo "  ✓ $1: $got_n/$exp_n WSGs accounted for"
    return 0
  fi
  echo "  ✗ $1: only $got_n/$exp_n WSGs accounted for ($warn_n [WARN]) — see $2"
  return 1
}

echo "=== per-host completeness ==="
complete_fail=0
report_completeness "dispatcher" "$LOG_DIR/${TS}_run_local.log" "$DISP_BUCKET" \
  || complete_fail=1
declare -A CY_BUCKET_DONE
for WS in "${CY_WS_ARR[@]}"; do
  report_completeness "cy[$WS]" "$LOG_DIR/${TS}_run_$WS.log" "${CY_BUCKET[$WS]}" \
    || complete_fail=1
  CY_BUCKET_DONE[$WS]=$(bucket_done "$LOG_DIR/${TS}_run_$WS.log" | paste -sd, -)
done
[ "$complete_fail" = "0" ] || {
  echo "  WARN: consolidating only the WSGs each host reported. The run will"
  echo "        finish so nothing already computed is lost, then exit non-zero."
}

# --- consolidate cyphers -> dispatcher ---
if [ "$N_CY" -gt 0 ]; then
  echo "=== consolidate cyphers -> dispatcher ($SCHEMA) ==="
  SRC_R="list("
  first=1
  n_src=0
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    # The bucket is what the host REPORTED, not what it was asked to do.
    # schema_consolidate DELETEs its bucket before COPYing, so a bucket
    # holding only WSGs that are about to be re-COPYed cannot delete
    # anything it does not replace. A host that reported nothing is skipped
    # entirely rather than handed an empty bucket — an empty one would make
    # schema_consolidate stop() and take the other hosts' work with it.
    bucket_r=$(csv_lines "${CY_BUCKET_DONE[$WS]:-}" | sed "s/.*/'&'/" | paste -sd, -)
    if [ -z "$bucket_r" ]; then
      echo "  WARN: cy[$WS] reported no WSGs — skipping it in consolidate"
      continue
    fi
    [ "$first" = "1" ] || SRC_R="$SRC_R, "
    SRC_R="$SRC_R list(host = 'cypher@$IP', via = 'docker', bucket = c($bucket_r))"
    first=0
    n_src=$((n_src + 1))
  done
  SRC_R="$SRC_R)"
  if [ "$n_src" -eq 0 ]; then
    # Zero sources gets its own branch: `list()` would make
    # schema_consolidate a no-op that returns cleanly, which reads as
    # "consolidated" when nothing was.
    echo "  ✗ no cypher reported any WSG — nothing to consolidate"
  else
    ( cd "$REPO_ROOT" && Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
res <- schema_consolidate(schema = '$SCHEMA', sources = $SRC_R, backup = TRUE)
print(res)
ok <- all(vapply(res\$sources, function(s) isTRUE(s\$ok), logical(1)))
quit(status = if (ok) 0 else 1)
" ) > "$LOG_DIR/${TS}_consolidate.log" 2>&1 \
      || { echo "  ✗ consolidate failed; see $LOG_DIR/${TS}_consolidate.log"; exit 1; }
    echo "  ✓ consolidated $n_src/$N_CY cypher(s) (see $LOG_DIR/${TS}_consolidate.log)"
  fi
fi

# --- burn cyphers now (work is consolidated; minimise idle) ---
burn_cyphers || true

# WSG set across all hosts.
ALL_WSGS=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | sed '/^[[:space:]]*$/d' | sort -u | paste -sd, - )
COMPARE_CSV="$LOG_DIR/${TS}_compare.csv"

# --- coverage post-condition (link#246) ------------------------------------
# Detection rather than prevention: this fires whatever the cause, including
# causes nobody has thought of yet. Placed AFTER the burn so a failure cannot
# leak spend, and BEFORE the recompute so a partial result is never painted
# as complete.
#
# Necessary because schema_consolidate DELETEs the destination bucket
# (schema_consolidate.R:272-276) and then COPYs (:313-316). A source that
# produced nothing therefore removes the destination's prior rows for those
# WSGs and still returns ok = TRUE.
echo "=== verify WSG coverage in $SCHEMA ==="
if MISSING=$(PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -t -A -c "
  WITH expect(w) AS (SELECT unnest(string_to_array('$ALL_WSGS', ',')))
  SELECT coalesce(string_agg(e.w, ',' ORDER BY e.w), '')
  FROM expect e
  LEFT JOIN (SELECT DISTINCT watershed_group_code w FROM ${SCHEMA}.streams) g
    ON g.w = e.w
  WHERE g.w IS NULL")
then
  # coalesce(...,'') so zero missing returns an empty string rather than
  # NULL — and the empty string is only trusted on this success branch.
  [ -z "$MISSING" ] || {
    echo "FATAL: consolidate left $SCHEMA with no rows for: $MISSING"; exit 1; }
  echo "  ✓ every run WSG has rows in $SCHEMA.streams"
else
  echo "FATAL: could not verify WSG coverage in $SCHEMA"; exit 1
fi

# This check asks "are there rows", NOT "are they from this run". The persist
# accumulates across runs and consolidate's DELETE is bucket-scoped, so a WSG
# that was excluded from a narrowed bucket keeps its PREVIOUS run's rows and
# passes here. It is a guard against consolidate destroying data, not a
# substitute for the completeness accounting — an earlier revision of this
# script leaned on it as the backstop for an incomplete run, and it cannot
# carry that. `$RUN_INCOMPLETE` is what carries it, at the very end.
RUN_INCOMPLETE="$complete_fail"
if [ "$RUN_INCOMPLETE" != "0" ]; then
  echo "  NOTE: some WSGs were excluded from consolidate this run; any rows"
  echo "        they show above are from an EARLIER run, not this one."
fi

# --- post-consolidate recompute: settle cross-WSG access (link#205) ---
# Drainage-closed + DS-first per-host is NOT sufficient: a WSG's downstream
# barriers can be cross-bucket or arrive late in DS-first order, so its access
# (hence token1/token2) is computed against an incomplete barrier set.
# Caught 2026-05-25: FINA 75% / PARA 69% per-host -> both 99% only after
# re-modelling on the full consolidated barrier set. The recompute is the
# correctness guarantee REGARDLESS of bucketing. We use lnk_access(merge=TRUE)
# — the cheap access-only recompute that reuses the persisted streams /
# habitat / barriers / barrier_overrides (link#205, ~10 s/WSG vs ~1.5 min for
# a full pipeline rebuild). Because it is cheap, we recompute ALL run WSGs
# unconditionally rather than threshold-filtering by parity — bucketing is
# now a speed knob, not a correctness lever.
#
# Parallel since link#250. Two things previously made the serial loop
# mandatory, and both are now gone:
#
#   1. lnk_access() rebuilt the SCHEMA-scoped barrier views on every call --
#      38 DDL statements against names every sibling WSG reads. CREATE OR
#      REPLACE VIEW takes an AccessExclusiveLock, and a QUEUED exclusive
#      request blocks every AccessShareLock behind it, so one job's DDL would
#      stall every sibling's read until lock_timeout killed someone. The build
#      is now hoisted below and each job runs LNK_VIEWS_PREBUILT=1. Everything
#      else a job touches is WSG-scoped (zz_lnk_streams_<wsg>,
#      zz_lnk_access_scratch_<wsg>, zz_lnk_mc_scratch_<wsg>) or row-scoped
#      (UPDATE ... WHERE watershed_group_code; DELETE+INSERT in a transaction).
#
#   2. A failed WSG was invisible. `|| echo` sat INSIDE the loop, so the
#      subshell always exited 0 and the success line below was unconditional;
#      RUN_INCOMPLETE is assigned BEFORE this block and nothing after raised
#      it. A run in which every recompute failed exited 0 and wrote a compare
#      CSV. The .rc files + lnk_fanout_judge() are what fix that.
RECOMPUTE_LOG="$LOG_DIR/${TS}_recompute.log"
RC_DIR="$LOG_DIR/${TS}_recompute.d"
RC_TSV="$LOG_DIR/${TS}_recompute.tsv"
N_RECOMPUTE=$(csv_count "$ALL_WSGS")

echo "=== post-consolidate recompute (lnk_access, ${N_RECOMPUTE} WSGs, -j${RECOMPUTE_JOBS}) ==="

# Ensure the log tables exist ONCE, single-threaded, before any job starts
# (link#262). wsg_recompute_one.R deliberately refuses to run DDL — it runs
# inside this pool, and schema DDL belongs at init, not in N concurrent jobs.
# That leaves one edge case with the worst possible timing: if every focal WSG
# on the dispatcher species-skips (wsg_run_one.R exits 0 without calling
# lnk_pipeline_run), nothing ever creates log_recompute, and the pool would
# then hard-stop on all N WSGs — at the end of a paid multi-host run, after
# consolidate. One idempotent call here removes the class for nothing.
if ( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
cfg <- lnk_config(commandArgs(TRUE)[1])
s <- Sys.getenv("LNK_SCHEMA"); if (nzchar(s)) cfg$pipeline$schema <- s
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
link:::.lnk_log_create_tables(conn, cfg$pipeline$schema)
' "$CONFIG" ) > "$LOG_DIR/${TS}_recompute_logtables.log" 2>&1; then
  echo "  ✓ log tables present in $SCHEMA"
else
  echo "  ✗ could not ensure log tables; see $LOG_DIR/${TS}_recompute_logtables.log"
  echo "    the recompute would fail per-WSG on a missing log_recompute"
  RECOMPUTE_FAIL=1
  RECOMPUTE_FAIL_STAGE="views"
fi

# Build the barrier views ONCE, single-threaded, before any job starts.
# Nested rather than `[ "$RECOMPUTE_FAIL" = "0" ] && ( build )`: with the
# short-circuit form, an already-failed log-table step would fall into this
# else and report "barrier view build failed", naming a log file that was
# never written. Two prep steps, two diagnoses.
if [ "$RECOMPUTE_FAIL" = "0" ]; then
  if ( cd "$REPO_ROOT" && LNK_LOAD=loadall \
         Rscript data-raw/barriers_views_build.R "$CONFIG" ) \
       > "$LOG_DIR/${TS}_recompute_views.log" 2>&1; then
    echo "  ✓ barrier views built once for $SCHEMA"
  else
    # Deliberately NOT falling back to per-WSG builds. At -j>1 that is exactly
    # the race the hoist removes, and it would turn one loud pre-build failure
    # into N quiet lock_timeouts attributed to individual WSGs.
    echo "  ✗ barrier view build failed; see $LOG_DIR/${TS}_recompute_views.log"
    echo "    skipping the recompute — the run will exit non-zero"
    RECOMPUTE_FAIL=1
    # Which stage failed decides which evidence exists. The pool never ran, so
    # RECOMPUTE_LOG and RC_TSV were never created -- naming them at the final
    # gate would send the operator to two absent files.
    RECOMPUTE_FAIL_STAGE="views"
  fi
fi

if [ "$RECOMPUTE_FAIL" = "0" ]; then
  rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
  # Longest-first. Ordering is the CALLER's business -- run_recompute_pool
  # consumes ALL_WSGS as given, which keeps it testable by pool_probe.sh and
  # lets recompute_parity.sh shuffle deliberately for its invariance pass.
  ALL_WSGS=$(recompute_order "$ALL_WSGS" | paste -sd, -)
  run_recompute_pool "$RECOMPUTE_JOBS"

  # Never `cat "$RC_DIR"/*` — ARG_MAX at provincial scope. `find -exec ... +`
  # also exits 0 on zero matches, leaving an EMPTY tsv rather than aborting;
  # that empty case is a real branch and is judged in R, not here.
  : > "$RC_TSV"
  find "$RC_DIR" -maxdepth 1 -name '*.rc'  -exec cat {} + >> "$RC_TSV"
  : > "$RECOMPUTE_LOG"
  find "$RC_DIR" -maxdepth 1 -name '*.log' -exec cat {} + >> "$RECOMPUTE_LOG"

  if ( cd "$REPO_ROOT" && LNK_LOAD=loadall \
         Rscript data-raw/fanout_judge.R "$RC_TSV" "$ALL_WSGS" recompute ); then
    echo "  ✓ recompute: ${N_RECOMPUTE}/${N_RECOMPUTE} WSGs"
    rm -rf "$RC_DIR"
  else
    echo "  ✗ recompute incomplete; see $RECOMPUTE_LOG and $RC_DIR/"
    RECOMPUTE_FAIL_STAGE="pool"
    # Per-job logs KEPT on failure: the concatenation is the artifact, the
    # per-job files are what you actually grep.
    RECOMPUTE_FAIL=1
  fi
fi

# --- compare (tunnel-free) -> CSV ---
echo "=== compare (tunnel-free) ==="
( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_compare.R \
    "$COMPARE_CSV" "$ALL_WSGS" "$CONFIG" ) > "$LOG_DIR/${TS}_compare.log" 2>&1 \
  || { echo "  ✗ compare failed; see $LOG_DIR/${TS}_compare.log"; exit 1; }
echo "  ✓ compare CSV: $COMPARE_CSV"

# --- report ---
echo "=== summary ==="
echo "  run WSGs: $ALL_WSGS"
echo "  compare CSV: $COMPARE_CSV"
tail -40 "$LOG_DIR/${TS}_compare.log" || true

# An incomplete run must not exit 0. The failure is reported HERE rather than
# at the point of detection so that everything already computed is
# consolidated, recomputed, compared and written out first — the operator gets
# the artifacts AND an accurate exit status, instead of one at the cost of the
# other. A caller that only checks the exit code still learns the truth.
# Two independent causes, reported separately. Merging them into one flag
# would print "some host did not account for its bucket" over a recompute
# failure, which is the wrong diagnosis and sends the operator to the wrong
# host. They are also different KINDS of failure: an incomplete bucket means
# output is missing, an incomplete recompute means output is silently WRONG.
if [ "${RUN_INCOMPLETE:-0}" != "0" ] || [ "${RECOMPUTE_FAIL:-0}" != "0" ]; then
  echo "=== study_area_run INCOMPLETE ==="
  if [ "${RUN_INCOMPLETE:-0}" != "0" ]; then
    echo "  At least one host did not account for its whole bucket; only the"
    echo "  WSGs it reported were consolidated. Artifacts above are valid for"
    echo "  those WSGs. Re-run the missing ones before trusting the compare."
  fi
  if [ "${RECOMPUTE_FAIL:-0}" != "0" ]; then
    echo "  The post-consolidate recompute did not complete for every WSG."
    echo "  Those WSGs' streams_access / streams_mapping_code still hold their"
    echo "  PRE-consolidate values, so cross-WSG access — hence token1/token2"
    echo "  and ;DAM — is WRONG for them. This is bad output, not missing"
    echo "  output: the compare CSV above will look complete."
    if [ "${RECOMPUTE_FAIL_STAGE:-pool}" = "views" ]; then
      echo "  The barrier views could not be built, so NO WSG was recomputed."
      echo "  See $LOG_DIR/${TS}_recompute_views.log."
    else
      echo "  See $RECOMPUTE_LOG (and ${RC_TSV} for per-WSG exit status)."
    fi
    echo "  Re-run just those, no full run needed:"
    echo "    LNK_SCHEMA=$SCHEMA LNK_LOAD=loadall \\"
    echo "      Rscript data-raw/wsg_recompute_one.R <WSG> $CONFIG"
  fi
  exit 1
fi
echo "=== study_area_run done ==="
