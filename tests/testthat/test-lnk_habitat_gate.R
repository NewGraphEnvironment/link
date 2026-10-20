fake_conn <- function() structure(list(), class = "DBIConnection")

gate_args <- function(...) {
  c(list(conn = fake_conn(), aoi = "DUNC",
         table_habitat = "fresh_default.streams_habitat",
         table_access  = "fresh_default.streams_access",
         table_streams = "fresh_default.streams",
         species = c("BT", "RB")),
    list(...))
}

# Captures every statement and answers the count queries with zero rows, so
# the shape of what the gate sends can be read without a database.
capture_gate <- function(...) {
  sent <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) { sent <<- c(sent, sql); 0L },
    .lnk_db_query = function(conn, sql) {
      sent <<- c(sent, sql)
      data.frame(flag = character(0), n_segments = integer(0), km = numeric(0),
                 n_lifted = integer(0))
    },
    .lnk_db_transaction = function(conn, code) force(code),
    .package = "link"
  )
  out <- do.call(lnk_habitat_gate, gate_args(...))
  list(sent = sent, out = out)
}

test_that("one UPDATE per species, keyed on the full key, access = 0 only", {
  r <- capture_gate()
  upd <- grep("^\\s*UPDATE", r$sent, value = TRUE)
  expect_length(upd, 2L)
  expect_match(upd[1], "fresh_default\\.streams_habitat_bt h")
  expect_match(upd[2], "fresh_default\\.streams_habitat_rb h")
  for (u in upd) {
    for (flag in c("accessible", "spawning", "rearing", "lake_rearing",
                   "wetland_rearing")) {
      expect_match(u, paste0("\\b", flag, " = "), perl = TRUE)
    }
    expect_match(u, "a\\.id_segment = h\\.id_segment")
    expect_match(u, "a\\.watershed_group_code = h\\.watershed_group_code")
    expect_match(u, "h\\.watershed_group_code = 'DUNC'")
  }
  expect_match(upd[1], "a\\.access_bt = 0")
  expect_match(upd[2], "a\\.access_rb = 0")
})

test_that("without an overlay, spawning and rearing are not exempted", {
  r <- capture_gate()
  upd <- grep("^\\s*UPDATE", r$sent, value = TRUE)
  expect_false(any(grepl("zz_lnk_gate_overlay", upd)))
})

test_that("an overlay exempts spawning and rearing, never accessible", {
  ov <- data.frame(species_code = "BT", blue_line_key = 1L,
                   downstream_route_measure = 0, upstream_route_measure = 10,
                   spawning = 1L, rearing = NA_integer_)
  written <- NULL
  local_mocked_bindings(
    .lnk_gate_write_overlay = function(conn, overlay, aoi) {
      written <<- overlay
      "zz_lnk_gate_overlay_dunc"
    },
    .package = "link"
  )
  r <- capture_gate(overlay = ov)
  upd <- grep("^\\s*UPDATE", r$sent, value = TRUE)[1]
  expect_identical(written, ov)
  expect_match(upd, "spawning = CASE WHEN EXISTS")
  expect_match(upd, "rearing = CASE WHEN EXISTS")
  expect_match(upd, "accessible = FALSE")
  expect_match(upd, "lake_rearing = FALSE")
  expect_match(upd, "wetland_rearing = FALSE")
})

test_that("argument checks", {
  expect_error(do.call(lnk_habitat_gate, gate_args(aoi = "dunc")))
  expect_error(do.call(lnk_habitat_gate, gate_args(species = character(0))))
  expect_error(do.call(lnk_habitat_gate, gate_args(species = "B T")))
  expect_error(do.call(lnk_habitat_gate, gate_args(table_habitat = "x; DROP")))
  expect_error(do.call(lnk_habitat_gate, gate_args(overlay = "a.table")))
})

test_that("the gate blanks blocked rows, keeps the overlay, counts lifts", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn))
  s <- "zz_lnk_gate_probe"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(try(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)),
                   silent = TRUE))

  # 1 blocked, all flags; 2 accessible; 3 absent (-9); 4 blocked, inside the
  # overlay's spawning reach; 5 lifted since the prior compute, flags FALSE;
  # 6 blocked but another group; 7 NULL access.
  streams <- data.frame(
    id_segment = c(1:7), watershed_group_code = c(rep("DUNC", 5), "OTHR", "DUNC"),
    blue_line_key = c(10L, 10L, 10L, 20L, 10L, 10L, 10L),
    downstream_route_measure = c(0, 100, 200, 50, 300, 0, 400),
    upstream_route_measure = c(100, 200, 300, 80, 400, 100, 500),
    length_metre = c(100, 100, 100, 30, 100, 100, 100))
  access <- data.frame(
    id_segment = c(1:7), watershed_group_code = streams$watershed_group_code,
    access_bt = c(0L, 1L, -9L, 0L, 2L, 0L, NA))
  prior <- transform(access, access_bt = c(0L, 1L, -9L, 0L, 0L, 0L, NA))
  hab <- data.frame(
    id_segment = c(1:7), watershed_group_code = streams$watershed_group_code,
    accessible = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    spawning = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    rearing = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE),
    lake_rearing = c(TRUE, FALSE, FALSE, TRUE, FALSE, TRUE, TRUE),
    wetland_rearing = c(TRUE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE))
  for (tb in list(list("streams", streams), list("streams_access", access),
                  list("access_prior", prior), list("streams_habitat_bt", hab))) {
    DBI::dbWriteTable(conn, DBI::Id(schema = s, table = tb[[1]]), tb[[2]])
  }
  overlay <- data.frame(species_code = c("BT", "RB"), blue_line_key = c(20L, 10L),
                        downstream_route_measure = c(40, 0),
                        upstream_route_measure = c(90, 500),
                        spawning = c(1L, 1L), rearing = c(NA, 1L))

  res <- lnk_habitat_gate(conn, aoi = "DUNC",
    table_habitat = paste0(s, ".streams_habitat"),
    table_access  = paste0(s, ".streams_access"),
    table_streams = paste0(s, ".streams"),
    species = "BT", overlay = overlay,
    table_access_prior = paste0(s, ".access_prior"))

  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s.streams_habitat_bt ORDER BY id_segment", s))
  # 1: every flag FALSE.
  expect_equal(unlist(got[1, 3:7]), c(accessible = FALSE, spawning = FALSE,
    rearing = FALSE, lake_rearing = FALSE, wetland_rearing = FALSE))
  # 2, 3, 6, 7 untouched.
  for (i in c(2L, 3L, 6L, 7L)) {
    expect_equal(unlist(got[i, 3:7]), unlist(hab[i, 3:7]), info = paste("row", i))
  }
  # 4: blocked, but the overlay's BT spawning reach contains it.
  expect_equal(unlist(got[4, 3:7]), c(accessible = FALSE, spawning = TRUE,
    rearing = FALSE, lake_rearing = FALSE, wetland_rearing = FALSE))

  expect_s3_class(res, "data.frame")
  expect_named(res, c("species", "flag", "n_segments", "km", "n_lifted_settled"))
  cnt <- stats::setNames(res$n_segments, res$flag)
  expect_equal(cnt[["accessible"]], 2L)
  expect_equal(cnt[["spawning"]], 1L)
  expect_equal(cnt[["rearing"]], 2L)
  expect_equal(cnt[["lake_rearing"]], 2L)
  expect_equal(cnt[["wetland_rearing"]], 1L)
  expect_equal(res$km[res$flag == "accessible"], 0.13)
  expect_true(all(res$n_lifted_settled == 1L))

  # A second pass changes nothing.
  res2 <- lnk_habitat_gate(conn, aoi = "DUNC",
    table_habitat = paste0(s, ".streams_habitat"),
    table_access  = paste0(s, ".streams_access"),
    table_streams = paste0(s, ".streams"),
    species = "BT", overlay = overlay)
  expect_true(all(res2$n_segments == 0L))
  expect_true(all(is.na(res2$n_lifted_settled)))
})
