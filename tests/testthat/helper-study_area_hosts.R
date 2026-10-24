# Shared by the tests that run data-raw/study_area_hosts.sh against stub hosts
# (test-study_area_hosts.R, test-study_area_legs.R): a scratch world of stub
# binaries, a mock cypher_down.sh, and readers for what the libs leave there.

# A scratch world: stub binaries, a mock cypher_down.sh, empty dirs for the
# tofu workspace and the logs.
hosts_world <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  for (sub in c("bin", "stub", "cypher", "tf", "logs")) {
    dir.create(file.path(d, sub))
  }
  stub <- function(name, body) {
    p <- file.path(d, "bin", name)
    writeLines(c("#!/bin/sh", body), p)
    Sys.chmod(p, "755")
  }
  # ssh: the host is the cypher@ argument. Records argv and stdin, so a test
  # can assert the remote route, and answers from that host's fixture: the
  # `_streams` one for a streams query, the plain one for a log query.
  stub("ssh", c(
    'host=""; for a in "$@"; do case "$a" in cypher@*) host="${a#cypher@}" ;; esac; done',
    sprintf('s="%s/stub/ssh_$host"', d),
    'printf "%s\\n" "$*" >> "$s.argv"',
    'in=$(cat); printf "%s\\n" "$in" >> "$s.stdin"',
    'f="$s.out"',
    'case "$in" in *".streams_mapping_code WHERE"*) f="${s}_mc.out" ;; esac',
    'case "$in" in *".streams WHERE"*) f="${s}_streams.out" ;; esac',
    '[ -f "$f" ] && cat "$f"',
    '[ -f "$s.rc" ] && exit "$(cat "$s.rc")"',
    "exit 0"
  ))
  stub("psql", c(
    "cat > /dev/null",
    sprintf(
      '[ -f "%s/stub/psql_local.out" ] && cat "%s/stub/psql_local.out"',
      d, d
    ),
    "exit 0"
  ))
  # tofu: `state list` prints that workspace's fixture (none = destroyed).
  stub("tofu", sprintf(
    '[ -f "%s/stub/tofu_$TF_WORKSPACE.out" ] && cat "%s/stub/tofu_$TF_WORKSPACE.out"; exit 0',
    d, d
  ))
  stub("doctl", sprintf(
    '[ -f "%s/stub/doctl.out" ] && cat "%s/stub/doctl.out"; exit 0',
    d, d
  ))
  down <- file.path(d, "cypher", "cypher_down.sh")
  writeLines(
    c("#!/bin/sh", sprintf('echo "$*" >> "%s/stub/burn_calls"', d)),
    down
  )
  Sys.chmod(down, "755")
  d
}

# What host_finished reads back from a host's database.
db_answer <- function(wsgs) c("__LNK_BEGIN__", wsgs, "__LNK_END__")

put <- function(world, name, lines) {
  writeLines(lines, file.path(world, "stub", name))
}

burn_calls <- function(world) {
  p <- file.path(world, "stub", "burn_calls")
  if (file.exists(p)) readLines(p) else character(0)
}

kept_tsv <- function(world) {
  p <- file.path(world, "logs", "T0_kept_hosts.tsv")
  if (!file.exists(p)) {
    return(NULL)
  }
  utils::read.delim(p,
    quote = "", na.strings = character(),
    comment.char = "", stringsAsFactors = FALSE, colClasses = "character"
  )
}
