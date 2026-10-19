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
# consolidate (minimise idle); a trap EXIT is the safety net. A cypher that
# may hold unconsolidated work is never burned, on any path: it is kept and
# listed in <TS>_kept_hosts.tsv, and the run exits non-zero (link#347).
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
# consolidate (read from its database, not its log), and every run WSG must
# have rows from a build this run finished in the persist afterwards. A group
# that does not is named and the run exits non-zero, but the recompute and the
# compare still run over the rest (link#348; data-raw/study_area_finish.sh).
# A consolidate that refuses one source carries on the same way: that host is
# kept and its groups are named (link#358). The run's groups are written to
# <TS>_run_wsgs.tsv before any spend, which --recompute-only reads.
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

# declare -A (the per-host maps below) needs bash 4+; macOS /bin/bash is 3.2 and
# would die at the first map, after the refresh and pre-flight already ran
# (link#246). Launch with Homebrew bash.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "FATAL: bash ${BASH_VERSION} is too old; run with bash >= 4 (e.g. /opt/homebrew/bin/bash)" >&2
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
  if [ "${#FOCAL_ARR[@]}" -gt 0 ] || [ -n "$CY_WS" ] || [ "$PREFLIGHT_ONLY" = "1" ] \
     || [ "$REFRESH_PRIMITIVES" = "1" ] || [ "$AUTO_INSTALL" = "1" ]; then
    echo "FATAL: --recompute-only takes no --focal, --cy-workspaces, --preflight-only," >&2
    echo "  --refresh-primitives or --auto-install: it dispatches nothing." >&2
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
if [ "$PREFLIGHT_ONLY" = "0" ] && [ "$RECOMPUTE_ONLY" = "0" ]; then
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
echo "  log dir:      $LOG_DIR"
echo "  vintage max:  ${VINTAGE_MAX_DAYS} d"
echo "  recompute -j: $RECOMPUTE_JOBS"
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
CYPHERS_UP=0
KEPT_N=0
KEPT_CAUSE_N=0
RECOMPUTE_RAN=0
CONSOLIDATING=0
# The lib declares every map the trap reads (CY_IP and CY_BUCKET included,
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
  run_finish "$RO_EXPECT" ""
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
        "cd ~/Projects/repo/link && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export BCFISHOBS_GIT_SHA='${BCFISHOBS_GIT_SHA:-}' && Rscript data-raw/host_stamp.R '$CONFIG'" 2>/dev/null); then
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
# The run's config and the source tree, not the defaults: study_area_wsgs.R
# defaults to bcfishpass's species filter and library(link) is whatever is
# installed, which silently dropped default's KO/RB/GR-only groups (link#246).
DISP_BUCKET=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[0]}" "$CONFIG")
DISP_BUCKET=$(echo "$DISP_BUCKET" | tr -d '[:space:]')
echo "  dispatcher (focal=${FOCAL_ARR[0]}): $DISP_BUCKET"
declare -A CY_BUCKET
for i in "${!CY_WS_ARR[@]}"; do
  WS="${CY_WS_ARR[$i]}"
  B=$(cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[$((i+1))]}" "$CONFIG")
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

# Recorded before any spend (link#358): a run that stops before its tail must
# still say which groups it was running. A group that fails on a cypher, or
# before its first log row, leaves no <schema>.log row on the dispatcher, so
# without this file --recompute-only could not name it. Rewritten after the
# per-host accounting with each host's SKIPs.
RUN_WSGS_TSV="$LOG_DIR/${TS}_run_wsgs.tsv"
run_wsgs_write "$RUN_WSGS_TSV"
echo "  run groups: $RUN_WSGS_TSV"

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
        && ssh "cypher@$IP" "CYPHER_PREP_BRANCH='$LINK_BRANCH' CYPHER_PREP_DISCHARGE='$DISCHARGE' CYPHER_PREP_WET_LOAD='$WET_LOAD' CYPHER_PREP_CONFIG='$CONFIG' CYPHER_PREP_SCHEMA='$SCHEMA' bash /tmp/cypher_prep.sh" ) > "$LOG_DIR/${TS}_prep_$WS.log" 2>&1 &
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
# Baseline before any write (link#347): which of each cypher's bucket already
# have streams rows from its image, so rows found later can be told apart.
for WS in "${CY_WS_ARR[@]}"; do host_baseline "$WS"; done
for WS in "${CY_WS_ARR[@]}"; do
  # HELD from here on: from its first write, this host may hold the only copy
  # of finished groups. Released only by host_release after consolidate
  # (link#347); until then no exit path burns it.
  CY_HOLD[$WS]=1
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
  # Keepalives: this one session carries the host's whole bucket (hours); a
  # silent link drop would kill the rest of it (link#246).
  ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=10 "cypher@$IP" "cd ~/Projects/repo/link && export LNK_SCHEMA='$SCHEMA' && export LNK_GUARD_DOWNSTREAM=warn && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export BCFISHOBS_GIT_SHA='${BCFISHOBS_GIT_SHA:-}' && export LNK_RUN_UID='$RUN_UID' && export LNK_RUN_LABEL='$RUN_LABEL' && export LNK_BCFP_MODEL_VERSION='${LNK_BCFP_MODEL_VERSION:-}' && for w in $B_SPACE; do Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done" \
    > "$LOG_DIR/${TS}_run_$WS.log" 2>&1 &
  CY_PID[$WS]=$!
done
# A non-zero host exit (e.g. ssh dropped) is logged, NOT fatal — we still
# consolidate whatever each host persisted so a late failure can't lose the
# other hosts' work.
wait $LOCAL_PID || echo "  WARN: dispatcher run returned non-zero; see $LOG_DIR/${TS}_run_local.log"
for WS in "${CY_WS_ARR[@]}"; do
  # Recorded, not just warned: a session that dropped may have left its loop
  # running on the host, so host_release keeps any host whose session did
  # not exit 0 (link#347). host_wait records it only once wait has returned.
  host_wait "$WS" "${CY_PID[$WS]}" \
    || echo "  WARN: cy[$WS] run returned non-zero; see $LOG_DIR/${TS}_run_$WS.log"
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
# finished, read from its database (link#347). That also removes the reason
# the abort was here: schema_consolidate
# DELETEs its bucket before COPYing, and a bucket containing only WSGs that are
# about to be re-COPYed cannot delete anything it does not replace. The gap
# then surfaces at the coverage post-condition after the burn, by which point
# the successful work is safely on the dispatcher.

# What each host finished comes from its DATABASE (host_account, in
# study_area_hosts.sh): <schema>.log rows for this run_uid with date_end set,
# plus SKIP markers from the log, which write no row. The log text used to be
# the count, anchored at line start, and an R warning flushed without a newline
# hid 18 finished groups that way in run 20261017_004619-3f4c713b (link#347).
# The log is still read, unanchored, and any disagreement is printed.
echo "=== per-host completeness (database) ==="
complete_fail=0
host_account dispatcher local "$LOG_DIR/${TS}_run_local.log" "$DISP_BUCKET" \
  || complete_fail=1
declare -A CY_BUCKET_DONE
for WS in "${CY_WS_ARR[@]}"; do
  host_account "$WS" "${CY_IP[$WS]}" "$LOG_DIR/${TS}_run_$WS.log" "${CY_BUCKET[$WS]}" \
    || complete_fail=1
  # Database ∪ log done; empty for a host whose database did not answer,
  # which is then left out of consolidate (it would sink the other hosts)
  # and KEPT.
  CY_BUCKET_DONE[$WS]=$(host_consolidate_bucket "$WS")
  [ "${ACC_STATE[$WS]}" = "known" ] || \
    echo "    cy[$WS]: left out of consolidate; the host will be KEPT"
done
[ "$complete_fail" = "0" ] || {
  echo "  WARN: consolidating only the WSGs each host finished. The run will"
  echo "        finish so nothing already computed is lost, then exit non-zero."
}
# Each host's SKIPs, now known. Never fatal here: hosts are held.
run_wsgs_write "$RUN_WSGS_TSV" \
  || echo "  WARN: could not rewrite $RUN_WSGS_TSV with SKIPs; it still lists every group"

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
      echo "  WARN: cy[$WS] has nothing to consolidate — skipping it"
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
    # CONSOLIDATING marks consolidate as a write in flight against every source
    # host (link#347): a driver killed here runs its EXIT trap while this
    # subshell keeps copying and deleting from the hosts, so nothing measured
    # there in the trap is settled. Cleared as soon as the subshell returns.
    CONSOLIDATING=1
    crc=0
    # One outcome row per source (link#358), read by consolidate_outcomes.
    # Removed first, so a run that dies before writing it is never read as
    # having recorded one.
    CONS_TSV="$LOG_DIR/${TS}_consolidate.tsv"
    rm -f "$CONS_TSV"
    ( cd "$REPO_ROOT" && Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
res <- schema_consolidate(schema = '$SCHEMA', sources = $SRC_R, backup = TRUE)
print(res)
out <- do.call(rbind, lapply(names(res\$sources), function(h) {
  s <- res\$sources[[h]]
  data.frame(host = h, ok = isTRUE(s\$ok),
             stage = if (is.null(s\$stage)) NA_character_ else as.character(s\$stage),
             groups = paste(s\$groups, collapse = ','), stringsAsFactors = FALSE)
}))
if (!is.null(out)) utils::write.table(out, '$CONS_TSV', sep = '\\t', quote = FALSE,
                                      row.names = FALSE, na = '')
ok <- all(vapply(res\$sources, function(s) isTRUE(s\$ok), logical(1)))
quit(status = if (ok) 0 else 1)
" ) > "$LOG_DIR/${TS}_consolidate.log" 2>&1 || crc=$?
    CONSOLIDATING=0
    if [ "$crc" = "0" ]; then
      echo "  ✓ consolidated $n_src/$N_CY cypher(s) (see $LOG_DIR/${TS}_consolidate.log)"
    elif consolidate_outcomes "$CONS_TSV" && [ -n "$CONS_FAILED" ]; then
      # A source refused or failed; the others landed (link#358). Carry on:
      # the refused host keeps its groups and is kept below, its groups are
      # kept out of the recompute, and the run exits non-zero naming them.
      echo "  ✗ consolidate failed for: $CONS_FAILED (see $LOG_DIR/${TS}_consolidate.log)"
      echo "    carrying on with the cypher(s) that consolidated; the run will exit non-zero"
    else
      # Nothing says which sources landed (or R failed after recording every
      # source ok), so nothing after this can be judged.
      echo "  ✗ consolidate failed; see $LOG_DIR/${TS}_consolidate.log — cyphers KEPT"
      run_expected_from_hosts
      echo "    No group was recomputed. Once the hosts' groups are consolidated:"
      echo "      bash data-raw/study_area_run.sh --recompute-only --run-uid=$RUN_UID \\"
      echo "        --config=$CONFIG --schema=$SCHEMA${RUN_LABEL:+ --run-label=$RUN_LABEL} \\"
      echo "        --wsgs=$RUN_EXPECT"
      exit 1
    fi
  fi

  # Reached when consolidate recorded an outcome for every source, whether or
  # not each succeeded (link#358), or had nothing to take. A host is released
  # only when its session exited 0 and its database answers that no streams
  # rows are left for any group it ran or finished: consolidate deletes what it
  # copied from the source, and only after copying all of it, so what is left
  # was not consolidated. Any other host stays HELD and the burn below skips it
  # (link#347).
  echo "=== release consolidated cyphers ==="
  for WS in "${CY_WS_ARR[@]}"; do
    host_release "$WS" "${CY_BUCKET[$WS]}"
  done
fi

# --- burn cyphers now (released hosts only; minimise idle) ---
burn_cyphers || true

# The run's groups, less SKIPs, and the finish signals the per-host accounting
# already holds (run_expected_from_hosts, study_area_finish.sh).
run_expected_from_hosts

# A host that did not account for its whole bucket. Coverage can only add to
# it: a group with no rows from this run sets it too (link#348).
RUN_INCOMPLETE="$complete_fail"

# Coverage, recompute over the groups this run built, compare, report. Exits
# non-zero on an incomplete run. Bare call: see study_area_finish.sh.
run_finish "$RUN_EXPECT" "$RUN_SIGNALS" "${CONS_EXCLUDED:-}"
