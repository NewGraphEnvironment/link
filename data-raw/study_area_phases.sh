# data-raw/study_area_phases.sh — when each phase of a run started and ended,
# per host (link#375). Sourced by study_area_run.sh beside study_area_hosts.sh
# and study_area_finish.sh, and by tests/testthat/test-study_area_phases.R.
# Sourcing defines functions and declares PHASE_OPEN, nothing else.
#
# Every speed number before this was rebuilt by hand from log tables, console
# logs and date_end columns, so nothing comparable could be read off one run
# against the next (#377). The driver now writes <TS>_phases.tsv, one row per
# phase per host, each row as its phase ends, so a run that dies still leaves
# the phases it finished; the EXIT trap closes the one it died in as failed.
#
#   run_uid  phase  host  start_utc  end_utc  minutes  groups  status
#
#   phase    prep refresh backup model account consolidate burn coverage
#            views recompute compare (RUNBOOK §8d says what each one covers)
#   host     dispatcher or a cypher workspace; blank for a run-wide phase.
#            account, consolidate and burn are per host since link#369: each
#            cypher's run as soon as its own leg ends
#   minutes  end - start, one decimal, from the epochs taken with the times
#   groups   groups the phase covered; blank where it covers none
#   status   ok (finished, covering all it was given), failed (it errored, or
#            left groups out), skipped (it did not run: blank times). model is
#            the exception: its status is the leg's session exit, which is 0
#            even when every group in it failed (each group soft-fails); the
#            account row says whether the hosts finished their buckets.
#
# Rows overlap: the run-wide prep holds refresh and every cypher's prep, and
# the model legs run side by side. So the critical path is first start to last
# end, never a sum of rows. A driver killed mid-leg closes that leg failed, and
# the leg, which the kill does not stop, writes its own row when it ends: for
# one phase, host and start, the later row is the leg's real end.
#
# Times come from one `date -u` call each, which prints the ISO time and the
# epoch together: `date` is GNU on some hosts and BSD on others, so nothing
# here parses a date with it. The report parses ISO with perl, as the driver's
# redaction already relies on it.
#
# A row is one printf builtin call, which bash flushes as a single write() of
# well under 4 KB to a local file opened O_APPEND, so the model legs, which end
# in parallel subshells on the dispatcher (an ssh leg's row is written here too),
# can each write their own without interleaving.
#
# Globals read: PHASES_TSV (unset or empty: every function is a no-op, which is
#   how --preflight-only writes nothing) RUN_UID
# Globals written: PHASE_OPEN (key "<phase>|<host>", value "<iso> <epoch>"),
#   PHASES_REPORTED (set once phases_report has printed)
#
# Needs bash >= 4, as the driver does.

# Assigned, not just declared: ${#PHASE_OPEN[@]} on a never-assigned map is
# "unbound variable" under set -u.
declare -A PHASE_OPEN=()
PHASES_REPORTED=0

.phase_now() { date -u '+%Y-%m-%dT%H:%M:%SZ %s'; }

# phases_init <file>: where rows go. The header is written only to a new file.
phases_init() {
  PHASES_TSV="$1"
  [ -s "$PHASES_TSV" ] && return 0
  printf 'run_uid\tphase\thost\tstart_utc\tend_utc\tminutes\tgroups\tstatus\n' \
    > "$PHASES_TSV"
}

# phase_begin <phase> [host] [start]: open a phase. start is "<iso> <epoch>",
# for a phase that began before the file existed (the run-wide prep).
phase_begin() {
  [ -n "${PHASES_TSV:-}" ] || return 0
  local now="${3:-}"
  # A date that fails costs this row its start, never the run.
  [ -n "$now" ] || now=$(.phase_now) || now=""
  [ -n "$now" ] || now=" "
  PHASE_OPEN["$1|${2:-}"]="$now"
}

# phase_forget <phase> [host]: the parent's copy of a phase a subshell closed.
phase_forget() { unset 'PHASE_OPEN['"$1|${2:-}"']'; }

# phase_end <phase> <host> <groups> <status> [quiet]: close a phase and write
# its row. quiet writes no console line, for a subshell whose stdout is a log;
# the parent prints the row with phase_print once the subshell has returned.
# Never fails: a row that cannot be written is a lost measurement, not a reason
# to stop a run.
phase_end() {
  [ -n "${PHASES_TSV:-}" ] || return 0
  local key="$1|${2:-}" start end s_iso s_ep e_iso e_ep min
  start="${PHASE_OPEN[$key]:- }"
  end=$(.phase_now) || end=" "
  [ -n "$end" ] || end=" "
  e_iso="${end% *}"; e_ep="${end#* }"
  # Ended without a begin, or a date failed: the row says nothing it cannot.
  s_iso="${start% *}"; s_ep="${start#* }"
  min=""
  if [ -n "$s_ep" ] && [ -n "$e_ep" ]; then
    min=$(LC_ALL=C awk -v s="$s_ep" -v e="$e_ep" 'BEGIN { printf "%.1f", (e - s) / 60 }') \
      || min=""
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${RUN_UID:-}" "$1" "${2:-}" \
    "$s_iso" "$e_iso" "$min" "${3:-}" "$4" >> "$PHASES_TSV" 2>/dev/null \
    || echo "  WARN: could not write the $1 row to $PHASES_TSV" >&2
  unset 'PHASE_OPEN['"$key"']'
  [ "${5:-}" = "quiet" ] || phase_print "$1" "${2:-}"
  return 0
}

# phase_skip <phase> [host] [groups]: a phase that did not run, blank times.
phase_skip() {
  [ -n "${PHASES_TSV:-}" ] || return 0
  printf '%s\t%s\t%s\t\t\t\t%s\tskipped\n' "${RUN_UID:-}" "$1" "${2:-}" "${3:-}" \
    >> "$PHASES_TSV" 2>/dev/null \
    || echo "  WARN: could not write the $1 row to $PHASES_TSV" >&2
  phase_print "$1" "${2:-}"
  return 0
}

# phase_print <phase> [host]: the newest row for it, as one console line.
phase_print() {
  [ -n "${PHASES_TSV:-}" ] && [ -f "$PHASES_TSV" ] || return 0
  awk -F'\t' -v p="$1" -v h="${2:-}" '
    NR > 1 && $2 == p && $3 == h { row = $0 }
    END {
      if (row == "") exit
      split(row, f, "\t")
      host = (f[3] == "") ? "" : " " f[3]
      if (f[8] == "skipped") { printf "  [phase] %s%s skipped\n", f[2], host; exit }
      g = (f[7] == "") ? "" : ", " f[7] " groups"
      printf "  [phase] %s%s %s %s -> %s (%s min%s)\n", f[2], host, f[8], f[4], f[5], f[6], g
    }' "$PHASES_TSV" 2>/dev/null || true
}

# phases_close_open: every phase still open, closed failed. For the EXIT trap:
# the phase a run died in is the one its file would otherwise leave out. A phase
# a subshell already closed (a leg that ended while the driver waited on an
# earlier one) has its row, with the start the parent holds, and is left alone.
phases_close_open() {
  [ -n "${PHASES_TSV:-}" ] || return 0
  [ "${#PHASE_OPEN[@]}" -gt 0 ] || return 0
  local key s
  for key in "${!PHASE_OPEN[@]}"; do
    s="${PHASE_OPEN[$key]% *}"
    if [ -n "$s" ] && [ -f "$PHASES_TSV" ] && awk -F'\t' -v p="${key%%|*}" \
         -v h="${key#*|}" -v s="$s" '$2 == p && $3 == h && $4 == s { f = 1 }
         END { exit !f }' "$PHASES_TSV" 2>/dev/null; then
      unset 'PHASE_OPEN['"$key"']'
      continue
    fi
    phase_end "${key%%|*}" "${key#*|}" "" failed
  done
  return 0
}

# phases_report: the table, then the run's critical path (first start to last
# end), its longest model leg, and the consolidate tail: how long the last
# consolidate ran past the last model leg's end (link#369; 0 when every copy
# overlapped a leg still modelling). Skipped rows have no times and add nothing.
phases_report() {
  [ -n "${PHASES_TSV:-}" ] && [ -f "$PHASES_TSV" ] || return 0
  PHASES_REPORTED=1
  echo "  phases ($PHASES_TSV):"
  awk -F'\t' '{ printf "    %-11s %-10s %-20s %-20s %7s %6s %s\n", $2, $3, $4, $5, $6, $7, $8 }' \
    "$PHASES_TSV" 2>/dev/null || true
  perl -MTime::Local=timegm -F'\t' -lane '
    next if $. == 1;
    sub t { my ($y, $mo, $d, $h, $mi, $s) = $_[0] =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z$/
              or return undef; timegm($s, $mi, $h, $d, $mo - 1, $y) }
    my ($s, $e) = (t($F[3] // ""), t($F[4] // ""));
    next unless defined $s && defined $e;
    $lo = $s if !defined $lo || $s < $lo;
    $hi = $e if !defined $hi || $e > $hi;
    if ($F[1] eq "model" && (!defined $leg || $e - $s > $leg)) { $leg = $e - $s; $who = $F[2] }
    $mend = $e if $F[1] eq "model" && (!defined $mend || $e > $mend);
    $cend = $e if $F[1] eq "consolidate" && (!defined $cend || $e > $cend);
    END {
      exit unless defined $lo;
      printf "  critical path: %.1f min (first start to last end)\n", ($hi - $lo) / 60;
      printf "  longest model leg: %.1f min (%s)\n", $leg / 60, $who if defined $leg;
      if (defined $mend && defined $cend) {
        my $tail = $cend - $mend; $tail = 0 if $tail < 0;
        printf "  consolidate tail: %.1f min (last consolidate end past the last model end)\n", $tail / 60;
      }
    }' "$PHASES_TSV" 2>/dev/null || true
  return 0
}
