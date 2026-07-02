# Tests for lnk_compare_rollup — argument validation + reference dispatch

mock_conn <- function() structure(list(), class = "DBIConnection")
mock_cfg <- function() lnk_config("bcfishpass")

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("lnk_compare_rollup rejects invalid aoi", {
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "", cfg = mock_cfg()),
    "aoi"
  )
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = c("ADMS", "BULK"), cfg = mock_cfg()),
    "aoi"
  )
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "ab", cfg = mock_cfg()),
    "aoi"
  )
})

test_that("lnk_compare_rollup rejects non-lnk_config cfg", {
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "ADMS", cfg = list(name = "x")),
    "cfg"
  )
})

test_that("lnk_compare_rollup rejects non-DBI conn", {
  expect_error(
    lnk_compare_rollup(conn = "not-a-conn", aoi = "ADMS", cfg = mock_cfg()),
    "DBI"
  )
})

# ---------------------------------------------------------------------------
# Reference dispatch
# ---------------------------------------------------------------------------

test_that("lnk_compare_rollup rejects unsupported reference", {
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
                       reference = "unknown"),
    "Unsupported reference"
  )
})

test_that("lnk_compare_rollup requires conn_ref for reference='bcfishpass'", {
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
                       reference = "bcfishpass", conn_ref = NULL),
    "conn_ref"
  )
  expect_error(
    lnk_compare_rollup(mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
                       reference = "bcfishpass", conn_ref = "not-a-conn"),
    "conn_ref"
  )
})

# ---------------------------------------------------------------------------
# PG-state probe — empty persistent state errors before query work
# ---------------------------------------------------------------------------

test_that("lnk_compare_rollup errors when no persisted species exist for AOI", {
  m_resolve <- function(conn, cfg, aoi) character(0)

  with_mocked_bindings(
    .lnk_compare_rollup_resolve_species = m_resolve,
    {
      expect_error(
        lnk_compare_rollup(
          conn = mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
          reference = "bcfishpass", conn_ref = mock_conn()
        ),
        "no persisted species found"
      )
    }
  )
})

test_that("lnk_compare_rollup intersects caller-passed species with PG-discovered set", {
  m_resolve <- function(conn, cfg, aoi) c("BT", "CO")

  with_mocked_bindings(
    .lnk_compare_rollup_resolve_species = m_resolve,
    {
      # No overlap → error
      expect_error(
        lnk_compare_rollup(
          conn = mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
          reference = "bcfishpass", conn_ref = mock_conn(),
          species = c("CH", "SK")
        ),
        "no species to roll up"
      )
    }
  )
})

# ---------------------------------------------------------------------------
# Composition — link-side + ref-side helpers called, assembled
# ---------------------------------------------------------------------------

test_that("lnk_compare_rollup composes resolve → link-rollup → ref-rollup → assemble", {
  calls <- character()

  m_resolve <- function(conn, cfg, aoi) {
    calls <<- c(calls, "resolve"); c("BT")
  }
  m_link <- function(conn, cfg, aoi, species) {
    calls <<- c(calls, "link")
    list(km = data.frame(species_code = "BT",
                         spawning_km = 10, rearing_km = 20,
                         rearing_stream_km = 15,
                         rearing_lake_centerline_km = 3,
                         rearing_wetland_centerline_km = 2,
                         accessible_km = 18,
                         stringsAsFactors = FALSE),
         lake_ha = data.frame(species_code = "BT", lake_rearing_ha = 100,
                              stringsAsFactors = FALSE),
         wetland_ha = data.frame(species_code = "BT", wetland_rearing_ha = 50,
                                 stringsAsFactors = FALSE))
  }
  m_ref <- function(reference, conn_ref, aoi, species, conn) {
    calls <<- c(calls, "ref")
    data.frame(species_code = "BT",
               spawning_km = 11, rearing_km = 21,
               rearing_stream_km = 16,
               rearing_lake_centerline_km = 3,
               rearing_wetland_centerline_km = 2,
               lake_rearing_ha = 105, wetland_rearing_ha = 50,
               stringsAsFactors = FALSE)
  }

  with_mocked_bindings(
    .lnk_compare_rollup_resolve_species = m_resolve,
    .lnk_compare_rollup_link = m_link,
    .lnk_compare_wsg_rollup_reference = m_ref,
    {
      result <- lnk_compare_rollup(
        conn = mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
        reference = "bcfishpass", conn_ref = mock_conn()
      )
    }
  )

  expect_equal(calls, c("resolve", "link", "ref"))
  # 8 habitat types × 1 species (7 habitat + accessible, link#221)
  expect_equal(nrow(result), 8L)
  expect_named(result, c("wsg", "species", "habitat_type", "unit",
                         "link_value", "ref_value", "diff_pct"))
  expect_setequal(unique(result$species), "BT")
  expect_setequal(unique(result$wsg), "ADMS")

  # accessible row: link value flows from km$accessible_km; ref has no
  # accessible column (tunnel-free ref path not yet wired) → NA diff.
  acc <- result[result$habitat_type == "accessible", ]
  expect_equal(nrow(acc), 1L)
  expect_equal(acc$link_value, 18)
  expect_equal(acc$unit, "km")
  expect_true(is.na(acc$ref_value))
  expect_true(is.na(acc$diff_pct))
})
