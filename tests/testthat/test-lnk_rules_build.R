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

test_that("non-numeric rear_wetland_ha_min coerces to NA and emits no threshold", {
  dims <- tibble::tribble(
    ~species, ~spawn_lake, ~spawn_stream, ~rear_lake, ~rear_lake_only,
    ~rear_no_fw, ~rear_stream, ~rear_wetland, ~rear_all_edges,
    ~river_skip_cw_min, ~rear_wetland_ha_min,
    "BT", "no", "yes", "no", "no", "no", "yes", "yes", "no", "yes", "not_a_number"
  )

  out <- withr::local_tempfile(fileext = ".yaml")
  csv <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(dims, csv, row.names = FALSE)

  # expect the coercion warning but no error
  expect_warning(
    lnk_rules_build(csv, out, edge_types = "categories"),
    "NAs introduced by coercion"
  )

  bt_w <- find_wb_rule(get_rear_rules(out, "BT"), "W")
  expect_false(is.null(bt_w))
  expect_null(bt_w$wetland_ha_min)
})

# -- Default bundle smoke test ------------------------------------------------

test_that("configs/default/dimensions.csv emits W rule for rear_wetland=yes species that have fresh thresholds", {
  csv <- system.file("extdata", "configs", "default", "dimensions.csv",
                     package = "link", mustWork = TRUE)
  out <- withr::local_tempfile(fileext = ".yaml")

  # lnk_rules_build emits a message for species dropped because fresh's
  # parameters_habitat_thresholds.csv has no row for them. Capture
  # those so the smoke test only checks species actually in rules.yaml.
  skipped <- character(0)
  withCallingHandlers(
    lnk_rules_build(csv, out, edge_types = "categories"),
    message = function(m) {
      if (grepl("^Skipping ", conditionMessage(m))) {
        skipped <<- c(skipped, sub("Skipping ([A-Z]+):.*", "\\1",
                                    conditionMessage(m)))
      }
      invokeRestart("muffleMessage")
    })

  r <- yaml::read_yaml(out)
  dims <- utils::read.csv(csv, stringsAsFactors = FALSE)
  wetland_spp <- setdiff(
    dims$species[tolower(trimws(dims$rear_wetland)) == "yes"],
    skipped)
  expect_gt(length(wetland_spp), 0)

  for (sp in wetland_spp) {
    w <- find_wb_rule(r[[sp]]$rear, "W")
    expect_false(is.null(w), info = paste0("missing W rule for ", sp))
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
  # No stream / river / wetland rules even though rear_stream/rear_wetland=yes
  for (r in rear) {
    expect_null(r$edge_types)
  }
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
  # rear_all_edges gives one empty rule (all edge types accepted)
  # No explicit edge_types / edge_types_explicit set
  first <- rear[[1]]
  expect_null(first$edge_types)
  expect_null(first$edge_types_explicit)
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
  # When river_skip_cw_min is FALSE/no, the 0-9999 override is NOT emitted;
  # the rule either has no channel_width override or is absent.
  if (!is.null(river_r)) {
    expect_false(identical(river_r$channel_width, c(0, 9999)))
  }
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
  expect_equal(stream_rule$channel_width_min_bypass$stream_order, 1)
  expect_equal(stream_rule$channel_width_min_bypass$stream_order_parent_min, 5)
})
