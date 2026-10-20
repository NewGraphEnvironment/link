#' Settle persisted habitat flags on link's access
#'
#' Sets `accessible`, `spawning`, `rearing`, `lake_rearing` and
#' `wetland_rearing` FALSE in `<table_habitat>_<sp>` wherever
#' `<table_access>.access_<sp>` is 0, for one watershed group, so the habitat
#' flags agree with the access a consumer reads.
#'
#' The two columns are built at different times from different barrier sets
#' (link#349). fresh's `accessible`, which gates spawning and rearing inside
#' `frs_habitat_classify()`, is computed once per group from that group's own
#' breaks: metre-rounded positions, within the group only, lifted by the
#' group's own overrides. `access_<sp>` is link's, built from every group's
#' persisted barriers and overrides and re-settled after a multi-host run
#' ([lnk_access()] with `merge = TRUE`). `access_<sp>` is the authoritative
#' one, and this step makes the habitat flags follow it.
#'
#' Rows that `user_habitat_classification` marks as known habitat keep their
#' `spawning` / `rearing` (bcfishpass forces known habitat whatever the model
#' says, and so does [fresh::frs_habitat_overlay()]); their `accessible` is
#' still set FALSE. Pass the loaded table as `overlay` when the bundle applies
#' the overlay. The match is the overlay's own: same `blue_line_key`, the
#' segment's measure range inside the overlay row's.
#'
#' The settle is one-way. A segment it blanks gets its habitat back only from
#' a re-model of the group: when a later recompute lifts a segment
#' (`access_<sp>` 0 to 1 or 2) whose `accessible` is FALSE, its habitat is
#' missing until then. Pass the access values from before the recompute as
#' `table_access_prior` and those segments are counted in `n_lifted_settled`.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param aoi Character. Watershed group code (e.g. `"DUNC"`).
#' @param table_habitat Character. Schema-qualified prefix of the per-species
#'   habitat tables: `<table_habitat>_<sp>` (e.g. `"fresh_default.streams_habitat"`).
#' @param table_access Character. Schema-qualified `streams_access` table.
#' @param table_streams Character. Schema-qualified `streams` table (measures
#'   and `length_metre`).
#' @param species Character vector of species codes to settle.
#' @param overlay A data frame in `user_habitat_classification`'s shape
#'   (`species_code`, `blue_line_key`, `downstream_route_measure`,
#'   `upstream_route_measure`, `spawning`, `rearing`), or `NULL` for none.
#' @param table_access_prior Character or `NULL`. Schema-qualified table of
#'   `id_segment`, `watershed_group_code` and `access_<sp>` as they were before
#'   the recompute that precedes this call. `NULL` leaves `n_lifted_settled` NA.
#'
#' @return A data frame, one row per species and flag: `species`, `flag`,
#'   `n_segments` and `km` set from TRUE to FALSE, and `n_lifted_settled` (per
#'   species, repeated on its rows).
#'
#' @family pipeline
#' @seealso [lnk_access()], [lnk_pipeline_run()]
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("default")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # After a recompute of DUNC's access in fresh_default:
#' lnk_habitat_gate(conn, aoi = "DUNC",
#'   table_habitat = "fresh_default.streams_habitat",
#'   table_access  = "fresh_default.streams_access",
#'   table_streams = "fresh_default.streams",
#'   species = lnk_pipeline_species(cfg, loaded, "DUNC"),
#'   overlay = loaded$user_habitat_classification)
#' }
#'
#' @export
lnk_habitat_gate <- function(conn, aoi, table_habitat, table_access,
                             table_streams, species, overlay = NULL,
                             table_access_prior = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, grepl("^[A-Z]{3,5}$", aoi),
    is.character(species), length(species) > 0L,
    all(grepl("^[A-Za-z]{2,4}$", species)),
    is.null(overlay) || is.data.frame(overlay)
  )
  .lnk_validate_identifier(table_habitat, "table_habitat")
  .lnk_validate_identifier(table_access, "table_access")
  .lnk_validate_identifier(table_streams, "table_streams")
  if (!is.null(table_access_prior)) {
    .lnk_validate_identifier(table_access_prior, "table_access_prior")
  }

  sp_set <- unique(tolower(species))
  aoi_lit <- .lnk_quote_literal(aoi)
  flags <- c("accessible", "spawning", "rearing", "lake_rearing",
             "wetland_rearing")

  ov <- NULL
  if (!is.null(overlay)) {
    ov <- .lnk_gate_write_overlay(conn, overlay[toupper(overlay$species_code) %in%
                                                  toupper(sp_set), , drop = FALSE],
                                  aoi)
    on.exit(try(.lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", ov)),
                silent = TRUE), add = TRUE)
  }

  out <- vector("list", length(sp_set))
  for (i in seq_along(sp_set)) {
    sp <- sp_set[i]
    hab <- paste0(table_habitat, "_", sp)
    acc <- paste0("access_", sp)

    # The overlay keeps a flag where one of its rows for the species says so
    # and contains the segment (fresh::frs_habitat_overlay's match).
    keep <- function(flag) {
      if (is.null(ov)) return("FALSE")
      sprintf(
        "EXISTS (SELECT 1 FROM %s k
                  WHERE k.species_code = %s AND k.%s
                    AND k.blue_line_key = s.blue_line_key
                    AND s.downstream_route_measure >= k.downstream_route_measure
                    AND s.upstream_route_measure <= k.upstream_route_measure)",
        ov, .lnk_quote_literal(toupper(sp)), flag)
    }
    from_where <- sprintf(
      "FROM %1$s a, %2$s s
       WHERE a.id_segment = h.id_segment
         AND a.watershed_group_code = h.watershed_group_code
         AND s.id_segment = h.id_segment
         AND s.watershed_group_code = h.watershed_group_code
         AND h.watershed_group_code = %3$s
         AND a.%4$s = 0",
      table_access, table_streams, aoi_lit, acc)

    sql_count <- sprintf(
      "SELECT f.flag, count(*) AS n_segments,
              round((sum(s.length_metre) / 1000)::numeric, 3)::double precision AS km
       FROM %1$s h
       JOIN %2$s a ON a.id_segment = h.id_segment
                  AND a.watershed_group_code = h.watershed_group_code
       JOIN %3$s s ON s.id_segment = h.id_segment
                  AND s.watershed_group_code = h.watershed_group_code
       CROSS JOIN LATERAL (VALUES
         ('accessible', h.accessible IS TRUE),
         ('spawning', h.spawning IS TRUE AND NOT %4$s),
         ('rearing', h.rearing IS TRUE AND NOT %5$s),
         ('lake_rearing', h.lake_rearing IS TRUE),
         ('wetland_rearing', h.wetland_rearing IS TRUE)) f(flag, changes)
       WHERE h.watershed_group_code = %6$s AND a.%7$s = 0 AND f.changes
       GROUP BY f.flag",
      hab, table_access, table_streams, keep("spawning"), keep("rearing"),
      aoi_lit, acc)

    sql_lifted <- if (!is.null(table_access_prior)) {
      sprintf(
        "SELECT count(*) AS n_lifted
         FROM %1$s h
         JOIN %2$s a ON a.id_segment = h.id_segment
                    AND a.watershed_group_code = h.watershed_group_code
         JOIN %3$s p ON p.id_segment = h.id_segment
                    AND p.watershed_group_code = h.watershed_group_code
         WHERE h.watershed_group_code = %4$s
           AND p.%5$s = 0 AND a.%5$s > 0 AND h.accessible IS NOT TRUE",
        hab, table_access, table_access_prior, aoi_lit, acc)
    }

    sql_update <- sprintf(
      "UPDATE %1$s h SET
         accessible = FALSE,
         spawning = CASE WHEN %2$s THEN h.spawning ELSE FALSE END,
         rearing = CASE WHEN %3$s THEN h.rearing ELSE FALSE END,
         lake_rearing = FALSE,
         wetland_rearing = FALSE
       %4$s
         AND (h.accessible IS TRUE OR h.spawning IS TRUE OR h.rearing IS TRUE
              OR h.lake_rearing IS TRUE OR h.wetland_rearing IS TRUE)",
      hab, keep("spawning"), keep("rearing"), from_where)

    res <- .lnk_db_transaction(conn, {
      cnt <- .lnk_db_query(conn, sql_count)
      lifted <- if (is.null(sql_lifted)) NA_integer_ else
        as.integer(.lnk_db_query(conn, sql_lifted)$n_lifted)
      .lnk_db_execute(conn, sql_update)
      list(cnt = cnt, lifted = lifted)
    })

    cnt <- res$cnt
    n <- stats::setNames(as.integer(cnt$n_segments), cnt$flag)
    km <- stats::setNames(as.numeric(cnt$km), cnt$flag)
    lifted <- if (length(res$lifted) == 1L) res$lifted else NA_integer_
    out[[i]] <- data.frame(
      species = toupper(sp),
      flag = flags,
      n_segments = vapply(flags, function(f) if (is.na(n[f])) 0L else n[[f]],
                          integer(1), USE.NAMES = FALSE),
      km = vapply(flags, function(f) if (is.na(km[f])) 0 else km[[f]],
                  numeric(1), USE.NAMES = FALSE),
      n_lifted_settled = lifted,
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}


#' The overlay a bundle applies, for the gate
#'
#' `loaded$user_habitat_classification` when the bundle declares it and does
#' not turn the overlay off (`pipeline: apply_habitat_overlay: false`), the
#' same condition [lnk_pipeline_classify()] applies it on; else `NULL`.
#' @noRd
.lnk_habitat_gate_overlay <- function(cfg, loaded) {
  apply_overlay <- isTRUE(cfg$pipeline$apply_habitat_overlay %||% TRUE)
  if (apply_overlay) loaded$user_habitat_classification else NULL
}


#' Overlay rows as a session-temporary table for the gate
#'
#' Normalises `user_habitat_classification`'s indicator columns (integer 1,
#' `"t"`, `"true"`) to boolean, as fresh's overlay does with
#' `lower(trim(x::text)) IN ('true', 't', '1')`.
#' @noRd
.lnk_gate_write_overlay <- function(conn, overlay, aoi) {
  truthy <- function(v) tolower(trimws(as.character(v))) %in% c("1", "t", "true")
  df <- data.frame(
    species_code = toupper(as.character(overlay$species_code)),
    blue_line_key = as.integer(overlay$blue_line_key),
    downstream_route_measure = as.numeric(overlay$downstream_route_measure),
    upstream_route_measure = as.numeric(overlay$upstream_route_measure),
    spawning = truthy(overlay$spawning),
    rearing = truthy(overlay$rearing),
    stringsAsFactors = FALSE)
  name <- paste0("zz_lnk_gate_overlay_", tolower(aoi))
  DBI::dbWriteTable(conn, name, df, temporary = TRUE, overwrite = TRUE)
  .lnk_db_execute(conn, sprintf("CREATE INDEX ON %s (blue_line_key)", name))
  name
}


#' @noRd
.lnk_db_query <- function(conn, sql) DBI::dbGetQuery(conn, sql)

#' @noRd
.lnk_db_transaction <- function(conn, code) DBI::dbWithTransaction(conn, code)
