# lnk_stamp captures a structured snapshot of every input that
# influences a habitat-classification run. Tests cover the no-DB path,
# stamp_finish workflow, markdown rendering, and validation.

test_that("lnk_stamp rejects non-lnk_config input", {
  expect_error(lnk_stamp(list()), "must be an lnk_config")
  expect_error(lnk_stamp(NULL), "must be an lnk_config")
})

test_that("lnk_stamp rejects bad aoi", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_stamp(cfg, aoi = ""), "non-empty string")
  expect_error(lnk_stamp(cfg, aoi = c("a", "b")), "non-empty string")
})

test_that("lnk_stamp returns lnk_stamp S3 with expected slots", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_s3_class(s, "lnk_stamp")
  expect_setequal(names(s),
    c("config_name", "config_dir", "config_hash", "config_drift",
      "host", "fwapg_sha", "bcfishobs_sha", "provenance",
      "software", "db", "run", "result"))
  expect_equal(s$config_name, "bcfishpass")
  expect_equal(s$run$aoi, "ADMS")
  expect_null(s$run$end_time)
  expect_null(s$result)
  expect_null(s$db)  # no conn, db should be NULL
})

test_that("lnk_stamp software slot has link + fresh + R", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_setequal(names(s$software), c("link", "fresh", "R"))
  expect_match(s$software$link$version, "^\\d+\\.\\d+\\.\\d+$")
  expect_match(s$software$R, "^R version")
})

test_that("lnk_stamp provenance slot is the verify tibble", {
  testthat::skip_if_not_installed("digest")
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_s3_class(s$provenance, "data.frame")
  expect_named(s$provenance,
               c("file",
                 "byte_expected", "byte_observed", "byte_drift",
                 "shape_expected", "shape_observed", "shape_drift",
                 "missing"))
  expect_equal(sum(s$provenance$byte_drift), 0L)
  expect_equal(sum(s$provenance$shape_drift), 0L)
})

test_that("lnk_stamp handles config without provenance block", {
  tmp <- withr::local_tempdir()
  file.create(file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"), row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(tmp, "params.csv"),
            row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(parameters_fresh = list(path = "params.csv"))
    ),
    file.path(tmp, "config.yaml")
  )
  cfg <- lnk_config(tmp)
  s <- lnk_stamp(cfg, aoi = "TEST")
  expect_null(s$provenance)
})

test_that("lnk_stamp_finish sets end_time and result", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  Sys.sleep(0.05)
  s <- lnk_stamp_finish(s, result = data.frame(x = 1:3))
  expect_true(!is.null(s$run$end_time))
  expect_true(s$run$end_time > s$run$start_time)
  expect_s3_class(s$result, "data.frame")
  expect_equal(nrow(s$result), 3L)
})

test_that("lnk_stamp_finish rejects non-lnk_stamp input", {
  expect_error(lnk_stamp_finish(list()), "must be an lnk_stamp")
})

test_that("format(stamp, 'markdown') produces structured output", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  md <- format(s, "markdown")
  expect_type(md, "character")
  expect_length(md, 1L)
  expect_match(md, "## Run stamp", fixed = TRUE)
  expect_match(md, "AOI: `ADMS`", fixed = TRUE)
  expect_match(md, "### Software", fixed = TRUE)
  expect_match(md, "### Config provenance", fixed = TRUE)
})

test_that("format(stamp, 'markdown') includes ended + elapsed when finished", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  Sys.sleep(0.05)
  s <- lnk_stamp_finish(s)
  md <- format(s, "markdown")
  expect_match(md, "Ended:", fixed = TRUE)
  expect_match(md, "elapsed", fixed = TRUE)
})

test_that("format(stamp) defaults to markdown", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_identical(format(s), format(s, "markdown"))
})

test_that("format(stamp, 'text') runs without error", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  txt <- format(s, "text")
  expect_type(txt, "character")
  expect_match(txt, "<lnk_stamp>", fixed = TRUE)
})

test_that("print.lnk_stamp returns the stamp invisibly", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  out <- capture.output(r <- print(s))
  expect_identical(r, s)
  expect_match(paste(out, collapse = "\n"), "<lnk_stamp>", fixed = TRUE)
})

test_that("lnk_stamp db slot is NULL when conn is NULL", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, conn = NULL, aoi = "ADMS")
  expect_null(s$db)
})

test_that("lnk_stamp db slot is NULL when db_snapshot = FALSE even with conn", {
  cfg <- lnk_config("bcfishpass")
  conn <- structure(list(), class = "DBIConnection")  # mock conn
  s <- lnk_stamp(cfg, conn = conn, aoi = "ADMS", db_snapshot = FALSE)
  expect_null(s$db)
})

# -- HEAD of a worktree, and of a packed ref (link#369) ----------------------

test_that(".lnk_read_git_head resolves a worktree's branch in the common dir", {
  d <- withr::local_tempdir()
  common <- file.path(d, "repo", ".git")
  wt_git <- file.path(common, "worktrees", "wt")
  dir.create(file.path(common, "refs", "heads"), recursive = TRUE)
  dir.create(wt_git, recursive = TRUE)
  sha <- "8d0a18220000000000000000000000000000abcd"
  writeLines(sha, file.path(common, "refs", "heads", "369-run"))
  writeLines("ref: refs/heads/369-run", file.path(wt_git, "HEAD"))
  writeLines("../..", file.path(wt_git, "commondir"))
  wt <- file.path(d, "wt")
  dir.create(wt)
  writeLines(paste0("gitdir: ", wt_git), file.path(wt, ".git"))
  expect_identical(.lnk_read_git_head(file.path(wt, ".git")), sha)
})

test_that(".lnk_read_git_head reads a branch that lives only in packed-refs", {
  d <- withr::local_tempdir()
  git <- file.path(d, ".git")
  dir.create(git)
  writeLines("ref: refs/heads/main", file.path(git, "HEAD"))
  writeLines(c("# pack-refs with: peeled fully-peeled sorted",
               "1111111111111111111111111111111111111111 refs/heads/main-old",
               "2222222222222222222222222222222222222222 refs/heads/main",
               "^3333333333333333333333333333333333333333"),
             file.path(git, "packed-refs"))
  expect_identical(.lnk_read_git_head(git), "2222222222222222222222222222222222222222")
})

test_that(".lnk_read_git_head reads this checkout's HEAD as git does", {
  root <- normalizePath(testthat::test_path("..", ".."))
  skip_if_not(file.exists(file.path(root, ".git")), "not a git checkout")
  git <- Sys.which("git")
  skip_if(!nzchar(git), "git not on PATH")
  want <- system2(git, c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE)
  expect_identical(.lnk_read_git_head(file.path(root, ".git")), want)
})
