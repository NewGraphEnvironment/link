# The record rule (link#470): which fish records count, as which species.

presence_rr <- function() {
  data.frame(
    watershed_group_code = c("LFRA", "SQAM"),
    bt = "t", ch = "t", cm = "", co = "", ct = "t", dv = "t", pk = "",
    rb = "", sk = "", st = "t", wct = "", notes = "",
    stringsAsFactors = FALSE)
}

tracker_rr <- function() {
  rbind(
    data.frame(species_code = "BT", species_obs = "DV", scope_level = "region",
               scope = "Fraser", pool = "yes"),
    data.frame(species_code = "BT", species_obs = "BT/DV",
               scope_level = "region", scope = "Fraser", pool = "yes"),
    data.frame(species_code = "CT", species_obs = "CCT",
               scope_level = "province", scope = "BC", pool = "yes"),
    data.frame(species_code = "ST", species_obs = "SST",
               scope_level = "province", scope = "BC", pool = "yes"))
}

pf_rr <- function() {
  data.frame(species_code = c("BT", "CH", "ST", "CT", "DV"),
             observation_date_min = c(NA, "1990-01-01", "1990-01-01", NA, NA),
             stringsAsFactors = FALSE)
}

cfg_rr <- function(record_date = NULL) {
  list(name = "rr", pipeline = list(observation_record_date = record_date))
}

codes_for <- function(m, w, sp) {
  sort(m$species_obs[m$watershed_group_code == w & m$species_code == sp])
}

test_that("without a tracker each species counts its own code only", {
  m <- .lnk_observation_species_map(
    cfg_rr(), list(wsg_species_presence = presence_rr()), c("LFRA", "SQAM"))
  expect_true(all(m$species_obs == m$species_code))
  expect_equal(codes_for(m, "LFRA", "CT"), "CT")
  expect_true(all(is.na(m$date_min)))
})

test_that("the tracker adds aliases everywhere and pooling only where it applies", {
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rr(), parameters_fresh = pf_rr())
  m <- .lnk_observation_species_map(cfg_rr(), ld, c("LFRA", "SQAM"))
  expect_equal(codes_for(m, "LFRA", "BT"), c("BT", "BT/DV", "DV"))
  expect_equal(codes_for(m, "SQAM", "BT"), "BT")
  expect_equal(codes_for(m, "SQAM", "CT"), c("CCT", "CT"))
  expect_equal(codes_for(m, "SQAM", "ST"), c("SST", "ST"))
  # a pooled DV still counts as DV too
  expect_equal(codes_for(m, "LFRA", "DV"), "DV")
})

test_that("lift_floor holds each target species to its own lift floor", {
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rr(), parameters_fresh = pf_rr())
  m <- .lnk_observation_species_map(cfg_rr("lift_floor"), ld, "SQAM")
  d <- function(sp, obs) m$date_min[m$species_code == sp & m$species_obs == obs]
  expect_equal(d("ST", "SST"), as.Date("1990-01-01"))
  expect_equal(d("CH", "CH"), as.Date("1990-01-01"))
  expect_true(is.na(d("BT", "BT")))
  m_any <- .lnk_observation_species_map(cfg_rr("any"), ld, "SQAM")
  expect_true(all(is.na(m_any$date_min)))
  expect_error(.lnk_observation_species_map(
    cfg_rr("lift_floor"), ld[c("wsg_species_presence", "species_pooling")],
    "SQAM"), "parameters_fresh")
})

test_that("the observation tables refuse a call with no bundle", {
  expect_error(
    .lnk_pipeline_prep_observations("mock", "W1",
      list(wsg_species_presence = presence_rr()), "w_x"),
    "needs cfg")
})

test_that("an alias reads as one species in the zones only if every group lists it", {
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rr())
  a <- .lnk_record_aliases(ld, c("LFRA", "SQAM"))
  ev <- .lnk_record_aliases_everywhere(a)
  # CCT and SST are province rows; BT/DV is the Fraser's alone (LFRA)
  expect_setequal(ev$species_obs, c("CCT", "SST"))
  # resolved for LFRA only, BT/DV is listed in every group resolved
  ev1 <- .lnk_record_aliases_everywhere(.lnk_record_aliases(ld, "LFRA"))
  expect_true("BT/DV" %in% ev1$species_obs)
  # with only the regional row, BT/DV is not everywhere when SQAM is resolved
  ld2 <- ld
  ld2$species_pooling <- tracker_rr()[tracker_rr()$species_obs == "BT/DV", ]
  ev2 <- .lnk_record_aliases_everywhere(.lnk_record_aliases(ld2, c("LFRA", "SQAM")))
  expect_equal(nrow(ev2), 0L)
})

test_that("observation_record_date is checked", {
  expect_identical(.lnk_observation_record_date(list()), "any")
  expect_error(.lnk_observation_record_date(cfg_rr("since_1990")),
               "observation_record_date")
  expect_identical(lnk_config("default")$pipeline$observation_record_date,
                   "lift_floor")
  expect_null(lnk_config("bcfishpass")$pipeline$observation_record_date)
})

test_that("default's two-way char codes count as BT exactly where DV does", {
  cfg <- lnk_config("default")
  ld <- suppressWarnings(lnk_load_overrides(cfg))
  m <- .lnk_observation_species_map(
    cfg, ld, ld$wsg_species_presence$watershed_group_code)
  bt <- m[m$species_code == "BT", ]
  where <- function(code) sort(bt$watershed_group_code[bt$species_obs == code])
  expect_gt(length(where("DV")), 0L)
  expect_identical(where("BT/DV"), where("DV"))
  expect_identical(where("DV/BT"), where("DV"))
  # RB/CT counts as nothing; the steelhead aliases count as ST wherever ST is
  expect_false("RB/CT" %in% m$species_obs)
  st <- m[m$species_code == "ST", ]
  expect_identical(sort(st$watershed_group_code[st$species_obs == "SST"]),
                   sort(st$watershed_group_code[st$species_obs == "ST"]))
  # BT's lift no longer lists DV: DV counts only through the tracker
  expect_identical(
    ld$parameters_fresh$observation_species[ld$parameters_fresh$species_code == "BT"],
    "BT")
})

test_that("the observation table holds model species and the walk reads aliases (DB)", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ex <- function(sql) DBI::dbExecute(conn, sql)
  # One segment of SQAM on line 10; upstream of it a CCT record (CT's alias),
  # an SST record, a 1985 CH record and a BT/DV record.
  ex("CREATE TEMP TABLE seg470 (id_segment int, watershed_group_code text,
        blue_line_key int, downstream_route_measure float8,
        wscode_ltree ltree, localcode_ltree ltree)")
  ex("INSERT INTO seg470 VALUES (1, 'SQAM', 10, 100, '100.200', '100.200')")
  ex("CREATE TEMP TABLE src470 (observation_key text,
        watershed_group_code text, species_code text, observation_date date,
        blue_line_key int, downstream_route_measure float8,
        wscode ltree, localcode ltree)")
  ex("INSERT INTO src470 VALUES
        ('k1', 'SQAM', 'CCT', '2001-06-01', 10, 500, '100.200', '100.200'),
        ('k2', 'SQAM', 'SST', '2001-06-01', 10, 600, '100.200', '100.200'),
        ('k3', 'SQAM', 'CH', '1985-06-01', 10, 700, '100.200', '100.200'),
        ('k4', 'SQAM', 'BT/DV', '2001-06-01', 10, 800, '100.200', '100.200')")
  ex("CREATE TEMP TABLE barriers_none (barriers_none_id text,
        watershed_group_code text, blue_line_key int,
        downstream_route_measure float8, wscode_ltree ltree,
        localcode_ltree ltree)")
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rr(), parameters_fresh = pf_rr())
  build <- function(cfg, loaded) {
    m <- .lnk_observation_species_map(cfg, loaded, "SQAM")
    .lnk_observation_table_build(conn, "pg_temp.obs470", "pg_temp.src470", m)
    DBI::dbGetQuery(conn, "SELECT observation_key, species_code,
                             species_code_recorded
                           FROM pg_temp.obs470 ORDER BY 1")
  }
  walk <- function() {
    withCallingHandlers(
      lnk_pipeline_access(
        conn, segments = "pg_temp.seg470", aoi = "SQAM",
        barriers_per_sp = list(ct = "pg_temp.barriers_none",
                               st = "pg_temp.barriers_none",
                               ch = "pg_temp.barriers_none",
                               bt = "pg_temp.barriers_none"),
        observations = "pg_temp.obs470",
        wsg_presence = list(ct = TRUE, st = TRUE, ch = TRUE, bt = TRUE)),
      warning = function(w) {
        if (grepl("simple features geometry column", conditionMessage(w))) {
          invokeRestart("muffleWarning")
        }
      })
  }

  # default's rule: aliases fold, the 1985 CH record is below CH's floor,
  # BT/DV counts as nothing in SQAM (DV does not pool into BT there)
  got <- build(cfg_rr("lift_floor"), ld)
  expect_equal(got$species_code, c("CT", "ST"))
  expect_equal(got$species_code_recorded, c("CCT", "SST"))
  a <- walk()
  expect_identical(c(a$access_ct, a$access_st, a$access_ch, a$access_bt),
                   c(2L, 2L, 1L, 1L))

  # exact codes (no tracker), any date: the CCT record no longer makes CT
  # known; this is the reading before #470, and the bcfishpass bundle's
  got <- build(cfg_rr("any"), ld[c("wsg_species_presence", "parameters_fresh")])
  expect_equal(got$species_code, "CH")
  a <- walk()
  expect_identical(c(a$access_ct, a$access_st, a$access_ch),
                   c(1L, 1L, 2L))
})

test_that("default's resident floors leave undated records counting", {
  cfg <- lnk_config("default")
  ld <- suppressWarnings(lnk_load_overrides(cfg))
  m <- .lnk_observation_species_map(cfg, ld,
                                    ld$wsg_species_presence$watershed_group_code)
  for (sp in c("BT", "RB", "WCT", "CT", "DV")) {
    expect_true(all(is.na(m$date_min[m$species_code == sp])), info = sp)
  }
  for (sp in c("CH", "CO", "SK", "ST")) {
    expect_true(all(m$date_min[m$species_code == sp] == as.Date("1990-01-01")),
                info = sp)
  }
})

test_that("lift_floor refuses a lift list that mixes date floors", {
  pf <- data.frame(species_code = c("ST", "BT"),
                   observation_threshold = c(1, 1),
                   observation_date_min = c("1990-01-01", NA),
                   observation_species = c("ST;BT", "BT"),
                   stringsAsFactors = FALSE)
  ld <- list(wsg_species_presence = presence_rr(), parameters_fresh = pf)
  expect_error(.lnk_observation_species_map(cfg_rr("lift_floor"), ld, "SQAM"),
               "ST's lift counts BT")
  pf$observation_species[1] <- "ST"
  ld$parameters_fresh <- pf
  expect_silent(.lnk_observation_species_map(cfg_rr("lift_floor"), ld, "SQAM"))
})

test_that("every alias code default's tracker names is a code bcfishobs uses (DB)", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  ld <- suppressWarnings(lnk_load_overrides(lnk_config("default")))
  a <- unique(.lnk_record_aliases(
    ld, ld$wsg_species_presence$watershed_group_code)$species_obs)
  expect_gt(length(a), 0L)
  have <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT species_code FROM bcfishobs.observations
     WHERE species_code IN (%s)",
    paste(vapply(a, .lnk_quote_literal, character(1)), collapse = ", ")))
  expect_setequal(have$species_code, a)
})

# Rainbow trout and steelhead (link#501): ST records count as RB where RB is
# present; RB records never count as ST; SST and WST count as both.
tracker_rb <- function() {
  rbind(tracker_rr(),
        data.frame(species_code = "RB", species_obs = "ST",
                   scope_level = "province", scope = "BC", pool = "yes"),
        data.frame(species_code = "RB", species_obs = "SST",
                   scope_level = "province", scope = "BC", pool = "yes"))
}

presence_rb <- function() {
  p <- presence_rr()
  p$rb[p$watershed_group_code == "SQAM"] <- "t"
  p
}

test_that("a steelhead record counts as rainbow trout only where RB is present", {
  ld <- list(wsg_species_presence = presence_rb(),
             species_pooling = tracker_rb(), parameters_fresh = pf_rr())
  m <- .lnk_observation_species_map(cfg_rr(), ld, c("LFRA", "SQAM"))
  expect_equal(codes_for(m, "SQAM", "RB"), c("RB", "SST", "ST"))
  expect_equal(codes_for(m, "LFRA", "RB"), character(0))
  # an RB record never counts as ST, and SST still counts as ST
  expect_equal(codes_for(m, "SQAM", "ST"), c("SST", "ST"))
  expect_equal(codes_for(m, "LFRA", "ST"), c("SST", "ST"))
})

test_that("a steelhead record counted as RB takes RB's date floor, not ST's", {
  pf <- rbind(pf_rr(), data.frame(species_code = "RB", observation_date_min = NA))
  ld <- list(wsg_species_presence = presence_rb(),
             species_pooling = tracker_rb(), parameters_fresh = pf)
  m <- .lnk_observation_species_map(cfg_rr("lift_floor"), ld, "SQAM")
  d <- function(sp, obs) m$date_min[m$species_code == sp & m$species_obs == obs]
  # undated and pre-1990 ST records cut and set code 2 for RB ...
  expect_true(is.na(d("RB", "ST")))
  expect_true(is.na(d("RB", "SST")))
  # ... and stay held to 1990 for ST
  expect_equal(d("ST", "ST"), as.Date("1990-01-01"))
  expect_equal(d("ST", "SST"), as.Date("1990-01-01"))
})

test_that("an alias can count as two species, in the records and the zones", {
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rb())
  a <- .lnk_record_aliases(ld, c("LFRA", "SQAM"))
  sst <- a[a$species_obs == "SST", ]
  # resolved as if every species were present, in both groups
  expect_setequal(paste(sst$watershed_group_code, sst$species_code),
                  c("LFRA RB", "LFRA ST", "SQAM RB", "SQAM ST"))
  ev <- .lnk_record_aliases_everywhere(a)
  expect_equal(ev$species_code[ev$species_obs == "SST"], c("RB", "ST"))
  expect_false("BT/DV" %in% ev$species_obs)
})

test_that("the RB rows move the record-rule digest", {
  cfg <- cfg_rr("lift_floor")
  pf <- rbind(pf_rr(), data.frame(species_code = "RB", observation_date_min = NA))
  ld <- list(wsg_species_presence = presence_rr(),
             species_pooling = tracker_rr(), parameters_fresh = pf)
  ld_rb <- ld
  ld_rb$species_pooling <- tracker_rb()
  expect_false(identical(.lnk_record_rule_digest(cfg, ld),
                         .lnk_record_rule_digest(cfg, ld_rb)))
})

test_that("default counts ST, SST and WST as RB wherever RB is present, and RB never as ST", {
  cfg <- lnk_config("default")
  ld <- suppressWarnings(lnk_load_overrides(cfg))
  pres <- ld$wsg_species_presence
  m <- .lnk_observation_species_map(cfg, ld, pres$watershed_group_code)
  rb_groups <- sort(pres$watershed_group_code[pres$rb %in% c("t", TRUE)])
  rb <- m[m$species_code == "RB", ]
  for (code in c("RB", "ST", "SST", "WST")) {
    expect_identical(sort(rb$watershed_group_code[rb$species_obs == code]),
                     rb_groups, info = code)
  }
  expect_false("RB" %in% m$species_obs[m$species_code == "ST"])
  # SST and WST still count as ST wherever ST is present
  st <- m[m$species_code == "ST", ]
  expect_identical(sort(st$watershed_group_code[st$species_obs == "WST"]),
                   sort(st$watershed_group_code[st$species_obs == "ST"]))
})
