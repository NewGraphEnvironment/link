# Mocked tests for `lnk_pipeline_access`'s sequence-aware indicators.
# `dam_dnstr_ind` and `remediated_dnstr_ind` are computed in R from
# the list-columns returned by fresh's `frs_network_features` plus an
# optional `crossings_table` lookup. These tests verify the per-row
# logic without a DB round-trip via `local_mocked_bindings`.
#
# See `data-raw/logs/<TS>_link135_parity_validation.txt` for the live
# ADMS parity proof against bcfp's `streams_access`.

mock_segments_aoi <- function(ids, segment_id_col = "segmented_stream_id") {
  setNames(data.frame(ids, stringsAsFactors = FALSE), segment_id_col)
}

# Helper: build the dnstr_per_source mock return for a single source.
mock_frs <- function(per_segment, segment_id_col = "segmented_stream_id") {
  ids <- names(per_segment)
  arrs <- unname(per_segment)
  tibble::tibble(!!segment_id_col := ids, feature_ids = arrs)
}

test_that("dam_dnstr_ind not emitted when only `anthropogenic` is in barrier_sources", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2")),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      mock_frs(list(s1 = c("A1"), s2 = character(0)))
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barriers_per_sp = list(),
    barrier_sources = list(anthropogenic = "s.barriers_anthropogenic"),
    segment_id_col = "segmented_stream_id"
  )
  expect_false("dam_dnstr_ind" %in% names(out))
  expect_false("remediated_dnstr_ind" %in% names(out))
})

test_that("dam_dnstr_ind: next anth IS a dam (overlap on shared ID)", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2")),
    .package = "DBI"
  )
  call_n <- 0L
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      call_n <<- call_n + 1L
      if (grepl("anthropogenic", features)) {
        mock_frs(list(s1 = c("A1", "A2"), s2 = c("P1", "A3")))
      } else if (grepl("dams", features)) {
        mock_frs(list(s1 = c("A1"), s2 = c("A3")))
      } else {
        stop("unexpected features: ", features)
      }
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(
      anthropogenic = "s.barriers_anthropogenic",
      dams          = "s.barriers_dams"
    ),
    segment_id_col = "segmented_stream_id"
  )
  expect_true("dam_dnstr_ind" %in% names(out))
  # s1: next anth A1 is in dams [A1] -> TRUE
  # s2: next anth P1 is NOT in dams [A3] -> FALSE
  expect_equal(out$dam_dnstr_ind[out$segmented_stream_id == "s1"], TRUE)
  expect_equal(out$dam_dnstr_ind[out$segmented_stream_id == "s2"], FALSE)
})

test_that("dam_dnstr_ind: PSCIS-first-then-dam returns FALSE (the #124 bug case)", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1")),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      if (grepl("anthropogenic", features)) {
        # next anth is a PSCIS structure (not a dam), dam is further dnstr
        mock_frs(list(s1 = c("P1", "A1")))
      } else if (grepl("dams", features)) {
        mock_frs(list(s1 = c("A1")))
      }
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(
      anthropogenic = "s.barriers_anthropogenic",
      dams          = "s.barriers_dams"
    ),
    segment_id_col = "segmented_stream_id"
  )
  # presence-only fallback (the pre-#135 fallback) would over-emit DAM here;
  # sequence-aware check correctly says FALSE.
  expect_equal(out$dam_dnstr_ind, FALSE)
})

test_that("dam_dnstr_ind: empty anth array returns FALSE", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1")),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      if (grepl("anthropogenic", features)) {
        # segment has no anthropogenic barriers downstream
        mock_frs(setNames(list(), character(0)))
      } else if (grepl("dams", features)) {
        mock_frs(list(s1 = c("A1")))
      }
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(
      anthropogenic = "s.barriers_anthropogenic",
      dams          = "s.barriers_dams"
    ),
    segment_id_col = "segmented_stream_id"
  )
  expect_equal(out$dam_dnstr_ind, FALSE)
})

test_that("remediated_dnstr_ind not emitted when crossings_table is NULL", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1")),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      mock_frs(list(s1 = c("R1")))
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(remediations = "s.barriers_remediations"),
    crossings_table = NULL,
    segment_id_col = "segmented_stream_id"
  )
  expect_false("remediated_dnstr_ind" %in% names(out))
})

test_that("remediated_dnstr_ind TRUE when next remediation is PASSABLE/REMEDIATED", {
  call_n <- 0L
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      call_n <<- call_n + 1L
      if (grepl("aggregated_crossings_id", sql)) {
        # crossings lookup
        data.frame(
          id = c("R1", "R2"),
          pscis_status = c("REMEDIATED", "BARRIER"),
          stringsAsFactors = FALSE
        )
      } else {
        # segments_aoi
        mock_segments_aoi(c("s1", "s2"))
      }
    },
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      mock_frs(list(s1 = c("R1"), s2 = c("R2")))
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(remediations = "s.barriers_remediations"),
    crossings_table = "s.crossings",
    segment_id_col = "segmented_stream_id"
  )
  expect_true("remediated_dnstr_ind" %in% names(out))
  # s1 -> R1 -> REMEDIATED -> TRUE
  # s2 -> R2 -> BARRIER    -> FALSE
  expect_equal(out$remediated_dnstr_ind[out$segmented_stream_id == "s1"], TRUE)
  expect_equal(out$remediated_dnstr_ind[out$segmented_stream_id == "s2"], FALSE)
})

test_that("remediated_dnstr_ind FALSE for segments with no remediations downstream", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      if (grepl("aggregated_crossings_id", sql)) {
        data.frame(id = character(0), pscis_status = character(0),
                   stringsAsFactors = FALSE)
      } else {
        mock_segments_aoi(c("s1", "s2"))
      }
    },
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      # only s1 has a remediation downstream; s2 absent from the result
      mock_frs(list(s1 = c("R1")))
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "ADMS",
    barrier_sources = list(remediations = "s.barriers_remediations"),
    crossings_table = "s.crossings",
    segment_id_col = "segmented_stream_id"
  )
  # s2 absent from frs result -> remediated_dnstr_ind = FALSE
  # s1 present but R1 not in lookup (empty) -> remediated_dnstr_ind = FALSE
  expect_equal(out$remediated_dnstr_ind, c(FALSE, FALSE))
})

test_that("access_<sp> is integer 1 / 2 when a present species has no barrier in the AOI", {
  # UPET RB, link#246: zero dnstr rows -> has_barriers_rb_dnstr all NA, and
  # ifelse(NA, ...) returned a logical NA column that persist rejected.
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2")),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_network_features = function(conn, segments, features, ...) {
      if (grepl("barriers_rb", features)) {
        return(tibble::tibble(segmented_stream_id = character(0),
                              feature_ids = list()))
      }
      tibble::tibble(segmented_stream_id = "s1", feature_ids = list("RB"))
    },
    .package = "fresh"
  )

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "UPET",
    barriers_per_sp = list(rb = "s.barriers_rb"),
    observations = "s.observations",
    wsg_presence = list(rb = TRUE),
    segment_id_col = "segmented_stream_id"
  )
  # Known present, so "no barrier downstream", not "no data": as NA the
  # mapping code emitted "" for every UPET RB segment.
  expect_identical(out$has_barriers_rb_dnstr, c(FALSE, FALSE))
  expect_type(out$access_rb, "integer")
  expect_equal(out$access_rb, c(2L, 1L))

  # With no presence given, zero rows stays "no data" (bcfp's NULL
  # column), and access is still an integer code.
  out_np <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams",
    aoi = "UPET",
    barriers_per_sp = list(rb = "s.barriers_rb"),
    observations = "s.observations",
    segment_id_col = "segmented_stream_id"
  )
  expect_true(all(is.na(out_np$has_barriers_rb_dnstr)))
  expect_type(out_np$access_rb, "integer")
  expect_equal(out_np$access_rb, c(2L, 1L))
})

# Each walk asks fresh for arrays only where an indicator reads their elements;
# the rest take the existence walk (link#394, fresh#281). The mock answers in
# the shape fresh returns for the mode it was asked for, and records the calls.
mock_walks <- function(per_table, segment_id_col = "segmented_stream_id") {
  calls <- new.env()
  calls$log <- data.frame(features = character(0), result = character(0),
                          direction = character(0))
  fn <- function(conn, segments, features, ...) {
    dots <- list(...)
    result <- if (is.null(dots$result)) "ids" else dots$result
    calls$log <- rbind(calls$log, data.frame(
      features = features, result = result, direction = dots$direction))
    per_segment <- per_table[[features]]
    if (is.null(per_segment)) per_segment <- list()
    if (identical(result, "exists")) {
      ids <- names(per_segment)[lengths(per_segment) > 0L]
      return(tibble::tibble(!!segment_id_col := ids,
                            has_features = rep(TRUE, length(ids))))
    }
    mock_frs(per_segment, segment_id_col)
  }
  list(fn = fn, calls = calls)
}

test_that("walks read only for membership take the existence walk (#394)", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2", "s3")),
    .package = "DBI"
  )
  w <- mock_walks(list(
    "s.barriers_bt_access" = list(s1 = "B1"),
    "s.barriers_ch_access" = list(s1 = "C1", s2 = "C2"),
    "s.anth" = list(s1 = c("D1", "P1"), s2 = "P2"),
    "s.pscis" = list(s1 = "P1", s2 = "P2"),
    "s.dams" = list(s1 = "D1")))
  local_mocked_bindings(frs_network_features = w$fn, .package = "fresh")

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams", aoi = "ADMS",
    barriers_per_sp = list(bt = "s.barriers_bt_access",
                           ch = "s.barriers_ch_access"),
    wsg_presence = list(bt = TRUE, ch = TRUE),
    barrier_sources = list(anthropogenic = "s.anth", pscis = "s.pscis",
                           dams = "s.dams"),
    segment_id_col = "segmented_stream_id")

  log <- w$calls$log
  expect_identical(stats::setNames(log$result, log$features),
                   c("s.barriers_bt_access" = "exists",
                     "s.barriers_ch_access" = "exists",
                     "s.anth" = "ids", "s.pscis" = "exists", "s.dams" = "ids"))
  expect_identical(out$has_barriers_bt_dnstr, c(TRUE, FALSE, FALSE))
  expect_identical(out$has_barriers_ch_dnstr, c(TRUE, TRUE, FALSE))
  expect_identical(out$has_barriers_pscis_dnstr, c(TRUE, TRUE, FALSE))
  expect_identical(out$has_barriers_anthropogenic_dnstr, c(TRUE, TRUE, FALSE))
  expect_identical(out$access_bt, c(0L, 1L, 1L))
  # s1's next anthropogenic barrier is a dam; s2's is not.
  expect_identical(out$dam_dnstr_ind, c(TRUE, FALSE, FALSE))
})

test_that("anthropogenic without dams, and remediations without crossings, are exists walks", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2")),
    .package = "DBI"
  )
  w <- mock_walks(list("s.anth" = list(s1 = "A1"), "s.rem" = list(s2 = "R1")))
  local_mocked_bindings(frs_network_features = w$fn, .package = "fresh")

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams", aoi = "ADMS",
    barrier_sources = list(anthropogenic = "s.anth", remediations = "s.rem"),
    crossings_table = NULL,
    segment_id_col = "segmented_stream_id")

  expect_identical(w$calls$log$result, c("exists", "exists"))
  expect_identical(out$has_barriers_anthropogenic_dnstr, c(TRUE, FALSE))
  expect_identical(out$has_barriers_remediations_dnstr, c(FALSE, TRUE))
  expect_false("dam_dnstr_ind" %in% names(out))
})

test_that("remediations with a crossings table, and observations, walk as arrays", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      if (grepl("aggregated_crossings_id", sql)) {
        data.frame(id = "R1", pscis_status = "REMEDIATED",
                   stringsAsFactors = FALSE)
      } else {
        mock_segments_aoi(c("s1", "s2"))
      }
    },
    .package = "DBI"
  )
  w <- mock_walks(list("s.rem" = list(s1 = "R1"),
                       "s.obs" = list(s2 = "BT"),
                       "s.barriers_bt_access" = list()))
  local_mocked_bindings(frs_network_features = w$fn, .package = "fresh")

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams", aoi = "ADMS",
    barriers_per_sp = list(bt = "s.barriers_bt_access"),
    observations = "s.obs",
    wsg_presence = list(bt = TRUE),
    barrier_sources = list(remediations = "s.rem"),
    crossings_table = "s.crossings",
    segment_id_col = "segmented_stream_id")

  log <- w$calls$log
  expect_identical(stats::setNames(log$result, log$features),
                   c("s.barriers_bt_access" = "exists", "s.rem" = "ids",
                     "s.obs" = "ids"))
  expect_identical(out$remediated_dnstr_ind, c(TRUE, FALSE))
  # Present with no barrier rows: FALSE (not NA), and observed upstream at s2.
  expect_identical(out$has_barriers_bt_dnstr, c(FALSE, FALSE))
  expect_identical(out$access_bt, c(1L, 2L))
})

test_that("a table given in an array role and a membership role is walked once, as arrays", {
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) mock_segments_aoi(c("s1", "s2")),
    .package = "DBI"
  )
  w <- mock_walks(list("s.shared" = list(s1 = "D1"), "s.dams" = list(s1 = "D1")))
  local_mocked_bindings(frs_network_features = w$fn, .package = "fresh")

  out <- lnk_pipeline_access(
    conn = structure(list(), class = "DBIConnection"),
    segments = "s.streams", aoi = "ADMS",
    barriers_per_sp = list(bt = "s.shared"),
    wsg_presence = list(bt = TRUE),
    barrier_sources = list(anthropogenic = "s.shared", dams = "s.dams"),
    segment_id_col = "segmented_stream_id")

  log <- w$calls$log
  expect_identical(log$features, c("s.shared", "s.dams"))
  expect_identical(log$result, c("ids", "ids"))
  expect_identical(out$has_barriers_bt_dnstr, c(TRUE, FALSE))
  expect_identical(out$dam_dnstr_ind, c(TRUE, FALSE))
})
