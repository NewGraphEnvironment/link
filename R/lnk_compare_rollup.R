#' Compare one watershed group's persisted state against a reference
#'
#' Comparison-only counterpart to [lnk_pipeline_run()]. Reads the
#' persisted `<persist_schema>.streams` + `streams_habitat_<sp>` tables
#' that `lnk_pipeline_run()` wrote, queries the reference dataset, and
#' returns a long-format diff tibble.
#'
#' Reads only — no writes to PG, no working schema. Caller persists the
#' return value (e.g. `saveRDS`) if a side-artifact is wanted; that's a
#' separate decision from whether the model itself ran.
#'
#' `reference` is a string identifying the comparison source. Today
#' only `"bcfishpass"` is supported (queries `bcfishpass.habitat_linear_<sp>`
#' on `conn_ref`). The arg is future-proofed for default-bundle parity,
#' regression detection across link runs, or non-bcfp external data —
#' new references plug in without renaming the public arg.
#'
#' ## Species resolution
#'
#' If `species = NULL` (default), the active species set is discovered
#' from PG: any `<persist_schema>.streams_habitat_<sp>` table with rows
#' for the requested WSG. This means the rollup is grounded in actual
#' persisted state — no need for `cfg$species` or
#' `wsg_species_presence` lookups here.
#'
#' If `species` is passed explicitly, it's intersected with the
#' PG-discovered set (caller-passed species absent from PG simply drop
#' out — no error).
#'
#' @param conn DBI connection to the local pipeline database (where
#'   `<persist_schema>` lives).
#' @param aoi Watershed group code (e.g. `"ADMS"`).
#' @param cfg An `lnk_config` object (used only to resolve
#'   `cfg$pipeline$schema` for the persisted table names).
#' @param reference Character scalar identifying the reference dataset.
#'   Currently only `"bcfishpass"` is supported.
#' @param conn_ref DBI connection to the reference database. Required
#'   when `reference = "bcfishpass"` (bcfp tunnel at
#'   `localhost:63333`).
#' @param species Optional character vector of species codes
#'   (e.g. `c("BT","CO")`) to restrict the rollup to. Default `NULL`
#'   discovers the set from PG.
#'
#' @return A tibble with one row per (species, habitat_type) — 7
#'   habitat types per species. Columns: `wsg`, `species`,
#'   `habitat_type`, `unit` (`km` | `ha`), `link_value`, `ref_value`,
#'   `diff_pct`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
#'   host = "localhost", port = 63333, dbname = "bcfishpass",
#'   user = "newgraph", password = Sys.getenv("PG_PASS_SHARE"))
#' cfg <- lnk_config("bcfishpass")
#'
#' # Compare-only against existing PG state (~2s).
#' rollup <- lnk_compare_rollup(
#'   conn = conn, aoi = "ADMS", cfg = cfg,
#'   reference = "bcfishpass", conn_ref = conn_ref
#' )
#' print(rollup)
#' }
#'
#' @family compare
#' @seealso [lnk_pipeline_run()], [lnk_compare_wsg()],
#'   [lnk_parity_annotate()]
#' @export
# nolint start: indentation_linter
lnk_compare_rollup <- function(conn, aoi, cfg,
                               reference = "bcfishpass",
                               conn_ref = NULL,
                               species = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    inherits(cfg, "lnk_config"),
    is.character(reference), length(reference) == 1L, nzchar(reference),
    is.null(species) || is.character(species)
  )

  supported_references <- c("bcfishpass")
  if (!reference %in% supported_references) {
    stop(
      "Unsupported reference '", reference, "'. Supported: ",
      paste(supported_references, collapse = ", "), ".",
      call. = FALSE
    )
  }
  if (reference == "bcfishpass" && !inherits(conn_ref, "DBIConnection")) {
    stop(
      "reference = 'bcfishpass' requires `conn_ref` (DBI connection to ",
      "the bcfp tunnel at localhost:63333).",
      call. = FALSE
    )
  }

  active_species <- .lnk_compare_rollup_resolve_species( # nolint
    conn = conn, cfg = cfg, aoi = aoi)
  if (length(active_species) == 0L) {
    stop("no persisted species found for ", aoi, " in ",
         cfg$pipeline$schema,
         " — run lnk_pipeline_run() first.",
         call. = FALSE)
  }
  if (!is.null(species)) {
    species <- intersect(species, active_species)
    if (length(species) == 0L) {
      stop("no species to roll up in ", aoi,
           " (persisted=", paste(active_species, collapse = ","),
           ") after intersecting with caller-passed `species`.",
           call. = FALSE)
    }
  } else {
    species <- active_species
  }

  rollup_link <- .lnk_compare_rollup_link( # nolint
    conn = conn, cfg = cfg, aoi = aoi, species = species)
  rollup_ref <- .lnk_compare_wsg_rollup_reference( # nolint
    reference = reference, conn_ref = conn_ref,
    aoi = aoi, species = species)

  .lnk_compare_wsg_assemble_rollup( # nolint
    aoi = aoi, species = species,
    rollup_link = rollup_link, rollup_ref = rollup_ref)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Discover which species have rows in `<persist_schema>.streams_habitat_<sp>`
#' for the requested WSG.
#'
#' Probes `information_schema.tables` for `streams_habitat_*` then runs
#' a `SELECT 1 ... LIMIT 1` per table filtered to the AOI. Species with
#' a hit join the active set.
#'
#' @noRd
.lnk_compare_rollup_resolve_species <- function(conn, cfg, aoi) {
  tn <- .lnk_table_names(cfg)
  schema_lit <- DBI::dbQuoteLiteral(conn, tn$schema)
  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

  tables <- DBI::dbGetQuery(conn, sprintf(
    "SELECT table_name FROM information_schema.tables
      WHERE table_schema = %s
        AND table_name LIKE 'streams_habitat\\_%%' ESCAPE '\\'",
    schema_lit))$table_name
  if (length(tables) == 0L) {
    return(character(0))
  }

  sp_candidates <- sub("^streams_habitat_", "", tables)
  # Defense in depth: lnk_persist_init only ever creates lowercase-alpha
  # species suffixes. Reject any stray table whose suffix has characters
  # outside that set rather than risk an injection-shaped SQL fault.
  sp_candidates <- sp_candidates[grepl("^[a-z]+$", sp_candidates)]
  active <- character(0)
  for (sp in sp_candidates) {
    n <- DBI::dbGetQuery(conn, sprintf(
      "SELECT 1 FROM %s.streams_habitat_%s
        WHERE watershed_group_code = %s LIMIT 1",
      tn$schema, sp, aoi_lit))
    if (nrow(n) > 0L) {
      active <- c(active, toupper(sp))
    }
  }
  active
}


#' Compute link-side rollup queries from `<persist_schema>` (persisted
#' state).
#'
#' Counterpart to `.lnk_compare_wsg_rollup_link` (which reads working
#' schema). Same output shape: `list(km, lake_ha, wetland_ha)` with
#' `species_code` keying each data.frame.
#'
#' Builds a per-species UNION ALL across the wide-per-species
#' `streams_habitat_<sp>` tables, then aggregates the long output by
#' `species_code`.
#'
#' @noRd
.lnk_compare_rollup_link <- function(conn, cfg, aoi, species) {
  tn <- .lnk_table_names(cfg)
  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)

  # Edge-type slices mirror the canonical fresh::frs_edge_types category
  # map used by .lnk_compare_wsg_rollup_link (working-schema variant).
  et_stream_sql  <- "(1000, 1050, 1100, 1150, 2000, 2100, 2300)"
  et_lake_sql    <- "(1500, 1525)"
  et_wetland_sql <- "(1700)"

  union_streams <- paste(vapply(species, function(sp) {
    sp_lit <- DBI::dbQuoteLiteral(conn, sp)
    sprintf(
      "SELECT %s AS species_code, s.id_segment, s.length_metre,
              s.edge_type, h.spawning, h.rearing
         FROM %s.streams s
         JOIN %s.streams_habitat_%s h ON s.id_segment = h.id_segment AND s.watershed_group_code = h.watershed_group_code
        WHERE s.watershed_group_code = %s",
      sp_lit, tn$schema, tn$schema, tolower(sp), aoi_lit)  # nolint: indentation_linter
  }, character(1)), collapse = "\n        UNION ALL\n        ")

  km <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code,
      round(SUM(CASE WHEN spawning THEN length_metre ELSE 0 END)::numeric
        / 1000, 2) AS spawning_km,
      round(SUM(CASE WHEN rearing  THEN length_metre ELSE 0 END)::numeric
        / 1000, 2) AS rearing_km,
      round(SUM(CASE WHEN rearing AND edge_type IN %s
                     THEN length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_stream_km,
      round(SUM(CASE WHEN rearing AND edge_type IN %s
                     THEN length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_lake_centerline_km,
      round(SUM(CASE WHEN rearing AND edge_type IN %s
                     THEN length_metre ELSE 0 END)::numeric / 1000, 2)
        AS rearing_wetland_centerline_km
    FROM (%s) per_species
    GROUP BY species_code ORDER BY species_code",
    et_stream_sql, et_lake_sql, et_wetland_sql, union_streams))  # nolint: indentation_linter

  # Lake / wetland ha — DISTINCT waterbody_key joins to fwa polygon
  # tables avoid double-counting multi-segment lakes/wetlands.
  union_lake <- paste(vapply(species, function(sp) {
    sp_lit <- DBI::dbQuoteLiteral(conn, sp)
    sprintf(
      "SELECT %s AS species_code, s.waterbody_key
         FROM %s.streams s
         JOIN %s.streams_habitat_%s h ON s.id_segment = h.id_segment AND s.watershed_group_code = h.watershed_group_code
        WHERE s.watershed_group_code = %s
          AND h.lake_rearing = TRUE",
      sp_lit, tn$schema, tn$schema, tolower(sp), aoi_lit)  # nolint: indentation_linter
  }, character(1)), collapse = "\n        UNION ALL\n        ")

  lake_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS lake_rearing_ha
    FROM (
      SELECT DISTINCT sub.species_code, l.waterbody_key, l.area_ha
      FROM (%s) sub
      JOIN whse_basemapping.fwa_lakes_poly l
        ON l.waterbody_key = sub.waterbody_key
    ) joined
    GROUP BY species_code", union_lake))

  union_wetland <- paste(vapply(species, function(sp) {
    sp_lit <- DBI::dbQuoteLiteral(conn, sp)
    sprintf(
      "SELECT %s AS species_code, s.waterbody_key
         FROM %s.streams s
         JOIN %s.streams_habitat_%s h ON s.id_segment = h.id_segment AND s.watershed_group_code = h.watershed_group_code
        WHERE s.watershed_group_code = %s
          AND h.wetland_rearing = TRUE",
      sp_lit, tn$schema, tn$schema, tolower(sp), aoi_lit)  # nolint: indentation_linter
  }, character(1)), collapse = "\n        UNION ALL\n        ")

  wetland_ha <- DBI::dbGetQuery(conn, sprintf("
    SELECT species_code, round(SUM(area_ha)::numeric, 2) AS wetland_rearing_ha
    FROM (
      SELECT DISTINCT sub.species_code, w.waterbody_key, w.area_ha
      FROM (%s) sub
      JOIN whse_basemapping.fwa_wetlands_poly w
        ON w.waterbody_key = sub.waterbody_key
    ) joined
    GROUP BY species_code", union_wetland))

  list(km = km, lake_ha = lake_ha, wetland_ha = wetland_ha)
}

# nolint end: indentation_linter
