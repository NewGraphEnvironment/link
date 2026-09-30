# lnk_habitat_validate_band() — observation density on the segments a
# threshold step moves.
# Closing parens sit on the last argument line, as in the other test files.
# nolint start: indentation_linter

test_that(".lnk_hvb_density returns NA, never 0 or Inf, on an empty side", {
  d <- link:::.lnk_hvb_density(n_band = c(2, 0, 3, 1), band_km = c(0.2, 0, 0.1, 0.1),
                               n_core = c(2, 2, 0, 1), core_km = c(0.1, 0.1, 0.1, 0))
  expect_equal(d$density_band, c(10, NA, 30, 10))
  expect_equal(d$density_core, c(20, 20, 0, NA))
  expect_equal(d$density_ratio, c(0.5, NA, NA, NA))
})

# -- DB fixture --------------------------------------------------------------
# Three schemas share one network: ref (the step's origin), new (the step
# taken) and core (a third ladder member). AAAA and BBBB reuse id_segment
# 1-4, so a bare id_segment join would read BBBB's rearing for AAAA.
#
# AAAA stream rearing:   seg 1   seg 2   seg 3   seg 4   seg 5
#   ref                    x       x       -       -       -
#   new                    x       -       x       x       -
#   core                   x       x       x       x       -
# -> added {3, 4} 0.2 km; removed {2} 0.1 km; core (all three) {1} 0.1 km.
# BBBB: segs 3 and 4 rearing everywhere, so nothing moves.
local_band_fixture <- function(conn, env = parent.frame()) {
  ss <- c(ref = "zz_lnk_band_ref", new = "zz_lnk_band_new",
          core = "zz_lnk_band_core", odd = "zz_lnk_band_odd")
  for (s in ss) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
    DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  }
  withr::defer(for (s in ss) {
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)),
        silent = TRUE)
  }, envir = env)
  wsg <- c(rep("AAAA", 5), rep("BBBB", 4))
  ids <- c(1:5, 1:4)
  streams <- data.frame(id_segment = ids, watershed_group_code = wsg,
                        length_metre = 100)
  rear <- list(
    ref  = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE),
    new  = c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE),
    core = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE),
    odd  = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE))
  for (k in names(ss)) {
    st <- streams
    # `odd` was broken differently in AAAA: its segment 5 is longer.
    if (k == "odd") st$length_metre[5] <- 150
    DBI::dbWriteTable(conn, DBI::Id(schema = ss[[k]], table = "streams"), st)
    DBI::dbWriteTable(conn, DBI::Id(schema = ss[[k]],
                                    table = "streams_habitat_bt"),
      data.frame(id_segment = ids, watershed_group_code = wsg,
                 spawning = FALSE, rearing = rear[[k]]))
  }
  as.list(ss)
}

band_obs <- function() {
  data.frame(
    species_code = c("BT", "BT", "BT", "BT", "BT", "BT", "BT", "CH", "BT"),
    watershed_group_code = c("AAAA", "AAAA", "AAAA", "AAAA", "AAAA", "AAAA",
                             "BBBB", "AAAA", "AAAA"),
    id_segment = c(1L, 1L, 3L, 4L, 2L, 5L, 3L, 3L, NA),
    is_spawn = c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    is_rear = c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE),
    stringsAsFactors = FALSE)
}

band_conn <- function(env = parent.frame()) {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  conn
}

run_band <- function(conn, ss, ...) {
  lnk_habitat_validate_band(conn, aoi = c("AAAA", "BBBB"), species = "bt",
                            flag = "rearing", schema = ss$new,
                            schema_ref = ss$ref, observations = band_obs(),
                            ...)
}

row_of <- function(b, wsg, dir) {
  b[b$watershed_group_code == wsg & b$direction == dir, ]
}

test_that("lnk_habitat_validate_band counts the band and core on the full key", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  b <- run_band(conn, ss, stage = "any",
                schema_core = c(ss$ref, ss$new, ss$core))

  expect_identical(nrow(b), 4L)
  expect_identical(unique(b$species_code), "BT")
  expect_identical(unique(b$flag), "rearing")
  expect_identical(unique(b$stage), "any")

  a <- row_of(b, "AAAA", "added")
  expect_equal(a$band_km, 0.2)
  # seg 3 and seg 4; the CH record on seg 3 and the unattached one do not count
  expect_identical(a$n_band, 2L)
  expect_equal(a$core_km, 0.1)
  expect_identical(a$n_core, 2L)
  expect_equal(a$density_band, 10)
  expect_equal(a$density_core, 20)
  expect_equal(a$density_ratio, 0.5)

  r <- row_of(b, "AAAA", "removed")
  expect_equal(r$band_km, 0.1)
  expect_identical(r$n_band, 1L)
  expect_equal(r$density_ratio, 0.5)

  # BBBB's segs 3 and 4 are rearing in every schema: a bare id_segment join
  # would have made AAAA's segs 3 and 4 core and left no added band.
  bb <- row_of(b, "BBBB", "added")
  expect_equal(bb$band_km, 0)
  expect_identical(bb$n_band, 0L)
  expect_equal(bb$core_km, 0.2)
  expect_identical(bb$n_core, 1L)
  expect_true(is.na(bb$density_band))
  expect_true(is.na(bb$density_ratio))
})

test_that("lnk_habitat_validate_band's default core is the pair's shared habitat", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  b <- run_band(conn, ss, stage = "any")
  # ref and new share seg 1 only in AAAA, the same core as the ladder here
  expect_equal(row_of(b, "AAAA", "added")$core_km, 0.1)
  expect_identical(row_of(b, "AAAA", "added")$n_core, 2L)
})

test_that("lnk_habitat_validate_band counts only the requested stage", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  rr <- run_band(conn, ss, stage = "rear")
  # rear-staged: seg 1 (one of two), seg 2; none on segs 3 and 4
  expect_identical(row_of(rr, "AAAA", "added")$n_band, 0L)
  expect_equal(row_of(rr, "AAAA", "added")$density_ratio, 0)
  expect_identical(row_of(rr, "AAAA", "removed")$n_band, 1L)
  expect_identical(row_of(rr, "AAAA", "removed")$n_core, 1L)
  expect_equal(row_of(rr, "AAAA", "removed")$density_ratio, 1)

  sp <- run_band(conn, ss, stage = "spawn")
  expect_identical(row_of(sp, "AAAA", "added")$n_band, 1L)
  expect_identical(row_of(sp, "AAAA", "added")$n_core, 0L)
  expect_true(is.na(row_of(sp, "AAAA", "added")$density_ratio))
})

test_that("lnk_habitat_validate_band stops when segmentation differs", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  expect_error(run_band(conn, ss, schema_core = c(ss$ref, ss$new, ss$odd)),
               "segmentation differs .* in: AAAA\\. Compare")
  expect_error(
    lnk_habitat_validate_band(conn, aoi = "CCCC", species = "BT",
                              flag = "rearing", schema = ss$new,
                              schema_ref = ss$ref, observations = band_obs()),
    "no streams for: zz_lnk_band_new:CCCC")
})

test_that("lnk_habitat_validate_band stops on a schema that modelled no habitat for a WSG", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  # An empty table reads as no habitat: BBBB would become a removed band.
  DBI::dbExecute(conn, sprintf(
    "DELETE FROM %s.streams_habitat_bt WHERE watershed_group_code = 'BBBB'",
    ss$new))
  expect_error(run_band(conn, ss),
               "no habitat rows for: zz_lnk_band_new\\.streams_habitat_bt:BBBB")
})

test_that("lnk_habitat_validate_band rejects an observations frame without segments", {
  conn <- band_conn()
  ss <- local_band_fixture(conn)
  o <- band_obs()
  o$id_segment <- NULL
  expect_error(
    lnk_habitat_validate_band(conn, aoi = "AAAA", species = "BT",
                              flag = "rearing", schema = ss$new,
                              schema_ref = ss$ref, observations = o),
    "missing columns: id_segment")
})
# nolint end
