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
#   --preflight-note="why"  downgrade ONLY vintage + parity to warnings,
#                           and only with a written reason. There is no
#                           global bypass on purpose.

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
  # Second layer for the guard above, so it survives someone editing the
  # YAML defaults: the name-based check catches the documented case, this
  # catches a future third config that happens to collide.
  BCFP_SCHEMA=$(resolve_schema bcfishpass 2>/dev/null || true)
  if [ -n "$SCHEMA" ] && [ "$CONFIG" != "bcfishpass" ] && [ "$SCHEMA" = "$BCFP_SCHEMA" ]; then
    echo "FATAL: --config=$CONFIG resolves to schema '$SCHEMA', the same target" >&2
    echo "  as --config=bcfishpass. Pass an explicit --schema=." >&2
    exit 1
  fi
fi
[ -n "$SCHEMA" ] || { echo "FATAL: could not resolve persist schema for --config=$CONFIG"; exit 1; }
export LNK_SCHEMA="$SCHEMA"

echo "=== study_area_run $TS ==="
echo "  config:       $CONFIG"
echo "  branch:       $LINK_BRANCH (cyphers run this ref)"
echo "  persist:      $SCHEMA"
echo "  cyphers:      ${CY_WS_ARR[*]:-<none>} ($N_CY)"
echo "  log dir:      $LOG_DIR"
echo "  vintage max:  ${VINTAGE_MAX_DAYS} d"
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
  if doctl compute droplet list --no-header 2>/dev/null | grep -qi cypher; then
    echo "  ✗ doctl still shows cypher droplets"; clean=0
  else echo "  ✓ doctl: no cypher droplets"; fi
  [ "$clean" = "1" ] && echo "  ✓ burn clean" || echo "  ✗ BURN INCOMPLETE — investigate"
  CYPHERS_UP=0
  return $rc
}
trap burn_cyphers EXIT

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
    # compares against a stale copy and is a false green.
    git -C "$REPO_ROOT" fetch --quiet origin "$LINK_BRANCH" 2>/dev/null || true

    if ! git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
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
  local dirty
  if dirty=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null); then
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
    local tok code
    tok="${LNK_PREFLIGHT_DO_TOKEN:-$(sed -nE \
      's/^[[:space:]]*do_token[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
      "$CYPHER_TF/terraform.tfvars" 2>/dev/null | head -1)}"
    if [ -z "$tok" ]; then
      echo "  ✗ could not read do_token from $CYPHER_TF/terraform.tfvars"
      fail=1
    else
      # --config - keeps the token out of argv, which `ps` exposes.
      code=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" \
        | curl -sS --config - --max-time 20 -o /dev/null -w '%{http_code}' \
               "${LNK_PREFLIGHT_DO_URL:-https://api.digitalocean.com/v2/account}" \
               2>/dev/null) || code="000"
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
STAMP_COLS="host,link_version,link_sha,fresh_version,fresh_sha,repo_sha,repo_dirty,config_hash,fwapg_sha,r_version"

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
s <- utils::read.delim(a[1], header = FALSE, colClasses = "character",
                       col.names = strsplit(a[2], ",")[[1]])
res <- lnk_preflight_parity(s, n_expected = as.integer(a[3]))
quit(status = if (isTRUE(res$ok)) 0L else 1L)
' "$1" "$STAMP_COLS" "$((N_CY + 1))")
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
  echo "=== --preflight-only: all local gates passed; exiting before spin ==="
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
DUP=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | grep -v '^$' | sort | uniq -d | paste -sd, - )
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
    ( # Wait for the fresh droplet's sshd before scp — cypher_up returns as
      # soon as the IP is assigned, often before SSH is up, which races scp
      # into "Connection closed". Poll up to ~150s, accept the new host key.
      for _ in $(seq 1 30); do
        ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
          "cypher@$IP" 'true' 2>/dev/null && break
        sleep 5
      done
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
  ssh "cypher@$IP" "cd ~/Projects/repo/link && export LNK_SCHEMA='$SCHEMA' && export LNK_GUARD_DOWNSTREAM=warn && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && for w in $B_SPACE; do Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done" \
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

# --- completeness count, per host, BEFORE consolidate (link#246) -----------
# The per-WSG soft-fail above is deliberate, but it means "0 of 28 succeeded"
# and "28 of 28 succeeded" produce the same exit status. That is exactly the
# 2026-05 failure: every WSG on every cypher errored, the hosts exited 0, and
# nothing said so until the compare.
#
# Counted before consolidate because consolidate DELETEs the destination
# bucket before it COPYs — so a host that lost its whole bucket does not
# merely fail to add rows, it REMOVES the rows already there and reports ok.
check_bucket_complete() {   # $1 = label, $2 = logfile, $3 = expected count
  local done_n warn_n
  done_n=$(grep -c '^\[wsg_run_one\] .* \(done\|SKIP\)' "$2" 2>/dev/null) || done_n=0
  warn_n=$(grep -c '^\[WARN\] ' "$2" 2>/dev/null) || warn_n=0
  if [ "$done_n" = "$3" ]; then
    echo "  ✓ $1: $done_n/$3 WSGs accounted for"
    return 0
  fi
  echo "  ✗ $1: only $done_n/$3 WSGs accounted for ($warn_n [WARN]) — see $2"
  return 1
}

complete_fail=0
n_disp=$(echo "$DISP_BUCKET" | tr ',' '\n' | grep -c '[^[:space:]]') || n_disp=0
check_bucket_complete "dispatcher" "$LOG_DIR/${TS}_run_local.log" "$n_disp" || complete_fail=1
for WS in "${CY_WS_ARR[@]}"; do
  n_ws=$(echo "${CY_BUCKET[$WS]}" | tr ',' '\n' | grep -c '[^[:space:]]') || n_ws=0
  check_bucket_complete "cy[$WS]" "$LOG_DIR/${TS}_run_$WS.log" "$n_ws" || complete_fail=1
done
[ "$complete_fail" = "0" ] || {
  echo "FATAL: at least one host did not account for its whole bucket."
  echo "  Refusing to consolidate — consolidate DELETEs before it COPYs, so"
  echo "  proceeding would delete existing rows for the missing WSGs."
  exit 1
}

# --- consolidate cyphers -> dispatcher ---
if [ "$N_CY" -gt 0 ]; then
  echo "=== consolidate cyphers -> dispatcher ($SCHEMA) ==="
  SRC_R="list("
  first=1
  for WS in "${CY_WS_ARR[@]}"; do
    IP="${CY_IP[$WS]}"
    bucket_r=$(echo "${CY_BUCKET[$WS]}" | tr ',' '\n' | grep -v '^$' | sed "s/.*/'&'/" | paste -sd, -)
    [ "$first" = "1" ] || SRC_R="$SRC_R, "
    SRC_R="$SRC_R list(host = 'cypher@$IP', via = 'docker', bucket = c($bucket_r))"
    first=0
  done
  SRC_R="$SRC_R)"
  ( cd "$REPO_ROOT" && Rscript -e "
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
source('data-raw/schema_consolidate.R')
res <- schema_consolidate(schema = '$SCHEMA', sources = $SRC_R, backup = TRUE)
print(res)
ok <- all(vapply(res\$sources, function(s) isTRUE(s\$ok), logical(1)))
quit(status = if (ok) 0 else 1)
" ) > "$LOG_DIR/${TS}_consolidate.log" 2>&1 \
    || { echo "  ✗ consolidate failed; see $LOG_DIR/${TS}_consolidate.log"; exit 1; }
  echo "  ✓ consolidated (see $LOG_DIR/${TS}_consolidate.log)"
fi

# --- burn cyphers now (work is consolidated; minimise idle) ---
burn_cyphers || true

# WSG set across all hosts.
ALL_WSGS=$( { echo "$DISP_BUCKET" | tr ',' '\n'
  for WS in "${CY_WS_ARR[@]}"; do echo "${CY_BUCKET[$WS]}" | tr ',' '\n'; done
} | grep -v '^$' | sort -u | paste -sd, - )
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
echo "=== post-consolidate recompute (lnk_access, all WSGs) ==="
( cd "$REPO_ROOT"
  for w in $(echo "$ALL_WSGS" | tr ',' ' '); do
    LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R "$w" "$CONFIG" \
      || echo "[WARN] recompute WSG $w failed (continuing)"
  done ) > "$LOG_DIR/${TS}_recompute.log" 2>&1
echo "  ✓ recompute done"

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
echo "=== study_area_run done ==="
