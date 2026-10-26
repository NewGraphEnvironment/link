# data-raw/study_area_recompute.sh — which groups may be recomputed now
# (link#374). Sourced by study_area_run.sh after study_area_hosts.sh, and by
# tests/testthat/test-study_area_recompute.R. Sourcing defines functions,
# nothing else.
#
# A group's recompute (wsg_recompute_one.R) reads its own rows and the
# barrier and override rows of every group on its downstream path. Until
# #374 it ran only after every leg and every consolidate. Now a group is
# recomputed once it, and every group it reads, has LANDED on the dispatcher:
#
#   a dispatcher group   its newest <schema>.log row is this run's, closed
#                        (date_end is written last, after every persist
#                        write; the rule run_coverage uses);
#   a remote group       its host's row in <TS>_consolidate_state.tsv is
#                        `ok` (written after the copy; `in_flight` before);
#   a SKIP, or a group   always landed: it has no rows this run writes.
#   outside the run
#
# A group a run gives to several hosts lands when every one of them has
# landed it. Which groups a group reads is <TS>_recompute_deps.tsv, the line
# rule of recompute_deps.R (complete by construction).
#
# Everything here FAILS CLOSED. An early recompute that reads too little
# cannot be undone (the habitat gate only clears flags), so an unreadable
# file, a database that does not answer, or a row that does not parse means
# "not landed" and the caller launches nothing new on that poll.
#
# Globals read: SCHEMA RUN_UID (through .hosts_query, study_area_hosts.sh)
# Functions read: .hosts_query .hosts_csv .hosts_lines .hosts_minus

# recompute_landed <run_wsgs.tsv> <consolidate_state.tsv>: the run's groups
# that have landed, as CSV. Returns 1, printing nothing, when any input is
# unknown. A state file that does not exist yet means no remote host has
# landed anything, which is known.
recompute_landed() {
  local wsgs="$1" state="$2" disp hdr
  [ -r "$wsgs" ] || return 1
  IFS= read -r hdr < "$wsgs" || return 1
  # Four columns since #358, bucket_mode appended by #361.
  case "$hdr" in "$(printf 'wsg\thost\tskip\trun_uid')"|"$(printf 'wsg\thost\tskip\trun_uid\t')"*) ;; *) return 1 ;; esac
  disp=$(.hosts_query local log "run_uid = '${RUN_UID}' AND date_end IS NOT NULL
    AND (watershed_group_code, date_start) IN (
      SELECT watershed_group_code, max(date_start) FROM ${SCHEMA}.log
      GROUP BY watershed_group_code)" 1) || return 1
  if [ -e "$state" ]; then
    [ -r "$state" ] || return 1
    IFS= read -r hdr < "$state" || return 1
    [ "$hdr" = "$(printf 'wsg\tworkspace\tstate\trun_uid\tstate_utc')" ] || return 1
  else
    state=/dev/null
  fi
  printf '%s\n' "$disp" | LC_ALL=C awk -F'\t' -v uid="$RUN_UID" -v st="$state" -v ws="$wsgs" '
    BEGIN {
      while ((getline l < "/dev/stdin") > 0) if (l != "") closed[l] = 1
      n = 0
      while ((getline l < st) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[4] != uid) { bad = 1; continue }
        if (f[3] == "ok") cons[f[1] SUBSEP f[2]] = 1
      }
      n = 0
      while ((getline l < ws) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        w = f[1]; h = f[2]
        if (w !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || h == "" || f[4] != uid) { bad = 1; continue }
        seen[w] = 1
        if (f[3] == "yes") continue
        if (h == "dispatcher") { if (!(w in closed)) out[w] = 1 }
        else if (!((w SUBSEP h) in cons)) out[w] = 1
      }
      if (bad) exit 1
      for (w in seen) if (!(w in out)) print w
    }' | .hosts_csv
  [ "${PIPESTATUS[1]}" = "0" ]
}

# recompute_ready <landed csv> <deps.tsv> <launched csv> <run_wsgs.tsv>: the
# run's groups that are landed, not SKIPs, not launched, and whose every
# dependency in the run is landed, as CSV. A dependency outside the run has
# landed already. Returns 1, printing nothing, on an unreadable or malformed
# dependency file or group list.
recompute_ready() {
  local landed="$1" deps="$2" launched="$3" wsgs="$4" hdr
  [ -r "$deps" ] && [ -r "$wsgs" ] || return 1
  IFS= read -r hdr < "$wsgs" || return 1
  case "$hdr" in "$(printf 'wsg\thost\tskip\trun_uid')"|"$(printf 'wsg\thost\tskip\trun_uid\t')"*) ;; *) return 1 ;; esac
  IFS= read -r hdr < "$deps" || return 1
  [ "$hdr" = "$(printf 'wsg\trule\tdep')" ] || return 1
  LC_ALL=C awk -F'\t' -v landed="$landed" -v launched="$launched" -v ws="$wsgs" -v dp="$deps" -v uid="$RUN_UID" '
    BEGIN {
      n = split(landed, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") L[a[i]] = 1
      n = split(launched, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") D[a[i]] = 1
      n = 0
      while ((getline l < ws) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[4] != uid) { bad = 1; continue }
        run[f[1]] = 1
        if (f[3] == "yes") skip[f[1]] = 1
      }
      n = 0
      while ((getline l < dp) > 0) {
        if (++n == 1) continue
        split(l, f, "\t")
        if (f[1] !~ /^[A-Z][A-Z][A-Z][A-Z]$/ || f[3] !~ /^[A-Z][A-Z][A-Z][A-Z]$/) { bad = 1; continue }
        if (f[2] != "line") continue
        if ((f[3] in run) && !(f[3] in L) && !(f[3] in skip)) blocked[f[1]] = 1
      }
      if (bad) exit 1
      for (w in run) if ((w in L) && !(w in skip) && !(w in D) && !(w in blocked)) print w
    }' | .hosts_csv
  [ "${PIPESTATUS[0]}" = "0" ]
}
