# --- Unit tests: lnk_rules_build waterbody-rule emission ---
#
# These tests cover the lake / wetland waterbody_type rule emission
# driven by dimensions.csv (rear_lake, rear_wetland, rear_lake_ha_min,
# rear_wetland_ha_min) plus the fresh thresholds fallback. The rules
# YAML these helpers produce is consumed by fresh::frs_habitat_classify
# which gates lake_rearing / wetland_rearing booleans on the presence
# of waterbody_type: L / W rules and their optional ha_min thresholds.
#
# See fresh#165 / fresh#166 for the downstream integration.

# Helpers --------------------------------------------------------------

get_rear_rules <- function(rules_path, sp) {
  r <- yaml::read_yaml(rules_path)
  r[[sp]][["rear"]]
}

find_wb_rule <- function(rules, wb_code) {
  for (r in rules) {
    wt <- r[["waterbody_type"]]
    if (!is.null(wt) && identical(wt, wb_code)) return(r)
  }
  NULL
}

# -- Lake rule emission --------------------------------------------------------

test_that("rear_lake=yes emits waterbody_type: L rule with per-config ha_min", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_lake_ha_min,
    "BT", "no", "yes", "yes", "no", "no", "yes", "no", "no", "yes", 10,
    "CH", "no", "yes", "yes", "no", "no", "yes", "no", "no", "yes", 100
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  bt_rear <- get_rear_rules(out, "BT")
  bt_l <- find_wb_rule(bt_rear, "L")
  expect_false(is.null(bt_l))
  expect_equal(bt_l$lake_ha_min, 10)

  ch_l <- find_wb_rule(get_rear_rules(out, "CH"), "L")
  expect_equal(ch_l$lake_ha_min, 100)
})

test_that("rear_lake=yes without rear_lake_ha_min column falls back to fresh thresholds", {
  # Without the dims column, use fresh's parameters_habitat_thresholds
  # (SK/KO = 200, others NA → no ha_min in rule)
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "yes", "no", "no", "yes", "no", "no", "yes"
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  bt_l <- find_wb_rule(get_rear_rules(out, "BT"), "L")
  expect_false(is.null(bt_l))
  # fresh's thresholds have NA for BT rear_lake_ha_min → no lake_ha_min emitted
  expect_null(bt_l$lake_ha_min)
})

test_that("rear_lake=no emits no waterbody_type: L rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_lake_ha_min,
    "CM", "no", "yes", "no", "no", "yes", "no", "no", "no", "yes", NA
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  # CM has rear_no_fw=yes so there's no rear block at all, but the
  # top-level species entry still parses — just with empty rear.
  r <- yaml::read_yaml(out)
  cm_rear <- r$CM$rear
  expect_null(find_wb_rule(cm_rear, "L"))
})

# -- Wetland rule emission (fresh#165 / fresh#166 dependency) -----------------

test_that("rear_wetland=yes emits waterbody_type: W rule + edge_types wetland rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_wetland_ha_min,
    "CO", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes", 0.5
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  co_rear <- get_rear_rules(out, "CO")

  # 1. waterbody_type: W rule emitted with wetland_ha_min
  co_w <- find_wb_rule(co_rear, "W")
  expect_false(is.null(co_w))
  expect_equal(co_w$wetland_ha_min, 0.5)

  # 2. edge_types: wetland rule still emitted (for the rearing km total)
  edge_wetland <- vapply(co_rear,
    function(r) identical(r$edge_types, "wetland"), logical(1))
  expect_true(any(edge_wetland))
})

test_that("rear_wetland=yes without ha_min column emits W rule without threshold", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes"
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
  expect_null(bt_w$wetland_ha_min)
})

test_that("rear_wetland=yes with NA / empty string ha_min emits W rule without threshold", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_wetland_ha_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes", NA,
    "CO", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes", ""
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
  expect_null(bt_w$wetland_ha_min)

  co_w <- find_wb_rule(get_rear_rules(out, "CO"), "W")
  expect_false(is.null(co_w))
  expect_null(co_w$wetland_ha_min)
})

test_that("rear_wetland=no emits no waterbody_type: W rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "PK", "no", "yes", "no", "no", "yes", "no", "no", "no", "yes"
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  lnk_rules_build(csv, out, edge_types = "categories")

  r <- yaml::read_yaml(out)
  expect_null(find_wb_rule(r$PK$rear, "W"))
})

# -- Regression: non-numeric ha_min ------------------------------------------

test_that("non-numeric rear_wetland_ha_min falls through: W rule without threshold", {
  # No wetland fallback exists in fresh thresholds, so garbage silently
  # falls through to "no threshold" (same outcome as blank/NA input).
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_wetland_ha_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes", "not_a_number"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
  expect_null(bt_w$wetland_ha_min)
})

# -- rear_wetland_polygon flag ------------------------------------------------

test_that("rear_wetland_polygon=no suppresses W rule emission", {
  # Per-species column added 2026-04-27 to split the wetland-flow
  # 1050/1150 carve-out from the W-polygon rule. When polygon=no, only
  # the carve-out emits; when polygon=yes (or column absent), both emit.
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_wetland_polygon,
    ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_null(bt_w)  # polygon=no → no W rule
  # but the 1050/1150 carve-out IS still emitted (rear_wetland=yes)
  carve <- Filter(function(r) {
    et <- r[["edge_types"]] %||% r[["edge_types_explicit"]]
    !is.null(et) && (identical(et, "wetland") ||
                      all(c(1050, 1150) %in% et))
  }, get_rear_rules(out, "BT"))
  expect_length(carve, 1L)
})

test_that("rear_wetland_polygon=yes preserves W rule emission", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_wetland_polygon,
    ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
})

test_that("rear_wetland_polygon column absent: W rule emits (backward compat)", {
  # Older fixtures without the column should preserve pre-2026-04-27
  # behaviour where rear_wetland=yes implied both rules.
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
})

# -- Default bundle smoke test ------------------------------------------------

test_that("bundled default config emits W rule with mainlines edge filter for rear_wetland=yes species", {
  # Default bundle (link#69 phase 2) ships use case 1: rear_wetland_polygon=yes
  # for rear_wetland=yes species, with the mainlines-only edge filter
  # `edge_types_explicit: [1000, 1100]` so polygon shorelines/banks
  # don't credit linear `rearing`. The W rule still drives wetland_rearing
  # bucket flag for area rollups.
  csv <- system.file("extdata", "configs", "default", "dimensions.csv",
                     package = "link", mustWork = TRUE)
  out <- withr::local_tempfile(fileext = ".yaml")

  skipped <- character(0)
  withCallingHandlers(
    lnk_rules_build(csv, out, edge_types = "explicit"),
    message = function(m) {
      if (grepl("^Skipping ", conditionMessage(m))) {
        skipped <<- c(skipped, sub("Skipping ([A-Z]+):.*", "\\1",
                                    conditionMessage(m)))
      }
      invokeRestart("muffleMessage")
    })

  dims <- utils::read.csv(csv, stringsAsFactors = FALSE)
  wetland_yes <- dims$species[
    tolower(trimws(dims$rear_wetland)) == "yes" &
    !dims$species %in% skipped]
  r <- yaml::read_yaml(out)
  for (sp in wetland_yes) {
    w <- find_wb_rule(r[[sp]]$rear, "W")
    expect_false(is.null(w))
    expect_setequal(as.integer(w$edge_types_explicit), c(1000L, 1100L))
  }
})

# -- Spawn rule emission ------------------------------------------------------

test_that("spawn_stream=yes emits stream + canal edge_types rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  spawn_rules <- yaml::read_yaml(out)$BT$spawn
  stream_rule <- spawn_rules[[1]]
  expect_setequal(stream_rule$edge_types, c("stream", "canal"))
})

test_that("spawn_stream=yes with edge_types=explicit emits integer codes", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  spawn_rules <- yaml::read_yaml(out)$BT$spawn
  stream_rule <- spawn_rules[[1]]
  expect_null(stream_rule[["edge_types"]])
  expect_setequal(stream_rule[["edge_types_explicit"]],
                  c(1000L, 1100L, 2000L, 2300L))
})

test_that("spawn_lake=yes emits waterbody_type: L spawn rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "SK", "yes", "no", "yes", "yes", "no", "no", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  spawn_rules <- yaml::read_yaml(out)$SK$spawn
  l <- find_wb_rule(spawn_rules, "L")
  expect_false(is.null(l))
})

# -- in_waterbody emission (link#69 / fresh#180) ------------------------------

test_that("spawn_stream_in_waterbody=no emits in_waterbody:false on stream rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~spawn_stream_in_waterbody,
    ~rear_lake, ~rear_lake_only, ~rear_no_fw, ~rear_stream,
    ~rear_stream_in_waterbody, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "no", "yes", "no", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  rules <- yaml::read_yaml(out)$BT
  spawn_stream <- rules$spawn[[1]]
  expect_equal(spawn_stream$in_waterbody, FALSE)
  rear_stream <- rules$rear[[1]]
  expect_equal(rear_stream$in_waterbody, FALSE)
})

test_that("rear_stream_in_waterbody=yes omits the field (rule matches in + out of polygons)", {
  # `yes` is the permissive default: no `in_waterbody` filter on the
  # stream rule so it matches segments inside AND outside polygons.
  # The opposite extreme (in_waterbody:true = inside polygons only)
  # has no biological use case for stream rules and is not emitted.
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~spawn_stream_in_waterbody,
    ~rear_lake, ~rear_lake_only, ~rear_no_fw, ~rear_stream,
    ~rear_stream_in_waterbody, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "yes", "no", "no", "yes", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  rules <- yaml::read_yaml(out)$BT
  spawn_stream <- rules$spawn[[1]]
  expect_equal(spawn_stream$in_waterbody, FALSE)
  rear_stream <- rules$rear[[1]]
  expect_null(rear_stream$in_waterbody)
})

test_that("absent in_waterbody columns omit the field (backward-compat)", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  rules <- yaml::read_yaml(out)$BT
  expect_null(rules$spawn[[1]]$in_waterbody)
  expect_null(rules$rear[[1]]$in_waterbody)
})

test_that("in_waterbody is NOT applied to the river polygon rule or wetland carve-out", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~spawn_stream_in_waterbody,
    ~rear_lake, ~rear_lake_only, ~rear_no_fw, ~rear_stream,
    ~rear_stream_in_waterbody, ~rear_wetland, ~rear_wetland_polygon,
    ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "no", "yes", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  rules <- yaml::read_yaml(out)$BT
  river_rule <- find_wb_rule(rules$spawn, "R")
  expect_false(is.null(river_rule))
  expect_null(river_rule$in_waterbody)
  carve <- Filter(function(r) {
    !is.null(r$edge_types_explicit) &&
      identical(sort(as.integer(r$edge_types_explicit)), c(1050L, 1150L))
  }, rules$rear)
  expect_length(carve, 1L)
  expect_null(carve[[1]]$in_waterbody)
})

test_that("bcfishpass bundle: spawn stream-edge rule carries in_waterbody:false", {
  # `spawn_stream_in_waterbody` is `no` for every species in the bundle —
  # spawn rules must filter to channel-line edges only. Rear is per-species
  # (CO and ST flip to `yes` to admit polygon mainlines), tested separately.
  csv <- system.file("extdata", "configs", "bcfishpass", "dimensions.csv",
                     package = "link", mustWork = TRUE)
  out <- withr::local_tempfile(fileext = ".yaml")
  suppressMessages(lnk_rules_build(csv, out, edge_types = "explicit"))
  r <- yaml::read_yaml(out)

  for (sp in names(r)) {
    for (rr in r[[sp]]$spawn) {
      is_stream_edge <- !is.null(rr$edge_types_explicit) &&
        all(c(1000L, 1100L, 2000L, 2300L) %in% rr$edge_types_explicit)
      if (is_stream_edge) {
        expect_equal(rr$in_waterbody, FALSE,
          info = paste0(sp, ": spawn stream-edge rule expected in_waterbody=FALSE"))
      }
    }
  }
})

test_that("default bundle: rear stream rule omits in_waterbody (matches in+out of polygons)", {
  # Default bundle ships rear_stream_in_waterbody=yes for permissive
  # rearing; spawn_stream_in_waterbody=no for biology. Spawn-stream
  # rules should carry in_waterbody:false; rear-stream rules omit
  # the field (no filter, matches polygon-mainlines too).
  csv <- system.file("extdata", "configs", "default", "dimensions.csv",
                     package = "link", mustWork = TRUE)
  out <- withr::local_tempfile(fileext = ".yaml")
  suppressMessages(lnk_rules_build(csv, out, edge_types = "explicit"))
  r <- yaml::read_yaml(out)

  for (sp in names(r)) {
    for (rr in r[[sp]]$spawn) {
      is_stream_edge <- !is.null(rr$edge_types_explicit) &&
        all(c(1000L, 1100L, 2000L, 2300L) %in% rr$edge_types_explicit)
      if (is_stream_edge) {
        expect_equal(rr$in_waterbody, FALSE, info = paste0(sp, " spawn"))
      }
    }
    for (rr in r[[sp]]$rear) {
      is_stream_edge <- !is.null(rr$edge_types_explicit) &&
        all(c(1000L, 1100L, 2000L, 2300L) %in% rr$edge_types_explicit)
      if (is_stream_edge) {
        expect_null(rr$in_waterbody, info = paste0(sp, " rear"))
      }
    }
  }
})

# -- area_only emission + polygon mainlines filter (link#69 phase 2) ----------

test_that("rear_lake_area_only=yes emits area_only:true on L rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_lake_area_only, ~rear_no_fw, ~rear_stream, ~rear_wetland,
    ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "yes", "no", "yes", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  l <- find_wb_rule(get_rear_rules(out, "BT"), "L")
  expect_false(is.null(l))
  expect_true(isTRUE(l$area_only))
})

test_that("rear_wetland_area_only=yes emits area_only:true on W rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_wetland_polygon,
    ~rear_wetland_area_only, ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(w))
  expect_true(isTRUE(w$area_only))
})

test_that("absent area_only column omits the field (backward-compat)", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "yes", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  l <- find_wb_rule(get_rear_rules(out, "BT"), "L")
  expect_false(is.null(l))
  expect_null(l$area_only)
})

test_that("L / W polygon rules carry edge_types_explicit: [1000, 1100] filter", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_wetland_polygon,
    ~rear_all_edges, ~river_skip_cw_min,
    "BT", "no", "yes", "yes", "no", "no", "yes", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  l <- find_wb_rule(get_rear_rules(out, "BT"), "L")
  expect_setequal(as.integer(l$edge_types_explicit), c(1000L, 1100L))
  w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_setequal(as.integer(w$edge_types_explicit), c(1000L, 1100L))
})

test_that("rear_lake_only branch L rule does NOT carry edge filter or area_only", {
  # SK / KO: L rule is the rear classification, must keep matching the
  # whole lake polygon (mainlines + shorelines) without an edge filter.
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_lake_area_only, ~rear_no_fw, ~rear_stream, ~rear_wetland,
    ~rear_all_edges, ~river_skip_cw_min,
    "SK", "no", "yes", "yes", "yes", "yes", "no", "no", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "explicit")

  l <- find_wb_rule(get_rear_rules(out, "SK"), "L")
  expect_false(is.null(l))
  expect_null(l$edge_types_explicit)
  expect_null(l$area_only)
})

test_that("default bundle: rear_lake non-lake-only species carry edge_types filter", {
  csv <- system.file("extdata", "configs", "default", "dimensions.csv",
                     package = "link", mustWork = TRUE)
  out <- withr::local_tempfile(fileext = ".yaml")
  suppressMessages(lnk_rules_build(csv, out, edge_types = "explicit"))
  r <- yaml::read_yaml(out)

  # SK and KO are rear_lake_only — exempt.
  for (sp in setdiff(names(r), c("SK", "KO"))) {
    l <- find_wb_rule(r[[sp]]$rear, "L")
    if (!is.null(l)) {
      expect_setequal(as.integer(l$edge_types_explicit), c(1000L, 1100L))
    }
    w <- find_wb_rule(r[[sp]]$rear, "W")
    if (!is.null(w)) {
      expect_setequal(as.integer(w$edge_types_explicit), c(1000L, 1100L))
    }
  }
})

test_that("spawn_requires_connected + connected_distance_max attach to every spawn rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~spawn_requires_connected, ~spawn_connected_distance_max,
    "SK", "no", "yes", "yes", "yes", "no", "no", "no", "no", "yes",
    "rearing", 3000
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  spawn_rules <- yaml::read_yaml(out)$SK$spawn
  for (r in spawn_rules) {
    expect_equal(r$requires_connected, "rearing")
    expect_equal(r$connected_distance_max, 3000)
  }
})

# -- spawn_connected block emission --------------------------------------------

test_that("spawn_connected block emits when direction set in dimensions", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    ~spawn_requires_connected, ~spawn_connected_distance_max,
    ~spawn_connected_direction, ~spawn_connected_gradient_max,
    ~spawn_connected_cw_min,
    "SK", "no", "yes", "yes", "yes", "no", "no", "no", "no", "yes",
    "rearing", 3000, "downstream", 0.05, 0
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  sc <- yaml::read_yaml(out)$SK$spawn_connected
  expect_false(is.null(sc))
  expect_equal(sc$direction, "downstream")
  expect_equal(sc$gradient_max, 0.05)
  expect_equal(sc$distance_max, 3000)
  expect_equal(sc$channel_width_min, 0)
})

test_that("spawn_connected block absent when direction missing", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  expect_null(yaml::read_yaml(out)$BT$spawn_connected)
})

# -- Rear precedence: no_fw > lake_only > additive ----------------------------

test_that("rear_no_fw=yes drops all rear rules", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "PK", "no", "yes", "no", "no", "yes", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  # rear_no_fw wins — rear_stream / rear_wetland ignored
  rear <- yaml::read_yaml(out)$PK$rear
  expect_true(is.null(rear) || length(rear) == 0)
})

test_that("rear_lake_only=yes produces exactly one L rule, no stream/river/wetland", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "SK", "no", "yes", "yes", "yes", "no", "yes", "yes", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$SK$rear
  expect_length(rear, 1)
  expect_equal(rear[[1]]$waterbody_type, "L")
  # Fresh thresholds fallback: SK has rear_lake_ha_min = 200 in
  # fresh's parameters_habitat_thresholds.csv — dimensions column is
  # absent here so the fresh value must come through.
  expect_equal(rear[[1]]$lake_ha_min, 200)
  for (r in rear) {
    expect_null(r[["edge_types"]])
  }
})

test_that("non-numeric rear_lake_ha_min falls through to fresh thresholds fallback", {
  # dimensions has garbage in rear_lake_ha_min; fresh has 200 for SK.
  # The resolver should ignore the garbage and use the fresh fallback.
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_lake_ha_min,
    "SK", "no", "yes", "yes", "yes", "no", "no", "no", "no", "yes", "garbage"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$SK$rear
  expect_equal(rear[[1]]$lake_ha_min, 200)
})

test_that("rear_all_edges=yes skips per-edge-type rules", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "yes", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$BT$rear
  # rear_all_edges gives exactly ONE empty rule (all edge types
  # accepted). Confirm the rule is present, has no edge filter, and
  # nothing else (no waterbody_type, no edge_types_explicit) snuck in.
  expect_length(rear, 1)
  first <- rear[[1]]
  expect_null(first[["edge_types"]])
  expect_null(first[["edge_types_explicit"]])
  expect_null(first[["waterbody_type"]])
})

# -- River polygon rule + river_skip_cw_min -----------------------------------

test_that("river_skip_cw_min=yes emits river rule with 0-9999 channel_width", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$BT$rear
  river_r <- find_wb_rule(rear, "R")
  expect_false(is.null(river_r))
  expect_equal(river_r$channel_width, c(0, 9999))
})

test_that("river_skip_cw_min=no or missing omits the 0-9999 override", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "no", "no", "no"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$BT$rear
  river_r <- find_wb_rule(rear, "R")
  # Invariant: rear_stream=yes always emits an R rule (the river
  # polygon rule). Assert presence first; then assert that without
  # river_skip_cw_min the 0-9999 channel_width override is NOT used.
  expect_false(is.null(river_r))
  expect_false(identical(river_r[["channel_width"]], c(0, 9999)))
})

# -- Species skipping ---------------------------------------------------------

test_that("species not in fresh thresholds are skipped with a message", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min,
    "ZZZ", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  expect_message(
    lnk_rules_build(csv, out, edge_types = "categories"),
    "Skipping ZZZ: no thresholds")

  r <- yaml::read_yaml(out)
  expect_null(r$ZZZ)
})

# -- Rear stream order bypass -------------------------------------------------

test_that("rear_stream_order_bypass=yes attaches channel_width_min_bypass to stream rule", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_stream_order_bypass,
    "ST", "no", "yes", "no", "no", "no", "yes", "no", "no", "yes", "yes"
  )
  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)
  lnk_rules_build(csv, out, edge_types = "categories")

  rear <- yaml::read_yaml(out)$ST$rear
  stream_rule <- rear[[1]]  # first rule is the stream/canal edge_types
  expect_false(is.null(stream_rule$channel_width_min_bypass))
  expect_equal(stream_rule$channel_width_min_bypass$stream_order_min, 1)
  expect_equal(stream_rule$channel_width_min_bypass$stream_order_max, 1)
  expect_equal(stream_rule$channel_width_min_bypass$stream_order_parent_min, 5)
})

# -- shipped default config: regression guard against re-introducing
#    1050 / 1150 / 2100 into spawn or rear-stream predicates ---------------

test_that("default config rules.yaml has no 1050/1150/2100 in spawn or rear-stream predicates", {
  yaml_path <- system.file("extdata", "configs", "default", "rules.yaml",
                           package = "link")
  skip_if(yaml_path == "", "default rules.yaml not installed")
  rules <- yaml::read_yaml(yaml_path)
  forbidden <- c(1050L, 1150L, 2100L)
  for (sp in names(rules)) {
    spawn <- rules[[sp]]$spawn %||% list()
    for (r in spawn) {
      codes <- r[["edge_types_explicit"]]
      if (!is.null(codes)) {
        expect_true(length(intersect(as.integer(codes), forbidden)) == 0L,
          info = sprintf("%s spawn rule contains forbidden code", sp))
      }
    }
    # Rear-stream rule is the predicate-bearing rule. The dedicated
    # wetland_rearing rule has `thresholds: false` and IS allowed to
    # carry 1050/1150 (its sole purpose). Check only rules that act as
    # predicates (no `thresholds: false`).
    rear <- rules[[sp]]$rear %||% list()
    for (r in rear) {
      codes <- r[["edge_types_explicit"]]
      thr <- r[["thresholds"]]
      is_wetland_rule <- !is.null(thr) && isFALSE(thr)
      if (!is.null(codes) && !is_wetland_rule) {
        expect_true(length(intersect(as.integer(codes), forbidden)) == 0L,
          info = sprintf("%s rear stream-predicate rule contains forbidden code", sp))
      }
    }
  }
})

test_that("rear_stream_order_parent_min column drives bypass threshold", {
  # Default 5L when bypass=yes and column absent; explicit value when present.
  base <- list(species = "BT", spawn_lake = "no", spawn_stream = "yes",
               rear_lake = "no", rear_lake_only = "no", rear_no_fw = "no",
               rear_stream = "yes", rear_wetland = "no",
               rear_stream_order_bypass = "yes")

  # No column → default 5
  csv <- withr::local_tempfile(fileext = ".csv")
  out <- withr::local_tempfile(fileext = ".yaml")
  utils::write.csv(as.data.frame(base, stringsAsFactors = FALSE), csv,
                   row.names = FALSE)
  suppressMessages(lnk_rules_build(csv, out, edge_types = "explicit"))
  rules <- yaml::read_yaml(out)
  bp <- NULL
  for (rr in rules$BT$rear) {
    if (!is.null(rr$channel_width_min_bypass)) { bp <- rr$channel_width_min_bypass; break }
  }
  expect_false(is.null(bp))
  expect_equal(bp$stream_order_min, 1L)
  expect_equal(bp$stream_order_max, 1L)
  expect_equal(bp$stream_order_parent_min, 5L)

  # Column present, explicit value 7
  with7 <- c(base, list(rear_stream_order_parent_min = "7"))
  csv2 <- withr::local_tempfile(fileext = ".csv")
  out2 <- withr::local_tempfile(fileext = ".yaml")
  utils::write.csv(as.data.frame(with7, stringsAsFactors = FALSE), csv2,
                   row.names = FALSE)
  suppressMessages(lnk_rules_build(csv2, out2, edge_types = "explicit"))
  rules2 <- yaml::read_yaml(out2)
  bp2 <- NULL
  for (rr in rules2$BT$rear) {
    if (!is.null(rr$channel_width_min_bypass)) { bp2 <- rr$channel_width_min_bypass; break }
  }
  expect_equal(bp2$stream_order_parent_min, 7L)

  # Column present but empty → default 5
  with_empty <- c(base, list(rear_stream_order_parent_min = ""))
  csv3 <- withr::local_tempfile(fileext = ".csv")
  out3 <- withr::local_tempfile(fileext = ".yaml")
  utils::write.csv(as.data.frame(with_empty, stringsAsFactors = FALSE), csv3,
                   row.names = FALSE)
  suppressMessages(lnk_rules_build(csv3, out3, edge_types = "explicit"))
  rules3 <- yaml::read_yaml(out3)
  bp3 <- NULL
  for (rr in rules3$BT$rear) {
    if (!is.null(rr$channel_width_min_bypass)) { bp3 <- rr$channel_width_min_bypass; break }
  }
  expect_equal(bp3$stream_order_parent_min, 5L)
})

test_that("rear_stream_order_parent_min has no effect when bypass=no", {
  base <- list(species = "BT", spawn_lake = "no", spawn_stream = "yes",
               rear_lake = "no", rear_lake_only = "no", rear_no_fw = "no",
               rear_stream = "yes", rear_wetland = "no",
               rear_stream_order_bypass = "no",
               rear_stream_order_parent_min = "7")
  csv <- withr::local_tempfile(fileext = ".csv")
  out <- withr::local_tempfile(fileext = ".yaml")
  utils::write.csv(as.data.frame(base, stringsAsFactors = FALSE), csv,
                   row.names = FALSE)
  suppressMessages(lnk_rules_build(csv, out, edge_types = "explicit"))
  rules <- yaml::read_yaml(out)
  for (rr in rules$BT$rear) {
    expect_null(rr$channel_width_min_bypass)
  }
})

test_that("default config rules.yaml retains 1050/1150 in dedicated wetland-rear rule", {
  yaml_path <- system.file("extdata", "configs", "default", "rules.yaml",
                           package = "link")
  skip_if(yaml_path == "", "default rules.yaml not installed")
  rules <- yaml::read_yaml(yaml_path)
  # BT has rear_wetland = yes — wetland-rear rule must be present
  rear <- rules$BT$rear
  wetland_rule <- NULL
  for (r in rear) {
    if (!is.null(r[["edge_types_explicit"]]) &&
        !is.null(r[["thresholds"]]) && isFALSE(r[["thresholds"]])) {
      wetland_rule <- r
      break
    }
  }
  expect_false(is.null(wetland_rule),
               info = "BT rear should include dedicated wetland rule")
  expect_setequal(as.integer(wetland_rule[["edge_types_explicit"]]),
                  c(1050L, 1150L))
})
