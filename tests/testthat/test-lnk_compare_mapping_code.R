# Tests for lnk_compare_mapping_code — tunnel-free per-segment token compare (#175)

cfg_fixture <- function() lnk_config("bcfishpass")

test_that("lnk_compare_mapping_code validates arguments", {
  cfg <- cfg_fixture()
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_compare_mapping_code("notconn", "PARS", cfg))
  expect_error(lnk_compare_mapping_code(conn, "", cfg))
  expect_error(lnk_compare_mapping_code(conn, "toolongwsg", cfg))
  expect_error(lnk_compare_mapping_code(conn, "PARS", list()))
  expect_error(lnk_compare_mapping_code(conn, "PARS", cfg, reference = "nope"),
               "Unsupported reference")
  expect_error(lnk_compare_mapping_code(conn, "PARS", cfg, conn_ref = "notconn"))
})

test_that(".lnk_mc_diff computes per-species match stats + top mismatch pattern", {
  # Three segments share FWA position keys; bt differs on seg 3
  # (REAR vs REAR;DAM), co matches everywhere.
  link_mc <- data.frame(
    blue_line_key = c(1, 2, 3),
    downstream_route_measure = c(10, 20, 30),
    length_metre = c(5, 5, 5),
    mapping_code_bt = c("ACCESS;DAM", "SPAWN;DAM", "REAR"),
    mapping_code_co = c("ACCESS", "SPAWN", "REAR"),
    stringsAsFactors = FALSE)
  bcfp_mc <- data.frame(
    blue_line_key = c(1, 2, 3),
    downstream_route_measure = c(10, 20, 30),
    length_metre = c(5, 5, 5),
    mapping_code_bt = c("ACCESS;DAM", "SPAWN;DAM", "REAR;DAM"),
    mapping_code_co = c("ACCESS", "SPAWN", "REAR"),
    stringsAsFactors = FALSE)

  out <- link:::.lnk_mc_diff(link_mc, bcfp_mc, aoi = "PARS",
                             species = c("BT", "CO"))

  expect_equal(sort(out$species), c("BT", "CO"))
  bt <- out[out$species == "BT", ]
  co <- out[out$species == "CO", ]
  expect_equal(bt$total_segs, 3L)
  expect_equal(bt$match_pct, round(100 * 2 / 3, 2))
  expect_equal(bt$n_diffs, 1L)
  expect_equal(bt$top_pattern, "REAR | REAR;DAM")
  expect_equal(bt$top_pattern_count, 1L)
  expect_equal(co$match_pct, 100)
  expect_equal(co$n_diffs, 0L)
  expect_true(is.na(co$top_pattern))
})

test_that(".lnk_mc_diff NA-fills when reference has no rows for the WSG", {
  link_mc <- data.frame(
    blue_line_key = 1, downstream_route_measure = 10, length_metre = 5,
    mapping_code_bt = "ACCESS", stringsAsFactors = FALSE)
  bcfp_mc <- link_mc[0, ]
  expect_warning(
    out <- link:::.lnk_mc_diff(link_mc, bcfp_mc, aoi = "XXXX",
                               species = "BT"),
    "0 rows")
  expect_equal(out$total_segs, 0L)
  expect_true(is.na(out$match_pct))
})

test_that(".lnk_mc_diff errors on non-empty reference with no key overlap", {
  link_mc <- data.frame(
    blue_line_key = 1, downstream_route_measure = 10, length_metre = 5,
    mapping_code_bt = "ACCESS", stringsAsFactors = FALSE)
  bcfp_mc <- data.frame(
    blue_line_key = 999, downstream_route_measure = 99, length_metre = 9,
    mapping_code_bt = "ACCESS", stringsAsFactors = FALSE)
  expect_error(
    link:::.lnk_mc_diff(link_mc, bcfp_mc, aoi = "PARS", species = "BT"),
    "no position overlap")
})

# -- live DB: tunnel-free PARS compare vs the local snapshot --------------

test_that("lnk_compare_mapping_code reproduces PARS BT parity tunnel-free", {
  conn <- skip_if_no_db()
  # Needs a prior PARS mapping_code=TRUE run (fresh.streams_mapping_code) +
  # the bcfp snapshot (fresh.streams_vw_bcfp). Skip cleanly if absent.
  have <- tryCatch({
    a <- DBI::dbGetQuery(conn, "SELECT 1 FROM fresh.streams_mapping_code WHERE watershed_group_code='PARS' LIMIT 1")
    b <- DBI::dbGetQuery(conn, "SELECT 1 FROM fresh.streams_vw_bcfp WHERE watershed_group_code='PARS' LIMIT 1")
    nrow(a) > 0 && nrow(b) > 0
  }, error = function(e) FALSE)
  if (!isTRUE(have)) {
    testthat::skip("PARS streams_mapping_code or streams_vw_bcfp snapshot not present")
  }

  out <- lnk_compare_mapping_code(conn, aoi = "PARS", cfg = cfg_fixture(),
                                  species = "BT")
  expect_s3_class(out, "tbl_df")
  expect_equal(out$species, "BT")
  expect_gt(out$total_segs, 40000)        # PARS ~43k segments
  expect_gt(out$match_pct, 95)            # validated ~98.95% tunnel-free
})
