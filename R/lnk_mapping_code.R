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
#' `lnk_compare_run()`. The compare wrapper now goes through this
#' function via `lnk_pipeline_run(..., mapping_code = TRUE)`. Operators
#' can also call this directly against persist schema with the tunnel
#' down — the build is tunnel-independent (the diff vs reference is
#' separate, see [lnk_compare_mapping_code()]).
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
#' @param presence An `lnk_presence` object, a named logical vector, or
#'   `NULL`. Per-species presence for `aoi`. When `NULL` the function derives presence from
#'   the data: a species is present iff it has at least one habitat row
#'   with `spawning = TRUE` or `rearing = TRUE`. Pass explicit values
#'   to override (e.g. force-include a species for QGIS symbology even
#'   when no segments are accessible).
#' @param species_resident,species_anadromous,species_spawn_only Character
#'   or `NULL`: the residence sets, resolved as in
#'   [lnk_pipeline_mapping_code()] (from `cfg`, else bcfishpass's sets).
#' @param cfg An [lnk_config()] object, or `NULL`. Supplies the residence sets
#'   not passed (link#512) and the mapping-code rules (link#197).
#' @param rules_mapping_code A data frame of mapping-code rules, or `NULL` to
#'   read them from `cfg`, else the package copy.
#'
#' With `cfg` and no species arguments every species the bundle models is
#' coded; the persisted build (`.lnk_mapping_code_persist()`) passes the
#' group's active species instead.
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
    species_resident   = NULL,
    species_anadromous = NULL,
    species_spawn_only = NULL,
    cfg = NULL,
    rules_mapping_code = NULL) {

  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(table_access),  length(table_access)  == 1L, nzchar(table_access),
    is.character(table_habitat), length(table_habitat) == 1L, nzchar(table_habitat),
    is.character(table_streams), length(table_streams) == 1L, nzchar(table_streams),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.null(table_to) || (is.character(table_to) && length(table_to) == 1L)
  )
  sets <- .lnk_mc_species(cfg, species_resident, species_anadromous,
                          species_spawn_only)
  species_resident   <- sets$resident
  species_anadromous <- sets$anadromous
  species_spawn_only <- sets$spawn_only

  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)
  species_union <- tolower(union(species_resident, species_anadromous))

  # 1. Access: scalar projection from streams_access. lnk_pipeline_mapping_code
  # expects a data.frame keyed by id_segment.
  #
  # `id_segment` is per-WSG unique, NOT globally (link#203). When table_access
  # is a PERSIST table (all WSGs), `id_segment IN (FINA's segments)` matches
  # access rows from every WSG that happens to share those id_segment values
  # -> ~N(WSGs)× duplicates -> propagates through the pivot/joins below and
  # blows up `streams_mapping_code_pkey` on the persist write. Caught
  # 2026-05-25 in the link#205 cheap recompute. Fix: when table_access carries
  # `watershed_group_code` (persist shape, from lnk_persist_init's
  # cols_streams_access_base), filter by that directly. Working-schema access
  # (written by lnk_pipeline_access via dbWriteTable, no WSG col) falls back
  # to the id_segment-in clause (only one WSG present there, so the cartesian
  # is impossible).
  access_schema_table <- strsplit(table_access, "\\.", fixed = FALSE)[[1]]
  access_has_wsg <- DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.columns
       WHERE table_schema = %s AND table_name = %s
         AND column_name = 'watershed_group_code' LIMIT 1",
    DBI::dbQuoteString(conn, access_schema_table[1]),
    DBI::dbQuoteString(conn, access_schema_table[length(access_schema_table)])))
  if (nrow(access_has_wsg) > 0L) {
    access <- DBI::dbGetQuery(conn, sprintf(
      "SELECT * FROM %s WHERE watershed_group_code = %s",
      table_access, aoi_lit))
  } else {
    access <- DBI::dbGetQuery(conn, sprintf(
      "SELECT * FROM %s WHERE id_segment IN (
         SELECT id_segment FROM %s WHERE watershed_group_code = %s)",
      table_access, table_streams, aoi_lit))
  }
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
    species_resident   = species_resident,
    species_anadromous = species_anadromous,
    species_spawn_only = species_spawn_only,
    cfg                = cfg,
    rules_mapping_code = rules_mapping_code)
}


#' Rebuild one group's persisted mapping codes from persisted access + habitat
#'
#' The persist-side build shared by [lnk_pipeline_run()] (after the habitat
#' gate, link#349) and the post-consolidate recompute
#' (`data-raw/wsg_recompute_one.R`): [lnk_mapping_code()] over
#' `<schema>.streams_access` and `<schema>.streams_habitat_long_vw` into a
#' scratch table, then one transaction that replaces the group's rows in
#' `<schema>.streams_mapping_code` (watershed group joined from `streams`).
#' Reading persist, not the working tables, is what puts SPAWN / REAR tokens on
#' the settled flags.
#'
#' Which species read the resident or the anadromous barrier token, and which
#' spawn only, comes from the bundle's `dimensions.csv` (`residence`,
#' `rear_no_fw`) through [.lnk_species_residence()] (link#189). With
#' `cfg = NULL` the sets are the ones coded before that: CH, CM, CO, PK, SK and
#' ST anadromous, CM and PK spawn-only, every other species resident.
#'
#' @param schema Persist schema.
#' @param species Active species for `aoi`.
#' @param presence An `lnk_presence` object for `aoi`.
#' @param cfg The run's `lnk_config()` object, or `NULL`.
#' @noRd
.lnk_mapping_code_persist <- function(conn, schema, aoi, species, presence,
                                      cfg = NULL) {
  sp_set <- tolower(species)
  res <- .lnk_species_residence(cfg, sp_set)
  sp_resident   <- res$resident
  sp_anadromous <- res$anadromous
  sp_spawn_only <- res$spawn_only

  aoi_lit <- DBI::dbQuoteLiteral(conn, aoi)
  # No species classified here (only paused species present, #432): the group
  # keeps one row per segment with no code, as an absent species reads "".
  if (length(sp_set) == 0L) {
    DBI::dbWithTransaction(conn, {
      .lnk_db_execute(conn, sprintf(
        "DELETE FROM %s.streams_mapping_code WHERE watershed_group_code = %s",
        schema, aoi_lit))
      .lnk_db_execute(conn, sprintf(
        "INSERT INTO %s.streams_mapping_code (id_segment, watershed_group_code)
         SELECT id_segment, watershed_group_code FROM %s.streams
         WHERE watershed_group_code = %s",
        schema, schema, aoi_lit))
    })
    return(invisible(conn))
  }

  mc_name    <- paste0("zz_lnk_mc_scratch_", tolower(aoi))
  mc_scratch <- paste0(schema, ".", mc_name)
  on.exit(try(.lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", mc_scratch)),
              silent = TRUE), add = TRUE)

  lnk_mapping_code(conn,
    table_access  = paste0(schema, ".streams_access"),
    table_habitat = paste0(schema, ".streams_habitat_long_vw"),
    table_streams = paste0(schema, ".streams"),
    aoi           = aoi,
    table_to      = mc_scratch,
    presence      = presence,
    species_resident   = sp_resident,
    species_anadromous = sp_anadromous,
    species_spawn_only = sp_spawn_only,
    cfg                = cfg)

  mc_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s AND column_name <> 'id_segment'
     ORDER BY ordinal_position",
    DBI::dbQuoteString(conn, schema), DBI::dbQuoteString(conn, mc_name)))$column_name
  ins_cols <- paste(c("id_segment", "watershed_group_code", mc_cols), collapse = ", ")
  sel_cols <- paste(c("m.id_segment", "s.watershed_group_code",
                      paste0("m.", mc_cols)), collapse = ", ")
  # Atomic DELETE + INSERT: a failed INSERT must not leave the group's rows
  # deleted (FINA lost its mapping codes that way on 2026-05-25, #203).
  DBI::dbWithTransaction(conn, {
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s.streams_mapping_code WHERE watershed_group_code = %s",
      schema, aoi_lit))
    .lnk_db_execute(conn, sprintf(
      "INSERT INTO %s.streams_mapping_code (%s)
       SELECT %s FROM %s m JOIN %s.streams s USING (id_segment)
       WHERE s.watershed_group_code = %s",
      schema, ins_cols, sel_cols, mc_scratch, schema, aoi_lit))
  })
  invisible(conn)
}


#' Residence and spawn-only sets for a bundle's species
#'
#' Reads the `residence` column (`resident` or `anadromous`) and `rear_no_fw`
#' (`yes` spawns only) of the bundle's `dimensions.csv` (link#189). A bundle
#' whose `dimensions.csv` has no `residence` column, or `cfg = NULL`, gets the
#' sets coded before link#189: CH, CM, CO, PK, SK and ST anadromous, CM and PK
#' spawn-only, every other species resident.
#'
#' @param cfg An `lnk_config()` object, or `NULL`.
#' @param species Species codes, any case.
#' @return A list of lower-case character vectors `resident`, `anadromous`
#'   and `spawn_only`, each in the order of `species`.
#' @noRd
.lnk_species_residence <- function(cfg, species) {
  sp <- unique(tolower(species))
  anad_coded <- c("ch", "cm", "co", "pk", "sk", "st")
  fallback <- list(resident = setdiff(sp, anad_coded),
                   anadromous = intersect(sp, anad_coded),
                   spawn_only = intersect(sp, c("cm", "pk")))
  if (is.null(cfg) || is.null(cfg$dimensions)) return(fallback)
  dims <- utils::read.csv(cfg$dimensions, stringsAsFactors = FALSE,
                          check.names = FALSE, colClasses = "character",
                          na.strings = character())
  if (!"residence" %in% names(dims)) return(fallback)
  if (length(sp) == 0L) {
    return(list(resident = character(0), anadromous = character(0),
                spawn_only = character(0)))
  }
  key <- tolower(trimws(dims$species))
  i <- match(sp, key)
  if (anyNA(i)) {
    stop("species with no row in ", cfg$dimensions, ": ",
         paste(toupper(sp[is.na(i)]), collapse = ", "), call. = FALSE)
  }
  r <- tolower(trimws(dims$residence[i]))
  bad <- !r %in% c("resident", "anadromous")
  if (any(bad)) {
    stop("residence must be resident or anadromous in ", cfg$dimensions,
         "; not for: ", paste(toupper(sp[bad]), collapse = ", "), call. = FALSE)
  }
  no_fw <- if ("rear_no_fw" %in% names(dims)) {
    tolower(trimws(dims$rear_no_fw[i])) == "yes"
  } else {
    rep(FALSE, length(sp))
  }
  list(resident = sp[r == "resident"], anadromous = sp[r == "anadromous"],
       spawn_only = sp[no_fw])
}
