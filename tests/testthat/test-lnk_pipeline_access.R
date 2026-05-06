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
