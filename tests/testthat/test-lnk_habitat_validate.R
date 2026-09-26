# lnk_habitat_validate() — observation-based scoring of a persisted run.
# Closing parens sit on the last argument line, as in the other test files.
# nolint start: indentation_linter

test_that(".lnk_obs_stage reads spawning from activity and rearing from activity or juvenile stage", {
  st <- link:::.lnk_obs_stage(
    activity_code = c("SPL", "R", NA, "OBS", "S", "M"),
    activity = c("Spawning - live", "Rearing", NA, "Observed", NA, "Migrating"),
    life_stage = c("Adult", NA, "Fry", "Adult", NA, "Juvenile"))
  expect_identical(st$is_spawn, c(TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(st$is_rear, c(FALSE, TRUE, TRUE, FALSE, FALSE, TRUE))
})

test_that(".lnk_obs_stage does not read NA activity as a stage", {
  st <- link:::.lnk_obs_stage(NA_character_, NA_character_, NA_character_)
  expect_false(st$is_spawn)
  expect_false(st$is_rear)
})

test_that(".lnk_habitat_miss_reason attributes each miss once, in order", {
  r <- link:::.lnk_habitat_miss_reason(
    captured      = c(TRUE, NA,   FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    accessible    = c(TRUE, NA,   FALSE, TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE),
    channel_width = c(5,    NA,   5,     5,     5,     NA,    5,     5,     5,     5),
    p             = c(TRUE, NA,   TRUE,  TRUE,  FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    p_g           = c(TRUE, NA,   TRUE,  TRUE,  TRUE,  FALSE, FALSE, TRUE,  FALSE, FALSE),
    p_w           = c(TRUE, NA,   TRUE,  TRUE,  FALSE, TRUE,  TRUE,  TRUE,  FALSE, FALSE),
    p_gw          = c(TRUE, NA,   TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  FALSE))
  expect_identical(r, c(NA, "no_segment", "not_accessible", "post_predicate",
                        "fails_gradient", "width_null", "fails_width",
                        "fails_gradient_or_width", "fails_gradient_and_width",
                        "rule_excludes"))
})

test_that(".lnk_habitat_miss_reason separates a gradient below the window from one above it", {
  r <- link:::.lnk_habitat_miss_reason(
    captured = c(FALSE, FALSE), accessible = c(TRUE, TRUE),
    channel_width = c(5, 5), p = c(FALSE, FALSE), p_g = c(TRUE, TRUE),
    p_w = c(FALSE, FALSE), p_gw = c(TRUE, TRUE),
    gradient = c(-0.02, 0.2), gradient_min = c(0, 0))
  expect_identical(r, c("gradient_below_min", "fails_gradient"))
})

test_that(".lnk_hv_relax fixes gradient and width without touching lookalike columns", {
  p <- "s.gradient BETWEEN 0 AND 0.05 AND s.channel_width >= 2 AND s.gradient_x > 1"
  r <- link:::.lnk_hv_relax(p, gradient = 0, width = 2)
  expect_false(grepl("s\\.gradient ", r))
  expect_false(grepl("s\\.channel_width", r))
  expect_true(grepl("s.gradient_x", r, fixed = TRUE))
  expect_identical(link:::.lnk_hv_relax(p), p)
})

test_that(".lnk_hv_stage_min takes the spawn gradient floor from parameters_fresh", {
  spp <- list(spawn_gradient_min = 0.0025,
              params_sp = list(ranges = list(
                spawn = list(gradient = c(0, 0.05), channel_width = c(4, 9999)),
                rear = list(gradient = c(0, 0.1), channel_width = c(1.5, 9999)))))
  m <- link:::.lnk_hv_stage_min(spp)
  expect_identical(m$spawn[["gradient"]], 0.0025)
  expect_identical(m$spawn[["width"]], 4)
  expect_identical(m$rear[["gradient"]], 0)
  expect_identical(m$rear[["width"]], 1.5)
})

test_that("the predicate call passes no argument fresh@v0.33.0 lacks", {
  # DESCRIPTION pins fresh >= 0.33.0, whose frs_habitat_predicates() takes
  # only `sp_params`; `model =` arrived later and would error there.
  calls <- list()
  walk <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1]], quote(fresh::frs_habitat_predicates))) {
        calls[[length(calls) + 1L]] <<- e
      }
      for (a in as.list(e)[-1]) if (!missing(a)) walk(a)
    }
  }
  walk(body(link:::.lnk_hv_predicates))
  expect_length(calls, 1L)
  expect_length(as.list(calls[[1]])[-1], 1L)
  expect_null(names(as.list(calls[[1]])[-1]))
})

test_that(".lnk_hv_spec admits observation species only where the model species is present", {
  presence <- data.frame(
    watershed_group_code = c("AAAA", "BBBB"),
    bt = c("t", ""), ch = c("t", "t"), notes = c("", ""),
    stringsAsFactors = FALSE)
  s <- link:::.lnk_hv_spec(
    presence, aoi = c("AAAA", "BBBB", "CCCC"), species = c("BT", "CH"),
    species_obs = list(BT = c("BT", "DV")))
  got <- paste(s$watershed_group_code, s$species_code, s$obs_species)
  expect_setequal(got, c("AAAA BT BT", "AAAA BT DV", "AAAA CH CH",
                         "BBBB CH CH"))
})

test_that(".lnk_hv_spec returns a typed empty frame when nothing is present", {
  presence <- data.frame(watershed_group_code = "AAAA", bt = "",
                         stringsAsFactors = FALSE)
  s <- link:::.lnk_hv_spec(presence, "AAAA", "BT", list())
  expect_identical(nrow(s), 0L)
  expect_named(s, c("watershed_group_code", "species_code", "obs_species"))
})

test_that(".lnk_hv_dedup merges records at one location and ORs their stages", {
  obs <- data.frame(
    observation_key = c("b", "a", "c"),
    species_code = "BT", obs_species = c("BT", "DV", "BT"),
    blue_line_key = 1L, m = c(50.2, 50, 120),
    activity_code = c("S", NA, NA), activity = c("Spawning", NA, NA),
    life_stage = c(NA, "Fry", NA), stringsAsFactors = FALSE)
  d <- link:::.lnk_hv_dedup(obs)
  expect_identical(nrow(d), 2L)
  loc50 <- d[round(d$m) == 50, ]
  expect_identical(loc50$observation_key, "a")
  expect_true(loc50$is_spawn)
  expect_true(loc50$is_rear)
  expect_identical(loc50$n_records, 2L)
  expect_identical(loc50$obs_species, "BT;DV")
})

test_that("lnk_habitat_validate validates its arguments before touching the DB", {
  cfg <- lnk_config("default")
  conn <- structure(list(), class = c("PqConnection", "DBIConnection"))
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "BT"),
               "schema")
  expect_error(lnk_habitat_validate(conn, "morr", cfg, list(), "BT", "s"))
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "B;T", "s"))
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "BT", "s",
                                    buffer_m = -1))
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "BT", "s",
                                    match_types = "A'"))
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "BT", "s",
                                    observations = "x; drop"),
               "disallowed")
  expect_error(lnk_habitat_validate(conn, "MORR", cfg, list(), "BT", "s"),
               "wsg_species_presence")
})


# -- DB fixture --------------------------------------------------------------
# Two WSGs share id_segment values, so a bare id_segment join would attach
# BBBB's spawning segment to an AAAA observation. BT is present in AAAA
# only, so BBBB's DV and BT records must not count.
#
# AAAA, blue_line_key 1:
#   seg 1   0-100  gradient 0.01  width 5    access 1  rearing
#   seg 2 100-200  gradient 0.08  width 5    access 0  -
#   seg 3 200-300  gradient 0.01  width 5    access 1  spawning, rearing
#   seg 4 300-400  gradient 0.20  width 5    access 1  -
#   seg 5 400-500  gradient 0.01  width NULL access 1  -
local_validate_fixture <- function(conn, env = parent.frame()) {
  s <- "zz_lnk_validate_probe"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)),
        silent = TRUE), envir = env)
  wsg <- c(rep("AAAA", 5), "BBBB", "BBBB")
  ids <- c(1:5, 1L, 2L)
  DBI::dbWriteTable(conn, DBI::Id(schema = s, table = "streams"), data.frame(
    id_segment = ids, watershed_group_code = wsg,
    blue_line_key = c(rep(1L, 5), 2L, 2L),
    downstream_route_measure = c(0, 100, 200, 300, 400, 0, 100),
    upstream_route_measure = c(100, 200, 300, 400, 500, 100, 200),
    length_metre = 100,
    gradient = c(0.01, 0.08, 0.01, 0.20, 0.01, 0.01, 0.01),
    channel_width = c(5, 5, 5, 5, NA, 5, 5),
    channel_width_source = "MODELLED",
    edge_type = 1000L, stream_order = 3L,
    waterbody_key = NA_integer_))
  DBI::dbWriteTable(conn, DBI::Id(schema = s, table = "streams_access"),
                    data.frame(
    id_segment = ids, watershed_group_code = wsg,
    access_bt = c(1L, 0L, 1L, 1L, 1L, 1L, 1L)))
  DBI::dbWriteTable(conn, DBI::Id(schema = s, table = "streams_habitat_bt"),
                    data.frame(
    id_segment = ids, watershed_group_code = wsg,
    accessible = TRUE,
    spawning = c(FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE),
    rearing = c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE),
    lake_rearing = FALSE, wetland_rearing = FALSE))
  DBI::dbWriteTable(conn, DBI::Id(schema = s, table = "observations"),
                    data.frame(
    observation_key = paste0("o", 1:11),
    species_code = c("BT", "DV", "BT", "BT", "DV", "BT", "BT", "BT",
                     "BT", "BT", "BT"),
    watershed_group_code = c("AAAA", "AAAA", "AAAA", "AAAA", "BBBB",
                             "AAAA", "AAAA", "BBBB", "AAAA", "AAAA", "AAAA"),
    blue_line_key = c(1L, 1L, 1L, 1L, 2L, 1L, 1L, 2L, 1L, 1L, 1L),
    downstream_route_measure = c(100, 50, 50, 60, 50, 150, 50.2, 150,
                                 300, 400, 600),
    match_type = c("A. matched", "B. matched", "A.", "A.", "A.",
                   "C. not matched", "A.", "A.", "A.", "A.", "A."),
    activity_code = c("R", NA, NA, NA, NA, NA, "S", NA, NA, NA, NA),
    activity = c("Rearing", NA, NA, NA, NA, NA, "Spawning", NA, NA, NA, NA),
    life_stage = c(NA, "Fry", NA, NA, NA, NA, NA, NA, NA, NA, NA),
    source = c("FISS", "FISS", "FISS", "Releases Database (x)",
               rep("FISS", 7))))
  s
}

validate_loaded <- function() {
  list(
    wsg_species_presence = data.frame(
      watershed_group_code = c("AAAA", "BBBB"), bt = c("t", ""),
      notes = "", stringsAsFactors = FALSE),
    parameters_fresh = utils::read.csv(
      lnk_config("default")$files$parameters_fresh$path,
      stringsAsFactors = FALSE),
    observation_exclusions = data.frame(
      observation_key = "o3", data_error = "t", release_exclude = "",
      stringsAsFactors = FALSE),
    # A spawning-only reach and a confirmed non-habitat reach, both over o2,
    # and a spawning reach 50 m above o1.
    user_habitat_classification = data.frame(
      species_code = "BT", blue_line_key = 1L,
      downstream_route_measure = c(0, 40, 150),
      upstream_route_measure = c(60, 70, 160),
      spawning = c(1L, -1L, 1L), rearing = c(NA, -4L, NA)))
}

validate_conn <- function(env = parent.frame()) {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  conn
}

run_validate <- function(conn, s, aoi = c("AAAA", "BBBB"), ...) {
  lnk_habitat_validate(
    conn, aoi = aoi, cfg = lnk_config("default"),
    loaded = validate_loaded(), species = "BT", schema = s,
    observations = paste0(s, ".observations"), ...)
}

test_that("lnk_habitat_validate scores a fixture run on the full key", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  v <- run_validate(conn, s)

  # o3 excluded, o4 a release, o5 DV where BT is absent, o6 match C,
  # o8 BT where BT is absent; o2 and o7 are one location.
  obs <- v$observations
  expect_setequal(obs$observation_key, c("o1", "o2", "o9", "o10", "o11"))

  o <- function(k) obs[obs$observation_key == k, ]
  # Starts at 100 -> segment 2 of AAAA, not the containing segment 1, and
  # not BBBB's segment 2 (spawning).
  expect_identical(o("o1")$id_segment, 2L)
  expect_false(o("o1")$spawning)
  expect_false(o("o1")$accessible)
  expect_identical(o("o1")$miss_reason_rear, "not_accessible")

  expect_true(o("o2")$rearing)
  expect_true(o("o2")$in_uhc_spawn)
  expect_false(o("o2")$in_uhc_rear)
  expect_identical(o("o2")$obs_species, "BT;DV")
  expect_true(is.na(o("o2")$miss_reason_rear))
  # Passes the spawning predicate but is not spawning: clustering.
  expect_identical(o("o2")$miss_reason_spawn, "post_predicate")

  expect_identical(o("o9")$miss_reason_spawn, "fails_gradient")
  expect_identical(o("o9")$miss_reason_rear, "fails_gradient")
  expect_identical(o("o10")$miss_reason_spawn, "width_null")
  expect_identical(o("o10")$miss_reason_rear, "width_null")
  expect_true(is.na(o("o11")$id_segment))
  expect_identical(o("o11")$miss_reason_rear, "no_segment")

  sm <- v$summary
  a_any <- sm[sm$watershed_group_code == "AAAA" & sm$stage == "any", ]
  expect_identical(a_any$n_obs, 4L)
  expect_identical(a_any$n_unattached, 1L)
  expect_identical(a_any$n_accessible, 3L)
  expect_identical(a_any$n_inaccessible, 1L)
  expect_identical(a_any$n_rearing, 1L)
  expect_identical(a_any$n_spawning, 0L)
  expect_equal(a_any$share_rearing, 0.25)
  expect_identical(a_any$n_in_uhc_spawn, 1L)
  expect_identical(a_any$n_in_uhc_rear, 0L)
  # o2 (loc 50) is the only location in a spawning UHC reach.
  expect_identical(a_any$n_obs_outside_uhc_spawn, 3L)
  expect_identical(a_any$n_spawning_outside_uhc, 0L)
  expect_equal(a_any$share_spawning_outside_uhc, 0)
  expect_equal(a_any$share_rearing_any_outside_uhc, 0.25)
  expect_true(is.integer(obs$n_cand))
  expect_equal(a_any$spawning_km, 0.1)
  expect_identical(sm$n_obs[sm$watershed_group_code == "AAAA" &
                              sm$stage == "spawn"], 1L)
  expect_identical(sm$n_obs[sm$watershed_group_code == "AAAA" &
                              sm$stage == "rear"], 2L)
  b <- sm[sm$watershed_group_code == "BBBB", ]
  expect_identical(nrow(b), 3L)
  expect_true(all(b$n_obs == 0L))
  expect_true(all(is.na(b$share_rearing)))
  expect_identical(unique(sm$schema), s)
  expect_identical(unique(sm$config_name), "default")
  expect_identical(unique(sm$buffer_m), 0)
  expect_false(any(sm$run_logged))
})

test_that("species_obs values are case-insensitive", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  v <- run_validate(conn, s, aoi = "AAAA", species_obs = list(bt = c("bt", "dv")))
  expect_identical(v$summary$n_obs[v$summary$stage == "any"], 4L)
})

test_that("buffer_m captures habitat upstream along the same stream", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  o1 <- function(b) {
    v <- run_validate(conn, s, aoi = "AAAA", buffer_m = b)
    v$observations[v$observations$observation_key == "o1", ]
  }
  # Segment 3 (spawning) starts 100 m above o1.
  expect_false(o1(99)$spawning)
  expect_true(o1(101)$spawning)
  # Accessibility stays the point's own segment.
  expect_false(o1(101)$accessible)
  # The UHC reach 50 m up is inside the buffered window, not the point's.
  expect_false(o1(0)$in_uhc_spawn)
  expect_true(o1(51)$in_uhc_spawn)
})

test_that("absences are counted against the segment containing them", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  v <- run_validate(conn, s, absences = data.frame(
    watershed_group_code = c("AAAA", "AAAA", "BBBB"),
    blue_line_key = c(1L, 1L, 2L),
    downstream_route_measure = c(250, 150, 50),
    species_code = "bt"))
  a <- v$summary[v$summary$watershed_group_code == "AAAA" &
                   v$summary$stage == "any", ]
  expect_identical(a$n_absence, 2L)
  expect_identical(a$n_absence_spawning, 1L)
  expect_identical(a$n_absence_accessible, 1L)
  # BT is absent from BBBB, so its absence row is dropped and BBBB was not
  # assessed: NA, not 0.
  expect_true(all(is.na(
    v$summary$n_absence[v$summary$watershed_group_code == "BBBB"])))
})

test_that("absences are buffered like observations", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  n_spawn <- function(b) {
    v <- run_validate(conn, s, aoi = "AAAA", buffer_m = b,
      absences = data.frame(watershed_group_code = "AAAA", blue_line_key = 1L,
                            downstream_route_measure = 150,
                            species_code = "BT"))
    v$summary$n_absence_spawning[1]
  }
  # Segment 3 (spawning) starts at 200, above the segment 2 start at 100.
  expect_identical(n_spawn(0), 0L)
  expect_identical(n_spawn(51), 1L)
})

test_that("lnk_habitat_validate fails loud on a WSG the schema cannot score", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  expect_error(run_validate(conn, s, aoi = c("AAAA", "ZZZZ")),
               "not persisted.*ZZZZ")
  DBI::dbExecute(conn, sprintf(
    "DELETE FROM %s.streams_access WHERE watershed_group_code = 'BBBB'", s))
  expect_error(run_validate(conn, s), "streams_access rows for: BBBB")
})

test_that("lnk_habitat_validate refuses a schema logged as another config's", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.log (watershed_group_code text, config_name text,
                         date_start timestamptz)", s))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log VALUES
       ('AAAA', 'default', '2026-01-01'), ('AAAA', 'bcfishpass', '2026-02-01')",
    s))
  expect_error(run_validate(conn, s), "AAAA \\(bcfishpass\\)")
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET config_name = 'default'", s))
  v <- run_validate(conn, s)
  expect_identical(
    unique(v$summary$run_logged[v$summary$watershed_group_code == "AAAA"]),
    TRUE)
  expect_identical(
    unique(v$summary$run_logged[v$summary$watershed_group_code == "BBBB"]),
    FALSE)
})
# nolint end: indentation_linter
