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
#   phase    prep refresh model account consolidate burn coverage views
#            recompute compare (RUNBOOK §8d says what each one covers)
#   host     dispatcher or a cypher workspace; blank for a run-wide phase
#   minutes  end - start, one decimal, from the epochs taken with the times
#   groups   groups the phase covered; blank where it covers none
#   status   ok (finished, covering all it was given), failed (it errored, or
#            left groups out), skipped (it did not run: blank times)
#
# Times come from one `date -u` call each, which prints the ISO time and the
# epoch together: `date` is GNU on some hosts and BSD on others, so nothing
# here parses a date with it. The report parses ISO with perl, as the driver's
# redaction already relies on it.
#
# A row is one printf to a file opened for append, well under PIPE_BUF, so the
# model legs, which end in parallel subshells, can each write their own.
#
# Globals read: PHASES_TSV (unset or empty: every function is a no-op, which is
#   how --preflight-only writes nothing) RUN_UID
# Globals written: PHASE_OPEN (key "<phase>|<host>", value "<iso> <epoch>")
#
# Needs bash >= 4, as the driver does.

declare -A PHASE_OPEN

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
  [ -n "$now" ] || now=$(.phase_now)
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
  start="${PHASE_OPEN[$key]:-}"
  end=$(.phase_now)
  e_iso="${end% *}"; e_ep="${end#* }"
  if [ -n "$start" ]; then
    s_iso="${start% *}"; s_ep="${start#* }"
    min=$(awk -v s="$s_ep" -v e="$e_ep" 'BEGIN { printf "%.1f", (e - s) / 60 }')
  else
    # Ended without a begin: the row keeps its end, and says nothing it cannot.
    s_iso=""; min=""
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
# the phase a run died in is the one its file would otherwise leave out.
phases_close_open() {
  [ -n "${PHASES_TSV:-}" ] || return 0
  local key
  for key in "${!PHASE_OPEN[@]}"; do
    phase_end "${key%%|*}" "${key#*|}" "" failed
  done
  return 0
}

# phases_report: the table, then the run's critical path (first start to last
# end) and its longest model leg. Skipped rows have no times and add nothing.
phases_report() {
  [ -n "${PHASES_TSV:-}" ] && [ -f "$PHASES_TSV" ] || return 0
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
    END {
      exit unless defined $lo;
      printf "  critical path: %.1f min (first start to last end)\n", ($hi - $lo) / 60;
      printf "  longest model leg: %.1f min (%s)\n", $leg / 60, $who if defined $leg;
    }' "$PHASES_TSV" 2>/dev/null || true
  return 0
}
