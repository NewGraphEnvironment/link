row <- function(host, ...) {
  d <- list(host = host, link_version = "0.46.0", link_sha = "NA",
            fresh_version = "0.33.0", fresh_sha = "7f12d99115b7",
            repo_sha = "abc123def456", repo_dirty = "FALSE",
            config_hash = "cfg012345678", fwapg_sha = "e6e1eb0aaaaa",
            r_version = "4.5.2")
  as.data.frame(utils::modifyList(d, list(...)), stringsAsFactors = FALSE)
}


test_that("parity passes when all hosts agree", {
  s <- rbind(row("m1"), row("cy-job1"), row("cy-job2"))
  res <- lnk_preflight_parity(s, n_expected = 3, quiet = TRUE)
  expect_true(res$ok)
  expect_identical(res$n, 3L)
  expect_identical(res$reference, "m1")
})

test_that("parity does NOT over-fire on link_sha, which is NA on installed hosts", {
  # The trap this design exists to avoid: link_sha is a real SHA on a
  # load_all dispatcher and NA on every pak-installed cypher. Comparing it
  # would fail every legitimate run, so it is reported and never keyed on.
  s <- rbind(row("m1", link_sha = "deadbeef1234"), row("cy-job1"))
  expect_true(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
})

test_that("parity DOES key on fresh_sha now that it resolves everywhere", {
  # The inverse of what this test asserted before link#264. It was excluded
  # because it was NA on both hosts, so comparing it was a vacuous NA == NA
  # pass. The dispatcher's value turned out to be sitting unread in the
  # installed DESCRIPTION, so the exclusion outlived its reason.
  #
  # A cypher on a different fresh BUILD at the same version string is
  # link#246 exactly, and fresh_version alone cannot see it.
  s <- rbind(row("m1"), row("cy-job1", fresh_sha = "abc999888777"))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$offenders, "cy-job1")
  expect_true("fresh_sha" %in% res$mismatches$field)
})

test_that("parity fails on a fresh_version mismatch and names the host", {
  # The literal #246 scenario: a cypher still on the image's fresh.
  s <- rbind(row("m1"), row("cy-job1", fresh_version = "0.31.0"))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$offenders, "cy-job1")
  expect_true("fresh_version" %in% res$mismatches$field)
  expect_match(res$message, "0.31.0", fixed = TRUE)
})

test_that("parity fails on a repo_sha mismatch", {
  s <- rbind(row("m1"), row("cy-job1", repo_sha = "000000000000"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
})

test_that("parity fails on a config_hash mismatch", {
  s <- rbind(row("m1"), row("cy-job1", config_hash = "cfgXXXXXXXXX"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
})

test_that("parity fails when a host did not report - a short table is not agreement", {
  s <- rbind(row("m1"), row("cy-job1"))
  res <- lnk_preflight_parity(s, n_expected = 3, quiet = TRUE)
  expect_false(res$ok)
  expect_match(res$message, "did not report")
})

test_that("parity fails on ZERO rows", {
  # A loop that collected nothing must not produce "no mismatches found".
  res <- lnk_preflight_parity(row("m1")[0, ], n_expected = 3, quiet = TRUE)
  expect_false(res$ok)
})

test_that("parity fails on an unresolved fwapg_sha - NA == NA is not agreement", {
  s <- rbind(row("m1", fwapg_sha = "NA"), row("cy-job1", fwapg_sha = "NA"))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_match(res$message, "fwapg_sha unresolved")
})

test_that("parity fails on an unresolved fresh_sha on EVERY host", {
  # Both hosts NA is the pre-link#264 steady state, and it used to pass. It
  # is the state where nobody can say which fresh build produced the run, so
  # it has to fail rather than agree with itself.
  s <- rbind(row("m1", fresh_sha = "NA"), row("cy-job1", fresh_sha = "NA"))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_match(res$message, "fresh_sha unresolved")

  # And on one host only -- link#246's failure, where a cypher ran the
  # image's fresh instead of the DESCRIPTION Remotes pin.
  s1 <- rbind(row("m1"), row("cy-job1", fresh_sha = "NA"))
  res1 <- lnk_preflight_parity(s1, n_expected = 2, quiet = TRUE)
  expect_false(res1$ok)
  expect_match(res1$message, "cy-job1")
})

test_that("parity fails on an empty-string field, not just the literal NA", {
  s <- rbind(row("m1", repo_sha = ""), row("cy-job1"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
})

test_that("parity fails when any host is dirty", {
  s <- rbind(row("m1", repo_dirty = "TRUE"), row("cy-job1"))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_match(res$message, "dirty checkout")
})

test_that("parity errors loudly on a malformed stamps table", {
  expect_error(lnk_preflight_parity(data.frame(host = "m1"), n_expected = 1),
               "missing column")
})

test_that("parity requires n_expected - it has no default", {
  expect_error(lnk_preflight_parity(row("m1")))
})

test_that("a single-host run with n_expected = 1 passes", {
  expect_true(lnk_preflight_parity(row("m1"), n_expected = 1, quiet = TRUE)$ok)
})


test_that("lnk_preflight_stamp returns the documented field order", {
  # An honest scope note: this asserts the stamp matches its own declared
  # contract. It does NOT prove the shell agrees, and an earlier version of
  # this comment claimed it did while comparing R against R. The shell now
  # calls .lnk_preflight_stamp_cols() directly for col.names, so there is no
  # second list to diverge from - the duplication was removed rather than
  # tested around.
  s <- lnk_preflight_stamp(lnk_config("bcfishpass"))
  expect_identical(names(s), .lnk_preflight_stamp_cols())
  expect_true(all(nzchar(s)))          # never empty; the literal "NA" instead
  expect_type(s, "character")
})

test_that("a stamp is judgeable by the parity function it feeds", {
  # Guards the seam: the collector's output must satisfy the judge's
  # column contract, or the gate errors at run time on a live host.
  s <- lnk_preflight_stamp(lnk_config("bcfishpass"))
  df <- as.data.frame(as.list(s), stringsAsFactors = FALSE)
  expect_no_error(lnk_preflight_parity(df, n_expected = 1, quiet = TRUE))
})

test_that("an unresolved field survives the TSV round-trip the shell performs", {
  # The version of this test that built the frame in R passed while the real
  # gate was broken: the shell writes stamps to a TSV and reads them with
  # read.delim(), whose default na.strings = "NA" turned the deliberate "NA"
  # sentinel into a real NA. `%in% c("NA","")` did not match it and `!=`
  # dropped it, so a run with fwapg_sha unresolved on EVERY host printed
  # "host parity clean". Reproduced 2026-08-30, then fixed on both sides.
  #
  # This test crosses the seam: write the file the way collect_stamps() does,
  # read it back the way judge_stamps() does.
  cols <- .lnk_preflight_stamp_cols()
  mk <- function(host, fwapg) {
    v <- c(host, "0.47.0", "abc123def456", "0.33.0", "NA",
           "deadbeef0001", "FALSE", "cfg012345678", fwapg, "4.5.2")
    paste(v, collapse = "\t")
  }
  tsv <- withr::local_tempfile()
  writeLines(c(mk("m1", "NA"), mk("cy-job1", "NA")), tsv)

  s <- utils::read.delim(tsv, header = FALSE, colClasses = "character",
                         na.strings = character(0), col.names = cols)
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
  expect_match(res$message, "fwapg_sha unresolved")

  # And the belt: even parsed with read.delim's defaults, where the sentinel
  # has already become a real NA, the judge must still refuse it.
  s_na <- utils::read.delim(tsv, header = FALSE, colClasses = "character",
                            col.names = cols)
  expect_true(all(is.na(s_na$fwapg_sha)))       # premise: the NAs are real
  expect_false(lnk_preflight_parity(s_na, n_expected = 2, quiet = TRUE)$ok)
})

test_that("a real NA in a key field is a mismatch, not silent agreement", {
  # `!=` returns NA for an NA operand and which() drops it, so without
  # normalisation a host whose field failed to parse would agree with
  # everything.
  s <- rbind(row("m1"), row("cy-job1", repo_sha = NA_character_))
  res <- lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)
  expect_false(res$ok)
})

test_that(".lnk_repo_git_state reports NA for a non-git directory", {
  d <- withr::local_tempdir()
  g <- .lnk_repo_git_state(d)
  expect_true(is.na(g$sha))
  expect_true(is.na(g$dirty))
})

test_that("a non-git host stamp fails parity rather than passing vacuously", {
  s <- rbind(row("m1"), row("cy-job1", repo_sha = "NA", repo_dirty = "NA"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
})


test_that("forbid_dirty = FALSE lets a dirty-but-agreeing pair pass", {
  # The post-prep parity check must pass this: by then BOTH hosts are dirty by
  # their own normal operation — the dispatcher has written run logs into the
  # tracked data-raw/logs/, and snapshot_bcfp.sh has stamped
  # bcfp_baselines.csv on the cypher. With forbid_dirty left on (the default),
  # the gate fired on every real run. Found by the link#246 pilot 2026-08-31;
  # the original tests could not catch it because they set dirty = "FALSE".
  s <- rbind(row("m1", repo_dirty = "TRUE"), row("cy-job1", repo_dirty = "TRUE"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
  expect_true(lnk_preflight_parity(s, n_expected = 2, forbid_dirty = FALSE,
                                   quiet = TRUE)$ok)
})

test_that("forbid_dirty = FALSE still catches a real divergence", {
  # Turning the dirty check off must not turn the gate off.
  s <- rbind(row("m1", repo_dirty = "TRUE"),
             row("cy-job1", repo_dirty = "TRUE", repo_sha = "000000000000"))
  expect_false(lnk_preflight_parity(s, n_expected = 2, forbid_dirty = FALSE,
                                    quiet = TRUE)$ok)
  s2 <- rbind(row("m1", repo_dirty = "TRUE"),
              row("cy-job1", repo_dirty = "TRUE", fresh_version = "0.31.0"))
  expect_false(lnk_preflight_parity(s2, n_expected = 2, forbid_dirty = FALSE,
                                    quiet = TRUE)$ok)
})
