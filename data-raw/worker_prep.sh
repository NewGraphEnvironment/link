#!/usr/bin/env bash
# Per-worker prep (link#376): ready a persistent machine to model one bucket
# of a study_area_run.sh run, without changing anything else on it.
#
# A worker is a machine that already exists and stays up, reached over ssh,
# which the driver neither spins nor burns. Other sessions use it, so unlike
# cypher_prep.sh this script installs nothing by default, reloads no shared
# data and recreates no table:
#
#   1. a clone the driver owns, ~/Projects/repo/link_worker (WORKER_PREP_DIR),
#      cloned on first use and reset to origin/<run branch> on every prep. The
#      worker's own link checkout is never touched.
#   2. link by load_all from that clone, so the link installed on the worker
#      for every other session is never replaced. load_all also refuses an
#      installed fresh below DESCRIPTION's floor.
#   3. fresh asserted, never installed: it must export what the pipeline
#      calls, and its recorded sha must be its own. A FRESH_GIT_SHA pin in the
#      worker's ~/.Renviron that names another build, or a LINK_GIT_SHA pin
#      that is not the clone's HEAD, is refused: R reads ~/.Renviron after the
#      environment, so a pin there wins over anything the driver exports and
#      would be stamped into every row. The driver's parity gate then compares
#      fresh_sha and repo_sha with the dispatcher's.
#   4. the config's discharge table checked, not loaded; the primitives'
#      vintage is the driver's own gate (host_vintage.R), also not reloaded.
#   5. lnk_persist_init() WITHOUT force_recreate: this schema may hold the
#      worker's own tables, and the driver refuses before prep a worker whose
#      schema holds rows for any group of its bucket.
#
# It ends with a bare `=== READY`, which the driver greps anchored, as for
# cypher_prep.sh.
#
# WORKER_PREP_STAGE=install-fresh is --auto-install's remediation: install
# fresh at the pin in DESCRIPTION's Remotes, re-check, and end with
# `=== READY (fresh install only)`. It refuses when a FRESH_GIT_SHA pin is
# set, because the pin would outlive the install and keep naming the old
# build.
#
# Invoked by the driver over ssh, the script on stdin:
#   ssh <worker> "WORKER_PREP_BRANCH=... bash -s" < data-raw/worker_prep.sh
# so no copy of an older version can be left behind on the worker. Written
# for bash 3.2 (macOS's /bin/bash): no associative arrays.
#
# Inputs (environment):
#   WORKER_PREP_BRANCH   the run's branch (required)
#   WORKER_PREP_ORIGIN   the clone's origin URL (required)
#   WORKER_PREP_CONFIG   the run's config (required for STAGE=all)
#   WORKER_PREP_SCHEMA   the run's persist schema (required for STAGE=all)
#   WORKER_PREP_WET_LOAD the dispatcher's wet load, when the config reads wet;
#                        the worker must hold the same one, or hosts classify
#                        on different discharge (link#331)
#   WORKER_PREP_STAGE    all (default) | install-fresh
#   WORKER_PREP_DIR      default ~/Projects/repo/link_worker

set -euo pipefail

BRANCH="${WORKER_PREP_BRANCH:-}"
ORIGIN="${WORKER_PREP_ORIGIN:-}"
STAGE="${WORKER_PREP_STAGE:-all}"
DIR="${WORKER_PREP_DIR:-$HOME/Projects/repo/link_worker}"
case "$STAGE" in
  all|install-fresh) ;;
  *) echo "FATAL: WORKER_PREP_STAGE must be 'all' or 'install-fresh' (got '$STAGE')" >&2; exit 1 ;;
esac
[ -n "$BRANCH" ] || { echo "FATAL: WORKER_PREP_BRANCH is required" >&2; exit 1; }
[ -n "$ORIGIN" ] || { echo "FATAL: WORKER_PREP_ORIGIN is required" >&2; exit 1; }
if [ "$STAGE" = "all" ]; then
  [ -n "${WORKER_PREP_CONFIG:-}" ] || { echo "FATAL: WORKER_PREP_CONFIG is required" >&2; exit 1; }
  [ -n "${WORKER_PREP_SCHEMA:-}" ] || { echo "FATAL: WORKER_PREP_SCHEMA is required" >&2; exit 1; }
fi

# --- 1. the driver's clone ------------------------------------------------
if [ ! -d "$DIR/.git" ]; then
  if [ -e "$DIR" ]; then
    echo "FATAL: $DIR exists and is not a git clone; it is not the driver's to use" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$DIR")"
  git clone -q "$ORIGIN" "$DIR"
fi
cd "$DIR"
got=$(git remote get-url origin 2>/dev/null || true)
if [ "$got" != "$ORIGIN" ]; then
  echo "FATAL: $DIR's origin is '$got', not the run's '$ORIGIN'; it is not the driver's clone" >&2
  exit 1
fi
git fetch -q origin "$BRANCH"
git checkout -q -B "$BRANCH" "origin/$BRANCH"
git reset -q --hard "origin/$BRANCH"
# Untracked files would read as a dirty tree in log.link_dirty.
git clean -q -fd
echo "=== worker clone at $(git rev-parse HEAD) ($BRANCH)"

# --- 2-3. link by load_all; fresh asserted --------------------------------
check_versions() {
  Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
fail <- function(...) { cat("FATAL: ", ..., "\n", sep = ""); quit(status = 1) }
res <- lnk_preflight_fresh(quiet = TRUE)
if (!isTRUE(res$ok)) fail("fresh does not export what the pipeline calls: ", res$message)
st <- link:::.lnk_pkg_git_state("fresh")
remote <- link:::.lnk_pkg_remote_sha("fresh")
if (is.na(st$sha)) fail("fresh_sha unresolvable on this worker; install fresh from a published ref")
if (!is.na(remote) && !identical(remote, st$sha)) {
  fail("FRESH_GIT_SHA pins ", substr(st$sha, 1, 12), " but the installed fresh was built from ",
       substr(remote, 1, 12), ". Remove FRESH_GIT_SHA (and FRESH_GIT_DIRTY) from this ",
       "worker\x27s ~/.Renviron; a pin there wins over anything the driver exports.")
}
head <- system("git rev-parse HEAD", intern = TRUE)
lk <- link:::.lnk_pkg_git_state("link")
if (!identical(lk$sha, head)) {
  fail("link_sha resolves to ", lk$sha, " (", lk$source, "), not the clone\x27s HEAD ", head,
       ". Remove LINK_GIT_SHA (and LINK_GIT_DIRTY) from this worker\x27s ~/.Renviron.")
}
cat("=== link ", as.character(utils::packageVersion("link")), " at ", substr(head, 1, 12),
    "; fresh ", as.character(utils::packageVersion("fresh")), " at ", substr(st$sha, 1, 12),
    " (", st$source, ")\n", sep = "")
'
}

if [ "$STAGE" = "install-fresh" ]; then
  if [ -n "$(Rscript -e 'cat(Sys.getenv("FRESH_GIT_SHA"))')" ]; then
    echo "FATAL: FRESH_GIT_SHA is set on this worker (its ~/.Renviron); it would outlive" >&2
    echo "  an install and keep naming the old build. Remove it, then re-run." >&2
    exit 1
  fi
  FRESH_REF=$(awk '/^Remotes:/{r=1;next} r && /^[^ ]/{r=0} r' DESCRIPTION \
    | tr -d ' ,' | grep '^NewGraphEnvironment/fresh@' || true)
  [ -n "$FRESH_REF" ] || { echo "FATAL: no NewGraphEnvironment/fresh@ pin in DESCRIPTION Remotes" >&2; exit 1; }
  echo "=== installing $FRESH_REF"
  Rscript -e "pak::pkg_install(commandArgs(TRUE)[1], upgrade = FALSE, ask = FALSE)" "$FRESH_REF"
  check_versions
  echo "=== READY (fresh install only)"
  exit 0
fi

check_versions

# --- 4-5. discharge checked; the persist initialised, never recreated -----
WORKER_PREP_CONFIG="$WORKER_PREP_CONFIG" WORKER_PREP_SCHEMA="$WORKER_PREP_SCHEMA" \
  WORKER_PREP_WET_LOAD="${WORKER_PREP_WET_LOAD:-}" Rscript -e '
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
fail <- function(...) { cat("FATAL: ", ..., "\n", sep = ""); quit(status = 1) }
conn <- DBI::dbConnect(RPostgres::Postgres(), host = "localhost", port = 5432L,
  dbname = "fwapg", user = "postgres", password = "postgres")
cfg <- lnk_config(Sys.getenv("WORKER_PREP_CONFIG"))
cfg$pipeline$schema <- Sys.getenv("WORKER_PREP_SCHEMA")
dis <- lnk_preflight_discharge(conn, cfg, quiet = TRUE)
if (!isTRUE(dis$ok)) {
  fail("this worker holds no discharge for --config=", Sys.getenv("WORKER_PREP_CONFIG"),
       " (", link:::.lnk_discharge_source(cfg), "); load it there first: ", dis$message)
}
if (identical(link:::.lnk_discharge_source(cfg), "wet")) {
  want <- Sys.getenv("WORKER_PREP_WET_LOAD")
  got <- link:::.lnk_discharge_wet_load_id(dis$comment)
  if (!nzchar(want) || !identical(got, want)) {
    fail("this worker holds wet load ", got, ", the dispatcher ", want,
         "; load the dispatcher\x27s there first (data-raw/discharge_wet_load.R --expect-load=", want, ")")
  }
}
species <- if (!is.null(cfg$species)) cfg$species else
  unique(lnk_load_overrides(cfg)$parameters_fresh$species_code)
lnk_persist_init(conn, cfg, species)
cat("=== persist ", cfg$pipeline$schema, " initialised (not recreated)\n", sep = "")
'
echo "=== READY"
