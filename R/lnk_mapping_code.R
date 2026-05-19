#' Build per-segment per-species mapping_code tokens from schema tables
#'
#' Schema-aware portable wrapper around [lnk_pipeline_mapping_code()].
#' Queries `table_access`, `table_habitat` (long form), and
#' `table_streams.feature_code`, assembles the inputs (pivot habitat
#' long → wide, build feature_code lookup), calls
#' [lnk_pipeline_mapping_code()] for the per-segment token compute, and
#' optionally writes the result to `table_to`.
#'
#' Decouples the mapping_code build from any specific schema layout.
#' Caller passes explicit table names — the function works against
#' working-schema tables (mid-pipeline) or persist-schema tables
#' (ad-hoc rebuild) without modification. The companion view
#' `<persist_schema>.streams_habitat_long_vw` (created by
#' [lnk_persist_init()]) presents the per-species split as a long-form
#' shape so `table_habitat` can point at either layout.
#'
#' This function replaces the inline assembly previously buried inside
#' `lnk_compare_wsg()`. The compare wrapper now goes through this
#' function via `lnk_pipeline_run(..., mapping_code = TRUE)`. Operators
#' can also call this directly against persist schema with the tunnel
#' down — the build is tunnel-independent (the diff vs reference is
#' separate, see `.lnk_compare_wsg_mapping_code_diff`).
#'
#' Tracks link#187 (tunnel decouple + portable build).
#'
#' @param conn A [DBI::DBIConnection-class] to the local pipeline DB.
#' @param table_access Character. Schema-qualified name of the
#'   `streams_access` table (e.g. `"working_pars.streams_access"` or
#'   `"fresh_default.streams_access"`).
#' @param table_habitat Character. Schema-qualified name of a long-form
#'   habitat source — either the working-schema `streams_habitat` table
#'   or the persist `streams_habitat_long_vw` view. Must have columns
#'   `id_segment`, `watershed_group_code`, `species_code`, `spawning`,
#'   `rearing`.
#' @param table_streams Character. Schema-qualified name of the
#'   `streams` table, queried for `id_segment` + `feature_code`.
#' @param aoi Character. Watershed group code (e.g. `"PARS"`) — filters
#'   all input queries to one WSG.
#' @param table_to Character or `NULL`. Optional schema-qualified
#'   destination table for the result. When non-NULL,
#'   `lnk_pipeline_mapping_code()` writes the tibble via
#'   `dbWriteTable(overwrite = TRUE)`. Default `NULL` — returns-only.
#' @param presence Named logical vector or `NULL`. Per-species presence
#'   flag for `aoi`. When `NULL` the function derives presence from
#'   the data: a species is present iff it has at least one habitat row
#'   with `spawning = TRUE` or `rearing = TRUE`. Pass explicit values
#'   to override (e.g. force-include a species for QGIS symbology even
#'   when no segments are accessible).
#' @param species_resident Character. Species using the resident flavor
#'   of `mapping_code_barrier`. Default `c("bt", "wct")`. Pass-through
#'   to [lnk_pipeline_mapping_code()]'s `resident_species` arg.
#' @param species_anadromous Character. Species using the anadromous
#'   flavor. Default `c("ch", "cm", "co", "pk", "sk", "st")`.
#'   Pass-through to `lnk_pipeline_mapping_code()`'s
#'   `anadromous_species` arg.
#' @param species_spawn_only Character. Species without rearing
#'   semantics. Default `c("cm", "pk")`. Pass-through to
#'   `lnk_pipeline_mapping_code()`'s `spawn_only_species` arg.
#'
#' @return Invisibly, the per-segment per-species mapping_code tibble
#'   keyed by `id_segment` with one `mapping_code_<sp>` text column per
#'   species in `union(species_resident, species_anadromous)`.
#'
#' @family compare
#'
#' @examples
#' \dontrun{
#' conn <- DBI::dbConnect(
#'   RPostgres::Postgres(),
#'   host = "localhost", port = 5432, dbname = "fwapg",
#'   user = "postgres", password = "postgres")
#'
#' # Working-schema build during a pipeline run:
#' lnk_mapping_code(
#'   conn,
#'   table_access  = "working_pars.streams_access",
#'   table_habitat = "working_pars.streams_habitat",
#'   table_streams = "working_pars.streams",
#'   aoi           = "PARS",
#'   table_to      = "working_pars.streams_mapping_code")
#'
#' # Ad-hoc rebuild against persist (tunnel-free) for QGIS symbology:
#' lnk_mapping_code(
#'   conn,
#'   table_access  = "fresh_default.streams_access",
#'   table_habitat = "fresh_default.streams_habitat_long_vw",
#'   table_streams = "fresh_default.streams",
#'   aoi           = "PARS",
#'   table_to      = "fresh_default.streams_mapping_code")
#' }
#'
#' @export
lnk_mapping_code <- function(
    conn,
    table_access,
    table_habitat,
    table_streams,
    aoi,
    table_to = NULL,
    presence = NULL,
    species_resident   = c("bt", "wct"),
    species_anadromous = c("ch", "cm", "co", "pk", "sk", "st"),
    species_spawn_only = c("cm", "pk")) {

  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(table_access),  length(table_access)  == 1L, nzchar(table_access),
    is.character(table_habitat), length(table_habitat) == 1L, nzchar(table_habitat),
    is.character(table_streams), length(table_streams) == 1L, nzchar(table_streams),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.null(table_to) || (is.character(table_to) && length(table_to) == 1L),
    is.character(species_resident),
    is.character(species_anadromous),
    is.character(species_spawn_only)
  )

  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)
  species_union <- tolower(union(species_resident, species_anadromous))

  # 1. Access: scalar projection from streams_access. lnk_pipeline_mapping_code
  # expects a data.frame keyed by id_segment.
  access <- DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s WHERE id_segment IN (
       SELECT id_segment FROM %s WHERE watershed_group_code = %s)",
    table_access, table_streams, aoi_lit))
  if (nrow(access) == 0L) {
    stop(sprintf("%s empty for WSG %s", table_access, aoi), call. = FALSE)
  }

  # 2. Habitat: long form -> wide. Pre-allocate species columns the
  # transform expects so missing species (zero presence) don't trip the
  # downstream column lookups.
  hab_long <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, lower(species_code) AS species_code,
            COALESCE(spawning::int, 0) AS spawning,
            COALESCE(rearing::int, 0)  AS rearing
       FROM %s
      WHERE watershed_group_code = %s",
    table_habitat, aoi_lit))
  if (nrow(hab_long) == 0L) {
    stop(sprintf("%s empty for WSG %s", table_habitat, aoi), call. = FALSE)
  }
  hab_wide <- tidyr::pivot_wider(
    hab_long,
    id_cols     = "id_segment",
    names_from  = "species_code",
    values_from = c("spawning", "rearing"),
    values_fill = list(spawning = 0L, rearing = 0L))
  for (sp in species_union) {
    for (col in c(paste0("spawning_", sp), paste0("rearing_", sp))) {
      if (!(col %in% names(hab_wide))) hab_wide[[col]] <- 0L
    }
  }

  # 3. Feature code lookup keyed by id_segment.
  fc <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, feature_code FROM %s
      WHERE watershed_group_code = %s",
    table_streams, aoi_lit))

  # 4. Presence: derive if not provided. A species is present iff it
  # has at least one habitat row with spawning or rearing.
  if (is.null(presence)) {
    presence <- vapply(species_union, function(sp) {
      sp_rows <- hab_long[hab_long$species_code == sp, , drop = FALSE]
      isTRUE(any(sp_rows$spawning > 0L | sp_rows$rearing > 0L))
    }, logical(1))
    names(presence) <- species_union
  }

  # 5. Delegate to the pure data transform.
  lnk_pipeline_mapping_code( # nolint: object_usage_linter
    access             = access,
    habitat            = hab_wide,
    feature_code       = fc,
    to                 = table_to,
    conn               = conn,
    presence           = presence,
    resident_species   = species_resident,
    anadromous_species = species_anadromous,
    spawn_only_species = species_spawn_only)
}
