row <- function(host, ...) {
  d <- list(host = host, link_version = "0.46.0", link_sha = "NA",
            fresh_version = "0.33.0", fresh_sha = "NA",
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

test_that("parity does not key on fresh_sha either", {
  # And the mirror: keying on it would be a vacuous NA == NA pass.
  s <- rbind(row("m1"), row("cy-job1", fresh_sha = "abc999888777"))
  expect_true(lnk_preflight_parity(s, n_expected = 2, quiet = TRUE)$ok)
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
  # This is what keeps the shell's STAMP_COLS and the R field order from
  # silently diverging - the two-place contract this design accepts.
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
