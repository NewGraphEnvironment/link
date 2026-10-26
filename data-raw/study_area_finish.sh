# data-raw/study_area_finish.sh — finishing a run once its groups are on the
# dispatcher: which groups have rows from this run, the post-consolidate
# recompute over those, the compare, and the final report (link#348). Sourced
# by study_area_run.sh after study_area_hosts.sh, and by
# tests/testthat/test-study_area_finish.R. Sourcing defines functions and
# declares HOST_BUCKET_DONE (re-declaring keeps its contents), nothing else.
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
#   driver); with a default: KEPT_CAUSE_N RUN_LABEL KEPT_TSV_GROUPS; run_expected_from_hosts
#   also reads DISP_BUCKET HOST_ARR HOST_BUCKET HOST_BUCKET_DONE ACC_FINISHED
#   ACC_DONE_LOG ACC_SKIP; run_wsgs_write reads DISP_BUCKET HOST_ARR
#   HOST_BUCKET ACC_SKIP
# Functions read: .hosts_query host_finished .hosts_* (study_area_hosts.sh);
#   csv_count recompute_order run_recompute_pool (study_area_run.sh);
#   phase_begin phase_end phase_skip phases_report (study_area_phases.sh),
#   which write the coverage, views, recompute and compare rows (link#375)
# Globals written: COV_STATE COV_RECOMPUTE COV_NOROWS COV_STALE COV_LOST
#   COV_UNCONS COV_MISSING RUN_WSGS ALL_WSGS COMPARE_CSV COMPARE_FAIL RUN_INCOMPLETE
#   RECOMPUTE_FAIL RECOMPUTE_FAIL_STAGE RECOMPUTE_RAN; run_expected_from_hosts
#   writes RUN_EXPECT RUN_SIGNALS RUN_SKIP; consolidate_outcomes writes
#   CONS_FAILED CONS_EXCLUDED HOST_CONS_FAIL (declared in study_area_hosts.sh);
#   consolidate_state_write reads HOST_ARR HOST_BUCKET_DONE HOST_CONS_FAIL
#   HOST_CONS_STATE HOST_CONS_UTC;
#   run_expected_recompute_only writes RO_EXPECT RO_EXCLUDED; run_timeouts
#   writes TIMED_OUT TIMEOUT_LINES RUN_BOUND
#
# Needs bash >= 4, as the driver does.

declare -A HOST_BUCKET_DONE HOST_CONS_STATE HOST_CONS_UTC

# run_expected_from_hosts: what a full run expects, and what it already knows
# finished, from the per-host accounting (study_area_hosts.sh). Sets:
#   RUN_EXPECT   every host's bucket, less RUN_SKIP;
#   RUN_SKIP     groups a host SKIPped (no modelled species: wsg_run_one.R
#                writes no row for them) and no host finished. Buckets come
#                from the same species filter, so one here means a host's
#                config or overrides disagree with the dispatcher's: a WARN;
#   RUN_SIGNALS  finish signals beyond the dispatcher's log rows: its `done`
#                markers and each cypher's consolidated bucket (database ∪
#                log done), which is what consolidate took. They only add. A
#                cypher whose consolidate failed (HOST_CONS_FAIL) adds nothing:
#                consolidate did not take its bucket (link#358). It still
#                finished those groups, so they are never RUN_SKIP: they stay
#                expected, and coverage classes them not_consolidated.
run_expected_from_hosts() {
  local ws all skip finished
  all="${DISP_BUCKET:-}"
  skip="${ACC_SKIP[dispatcher]:-}"
  RUN_SIGNALS=$(.hosts_union "${ACC_FINISHED[dispatcher]:-}" "${ACC_DONE_LOG[dispatcher]:-}")
  finished="$RUN_SIGNALS"
  for ws in "${HOST_ARR[@]}"; do
    all=$(.hosts_union "$all" "${HOST_BUCKET[$ws]:-}")
    skip=$(.hosts_union "$skip" "${ACC_SKIP[$ws]:-}")
    finished=$(.hosts_union "$finished" "${HOST_BUCKET_DONE[$ws]:-}")
    [ -n "${HOST_CONS_FAIL[$ws]:-}" ] || \
      RUN_SIGNALS=$(.hosts_union "$RUN_SIGNALS" "${HOST_BUCKET_DONE[$ws]:-}")
  done
  RUN_SKIP=$(.hosts_minus "$skip" "$finished")
  RUN_EXPECT=$(.hosts_minus "$all" "$RUN_SKIP")
  [ -z "$RUN_SKIP" ] || \
    echo "  WARN: SKIPped by a host (no modelled species) though its bucket expected them; not expected to have rows: $RUN_SKIP"
  return 0
}

# run_wsgs_write <path>: the run's groups, one row per group and host it was
# dispatched to (wsg, host, skip, run_uid), so a run that stops before its
# tail still says what it was running (link#358). The driver writes it as soon
# as the buckets resolve, with skip `unknown`, and again after the per-host
# accounting, with `yes` / `no` for each host whose accounting ran (ACC_SKIP
# set for that key). `--recompute-only` reads it back through
# run_expected_from_file. Written to a temp file and moved, so a driver killed
# mid-write leaves the previous copy whole.
run_wsgs_write() {
  local path="$1" ws w
  # bucket_mode (link#361): closure (each --focal= expanded to its drainage
  # closure) or exact (--buckets-exact). The same for every row of a run.
  local mode="${BUCKET_MODE:-closure}"
  {
    printf 'wsg\thost\tskip\trun_uid\tbucket_mode\n'
    for w in $(.hosts_lines "${DISP_BUCKET:-}"); do
      printf '%s\t%s\t%s\t%s\t%s\n' "$w" dispatcher "$(.run_wsgs_skip dispatcher "$w")" "$RUN_UID" "$mode"
    done
    for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
      for w in $(.hosts_lines "${HOST_BUCKET[$ws]:-}"); do
        printf '%s\t%s\t%s\t%s\t%s\n' "$w" "$ws" "$(.run_wsgs_skip "$ws" "$w")" "$RUN_UID" "$mode"
      done
    done
  } > "$path.tmp" && mv "$path.tmp" "$path"
}

# .run_wsgs_skip <host key> <wsg>: yes / no once that host's accounting ran,
# unknown before. `case`, not `grep -q`: under pipefail an early-exiting grep
# can SIGPIPE its writer and turn a match into "no".
.run_wsgs_skip() {
  if [ -z "${ACC_SKIP[$1]+x}" ]; then
    echo unknown
  else
    case ",${ACC_SKIP[$1]}," in *",$2,"*) echo yes ;; *) echo no ;; esac
  fi
}

# run_expected_from_file <path>: the groups a run_wsgs.tsv names, less those
# SKIPped on every host that ran them, as CSV on stdout. Returns 2 when the
# file does not exist (a run before link#358), and 1, saying why on stderr,
# when its header is not run_wsgs_write's, a row names another run_uid, or a
# group is not a four-letter code (the codes reach SQL in run_coverage).
run_expected_from_file() {
  local path="$1" hdr out
  [ -f "$path" ] || return 2
  IFS= read -r hdr < "$path" || hdr=""
  # Two headers: the four columns of link#358, and bucket_mode appended by
  # link#361. Both carry wsg, host, skip, run_uid in the same positions.
  case "$hdr" in
    "$(printf 'wsg\thost\tskip\trun_uid')"|"$(printf 'wsg\thost\tskip\trun_uid\tbucket_mode')") ;;
    *) echo "  ✗ $path: not a run_wsgs.tsv (header '$hdr')" >&2; return 1 ;;
  esac
  out=$(awk -F'\t' -v u="$RUN_UID" '
    NR == 1 { next }
    $4 != u { print "  ✗ " FILENAME ": row " NR " names another run_uid (" $4 ")" > "/dev/stderr"; bad = 1 }
    $1 !~ /^[A-Z][A-Z][A-Z][A-Z]$/ { print "  ✗ " FILENAME ": row " NR " is not a group code (" $1 ")" > "/dev/stderr"; bad = 1 }
    $3 != "yes" { keep[$1] = 1 }
    END { if (bad) exit 1; for (k in keep) print k }' "$path") || return 1
  printf '%s\n' "$out" | .hosts_csv
}

# consolidate_outcomes <tsv>: read schema_consolidate's per-source outcomes
# (host, ok, stage, groups; the driver writes them from its result) and decide
# what a run carries past (link#358). schema_consolidate loops past a source it
# refuses or fails on, so the other sources ARE on the dispatcher; one refused
# source (dest_log_newer, which a single group can trigger) used to end the run
# before coverage and the recompute. For each source that is not ok:
#   HOST_CONS_FAIL[ws]  the stage, which host_release names when it keeps the host
#                     and run_expected_from_hosts reads to drop its signals;
#   CONS_FAILED       the workspaces, space-separated;
#   CONS_EXCLUDED     their consolidated buckets, which run_finish keeps out of
#                     the recompute whatever the dispatcher's log says: a failure
#                     after the DELETE can leave log rows copied and streams not.
# A source is a workspace with a non-empty HOST_BUCKET_DONE (the driver skips the
# others), matched to its row by host (its ssh target, HOST_SSH). Returns 1, naming what is
# missing, when the file is absent or a source has no row: then nothing says
# which hosts landed, and the caller must not carry on.
#
# With a workspace, reads that one source and adds to CONS_FAILED and
# CONS_EXCLUDED rather than resetting them: the driver consolidates each host
# when its own leg ends, one call per host (link#369).
consolidate_outcomes() {
  local tsv="$1" only="${2:-}" ws row ok stage groups missing=""
  [ -n "$only" ] || { CONS_FAILED=""; CONS_EXCLUDED=""; }
  [ -r "$tsv" ] || { echo "  ✗ no consolidate outcomes at $tsv"; return 1; }
  for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
    [ -z "$only" ] || [ "$ws" = "$only" ] || continue
    [ -n "${HOST_BUCKET_DONE[$ws]:-}" ] || continue
    row=$(awk -F'\t' -v h="${HOST_SSH[$ws]:-}" 'NR > 1 && $1 == h { print; exit }' "$tsv")
    if [ -z "$row" ]; then
      missing="$missing $(.hosts_label "$ws")"
      continue
    fi
    IFS=$'\t' read -r _ ok stage groups <<< "$row"
    [ "$ok" = "TRUE" ] && continue
    HOST_CONS_FAIL[$ws]="${stage:-unknown}"
    CONS_FAILED="${CONS_FAILED:+$CONS_FAILED }$ws"
    CONS_EXCLUDED=$(.hosts_union "$CONS_EXCLUDED" "${HOST_BUCKET_DONE[$ws]}")
    echo "  ✗ $(.hosts_label "$ws"): consolidate failed at stage ${HOST_CONS_FAIL[$ws]}; its bucket is not consolidated: ${HOST_BUCKET_DONE[$ws]}"
    [ "${HOST_CONS_FAIL[$ws]}" != "dest_log_newer" ] || \
      echo "    the dispatcher's newest log row is not this host's for: ${groups:-?} (nothing was deleted or copied)"
  done
  if [ -n "$missing" ]; then
    echo "  ✗ $tsv has no outcome for:$missing"
    return 1
  fi
  return 0
}

# consolidate_state_write <path> [state]: one row per group consolidate is
# asked to take (wsg, workspace, state, run_uid, state_utc), so a
# --recompute-only knows which groups may sit half-copied on the dispatcher
# (link#358). Written `in_flight` BEFORE a copy and rewritten once it has an
# outcome, with `ok`, or `failed:<stage>` for a source in HOST_CONS_FAIL. If a
# consolidate dies with no outcome, its `in_flight` rows stay, so the record
# fails closed: absence of a failure is never inferred from a file that was
# written only after the risky step. Temp file + mv.
#
# Without <state>, each host's own state (HOST_CONS_STATE, and HOST_CONS_UTC for
# state_utc): the driver consolidates each host when its own leg ends
# (link#369), so hosts sit in different states, and a host not yet
# consolidated has no rows. A host whose consolidate ended with no outcome
# (HOST_CONS_FAIL no_outcome) stays in_flight. With <state>, every source in it,
# as before.
consolidate_state_write() {
  local path="$1" state="${2:-}" ws w st
  {
    printf 'wsg\tworkspace\tstate\trun_uid\tstate_utc\n'
    for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
      st="${state:-${HOST_CONS_STATE[$ws]:-}}"
      [ -n "$st" ] || continue
      [ -z "${HOST_CONS_FAIL[$ws]:-}" ] || [ "${HOST_CONS_FAIL[$ws]}" = "no_outcome" ] \
        || st="failed:${HOST_CONS_FAIL[$ws]}"
      for w in $(.hosts_lines "${HOST_BUCKET_DONE[$ws]:-}"); do
        printf '%s\t%s\t%s\t%s\t%s\n' "$w" "$ws" "$st" "$RUN_UID" "${HOST_CONS_UTC[$ws]:-}"
      done
    done
  } > "$path.tmp" && mv "$path.tmp" "$path"
}

# run_unconsolidated_from_state <path>: the groups a consolidate state record
# names in any state but `ok`, as CSV. Returns 2 when the file does not exist
# (the run never reached consolidate, had no cyphers, or predates #358: in each
# case consolidate wrote nothing to the dispatcher), and 1, saying why on
# stderr, for a bad header, another run_uid, or a value that is not a group
# code.
run_unconsolidated_from_state() {
  local path="$1" hdr out
  [ -f "$path" ] || return 2
  IFS= read -r hdr < "$path" || hdr=""
  # Two headers: link#358's four columns, and state_utc appended by link#369.
  case "$hdr" in
    "$(printf 'wsg\tworkspace\tstate\trun_uid')"|"$(printf 'wsg\tworkspace\tstate\trun_uid\tstate_utc')") ;;
    *) echo "  ✗ $path: not a consolidate state record (header '$hdr')" >&2; return 1 ;;
  esac
  out=$(awk -F'\t' -v u="$RUN_UID" '
    NR == 1 { next }
    $4 != u { print "  ✗ " FILENAME ": row " NR " names another run_uid (" $4 ")" > "/dev/stderr"; bad = 1 }
    $1 !~ /^[A-Z][A-Z][A-Z][A-Z]$/ { print "  ✗ " FILENAME ": row " NR " is not a group code (" $1 ")" > "/dev/stderr"; bad = 1 }
    $3 != "ok" { print $1 }
    END { if (bad) exit 1 }' "$path") || return 1
  printf '%s\n' "$out" | .hosts_csv
}

# run_config_check: the run's log rows on the dispatcher name exactly one
# config, and it is $CONFIG. --recompute-only with a forgotten --config would
# otherwise recompute every group under another bundle and stamp the rows with
# the run's uid. Returns 1, saying why, otherwise.
run_config_check() {
  local out
  out=$(PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg \
    -X -q -t -A -v ON_ERROR_STOP=1 -c "
    SELECT coalesce(string_agg(DISTINCT coalesce(config_name, '<none>'), ','
                               ORDER BY coalesce(config_name, '<none>')), '')
    FROM ${SCHEMA}.log WHERE run_uid = '${RUN_UID}'" 2>/dev/null) || {
    echo "  ✗ could not read config_name from $SCHEMA.log"; return 1; }
  if [ "$out" = "$CONFIG" ]; then
    echo "  ✓ run_uid $RUN_UID was built with --config=$CONFIG"
    return 0
  fi
  echo "  ✗ run_uid $RUN_UID was built with config '${out:-<no log rows>}', not --config=$CONFIG"
  return 1
}

# run_coverage <expected csv> [signals csv] [excluded csv]: split the expected
# groups by what the dispatcher's database holds for this run.
#
#   COV_RECOMPUTE  rows in <schema>.streams, and finished this run: the
#                  group's NEWEST log row (max date_start, the rule
#                  schema_consolidate.R uses for which build the persist rows
#                  hold) is RUN_UID's and has date_end set, or the driver
#                  passes a signal (a host's `done` marker, a consolidated
#                  bucket). The log's date_end is a soft UPDATE that can fail
#                  (.lnk_log_run_finish), so signals only ever add. Newest,
#                  not any: a group a later run rebuilt, or a hand re-run under
#                  this uid that failed after its pre-persist, holds rows that
#                  are not this run's finished build.
#   COV_NOROWS     no rows at all.
#   COV_STALE      rows, but no finish signal of this run: an earlier run's
#                  rows, or this run's pre-persist of a build that then failed.
#   COV_LOST       finished this run, no rows here: consolidate lost them.
#   COV_UNCONS     the excluded groups: in the bucket of a source consolidate
#                  refused or failed on (consolidate_outcomes). Taken out of
#                  every class above, whatever rows or log they have here.
#
# Returns 1, with COV_STATE=unknown and every set empty, when the database
# does not answer or has no <schema>.streams (strict, as the hosts are): an
# unknown must never read as "nothing has rows".
run_coverage() {
  local expected signals excluded in rows closed fin
  expected=$(.hosts_union "${1:-}")
  signals="${2:-}"
  COV_STATE=unknown
  COV_RECOMPUTE=""; COV_NOROWS=""; COV_STALE=""; COV_LOST=""; COV_UNCONS=""; COV_MISSING=""
  # Every excluded group is expected: run_finish already adds them to
  # RUN_WSGS, and an intersection here would drop one only the exclusion
  # names (the round-2 shape, #358).
  excluded=$(.hosts_union "${3:-}")
  expected=$(.hosts_union "$expected" "$excluded")
  in=$(.hosts_lines "$expected" | sed "s/.*/'&'/" | paste -sd, -)
  rows=$(.hosts_query local streams "watershed_group_code IN (${in:-NULL})" 1) \
    || return 1
  closed=$(.hosts_query local log "run_uid = '${RUN_UID}' AND date_end IS NOT NULL
    AND (watershed_group_code, date_start) IN (
      SELECT watershed_group_code, max(date_start) FROM ${SCHEMA}.log
      GROUP BY watershed_group_code)") || return 1
  COV_STATE=known
  rows=$(printf '%s\n' "$rows" | .hosts_csv)
  fin=$(.hosts_union "$(printf '%s\n' "$closed" | .hosts_csv)" "$signals")
  fin=$(.hosts_inter "$fin" "$expected")
  COV_RECOMPUTE=$(.hosts_inter "$rows" "$fin")
  COV_LOST=$(.hosts_minus "$fin" "$rows")
  COV_STALE=$(.hosts_minus "$rows" "$fin")
  COV_NOROWS=$(.hosts_minus "$(.hosts_minus "$expected" "$rows")" "$COV_LOST")
  COV_UNCONS="$excluded"
  COV_RECOMPUTE=$(.hosts_minus "$COV_RECOMPUTE" "$excluded")
  COV_LOST=$(.hosts_minus "$COV_LOST" "$excluded")
  COV_STALE=$(.hosts_minus "$COV_STALE" "$excluded")
  COV_NOROWS=$(.hosts_minus "$COV_NOROWS" "$excluded")
  COV_MISSING=$(.hosts_union "$COV_NOROWS" "$COV_STALE" "$COV_LOST" "$COV_UNCONS")
  echo "  $(.hosts_n "$COV_RECOMPUTE")/$(.hosts_n "$expected") run WSGs have rows from a build this run finished"
  [ -z "$COV_NOROWS" ] || echo "  ✗ no rows in $SCHEMA.streams: $COV_NOROWS"
  [ -z "$COV_STALE" ]  || echo "  ✗ rows NOT from a build this run finished (an earlier run's, or this run's partial build): $COV_STALE"
  [ -z "$COV_LOST" ]   || echo "  ✗ finished this run, but no rows in $SCHEMA.streams (lost at consolidate): $COV_LOST"
  [ -z "$COV_UNCONS" ] || echo "  ✗ not consolidated (its host's consolidate failed): $COV_UNCONS"
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

# run_expected_recompute_only [--wsgs= csv]: the expected set of a
# --recompute-only, in RO_EXPECT. --wsgs= wins, with a WARN naming the run's
# groups it leaves out. Otherwise the run's own <TS>_run_wsgs.tsv (a run_uid's
# prefix is its TS) together with every group holding a log row for the
# run_uid, so a group that failed on a cloud host, or before its first log
# row, is still named (link#358). A run from before #358 has no such file and
# falls back to the log alone. Without --wsgs=, RO_EXCLUDED holds every group
# the run's <TS>_consolidate_state.tsv names in a state other than `ok`: its
# host's consolidate failed or never finished, possibly after the DELETE, so
# the dispatcher may hold part of a bucket under a closed log row, and nothing
# here can tell whether the kept host was settled since. They are expected
# (named), but kept out of the recompute until --wsgs= names them, which is
# the operator's word that they were. Returns 1, saying why, when the log
# cannot be read, when either file is not this run's (fatal only without
# --wsgs=), or when the set is empty. Prints only; never exits.
run_expected_recompute_only() {
  local wsgs="${1:-}" logged file from_file="" rc=0 left state
  RO_EXCLUDED=""
  logged=$(run_expected_from_log) || { echo "FATAL: could not read $SCHEMA.log"; return 1; }
  file="$LOG_DIR/${RUN_UID%-*}_run_wsgs.tsv"
  from_file=$(run_expected_from_file "$file") || rc=$?
  if [ "$rc" != "0" ] && [ "$rc" != "2" ]; then
    if [ -z "$wsgs" ]; then
      echo "FATAL: $file is not this run's record of its groups (above); pass --wsgs="
      return 1
    fi
    echo "  WARN: ignoring $file (above); --wsgs= gives the groups"
    from_file=""
  fi
  if [ -n "$wsgs" ]; then
    RO_EXPECT=$(.hosts_union "$wsgs")
    echo "  expected WSGs: $(.hosts_n "$RO_EXPECT"), from --wsgs="
    # A subset leaves the groups upstream of a re-modelled one on access
    # computed before its barriers changed.
    left=$(.hosts_minus "$(.hosts_union "$logged" "$from_file")" "$RO_EXPECT")
    [ -z "$left" ] || {
      echo "  WARN: --wsgs= leaves out $(.hosts_n "$left") group(s) of this run_uid (log rows or run_wsgs.tsv);"
      echo "        those upstream of a re-modelled group keep stale access: $left"; }
  elif [ "$rc" = "0" ]; then
    RO_EXPECT=$(.hosts_union "$from_file" "$logged")
    echo "  expected WSGs: $(.hosts_n "$RO_EXPECT"): the $(.hosts_n "$from_file") in $file"
    left=$(.hosts_minus "$logged" "$from_file")
    [ -z "$left" ] || \
      echo "    and $(.hosts_n "$left") more with a $SCHEMA.log row for this run_uid: $left"
  else
    RO_EXPECT="$logged"
    echo "  expected WSGs: the $(.hosts_n "$RO_EXPECT") with a $SCHEMA.log row for this run_uid"
    echo "  (no $file: a run before link#358). A group that failed on a cloud host"
    echo "  and was not re-run here has no row here; pass the run's groups with --wsgs= to have it named."
  fi
  [ -n "$RO_EXPECT" ] || {
    echo "FATAL: no group recorded for run_uid $RUN_UID, and no --wsgs=: nothing to recompute"
    return 1; }
  [ -z "$wsgs" ] || return 0
  state="$LOG_DIR/${RUN_UID%-*}_consolidate_state.tsv"
  rc=0
  RO_EXCLUDED=$(run_unconsolidated_from_state "$state") || rc=$?
  case "$rc" in
    0) ;;
    2) RO_EXCLUDED="" ;;
    *) echo "FATAL: $state is not this run's consolidate record (above); pass --wsgs="
       RO_EXCLUDED=""; return 1 ;;
  esac
  # A union: a failed host can have finished a group outside its bucket,
  # which neither the log nor run_wsgs.tsv then names.
  RO_EXPECT=$(.hosts_union "$RO_EXPECT" "$RO_EXCLUDED")
  [ -z "$RO_EXCLUDED" ] || {
    echo "  WARN: the run did not consolidate these from their host (failed, or never finished);"
    echo "        kept out of the recompute until settled per its kept_hosts.tsv and named"
    echo "        with --wsgs=: $RO_EXCLUDED"; }
  return 0
}

# run_timeouts <groups csv>: which of these groups had a modelling statement
# cancelled by the statement bound (link#371), from the run's host logs. Each
# group's wsg_run_one.R writes `[wsg_run_one] <WSG> statement_timeout=<bound>`
# and, when cancelled, `[wsg_run_one] <WSG> TIMEOUT after <bound>: <statement>`;
# every host's output lands in $LOG_DIR/<ts>_run_<host>.log, where <ts> is the
# run_uid's timestamp: TS in a full run, an earlier one under --recompute-only.
# Matched unanchored, since an R warning flushed without a newline can put the
# marker mid-line (link#347), and byte-wise (LC_ALL=C): a log cut mid-glyph by
# a dropped session holds bytes macOS sed refuses in a UTF-8 locale. Never
# fatal, under the driver's set -e: it only adds lines to the report. Only
# groups in the argument are named, so a group re-modelled since its timeout is
# not; a group that hit it twice keeps its last line. Sets:
#   TIMED_OUT      the groups, sorted, comma-separated;
#   TIMEOUT_LINES  one `<WSG> (bound <bound>): <statement>` line per group;
#   RUN_BOUND      the run's bound as its groups reported it (Postgres text, which
#                  PGOPTIONS accepts back: 30min, 2h), or "" when no log says.
#                  Only a whole value with its unit counts: a line cut after
#                  `=30` would print a 30 ms bound (code-check round 3).
run_timeouts() {
  local want="${1:-}" logs
  TIMED_OUT=""; TIMEOUT_LINES=""; RUN_BOUND=""
  logs=$(find "$LOG_DIR" -maxdepth 1 -name "${RUN_UID%-*}_run_*.log" 2>/dev/null | sort) || logs=""
  [ -n "$logs" ] || return 0
  RUN_BOUND=$(printf '%s\n' "$logs" | while IFS= read -r f; do cat "$f" 2>/dev/null || true; done \
    | LC_ALL=C sed -nE 's/.*\[wsg_run_one\] [A-Z]{4} statement_timeout=([0-9]+(ms|s|min|h|d))([^0-9a-z].*)?$/\1/p' \
    | LC_ALL=C awk '$0 != "0" { b = $0 } END { print b }') || RUN_BOUND=""
  [ -n "$want" ] || return 0
  TIMEOUT_LINES=$(printf '%s\n' "$logs" | while IFS= read -r f; do cat "$f" 2>/dev/null || true; done \
    | LC_ALL=C sed -nE 's/.*\[wsg_run_one\] ([A-Z]{4}) TIMEOUT after ([^:]+): (.*)$/\1\t\2\t\3/p' \
    | LC_ALL=C awk -F'\t' -v want=",$want," 'index(want, "," $1 ",") { last[$1] = $1 " (bound " $2 "): " $3 }
        END { for (w in last) print last[w] }' | LC_ALL=C sort) || TIMEOUT_LINES=""
  TIMED_OUT=$(printf '%s\n' "$TIMEOUT_LINES" | LC_ALL=C sed -nE 's/^([A-Z]{4}) .*/\1/p' | paste -sd, -) \
    || TIMED_OUT=""
}

# run_finish <expected csv> [signals csv] [excluded csv]: coverage, recompute,
# compare and the final report. The excluded groups are a failed consolidate
# source's (consolidate_outcomes): never recomputed, named as not consolidated,
# and part of the run's groups even when the host finished one outside its
# bucket. EXITS the shell on an incomplete or failed run, as the driver
# always has, and returns 0 only for a complete one. Call it bare: under
# `set -e`, a function called in an `if` or `||` runs with errexit off.
run_finish() {
  RUN_WSGS=$(.hosts_union "${1:-}" "${3:-}")
  local signals="${2:-}" excluded="${3:-}" w
  COMPARE_CSV="$LOG_DIR/${TS}_compare.csv"
  COMPARE_FAIL=0

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
  phase_begin coverage
  if ! run_coverage "$RUN_WSGS" "$signals" "$excluded"; then
    echo "FATAL: could not verify WSG coverage in $SCHEMA"; exit 1
  fi
  # One row per run group and its class: the compare CSV covers only the
  # first class, so this is what says what it leaves out.
  {
    printf 'wsg\tclass\n'
    for w in $(.hosts_lines "$COV_RECOMPUTE"); do printf '%s\trecompute\n' "$w"; done
    for w in $(.hosts_lines "$COV_NOROWS"); do printf '%s\tno_rows\n' "$w"; done
    for w in $(.hosts_lines "$COV_STALE"); do printf '%s\tnot_this_run\n' "$w"; done
    for w in $(.hosts_lines "$COV_LOST"); do printf '%s\tlost_at_consolidate\n' "$w"; done
    for w in $(.hosts_lines "$COV_UNCONS"); do printf '%s\tnot_consolidated\n' "$w"; done
  } > "$LOG_DIR/${TS}_coverage.tsv"
  echo "  classes: $LOG_DIR/${TS}_coverage.tsv"
  if [ -n "$COV_MISSING" ]; then
    RUN_INCOMPLETE=1
    echo "  NOTE: recomputing only the $(.hosts_n "$COV_RECOMPUTE") WSGs above; the rest keep"
    echo "        whatever rows they hold, and the run will exit non-zero."
  fi
  phase_end coverage "" "$(.hosts_n "$RUN_WSGS")" "$([ -z "$COV_MISSING" ] && echo ok || echo failed)"
  ALL_WSGS="$COV_RECOMPUTE"

  if [ -z "$ALL_WSGS" ]; then
    # An early scheduler is told there is nothing left and waited for. Any
    # group it already started is not one coverage found finished.
    if [ -n "${RC_SCHED_PID:-}" ]; then
      recompute_final_write "" || touch "$RC_STOP" 2>/dev/null || true
      wait "$RC_SCHED_PID" || true
      RC_SCHED_PID=""
      if [ -s "$RC_DIR/launched.tsv" ]; then
        RUN_INCOMPLETE=1
        echo "  ✗ recomputed early but not found finished by coverage: $(cut -f1 "$RC_DIR/launched.tsv" | .hosts_csv)"
      fi
    fi
    echo "=== post-consolidate recompute: SKIPPED ==="
    echo "  No run group has rows from a build this run finished, so there is"
    echo "  nothing the recompute could settle and nothing valid to compare."
    phase_skip views; phase_skip recompute; phase_skip compare
  else
    run_finish_recompute
    run_finish_compare
  fi
  run_finish_report
}

# recompute_views_prep: the two single-threaded steps every recompute job
# relies on, once: the log tables and the schema's barrier views. Run before
# the pool at the end of a run, or before the legs when groups are recomputed
# early (link#374), where a view rebuild later would take an exclusive lock
# under running jobs. Sets RECOMPUTE_FAIL / RECOMPUTE_FAIL_STAGE on failure.
recompute_views_prep() {
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
  if [ -n "${RC_SCHED_PID:-}" ]; then
    # The log tables and views were prepared before the legs, and the
    # scheduler has been recomputing groups as they landed (link#374).
    run_finish_recompute_early
  else
    # views: the two single-threaded steps before the pool (link#375).
    phase_begin views
    recompute_views_prep
    phase_end views "" "" "$([ "$RECOMPUTE_FAIL" = "0" ] && echo ok || echo failed)"
    if [ "$RECOMPUTE_FAIL" != "0" ]; then
      phase_skip recompute
      return 0
    fi
    phase_begin recompute
    rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"
    # Longest-first. Ordering is the CALLER's business -- run_recompute_pool
    # consumes ALL_WSGS as given, which keeps it testable by pool_probe.sh and
    # lets recompute_parity.sh shuffle deliberately for its invariance pass.
    ALL_WSGS=$(recompute_order "$ALL_WSGS" | paste -sd, -)
    run_recompute_pool "$RECOMPUTE_JOBS"
  fi
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

  local judged=0
  if ( cd "$REPO_ROOT" && LNK_LOAD=loadall \
         Rscript data-raw/fanout_judge.R "$RC_TSV" "$ALL_WSGS" recompute ); then
    echo "  ✓ recompute: ${N_RECOMPUTE}/${N_RECOMPUTE} WSGs"
    judged=1
  else
    echo "  ✗ recompute incomplete; see $RECOMPUTE_LOG and $RC_DIR/"
    RECOMPUTE_FAIL_STAGE="pool"
    # Per-job logs KEPT on failure: the concatenation is the artifact, the
    # per-job files are what you actually grep.
    RECOMPUTE_FAIL=1
  fi
  # Early recompute (link#374): no group started before a group it reads had
  # landed, checked from the records (recompute_audit.R). An unreadable audit
  # fails closed: it is the only thing that says the early starts were right.
  if [ "${RC_EARLY_RAN:-0}" = "1" ]; then
    local arc=0
    ( cd "$REPO_ROOT" && Rscript data-raw/recompute_audit.R "$SCHEMA" "$RUN_UID" \
        "$RC_DEPS" "$RUN_WSGS_TSV" "$CONS_STATE" "$RC_DIR/launched.tsv" \
        "$LOG_DIR/${TS}_recompute_audit.tsv" "$RC_DIR/fallback.txt" ) \
      > "$LOG_DIR/${TS}_recompute_audit.log" 2>&1 || arc=$?
    case "$arc" in
      0) echo "  ✓ recompute audit: no group started before a group it reads had landed" ;;
      # Its own verdict, beside the pool's stage: both can fail, and each
      # has its own remedy.
      1) echo "  ✗ recompute audit: a group started before a group it reads had landed; see $LOG_DIR/${TS}_recompute_audit.log"
         RECOMPUTE_FAIL=1; RC_AUDIT="early" ;;
      *) echo "  ✗ recompute audit could not run (exit $arc); see $LOG_DIR/${TS}_recompute_audit.log"
         RECOMPUTE_FAIL=1; RC_AUDIT="unread" ;;
    esac
  fi
  # The per-job directory goes only after the audit has read the scheduler's
  # launch record in it, and only when everything passed.
  if [ "$judged" = "1" ] && [ "$RECOMPUTE_FAIL" = "0" ]; then rm -rf "$RC_DIR"; fi
  phase_end recompute "" "$N_RECOMPUTE" "$([ "$RECOMPUTE_FAIL" = "0" ] && echo ok || echo failed)"
}

# run_finish_recompute_early: the end of an early recompute (link#374). Hands
# the scheduler the final set (the groups coverage found finished), which it
# starts whether or not they read a group that never landed, as the end-of-run
# pool always has; then waits for it. A scheduler that ended any other way
# (stopped, orphaned, a bad final file) leaves the groups it did not start to
# the pool here, so a dead scheduler costs time, never a group. The recompute
# row starts at the first early launch.
run_finish_recompute_early() {
  local first src done_rc left saved n_early
  first=$(awk -F'\t' 'NR == 1 { print $2; exit }' "$RC_DIR/launched.tsv" 2>/dev/null) || first=""
  phase_begin recompute "" "$first"
  recompute_final_write "$ALL_WSGS" \
    || { echo "  WARN: could not write $RC_FINAL; stopping the scheduler"; touch "$RC_STOP" 2>/dev/null || true; }
  src=0
  wait "$RC_SCHED_PID" || src=$?
  RC_SCHED_PID=""
  RC_EARLY_RAN=1
  # Kept beside the run's other records: the per-job directory goes on success.
  cp "$RC_DIR/launched.tsv" "$LOG_DIR/${TS}_recompute_launched.tsv" 2>/dev/null || true
  # Guarded: launched.tsv is missing when the scheduler died at its first
  # step, the case the fallback below is for, and errexit is on here.
  n_early=$(awk -F'\t' '$3 == "early"' "$RC_DIR/launched.tsv" 2>/dev/null | wc -l | tr -d ' ') || n_early=0
  echo "  ${n_early:-0} of $N_RECOMPUTE group(s) recomputed while the legs ran (see $LOG_DIR/${TS}_recompute_scheduler.log)"
  if [ "$src" != "0" ]; then
    # A job the scheduler started may outlive it (it waits for its jobs on
    # every path it takes itself, not when it is killed). Two jobs on one group
    # collide on its scratch tables and both run the one-way gate, so wait for
    # each launched job that has not reported before deciding what is left.
    local w pid
    while IFS=$'\t' read -r w _ _ pid; do
      [ -n "${pid:-}" ] && [ ! -e "$RC_DIR/$w.rc" ] || continue
      while kill -0 "$pid" 2>/dev/null; do sleep 5; done
    done < <(cat "$RC_DIR/launched.tsv" 2>/dev/null || true)
    done_rc=$(find "$RC_DIR" -maxdepth 1 -name '*.rc' -exec cat {} + 2>/dev/null | cut -f1 | .hosts_csv) || done_rc=""
    left=$(.hosts_minus "$ALL_WSGS" "$done_rc")
    echo "  WARN: the recompute scheduler ended with $src; recomputing the $(.hosts_n "$left") group(s) it did not start here"
    if [ -n "$left" ]; then
      # Recorded for the audit: these start after every landing, so they need
      # no launch time from the scheduler.
      .hosts_lines "$left" > "$RC_DIR/fallback.txt" || true
      saved="$ALL_WSGS"
      ALL_WSGS=$(recompute_order "$left" | paste -sd, -)
      run_recompute_pool "$RECOMPUTE_JOBS"
      ALL_WSGS="$saved"
    fi
  fi
}

# --- compare (tunnel-free) -> CSV ---
# Over the recomputed groups only: a group this run did not build has nothing
# of this run's to compare (link#348). A failure no longer exits here: it
# would hide the report, which names the groups that are missing.
run_finish_compare() {
  echo "=== compare (tunnel-free) ==="
  phase_begin compare
  if ( cd "$REPO_ROOT" && LNK_LOAD=loadall Rscript data-raw/study_area_compare.R \
      "$COMPARE_CSV" "$ALL_WSGS" "$CONFIG" ) > "$LOG_DIR/${TS}_compare.log" 2>&1; then
    echo "  ✓ compare CSV: $COMPARE_CSV"
  else
    echo "  ✗ compare failed; see $LOG_DIR/${TS}_compare.log"
    COMPARE_FAIL=1
  fi
  phase_end compare "" "$(csv_count "$ALL_WSGS")" "$([ "$COMPARE_FAIL" = "0" ] && echo ok || echo failed)"
}

run_finish_report() {
  echo "=== summary ==="
  # Before the INCOMPLETE branch below, which exits (link#375).
  phases_report
  echo "  run WSGs:        ${RUN_WSGS:-<none>}"
  echo "  recomputed WSGs: ${ALL_WSGS:-<none>}"
  if [ -n "$ALL_WSGS" ] && [ "${COMPARE_FAIL:-0}" = "0" ]; then
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
     || [ "$hosts_kept" != "0" ] || [ "${COMPARE_FAIL:-0}" != "0" ]; then
    echo "=== study_area_run INCOMPLETE ==="
    if [ "$hosts_kept" != "0" ]; then
      echo "  $KEPT_CAUSE_N cypher(s) were NOT burned for cause: each may hold groups"
      echo "  that are not on the dispatcher, and is still running and billed."
      echo "  Consolidate only each host's groups column, and only where"
      echo "  groups_measured = yes; never groups_partial (consolidating a group the"
      echo "  host no longer holds, or holds in part, deletes the dispatcher's copy)."
      if [ "${RECOMPUTE_RAN:-0}" = "1" ]; then
        echo "  The recompute above ran WITHOUT those groups, so recompute each one and"
        echo "  each run group that reads it afterwards (the wsg of each row of"
        echo "  ${RC_DEPS:-<TS>_recompute_deps.tsv} whose dep is one of them; without"
        echo "  that file, every group of the run). Then burn the host."
      else
        echo "  The recompute did not run, so recompute every group of the run"
        echo "  afterwards. Then burn the host."
      fi
      echo "  Every group of the run, once consolidated:"
      echo "    bash data-raw/study_area_run.sh --recompute-only --run-uid=$RUN_UID \\"
      echo "      --config=$CONFIG --schema=$SCHEMA${RUN_LABEL:+ --run-label=$RUN_LABEL} --wsgs=$RUN_WSGS"
      echo "  Hosts, reasons and commands: $LOG_DIR/${TS}_kept_hosts.tsv"
    fi
    if [ "${RUN_INCOMPLETE:-0}" != "0" ]; then
      if [ -n "${COV_MISSING:-}" ]; then
        echo "  These run WSGs have no rows from a build this run finished, so they"
        echo "  were NOT recomputed or compared: $COV_MISSING"
        [ -z "${COV_NOROWS:-}" ] || echo "    no rows:                         $COV_NOROWS"
        [ -z "${COV_STALE:-}" ]  || echo "    an earlier run's or partial rows: $COV_STALE"
        [ -z "${COV_LOST:-}" ]   || echo "    lost at consolidate:             $COV_LOST"
        [ -z "${COV_UNCONS:-}" ] || echo "    not consolidated:                $COV_UNCONS"
        run_timeouts "$COV_MISSING"
        if [ -n "$TIMED_OUT" ]; then
          echo "    statement bound hit:             $TIMED_OUT"
          printf '%s\n' "$TIMEOUT_LINES" | sed 's/^/      /'
        fi
        # A held cypher may hold this run's finished work, unconsolidated. What
        # to do with each of its groups depends on whether the host could be
        # measured and whether it was settled, which only hosts_kept_report
        # knows, and it has written that to kept_hosts.tsv. So this names the
        # groups in a held host's bucket and defers to that file, rather than
        # re-deriving its advice from sets whose meaning depends on state it
        # cannot see (code-check rounds 1-3, #348). The groups are the same
        # union hosts_kept_report checks, not the bucket alone: a host can
        # finish a group outside its bucket, and a failed consolidate source
        # puts that group in COV_MISSING (#358, code-check round 3).
        local ws held="" on_kept remodel
        for ws in ${HOST_ARR[@]+"${HOST_ARR[@]}"}; do
          if [ "${HOST_HOLD[$ws]:-0}" = "1" ]; then
            held=$(.hosts_union "$held" "${HOST_BUCKET[$ws]:-}" "${ACC_FINISHED[$ws]:-}" \
              "${ACC_DONE_LOG[$ws]:-}" "${HOST_UNCONS[$ws]:-}")
          fi
        done
        # --recompute-only has no hosts of its own; it reads the groups an
        # earlier session's kept_hosts.tsv listed for this run_uid.
        held=$(.hosts_union "$held" "${KEPT_TSV_GROUPS:-}")
        on_kept=$(.hosts_inter "$COV_MISSING" "$held")
        remodel=$(.hosts_minus "$COV_MISSING" "$held")
        if [ -n "$on_kept" ]; then
          echo "  In a kept host's bucket: settle these per ${TS}_kept_hosts.tsv first"
          echo "  (consolidate only its groups column where groups_measured = yes, never"
          echo "  groups_partial), and re-model only what is still missing: $on_kept"
        fi
        if [ -n "$remodel" ]; then
          echo "  Re-model each of these under this run_uid: $remodel"
          # warn, as the driver runs it: a group whose downstream neighbour is
          # missing too would otherwise stop at the guard (error by default),
          # and the recompute re-runs it in error mode once all are back.
          # LNK_HABITAT_GATE=0, as the driver runs it too (link#349): the gate
          # is one-way, and a group re-modelled before its missing downstream
          # neighbour would be settled on that neighbour's stale barriers; the
          # recompute below settles every group on final access.
          # Bounded as the driver bounds it (link#371): this re-model follows
          # a failure, which may have been a runaway statement.
          # The run's own bound, read from its logs, so a --recompute-only
          # session (which takes no --statement-timeout) prints it too. A group
          # that timed out may need it raised.
          # The note goes above the command: inside its backslash-continued
          # lines it would break the paste (code-check round 2).
          [ -z "$TIMED_OUT" ] || echo "    The bound below is the run's; raise it for $TIMED_OUT if the statement is genuinely slow:"
          echo "    PGOPTIONS='-c statement_timeout=${RUN_BOUND:-${STATEMENT_TIMEOUT_MIN:-30}min}' \\"
          echo "    LNK_RUN_UID=$RUN_UID ${RUN_LABEL:+LNK_RUN_LABEL=$RUN_LABEL }LNK_SCHEMA=$SCHEMA \\"
          echo "      LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 LNK_LOAD=loadall \\"
          echo "      Rscript data-raw/wsg_run_one.R <WSG> $CONFIG"
        fi
        echo "  Then recompute the whole run (every group: a re-modelled group's"
        echo "  barriers change access upstream of it):"
        echo "    bash data-raw/study_area_run.sh --recompute-only --run-uid=$RUN_UID \\"
        echo "      --config=$CONFIG --schema=$SCHEMA${RUN_LABEL:+ --run-label=$RUN_LABEL} --wsgs=$RUN_WSGS"
      else
        # Accounting reads only closed log rows; coverage also counts done
        # markers and consolidated buckets, and it found every group.
        echo "  A host's accounting (closed log rows) did not cover its whole bucket,"
        echo "  but every run WSG has rows from a build this run finished (a done"
        echo "  marker or a consolidated bucket counted), so the recompute and the"
        echo "  compare above cover them all. Most likely a log row whose date_end"
        echo "  was not set; see the per-host completeness lines above."
      fi
    fi
    if [ "${COMPARE_FAIL:-0}" != "0" ]; then
      echo "  The compare failed (see $LOG_DIR/${TS}_compare.log); the recompute"
      echo "  above stands. Re-run it alone:"
      echo "    LNK_SCHEMA=$SCHEMA LNK_LOAD=loadall Rscript data-raw/study_area_compare.R \\"
      echo "      $COMPARE_CSV ${ALL_WSGS:-<WSGs>} $CONFIG"
    fi
    # The early recompute's audit (link#374), then the pool's own failure, if
    # any: RECOMPUTE_FAIL is set by either, RECOMPUTE_FAIL_STAGE only by the
    # pool and its prep.
    if [ "${RC_AUDIT:-}" = "early" ]; then
      echo "  Every group was recomputed, but the groups named EARLY in"
      echo "  $LOG_DIR/${TS}_recompute_audit.tsv were recomputed before a group they read had"
      echo "  landed (link#374). Their habitat gate may have cleared flags for good, so"
      echo "  RE-MODEL each of them (wsg_run_one.R, LNK_HABITAT_GATE=0, under this run_uid)"
      echo "  and then recompute them; a recompute alone cannot restore what the gate cleared."
    elif [ "${RC_AUDIT:-}" = "unread" ]; then
      echo "  Every group was recomputed, but whether any started before a group it"
      echo "  reads had landed could not be checked. See $LOG_DIR/${TS}_recompute_audit.log, then:"
      echo "    Rscript data-raw/recompute_audit.R $SCHEMA $RUN_UID $RC_DEPS $RUN_WSGS_TSV $CONS_STATE $RC_DIR/launched.tsv '' $RC_DIR/fallback.txt"
    fi
    if [ "${RECOMPUTE_FAIL:-0}" != "0" ] && [ -n "${RECOMPUTE_FAIL_STAGE:-}" ]; then
      echo "  The post-consolidate recompute did not complete for every WSG."
      echo "  Those WSGs' streams_access / streams_mapping_code still hold their"
      echo "  PRE-consolidate values, so cross-WSG access — hence token1/token2"
      echo "  and ;DAM — is WRONG for them, and their habitat was never settled"
      echo "  on access (the model leg runs ungated). This is bad output, not missing"
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
      echo "    LNK_RUN_UID=$RUN_UID ${RUN_LABEL:+LNK_RUN_LABEL=$RUN_LABEL }LNK_SCHEMA=$SCHEMA \\"
      echo "      LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R <WSG> $CONFIG"
    fi
    exit 1
  fi
  echo "=== study_area_run done ==="
}
