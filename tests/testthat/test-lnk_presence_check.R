# .lnk_presence_check() and friends (#402): a presence table judged against
# fish records. Real species codes, because the CT aliases and lnk_presence()'s
# groups are keyed on them; synthetic groups and regions.

regions_pc <- data.frame(
  watershed_group_code = c("W1", "W2"),
  region = c("North", "South"),
  subregion = NA_character_,
  stringsAsFactors = FALSE
)

presence_pc <- data.frame(
  watershed_group_code = c("W1", "W2"),
  bt = c("t", ""),
  ch = c("", "t"),
  co = c("", ""),
  ct = c("", ""),
  dv = c("t", "t"),
  notes = c("", "Kenny Dam"),
  stringsAsFactors = FALSE
)

loaded_pc <- function(presence = presence_pc, exclusions = NULL,
                      pooling = NULL) {
  list(wsg_species_presence = presence,
       observation_exclusions = exclusions,
       species_pooling = pooling,
       species_groups = NULL)
}

rec <- function(key, w, sp, date = "2000-06-01", source = "FISS Database: x",
                source_ref = NA_character_) {
  data.frame(observation_key = key, watershed_group_code = w,
             species_code = sp, observation_date = as.Date(date),
             source = source, source_ref = source_ref,
             stringsAsFactors = FALSE)
}

cell <- function(res, w, sp) {
  res[res$watershed_group_code == w & res$species_code == sp, , drop = FALSE]
}

check <- function(records, loaded = loaded_pc(), ...) {
  .lnk_presence_check(records, loaded, regions = regions_pc,
                      year_now = 2026L, ...)
}

test_that("one cell per group and species, judged as written", {
  res <- check(rec("k1", "W1", "BT"))
  expect_identical(nrow(res), 10L)
  expect_identical(cell(res, "W1", "BT")$flag, NA_character_)
  expect_identical(cell(res, "W1", "DV")$flag, "present_unsupported")
  expect_identical(cell(res, "W2", "CH")$flag, "present_unsupported")
  expect_true(all(is.na(res$flag[!res$present_raw])))
})

test_that("a single record flags an absent cell; none flags a present one", {
  res <- check(rec("k1", "W2", "CO"))
  expect_identical(cell(res, "W2", "CO")$flag, "absent_recorded")
  expect_identical(cell(res, "W2", "CO")$n_kept, 1L)
  res0 <- check(rec("k1", "W1", "CH", date = "1940-01-01"))
  expect_identical(cell(res0, "W1", "CH")$flag, NA_character_)
})

test_that("n_min sets the line", {
  r <- rbind(rec("k1", "W2", "CO"), rec("k2", "W2", "CO"))
  expect_identical(cell(check(r, n_min = 3L), "W2", "CO")$flag, NA_character_)
  expect_identical(cell(check(r, n_min = 2L), "W2", "CO")$flag, "absent_recorded")
})

test_that("the date floor: 1949 does not count, 1950 does", {
  r49 <- check(rec("k1", "W1", "DV", date = "1949-12-31"))
  expect_identical(cell(r49, "W1", "DV")$flag, "present_unsupported")
  expect_identical(cell(r49, "W1", "DV")$n_before_floor, 1L)
  r50 <- check(rec("k1", "W1", "DV", date = "1950-01-01"))
  expect_identical(cell(r50, "W1", "DV")$flag, NA_character_)
})

test_that("undated and impossible years count as undated", {
  r <- rbind(rec("k1", "W1", "DV", date = NA),
             rec("k2", "W1", "DV", date = "9999-11-01"),
             rec("k3", "W1", "DV", date = "1007-08-03"))
  res <- check(r)
  expect_identical(cell(res, "W1", "DV")$n_undated, 3L)
  expect_identical(cell(res, "W1", "DV")$flag, "present_unsupported")
})

test_that("cutthroat aliases count as CT", {
  r <- rbind(rec("k1", "W1", "CCT"), rec("k2", "W1", "ACT"),
             rec("k3", "W1", "CT/RB"), rec("k4", "W1", "CT"))
  expect_identical(cell(check(r), "W1", "CT")$n_kept, 4L)
})

test_that("each of the four release tags keeps a record out", {
  ex <- data.frame(observation_key = "k4", data_error = NA,
                   release_exclude = NA, release_include = "t",
                   stringsAsFactors = FALSE)
  r <- rbind(rec("k1", "W2", "CO", source = "Releases Database: hatchery"),
             rec("k2", "W2", "CO", source_ref = "bc release records database 1990"),
             rec("k3", "W2", "CO", source_ref = "Stocking program"),
             rec("k4", "W2", "CO"))
  res <- check(r, loaded_pc(exclusions = ex))
  expect_identical(cell(res, "W2", "CO")$n_releases, 4L)
  expect_identical(cell(res, "W2", "CO")$n_kept, 0L)
  expect_identical(cell(res, "W2", "CO")$flag, NA_character_)
  # The source test reads up to the first colon, as bcfishpass's does.
  r5 <- rec("k5", "W2", "CO", source = "FISS Database: Releases Database: x")
  expect_identical(cell(check(r5), "W2", "CO")$n_releases, 0L)
})

test_that("excluded records do not count, and are not also releases", {
  ex <- data.frame(observation_key = c("k1", "k2"),
                   data_error = c("t", NA), release_exclude = c(NA, TRUE),
                   release_include = NA, stringsAsFactors = FALSE)
  r <- rbind(rec("k1", "W2", "CO"),
             rec("k2", "W2", "CO", source = "Releases Database: x"))
  res <- check(r, loaded_pc(exclusions = ex))
  expect_identical(cell(res, "W2", "CO")$n_excluded, 2L)
  expect_identical(cell(res, "W2", "CO")$n_releases, 0L)
  expect_identical(cell(res, "W2", "CO")$n_kept, 0L)
})

test_that("pooling counts only where the tracker pools, absent cells included", {
  p <- data.frame(species_code = "BT", species_obs = "DV",
                  scope_level = "region", scope = "South", pool = "yes",
                  stringsAsFactors = FALSE)
  r <- rbind(rec("k1", "W1", "DV"), rec("k2", "W2", "DV"))
  res <- check(r, loaded_pc(pooling = p))
  # W2 pools and marks BT absent: the DV record still reaches BT.
  expect_identical(cell(res, "W2", "BT")$n_kept_pooled, 1L)
  expect_identical(cell(res, "W2", "BT")$n_kept_own, 0L)
  expect_identical(cell(res, "W2", "BT")$flag, "absent_recorded")
  # W1 does not pool: its DV record supports DV only.
  expect_identical(cell(res, "W1", "BT")$n_kept_pooled, 0L)
  expect_identical(cell(res, "W1", "BT")$flag, "present_unsupported")
  # DV is judged on DV records alone.
  expect_identical(cell(res, "W2", "DV")$n_kept, 1L)
})

test_that("a pooling row's year limit applies to the pooled records", {
  p <- data.frame(species_code = "BT", species_obs = "DV",
                  scope_level = "region", scope = "South", pool = "yes",
                  obs_year_max = "1994", stringsAsFactors = FALSE)
  r <- rbind(rec("k1", "W2", "DV", date = "1994-06-01"),
             rec("k2", "W2", "DV", date = "1995-06-01"))
  expect_identical(cell(check(r, loaded_pc(pooling = p)), "W2", "BT")$n_kept_pooled, 1L)
})

test_that("promotion is reported beside the cell, not judged", {
  res <- check(rec("k1", "W2", "CO"))
  co <- cell(res, "W2", "CO")
  expect_false(co$present_raw)
  expect_true(co$present_promoted)
  expect_identical(co$promoted_by, "salmon (CH)")
  expect_identical(co$flag, "absent_recorded")
  expect_true(is.na(cell(res, "W1", "BT")$promoted_by))
  # Marked as written, so nothing promotes it, even inside a group.
  expect_true(is.na(cell(res, "W2", "CH")$promoted_by))
})

test_that("records outside the table's groups and species are ignored", {
  r <- rbind(rec("k1", "W9", "BT"), rec("k2", "W1", "SK"))
  res <- check(r)
  expect_identical(sum(res$n_records), 0L)
})

test_that("stories name the evidence and the group note", {
  r <- rbind(rec("k1", "W2", "CO", date = "2019-07-01", source = "FDIS Database: a"),
             rec("k2", "W1", "DV", source = "Releases Database: x"))
  res <- check(r)
  fl <- res[!is.na(res$flag), , drop = FALSE]
  st <- .lnk_presence_story(fl)
  co <- st[fl$watershed_group_code == "W2" & fl$species_code == "CO"]
  expect_match(co, "a single record (2019; FDIS Database)", fixed = TRUE)
  expect_match(co, "The salmon (CH) group makes it present", fixed = TRUE)
  expect_match(co, "Group note: \"Kenny Dam\".", fixed = TRUE)
  dv <- st[fl$watershed_group_code == "W1" & fl$species_code == "DV"]
  expect_match(dv, "1 record of DV, none counting: 1 release.", fixed = TRUE)
  bt <- st[fl$watershed_group_code == "W2" & fl$species_code == "DV"]
  expect_match(bt, "no record of DV in the group", fixed = TRUE)
})

test_that("a story above n_min = 1 says how many records count", {
  r <- rbind(rec("k1", "W1", "BT"), rec("k2", "W1", "BT"),
             rec("k3", "W1", "BT", source = "Releases Database: x"))
  res <- check(r, n_min = 3L)
  bt <- cell(res, "W1", "BT")
  expect_identical(bt$flag, "present_unsupported")
  st <- .lnk_presence_story(bt)
  expect_identical(st, paste0("Marked present; 2 counting records, fewer ",
                              "than the 3 the rule asks for (also 1 release, ",
                              "not counted)."))
  # The story reads the year the count was taken at, from the row.
  two <- rbind(rec("k1", "W2", "CO", date = "1995-01-01"),
               rec("k2", "W2", "CO", date = "2001-01-01"))
  co <- cell(check(two, year_recent = 2000L), "W2", "CO")
  expect_identical(co$n_since_recent, 1L)
  expect_match(.lnk_presence_story(co), "1 since 2000 (", fixed = TRUE)
  expect_match(.lnk_presence_story(cell(check(two), "W2", "CO")),
               "2 since 1990 (", fixed = TRUE)
  expect_error(.lnk_presence_story(co[, setdiff(names(co), "year_recent")]),
               "year_recent")
})

test_that("a pooled-only flag says its records are another species'", {
  p <- data.frame(species_code = "BT", species_obs = "DV",
                  scope_level = "region", scope = "South", pool = "yes",
                  stringsAsFactors = FALSE)
  res <- check(rec("k1", "W2", "DV", date = "1999-01-01"), loaded_pc(pooling = p))
  bt <- cell(res, "W2", "BT")
  expect_identical(bt$pooled_from, "DV")
  ld <- loaded_pc(pooling = p)
  ld$parameters_fresh <- data.frame(species_code = "BT",
                                    observation_species = "BT;DV",
                                    stringsAsFactors = FALSE)
  bt <- cell(check(rec("k1", "W2", "DV", date = "1999-01-01"), ld), "W2", "BT")
  st <- .lnk_presence_story(bt)
  expect_match(st, "all of them DV records pooled into BT", fixed = TRUE)
  # DV's own cell keeps those records, so nothing is dropped: no lift sentence.
  expect_no_match(st, "dropped")
})

test_that("the story names the species whose lifts read the cell", {
  ld <- loaded_pc()
  ld$parameters_fresh <- data.frame(
    species_code = c("BT", "CH", "CO", "CT", "DV"),
    observation_species = c("BT;DV", "CH;CO", "CH;CO", NA, NA),
    stringsAsFactors = FALSE)
  res <- check(rec("k1", "W2", "CO"), ld)
  co <- cell(res, "W2", "CO")
  expect_identical(co$lift_readers, "CH, CO")
  expect_match(.lnk_presence_story(co),
               "its own CO records are dropped before the observation breaks and from the barrier lifts of CH, CO.",
               fixed = TRUE)
  expect_true(is.na(cell(res, "W1", "CT")$lift_readers))
})

test_that("records under codes the table has no column for are counted apart", {
  r <- rbind(rec("k1", "W1", "WST"), rec("k2", "W1", "WST"),
             rec("k3", "W2", "BT/DV"), rec("k4", "W9", "WST"))
  oc <- attr(check(r), "other_codes")
  oc <- oc[order(oc$watershed_group_code), ]
  expect_identical(oc$watershed_group_code, c("W1", "W2"))
  expect_identical(oc$species_code, c("WST", "BT/DV"))
  expect_identical(as.integer(oc$n), c(2L, 1L))
  expect_identical(nrow(attr(check(rec("k1", "W1", "BT")), "other_codes")), 0L)
})

test_that("records must carry their columns and a Date", {
  expect_error(check(rec("k1", "W1", "BT")[, -1]), "observation_key")
  r <- rec("k1", "W1", "BT")
  r$observation_date <- "2000-01-01"
  expect_error(check(r), "must be a Date")
})

# -- the tracker merge -------------------------------------------------------

tracker_pc <- function(...) {
  d <- data.frame(watershed_group_code = character(0), species_code = character(0),
                  flag = character(0), rule = character(0), story = character(0),
                  decision = character(0), reviewer = character(0),
                  review_date = character(0), issue = character(0),
                  stringsAsFactors = FALSE)
  rows <- list(...)
  for (x in rows) d[nrow(d) + 1L, names(x)] <- x
  d[is.na(d)] <- ""
  d
}

flagged_pc <- data.frame(
  watershed_group_code = c("W1", "W2", "W2"),
  species_code = c("DV", "CO", "BT"),
  flag = c("present_unsupported", "absent_recorded", "absent_recorded"),
  story = c("s1 new", "s2 new", "s3 new"),
  stringsAsFactors = FALSE)

test_that("merge adds new flags as pending and refreshes pending rows", {
  t0 <- tracker_pc(list(watershed_group_code = "W1", species_code = "DV",
                        flag = "present_unsupported", rule = "old",
                        story = "s1 old", decision = "pending", issue = "#402"))
  m <- .lnk_presence_review_merge(t0, flagged_pc, rule = "r")
  expect_identical(nrow(m$tracker), 3L)
  expect_identical(nrow(m$added), 2L)
  expect_true(all(m$tracker$decision == "pending"))
  expect_identical(m$tracker$story[m$tracker$species_code == "DV"], "s1 new")
  expect_identical(m$tracker$rule[m$tracker$species_code == "DV"], "r")
  expect_identical(m$tracker$species_code, c("DV", "BT", "CO"))
})

test_that("merge never changes a decided row, and reports stale ones", {
  t0 <- tracker_pc(
    list(watershed_group_code = "W2", species_code = "CO", flag = "absent_recorded",
         rule = "old", story = "operator's words", decision = "add",
         reviewer = "AI", review_date = "2026-11-01", issue = "#402"),
    list(watershed_group_code = "W1", species_code = "CH", flag = "absent_recorded",
         rule = "old", story = "gone", decision = "keep", issue = "#402"))
  m <- .lnk_presence_review_merge(t0, flagged_pc, rule = "r")
  co <- m$tracker[m$tracker$species_code == "CO", ]
  expect_identical(co$story, "operator's words")
  expect_identical(co$rule, "old")
  expect_identical(co$decision, "add")
  expect_identical(m$stale$species_code, "CH")
  expect_true("CH" %in% m$tracker$species_code)
})

test_that("merge refuses an unknown decision and a duplicate row", {
  bad <- tracker_pc(list(watershed_group_code = "W1", species_code = "DV",
                         decision = "maybe"))
  expect_error(.lnk_presence_review_merge(bad, flagged_pc, "r"), "maybe")
  row <- list(watershed_group_code = "W1", species_code = "DV",
              decision = "pending")
  expect_error(.lnk_presence_review_merge(tracker_pc(row, row), flagged_pc, "r"),
               "duplicate")
})

test_that("the rule sentence states the count and the floor", {
  expect_identical(.lnk_presence_rule(1L, 1950L),
                   paste0("at least 1 record dated 1950 or later; releases ",
                          "and excluded records out; pooled per ",
                          "species_pooling.csv"))
  expect_match(.lnk_presence_rule(5L, 1990L), "at least 5 records dated 1990")
})

# -- the shared exclusion rule ----------------------------------------------

test_that("prep's observation SQL excludes the keys the check excludes", {
  ex <- data.frame(observation_key = c("k1", "k2", "k3", "k4"),
                   data_error = c("t", NA, NA, NA),
                   release_exclude = c(NA, TRUE, NA, "f"),
                   release_include = c(NA, NA, "t", NA),
                   stringsAsFactors = FALSE)
  ld <- loaded_pc(exclusions = ex)
  expect_identical(.lnk_observation_exclusion_keys(ld), c("k1", "k2"))
  expect_identical(.lnk_observation_exclusion_keys(loaded_pc()), character(0))
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  .lnk_pipeline_prep_observations("mock", aoi = "W1", loaded = ld,
                                  schema = "w_w1")
  joined <- paste(captured, collapse = "\n")
  expect_identical(
    lengths(regmatches(joined, gregexpr(
      "AND o.observation_key NOT IN ('k1', 'k2')", joined, fixed = TRUE))),
    2L)
})
