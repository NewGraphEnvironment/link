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
# A cloud host runs the link it pak-installed during prep, from
# ~/Projects/repo/link. A persistent worker runs link by load_all from a clone
# the driver owns, ~/Projects/repo/link_worker, so the link installed there for
# every other session is never replaced, and the worker's own checkout is
# never touched (link#376).
#
# Globals read by remote_leg_cmd: SCHEMA CONFIG RUN_UID RUN_LABEL RUN_SHA
#   STATEMENT_TIMEOUT_MIN FWAPG_GIT_SHA BCFISHOBS_GIT_SHA LNK_BCFP_MODEL_VERSION
#   LNK_TEST_STALL_WSG HOST_KIND (assoc, keyed by host)
#
# Needs bash >= 4 (assoc arrays), as the driver does.

# .remote_dir <host>: the link checkout a host's commands run from.
.remote_dir() {
  if [ "${HOST_KIND[$1]:-cypher}" = "worker" ]; then
    echo "~/Projects/repo/link_worker"
  else
    echo "~/Projects/repo/link"
  fi
}

# .remote_cd <host>: what every R command there is preceded by: the checkout,
# and on a worker the load_all switch every data-raw script reads.
.remote_cd() {
  if [ "${HOST_KIND[$1]:-cypher}" = "worker" ]; then
    echo "cd $(.remote_dir "$1") && export LNK_LOAD=loadall"
  else
    echo "cd $(.remote_dir "$1")"
  fi
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

# Every variable remote_leg_cmd exports, plus the one the leg runs under on a
# worker. A worker's ~/.Renviron is read after the environment, so a line
# there for any of these would beat the leg's export (link#376): another
# schema, the habitat gate on, another run's provenance. worker_prep.sh
# refuses a worker that sets one; a test holds this list to remote_leg_cmd's
# exports.
REMOTE_LEG_VARS="LNK_LOAD LNK_TEST_STALL_WSG LNK_SCHEMA LNK_GUARD_DOWNSTREAM LNK_HABITAT_GATE PGOPTIONS LNK_STATEMENT_TIMEOUT_MIN FWAPG_GIT_SHA BCFISHOBS_GIT_SHA LNK_RUN_UID LNK_RUN_LABEL LNK_BCFP_MODEL_VERSION"

# remote_leg_cmd <host> <groups, space-separated>: the modelling leg's remote
# command. Every export the leg needs crosses ssh in the command itself: an
# export in the driver's environment does not (link#227, link#262, link#371).
# The loop soft-fails each group, and `__LNK_LEG_END__` is printed after it,
# inside the braces the `cd` guards, so a failed `cd` prints no marker.
#
# On a worker every group runs load_all afresh from the clone, so a change to
# the clone after the parity gate (another run's prep, a hand `git checkout`)
# would change the code under later groups. Each group first checks the
# clone's HEAD against the run's (RUN_SHA) and is not run when it moved.
#
# LNK_TEST_STALL_WSG (link#371's stall hook) crosses ssh only as a group code;
# anything else returns 1 and prints nothing of it.
remote_leg_cmd() {
  local host="$1" groups="$2" stall="" guard=""
  if [ -n "${LNK_TEST_STALL_WSG:-}" ]; then
    # Whole value: grep -x would pass one with an embedded newline.
    if ! [[ "$LNK_TEST_STALL_WSG" =~ ^[A-Z]{4}$ ]]; then
      echo "FATAL: LNK_TEST_STALL_WSG must be one four-letter group code" >&2
      return 1
    fi
    stall="export LNK_TEST_STALL_WSG='$LNK_TEST_STALL_WSG' && "
  fi
  if [ "${HOST_KIND[$host]:-cypher}" = "worker" ]; then
    guard="[ \"\$(git rev-parse HEAD)\" = '${RUN_SHA:-}' ] || { echo \"[WARN] worker WSG \$w not run: HEAD moved off ${RUN_SHA:-}\"; continue; }; "
  fi
  printf '%s' "$(.remote_cd "$host") && ${stall}export LNK_SCHEMA='$SCHEMA' && export LNK_GUARD_DOWNSTREAM=warn && export LNK_HABITAT_GATE=0 && export PGOPTIONS='-c statement_timeout=${STATEMENT_TIMEOUT_MIN}min' && export LNK_STATEMENT_TIMEOUT_MIN='$STATEMENT_TIMEOUT_MIN' && export FWAPG_GIT_SHA='${FWAPG_GIT_SHA:-}' && export BCFISHOBS_GIT_SHA='${BCFISHOBS_GIT_SHA:-}' && export LNK_RUN_UID='$RUN_UID' && export LNK_RUN_LABEL='${RUN_LABEL:-}' && export LNK_BCFP_MODEL_VERSION='${LNK_BCFP_MODEL_VERSION:-}' && { for w in $groups; do ${guard}Rscript data-raw/wsg_run_one.R \$w '$CONFIG' || echo \"[WARN] cy WSG \$w failed\"; done; echo __LNK_LEG_END__; }"
}

# worker_prep_env <host>: the environment worker_prep.sh reads, as words to
# put before `bash -s` in the remote command (link#376). The driver refuses
# a quote in each before any remote host is reached (the branch, --config,
# the persist schema however it was resolved, the wet load); the origin URL
# is checked here.
worker_prep_env() {
  case "${ORIGIN_URL:-}" in
    ""|*[!A-Za-z0-9._:/@~+-]*)
      echo "FATAL: the origin URL cannot be passed to a worker" >&2; return 1 ;;
    *://*@*)
      # Userinfo (a token) would reach the worker's ps, its clone's config and
      # the committed prep log.
      echo "FATAL: the origin URL carries credentials; a worker clones a public URL" >&2; return 1 ;;
  esac
  printf '%s' "WORKER_PREP_BRANCH='${LINK_BRANCH:-}' WORKER_PREP_ORIGIN='$ORIGIN_URL' WORKER_PREP_CONFIG='${CONFIG:-}' WORKER_PREP_SCHEMA='${SCHEMA:-}' WORKER_PREP_WET_LOAD='${WET_LOAD:-}' WORKER_PREP_LEG_VARS='$REMOTE_LEG_VARS'"
}

# remote_redact_init: the names to redact for each worker, longest first,
# into WK_REDACT (name) and WK_REDACT_KEY (its worker key). ssh writes more
# than the target itself into a log: for `user@host` its errors name the host
# alone, and for an alias from ssh's config they name the HostName it resolves
# to. `ssh -G` reads that from the config without connecting. Run once, by the
# driver after its arguments are parsed; remote_redact_targets runs it when
# nothing has.
remote_redact_init() {
  local i t n r m seen
  WK_REDACT=(); WK_REDACT_KEY=()
  for i in ${WK_TARGETS[@]+"${!WK_TARGETS[@]}"}; do
    t="${WK_TARGETS[$i]}"
    r=$(ssh -G "$t" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }') || r=""
    for n in "$t" "${t#*@}" "$r"; do
      [ -n "$n" ] || continue
      seen=0
      for m in ${WK_REDACT[@]+"${WK_REDACT[@]}"}; do [ "$m" = "$n" ] && seen=1; done
      [ "$seen" = 1 ] && continue
      WK_REDACT+=("$n"); WK_REDACT_KEY+=("${WK_KEYS[$i]}")
    done
  done
  # Longest first, so a target is replaced before its host part.
  local order
  order=$(for i in ${WK_REDACT[@]+"${!WK_REDACT[@]}"}; do
    printf '%s %s\n' "${#WK_REDACT[$i]}" "$i"; done | sort -rn | awk '{ print $2 }')
  local names=() keys=()
  for i in $order; do names+=("${WK_REDACT[$i]}"); keys+=("${WK_REDACT_KEY[$i]}"); done
  WK_REDACT=(${names[@]+"${names[@]}"}); WK_REDACT_KEY=(${keys[@]+"${keys[@]}"})
  WK_REDACT_READY=1
}

# remote_redact_add <key> <name>: one more name to redact for a worker, such
# as how it names itself in what it writes (worker_prep.sh prints it).
remote_redact_add() {
  local m names=() keys=() i order
  [ -n "${2:-}" ] || return 0
  [ "${WK_REDACT_READY:-0}" = "1" ] || remote_redact_init
  for m in ${WK_REDACT[@]+"${WK_REDACT[@]}"}; do [ "$m" = "$2" ] && return 0; done
  WK_REDACT+=("$2"); WK_REDACT_KEY+=("$1")
  order=$(for i in "${!WK_REDACT[@]}"; do
    printf '%s %s\n' "${#WK_REDACT[$i]}" "$i"; done | sort -rn | awk '{ print $2 }')
  for i in $order; do names+=("${WK_REDACT[$i]}"); keys+=("${WK_REDACT_KEY[$i]}"); done
  WK_REDACT=("${names[@]}"); WK_REDACT_KEY=("${keys[@]}")
}

# remote_redact_targets <file>: replace each worker's names (remote_redact_init)
# in the file with `<workerN>`. A worker's target is the operator's
# infrastructure and a run's logs are committed as evidence. Matched whole
# (not inside a longer name) and literally: a name holds `.`, `@` and `-`.
# `@` may precede a match: ssh's own failure line is `<user>@<host>: ...`,
# and the longest-first order already replaces a whole `user@host` target
# before its host part. Never fails.
remote_redact_targets() {
  local i
  [ -f "$1" ] || return 0
  [ "${WK_REDACT_READY:-0}" = "1" ] || remote_redact_init
  for i in ${WK_REDACT[@]+"${!WK_REDACT[@]}"}; do
    LNK_TGT="${WK_REDACT[$i]}" LNK_REP="<${WK_REDACT_KEY[$i]}>" perl -i -pe \
      's/(?<![A-Za-z0-9._-])\Q$ENV{LNK_TGT}\E(?![A-Za-z0-9._@-])/$ENV{LNK_REP}/g' \
      "$1" 2>/dev/null || true
  done
  return 0
}

# remote_leg_status <ssh status> <leg log>: 0 only when ssh exited 0 and the
# log holds the end marker; ssh's status when it is non-zero; 1 otherwise.
remote_leg_status() {
  [ "$1" = "0" ] || return "$1"
  [ -r "$2" ] || return 1
  LC_ALL=C grep -q '__LNK_LEG_END__' "$2" 2>/dev/null || return 1
  return 0
}
