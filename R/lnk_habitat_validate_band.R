#' Score the habitat one threshold step adds or removes
#'
#' Compares two persisted runs that share segmentation and differ in one
#' habitat threshold, and asks whether the segments the step moves (the
#' **band**) are used by fish about as often as habitat both runs agree on
#' (the **core**). It reports observations per km in each and their ratio,
#' which is the evidence for taking or refusing the step.
#'
#' For each watershed group and species:
#' - **Band, `added`:** segments `flag` in `schema` and not in `schema_ref`.
#' - **Band, `removed`:** segments `flag` in `schema_ref` and not in
#'   `schema`.
#' - **Core:** segments `flag` in every schema of `schema_core`. Pass all
#'   the schemas of a threshold ladder so the core is the habitat no step
#'   in it moves.
#'
#' Observation locations are counted on the segment the validator attached
#' them to, so `observations` must come from [lnk_habitat_validate()] on
#' one of these schemas.
#'
#' @section Why segmentation must match:
#' Segments are compared on the full key `(id_segment, watershed_group_code)`,
#' which names the same stretch of stream in two schemas only when both were
#' broken identically. Two full pipeline runs are not guaranteed to be, so
#' prepare the network once and re-classify it per threshold. The function
#' compares an `id_segment` x `length_metre` digest of `streams` per WSG
#' across every schema it reads and stops when any differ. It also stops
#' when a schema holds no `streams_habitat_<sp>` rows for a WSG, which would
#' otherwise read as a WSG with no habitat.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [lnk_db_conn()]).
#' @param aoi Character vector of watershed group codes, persisted in every
#'   schema.
#' @param species Character vector of model species codes. Each must name
#'   `<schema>.streams_habitat_<sp>` in every schema.
#' @param flag `"spawning"` or `"rearing"` (fresh's `rearing` flag, which
#'   the rearing thresholds govern on stream lines).
#' @param schema Persist schema with the step taken.
#' @param schema_ref Persist schema the step is taken from.
#' @param observations The `observations` data frame from
#'   [lnk_habitat_validate()]. Uses `species_code`, `watershed_group_code`,
#'   `id_segment`, `is_spawn` and `is_rear`.
#' @param stage Which locations count: `"any"` (all), `"spawn"` (spawn-staged)
#'   or `"rear"` (rear-staged).
#' @param schema_core Character vector of persist schemas whose shared
#'   `flag` segments form the core. Default `c(schema, schema_ref)`.
#'
#' @return A data frame, one row per `watershed_group_code` x `species_code`
#'   x `direction` (`added`, `removed`), with `flag`, `stage`, `band_km`,
#'   `n_band` (locations on band segments), `core_km`, `n_core`,
#'   `density_band` and `density_core` (locations per km; `NA` when the km
#'   is 0) and `density_ratio` (`density_band / density_core`; `NA` when
#'   either is `NA` or the core density is 0). Counts are returned beside
#'   the densities so rows can be pooled across WSGs by summing.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' cfg <- lnk_config("default")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Observations as the validator attaches them to segments
#' v <- lnk_habitat_validate(conn, aoi = "BULL", cfg = cfg, loaded = loaded,
#'                           species = "BT", schema = "score284_default")
#'
#' # Is the rearing that BT rear_gradient_max 0.1249 -> 0.1349 adds used as
#' # often per km as the rearing every step agrees on?
#' lnk_habitat_validate_band(
#'   conn, aoi = "BULL", species = "BT", flag = "rearing",
#'   schema = "score284_bt_rear_0p1349",
#'   schema_ref = "score284_bt_rear_0p1249",
#'   observations = v$observations, stage = "any",
#'   schema_core = c("score284_default", "score284_bt_rear_0p1249",
#'                   "score284_bt_rear_0p1349"))
#' }
#'
#' @family compare
#' @seealso [lnk_habitat_validate()]
#' @export
# nolint start: indentation_linter
lnk_habitat_validate_band <- function(conn, aoi, species,
                                      flag = c("spawning", "rearing"),
                                      schema, schema_ref, observations,
                                      stage = c("any", "spawn", "rear"),
                                      schema_core = c(schema, schema_ref)) {
  flag <- match.arg(flag)
  stage <- match.arg(stage)
  is_schema <- function(x) {
    is.character(x) && length(x) >= 1L && !anyNA(x) &&
      all(grepl("^[a-z_][a-z0-9_]*$", x))
  }
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) >= 1L, !anyNA(aoi),
    all(grepl("^[A-Z]{3,5}$", aoi)),
    is.character(species), length(species) >= 1L, !anyNA(species),
    all(grepl("^[A-Za-z]+$", species)),
    is_schema(schema), length(schema) == 1L,
    is_schema(schema_ref), length(schema_ref) == 1L,
    schema != schema_ref,
    is_schema(schema_core),
    is.data.frame(observations)
  )
  cols_obs <- c("species_code", "watershed_group_code", "id_segment",
                "is_spawn", "is_rear")
  miss <- setdiff(cols_obs, names(observations))
  if (length(miss) > 0L) {
    stop("observations is missing columns: ", paste(miss, collapse = ", "),
         " (pass lnk_habitat_validate()$observations)", call. = FALSE)
  }
  aoi <- unique(aoi)
  species <- unique(toupper(species))
  schemas <- unique(c(schema, schema_ref, schema_core))

  .lnk_hvb_check_segmentation(conn, schemas, aoi)
  .lnk_hvb_check_habitat(conn, schemas, aoi, species)

  o <- observations[!is.na(observations$id_segment) &
                      toupper(observations$species_code) %in% species &
                      observations$watershed_group_code %in% aoi, ,
                    drop = FALSE]
  keep <- switch(stage,
                 any = rep(TRUE, nrow(o)),
                 spawn = o$is_spawn %in% TRUE,
                 rear = o$is_rear %in% TRUE)
  o <- o[keep, , drop = FALSE]
  .lnk_hv_drop_temp(conn, "lnk_vb_obs")
  DBI::dbWriteTable(conn, "lnk_vb_obs", data.frame(
    species_code = toupper(o$species_code),
    watershed_group_code = o$watershed_group_code,
    id_segment = as.integer(o$id_segment), stringsAsFactors = FALSE),
    temporary = TRUE, overwrite = TRUE)

  aoi_arr <- paste0("{", paste(aoi, collapse = ","), "}")
  out <- do.call(rbind, lapply(species, function(sp) {
    spl <- tolower(sp)
    joins <- paste(vapply(seq_along(schemas), function(i) {
      sprintf(
        "LEFT JOIN %1$s.streams_habitat_%2$s h%3$d
           ON h%3$d.id_segment = s.id_segment
          AND h%3$d.watershed_group_code = s.watershed_group_code",
        schemas[i], spl, i)
    }, character(1)), collapse = "\n ")
    f <- function(sch) {
      sprintf("coalesce(h%d.%s, false)", match(sch, schemas), flag)
    }
    core <- paste(vapply(schema_core, f, character(1)), collapse = " AND ")
    d <- DBI::dbGetQuery(conn, sprintf(
      "WITH seg AS (
         SELECT s.watershed_group_code, s.id_segment, s.length_metre,
                %3$s AND NOT %4$s AS added,
                %4$s AND NOT %3$s AS removed,
                %5$s AS core
           FROM %1$s.streams s
           %2$s
          WHERE s.watershed_group_code = ANY($1)),
       obs AS (
         SELECT watershed_group_code, id_segment, count(*)::int AS n
           FROM pg_temp.lnk_vb_obs
          WHERE species_code = $2
          GROUP BY 1, 2)
       SELECT g.watershed_group_code,
              coalesce(sum(g.length_metre) FILTER (WHERE g.added), 0)
                / 1000 AS added_km,
              coalesce(sum(o.n) FILTER (WHERE g.added), 0)::int AS added_n,
              coalesce(sum(g.length_metre) FILTER (WHERE g.removed), 0)
                / 1000 AS removed_km,
              coalesce(sum(o.n) FILTER (WHERE g.removed), 0)::int AS removed_n,
              coalesce(sum(g.length_metre) FILTER (WHERE g.core), 0)
                / 1000 AS core_km,
              coalesce(sum(o.n) FILTER (WHERE g.core), 0)::int AS core_n
         FROM seg g
         LEFT JOIN obs o
           ON o.watershed_group_code = g.watershed_group_code
          AND o.id_segment = g.id_segment
        GROUP BY 1",
      schema, joins, f(schema), f(schema_ref), core),
      params = list(aoi_arr, sp))
    # A WSG with no streams rows still gets its rows, as zeros.
    d <- merge(data.frame(watershed_group_code = aoi,
                          stringsAsFactors = FALSE), d, all.x = TRUE)
    num <- setdiff(names(d), "watershed_group_code")
    d[num] <- lapply(d[num], function(x) ifelse(is.na(x), 0, x))
    rbind(
      data.frame(watershed_group_code = d$watershed_group_code,
                 species_code = sp, direction = "added",
                 band_km = d$added_km, n_band = as.integer(d$added_n),
                 core_km = d$core_km, n_core = as.integer(d$core_n),
                 stringsAsFactors = FALSE),
      data.frame(watershed_group_code = d$watershed_group_code,
                 species_code = sp, direction = "removed",
                 band_km = d$removed_km, n_band = as.integer(d$removed_n),
                 core_km = d$core_km, n_core = as.integer(d$core_n),
                 stringsAsFactors = FALSE))
  }))
  .lnk_hv_drop_temp(conn, "lnk_vb_obs")

  out <- cbind(out[1:3], data.frame(flag = flag, stage = stage,
                                    stringsAsFactors = FALSE), out[-(1:3)])
  dens <- .lnk_hvb_density(out$n_band, out$band_km, out$n_core, out$core_km)
  out <- cbind(out, dens)
  out <- out[order(out$species_code, out$watershed_group_code,
                   out$direction), ]
  rownames(out) <- NULL
  out
}

#' Observations per km and their ratio; NA where a km or the core density
#' is 0, never 0 or Inf.
#' @noRd
.lnk_hvb_density <- function(n_band, band_km, n_core, core_km) {
  per_km <- function(n, km) ifelse(km > 0, n / km, NA_real_)
  db <- per_km(n_band, band_km)
  dc <- per_km(n_core, core_km)
  data.frame(density_band = db, density_core = dc,
             density_ratio = ifelse(!is.na(dc) & dc > 0, db / dc, NA_real_))
}

#' Stop unless every schema holds habitat rows for every species x WSG.
#'
#' A schema can carry an empty `streams_habitat_<sp>` (persist creates every
#' species' table; a run may fill only some), which a LEFT JOIN would read as
#' "no habitat" and turn into a band or a core of zero.
#' @noRd
.lnk_hvb_check_habitat <- function(conn, schemas, aoi, species) {
  aoi_arr <- paste0("{", paste(aoi, collapse = ","), "}")
  miss <- character(0)
  for (s in schemas) {
    for (sp in species) {
      have <- DBI::dbGetQuery(conn, sprintf(
        "SELECT DISTINCT watershed_group_code FROM %s.streams_habitat_%s
          WHERE watershed_group_code = ANY($1)", s, tolower(sp)),
        params = list(aoi_arr))$watershed_group_code
      gone <- setdiff(aoi, have)
      if (length(gone) > 0L) {
        miss <- c(miss, paste0(s, ".streams_habitat_", tolower(sp), ":", gone))
      }
    }
  }
  if (length(miss) > 0L) {
    stop("no habitat rows for: ", paste(miss, collapse = ", "),
         ". Pass only WSGs where every schema modelled the species.",
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Stop unless every schema carries the same segments per WSG.
#' @noRd
.lnk_hvb_check_segmentation <- function(conn, schemas, aoi) {
  aoi_arr <- paste0("{", paste(aoi, collapse = ","), "}")
  dg <- do.call(rbind, lapply(schemas, function(s) {
    d <- DBI::dbGetQuery(conn, sprintf(
      "SELECT watershed_group_code,
              md5(string_agg(id_segment::text || ':' ||
                             round(length_metre::numeric, 3)::text, '|'
                             ORDER BY id_segment)) AS digest
         FROM %s.streams
        WHERE watershed_group_code = ANY($1)
        GROUP BY 1", s), params = list(aoi_arr))
    d <- merge(data.frame(watershed_group_code = aoi,
                          stringsAsFactors = FALSE), d, all.x = TRUE)
    d$schema <- s
    d
  }))
  empty <- dg[is.na(dg$digest), , drop = FALSE]
  if (nrow(empty) > 0L) {
    stop("no streams for: ",
         paste(unique(paste0(empty$schema, ":", empty$watershed_group_code)),
               collapse = ", "), call. = FALSE)
  }
  n_distinct <- tapply(dg$digest, dg$watershed_group_code,
                       function(x) length(unique(x)))
  bad <- names(n_distinct)[n_distinct > 1L]
  if (length(bad) > 0L) {
    stop("segmentation differs between ", paste(schemas, collapse = ", "),
         " in: ", paste(bad, collapse = ", "),
         ". Compare runs that share one prepared network.", call. = FALSE)
  }
  invisible(TRUE)
}
# nolint end: indentation_linter
