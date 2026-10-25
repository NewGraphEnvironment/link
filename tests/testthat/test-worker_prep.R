# data-raw/worker_prep.sh: ready a persistent worker without changing anything
# else on it (link#376). These run the script with a stub Rscript, so they
# cover its own branches (the clone it owns, its stages); its R checks ran
# for real on 2026-10-24 (planning archive for #376).
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the script is absent and
# these skip; devtools::test() from the source tree runs them.

worker_prep_script <- function() {
  normalizePath(testthat::test_path("..", "..", "data-raw", "worker_prep.sh"),
    mustWork = FALSE
  )
}

# A world: an origin repo with branch `b`, a stub Rscript that prints
# FRESH_GIT_SHA when asked for it and otherwise succeeds, and a clone dir.
wprep_world <- function(env = parent.frame()) {
  testthat::skip_if_not(file.exists(worker_prep_script()), "data-raw/worker_prep.sh absent")
  d <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(d, "bin"))
  writeLines(c(
    "#!/bin/sh",
    'case "$*" in *FRESH_GIT_SHA*\\)\\)*) printf "%s" "${FRESH_GIT_SHA:-}"; exit 0 ;; esac',
    sprintf('echo "Rscript $*" >> %s/r_calls', shQuote(d)),
    "exit 0"
  ), file.path(d, "bin", "Rscript"))
  Sys.chmod(file.path(d, "bin", "Rscript"), "755")
  o <- file.path(d, "origin")
  git <- function(...) system2("git", c("-C", o, ...), stdout = FALSE, stderr = FALSE)
  dir.create(o)
  git("init", "-q", "-b", "b")
  writeLines("Remotes:\n    NewGraphEnvironment/fresh@v9.9.9", file.path(o, "DESCRIPTION"))
  git("add", "DESCRIPTION")
  git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "x")
  d
}

run_wprep <- function(world, env = character()) {
  base <- c(
    WORKER_PREP_BRANCH = "b", WORKER_PREP_ORIGIN = file.path(world, "origin"),
    WORKER_PREP_CONFIG = "default", WORKER_PREP_SCHEMA = "s",
    WORKER_PREP_DIR = file.path(world, "clone"),
    PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")
  )
  base[names(env)] <- env
  out <- withr::with_envvar(base, suppressWarnings(system2(
    "bash", c("-c", shQuote(paste("bash -s <", shQuote(worker_prep_script())))),
    stdout = TRUE, stderr = TRUE
  )))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

test_that("a first prep clones, and every prep resets the clone to the run's branch", {
  w <- wprep_world()
  r <- run_wprep(w)
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "=== READY$")
  # Something left in the clone is cleaned and the branch reset.
  writeLines("x", file.path(w, "clone", "stray.txt"))
  writeLines("changed", file.path(w, "clone", "DESCRIPTION"))
  r <- run_wprep(w)
  expect_equal(r$status, 0L, info = r$out)
  expect_false(file.exists(file.path(w, "clone", "stray.txt")))
  expect_match(readLines(file.path(w, "clone", "DESCRIPTION"))[1], "^Remotes:")
})

test_that("a directory that is not the driver's clone is refused, untouched", {
  w <- wprep_world()
  dir.create(file.path(w, "clone"))
  writeLines("mine", file.path(w, "clone", "notes.txt"))
  r <- run_wprep(w)
  expect_equal(r$status, 1L)
  expect_match(r$out, "is not a git clone", fixed = TRUE)
  expect_identical(readLines(file.path(w, "clone", "notes.txt")), "mine")
  unlink(file.path(w, "clone"), recursive = TRUE)
  expect_equal(run_wprep(w)$status, 0L)
  r <- run_wprep(w, c(WORKER_PREP_ORIGIN = file.path(w, "elsewhere")))
  expect_equal(r$status, 1L)
  expect_match(r$out, "not the driver's clone", fixed = TRUE)
})

test_that("the fresh install refuses a FRESH_GIT_SHA pin, and an unknown stage is refused", {
  w <- wprep_world()
  r <- run_wprep(w, c(WORKER_PREP_STAGE = "install-fresh", FRESH_GIT_SHA = "abc1234"))
  expect_equal(r$status, 1L)
  expect_match(r$out, "FRESH_GIT_SHA is set on this worker", fixed = TRUE)
  calls <- file.path(w, "r_calls")
  installed <- file.exists(calls) && any(grepl("pkg_install", readLines(calls), fixed = TRUE))
  expect_false(installed)
  r <- run_wprep(w, c(WORKER_PREP_STAGE = "install-fresh", FRESH_GIT_SHA = ""))
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "=== installing NewGraphEnvironment/fresh@v9.9.9", fixed = TRUE)
  expect_match(r$out, "=== READY (fresh install only)", fixed = TRUE)
  r <- run_wprep(w, c(WORKER_PREP_STAGE = "snapshot"))
  expect_equal(r$status, 1L)
  expect_match(r$out, "must be 'all' or 'install-fresh'", fixed = TRUE)
})

test_that("the script parses under macOS's bash 3.2, as a worker runs it", {
  skip_if_not(file.exists(worker_prep_script()), "data-raw/worker_prep.sh absent")
  skip_if_not(file.exists("/bin/bash"), "no /bin/bash")
  # An apostrophe in a comment inside its single-quoted R programs ends the
  # quote; this has happened three times while writing it.
  out <- suppressWarnings(system2("/bin/bash", c("-n", shQuote(worker_prep_script())),
    stdout = TRUE, stderr = TRUE
  ))
  expect_null(attr(out, "status"), label = paste(out, collapse = "\n"))
})
