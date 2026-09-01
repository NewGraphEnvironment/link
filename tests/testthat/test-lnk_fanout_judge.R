rcf <- function(job, rc) {
  data.frame(job = as.character(job), rc = as.character(rc),
             stringsAsFactors = FALSE)
}
none <- function() rcf(character(0), character(0))

test_that("all jobs reported and all succeeded is ok", {
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS", "ADMS"), c("0", "0", "0")),
                          expected = c("BULK", "PARS", "ADMS"), quiet = TRUE)
  expect_true(res$ok)
  expect_equal(res$status, "ok")
  expect_equal(res$n_ok, 3L)
  expect_equal(res$n_expected, 3L)
  expect_length(res$failed, 0L)
  expect_length(res$missing, 0L)
})

test_that("an empty expected set fails - a fan-out over nothing exits 0", {
  # The whole reason this function exists. A loop over an empty list and a
  # loop over a fully successful list are indistinguishable from the outside.
  res <- lnk_fanout_judge(none(), expected = character(0), quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "none_expected")
  expect_match(paste(res$problems, collapse = "\n"), "no jobs were expected")
})

test_that("allow_empty flips the verdict without turning the branch off", {
  res <- lnk_fanout_judge(none(), expected = character(0), allow_empty = TRUE,
                          quiet = TRUE)
  expect_true(res$ok)
  # Status is unchanged -- the caller opted in to an empty run, it did not
  # stop being one. A reader of the record can still see what happened.
  expect_equal(res$status, "none_expected")
})

test_that("allow_empty does not excuse a job that reported and FAILED", {
  # The previous test passes a NON-empty `expected`, which routes past the
  # none_expected branch entirely -- so its premise made this case
  # unreachable. Here `expected` IS empty, which is the branch allow_empty
  # governs, and a job still reported a non-zero status. allow_empty excuses
  # an empty expectation, not a failure.
  res <- lnk_fanout_judge(rcf("BULK", "1"), expected = character(0),
                          allow_empty = TRUE, quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "none_expected")
  expect_match(paste(res$problems, collapse = "\n"), "exited non-zero")

  # ...and the genuinely empty case still passes, so the flag is not simply
  # broken in the other direction.
  clean <- lnk_fanout_judge(none(), expected = character(0),
                            allow_empty = TRUE, quiet = TRUE)
  expect_true(clean$ok)
})

test_that("allow_empty does not excuse a non-empty run that failed", {
  # Guards the obvious mis-implementation: allow_empty short-circuiting the
  # whole function rather than just the empty branch.
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS"), c("0", "1")),
                          expected = c("BULK", "PARS"), allow_empty = TRUE,
                          quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "partial")
})

test_that("nothing reporting is none_ran, not all_failed", {
  # Different diagnosis: no job got far enough to record anything, which
  # points at the harness rather than at the work.
  res <- lnk_fanout_judge(none(), expected = c("BULK", "PARS", "ADMS", "HORS"),
                          quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "none_ran")
  expect_equal(res$n_missing, 4L)
  expect_setequal(res$missing, c("BULK", "PARS", "ADMS", "HORS"))
})

test_that("one failure among successes is partial and names the job", {
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS", "ADMS", "HORS"),
                              c("0", "1", "0", "0")),
                          expected = c("BULK", "PARS", "ADMS", "HORS"),
                          quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "partial")
  expect_equal(res$failed, "PARS")
  expect_equal(res$n_ok, 3L)
})

test_that("every reported job failing is all_failed", {
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS"), c("1", "2")),
                          expected = c("BULK", "PARS"), quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "all_failed")
  expect_equal(res$n_ok, 0L)
})

test_that("failed and never-reported are counted separately", {
  # The case a count-only implementation gets wrong: three of four reported,
  # all of them fine, one silently absent. n_failed must be 0 and n_missing 1
  # -- reporting it as a failure would send someone to read a log that does
  # not exist.
  res <- lnk_fanout_judge(rcf(c("BULK", "ADMS", "HORS"), c("0", "0", "0")),
                          expected = c("BULK", "PARS", "ADMS", "HORS"),
                          quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$status, "partial")
  expect_equal(res$n_failed, 0L)
  expect_equal(res$n_missing, 1L)
  expect_equal(res$missing, "PARS")
})

test_that("all_failed still reports how many are missing", {
  # Both facts must survive: nothing succeeded AND two never reported.
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS"), c("1", "1")),
                          expected = c("BULK", "PARS", "ADMS", "HORS"),
                          quiet = TRUE)
  expect_equal(res$status, "all_failed")
  expect_equal(res$n_missing, 2L)
  expect_setequal(res$missing, c("ADMS", "HORS"))
})

test_that("an unreadable exit status is a failure, never a neutral", {
  # as.integer("abc") is NA, NA != 0 is NA, and which() drops it -- so a
  # naive implementation counts these as successes.
  for (bad in list("", "abc", NA_character_, "NA", "0.0", " ")) {
    res <- lnk_fanout_judge(rcf(c("BULK", "PARS"), c("0", bad)),
                            expected = c("BULK", "PARS"), quiet = TRUE)
    expect_false(res$ok, info = paste("rc =", bad))
    expect_equal(res$failed, "PARS", info = paste("rc =", bad))
  }
})

test_that("a job reporting twice is a harness bug and fails", {
  res <- lnk_fanout_judge(rcf(c("BULK", "BULK", "PARS"), c("0", "0", "0")),
                          expected = c("BULK", "PARS"), quiet = TRUE)
  expect_false(res$ok)
  expect_match(paste(res$problems, collapse = "\n"), "more than once")
})

test_that("a job that was never asked for fails and is listed separately", {
  res <- lnk_fanout_judge(rcf(c("BULK", "PARS", "ZZZZ"), c("0", "0", "0")),
                          expected = c("BULK", "PARS"), quiet = TRUE)
  expect_false(res$ok)
  expect_equal(res$unexpected, "ZZZZ")
  expect_match(paste(res$problems, collapse = "\n"), "not asked for")
})

test_that("a duplicate in `expected` fails instead of reading as success", {
  # setdiff() deduplicates `missing` while n_expected counts the duplicate, so
  # unchecked this returns status "ok" with "1/2 job(s) succeeded" -- a clean
  # verdict over a list the caller got wrong. study_area_run.sh sorts -u, but
  # the sweep scripts pass an operator-supplied list straight through.
  res <- lnk_fanout_judge(rcf("BULK", "0"), expected = c("BULK", "BULK"),
                          quiet = TRUE)
  expect_false(res$ok)
  expect_match(paste(res$problems, collapse = "\n"),
               "listed more than once in `expected`")
  # The dedup must also correct the arithmetic, not just warn about it.
  expect_equal(res$n_expected, 1L)
  expect_equal(res$n_ok, 1L)
  expect_length(res$missing, 0L)
})

test_that("expected has no default and rc must carry both columns", {
  # Judging a table on its own terms is an affirmative claim of success about
  # jobs that never reported. Asserted rather than left as a comment.
  expect_error(lnk_fanout_judge(rcf("BULK", "0")))
  expect_error(lnk_fanout_judge(data.frame(job = "BULK"), expected = "BULK"),
               "missing column")
  expect_error(lnk_fanout_judge(data.frame(rc = "0"), expected = "BULK"),
               "missing column")
})

test_that("quiet controls the message and the label reaches it", {
  expect_silent(lnk_fanout_judge(rcf("BULK", "0"), expected = "BULK",
                                 quiet = TRUE))
  expect_message(
    lnk_fanout_judge(rcf("BULK", "0"), expected = "BULK",
                     label = "recompute"),
    "recompute")
})

test_that("the shell wrapper exits 0 only on a clean fan-out", {
  # The wrapper is what study_area_run.sh actually calls, so its exit status
  # is the contract. Covers the zero-byte-file branch, which read.delim()
  # would otherwise turn into a parse error indistinguishable from a verdict.
  # NOT skip_on_cran(): that would hide this from every non-interactive run,
  # which is exactly where a regression net has to fire. The honest guard is
  # whether the script is in this tree at all -- data-raw/ is .Rbuildignore'd,
  # so an installed package legitimately does not have it.
  script <- testthat::test_path("..", "..", "data-raw", "fanout_judge.R")
  skip_if_not(file.exists(script), "data-raw/fanout_judge.R not in this tree")
  rscript <- file.path(R.home("bin"), "Rscript")

  run <- function(lines, expected) {
    tsv <- withr::local_tempfile()
    if (length(lines)) writeLines(lines, tsv) else file.create(tsv)
    # LNK_LOAD=loadall, exactly as study_area_run.sh invokes it. Without it
    # the script does library(link) and reads the INSTALLED package, which on
    # a dev machine is routinely behind the source tree -- so the test would
    # be measuring the wrong copy. Caught here on the first real run of this
    # test: the installed link had no lnk_fanout_judge at all.
    suppressWarnings(system2(
      rscript, c(shQuote(script), shQuote(tsv), shQuote(expected), "recompute"),
      env = "LNK_LOAD=loadall", stdout = FALSE, stderr = FALSE))
  }

  expect_equal(run(c("BULK\t0", "PARS\t0"), "BULK,PARS"), 0L)
  expect_equal(run(c("BULK\t0", "PARS\t1"), "BULK,PARS"), 1L)
  expect_equal(run(character(0), "BULK,PARS"), 1L)   # empty file, jobs expected
  expect_equal(run(character(0), ""), 1L)            # nothing expected at all
  # A trailing comma must not invent a job id that can never report.
  expect_equal(run(c("BULK\t0", "PARS\t0"), "BULK,PARS,"), 0L)
})
