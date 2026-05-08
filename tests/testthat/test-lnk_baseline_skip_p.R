make_ledger <- function(rows) {
  hdr <- c("run_started_pdt", "host", "run_label", "link_schema",
           "bcfp_model_run_id", "bcfp_model_version",
           "bcfp_date_completed", "notes")
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(rows, tmp, row.names = FALSE)
  # Ensure header order matches cols_baseline.
  df <- utils::read.csv(tmp, stringsAsFactors = FALSE,
                        colClasses = "character")
  utils::write.csv(df[, hdr, drop = FALSE], tmp, row.names = FALSE)
  tmp
}

base_row <- function(...) {
  defaults <- list(
    run_started_pdt     = "2026-05-08 10:00",
    host                = "test-host",
    run_label           = "snapshot",
    link_schema         = "n/a",
    bcfp_model_run_id   = "",
    bcfp_model_version  = "v0.7.14-125-g6e9cf1c",
    bcfp_date_completed = "2026-05-06T04:15:41Z",
    notes               = ""
  )
  modifyList(defaults, list(...))
}

test_that("lnk_baseline_skip_p returns TRUE when latest row matches model_version", {
  rows <- do.call(rbind, list(
    as.data.frame(base_row(run_started_pdt = "2026-05-01 09:00",
                           bcfp_model_version = "v0.7.14-100-gOLD")),
    as.data.frame(base_row(run_started_pdt = "2026-05-08 10:00",
                           bcfp_model_version = "v0.7.14-125-g6e9cf1c"))
  ))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c")
  expect_true(lnk_baseline_skip_p(log, host = "test-host", path = path))
})

test_that("lnk_baseline_skip_p returns FALSE when latest row's version differs", {
  rows <- as.data.frame(base_row(bcfp_model_version = "v0.7.14-100-gOLD"))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c")
  expect_false(lnk_baseline_skip_p(log, host = "test-host", path = path))
})

test_that("lnk_baseline_skip_p returns FALSE when no rows for host", {
  rows <- as.data.frame(base_row(host = "other-host"))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c")
  expect_false(lnk_baseline_skip_p(log, host = "test-host", path = path))
})

test_that("lnk_baseline_skip_p returns FALSE when ledger file is missing", {
  log <- list(model_version = "v0.7.14-125-g6e9cf1c")
  expect_false(lnk_baseline_skip_p(log,
                                   host = "test-host",
                                   path = tempfile(fileext = ".csv")))
})

test_that("lnk_baseline_skip_p picks LATEST row for host (per-host scoping)", {
  # M4 stamped this week's SHA; M1 has only an older row. M1 should NOT skip.
  rows <- do.call(rbind, list(
    as.data.frame(base_row(host = "m4",
                           run_started_pdt = "2026-05-08 05:00",
                           bcfp_model_version = "v0.7.14-125-g6e9cf1c")),
    as.data.frame(base_row(host = "m1",
                           run_started_pdt = "2026-05-01 05:00",
                           bcfp_model_version = "v0.7.14-100-gOLD"))
  ))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c")
  expect_true(lnk_baseline_skip_p(log, host = "m4", path = path))
  expect_false(lnk_baseline_skip_p(log, host = "m1", path = path))
})

test_that("lnk_baseline_skip_p validates argument shapes", {
  log <- list(model_version = "v1")
  expect_error(lnk_baseline_skip_p("not a list"))
  expect_error(lnk_baseline_skip_p(list()))                       # missing key
  expect_error(lnk_baseline_skip_p(list(model_version = "")))     # empty
  expect_error(lnk_baseline_skip_p(list(model_version = c("a", "b"))))
  expect_error(lnk_baseline_skip_p(log, host = ""))
  expect_error(lnk_baseline_skip_p(log, path = ""))
})
