now <- as.POSIXct("2026-08-30 12:00:00", tz = "UTC")
all_four <- .lnk_vintage_primitives()

# Build a vintage frame from named ages in days.
v <- function(ages) {
  data.frame(table_name = names(ages),
             last_analyze = now - unname(ages) * 86400,
             stringsAsFactors = FALSE)
}
fresh_ages <- function() stats::setNames(rep(2, length(all_four)), all_four)


test_that(".lnk_vintage_primitives selects the snapshot-loaded tables only", {
  # The seven FWA tables are bulk-restored and never ANALYZEd, so including
  # them would fail every host forever on data that is not the staleness risk.
  expect_setequal(all_four,
    c("bcfishobs.observations", "whse_fish.pscis_assessment_svw",
      "cabd.dams", "fresh.modelled_stream_crossings"))
  expect_false(any(grepl("^whse_basemapping\\.", all_four)))
})

test_that("vintage passes when every primitive is inside the window", {
  res <- lnk_preflight_vintage(vintage = v(fresh_ages()), now = now,
                               max_age_days = 7, quiet = TRUE)
  expect_true(res$ok)
  expect_length(res$stale, 0L)
  expect_length(res$missing, 0L)
})

test_that("vintage fails when one primitive is outside the window", {
  # cabd.dams at 2026-05-23 against a 2026-08-30 run — the real dispatcher
  # state that motivated the gate.
  ages <- fresh_ages()
  ages[["cabd.dams"]] <- 99
  res <- lnk_preflight_vintage(vintage = v(ages), now = now,
                               max_age_days = 7, quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$stale, "cabd.dams")
  expect_match(res$message, "cabd.dams", fixed = TRUE)
})

test_that("vintage boundary: exactly max_age_days passes, a hair more fails", {
  ages <- stats::setNames(rep(7, length(all_four)), all_four)
  expect_true(lnk_preflight_vintage(vintage = v(ages), now = now,
                                    max_age_days = 7, quiet = TRUE)$ok)
  ages[[1]] <- 7 + 1 / 24
  expect_false(lnk_preflight_vintage(vintage = v(ages), now = now,
                                     max_age_days = 7, quiet = TRUE)$ok)
})

test_that("a NULL timestamp FAILS - never loaded is not fresh", {
  x <- v(fresh_ages())
  x$last_analyze[2] <- NA
  res <- lnk_preflight_vintage(vintage = x, now = now, quiet = TRUE)
  expect_false(res$ok)
  expect_true(all_four[2] %in% res$missing)
})

test_that("an EMPTY result set FAILS - zero rows is not a pass", {
  # The failure this gate exists to avoid inheriting: a query that returns
  # nothing must not read as "nothing is stale".
  empty <- data.frame(table_name = character(0),
                      last_analyze = as.POSIXct(character(0)),
                      stringsAsFactors = FALSE)
  res <- lnk_preflight_vintage(vintage = empty, now = now, quiet = TRUE)
  expect_false(res$ok)
  expect_setequal(res$missing, all_four)
})

test_that("a partial result FAILS and names the absent table", {
  ages <- fresh_ages()[-1]
  res <- lnk_preflight_vintage(vintage = v(ages), now = now, quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$missing, all_four[1])
})

test_that("extra unrequested tables cannot mask a missing required one", {
  x <- v(c(some.other_table = 1))
  res <- lnk_preflight_vintage(vintage = x, now = now, quiet = TRUE)
  expect_false(res$ok)
  expect_setequal(res$missing, all_four)
})

test_that(".lnk_vintage_read returns an empty frame of the right shape on NULL conn", {
  out <- .lnk_vintage_read(NULL, all_four)
  expect_s3_class(out, "data.frame")
  expect_identical(nrow(out), 0L)
  expect_true(all(c("table_name", "last_analyze") %in% names(out)))
})

test_that("lnk_preflight_vintage validates its arguments", {
  x <- v(fresh_ages())
  expect_error(lnk_preflight_vintage(vintage = x, max_age_days = 0))
  expect_error(lnk_preflight_vintage(vintage = x, max_age_days = NA))
  expect_error(lnk_preflight_vintage(vintage = x, max_age_days = -1))
  expect_error(lnk_preflight_vintage(vintage = x, tables = character(0)))
  expect_error(lnk_preflight_vintage(vintage = data.frame(a = 1)))
})
