meas_rec <- function(n = 1L, ...) {
  x <- data.frame(
    observation_key = paste0("k", seq_len(n)),
    watershed_group_code = "AAAA", species_code = "CH", counting = TRUE,
    yr = 2000L, waterbody_identifier = "00001AAAA", site = "1:100",
    code_other_group = FALSE, elevation_m = 500, major_drainage = "100",
    barriers_known = TRUE, barrier_below = NA_character_,
    n_class_above = NA_integer_, rearing_lake_ha = NA_real_,
    lake_record = FALSE, known_sockeye_lake = NA, through_main_stem = FALSE,
    in_hist_zone = FALSE, stringsAsFactors = FALSE
  )
  mod <- list(...)
  for (nm in names(mod)) x[[nm]] <- rep_len(mod[[nm]], n)
  x
}

test_that("distinct sites, waterbodies and years are counted, not records", {
  m <- meas_rec(4, site = c("1:100", "1:100", "1:200", "2:5"),
                waterbody_identifier = c("w1", "w1", "w1", "w2"),
                yr = c(2000L, 2000L, 2001L, NA))
  out <- .lnk_presence_cell_measures(m)
  expect_equal(out$n_counting, 4L)
  expect_equal(out$n_sites, 3L)
  expect_equal(out$n_waterbodies, 2L)
  expect_equal(out$n_years, 2L)
})

test_that("only counting records enter a cell", {
  m <- meas_rec(3, counting = c(TRUE, FALSE, NA), site = c("a", "b", "c"))
  out <- .lnk_presence_cell_measures(m)
  expect_equal(out$n_counting, 1L)
  expect_equal(out$n_sites, 1L)
  expect_equal(nrow(.lnk_presence_cell_measures(meas_rec(2, counting = FALSE))), 0L)
})

test_that("barrier measures: kinds, and fewest and most of the class above", {
  m <- meas_rec(3, barrier_below = c("FALLS", "GRADIENT", NA),
                n_class_above = c(1L, 12L, NA))
  out <- .lnk_presence_cell_measures(m)
  expect_equal(out$n_above_barrier, 2L)
  expect_equal(out$above_kinds, "FALLS;GRADIENT")
  expect_equal(out$min_class_above, 1)
  expect_equal(out$max_class_above, 12)
  none <- .lnk_presence_cell_measures(meas_rec(1))
  expect_equal(none$n_above_barrier, 0L)
  expect_true(is.na(none$min_class_above))
  expect_equal(none$above_kinds, "")
})

test_that("kokanee above a barrier with no lake are counted; with a lake not", {
  m <- meas_rec(3, species_code = "KO", barrier_below = c("FALLS", "FALLS", NA),
                rearing_lake_ha = c(NA, 120, NA))
  expect_equal(.lnk_presence_cell_measures(m)$n_ko_no_lake, 1L)
  ch <- meas_rec(1, barrier_below = "FALLS")
  expect_equal(.lnk_presence_cell_measures(ch)$n_ko_no_lake, 0L)
})

test_that("logical measures count TRUE only, NA as not", {
  m <- meas_rec(3, code_other_group = c(TRUE, NA, FALSE),
                through_main_stem = c(TRUE, TRUE, NA),
                in_hist_zone = c(NA, TRUE, FALSE),
                lake_record = c(TRUE, FALSE, FALSE),
                known_sockeye_lake = c(TRUE, NA, NA))
  out <- .lnk_presence_cell_measures(m)
  expect_equal(out$n_code_other_group, 1L)
  expect_equal(out$n_main_stem, 2L)
  expect_equal(out$n_hist_zone, 1L)
  expect_equal(out$n_lake_records, 1L)
  expect_equal(out$n_known_sockeye_lake, 1L)
})

test_that("elevation range ignores NA; all NA reads NA", {
  out <- .lnk_presence_cell_measures(meas_rec(3, elevation_m = c(NA, 300, 900)))
  expect_equal(c(out$elev_min, out$elev_max), c(300, 900))
  out <- .lnk_presence_cell_measures(meas_rec(1, elevation_m = NA_real_))
  expect_true(is.na(out$elev_min))
})

test_that("cells split by group and species, sorted", {
  m <- rbind(meas_rec(1, watershed_group_code = "BBBB"),
             meas_rec(2, species_code = "KO"),
             meas_rec(1))
  out <- .lnk_presence_cell_measures(m)
  expect_equal(paste(out$watershed_group_code, out$species_code),
               c("AAAA CH", "AAAA KO", "BBBB CH"))
  expect_equal(out$n_counting, c(1L, 2L, 1L))
  expect_equal(out$drainages, rep("100", 3))
})

test_that("a missing column stops", {
  expect_error(.lnk_presence_cell_measures(meas_rec(1)[, -3]), "lacks columns")
})

test_that("the measures' SQL is built for the years given and refuses NA", {
  s <- .lnk_presence_measures_sql(1950L, 2026L)
  expect_true(any(grepl("BETWEEN 1950 AND 2026", s, fixed = TRUE)))
  expect_error(.lnk_presence_measures_sql(NA, 2026L))
})

# Live: needs local fwapg with bcfishobs and fresh_default.barriers.
test_that("live: the barrier test reads a falls below, not one above", {
  skip_on_ci()
  conn <- tryCatch(lnk_db_conn(dbname = "fwapg", host = "localhost",
                               port = 5432L, user = "postgres",
                               password = "postgres"),
                   error = function(e) NULL)
  skip_if(is.null(conn), "local fwapg not reachable")
  on.exit(DBI::dbDisconnect(conn))
  ok <- tryCatch(DBI::dbGetQuery(conn, "SELECT 1 FROM fresh_default.barriers LIMIT 1"),
                 error = function(e) NULL)
  skip_if(is.null(ok) || nrow(ok) == 0L, "fresh_default.barriers not built")
  # A falls position, a point 100 m above it and one 100 m below it on its line.
  f <- DBI::dbGetQuery(conn, "
    SELECT b.blue_line_key, b.downstream_route_measure m, b.wscode_ltree::text ws,
           b.localcode_ltree::text lc
    FROM fresh_default.barriers b
    WHERE b.barrier_source = 'FALLS' AND b.downstream_route_measure > 1000
    ORDER BY b.blue_line_key, b.downstream_route_measure LIMIT 1")
  sql <- "SELECT whse_basemapping.fwa_downstream(%d, %f, '%s'::ltree, '%s'::ltree,
                                                %d, %f, '%s'::ltree, '%s'::ltree) d"
  q <- function(m) {
    DBI::dbGetQuery(conn, sprintf(sql, f$blue_line_key, m, f$ws, f$lc,
                                  f$blue_line_key, f$m, f$ws, f$lc))$d
  }
  expect_true(q(f$m + 100))
  expect_false(q(f$m - 100))
})

test_that("the measure story says what holds and skips what does not", {
  cm <- .lnk_presence_cell_measures(meas_rec(1))
  want <- paste0("Own records: 1 site on 1 waterbody in 1 year; none on a ",
                 "stream with a historical distribution zone of the species; ",
                 "at 500 m.")
  expect_equal(.lnk_presence_measure_story(cm), want)
  m <- meas_rec(3, site = c("a", "b", "c"), waterbody_identifier = c("w1", "w1", "w2"),
                yr = c(1990L, 2001L, 2001L), barrier_below = c("FALLS", "GRADIENT", NA),
                n_class_above = c(1L, 4L, NA), code_other_group = c(TRUE, FALSE, FALSE),
                in_hist_zone = c(TRUE, TRUE, TRUE), elevation_m = c(400, 800, 1200))
  s <- .lnk_presence_measure_story(.lnk_presence_cell_measures(m))
  expect_match(s, "3 sites on 2 waterbodies in 2 years", fixed = TRUE)
  expect_match(s, "1 of 3 filed under a 50k code", fixed = TRUE)
  expect_match(s, "2 of 3 above a natural barrier that blocks it (falls, gradient), with 1 to 4 counting",
               fixed = TRUE)
  expect_match(s, "all on a stream with a historical distribution zone", fixed = TRUE)
  expect_match(s, "400 to 1200 m.", fixed = TRUE)
})

test_that("the measure story names kokanee with no lake and lake records", {
  m <- meas_rec(2, species_code = "KO", barrier_below = c("FALLS", NA),
                n_class_above = c(2L, NA), lake_record = c(TRUE, TRUE),
                known_sockeye_lake = c(TRUE, FALSE), site = c("a", "b"))
  s <- .lnk_presence_measure_story(.lnk_presence_cell_measures(m))
  expect_match(s, "1 of 2 above a barrier with no lake above it", fixed = TRUE)
  expect_match(s, "all in lakes (1 in known sockeye lakes)", fixed = TRUE)
  expect_match(s, "with 2 counting records of its class above", fixed = TRUE)
})

test_that("the measure story says when a group holds no barrier rows, and is empty for no records", {
  s <- .lnk_presence_measure_story(.lnk_presence_cell_measures(meas_rec(1, barriers_known = FALSE)))
  expect_match(s, "no barrier rows in the group", fixed = TRUE)
  empty <- data.frame(n_counting = NA_integer_)
  expect_equal(.lnk_presence_measure_story(empty), "")
})
