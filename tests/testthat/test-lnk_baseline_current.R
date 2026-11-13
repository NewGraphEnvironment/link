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
    run_label           = "snapshot-20260508",
    link_schema         = "n/a",
    bcfp_model_run_id   = "",
    bcfp_model_version  = "v0.7.14-125-g6e9cf1c",
    bcfp_date_completed = "2026-05-06T04:15:41Z",
    notes               = ""
  )
  modifyList(defaults, list(...))
}

test_that("lnk_baseline_current returns TRUE when latest row matches model_version", {
  rows <- do.call(rbind, list(
    as.data.frame(base_row(run_started_pdt = "2026-05-01 09:00",
                           bcfp_model_version = "v0.7.14-100-gOLD")),
    as.data.frame(base_row(run_started_pdt = "2026-05-08 10:00",
                           bcfp_model_version = "v0.7.14-125-g6e9cf1c"))
  ))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_true(lnk_baseline_current(log, host = "test-host", path = path))
})

test_that("lnk_baseline_current returns FALSE when latest row's version differs", {
  rows <- as.data.frame(base_row(bcfp_model_version = "v0.7.14-100-gOLD"))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_false(lnk_baseline_current(log, host = "test-host", path = path))
})

test_that("lnk_baseline_current returns FALSE when no rows for host", {
  rows <- as.data.frame(base_row(host = "other-host"))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_false(lnk_baseline_current(log, host = "test-host", path = path))
})

test_that("lnk_baseline_current returns FALSE when ledger file is missing", {
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_false(lnk_baseline_current(log,
                                   host = "test-host",
                                   path = tempfile(fileext = ".csv")))
})

test_that("lnk_baseline_current picks LATEST row for host (per-host scoping)", {
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
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_true(lnk_baseline_current(log, host = "m4", path = path))
  expect_false(lnk_baseline_current(log, host = "m1", path = path))
})

test_that("lnk_baseline_current validates argument shapes", {
  log <- list(model_version = "v1")
  expect_error(lnk_baseline_current("not a list"))
  expect_error(lnk_baseline_current(list()))                       # missing key
  expect_error(lnk_baseline_current(list(model_version = "")))     # empty
  expect_error(lnk_baseline_current(list(model_version = c("a", "b"))))
  expect_error(lnk_baseline_current(log, host = ""))
  expect_error(lnk_baseline_current(log, path = ""))
})


# --- link#276 / link#446: what counts as current ------------------------------

test_that("the same version built later is not current (link#276)", {
  # bcfishpass rebuilt v0.7.15-47-ga702229 on 2026-09-01 from the commit its
  # 2026-08-18 build used; m1 skipped on the version alone and kept the older.
  rows <- as.data.frame(base_row(bcfp_model_version = "v0.7.15-47-ga702229",
                                 bcfp_date_completed = "2026-08-19T04:31:37Z"))
  path <- make_ledger(rows)
  later <- list(model_version = "v0.7.15-47-ga702229", date_completed = "2026-09-02T03:10:53Z")
  expect_false(lnk_baseline_current(later, host = "test-host", path = path))
  same <- list(model_version = "v0.7.15-47-ga702229", date_completed = "2026-08-19T04:31:37Z")
  expect_true(lnk_baseline_current(same, host = "test-host", path = path))
})

test_that("a csv-sync row does not make a host current (link#446)", {
  rows <- do.call(rbind, list(
    as.data.frame(base_row(run_started_pdt = "2026-05-01 09:00",
                           bcfp_model_version = "v0.7.14-100-gOLD")),
    as.data.frame(base_row(run_started_pdt = "2026-05-08 10:00",
                           run_label = "csv-sync-20260508"))
  ))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_false(lnk_baseline_current(log, host = "test-host", path = path))
})

test_that("with views = TRUE only a row that loaded the views counts", {
  rows <- as.data.frame(base_row(notes = "manual snapshot via data-raw/snapshot_bcfp.sh; head_sha=6e9cf1c"))
  path <- make_ledger(rows)
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_true(lnk_baseline_current(log, host = "test-host", path = path))
  expect_false(lnk_baseline_current(log, host = "test-host", path = path, views = TRUE))
  rows$notes <- "manual snapshot via data-raw/snapshot_bcfp.sh; --with-bcfp-views; head_sha=6e9cf1c"
  path <- make_ledger(rows)
  expect_true(lnk_baseline_current(log, host = "test-host", path = path, views = TRUE))
})

test_that("the default host is the name rows are written under (LNK_HOST_ALIAS)", {
  withr::local_envvar(LNK_HOST_ALIAS = "test-host")
  path <- make_ledger(as.data.frame(base_row()))
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_true(lnk_baseline_current(log, path = path))
})

test_that("a row whose build date is not an instant is not current", {
  path <- make_ledger(as.data.frame(base_row(bcfp_date_completed = "2026-05-06 04:15")))
  log <- list(model_version = "v0.7.14-125-g6e9cf1c", date_completed = "2026-05-06T04:15:41Z")
  expect_false(lnk_baseline_current(log, host = "test-host", path = path))
})
