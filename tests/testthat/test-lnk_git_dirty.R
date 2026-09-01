# The link_dirty predicate (link#257 / link#262).
#
# These run against a REAL temp checkout, not a mock. The defect being guarded
# is in what `git` is ASKED — a pathspec, and its survival through system2()'s
# argument handling — so a mocked return value is structurally incapable of
# seeing it. Two known answers per case, never one.

skip_if_no_git <- function() {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
}

# A throwaway repo shaped like link: tracked code under R/, tracked run logs
# under data-raw/logs/. Committed clean, so every later state is one the test
# created deliberately.
local_repo <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  run <- function(...) {
    out <- suppressWarnings(system2("git", c("-C", shQuote(d), ...),
                                    stdout = TRUE, stderr = FALSE))
    st <- attr(out, "status")
    if (!is.null(st) && !identical(as.integer(st), 0L)) {
      stop("git setup failed: ", paste(c(...), collapse = " "))
    }
    invisible(out)
  }
  dir.create(file.path(d, "R"))
  dir.create(file.path(d, "data-raw", "logs"), recursive = TRUE)
  writeLines("f <- function() 1", file.path(d, "R", "f.R"))
  writeLines("run 1 ok", file.path(d, "data-raw", "logs", "prior.log"))
  run("init", "-q", ".")
  run("add", "-A")
  run("-c", "user.email=t@example.com", "-c", "user.name=t",
      "commit", "-qm", "init")
  d
}


test_that("a clean checkout reads clean (the premise the rest depends on)", {
  skip_if_no_git()
  d <- local_repo()
  expect_false(.lnk_git_dirty_at(d))
})

test_that("the run's own logs do NOT mark the tree dirty", {
  skip_if_no_git()
  d <- local_repo()

  # Exactly what study_area_run.sh does to its own checkout while it runs:
  # appends to a tracked log and drops new ones in beside it. On 2026-08-31
  # this state produced link_dirty = t on all 21 dispatcher rows.
  cat("more output\n", file = file.path(d, "data-raw", "logs", "prior.log"),
      append = TRUE)
  writeLines("new run", file.path(d, "data-raw", "logs", "20260901_run.log"))
  dir.create(file.path(d, "data-raw", "logs", "20260901_recompute.d"))
  writeLines("job", file.path(d, "data-raw", "logs", "20260901_recompute.d",
                              "PINE.log"))

  # Premise: git genuinely sees changes here. Without this the test would pass
  # for a predicate that reports clean unconditionally.
  bare <- system2("git", c("-C", shQuote(d), "status", "--porcelain"),
                  stdout = TRUE, stderr = FALSE)
  expect_gt(length(bare), 0L)

  expect_false(.lnk_git_dirty_at(d))
})

test_that("a modified TRACKED source file marks the tree dirty", {
  skip_if_no_git()
  d <- local_repo()
  cat("g <- function() 2\n", file = file.path(d, "R", "f.R"), append = TRUE)
  expect_true(.lnk_git_dirty_at(d))
})

test_that("a NEW UNTRACKED source file marks the tree dirty", {
  skip_if_no_git()
  d <- local_repo()
  # Deliberate: --untracked-files=no would report this clean. A cypher does
  # `git reset --hard origin/<branch>` and cannot see an uncommitted file, so
  # it is exactly the drift the flag exists to detect.
  writeLines("h <- function() 3", file.path(d, "R", "new.R"))
  expect_true(.lnk_git_dirty_at(d))
})

test_that("a dirty source file still reads dirty alongside dirty logs", {
  skip_if_no_git()
  d <- local_repo()
  # The realistic mid-run state. The exclusion must not swallow the signal
  # merely because log noise is present at the same time.
  cat("more\n", file = file.path(d, "data-raw", "logs", "prior.log"),
      append = TRUE)
  cat("g <- function() 2\n", file = file.path(d, "R", "f.R"), append = TRUE)
  expect_true(.lnk_git_dirty_at(d))
})

test_that("a non-repo directory yields NA, never FALSE", {
  skip_if_no_git()
  d <- withr::local_tempdir()
  # git fails here. The answer must be "cannot tell", because a failure read
  # as clean is a SHA silently certified against an unknown tree.
  expect_true(is.na(.lnk_git_dirty_at(d)))
})

test_that("the pathspec survives system2's argument handling", {
  # Regression for the bug caught on the first probe of this work: system2()
  # shell-quotes the command and pastes arguments on RAW, so the parentheses
  # in `:(top,exclude)` were parsed by the shell —
  #   sh: -c: line 0: syntax error near unexpected token `('
  # — the command never ran, and the predicate returned NA for every input.
  # It failed toward NA rather than toward a wrong boolean, which is why it
  # was invisible without running it.
  skip_if_no_git()
  d <- local_repo()
  cat("g <- function() 2\n", file = file.path(d, "R", "f.R"), append = TRUE)

  # NA here means the command did not execute. The value must be a real
  # boolean, which is only possible if the pathspec reached git intact.
  expect_false(is.na(.lnk_git_dirty_at(d)))
  expect_true(.lnk_git_dirty_at(d))
})

test_that("the pathspec excludes at the repo root regardless of cwd", {
  skip_if_no_git()
  d <- local_repo()
  # `:(top,...)` anchors at the repo root. A cwd-relative form would resolve
  # the exclude against a subdirectory, naming a path that does not exist,
  # while `.` narrowed the scan — silently missing changes one level up.
  cat("more\n", file = file.path(d, "data-raw", "logs", "prior.log"),
      append = TRUE)
  expect_false(.lnk_git_dirty_at(file.path(d, "R")))

  cat("g <- function() 2\n", file = file.path(d, "R", "f.R"), append = TRUE)
  expect_true(.lnk_git_dirty_at(file.path(d, "R")))
})

test_that("the env override still wins over any git state", {
  skip_if_no_git()
  withr::local_envvar(LINK_GIT_DIRTY = "1")
  expect_true(.lnk_pkg_git_dirty("link"))
  withr::local_envvar(LINK_GIT_DIRTY = "0")
  expect_false(.lnk_pkg_git_dirty("link"))
})
