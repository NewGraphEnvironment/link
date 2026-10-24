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
# destination. Two kinds of remote host model beside it: cyphers, cloud hosts
# the driver spins, preps and burns, and persistent workers (--workers=,
# link#376), machines that exist and stay up, prepped by worker_prep.sh,
# consolidated and released but never burned. No bcfp tunnel
# (`:63333`/PG_PASS_SHARE) — the compare reference is the LOCAL bcfp
# snapshot fresh.streams_vw_bcfp (snapshot_bcfp.sh --with-bcfp-views).
#
# Every remote status is read from what the remote shell prints, never from
# ssh's exit status: some ssh servers (Tailscale SSH to macOS) exit 0
# whatever the remote command returned (link#376; data-raw/study_area_remote.sh,
# RUNBOOK §8d, "A remote status is what the remote shell prints").
#
# Cross-WSG `;DAM` correctness WITHOUT a post-consolidate recompute: each
# host gets a DRAINAGE-CLOSED bucket (focal WSGs + every WSG they drain
# through, via study_area_wsgs.R / lnk_wsg_resolve) run DOWNSTREAM-FIRST,
# so a WSG's downstream dam barriers are persisted before its access /
# mapping_code is computed. One study area (closed) per host.
#
# Usage:
#   bash data-raw/study_area_run.sh \
#     [--workers=<ssh target>,...] \
#     --cy-workspaces=job1,job2 \
#     --focal=<dispatcher focal csv> \
#     [--focal=<worker1 focal csv> ...] \
#     --focal=<cy1 focal csv> \
#     --focal=<cy2 focal csv> \
#     [--config=bcfishpass] [--schema=<persist-schema>] [--keep-cyphers] \
#     [--buckets-exact]
#
#   bash data-raw/study_area_run.sh --preflight-only    # gates only, no spend
#
# --buckets-exact (link#361): each --focal= list is the host's EXACT bucket, in
# the order given, less what the config's species presence drops
# (study_area_wsgs.R --exact); no closure expansion. For a split from
# `study_area_buckets.R --atom=group`, which packs single groups because the
# post-consolidate recompute settles access, mapping code and the gated
# habitat flags whatever host modelled which group (the split test of
# 2026-10-23, data-raw/logs/provincial_361/split_verdict.md). An overlap
# between hosts' lists is FATAL in this mode: it is operator error, not a
# closure property. Without the flag the closure buckets below apply.
#
# The number of --focal flags MUST equal 1 (dispatcher) + N workers + N
# cyphers, in order: first --focal -> dispatcher, then the workers in
# --workers order, then the cyphers in --cy-workspaces order. Put the LARGEST area on the dispatcher (first --focal): it is the
# fast, free local host, while cyphers are slower + paid — give them the
# smaller areas so they finish + burn sooner. Each cypher is accounted,
# consolidated and burned as soon as its own leg ends, while the other legs
# keep modelling (link#369; data-raw/study_area_legs.sh); a trap EXIT is the
# safety net. A cypher that may hold unconsolidated work is never burned, on
# any path: it is kept and listed in <TS>_kept_hosts.tsv, and the run exits
# non-zero (link#347). --keep-cyphers consolidates each host when its leg
# ends and burns none.
#
# The run's one backup of the persist schema is taken before any leg writes,
# in the background through spin and prep, after the dispatcher's persist is
# initialised; no leg is dispatched until it has succeeded (link#369). A
# pg_dump running beside the dispatcher would stall its groups' log-table DDL.
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
# Post-conditions: every host must account for its whole bucket before its
# consolidate (read from its database, not its log), and every run WSG must
# have rows from a build this run finished in the persist afterwards. A group
# that does not is named and the run exits non-zero, but the recompute and the
# compare still run over the rest (link#348; data-raw/study_area_finish.sh).
# A consolidate that refuses one source carries on the same way: that host is
# kept and its groups are named (link#358). The run's groups are written to
# <TS>_run_wsgs.tsv before any spend, which --recompute-only reads.
#
# Each phase's start and end per host goes to <TS>_phases.tsv as it ends, and
# the summary prints the table and the critical path (link#375; RUNBOOK §8d,
# "Where a run's time went").
#
# Extra flags:
#   --workers=<target>,...  persistent workers (link#376), each an ssh target
#                           the operator owns (A-Z a-z 0-9 . _ @ -), keyed
#                           worker1..N in that order; the key, never the
#                           target, reaches the logs. Each must answer and hold
#                           its own database, and its --schema must hold no
#                           rows for its bucket. Modelled from a clone the
#                           driver owns (~/Projects/repo/link_worker) by
#                           load_all; never burned (RUNBOOK §8d, "Persistent
#                           workers").
#   --preflight-only        run the local gates and exit (no spend)
#   --refresh-primitives    snapshot_bcfp.sh --force first (default off)
#   --auto-install          on a parity mismatch, re-run the cyphers'
#                           install stage (a worker: install fresh at the
#                           DESCRIPTION pin) and re-check once
#   --vintage-max-days=N    primitive staleness window (default 7)
#   --recompute-jobs=N      width of the post-consolidate recompute pool
#                           (default 4, max 16). The recompute was >50% of
#                           run wall clock single-threaded (link#250). N=1
#                           reproduces the serial path and is the control arm
#                           of data-raw/recompute_parity.sh.
#   --statement-timeout=N   minutes any one statement of a group's modelling
#                           may run (default 30, 1..1440; link#371). Set as
#                           PGOPTIONS='-c statement_timeout=<N>min' on BOTH
#                           modelling legs (appended to the operator's on the
#                           local leg, replacing it in the ssh string), so it
#                           reaches every connection of the run and nothing
#                           else (a role setting reaches every session on the
#                           host and must be reset). A
#                           statement past it is cancelled server-side, the
#                           group fails like any other, and the report names it
#                           with the statement. Default from 2026-10-23: the
#                           longest finished group took 16.3 min in total
#                           (SETN), while OKAN sat 4 h in one statement. Raise
#                           it when a top group is placed on a cypher by hand:
#                           cyphers ran up to 2.9x the dispatcher's time. The
#                           recompute leg is not given this bound: it keeps its
#                           own 10 min per statement and 1 min lock wait
#                           (wsg_recompute_one.R's SET, which a PGOPTIONS would
#                           not override anyway), not hit on 2026-10-23.
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
#   --recompute-only --run-uid=<uid> [--wsgs=A,B]
#                           finish an existing run on the dispatcher: coverage
#                           for that run_uid, the recompute over every group
#                           with rows from a finished build of it, the compare
#                           and the report. No droplet, no pre-flight. For a
#                           run whose missing groups were re-modelled by hand
#                           under the same run_uid (link#348). Without --wsgs=
#                           the expected groups are those the run recorded in
#                           <TS>_run_wsgs.tsv when its buckets resolved, and
#                           any with a log row for the run_uid on the
#                           dispatcher (the log alone for a run before
#                           link#358).
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

# The run-wide prep phase starts here, before its file can exist (link#375).
PHASE_RUN_START=$(date -u '+%Y-%m-%dT%H:%M:%SZ %s')

# declare -A (the per-host maps below) needs bash 4+, and waiting on the legs
# in the order they end needs `wait -n -p`, bash 5.1+ (link#369). macOS
# /bin/bash is 3.2 and would die at the first map, after the refresh and
# pre-flight already ran (link#246). Launch with Homebrew bash.
if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then
  echo "FATAL: bash ${BASH_VERSION} is too old; run with bash >= 5.1 (e.g. /opt/homebrew/bin/bash)" >&2
  exit 1
fi

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
# Minutes one modelling statement may run before Postgres cancels it (link#371).
STATEMENT_TIMEOUT_MIN=30
STATEMENT_TIMEOUT_SET=0
# Set when the recompute did not complete for every WSG. Initialised here, not
# at the recompute, so `set -u` cannot bite on any earlier exit path.
RECOMPUTE_FAIL=0
RECOMPUTE_FAIL_STAGE=""
# Set when a run group has no rows from a build this run finished, or a host
# did not account for its bucket (link#348). Read by the final report.
RUN_INCOMPLETE=0
# --recompute-only finishes an EXISTING run: its run_uid, and optionally the
# run's groups (link#348).
RECOMPUTE_ONLY=0
RUN_UID_ARG=""
WSGS_ARG=""
# --buckets-exact: each --focal= list is taken as the host's bucket (link#361).
BUCKETS_EXACT=0
# --workers=: persistent hosts reached by their own ssh targets (link#376).
WORKERS_ARG=""
FOCAL_ARR=()
for arg in "$@"; do
  case "$arg" in
    --cy-workspaces=*) CY_WS="${arg#--cy-workspaces=}" ;;
    --workers=*)       WORKERS_ARG="${arg#--workers=}" ;;
    --buckets-exact)   BUCKETS_EXACT=1 ;;
    --config=*)        CONFIG="${arg#--config=}" ;;
    --schema=*)        SCHEMA_OVERRIDE="${arg#--schema=}"
                       [ -n "$SCHEMA_OVERRIDE" ] || { echo "FATAL: --schema= requires a non-empty value" >&2; exit 1; } ;;
    --focal=*)         FOCAL_ARR+=("${arg#--focal=}") ;;
    --keep-cyphers)    KEEP_CYPHERS=1 ;;
    --preflight-only)  PREFLIGHT_ONLY=1 ;;
    --refresh-primitives) REFRESH_PRIMITIVES=1 ;;
    --auto-install)    AUTO_INSTALL=1 ;;
    --recompute-only)  RECOMPUTE_ONLY=1 ;;
    # Interpolated into SQL (the coverage and log queries), so the format the
    # driver mints is the only one accepted.
    --run-uid=*)       RUN_UID_ARG="${arg#--run-uid=}"
                       [[ "$RUN_UID_ARG" =~ ^[0-9]{8}_[0-9]{6}-[0-9a-f]{8}$ ]] \
                         || { echo "FATAL: --run-uid= must look like 20261017_004619-3f4c713b (got '$RUN_UID_ARG')" >&2; exit 1; } ;;
    --wsgs=*)          WSGS_ARG="${arg#--wsgs=}"
                       [[ "$WSGS_ARG" =~ ^[A-Z]{4}(,[A-Z]{4})*$ ]] \
                         || { echo "FATAL: --wsgs= takes comma-separated four-letter group codes (got '$WSGS_ARG')" >&2; exit 1; } ;;
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
    # Base-10 normalised like --recompute-jobs; 0 is Postgres's "no bound", so
    # it is refused rather than offered as a way to switch the bound off.
    --statement-timeout=*)
                       STATEMENT_TIMEOUT_MIN="${arg#--statement-timeout=}"
                       STATEMENT_TIMEOUT_SET=1
                       case "$STATEMENT_TIMEOUT_MIN" in
                         ''|*[!0-9]*) echo "FATAL: --statement-timeout= needs a whole number of minutes (got '$STATEMENT_TIMEOUT_MIN')" >&2; exit 1 ;;
                       esac
                       [ "${#STATEMENT_TIMEOUT_MIN}" -le 9 ] || { echo "FATAL: --statement-timeout must be <= 1440" >&2; exit 1; }
                       STATEMENT_TIMEOUT_MIN=$((10#$STATEMENT_TIMEOUT_MIN))
                       [ "$STATEMENT_TIMEOUT_MIN" -gt 0 ] || { echo "FATAL: --statement-timeout must be > 0 (there is no unbounded mode)" >&2; exit 1; }
                       [ "$STATEMENT_TIMEOUT_MIN" -le 1440 ] || { echo "FATAL: --statement-timeout must be <= 1440" >&2; exit 1; } ;;
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

# --recompute-only finishes one existing run on the dispatcher, so it needs
# that run's uid and takes nothing that dispatches. --run-uid and --wsgs
# without it would be silently ignored, so they are refused instead.
if [ "$RECOMPUTE_ONLY" = "1" ]; then
  [ -n "$RUN_UID_ARG" ] || {
    echo "FATAL: --recompute-only needs --run-uid=<uid> of the run to finish" >&2; exit 1; }
  if [ "${#FOCAL_ARR[@]}" -gt 0 ] || [ -n "$CY_WS" ] || [ -n "$WORKERS_ARG" ] || [ "$PREFLIGHT_ONLY" = "1" ] \
     || [ "$REFRESH_PRIMITIVES" = "1" ] || [ "$AUTO_INSTALL" = "1" ] || [ "$BUCKETS_EXACT" = "1" ] \
     || [ "$STATEMENT_TIMEOUT_SET" = "1" ]; then
    echo "FATAL: --recompute-only takes no --focal, --cy-workspaces, --workers, --preflight-only," >&2
    echo "  --refresh-primitives, --auto-install, --buckets-exact or --statement-timeout:" >&2
    echo "  it dispatches nothing." >&2
    exit 1
  fi
else
  [ -z "$RUN_UID_ARG" ] || {
    echo "FATAL: --run-uid= is for --recompute-only; a run mints its own" >&2; exit 1; }
  [ -z "$WSGS_ARG" ] || {
    echo "FATAL: --wsgs= is for --recompute-only; a run's groups come from --focal" >&2; exit 1; }
fi

# --config and --schema are interpolated into the cypher ssh command strings
# inside '...', like --run-label: refuse anything that could close the quote
# (link#246 code-check).
for v in "$CONFIG" "$SCHEMA_OVERRIDE"; do
  case "$v" in
    *[!A-Za-z0-9_]*) echo "FATAL: --config= / --schema= accept only A-Z a-z 0-9 _ (got '$v')" >&2; exit 1 ;;
  esac
done

# --preflight-only needs no --focal set: it exits before the buckets are
# resolved, and demanding them would make the cheap dry check as awkward as
# the real thing.
case "$CY_WS" in
  *$'\n'*) echo "FATAL: --cy-workspaces= holds a newline" >&2; exit 1 ;;
esac
IFS=',' read -ra CY_WS_ARR <<< "$CY_WS"
[ -n "$CY_WS" ] || CY_WS_ARR=()
N_CY=${#CY_WS_ARR[@]}
# Persistent workers (link#376): each target is an ssh destination the
# operator owns. It is pasted into ssh command lines and into R source, so the
# charset is restricted; a leading `-` would be an ssh option, `local` is the
# hosts lib's name for the dispatcher's own database, and a target given twice
# would model and consolidate one database as two hosts. Each worker is keyed
# worker1..N in the order given: the key, never the target, is what the logs,
# phases.tsv and kept-hosts record (the target is infrastructure identity).
# `read` stops at a newline, which would silently drop every target after it.
case "$WORKERS_ARG" in
  *$'\n'*) echo "FATAL: --workers= takes ssh targets of A-Z a-z 0-9 . _ @ - (not starting with -, not 'local'); it holds a newline" >&2; exit 1 ;;
esac
IFS=',' read -ra WK_TARGETS <<< "$WORKERS_ARG"
[ -n "$WORKERS_ARG" ] || WK_TARGETS=()
N_WK=${#WK_TARGETS[@]}
WK_KEYS=()
for i in "${!WK_TARGETS[@]}"; do
  t="${WK_TARGETS[$i]}"
  # [[ =~ ]] anchors on the whole value; grep -x would pass one with an
  # embedded newline whose first line fits (code-check round 2).
  if ! [[ "$t" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || [ "$t" = "local" ]; then
    echo "FATAL: --workers= takes ssh targets of A-Z a-z 0-9 . _ @ - (not starting with -, not 'local'); worker $((i + 1)) is not one" >&2
    exit 1
  fi
  for k in "${!WK_TARGETS[@]}"; do
    [ "$k" -lt "$i" ] && [ "${WK_TARGETS[$k]}" = "$t" ] && {
      echo "FATAL: --workers= names worker $((i + 1)) twice (as worker $((k + 1)) too)" >&2; exit 1; }
  done
  WK_KEYS+=("worker$((i + 1))")
done
for ws in ${CY_WS_ARR[@]+"${CY_WS_ARR[@]}"}; do
  if [[ "$ws" =~ ^(worker[0-9]+|dispatcher)$ ]]; then
    echo "FATAL: --cy-workspaces= may not name '$ws', which keys a worker or the dispatcher" >&2
    exit 1
  fi
done
# Every remote host, workers first: the --focal= lists follow this order.
HOST_ARR=(${WK_KEYS[@]+"${WK_KEYS[@]}"} ${CY_WS_ARR[@]+"${CY_WS_ARR[@]}"})
N_HOSTS=${#HOST_ARR[@]}
if [ "$PREFLIGHT_ONLY" = "0" ] && [ "$RECOMPUTE_ONLY" = "0" ]; then
  N_FOCAL=${#FOCAL_ARR[@]}
  EXPECT=$((N_HOSTS + 1))
  if [ "$N_FOCAL" -ne "$EXPECT" ]; then
    echo "FATAL: need exactly $EXPECT --focal flags (1 dispatcher + $N_WK workers + $N_CY cyphers, in that order); got $N_FOCAL" >&2
    exit 1
  fi
fi
# The stall hook (link#371) reaches remote legs too (link#376), so it is
# checked here, before anything runs, as well as where it is used.
if [ -n "${LNK_TEST_STALL_WSG:-}" ] && ! [[ "$LNK_TEST_STALL_WSG" =~ ^[A-Z]{4}$ ]]; then
  echo "FATAL: LNK_TEST_STALL_WSG must be one four-letter group code" >&2
  exit 1
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
# Git allows quotes, `$` and backticks in a branch name, and the branch is
# pasted into remote command strings (cypher_prep, worker_prep): refuse what
# could close a quote (link#376).
# Only where a remote host is sent it: a dispatcher-only run passes it nowhere.
if [ "$N_HOSTS" -gt 0 ] && ! [[ "$LINK_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "FATAL: the branch name holds a character the remote command strings cannot carry" >&2
  exit 1
fi
# The commit every host must model: a worker's leg checks its clone's HEAD
# against it before each group (link#376).
RUN_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
# Where a worker clones link from: origin, as https for GitHub (the repo is
# public, and a worker may hold no key for it).
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
case "$ORIGIN_URL" in
  git@github.com:*) ORIGIN_URL="https://github.com/${ORIGIN_URL#git@github.com:}" ;;
esac

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
# A schema taken from the config's YAML was not seen by the --schema= check,
# and it reaches the remote command strings too (link#376).
[[ "$SCHEMA" =~ ^[A-Za-z0-9_]+$ ]] \
  || { echo "FATAL: the persist schema of --config=$CONFIG is not a bare name" >&2; exit 1; }
export LNK_SCHEMA="$SCHEMA"

# Where the config reads discharge (link#331): every host needs that table,
# because prepare joins discharge for every group. The dispatcher's gate
# checks its own database; cypher_prep loads wet's on each cypher.
# --recompute-only models nothing and reads no discharge (wsg_recompute_one.R),
# so it resolves neither and cannot be stopped by them (link#348).
DISCHARGE=""
WET_LOAD=""
if [ "$RECOMPUTE_ONLY" = "0" ]; then
DISCHARGE=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
cat(link:::.lnk_discharge_source(lnk_config(commandArgs(TRUE)[1])))' "$CONFIG" 2>/dev/null || true)
case "$DISCHARGE" in
  fwapg|wet) ;;
  *) echo "FATAL: could not resolve the discharge source of --config=$CONFIG"; exit 1 ;;
esac
# The wet load the dispatcher holds; every cypher must hold the same one
# (cypher_prep.sh), or hosts classify on different discharge. Empty when the
# dispatcher has none, which its discharge gate then fails.
if [ "$DISCHARGE" = "wet" ]; then
  WET_LOAD=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
res <- lnk_preflight_discharge(conn, lnk_config(commandArgs(TRUE)[1]),
                               quiet = TRUE)
if (res$ok) cat(link:::.lnk_discharge_wet_load_id(res$comment))' \
    "$CONFIG" 2>/dev/null || true)
  case "$WET_LOAD" in
    "") echo "FATAL: --config=$CONFIG reads wet's discharge and the dispatcher holds none."
        echo "  LNK_LOAD=loadall Rscript data-raw/discharge_wet_load.R"
        exit 1 ;;
    *"'"*) echo "FATAL: the wet table comment holds a quote: $WET_LOAD"; exit 1 ;;
  esac
fi
fi

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
# --recompute-only takes the uid of the run it finishes, so its recompute rows
# land under that run (link#348).
if [ "$RECOMPUTE_ONLY" = "1" ]; then
  RUN_UID="$RUN_UID_ARG"
else
  RUN_UID="${TS}-$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
fi
export LNK_RUN_UID="$RUN_UID"
export LNK_RUN_LABEL="$RUN_LABEL"

echo "=== study_area_run $TS ==="
echo "  run_uid:      $RUN_UID"
echo "  run_label:    ${RUN_LABEL:-<none>}"
echo "  config:       $CONFIG"
echo "  branch:       $LINK_BRANCH (cyphers run this ref)"
echo "  persist:      $SCHEMA"
echo "  cyphers:      ${CY_WS_ARR[*]:-<none>} ($N_CY)"
echo "  workers:      ${WK_KEYS[*]:-<none>} ($N_WK; persistent, never burned)"
echo "  log dir:      $LOG_DIR"
echo "  vintage max:  ${VINTAGE_MAX_DAYS} d"
echo "  recompute -j: $RECOMPUTE_JOBS"
[ "$RECOMPUTE_ONLY" = "1" ] || echo "  statement:    ${STATEMENT_TIMEOUT_MIN} min per modelling statement (PGOPTIONS, both legs); recompute 10 min (wsg_recompute_one.R)"
# The stall hook (link#371) rides the driver's environment onto the local leg,
# so one left exported in the operator's shell would stall a real group.
[ -z "${LNK_TEST_STALL_WSG:-}" ] || echo "  TEST HOOK:    LNK_TEST_STALL_WSG=$LNK_TEST_STALL_WSG (that group stalls until the statement bound cancels it)"
[ "$BUCKETS_EXACT" = "0" ] && echo "  buckets:      closure (each --focal= expanded to its drainage closure, DS-first)" \
                            || echo "  buckets:      exact (--buckets-exact; each --focal= list as given; the recompute settles access)"
[ "$PREFLIGHT_ONLY" = "0" ] || echo "  MODE:         --preflight-only (no spend, no writes)"
[ "$RECOMPUTE_ONLY" = "0" ] || echo "  MODE:         --recompute-only (finish run_uid $RUN_UID; no spend)"
[ -z "$PREFLIGHT_NOTE" ] || echo "  OVERRIDE:     vintage+parity downgraded to warnings — $PREFLIGHT_NOTE"

# --- trap: burn cyphers on exit (safety net; explicit burn after consolidate) ---
# burn_cyphers, host_account and the hold rules live in study_area_hosts.sh
# (link#347), where tests can reach them. A cypher is HELD from the moment its
# bucket is dispatched and released only when its database shows everything it
# finished was consolidated; a held host is never burned, on any exit path,
# and is listed in ${TS}_kept_hosts.tsv with the command that burns it.
# shellcheck source=study_area_hosts.sh
source "$REPO_ROOT/data-raw/study_area_hosts.sh"
# Coverage, recompute, compare and the final report (link#348).
# shellcheck source=study_area_finish.sh
source "$REPO_ROOT/data-raw/study_area_finish.sh"
# Each phase's start and end per host, to ${TS}_phases.tsv (link#375). Not on
# --preflight-only, which runs nothing a row would time. --recompute-only writes
# its own file, under the run_uid it finishes, with the tail's rows only.
# shellcheck source=study_area_phases.sh
source "$REPO_ROOT/data-raw/study_area_phases.sh"
# Each cypher consolidated and burned when its own leg ends (link#369).
# shellcheck source=study_area_legs.sh
source "$REPO_ROOT/data-raw/study_area_legs.sh"
# Remote commands judged by what they print, never by ssh's exit status
# (link#376).
# shellcheck source=study_area_remote.sh
source "$REPO_ROOT/data-raw/study_area_remote.sh"
PHASES_TSV=""
if [ "$PREFLIGHT_ONLY" = "0" ]; then
  phases_init "$LOG_DIR/${TS}_phases.tsv"
  echo "  phases:       $PHASES_TSV"
  phase_begin prep "" "$PHASE_RUN_START"
fi
CYPHERS_UP=0
WORKERS_UP=0
for i in "${!WK_KEYS[@]}"; do
  HOST_KIND[${WK_KEYS[$i]}]=worker
  HOST_SSH[${WK_KEYS[$i]}]="${WK_TARGETS[$i]}"
done
# What to redact from the run's logs for each worker (link#376).
remote_redact_init
KEPT_N=0
KEPT_CAUSE_N=0
RECOMPUTE_RAN=0
CONSOLIDATING=0
# The lib declares every map the trap reads (CY_IP and HOST_BUCKET included,
# filled further down), so it is sourced here, at the top level, before the
# trap exists.

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
  # And each worker's ssh target, replaced by its key (link#376).
  for f in "$LOG_DIR"/"${TS:-}"_* "$LOG_DIR"/"${TS:-}"_*/*; do
    [ -f "$f" ] || continue
    remote_redact_targets "$f"
  done
  [ "$n" -gt 0 ] && echo "  ✓ redacted host addresses in $n log file(s)"
  return 0
}

on_exit() {
  local rc=$?
  # The phase the run died in, and any other still open (link#375), and the
  # table once, for a run that exits before its summary. First, so the end is
  # the moment of exit, not after the trap's burn; `|| true` so nothing here
  # can stop the burn below.
  phases_close_open || true
  [ "${PHASES_REPORTED:-0}" = "1" ] || phases_report || true
  burn_cyphers || rc=$?
  # A worker's prep still running (the run died during the cyphers' spin)
  # would keep writing ssh's output into its log after the redaction below
  # (link#376): stop it first. Its remote side may finish; it holds nothing.
  local pid
  for pid in ${WK_PREP_PIDS[@]+"${WK_PREP_PIDS[@]}"}; do
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  redact_log_addresses
  return $rc
}
trap on_exit EXIT

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

# --- --recompute-only: finish a run whose gaps were filled by hand (link#348)
# A run that ends with groups missing names them; once each is re-modelled
# under the same run_uid (LNK_RUN_UID=<uid> ... wsg_run_one.R), this runs the
# rest of a run's tail and nothing else: coverage for that run_uid, the
# recompute over every group with rows from a finished build of it, the
# compare and the report. No droplet, no pre-flight (the recompute reads only
# the persisted tables), no consolidate.
if [ "$RECOMPUTE_ONLY" = "1" ]; then
  echo "=== --recompute-only: run_uid $RUN_UID ==="
  echo "  pre-flight, dispatch and consolidate SKIPPED: this reads only the"
  echo "  persisted tables in $SCHEMA, and spins up nothing."
  pg_isready -h localhost -p 5432 >/dev/null 2>&1 \
    || { echo "FATAL: local fwapg down (:5432)"; exit 1; }
  # The compare reads the local bcfp snapshot, as in a full run.
  [ "$(PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -t -A -c \
      "SELECT 1 FROM information_schema.tables WHERE table_schema='fresh' AND table_name='streams_vw_bcfp'" 2>/dev/null || true)" = "1" ] \
    || { echo "FATAL: fresh.streams_vw_bcfp missing (run snapshot_bcfp.sh --with-bcfp-views)"; exit 1; }
  run_config_check || { echo "FATAL: refusing to recompute run_uid $RUN_UID under another config"; exit 1; }
  # A host kept by the run may still hold groups to consolidate; this run
  # cannot see its state, only the file that recorded it.
  RO_KEPT=$(grep -l -F "$RUN_UID" "$LOG_DIR"/*_kept_hosts.tsv 2>/dev/null || true)
  KEPT_TSV_GROUPS=""
  if [ -n "$RO_KEPT" ]; then
    echo "  WARN: hosts were kept for this run_uid; settle their groups per these"
    echo "        files first, and re-model only what is still missing:"
    printf '        %s\n' $RO_KEPT
    # groups, groups_partial, groups_unknown of this run's rows: the report
    # lists those apart from the groups to re-model.
    KEPT_TSV_GROUPS=$(awk -F'\t' -v u="$RUN_UID" '$4 == u { print $6 "," $7 "," $8 }' \
      $RO_KEPT | .hosts_csv)
  fi
  # The run's run_wsgs.tsv and its log rows, or --wsgs= (link#358).
  run_expected_recompute_only "$WSGS_ARG" || exit 1
  phase_end prep "" "$(.hosts_n "$RO_EXPECT")" ok
  run_finish "$RO_EXPECT" "" "$RO_EXCLUDED"
  exit 0
fi

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
  # silently runs older driver scripts against a newer dispatcher. A worker
  # resets its clone the same way (worker_prep.sh, link#376).
  if [ "$N_HOSTS" -gt 0 ]; then
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
      if [ "$N_HOSTS" -gt 0 ]; then
        echo "  ✗ dispatcher checkout dirty; remote hosts reset to origin/$LINK_BRANCH and cannot see it"
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
    # `else fail=1` is not decoration. Without it the probe fails toward SKIP:
    # a git that errors makes the inner `if` false, nothing is reported, and
    # the SHA is exported with a tick. There is deliberately no fwapg_dirty
    # column, so this gate is the ONLY thing standing between a modified
    # checkout and a SHA recorded as if it described one.
    if fwdirty=$(git -C "$fwapg_dir" status --porcelain 2>/dev/null); then
      [ -z "$fwdirty" ] \
        || { echo "  ✗ fwapg checkout dirty ($fwapg_dir) — the SHA stamped into log.fwapg_sha would be a lie"; fail=1; }
    else
      echo "  ✗ could not read git status in $fwapg_dir — cannot certify fwapg_sha clean"
      fail=1
    fi
    export FWAPG_GIT_SHA="$FWAPG_SHA"
    echo "  ✓ fwapg_sha ${FWAPG_SHA:0:12} (exported to all hosts)"
  else
    echo "  ✗ no fwapg checkout at $fwapg_dir — set FWAPG_DIR, or every row lands fwapg_sha=NA"
    fail=1
  fi

  # --- gate: bcfishobs SHA resolvable and exported (link#264) -------------
  # bcfishobs is a MODEL INPUT, not a reference dataset: it snaps observations
  # onto the network, lnk_barrier_overrides() counts those observations
  # upstream of each barrier to decide which barriers are skipped, and so it
  # moves access and mapping_code. Everything the 39 logged runs recorded
  # about it was a row count and a hardcoded source string.
  #
  # Exactly the fwapg block above, including the dirty refusal: a cypher has
  # no bcfishobs checkout, so without the export every cypher row lands
  # bcfishobs_sha = NA. There is deliberately NO bcfishobs_dirty column —
  # this gate is what makes a recorded SHA clean by construction, and a
  # column FALSE on every row carries no information (link#257).
  local bcfo_dir bcfo_dirty
  bcfo_dir="${BCFISHOBS_DIR:-$HOME/Projects/repo/bcfishobs}"
  if BCFISHOBS_SHA=$(git -C "$bcfo_dir" rev-parse HEAD 2>/dev/null) && [ -n "$BCFISHOBS_SHA" ]; then
    if bcfo_dirty=$(git -C "$bcfo_dir" status --porcelain 2>/dev/null); then
      [ -z "$bcfo_dirty" ] \
        || { echo "  ✗ bcfishobs checkout dirty ($bcfo_dir) — the SHA stamped into log.bcfishobs_sha would be a lie"; fail=1; }
    else
      echo "  ✗ could not read git status in $bcfo_dir — cannot certify bcfishobs_sha clean"
      fail=1
    fi
    export BCFISHOBS_GIT_SHA="$BCFISHOBS_SHA"
    echo "  ✓ bcfishobs_sha ${BCFISHOBS_SHA:0:12} (exported to all hosts)"
  else
    echo "  ✗ no bcfishobs checkout at $bcfo_dir — set BCFISHOBS_DIR, or every row lands bcfishobs_sha=NA"
    fail=1
  fi

  # --- gate: fresh's own code identity, BEFORE any spend (link#264) -------
  # fresh_sha and fresh_dirty are asserted on every host by
  # study_area_verify.sql, and fresh_sha is a lnk_preflight_parity key. Both
  # of those fire LATE: parity runs after spin + prep, so an unresolvable
  # fresh burns droplets before anyone finds out, and verify runs after the
  # whole run. This is the same fact, five seconds in, for free.
  #
  # The state that reaches it is not exotic. `scripts/update_hosts.sh` uses
  # `R CMD INSTALL` on a source tarball to route around r-lib/pak#658, and
  # that writes no Remote* fields at all — so before that script started
  # recording FRESH_GIT_SHA itself, a host updated with it had no recoverable
  # fresh identity. Any host updated by an older copy of it still does not.
  # The third field is a STALENESS check, not a repeat of the first. An env
  # pin (FRESH_GIT_SHA, written by scripts/update_hosts.sh or cypher_prep.sh)
  # wins tier 1 and nothing expires it, so a later install by another route --
  # pak, r-universe, a hand-run R CMD INSTALL -- leaves the old value winning
  # and this gate reading the very variable it is meant to be gating. Where
  # the DESCRIPTION also has an answer, the two must agree; where it does not,
  # there is nothing to check and the pin stands alone.
  local fresh_state fresh_sha_local fresh_dirty_local fresh_stale
  fresh_state=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
st <- link:::.lnk_pkg_git_state("fresh")
remote <- link:::.lnk_pkg_remote_sha("fresh")
stale <- !is.na(remote) && !is.na(st$sha) && !identical(remote, st$sha)
cat(if (is.na(st$sha)) "" else st$sha, "|",
    if (is.na(st$dirty)) "" else tolower(as.character(st$dirty)), "|",
    if (stale) remote else "", sep = "")
' 2>/dev/null) || fresh_state="||"
  fresh_sha_local="${fresh_state%%|*}"
  fresh_stale="${fresh_state##*|}"
  fresh_dirty_local="${fresh_state#*|}"
  fresh_dirty_local="${fresh_dirty_local%%|*}"
  if [ -n "$fresh_stale" ]; then
    echo "  ✗ FRESH_GIT_SHA pins ${fresh_sha_local:0:12} but the installed fresh"
    echo "    was built from ${fresh_stale:0:12}. The env pin is stale and would"
    echo "    be recorded as this run's fresh_sha. Fix: remove FRESH_GIT_SHA from"
    echo "    ~/.Renviron, or re-run bash scripts/update_hosts.sh fresh"
    fail=1
  elif [ -z "$fresh_sha_local" ]; then
    echo "  ✗ fresh_sha unresolvable on this host — every row would land fresh_sha=NA,"
    echo "    which study_area_verify.sql now RAISEs on and parity refuses."
    echo "    Fix: bash scripts/update_hosts.sh fresh   (it records the sha it installs)"
    fail=1
  elif [ "$fresh_dirty_local" = "true" ]; then
    echo "  ✗ fresh reports dirty — the SHA stamped into log.fresh_sha would be a lie"
    fail=1
  elif [ -z "$fresh_dirty_local" ]; then
    echo "  ✗ fresh_dirty unresolvable — 'unknown' is not 'clean', and log.fresh_sha"
    echo "    cannot be trusted without it. Fix: bash scripts/update_hosts.sh fresh"
    fail=1
  else
    echo "  ✓ fresh_sha ${fresh_sha_local:0:12} (clean)"
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
  # It is pasted into every remote leg's command, from the ledger or from the
  # operator's own environment: a whole-value check, as for --run-label.
  if [ -n "${LNK_BCFP_MODEL_VERSION:-}" ] && ! [[ "$LNK_BCFP_MODEL_VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    echo "  ✗ the bcfp model version is not a plain version string; it cannot be sent to remote hosts"
    fail=1
  fi

  # --- gate: the config's discharge table on the dispatcher (link#331) -----
  if (cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
res <- lnk_preflight_discharge(conn, lnk_config(commandArgs(TRUE)[1]))
q(status = if (res$ok) 0L else 1L)' "$CONFIG" 2>&1 | sed 's/^/    /'; exit "${PIPESTATUS[0]}"); then
    echo "  ✓ discharge ($DISCHARGE) loaded on the dispatcher"
  else
    echo "  ✗ discharge ($DISCHARGE) not loaded on the dispatcher —"
    if [ "$DISCHARGE" = "wet" ]; then
      echo "    LNK_LOAD=loadall Rscript data-raw/discharge_wet_load.R"
    else
      echo "    fwapg's fwa_stream_networks_discharge is loaded by fwapg (load.sh)"
    fi
    fail=1
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
    local dl_names
    if dl_names=$(doctl compute droplet list --no-header --format Name 2>/dev/null); then
      echo "  ✓ doctl token valid (DO API reachable)"
      # A cypher already up is most likely one an earlier run KEPT (link#347).
      hosts_preflight_droplets "$dl_names" || fail=1
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

  # --- gate: workers reachable, each its own database (link#376) ---------
  if [ "$N_WK" -gt 0 ]; then
    preflight_workers || fail=1
  fi

  return "$fail"
}

# preflight_workers: before any spend. Each worker answers over ssh (judged on
# what it prints), and its database is neither the dispatcher's nor another
# worker's: consolidate DELETEs a bucket on the dispatcher and then copies it
# from the source, so a source that is the dispatcher's own database would copy
# back nothing, and a leg there would model into the dispatcher's persist.
preflight_workers() {
  local fail=0 ws id seen="" mine
  mine=$(host_db_id local) || { echo "  ✗ could not read the dispatcher's database identity"; return 1; }
  for ws in "${WK_KEYS[@]}"; do
    if ! remote_run "${HOST_SSH[$ws]}" "true" "$LOG_DIR/${TS}_reach_$ws.log"; then
      echo "  ✗ $ws: did not answer over ssh (see $LOG_DIR/${TS}_reach_$ws.log)"
      fail=1; continue
    fi
    if ! id=$(host_db_id "${HOST_SSH[$ws]}"); then
      echo "  ✗ $ws: its database did not answer (docker exec fresh-db psql)"
      fail=1; continue
    fi
    if [ "$id" = "$mine" ]; then
      echo "  ✗ $ws: its database is the dispatcher's own; a worker must hold its own"
      fail=1; continue
    fi
    case " $seen " in
      *" $id "*) echo "  ✗ $ws: its database is another worker's"; fail=1; continue ;;
    esac
    seen="$seen $id"
    echo "  ✓ $ws: answers, its own database"
  done
  return "$fail"
}

# preflight_worker_rows: once the buckets resolve, before any spend. A
# worker's persist schema must hold no rows for a group of its bucket: the
# run's accounting and release could not tell them from this run's, and
# consolidate would copy and then delete them (link#376). Read, never
# deleted here: they may be the worker's own builds.
preflight_worker_rows() {
  local fail=0 ws in st mc
  for ws in ${WK_KEYS[@]+"${WK_KEYS[@]}"}; do
    in=$(.hosts_lines "${HOST_BUCKET[$ws]:-}" | sed "s/.*/'&'/" | paste -sd, -)
    if ! st=$(.hosts_query "${HOST_SSH[$ws]}" streams "watershed_group_code IN (${in:-NULL})") \
       || ! mc=$(.hosts_query "${HOST_SSH[$ws]}" streams_mapping_code "watershed_group_code IN (${in:-NULL})"); then
      echo "  ✗ $ws: could not read its $SCHEMA before dispatch"
      fail=1; continue
    fi
    st=$(.hosts_union "$(printf '%s\n' "$st" | .hosts_csv)" "$(printf '%s\n' "$mc" | .hosts_csv)")
    if [ -n "$st" ]; then
      echo "  ✗ $ws: its $SCHEMA already holds rows for $st, which this run would model."
      echo "    They may be that machine's own builds: consolidate or remove them deliberately,"
      echo "    or give the run another --schema=."
      fail=1
    else
      echo "  ✓ $ws: $SCHEMA holds no rows for its bucket"
    fi
  done
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
  for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
    # Judged by the status the remote shell prints (remote_run, link#376).
    if ! remote_run "${HOST_SSH[$ws]}" \
        "$(.remote_cd "$ws") && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export BCFISHOBS_GIT_SHA='${BCFISHOBS_GIT_SHA:-}' && Rscript data-raw/host_stamp.R '$CONFIG'" \
        "$tsv.$ws.out" /dev/null; then
      echo "  ✗ cy[$ws] stamp failed (ssh or Rscript) — treated as a FAILURE, not a skip"
      return 1
    fi
    out=$(remote_out "$tsv.$ws.out"); rm -f "$tsv.$ws.out"
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
' "$1" "$((N_HOSTS + 1))")
}

preflight_hosts() {
  [ "$N_HOSTS" -gt 0 ] || { echo "  ✓ host pre-flight: no remote hosts, nothing to compare"; return 0; }
  echo "=== pre-flight (hosts; post-prep, pre-write) ==="
  local fail=0 ws
  local tsv="$LOG_DIR/${TS}_stamps.tsv"

  if collect_stamps "$tsv" && judge_stamps "$tsv"; then
    echo "  ✓ host parity clean ($((N_HOSTS + 1)) hosts)"
  elif [ "$AUTO_INSTALL" = "1" ]; then
    # Remediation, NOT a skip: re-run cypher_prep's install stage — which
    # re-runs the fresh export assertion — then re-check exactly once.
    echo "  → --auto-install: reinstalling on cyphers and re-checking once"
    for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
      # Judged per host on its status and its install-stage READY line
      # (link#376), not on ssh's exit status. A worker installs fresh only, at
      # DESCRIPTION's pin (worker_prep.sh install-fresh).
      if .hosts_is_worker "$ws"; then
        if remote_run "${HOST_SSH[$ws]}" \
             "$(worker_prep_env "$ws") WORKER_PREP_STAGE=install-fresh bash -s" \
             "$LOG_DIR/${TS}_autoinstall_$ws.log" < "$REPO_ROOT/data-raw/worker_prep.sh" \
           && grep -q '^=== READY (fresh install only)' "$LOG_DIR/${TS}_autoinstall_$ws.log"; then
          :
        else
          echo "  ✗ $ws fresh install failed; see $LOG_DIR/${TS}_autoinstall_$ws.log"; fail=1
        fi
        continue
      fi
      if remote_run "${HOST_SSH[$ws]}" \
           "CYPHER_PREP_BRANCH='$LINK_BRANCH' CYPHER_PREP_STAGE=install bash /tmp/cypher_prep.sh" \
           "$LOG_DIR/${TS}_autoinstall_$ws.log" \
         && grep -q '^=== READY (install stage only' "$LOG_DIR/${TS}_autoinstall_$ws.log"; then
        :
      else
        echo "  ✗ cy[$ws] reinstall failed; see $LOG_DIR/${TS}_autoinstall_$ws.log"; fail=1
      fi
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
  for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
    # One log per host, judged by the status the remote shell prints
    # (link#376): ssh's exit status can be 0 whatever host_vintage.R returned.
    if remote_run "${HOST_SSH[$ws]}" \
         "$(.remote_cd "$ws") && Rscript data-raw/host_vintage.R '$VINTAGE_MAX_DAYS'" \
         "$LOG_DIR/${TS}_vintage_$ws.log"; then
      echo "  ✓ cy[$ws] primitives within ${VINTAGE_MAX_DAYS} d"
    else
      if [ -n "$PREFLIGHT_NOTE" ]; then
        echo "  WARN: cy[$ws] primitives stale — proceeding on --preflight-note"
      else
        echo "  ✗ cy[$ws] primitives stale/absent — see $LOG_DIR/${TS}_vintage_$ws.log"
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
  phase_begin refresh
  ( cd "$REPO_ROOT" && PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost \
      PGPORT=5432 PGDATABASE=fwapg \
      bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force ) \
    > "$LOG_DIR/${TS}_snapshot.log" 2>&1 \
    || { echo "FATAL: snapshot_bcfp.sh failed; see $LOG_DIR/${TS}_snapshot.log"; exit 1; }
  echo "  ✓ primitives refreshed (see $LOG_DIR/${TS}_snapshot.log)"
  phase_end refresh "" "" ok
else
  phase_skip refresh
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
    [ "$N_WK" -gt 0 ] || echo "    - branch-pushed assertion"
    echo "    - host parity and cypher primitive vintage (need live cyphers)"
    echo "  For the full pre-spend set, pass the workspaces you intend to use:"
    echo "    bash data-raw/study_area_run.sh --preflight-only --cy-workspaces=job1,job2,job3"
  else
    echo "  NOT CHECKED (require live cyphers): host parity, cypher primitive vintage."
  fi
  # Workers exist before prep, so they were reached and their databases told
  # apart above (link#376); what needs their prep or the buckets was not.
  [ "$N_WK" -eq 0 ] || \
    echo "  NOT CHECKED (workers; need the buckets or their prep): prior rows in $SCHEMA, worker prep, parity, vintage."
  exit 0
fi

# --- resolve drainage-closed DS-first buckets ---
# Two modes (link#361). Closure (default): each --focal= list is expanded to
# its drainage closure, DS-first. Exact (--buckets-exact): each list is the
# host's bucket as given, in its order, less the species-less groups; what a
# `study_area_buckets.R --atom=group` split prints. The recompute settles
# access either way; the closure is a speed and guard-noise knob, not a
# correctness lever (RUNBOOK §8d).
if [ "$BUCKETS_EXACT" = "1" ]; then
  BUCKET_MODE=exact; WSGS_FLAG=(--exact)
  echo "=== resolve exact buckets (--buckets-exact; order as given, species filter only) ==="
else
  BUCKET_MODE=closure; WSGS_FLAG=()
  echo "=== resolve drainage-closed DS-first buckets ==="
fi
# The run's config and the source tree, not the defaults: study_area_wsgs.R
# defaults to bcfishpass's species filter and library(link) is whatever is
# installed, which silently dropped default's KO/RB/GR-only groups (link#246).
DISP_BUCKET=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_wsgs.R ${WSGS_FLAG[@]+"${WSGS_FLAG[@]}"} "${FOCAL_ARR[0]}" "$CONFIG")
DISP_BUCKET=$(echo "$DISP_BUCKET" | tr -d '[:space:]')
echo "  dispatcher (focal=${FOCAL_ARR[0]}): $DISP_BUCKET"
declare -A HOST_BUCKET
# Workers, then cyphers: the order of the --focal= lists (link#376).
for i in "${!HOST_ARR[@]}"; do
  WS="${HOST_ARR[$i]}"
  B=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_wsgs.R ${WSGS_FLAG[@]+"${WSGS_FLAG[@]}"} "${FOCAL_ARR[$((i+1))]}" "$CONFIG")
  HOST_BUCKET[$WS]=$(echo "$B" | tr -d '[:space:]')
  echo "  $(.hosts_label "$WS") (focal=${FOCAL_ARR[$((i+1))]}): ${HOST_BUCKET[$WS]}"
done

# Overlap: a WSG in two hosts' buckets is computed on both and consolidate is
# last-writer-wins. In closure mode it is a WARN (two closures can legitimately
# share a group when the focal sets are not drainage-independent); in exact
# mode it is FATAL, because the operator wrote the lists and a group on two of
# them is a mistake, not a closure property (link#361).
# sed, not `grep -v '^$'`: grep exits 1 when it selects nothing, which under
# `set -euo pipefail` aborts a plain assignment. Both instances here are
# provably unreachable today (study_area_wsgs.R stop()s on an empty resolve,
# so a bucket cannot be blank), but the unsafe form has already caused two
# real aborts in this script and is exactly what gets copied next.
DUP=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do echo "${HOST_BUCKET[$WS]}" | tr ',' '\n'; done
} | sed '/^[[:space:]]*$/d' | sort | uniq -d | paste -sd, - )
if [ -n "$DUP" ]; then
  if [ "$BUCKETS_EXACT" = "1" ]; then
    echo "FATAL: --buckets-exact lists overlap on: $DUP (a group listed twice, on two hosts or within one; fix the --focal= lists)" >&2
    exit 1
  fi
  echo "  WARN: buckets overlap on: $DUP (computed on multiple hosts; consolidate last-writer-wins)"
fi

# Recorded before any spend (link#358): a run that stops before its tail must
# still say which groups it was running. A group that fails on a cypher, or
# before its first log row, leaves no <schema>.log row on the dispatcher, so
# without this file --recompute-only could not name it. Rewritten after the
# per-host accounting with each host's SKIPs.
# A worker's schema must hold nothing for its bucket (link#376). Before any
# spend, now that the buckets are known.
if [ "$N_WK" -gt 0 ]; then
  echo "=== workers: prior rows ==="
  preflight_worker_rows \
    || { echo "FATAL: a worker's $SCHEMA already holds rows for its bucket; aborting before spend"; exit 1; }
fi
RUN_WSGS_TSV="$LOG_DIR/${TS}_run_wsgs.tsv"
run_wsgs_write "$RUN_WSGS_TSV"
echo "  run groups: $RUN_WSGS_TSV"

# --- the dispatcher's persist, and the run's one backup (link#369) ---------
# Each cypher is consolidated as soon as its own leg ends, possibly before the
# dispatcher's first group has created the persist tables. Consolidate copies
# the tables both sides have, so into a new schema it would copy only the log
# tables, report success and delete the host's log rows. So the dispatcher's
# persist is initialised here, as cypher_prep.sh does on each cypher, with the
# same species set (cfg$species, as lnk_pipeline_run does), never
# force_recreate: this schema holds every earlier build.
#
# Then the backup, ONCE per run (it used to be taken inside the one
# consolidate, after the dispatcher had already rebuilt its groups; #354 could
# restore only log rows from it). Taken now, before any leg writes, it is the
# pre-run schema with nothing writing to it: a running pg_dump would stall
# every dispatcher group's log-table ALTER. It runs in the background through
# spin and prep (7.6 min for fresh_default's 241 groups on 2026-10-24), and
# no leg is dispatched until it has succeeded. Its use is the earlier builds'
# log history (#354) and a rollback of the whole schema to before the run; the
# recompute rebuilds access and mapping code, not the persisted groups.
# Dispatcher-only runs consolidate nothing and take none, as before.
BACKUP_RC_FILE=""
if [ "$N_HOSTS" -gt 0 ]; then
  echo "=== dispatcher persist ($SCHEMA): init, then backup in the background ==="
  ( cd "$REPO_ROOT" && Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- DBI::dbConnect(RPostgres::Postgres(), host = 'localhost', port = 5432L,
  dbname = 'fwapg', user = 'postgres', password = 'postgres')
cfg <- lnk_config('$CONFIG')
cfg\$pipeline\$schema <- '$SCHEMA'
species <- if (!is.null(cfg\$species)) cfg\$species else
  unique(lnk_load_overrides(cfg)\$parameters_fresh\$species_code)
lnk_persist_init(conn, cfg, species)
cat('=== persist init done\\n')
" ) > "$LOG_DIR/${TS}_persist_init.log" 2>&1 \
    && grep -qx "=== persist init done" "$LOG_DIR/${TS}_persist_init.log" \
    || { echo "FATAL: could not initialise $SCHEMA on the dispatcher; see $LOG_DIR/${TS}_persist_init.log"; exit 1; }
  echo "  ✓ $SCHEMA initialised (see $LOG_DIR/${TS}_persist_init.log)"
  # The outcome goes to a file, read before dispatch: the rc of a background
  # job is not something a later bare `wait` must be trusted to keep.
  BACKUP_RC_FILE="$LOG_DIR/${TS}_backup.rc"
  rm -f "$BACKUP_RC_FILE"
  phase_begin backup
  ( brc=0
    ( cd "$REPO_ROOT" || exit 1
      Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
schema_consolidate_backup('$SCHEMA', '/tmp/${SCHEMA}_pre_run_${TS}.dump')
" ) > "$LOG_DIR/${TS}_backup.log" 2>&1 || brc=$?
    echo "$brc" > "$BACKUP_RC_FILE"
    phase_end backup "" "" "$([ "$brc" = "0" ] && echo ok || echo failed)" quiet
    exit "$brc" ) >> "$LOG_DIR/${TS}_backup.log" 2>&1 &
  BACKUP_PID=$!
  echo "  backup -> /tmp/${SCHEMA}_pre_run_${TS}.dump (see $LOG_DIR/${TS}_backup.log)"
fi

# --- prep workers (link#376), in the background beside the cyphers' spin ---
# worker_prep.sh goes over ssh on stdin, so no older copy can be left behind
# on a machine that stays up, and its status is the one the remote shell
# prints (remote_run). ok needs that status 0 and the bare READY line.
WK_PREP_PIDS=()
if [ "$N_WK" -gt 0 ]; then
  echo "=== prep workers (worker_prep.sh): ${WK_KEYS[*]} ==="
  # A worker is never burned; this only lets the trap report one it holds.
  WORKERS_UP=1
  for WS in "${WK_KEYS[@]}"; do
    phase_begin prep "$WS"
    WENV=$(worker_prep_env "$WS") || exit 1
    ( prc=0
      remote_run "${HOST_SSH[$WS]}" "$WENV bash -s" "$LOG_DIR/${TS}_prep_$WS.log" \
        < "$REPO_ROOT/data-raw/worker_prep.sh" || prc=$?
      pst=failed
      [ "$prc" = "0" ] && grep -qx "=== READY" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null && pst=ok
      phase_end prep "$WS" "" "$pst" quiet
      exit "$prc" ) >> "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
    WK_PREP_PIDS+=($!)
  done
fi

# --- spin + prep cyphers ---
declare -A CY_IP
if [ "$N_CY" -gt 0 ]; then
  echo "=== spin cyphers: ${CY_WS_ARR[*]} ==="
  # Up BEFORE the spin, not after every droplet_ip resolved: a FATAL on one
  # workspace below used to exit with CYPHERS_UP=0, so the trap burned nothing
  # and the droplets that DID spin were left billing (link#347). Nothing is
  # held yet, so the trap burns every workspace; cypher_down on one that never
  # spun is a no-op.
  CYPHERS_UP=1
  # Each host's prep phase runs from the spin to its own prep's end (link#375).
  for WS in "${CY_WS_ARR[@]}"; do phase_begin prep "$WS"; done
  ( cd "$CYPHER_DIR"
    for WS in "${CY_WS_ARR[@]}"; do
      ./cypher_up.sh --workspace "$WS" > "$LOG_DIR/${TS}_up_$WS.log" 2>&1 &
    done
    wait )
  for WS in "${CY_WS_ARR[@]}"; do
    IP=$(cd "$CYPHER_TF" && TF_WORKSPACE="$WS" tofu output -raw droplet_ip 2>/dev/null) \
      || { echo "FATAL: tofu droplet_ip failed for $WS"; exit 1; }
    [ -n "$IP" ] || { echo "FATAL: empty droplet_ip for $WS"; exit 1; }
    CY_IP[$WS]="$IP"; HOST_SSH[$WS]="cypher@$IP"; echo "  cy[$WS] = $IP"
  done

  echo "=== prep cyphers (cypher_prep.sh) ==="
  PREP_PIDS=()
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    # The outer subshell writes this host's prep row when its prep ends (quiet:
    # its stdout is the host's prep log; the parent prints the rows after the wait).
    # ok only on exit 0 AND the READY line the gate below reads.
    ( prc=0
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
        && ssh "cypher@$IP" "CYPHER_PREP_BRANCH='$LINK_BRANCH' CYPHER_PREP_DISCHARGE='$DISCHARGE' CYPHER_PREP_WET_LOAD='$WET_LOAD' CYPHER_PREP_CONFIG='$CONFIG' CYPHER_PREP_SCHEMA='$SCHEMA' bash /tmp/cypher_prep.sh" ) > "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 || prc=$?
      pst=failed
      [ "$prc" = "0" ] && grep -qx "=== READY" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null && pst=ok
      phase_end prep "$WS" "" "$pst" quiet
      exit "$prc" ) >> "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
    PREP_PIDS+=($!)
  done
  # The prep legs only: a bare `wait` would also wait for the backup.
  for pid in "${PREP_PIDS[@]}"; do wait "$pid" || true; done
  for WS in "${CY_WS_ARR[@]}"; do phase_forget prep "$WS"; phase_print prep "$WS"; done
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
fi
if [ "$N_WK" -gt 0 ]; then
  for pid in "${WK_PREP_PIDS[@]}"; do wait "$pid" || true; done
  for WS in "${WK_KEYS[@]}"; do phase_forget prep "$WS"; phase_print prep "$WS"; done
  for WS in "${WK_KEYS[@]}"; do
    grep -qx "=== READY" "$LOG_DIR/${TS}_prep_$WS.log" 2>/dev/null \
      || { echo "FATAL: $WS prep failed; see $LOG_DIR/${TS}_prep_$WS.log"; exit 1; }
  done
  echo "  ✓ workers prepped"
fi

# Post-prep, pre-write. exit 1 here trips the EXIT trap, which burns the
# cyphers (a worker is never burned, and holds nothing yet) — the loss is
# bounded at spin + prep rather than a whole run of two mixed model versions
# landing in one schema.
if [ "$N_HOSTS" -gt 0 ]; then
  preflight_hosts \
    || { echo "FATAL: host pre-flight failed; aborting before any WSG writes"; exit 1; }
fi

# --- run buckets DS-first (dispatcher local + cyphers, parallel) ---
# Per-WSG SOFT-FAIL (mirrors wsgs_run_host.R resume-safe behaviour): a single
# WSG error logs a warning and the loop CONTINUES. It must NEVER abort the host
# and trip the trap-burn before consolidate — that lost a whole run + the
# cyphers' data on 2026-05-25 (one species-less WSG -> exit 1 -> FATAL -> burn).
# Missing WSGs surface as gaps in the final compare, not as data loss.
#
# LNK_HABITAT_GATE=0 on BOTH legs (link#349): the habitat gate is one-way, and a
# group modelled here reads other hosts' barriers and overrides as this host
# holds them, possibly a previous run's. Gating then would blank habitat the
# post-consolidate recompute lifts, for good. The recompute (wsg_recompute_one.R)
# always follows a dispatch and settles every group on final access.
#
# PGOPTIONS on BOTH legs too (link#371): the statement bound. The local leg
# appends it to any PGOPTIONS the operator set; the ssh string replaces it,
# because the dispatcher's tuning is not the cyphers'. Not exported driver-wide,
# so the recompute keeps its own SET. LNK_STATEMENT_TIMEOUT_MIN goes with it,
# and wsg_run_one.R refuses to model on a connection whose bound differs, so a
# leg that lost PGOPTIONS fails its first group rather than running unbound.
#
# Each leg writes its own model row from an outer subshell when its loop ends
# (link#375): the legs are waited on one after another below, so the moment a
# wait returns is not when its leg ended. The status is the leg's exit status;
# a group that failed inside it is the accounting's to name. The parent forgets
# the phase once the wait returns, so a driver killed mid-leg closes it failed,
# and a leg that outlives the driver then writes its own row as well. Each
# wrapper's own output goes to its leg's log, as the leg's did before: holding
# the driver's stdout would keep a reader of it (a `| tee`) open until the last
# leg ended, after the driver was killed. Appending is safe: the inner `>`
# truncates before either writes, and an O_APPEND fd writes at the end.
RUN_N=$( { csv_lines "$DISP_BUCKET"
  for WS in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do csv_lines "${HOST_BUCKET[$WS]}"; done
} | sort -u | wc -l | tr -d ' ')
# No leg is dispatched until the backup has succeeded (link#369). A failure
# exits before any host is held, so the trap burns them.
if [ -n "$BACKUP_RC_FILE" ]; then
  wait "$BACKUP_PID" || true
  phase_forget backup; phase_print backup
  [ "$(cat "$BACKUP_RC_FILE" 2>/dev/null)" = "0" ] \
    || { echo "FATAL: the pre-run backup of $SCHEMA failed; see $LOG_DIR/${TS}_backup.log. Nothing dispatched."; exit 1; }
  echo "  ✓ pre-run backup taken (see $LOG_DIR/${TS}_backup.log)"
fi
phase_end prep "" "$RUN_N" ok
echo "=== run buckets (DS-first) ==="
phase_begin model dispatcher
# `|| exit 1` on the cd: left of the `||` that catches its status, the leg runs with errexit
# off, so a failed cd would otherwise model every group from the wrong directory.
( mrc=0
  ( cd "$REPO_ROOT" || exit 1
  for w in $(echo "$DISP_BUCKET" | tr ',' ' '); do
    PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c statement_timeout=${STATEMENT_TIMEOUT_MIN}min" \
    LNK_STATEMENT_TIMEOUT_MIN="$STATEMENT_TIMEOUT_MIN" \
    LNK_LOAD=loadall LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 \
      Rscript data-raw/wsg_run_one.R "$w" "$CONFIG" \
      || echo "[WARN] dispatcher WSG $w failed (continuing)"
  done ) > "$LOG_DIR/${TS}_run_local.log" 2>&1 || mrc=$?
  phase_end model dispatcher "$(csv_count "$DISP_BUCKET")" \
    "$([ "$mrc" = "0" ] && echo ok || echo failed)" quiet
  exit "$mrc" ) >> "$LOG_DIR/${TS}_run_local.log" 2>&1 &
LOCAL_PID=$!
# Baseline before any write (link#347): which of each cypher's bucket already
# have streams rows from its image, so rows found later can be told apart.
for WS in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do host_baseline "$WS"; done
for WS in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
  # HELD from here on: from its first write, this host may hold the only copy
  # of finished groups. Released only by host_release after consolidate
  # (link#347); until then no exit path burns it.
  HOST_HOLD[$WS]=1
  B_SPACE=$(echo "${HOST_BUCKET[$WS]}" | tr ',' ' ')
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
  # Keepalives: this one session carries the host's whole bucket (hours); a
  # silent link drop would kill the rest of it (link#246).
  phase_begin model "$WS"
  ( mrc=0
  ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10 "${HOST_SSH[$WS]}" \
    "$(remote_leg_cmd "$WS" "$B_SPACE")" \
    > "$LOG_DIR/${TS}_run_$WS.log" 2>&1 || mrc=$?
  # The leg ended only if its loop printed its end marker (link#376): ssh can
  # exit 0 whatever happened there. Feeds HOST_RUN_RC, so release stays strict.
  remote_leg_status "$mrc" "$LOG_DIR/${TS}_run_$WS.log" && mrc=0 || mrc=$?
  phase_end model "$WS" "$(csv_count "${HOST_BUCKET[$WS]}")" \
    "$([ "$mrc" = "0" ] && echo ok || echo failed)" quiet
  exit "$mrc" ) >> "$LOG_DIR/${TS}_run_$WS.log" 2>&1 &
  HOST_LEG_PID[$WS]=$!
done
# --- each leg as it ends (link#369) ---------------------------------------
# A non-zero host exit (e.g. ssh dropped) is logged, NOT fatal: whatever each
# host persisted is still consolidated, so a late failure can't lose the other
# hosts' work.
#
# Each cypher is accounted, consolidated, released and burned as soon as its
# own leg ends, while the other legs keep modelling (study_area_legs.sh). Until
# #369 every host waited for the slowest leg and one consolidate of all of
# them: about 3 host-hours idle on 2026-10-17 and about 20 on 2026-10-23.
#
# Completeness is read per host BEFORE its consolidate (link#246), from its
# DATABASE, not its log (link#347), and never aborts: one bad group on one host
# must not trip the trap and burn the groups that did succeed. Each host's
# consolidate takes only the groups it reports finished, so its DELETE on the
# dispatcher cannot remove anything it does not replace; a gap surfaces at the
# coverage post-condition, once the successful work is safely here.
COMPLETE_FAIL=0
CONS_FAILED=""
CONS_EXCLUDED=""
CONS_STATE="$LOG_DIR/${TS}_consolidate_state.tsv"
if [ "$N_HOSTS" -gt 0 ]; then
  echo "=== legs: each remote host is consolidated when its own leg ends (a cypher then burned, a worker released) ==="
fi
legs_wait
echo "  ✓ host runs finished (per-WSG soft-fail; gaps surface in compare)"

echo "=== dispatcher completeness (database) ==="
phase_begin account dispatcher
ast=ok
host_account dispatcher local "$LOG_DIR/${TS}_run_local.log" "$DISP_BUCKET" \
  || { ast=failed; COMPLETE_FAIL=1; }
# Each host's SKIPs, now known. Never fatal here: hosts are held.
run_wsgs_write "$RUN_WSGS_TSV" \
  || echo "  WARN: could not rewrite $RUN_WSGS_TSV with SKIPs; it still lists every group"
phase_end account dispatcher "$(csv_count "$DISP_BUCKET")" "$ast"
[ "$COMPLETE_FAIL" = "0" ] || {
  echo "  WARN: consolidated only the WSGs each host finished. The run will"
  echo "        finish so nothing already computed is lost, then exit non-zero."
}

if [ "$N_HOSTS" -gt 0 ]; then
  # Every leg has ended and every host was finished as it did; this burns
  # nothing new and writes the final kept-hosts record, which names a held
  # worker as well (link#376).
  burn_cyphers || true
else
  phase_skip consolidate
  phase_skip burn
fi

# The run's groups, less SKIPs, and the finish signals the per-host accounting
# already holds (run_expected_from_hosts, study_area_finish.sh).
run_expected_from_hosts

# A host that did not account for its whole bucket. Coverage can only add to
# it: a group with no rows from this run sets it too (link#348).
RUN_INCOMPLETE="$COMPLETE_FAIL"
# A source consolidate refused or failed on is an incomplete run whatever the
# coverage classes say (link#358).
[ -z "${CONS_FAILED:-}" ] || RUN_INCOMPLETE=1

# Coverage, recompute over the groups this run built, compare, report. Exits
# non-zero on an incomplete run. Bare call: see study_area_finish.sh.
run_finish "$RUN_EXPECT" "$RUN_SIGNALS" "${CONS_EXCLUDED:-}"
