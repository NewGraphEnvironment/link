# data-raw/study_area_finish.sh — finishing a run once its groups are on the
# dispatcher: which groups have rows from this run, the post-consolidate
# recompute over those, the compare, and the final report (link#348). Sourced
# by study_area_run.sh after study_area_hosts.sh, and by
# tests/testthat/test-study_area_finish.R. Sourcing defines functions only.
#
# The rule (link#348): one failed group does not cost the others their
# recompute. Coverage used to `exit 1` on the first run group with no
# <schema>.streams rows, before the recompute, so one failure left every other
# group's access computed against an incomplete barrier set. It also asked
# only "are there rows", so a failed group holding an EARLIER run's rows
# passed and was recomputed as if it were this run's.
#
# Now coverage splits the run's groups by what the dispatcher's database says
# about THIS run_uid, and the recompute and compare run over the groups whose
# rows a build of this run wrote. The rest are named at the end and the run
# exits non-zero; their rows, earlier or partial, are left as they are.
#
# Globals read: SCHEMA RUN_UID CONFIG TS LOG_DIR REPO_ROOT RECOMPUTE_JOBS
#   RUN_INCOMPLETE RECOMPUTE_FAIL RECOMPUTE_FAIL_STAGE (initialised by the
#   driver); with a default: KEPT_CAUSE_N RECOMPUTE_ONLY
# Functions read: .hosts_query host_finished .hosts_* (study_area_hosts.sh);
#   csv_count recompute_order run_recompute_pool (study_area_run.sh)
# Globals written: COV_STATE COV_RECOMPUTE COV_NOROWS COV_STALE COV_LOST
#   COV_MISSING RUN_WSGS ALL_WSGS COMPARE_CSV RUN_INCOMPLETE RECOMPUTE_FAIL
#   RECOMPUTE_FAIL_STAGE RECOMPUTE_RAN
#
# Needs bash >= 4, as the driver does.

# run_coverage <expected csv> [signals csv]: split the expected groups by what
# the dispatcher's database holds for this run.
#
#   COV_RECOMPUTE  rows in <schema>.streams, and finished this run: a log row
#                  for RUN_UID with date_end set, or a signal the driver
#                  passes (a host's `done` marker, a consolidated bucket).
#                  The log's date_end is a soft UPDATE that can fail
#                  (.lnk_log_run_finish), so signals only ever add.
#   COV_NOROWS     no rows at all.
#   COV_STALE      rows, but no finish signal of this run: an earlier run's
#                  rows, or this run's pre-persist of a build that then failed.
#   COV_LOST       finished this run, no rows here: consolidate lost them.
#
# Returns 1, with COV_STATE=unknown and every set empty, when the database
# does not answer or has no <schema>.streams (strict, as the hosts are): an
# unknown must never read as "nothing has rows".
run_coverage() {
  local expected signals in rows closed fin
  expected=$(.hosts_union "${1:-}")
  signals="${2:-}"
  COV_STATE=unknown
  COV_RECOMPUTE=""; COV_NOROWS=""; COV_STALE=""; COV_LOST=""; COV_MISSING=""
  in=$(.hosts_lines "$expected" | sed "s/.*/'&'/" | paste -sd, -)
  rows=$(.hosts_query local streams "watershed_group_code IN (${in:-NULL})" 1) \
    || return 1
  closed=$(host_finished local) || return 1
  COV_STATE=known
  rows=$(printf '%s\n' "$rows" | .hosts_csv)
  fin=$(.hosts_union "$(printf '%s\n' "$closed" | .hosts_csv)" "$signals")
  fin=$(.hosts_inter "$fin" "$expected")
  COV_RECOMPUTE=$(.hosts_inter "$rows" "$fin")
  COV_LOST=$(.hosts_minus "$fin" "$rows")
  COV_STALE=$(.hosts_minus "$rows" "$fin")
  COV_NOROWS=$(.hosts_minus "$(.hosts_minus "$expected" "$rows")" "$COV_LOST")
  COV_MISSING=$(.hosts_union "$COV_NOROWS" "$COV_STALE" "$COV_LOST")
  echo "  $(.hosts_n "$COV_RECOMPUTE")/$(.hosts_n "$expected") run WSGs have rows from a build this run finished"
  [ -z "$COV_NOROWS" ] || echo "  ✗ no rows in $SCHEMA.streams: $COV_NOROWS"
  [ -z "$COV_STALE" ]  || echo "  ✗ rows NOT from a build this run finished (an earlier run's, or this run's partial build): $COV_STALE"
  [ -z "$COV_LOST" ]   || echo "  ✗ finished this run, but no rows in $SCHEMA.streams (lost at consolidate): $COV_LOST"
  return 0
}

# run_expected_from_log: the groups with ANY <schema>.log row for RUN_UID on
# the dispatcher, open or closed, as CSV. The --recompute-only expected set
# when --wsgs= is not given. A group that failed on a cloud host and was never
# re-run here has no row here (consolidate copies finished groups only), so it
# cannot be seen this way. Strict: a missing log table returns 1.
run_expected_from_log() {
  local out
  out=$(.hosts_query local log "run_uid = '${RUN_UID}'" 1) || return 1
  printf '%s\n' "$out" | .hosts_csv
}

# run_finish <expected csv> [signals csv]: coverage, recompute, compare and the
# final report. EXITS the shell on an incomplete or failed run, as the driver
# always has, and returns 0 only for a complete one. Call it bare: under
# `set -e`, a function called in an `if` or `||` runs with errexit off.
run_finish() {
  RUN_WSGS=$(.hosts_union "${1:-}")
  local signals="${2:-}"
  COMPARE_CSV="$LOG_DIR/${TS}_compare.csv"

  # --- coverage post-condition (link#246, link#348) -------------------------
  # Detection rather than prevention: this fires whatever the cause. In a full
  # run it sits AFTER the burn so a failure cannot leak spend, and BEFORE the
  # recompute so the recompute covers only what this run built.
  #
  # Necessary because schema_consolidate DELETEs the destination bucket from
  # every persist table (its step 3.5) and then COPYs (step 4). A source that
  # produced nothing therefore removes the destination's prior rows for those
  # WSGs and still returns ok = TRUE (COV_LOST). The log tables keep their
  # rows (#354), so rows are read from streams and finishing from the log.
  #
  # A gap no longer exits here (link#348): it would take every other group's
  # recompute with it. It is named at the end, with an exit status to match.
  echo "=== verify WSG coverage in $SCHEMA (run_uid $RUN_UID) ==="
  if ! run_coverage "$RUN_WSGS" "$signals"; then
    echo "FATAL: could not verify WSG coverage in $SCHEMA"; exit 1
  fi
  if [ -n "$COV_MISSING" ]; then
    RUN_INCOMPLETE=1
    echo "  NOTE: recomputing only the $(.hosts_n "$COV_RECOMPUTE") WSGs above; the rest keep"
    echo "        whatever rows they hold, and the run will exit non-zero."
  fi
  ALL_WSGS="$COV_RECOMPUTE"

  if [ -z "$ALL_WSGS" ]; then
    echo "=== post-consolidate recompute: SKIPPED ==="
    echo "  No run group has rows from a build this run finished, so there is"
    echo "  nothing the recompute could settle and nothing valid to compare."
  else
    run_finish_recompute
    run_finish_compare
  fi
  run_finish_report
}

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
# this run built unconditionally rather than threshold-filtering by parity —
# bucketing is now a speed knob, not a correctness lever.
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
run_finish_recompute() {
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
    # Its OWN stage token. Reusing "views" made the final gate print "the barrier
    # views could not be built" and point at ${TS}_recompute_views.log -- a file
    # the views step never wrote, because it is gated on RECOMPUTE_FAIL=0 and
    # never ran. Two prep steps, two names, two pieces of evidence.
    RECOMPUTE_FAIL_STAGE="logtables"
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
    # Read by the kept-hosts report: whether a recovery must recompute only the
    # kept groups and those upstream, or every group of the run (link#347).
    RECOMPUTE_RAN=1

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
}

# --- compare (tunnel-free) -> CSV ---
# Over the recomputed groups only: a group this run did not build has nothing
# of this run's to compare (link#348).
run_finish_compare() {
  echo "=== compare (tunnel-free) ==="
  ( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_compare.R \
      "$COMPARE_CSV" "$ALL_WSGS" "$CONFIG" ) > "$LOG_DIR/${TS}_compare.log" 2>&1 \
    || { echo "  ✗ compare failed; see $LOG_DIR/${TS}_compare.log"; exit 1; }
  echo "  ✓ compare CSV: $COMPARE_CSV"
}

run_finish_report() {
  echo "=== summary ==="
  echo "  run WSGs:        ${RUN_WSGS:-<none>}"
  echo "  recomputed WSGs: ${ALL_WSGS:-<none>}"
  if [ -n "$ALL_WSGS" ]; then
    echo "  compare CSV: $COMPARE_CSV"
    tail -40 "$LOG_DIR/${TS}_compare.log" || true
  fi

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
  # A third cause (link#347): a cypher still up because it may hold work that
  # was not consolidated, or whose burn did not complete. --keep-cyphers alone is
  # a choice, not a failure; a host it keeps that is ALSO held for cause still
  # counts, so the flag cannot turn an unconsolidated host into an exit 0.
  local hosts_kept=0
  [ "${KEPT_CAUSE_N:-0}" -gt 0 ] && hosts_kept=1
  if [ "${RUN_INCOMPLETE:-0}" != "0" ] || [ "${RECOMPUTE_FAIL:-0}" != "0" ] \
     || [ "$hosts_kept" != "0" ]; then
    echo "=== study_area_run INCOMPLETE ==="
    if [ "$hosts_kept" != "0" ]; then
      echo "  $KEPT_CAUSE_N cypher(s) were NOT burned for cause: each may hold groups"
      echo "  that are not on the dispatcher, and is still running and billed."
      echo "  Consolidate only each host's groups column, and only where"
      echo "  groups_measured = yes; never groups_partial (consolidating a group the"
      echo "  host no longer holds, or holds in part, deletes the dispatcher's copy)."
      if [ "${RECOMPUTE_RAN:-0}" = "1" ]; then
        echo "  The recompute above ran WITHOUT those groups, so recompute each one and"
        echo "  each run group upstream of it afterwards. Then burn the host."
      else
        echo "  The recompute did not run, so recompute every group of the run"
        echo "  afterwards. Then burn the host."
      fi
      echo "  Hosts, reasons and commands: $LOG_DIR/${TS}_kept_hosts.tsv"
    fi
    if [ "${RUN_INCOMPLETE:-0}" != "0" ]; then
      if [ -n "${COV_MISSING:-}" ]; then
        echo "  These run WSGs have no rows from a build this run finished, so they"
        echo "  were NOT recomputed or compared: $COV_MISSING"
        [ -z "${COV_NOROWS:-}" ] || echo "    no rows:                         $COV_NOROWS"
        [ -z "${COV_STALE:-}" ]  || echo "    an earlier run's or partial rows: $COV_STALE"
        [ -z "${COV_LOST:-}" ]   || echo "    lost at consolidate:             $COV_LOST"
        echo "  The recompute above ran without them. Re-model each under this run_uid,"
        echo "  then recompute the whole run (every group, since a re-modelled group's"
        echo "  barriers change access upstream of it):"
        echo "    LNK_RUN_UID=$RUN_UID LNK_SCHEMA=$SCHEMA LNK_LOAD=loadall \\"
        echo "      Rscript data-raw/wsg_run_one.R <WSG> $CONFIG"
        echo "    bash data-raw/study_area_run.sh --recompute-only --run-uid=$RUN_UID \\"
        echo "      --config=$CONFIG --schema=$SCHEMA --wsgs=$RUN_WSGS"
      else
        echo "  At least one host did not account for its whole bucket; only the"
        echo "  WSGs it finished were consolidated. Artifacts above are valid for"
        echo "  those WSGs. Re-run the missing ones before trusting the compare."
      fi
    fi
    if [ "${RECOMPUTE_FAIL:-0}" != "0" ]; then
      echo "  The post-consolidate recompute did not complete for every WSG."
      echo "  Those WSGs' streams_access / streams_mapping_code still hold their"
      echo "  PRE-consolidate values, so cross-WSG access — hence token1/token2"
      echo "  and ;DAM — is WRONG for them. This is bad output, not missing"
      echo "  output: the compare CSV above will look complete."
      if [ "${RECOMPUTE_FAIL_STAGE:-pool}" = "logtables" ]; then
        echo "  The provenance log tables could not be created, so NO WSG was"
        echo "  recomputed. See $LOG_DIR/${TS}_recompute_logtables.log."
      elif [ "${RECOMPUTE_FAIL_STAGE:-pool}" = "views" ]; then
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
}
