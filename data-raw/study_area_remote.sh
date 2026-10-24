# data-raw/study_area_remote.sh — how the driver runs a command on a remote
# host and judges it (link#376). Sourced by study_area_run.sh and by
# tests/testthat/test-study_area_remote.R. Sourcing defines functions only.
#
# The rule: a remote command is judged by what the remote shell PRINTS, never
# by ssh's exit status. Some ssh servers exit 0 whatever the remote command
# returned (Tailscale SSH to macOS does), so a status read from ssh can say a
# failed probe passed or a killed leg ended cleanly. ssh's own non-zero status
# (it could not connect, or the link dropped) still wins: that one is real.
#
#   remote_run       a short command: its status is printed after it as
#                    `__LNK_RC__=<n>`, and no trailer at all is a failure.
#   remote_leg_cmd   the modelling leg's command, which prints
#                    `__LNK_LEG_END__` once its loop has run to the end.
#   remote_leg_status  the leg's status: ssh's when non-zero, else 0 only
#                    when its log holds the end marker.
#
# Markers are matched anywhere on a line: R writes warnings into the same
# stream, and one flushed without a newline puts the next line mid-line
# (link#347).
#
# Globals read by remote_leg_cmd: SCHEMA CONFIG RUN_UID RUN_LABEL
#   STATEMENT_TIMEOUT_MIN FWAPG_GIT_SHA BCFISHOBS_GIT_SHA LNK_BCFP_MODEL_VERSION
#   HOST_SSH HOST_KIND (assoc, keyed by host)
#
# Needs bash >= 4 (assoc arrays), as the driver does.

# .remote_dir <host>: the link checkout a host's commands run from.
.remote_dir() {
  echo "~/Projects/repo/link"
}

# remote_run <ssh target> <command> <stdout file> [stderr file]: run the
# command there, in a subshell so an `exit` inside it still reaches the
# trailer. Its stdout and the trailer go to <stdout file>; its stderr to
# [stderr file], or into <stdout file> when none is given. Returns the status
# the remote shell printed, 255 when it printed none, or ssh's own non-zero
# status. Read the output with remote_out, which drops the trailer.
remote_run() {
  local target="$1" cmd="$2" out="$3" err="${4:-}" rc=0 st
  if [ -n "$err" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$target" \
      "( $cmd ); echo __LNK_RC__=\$?" > "$out" 2> "$err" || rc=$?
  else
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$target" \
      "( $cmd ) 2>&1; echo __LNK_RC__=\$?" > "$out" 2>&1 || rc=$?
  fi
  [ "$rc" = "0" ] || return "$rc"
  st=$(LC_ALL=C sed -n 's/.*__LNK_RC__=\([0-9][0-9]*\)$/\1/p' "$out" 2>/dev/null | tail -1)
  [ -n "$st" ] || return 255
  return "$st"
}

# remote_out <stdout file>: what the command printed, less the trailer.
remote_out() {
  [ -r "$1" ] || return 0
  LC_ALL=C sed -e 's/__LNK_RC__=[0-9][0-9]*$//' "$1" | LC_ALL=C sed '/^$/d'
}

# remote_leg_cmd <host> <groups, space-separated>: the modelling leg's remote
# command. Every export the leg needs crosses ssh in the command itself: an
# export in the driver's environment does not (link#227, link#262, link#371).
# The loop soft-fails each group, and `__LNK_LEG_END__` is printed after it,
# inside the braces the `cd` guards, so a failed `cd` prints no marker.
remote_leg_cmd() {
  local host="$1" groups="$2"
  printf '%s' "cd $(.remote_dir "$host") && export LNK_SCHEMA='$SCHEMA' && export LNK_GUARD_DOWNSTREAM=warn && export LNK_HABITAT_GATE=0 && export PGOPTIONS='-c statement_timeout=${STATEMENT_TIMEOUT_MIN}min' && export LNK_STATEMENT_TIMEOUT_MIN='$STATEMENT_TIMEOUT_MIN' && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export BCFISHOBS_GIT_SHA='${BCFISHOBS_GIT_SHA:-}' && export LNK_RUN_UID='$RUN_UID' && export LNK_RUN_LABEL='${RUN_LABEL:-}' && export LNK_BCFP_MODEL_VERSION='${LNK_BCFP_MODEL_VERSION:-}' && { for w in $groups; do Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done; echo __LNK_LEG_END__; }"
}

# remote_leg_status <ssh status> <leg log>: 0 only when ssh exited 0 and the
# log holds the end marker; ssh's status when it is non-zero; 1 otherwise.
remote_leg_status() {
  [ "$1" = "0" ] || return "$1"
  [ -r "$2" ] || return 1
  LC_ALL=C grep -q '__LNK_LEG_END__' "$2" 2>/dev/null || return 1
  return 0
}
