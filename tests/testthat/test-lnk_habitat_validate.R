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
    size          = c(5,    NA,   5,     5,     5,     NA,    5,     5,     5,     5),
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
    size = c(5, 5), p = c(FALSE, FALSE), p_g = c(TRUE, TRUE),
    p_w = c(FALSE, FALSE), p_gw = c(TRUE, TRUE),
    gradient = c(-0.02, 0.2), gradient_min = c(0, 0))
  expect_identical(r, c("gradient_below_min", "fails_gradient"))
})

test_that(".lnk_habitat_miss_reason names a missing MAD range before rule_excludes (#299)", {
  r <- link:::.lnk_habitat_miss_reason(
    captured = c(FALSE, FALSE, FALSE, FALSE),
    accessible = c(TRUE, TRUE, TRUE, TRUE),
    size = c(1, 1, 1, NA), p = c(FALSE, FALSE, FALSE, FALSE),
    p_g = c(FALSE, FALSE, FALSE, FALSE), p_w = c(FALSE, FALSE, FALSE, FALSE),
    p_gw = c(FALSE, FALSE, FALSE, FALSE), p_nomad = c(TRUE, FALSE, NA, TRUE),
    p_nomad_g = c(TRUE, TRUE, NA, TRUE))
  # Passing with a range alone is the missing range; needing the gradient
  # relaxed as well is cw's "both" reason; with no discharge to test, a
  # range would not help and the value is what is missing.
  expect_identical(r, c("no_mad_threshold", "fails_gradient_and_width",
                        "rule_excludes", "width_null"))
})

test_that(".lnk_hv_relax fixes gradient and width without touching lookalike columns", {
  p <- "s.gradient BETWEEN 0 AND 0.05 AND s.channel_width >= 2 AND s.gradient_x > 1"
  r <- link:::.lnk_hv_relax(p, gradient = 0, size = 2)
  expect_false(grepl("s\\.gradient ", r))
  expect_false(grepl("s\\.channel_width", r))
  expect_true(grepl("s.gradient_x", r, fixed = TRUE))
  expect_identical(link:::.lnk_hv_relax(p), p)
})

test_that(".lnk_hv_relax rewrites the size column it is given", {
  p <- "s.mad_m3s BETWEEN 0.1 AND 40 AND s.channel_width >= 2 AND s.mad_m3s_x > 1"
  r <- link:::.lnk_hv_relax(p, size = 0.1, size_col = "mad_m3s")
  expect_false(grepl("s.mad_m3s ", r, fixed = TRUE))
  expect_true(grepl("s.channel_width", r, fixed = TRUE))
  expect_true(grepl("s.mad_m3s_x", r, fixed = TRUE))
})

test_that(".lnk_hv_stage_min takes the spawn gradient floor from parameters_fresh", {
  spp <- list(spawn_gradient_min = 0.0025,
              params_sp = list(ranges = list(
                spawn = list(gradient = c(0, 0.05), channel_width = c(4, 9999)),
                rear = list(gradient = c(0, 0.1), channel_width = c(1.5, 9999)))))
  m <- link:::.lnk_hv_stage_min(spp)
  expect_identical(m$spawn[["gradient"]], 0.0025)
  expect_identical(m$spawn[["size"]], 4)
  expect_identical(m$rear[["gradient"]], 0)
  expect_identical(m$rear[["size"]], 1.5)
})

test_that(".lnk_hv_stage_min takes MAD minimums on mad, 0 where a species has none (#299)", {
  spp <- list(spawn_gradient_min = 0,
              params_sp = list(ranges = list(
                spawn = list(channel_width = c(4, 9999), mad_m3s = c(0.164, 9999)),
                rear = list(channel_width = c(1.5, 9999)))))
  m <- link:::.lnk_hv_stage_min(spp, "mad")
  expect_identical(m$spawn[["size"]], 0.164)
  expect_identical(m$rear[["size"]], 0)
})

# One species' predicate inputs from the default bundle, as the validator
# assembles them.
default_spp <- function(sp, bundle = "default") {
  cfg <- lnk_config(bundle)
  params <- fresh::frs_params(csv = link:::.lnk_habitat_thresholds_csv(cfg),
                              rules_yaml = cfg$rules)
  link:::.lnk_hv_sp_params(
    params, utils::read.csv(cfg$files$parameters_fresh$path), sp)
}

test_that("cw predicate expressions are the ones the validator built before #299", {
  # The pre-#299 construction, inline: cw output must not move.
  for (sp in c("BT", "CO")) {
    spp <- default_spp(sp)
    pr <- fresh::frs_habitat_predicates(spp)
    mins <- link:::.lnk_hv_stage_min(spp)
    stage_pred <- list(
      spawn = pr$spawn,
      rear = sprintf("(%s) OR (%s) OR (%s)", pr$rear, pr$lake_rear,
                     pr$wetland_rear))
    old <- unlist(lapply(c("spawn", "rear"), function(st) {
      g <- mins[[st]][["gradient"]]
      w <- mins[[st]][["size"]]
      p <- stage_pred[[st]]
      v <- c(p, link:::.lnk_hv_relax(p, gradient = g),
             link:::.lnk_hv_relax(p, size = w),
             link:::.lnk_hv_relax(p, gradient = g, size = w))
      c(sprintf("coalesce((%s), false) AS pred_%s%s", v, st,
                c("", "_g", "_w", "_gw")),
        sprintf("NULL::boolean AS pred_%s%s", st, c("_nomad", "_nomad_g")))
    }))
    expect_identical(link:::.lnk_hv_stage_exprs(spp, "cw"), old, info = sp)
  }
})

test_that("mad predicate expressions test and relax discharge, not width (#299)", {
  e <- link:::.lnk_hv_stage_exprs(default_spp("CO"), "mad")
  pick <- function(k) e[grepl(paste0(" AS ", k, "$"), e)]
  expect_true(grepl("s.mad_m3s", pick("pred_spawn"), fixed = TRUE))
  expect_false(any(grepl("s.channel_width", e, fixed = TRUE)))
  # Relaxing the size leaves no discharge test behind.
  expect_false(grepl("s.mad_m3s", pick("pred_spawn_w"), fixed = TRUE))
  expect_false(grepl("s.mad_m3s", pick("pred_rear_gw"), fixed = TRUE))
  expect_true(grepl("s.mad_m3s", pick("pred_rear_g"), fixed = TRUE))
  # CO has MAD ranges for both stages: no missing-threshold test.
  expect_identical(pick("pred_spawn_nomad"), "NULL::boolean AS pred_spawn_nomad")
  expect_identical(pick("pred_rear_nomad_g"), "NULL::boolean AS pred_rear_nomad_g")
})

test_that(".lnk_hv_mad_missing follows fresh's branches, case by case (#299)", {
  rule <- list(list(edge_types_explicit = 1000L))
  ps <- function(rules, ranges) list(rules = rules, ranges = ranges)
  g <- list(gradient = c(0, 0.1))
  cw <- list(channel_width = c(1, 9999))
  mad <- list(mad_m3s = c(0.1, 40))
  f <- link:::.lnk_hv_mad_missing
  # A MAD range: never missing.
  expect_false(f(ps(list(rear = rule), list(rear = c(g, mad))), "rear"))
  expect_false(f(ps(NULL, list(rear = c(g, mad))), "rear"))
  # Rules path: missing, with or without a channel-width range.
  expect_true(f(ps(list(rear = rule), list(rear = c(g, cw))), "rear"))
  expect_true(f(ps(list(rear = rule), list(rear = g)), "rear"))
  expect_true(f(ps(list(spawn = rule), list()), "spawn"))
  # CSV path: spawning always tests size; rearing only with ranges.
  expect_true(f(ps(NULL, list()), "spawn"))
  expect_true(f(ps(NULL, list(rear = cw)), "rear"))
  expect_false(f(ps(NULL, list()), "rear"))
  # And against fresh: missing exactly where supplying a range changes the
  # mad predicate AND the stage has habitat on cw. A stage FALSE on both
  # models (CSV path, no rear ranges) has no threshold to miss; filling a
  # range there would invent a test fresh never writes.
  sp <- function(params_sp) list(species_code = "XX", spawn_gradient_min = 0,
                                 spawn_gradient_max = 0.05,
                                 params_sp = params_sp)
  cases <- list(ps(list(rear = rule, spawn = rule), list(rear = g, spawn = g)),
                ps(NULL, list(rear = cw)), ps(NULL, list()))
  for (x in cases) for (st in c("spawn", "rear")) {
    open <- x
    open$ranges[[st]][["mad_m3s"]] <- c(0, 0)
    a <- fresh::frs_habitat_predicates(sp(x), model = "mad")[[st]]
    b <- fresh::frs_habitat_predicates(sp(open), model = "mad")[[st]]
    cw_pred <- fresh::frs_habitat_predicates(sp(x), model = "cw")[[st]]
    expect_identical(f(x, st), !identical(a, b) && !identical(cw_pred, "FALSE"),
                     info = paste(st, a))
  }
})

test_that("mad predicate expressions wrap exactly what classify embeds (#299)", {
  for (sp in c("BT", "CO", "SK")) {
    spp <- default_spp(sp)
    pr <- fresh::frs_habitat_predicates(spp, model = "mad")
    e <- link:::.lnk_hv_stage_exprs(spp, "mad")
    expect_identical(e[1], sprintf("coalesce((%s), false) AS pred_spawn", pr$spawn),
                     info = sp)
    expect_identical(e[7], sprintf(
      "coalesce((%s), false) AS pred_rear",
      sprintf("(%s) OR (%s) OR (%s)", pr$rear, pr$lake_rear, pr$wetland_rear)),
      info = sp)
  }
})

test_that("no bundled rules set a rule-level gradient or mad window", {
  # Relaxation moves the size to the stage's CSV minimum; a rule-level
  # window with a higher floor would turn size misses into rule_excludes.
  files <- list.files(system.file("extdata", "configs", package = "link"),
                      pattern = "^rules\\.yaml$", recursive = TRUE,
                      full.names = TRUE)
  expect_gt(length(files), 0L)
  key <- function(k) sprintf("^\\s*(-\\s*)?(%s):", k)
  for (f in files) {
    y <- readLines(f)
    # The pattern can match: rule-level channel_width is the same shape.
    expect_true(any(grepl(key("channel_width"), y)), info = f)
    expect_false(any(grepl(key("gradient|mad"), y)), info = f)
  }
})

test_that("a species with no MAD range gets a missing-threshold test on mad only (#299)", {
  # bcfishpass gives BT no MAD range; default has one since #307.
  spp <- default_spp("BT", bundle = "bcfishpass")
  expect_true(is.na(spp$params_sp$spawn_mad_min) && is.na(spp$params_sp$rear_mad_min))
  e <- link:::.lnk_hv_stage_exprs(spp, "mad")
  pick <- function(k) e[grepl(paste0(" AS ", k, "$"), e)]
  for (st in c("spawn", "rear")) {
    nm <- pick(paste0("pred_", st, "_nomad"))
    expect_false(grepl("NULL::boolean", nm, fixed = TRUE), info = st)
    expect_false(grepl("s.mad_m3s", nm, fixed = TRUE), info = st)
    # The gradient is still tested; only _nomad_g relaxes it.
    expect_true(grepl("s.gradient ", nm, fixed = TRUE), info = st)
    expect_false(grepl("s.gradient ",
                       pick(paste0("pred_", st, "_nomad_g")), fixed = TRUE),
                 info = st)
  }
  # fresh writes FALSE for the absent size test, so no relaxation reaches it.
  expect_true(grepl("AND FALSE", pick("pred_spawn_w"), fixed = TRUE))
  expect_true(all(grepl("NULL::boolean",
                        link:::.lnk_hv_stage_exprs(spp, "cw")[c(5, 6, 11, 12)],
                        fixed = TRUE)))
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

test_that(".lnk_hv_spec applies a per-WSG species_obs data frame (#290)", {
  presence <- data.frame(
    watershed_group_code = c("AAAA", "BBBB", "CCCC"),
    bt = c("t", "t", ""), ch = c("t", "t", "t"), notes = "",
    stringsAsFactors = FALSE)
  so <- link:::.lnk_hv_species_obs(data.frame(
    watershed_group_code = c("AAAA", "AAAA", "CCCC", "aaaa"),
    species_code = c("BT", "BT", "BT", "bt"),
    obs_species = c("BT", "DV", "DV", "dv ")))
  s <- link:::.lnk_hv_spec(presence, aoi = c("AAAA", "BBBB", "CCCC"),
                           species = c("BT", "CH"), species_obs = so)
  got <- paste(s$watershed_group_code, s$species_code, s$obs_species)
  # AAAA pools (deduplicated); BBBB is unlisted, so BT is itself only;
  # CCCC lists a pooling row but BT is absent there, so it yields nothing
  expect_setequal(got, c("AAAA BT BT", "AAAA BT DV", "AAAA CH CH",
                         "BBBB BT BT", "BBBB CH CH", "CCCC CH CH"))
})

test_that(".lnk_hv_species_obs rejects a malformed species_obs", {
  expect_error(link:::.lnk_hv_species_obs(
    data.frame(watershed_group_code = "AAAA", species_code = "BT")),
    "obs_species")
  expect_error(link:::.lnk_hv_species_obs(
    data.frame(watershed_group_code = "AAAA", species_code = "BT",
               obs_species = NA)), "NA")
  expect_error(link:::.lnk_hv_species_obs(list(c("BT", "DV"))), "named list")
  expect_identical(link:::.lnk_hv_species_obs(list(bt = c("bt", "dv"))),
                   list(BT = c("BT", "DV")))
})

test_that(".lnk_hv_spec returns a typed empty frame when nothing is present", {
  presence <- data.frame(watershed_group_code = "AAAA", bt = "",
                         stringsAsFactors = FALSE)
  s <- link:::.lnk_hv_spec(presence, "AAAA", "BT", list())
  expect_identical(nrow(s), 0L)
  expect_named(s, c("watershed_group_code", "species_code", "obs_species",
                    "obs_year_max"))
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
# BBBB, blue_line_key 2 (BT absent, so no observation scores here):
#   seg 1   0-100  spawning, rearing
#   seg 2 100-200  spawning, rearing; a lake connection line (edge 1450 in
#                  a lake polygon), so cost splits it out of rearing_km
local_validate_fixture <- function(conn, env = parent.frame()) {
  s <- "zz_lnk_validate_probe"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(
    try(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)),
        silent = TRUE), envir = env)
  wsg <- c(rep("AAAA", 5), "BBBB", "BBBB")
  ids <- c(1:5, 1L, 2L)
  lake_key <- DBI::dbGetQuery(conn, "
    SELECT waterbody_key FROM whse_basemapping.fwa_lakes_poly
     ORDER BY waterbody_key LIMIT 1")$waterbody_key
  DBI::dbWriteTable(conn, DBI::Id(schema = s, table = "streams"), data.frame(
    id_segment = ids, watershed_group_code = wsg,
    blue_line_key = c(rep(1L, 5), 2L, 2L),
    downstream_route_measure = c(0, 100, 200, 300, 400, 0, 100),
    upstream_route_measure = c(100, 200, 300, 400, 500, 100, 200),
    length_metre = 100,
    gradient = c(0.01, 0.08, 0.01, 0.20, 0.01, 0.01, 0.01),
    channel_width = c(5, 5, 5, 5, NA, 5, 5),
    channel_width_source = "MODELLED",
    edge_type = c(rep(1000L, 6), 1450L), stream_order = 3L,
    waterbody_key = c(rep(NA_integer_, 6), as.integer(lake_key))))
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
  # Cost leaves the lake connection line out of rearing_km and carries it
  # apart (#319); AAAA has none.
  expect_equal(b$rearing_km, rep(0.1, 3))
  expect_equal(b$rearing_lake_connection_km, rep(0.1, 3))
  expect_equal(a_any$rearing_km, 0.2)
  expect_equal(a_any$rearing_lake_connection_km, 0)
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

test_that("a species_obs data frame scores the same as the equivalent list", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  v_list <- run_validate(conn, s, aoi = "AAAA",
                         species_obs = list(BT = c("BT", "DV")))
  v_df <- run_validate(conn, s, aoi = "AAAA", species_obs = data.frame(
    watershed_group_code = "AAAA", species_code = "BT", obs_species = "DV"))
  expect_identical(v_df$summary, v_list$summary)
  v_none <- run_validate(conn, s, aoi = "AAAA", species_obs = data.frame(
    watershed_group_code = character(0), species_code = character(0),
    obs_species = character(0)))
  # o2 is the fixture's one admissible DV record (it shares a location with
  # BT record o7, so location counts cannot tell the two apart)
  expect_true("o2" %in% v_df$observations$observation_key)
  expect_false("o2" %in% v_none$observations$observation_key)
})

test_that("obs_year_max admits only pooled records dated within it (#290)", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  so <- data.frame(watershed_group_code = "AAAA", species_code = "BT",
                   obs_species = "DV", obs_year_max = 1994L)
  # the fixture has no observation_date, which a year limit needs
  expect_error(run_validate(conn, s, aoi = "AAAA", species_obs = so),
               "observation_date")
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s.observations ADD COLUMN observation_date date", s))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.observations SET observation_date = '1990-06-01'", s))
  v_old <- run_validate(conn, s, aoi = "AAAA", species_obs = so)
  expect_true("o2" %in% v_old$observations$observation_key)
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.observations SET observation_date = '2005-06-01'
      WHERE observation_key = 'o2'", s))
  v_new <- run_validate(conn, s, aoi = "AAAA", species_obs = so)
  expect_false("o2" %in% v_new$observations$observation_key)
  # an undated DV record does not meet the limit either
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.observations SET observation_date = NULL
      WHERE observation_key = 'o2'", s))
  v_na <- run_validate(conn, s, aoi = "AAAA", species_obs = so)
  expect_false("o2" %in% v_na$observations$observation_key)
  # BT's own records carry no limit. o2 (DV) shares a location with BT record
  # o7, so with o2 admitted the location is keyed o2 (BT;DV), and without it
  # the same location is keyed o7 (BT only).
  o <- function(v, k) v$observations[v$observations$observation_key == k, ]
  expect_identical(o(v_old, "o2")$obs_species, "BT;DV")
  expect_identical(o(v_new, "o7")$obs_species, "BT")
  expect_setequal(c(setdiff(v_old$observations$observation_key, "o2"), "o7"),
                  v_new$observations$observation_key)
})

test_that("observations can be a data frame from any source", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  mine <- data.frame(
    species_code = "BT", watershed_group_code = "AAAA", blue_line_key = 1L,
    downstream_route_measure = c(100, 50, 300),
    is_rear = c(TRUE, NA, FALSE),
    # Its own stage wins over bcfishobs wording where given.
    activity = c(NA, "Spawning", "Spawning"), is_spawn = c(NA, NA, FALSE))
  ld <- validate_loaded()
  ld$observation_exclusions <- NULL
  v <- lnk_habitat_validate(
    conn, aoi = "AAAA", cfg = lnk_config("default"),
    loaded = ld, species = "BT", schema = s,
    observations = mine, match_types = NULL, source_exclude = NULL)
  sm <- v$summary
  expect_identical(sm$n_obs[sm$stage == "any"], 3L)
  expect_identical(sm$n_obs[sm$stage == "rear"], 1L)
  expect_identical(sm$n_obs[sm$stage == "spawn"], 1L)
  # Keys are the caller's row numbers, so results join back.
  expect_setequal(v$observations$observation_key, c("1", "2", "3"))
  expect_identical(
    v$observations$observation_key[round(v$observations$m) == 300], "3")
  # The upstream segment rule still applies: 100 is segment 2.
  expect_identical(
    v$observations$id_segment[round(v$observations$m) == 100], 2L)
})

test_that("a filter whose column the source lacks is an error, not a pass", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  mine <- data.frame(species_code = "BT", watershed_group_code = "AAAA",
                     blue_line_key = 1L, downstream_route_measure = 50)
  ld <- validate_loaded()
  ld$observation_exclusions <- NULL
  go <- function(obs = mine, loaded = ld, ...) lnk_habitat_validate(
    conn, aoi = "AAAA", cfg = lnk_config("default"),
    loaded = loaded, species = "BT", schema = s,
    observations = obs, ...)
  expect_error(go(source_exclude = NULL), "match_types = NULL")
  expect_error(go(match_types = NULL), "source_exclude = NULL")
  # Exclusions are keyed on observation_key; without one they cannot apply.
  expect_error(go(loaded = validate_loaded(), match_types = NULL,
                  source_exclude = NULL), "observation_exclusions")
  expect_error(go(match_types = NULL, source_exclude = ""))
  expect_error(go(obs = mine[, -2], match_types = NULL, source_exclude = NULL),
               "watershed_group_code")
})

test_that("source_exclude matches a literal prefix, not a LIKE pattern", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  mine <- data.frame(species_code = "BT", watershed_group_code = "AAAA",
                     blue_line_key = 1L, downstream_route_measure = c(50, 300),
                     source = c("50% stocked", "500 survey"))
  ld <- validate_loaded()
  ld$observation_exclusions <- NULL
  v <- lnk_habitat_validate(
    conn, aoi = "AAAA", cfg = lnk_config("default"),
    loaded = ld, species = "BT", schema = s,
    observations = mine, match_types = NULL, source_exclude = "50%")
  expect_identical(round(v$observations$m), 300)
})

test_that("codes are normalised on the observation side, and 0/1 flags read as stage", {
  conn <- validate_conn()
  s <- local_validate_fixture(conn)
  mine <- data.frame(species_code = c("bt", "BT "),
                     watershed_group_code = c("aaaa", "AAAA"),
                     blue_line_key = 1L, downstream_route_measure = c(50, 300),
                     is_spawn = c(1, 0))
  ld <- validate_loaded()
  ld$observation_exclusions <- NULL
  v <- lnk_habitat_validate(
    conn, aoi = "AAAA", cfg = lnk_config("default"),
    loaded = ld, species = "BT", schema = s,
    observations = mine, match_types = NULL, source_exclude = NULL)
  sm <- v$summary
  expect_identical(sm$n_obs[sm$stage == "any"], 2L)
  expect_identical(sm$n_obs[sm$stage == "spawn"], 1L)
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
# -- mad groups (#299) --------------------------------------------------------

# The fixture with AAAA's segments tied to real FWA lines, so the discharge
# join has rows to find: seg 3 low discharge (inside CO rearing's MAD window,
# below spawning's), seg 1 no discharge (but a channel width), the rest
# high. Adds CO, with no modelled habitat, and two CO locations on AAAA
# (seg 3, seg 1).
local_mad_fixture <- function(conn, env = parent.frame()) {
  s <- local_validate_fixture(conn, env)
  if (!DBI::dbExistsTable(conn, DBI::Id(schema = "whse_basemapping",
                                        table = "fwa_stream_networks_discharge"))) {
    testthat::skip("no fwa_stream_networks_discharge in this database")
  }
  lf <- DBI::dbGetQuery(conn,
    "SELECT
       (SELECT linear_feature_id FROM whse_basemapping.fwa_stream_networks_discharge
         WHERE mad_m3s BETWEEN 0.05 AND 0.1 ORDER BY linear_feature_id LIMIT 1) AS low,
       (SELECT linear_feature_id FROM whse_basemapping.fwa_stream_networks_discharge
         WHERE mad_m3s IS NULL ORDER BY linear_feature_id LIMIT 1) AS none,
       (SELECT linear_feature_id FROM whse_basemapping.fwa_stream_networks_discharge
         WHERE mad_m3s > 2 ORDER BY linear_feature_id LIMIT 1) AS high")
  stmts <- strsplit(sprintf(
    "ALTER TABLE %1$s.streams ADD COLUMN linear_feature_id bigint;
     UPDATE %1$s.streams SET linear_feature_id = CASE
       WHEN watershed_group_code = 'AAAA' AND id_segment = 3 THEN %2$s
       WHEN watershed_group_code = 'AAAA' AND id_segment = 1 THEN %3$s
       ELSE %4$s END;
     ALTER TABLE %1$s.streams_access ADD COLUMN access_co integer DEFAULT 1;
     CREATE TABLE %1$s.streams_habitat_co AS
       SELECT id_segment, watershed_group_code, true AS accessible,
              false AS spawning, false AS rearing, false AS lake_rearing,
              false AS wetland_rearing
         FROM %1$s.streams_habitat_bt;
     INSERT INTO %1$s.observations
       (observation_key, species_code, watershed_group_code, blue_line_key,
        downstream_route_measure, match_type, source)
     VALUES ('c1', 'CO', 'AAAA', 1, 200, 'A.', 'FISS'),
            ('c2', 'CO', 'AAAA', 1, 20, 'A.', 'FISS')",
    s, format(lf$low, scientific = FALSE), format(lf$none, scientific = FALSE),
    format(lf$high, scientific = FALSE)), ";", fixed = TRUE)[[1]]
  for (st in stmts) DBI::dbExecute(conn, st)
  s
}

run_validate_mad <- function(conn, s, method = "watershed_group_code,model\nAAAA,mad",
                             fill = FALSE, mad_none = character(0)) {
  csv <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  writeLines(method, csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_method <- list(path = csv)
  if (length(mad_none) > 0L) {
    # Species given no MAD range, as every bundle left BT before #307.
    th <- utils::read.csv(cfg$files$parameters_habitat_thresholds$path,
                          check.names = FALSE, stringsAsFactors = FALSE)
    th[th$species_code %in% mad_none,
       c("spawn_mad_min", "spawn_mad_max", "rear_mad_min", "rear_mad_max")] <- NA
    th_csv <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
    utils::write.csv(th, th_csv, row.names = FALSE, na = "NA")
    cfg$files$parameters_habitat_thresholds <- list(path = th_csv)
  }
  cfg$pipeline$discharge_fill <- fill
  loaded <- validate_loaded()
  loaded$wsg_species_presence$co <- c("t", "")
  lnk_habitat_validate(conn, aoi = c("AAAA", "BBBB"), cfg = cfg,
                       loaded = loaded, species = c("BT", "CO"), schema = s,
                       observations = paste0(s, ".observations"))
}

test_that("a mad group is scored on discharge (#299)", {
  conn <- validate_conn()
  s <- local_mad_fixture(conn)
  v <- run_validate_mad(conn, s, mad_none = "BT")
  obs <- v$observations
  o <- function(k) obs[obs$observation_key == k, ]

  expect_true(all(obs$model[obs$watershed_group_code == "AAAA"] == "mad"))
  sm <- v$summary
  expect_true(all(sm$model[sm$watershed_group_code == "AAAA"] == "mad"))
  expect_true(all(sm$model[sm$watershed_group_code == "BBBB"] == "cw"))

  # c1: discharge below CO spawning's minimum, inside rearing's window.
  expect_true(o("c1")$mad_m3s >= 0.05 && o("c1")$mad_m3s <= 0.1)
  expect_identical(o("c1")$miss_reason_spawn, "fails_width")
  expect_identical(o("c1")$miss_reason_rear, "post_predicate")
  # c2: a channel width but no discharge; width_null keys on discharge.
  expect_true(is.na(o("c2")$mad_m3s))
  expect_false(is.na(o("c2")$channel_width))
  expect_identical(o("c2")$miss_reason_spawn, "width_null")
  expect_identical(o("c2")$miss_reason_rear, "width_null")

  # BT has no MAD thresholds. o10 fails on its NULL width under cw; under
  # mad nothing but the missing range keeps it out. o9's 20 % gradient
  # still fails, so it needs the gradient relaxed as well.
  expect_identical(o("o10")$miss_reason_rear, "no_mad_threshold")
  expect_identical(o("o9")$miss_reason_spawn, "fails_gradient_and_width")
  expect_identical(o("o9")$miss_reason_rear, "fails_gradient_and_width")
  # o2's segment is persisted spawning-free; under cw it passed the spawn
  # predicate (post_predicate), under mad it cannot. Its line has no
  # discharge, so a MAD range would not admit it either: the value is
  # missing, not the threshold.
  expect_false(o("o2")$pred_spawn)
  expect_true(is.na(o("o2")$mad_m3s))
  expect_identical(o("o2")$miss_reason_spawn, "width_null")
  expect_identical(o("o1")$miss_reason_rear, "not_accessible")
})

test_that("default's own BT MAD range scores the same fixture on discharge (#307)", {
  conn <- validate_conn()
  s <- local_mad_fixture(conn)
  v <- run_validate_mad(conn, s)
  obs <- v$observations
  o <- function(k) obs[obs$observation_key == k, ]
  # o10 and o9 sit at 10.5 m3/s, inside BT's range. o10 now passes its
  # predicate, and o9 fails on its 20 % gradient alone.
  expect_identical(o("o10")$miss_reason_rear, "post_predicate")
  expect_identical(o("o9")$miss_reason_spawn, "fails_gradient")
  expect_identical(o("o9")$miss_reason_rear, "fails_gradient")
  expect_false(any(c(obs$miss_reason_spawn, obs$miss_reason_rear) %in%
                     "no_mad_threshold"))
})

test_that("the same fixture on cw keeps the cw reasons and reports no discharge (#299)", {
  conn <- validate_conn()
  s <- local_mad_fixture(conn)
  v <- run_validate_mad(conn, s, method = "watershed_group_code,model\nAAAA,cw")
  obs <- v$observations
  o <- function(k) obs[obs$observation_key == k, ]
  expect_true(all(obs$model == "cw"))
  expect_true(all(is.na(obs$mad_m3s)))
  expect_true(all(is.na(obs$pred_spawn_nomad)))
  expect_identical(o("o9")$miss_reason_spawn, "fails_gradient")
  expect_identical(o("o10")$miss_reason_rear, "width_null")
  expect_identical(o("o2")$miss_reason_spawn, "post_predicate")
  expect_false(any(c(obs$miss_reason_spawn, obs$miss_reason_rear) %in%
                     "no_mad_threshold"))
})
test_that("a mad group is scored on the discharge fill it was built with (#305)", {
  conn <- validate_conn()
  s <- local_mad_fixture(conn)
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.log (watershed_group_code text, config_name text,
                         date_start timestamptz, discharge_fill boolean)", s))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log VALUES ('AAAA', 'default', '2026-01-01', NULL),
                               ('BBBB', 'default', '2026-01-01', NULL)", s))
  # Logged before the fill existed (NULL): built raw, so a filling cfg is
  # refused, for the mad group only (BBBB is cw: nothing applies there).
  expect_error(run_validate_mad(conn, s, fill = TRUE),
               "\\(logged/cfg\\): AAAA \\(off/on\\)$")
  v <- run_validate_mad(conn, s)
  o <- v$observations
  expect_identical(o$mad_m3s_source[o$observation_key == "c1"], "modelled")
  expect_true(all(is.na(o$mad_m3s_source[o$model == "cw"])))

  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET discharge_fill = true
      WHERE watershed_group_code = 'AAAA'", s))
  expect_error(run_validate_mad(conn, s), "AAAA \\(on/off\\)$")
  # Built filled and scored filled: c1's valued line is unchanged, and c2's
  # NULL line reads exactly what the builder (prepare's source) gives it.
  f <- run_validate_mad(conn, s, fill = TRUE)$observations
  expect_identical(f$mad_m3s[f$observation_key == "c1"],
                   o$mad_m3s[o$observation_key == "c1"])
  expect_identical(f$mad_m3s_source[f$observation_key == "c1"], "modelled")
  want <- DBI::dbGetQuery(conn, sprintf(
    "SELECT d.mad_m3s, d.mad_m3s_source FROM %s d", link:::.lnk_discharge_sql(
      fill = TRUE, lines = sprintf(
        "SELECT linear_feature_id FROM %s.streams
          WHERE watershed_group_code = 'AAAA' AND id_segment = 1", s))))
  expect_identical(nrow(want), 1L)
  expect_identical(f$mad_m3s[f$observation_key == "c2"], want$mad_m3s)
  expect_identical(f$mad_m3s_source[f$observation_key == "c2"],
                   want$mad_m3s_source)
  # Unfilled, it was missing (c2 above reads width_null on the raw table).
  expect_true(is.na(o$mad_m3s[o$observation_key == "c2"]))
})
test_that("a mixed aoi fills only the groups the fill applies to (#305)", {
  conn <- validate_conn()
  s <- local_mad_fixture(conn)
  csv <- withr::local_tempfile(fileext = ".csv")
  cfg <- lnk_config("default")
  cfg$pipeline$discharge_fill <- TRUE
  cfg$files$parameters_habitat_method <- list(path = csv)
  # Point AAAA's segment 1 at an edge 1250 line the fill reaches: absent from
  # the table, in a covered group, with a valued line upstream on its line.
  lf <- DBI::dbGetQuery(conn,
    "SELECT s.linear_feature_id
       FROM whse_basemapping.fwa_stream_networks_sp s
       LEFT JOIN whse_basemapping.fwa_stream_networks_discharge d
         ON d.linear_feature_id = s.linear_feature_id
      WHERE s.edge_type = 1250 AND d.linear_feature_id IS NULL
        AND s.watershed_group_code IN (
          SELECT watershed_group_code
            FROM whse_basemapping.fwa_stream_networks_discharge
           WHERE mad_m3s IS NOT NULL)
        AND EXISTS (
          SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s2
            JOIN whse_basemapping.fwa_stream_networks_discharge d2
              ON d2.linear_feature_id = s2.linear_feature_id
           WHERE s2.blue_line_key = s.blue_line_key
             AND s2.downstream_route_measure > s.downstream_route_measure
             AND d2.mad_m3s IS NOT NULL)
      ORDER BY s.linear_feature_id LIMIT 1")[[1]]
  skip_if(length(lf) == 0L, "no fillable edge 1250 line")
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams SET linear_feature_id = %s
      WHERE watershed_group_code = 'AAAA' AND id_segment = 1", s,
    format(lf, scientific = FALSE)))
  want <- DBI::dbGetQuery(conn, sprintf(
    "SELECT mad_m3s, mad_m3s_source FROM %s d",
    link:::.lnk_discharge_sql(fill = TRUE, lines = format(lf, scientific = FALSE))))
  expect_identical(want$mad_m3s_source, "fill_upstream")
  read_lf <- function() {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT mad_m3s, mad_m3s_source FROM %s d WHERE d.linear_feature_id = %s",
      link:::.lnk_hv_discharge_src(conn, s, c("AAAA", "BBBB"), cfg),
      format(lf, scientific = FALSE)))
  }
  # AAAA on mad: its line is filled, as prepare fills it.
  writeLines("watershed_group_code,model\nAAAA,mad", csv)
  expect_identical(read_lf(), want)
  # AAAA on cw beside BBBB on mad: prepare never filled AAAA, so neither does
  # the validator, though the call fills BBBB.
  writeLines("watershed_group_code,model\nBBBB,mad", csv)
  # The line is absent from the raw table, so the raw relation has no row
  # for it: the join reads NULL, as prepare's did.
  expect_identical(nrow(read_lf()), 0L)
})
# nolint end: indentation_linter
