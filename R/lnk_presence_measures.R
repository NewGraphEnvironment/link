#' Measure each fish record for the presence review
#'
#' Builds session temp tables on `conn` and returns one row per record of
#' `bcfishobs.observations`, with the measures an operator reads before a
#' record counts as evidence for a presence cell (link#402). Nothing here
#' judges a record: the rules are the operator's, set from these numbers.
#'
#' Per record:
#' - `code_other_group`: the record's own 50k watershed code
#'   (`new_watershed_code`) runs through no part of the group the record is
#'   filed under, read from `whse_basemapping.fwa_streams_20k_50k` (a code can
#'   span several groups; a main stem's does). NA where the code is not in
#'   the lookup.
#' - `elevation_m`: the record point's Z, which bcfishobs takes from the
#'   matched stream. 0 reads as NA.
#' - `major_drainage`: the first segment of the record's watershed code
#'   (100 Fraser, 200 Mackenzie, 300 Columbia, 400 Skeena, ...).
#' - `barrier_below`: for species in `species_barrier`, the kind of the
#'   nearest natural barrier below the record (FALLS, GRADIENT,
#'   USER_DEFINITE in `fresh_default.barriers`) whose `blocks_species` holds
#'   the species. Lifts are not read: they count only records of species a
#'   group marks present, so they cannot judge an absent cell. NA where none,
#'   and `barriers_known` is FALSE in a group holding no barrier rows.
#' - `n_class_above`: counting records above that barrier of the species'
#'   lift pool (`lift_pools`), presence ignored: not excluded, not a release,
#'   dated `year_min` to `year_now`.
#' - `rearing_lake_ha` (KO only): the largest lake above that barrier, a lake
#'   placed by the stream segments that run through it (FWA lake polygons
#'   carry no local code).
#' - `lake_record`: bcfishobs matched the record to a lake; `lake_ha` and
#'   `known_sockeye_lake` (its lake's `waterbody_poly_id` is in
#'   `sockeye_lakes`) for those. The lake is found by the record's own
#'   `waterbody_identifier` (the lake's 50k key; several polygons can share
#'   one, so area is the largest and sockeye any), else by the lake polygon
#'   of the segment it was matched to: many lake records are snapped to a
#'   river or construction line outside the polygon.
#' - `through_main_stem`: the record's blue line continues upstream outside
#'   its group.
#' - `in_hist_zone`: its 50k code carries a historical distribution zone of
#'   the species (`zones`, cutthroat aliases folded as for the records;
#'   pre-2001 FISS, the same source as bcfishobs's FISS
#'   records, so not independent of them).
#' - `gradient`: the matched segment's.
#' - `counting`: not excluded, not a release, dated `year_min` to
#'   `year_now`, as the presence check counts a record.
#' - `yr`, `waterbody` and `site` (blue line and measure to the metre), for
#'   counting distinct years, waterbodies and sites. A waterbody is a lake's
#'   or wetland's own `waterbody_identifier`, otherwise the blue line the
#'   record is matched to: bcfishobs gives stream records a group-level
#'   identifier (`00000<group>`, not always the record's own group), not one
#'   per stream, and a record's own 50k code can name the main river it was
#'   filed under rather than the stream it is on.
#'
#' Cutthroat aliases (`CCT`, `ACT`, `CT/RB`) read as `CT`, as the presence
#' check reads them.
#'
#' @param conn A DBI connection to a database holding `bcfishobs`, FWA and
#'   `fresh_default.barriers`.
#' @param zones Data frame with `species_code` and `code50` (digits,
#'   trailing zeros trimmed).
#' @param species_barrier Species whose records are measured against the
#'   barriers below them.
#' @param lift_pools Named list: for each species in `species_barrier`, the
#'   species whose records count above its barrier.
#' @param sockeye_lakes `waterbody_poly_id`s of known sockeye lakes.
#' @param excl_keys,incl_keys `observation_key`s excluded
#'   ([.lnk_observation_exclusion_keys()]) and read as releases
#'   (`release_include`).
#' @param year_min,year_now Years a counting record falls between.
#' @return A data frame, one row per record.
#' @noRd
.lnk_presence_measures <- function(conn, zones, species_barrier, lift_pools,
                                   sockeye_lakes, excl_keys, incl_keys,
                                   year_min = 1950L,
                                   year_now = as.integer(format(Sys.Date(), "%Y"))) {
  stopifnot(all(c("species_code", "code50") %in% names(zones)),
            is.list(lift_pools),
            all(species_barrier %in% names(lift_pools)),
            length(year_min) == 1L, length(year_now) == 1L)
  pools <- do.call(rbind, lapply(species_barrier, function(s) {
    data.frame(species_code = s, pool_species = unique(lift_pools[[s]]),
               stringsAsFactors = FALSE)
  }))
  tmp <- function(name, df) {
    DBI::dbWriteTable(conn, name, df, temporary = TRUE, overwrite = TRUE)
  }
  # Fold cutthroat aliases in the zones as in the records.
  z <- zones[, c("species_code", "code50")]
  z$species_code <- ifelse(z$species_code %in% c("CCT", "ACT", "CT/RB"), "CT",
                           z$species_code)
  tmp("pm_zones", unique(z))
  tmp("pm_pools", pools)
  tmp("pm_sockeye", data.frame(waterbody_poly_id = as.numeric(sockeye_lakes)))
  tmp("pm_excl", data.frame(observation_key = as.character(excl_keys)))
  tmp("pm_incl", data.frame(observation_key = as.character(incl_keys)))
  for (s in .lnk_presence_measures_sql(year_min, year_now)) {
    suppressMessages(DBI::dbExecute(conn, s))
  }
  out <- DBI::dbGetQuery(conn, "SELECT * FROM pg_temp.pm_out ORDER BY observation_key")
  out
}

#' The statements `.lnk_presence_measures()` runs, in order
#' @noRd
.lnk_presence_measures_sql <- function(year_min, year_now) {
  year_min <- as.integer(year_min)
  year_now <- as.integer(year_now)
  stopifnot(!is.na(year_min), !is.na(year_now))
  c(
    "DROP TABLE IF EXISTS pg_temp.pm_rec",
    sprintf("
CREATE TEMP TABLE pm_rec AS
SELECT o.observation_key,
       o.watershed_group_code,
       CASE WHEN o.species_code IN ('CCT', 'ACT', 'CT/RB') THEN 'CT'
            ELSE o.species_code END AS species_code,
       replace(o.new_watershed_code, '-', '') AS code50_full,
       nullif(rtrim(replace(o.new_watershed_code, '-', ''), '0'), '') AS code50,
       nullif(ST_Z(o.geom), 0) AS elevation_m,
       split_part(o.wscode::text, '.', 1) AS major_drainage,
       s.gradient,
       s.waterbody_key,
       (o.waterbody_type = 'Lake') AS lake_record,
       (x.observation_key IS NULL
        AND NOT (coalesce(substring(o.source FROM 1 FOR position(':' IN o.source)), '')
                   = 'Releases Database:'
                 OR coalesce(o.source_ref ILIKE '%%BC RELEASE RECORDS DATABASE%%', false)
                 OR coalesce(o.source_ref ILIKE '%%STOCKING%%', false)
                 OR i.observation_key IS NOT NULL)
        AND extract(year FROM o.observation_date) BETWEEN %d AND %d) AS counting,
       extract(year FROM o.observation_date)::int AS yr,
       CASE WHEN o.waterbody_type IN ('Lake', 'Wetland')
                 AND o.waterbody_identifier IS NOT NULL
              THEN 'wb:' || o.waterbody_identifier
            ELSE 'line:' || o.blue_line_key END AS waterbody,
       o.waterbody_identifier,
       o.blue_line_key, o.downstream_route_measure, o.wscode, o.localcode
FROM bcfishobs.observations o
LEFT JOIN whse_basemapping.fwa_stream_networks_sp s
  ON s.linear_feature_id = o.linear_feature_id
LEFT JOIN pg_temp.pm_excl x ON x.observation_key = o.observation_key
LEFT JOIN (SELECT DISTINCT observation_key FROM pg_temp.pm_incl) i
  ON i.observation_key = o.observation_key", year_min, year_now),
    "CREATE INDEX ON pg_temp.pm_rec (species_code)",
    "CREATE INDEX ON pg_temp.pm_rec USING gist (wscode)",
    "ANALYZE pg_temp.pm_rec",

    # Groups each record's own 50k code runs through.
    "DROP TABLE IF EXISTS pg_temp.pm_codegrp",
    "
CREATE TEMP TABLE pm_codegrp AS
SELECT DISTINCT l.watershed_code_50k AS code50_full, l.watershed_group_code_20k AS wsg
FROM whse_basemapping.fwa_streams_20k_50k l
WHERE l.watershed_code_50k IN (SELECT DISTINCT code50_full FROM pg_temp.pm_rec)",
    "CREATE INDEX ON pg_temp.pm_codegrp (code50_full)",

    # The nearest blocking natural barrier below each record of a measured
    # species: deepest watershed code, then highest local code, then highest
    # measure. fwa_downstream(a, b) is true when b is downstream of a.
    "DROP TABLE IF EXISTS pg_temp.pm_bar",
    "
CREATE TEMP TABLE pm_bar AS
SELECT o.observation_key, o.species_code, b.barrier_source,
       b.blue_line_key AS b_blk, b.downstream_route_measure AS b_drm,
       b.wscode_ltree AS b_ws, b.localcode_ltree AS b_lc
FROM pg_temp.pm_rec o
CROSS JOIN LATERAL (
  SELECT b.barrier_source, b.blue_line_key, b.downstream_route_measure,
         b.wscode_ltree, b.localcode_ltree
  FROM fresh_default.barriers b
  WHERE b.barrier_source IN ('FALLS', 'GRADIENT', 'USER_DEFINITE')
    AND b.wscode_ltree @> o.wscode
    AND o.species_code = ANY (b.blocks_species)
    AND whse_basemapping.fwa_downstream(
          o.blue_line_key, o.downstream_route_measure, o.wscode, o.localcode,
          b.blue_line_key, b.downstream_route_measure, b.wscode_ltree, b.localcode_ltree)
  ORDER BY nlevel(b.wscode_ltree) DESC, b.localcode_ltree DESC,
           b.downstream_route_measure DESC
  LIMIT 1) b
WHERE o.species_code IN (SELECT DISTINCT species_code FROM pg_temp.pm_pools)
  AND o.wscode IS NOT NULL",

    # Counting records of the species' pool above each such barrier.
    "DROP TABLE IF EXISTS pg_temp.pm_above",
    "
CREATE TEMP TABLE pm_above AS
SELECT d.b_blk, d.b_drm, d.species_code,
       count(DISTINCT r.observation_key)::int AS n_class_above
FROM (SELECT DISTINCT b_blk, b_drm, b_ws, b_lc, species_code FROM pg_temp.pm_bar) d
JOIN pg_temp.pm_pools p ON p.species_code = d.species_code
JOIN pg_temp.pm_rec r
  ON r.species_code = p.pool_species
 AND r.counting
 AND r.wscode <@ d.b_ws
 AND whse_basemapping.fwa_upstream(
       d.b_blk, d.b_drm, d.b_ws, d.b_lc,
       r.blue_line_key, r.downstream_route_measure, r.wscode, r.localcode)
GROUP BY 1, 2, 3",

    # The largest lake above each barrier below a kokanee record.
    "DROP TABLE IF EXISTS pg_temp.pm_lake",
    "
CREATE TEMP TABLE pm_lake AS
SELECT d.b_blk, d.b_drm, max(l.area_ha) AS rearing_lake_ha
FROM (SELECT DISTINCT b_blk, b_drm, b_ws, b_lc FROM pg_temp.pm_bar
      WHERE species_code = 'KO') d
JOIN whse_basemapping.fwa_stream_networks_sp s
  ON s.wscode_ltree <@ d.b_ws
 AND s.waterbody_key IS NOT NULL
 AND whse_basemapping.fwa_upstream(
       d.b_blk, d.b_drm, d.b_ws, d.b_lc,
       s.blue_line_key, s.downstream_route_measure, s.wscode_ltree, s.localcode_ltree)
JOIN whse_basemapping.fwa_lakes_poly l ON l.waterbody_key = s.waterbody_key
GROUP BY 1, 2",

    # A lake record's lake: first by its own waterbody_identifier (the lake's
    # 50k key, not unique across polygons, so aggregated), else by the
    # polygon of the segment it was matched to.
    "DROP TABLE IF EXISTS pg_temp.pm_lake50",
    "
CREATE TEMP TABLE pm_lake50 AS
SELECT l.waterbody_key_group_code_50k AS wb_id, max(l.area_ha) AS area_ha,
       bool_or(l.waterbody_poly_id IN (SELECT waterbody_poly_id FROM pg_temp.pm_sockeye)) AS sockeye
FROM whse_basemapping.fwa_lakes_poly l
WHERE l.waterbody_key_group_code_50k IN
      (SELECT DISTINCT waterbody_identifier FROM pg_temp.pm_rec WHERE lake_record)
GROUP BY 1",
    "DROP TABLE IF EXISTS pg_temp.pm_lakekey",
    "
CREATE TEMP TABLE pm_lakekey AS
SELECT l.waterbody_key, max(l.area_ha) AS area_ha,
       bool_or(l.waterbody_poly_id IN (SELECT waterbody_poly_id FROM pg_temp.pm_sockeye)) AS sockeye
FROM whse_basemapping.fwa_lakes_poly l
WHERE l.waterbody_key IN (SELECT DISTINCT waterbody_key FROM pg_temp.pm_rec WHERE lake_record)
GROUP BY 1",
    "DROP TABLE IF EXISTS pg_temp.pm_out",
    "
CREATE TEMP TABLE pm_out AS
SELECT o.observation_key, o.watershed_group_code, o.species_code, o.counting,
       o.yr, o.waterbody,
       o.blue_line_key || ':' || round(o.downstream_route_measure)::bigint AS site,
       o.code50,
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_temp.pm_codegrp c
                             WHERE c.code50_full = o.code50_full) THEN NULL
            ELSE NOT EXISTS (SELECT 1 FROM pg_temp.pm_codegrp c
                             WHERE c.code50_full = o.code50_full
                               AND c.wsg = o.watershed_group_code) END AS code_other_group,
       o.elevation_m, o.major_drainage, o.gradient,
       EXISTS (SELECT 1 FROM fresh_default.barriers g
               WHERE g.watershed_group_code = o.watershed_group_code) AS barriers_known,
       b.barrier_source AS barrier_below,
       CASE WHEN b.barrier_source IS NULL THEN NULL
            ELSE coalesce(a.n_class_above, 0) END AS n_class_above,
       k.rearing_lake_ha,
       o.lake_record,
       CASE WHEN o.lake_record THEN coalesce(lw.area_ha, ls.area_ha) END AS lake_ha,
       CASE WHEN o.lake_record THEN coalesce(lw.sockeye, ls.sockeye, false) END AS known_sockeye_lake,
       EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
               WHERE s.blue_line_key = o.blue_line_key
                 AND s.watershed_group_code <> o.watershed_group_code
                 AND s.downstream_route_measure > o.downstream_route_measure) AS through_main_stem,
       CASE WHEN o.code50 IS NULL THEN NULL
            ELSE EXISTS (SELECT 1 FROM pg_temp.pm_zones z
                         WHERE z.species_code = o.species_code
                           AND z.code50 = o.code50) END AS in_hist_zone
FROM pg_temp.pm_rec o
LEFT JOIN pg_temp.pm_bar b ON b.observation_key = o.observation_key
LEFT JOIN pg_temp.pm_above a
  ON a.b_blk = b.b_blk AND a.b_drm = b.b_drm AND a.species_code = b.species_code
LEFT JOIN pg_temp.pm_lake k
  ON k.b_blk = b.b_blk AND k.b_drm = b.b_drm AND b.species_code = 'KO'
LEFT JOIN pg_temp.pm_lake50 lw ON lw.wb_id = o.waterbody_identifier
LEFT JOIN pg_temp.pm_lakekey ls ON ls.waterbody_key = o.waterbody_key"
  )
}

#' Roll the record measures up to presence cells
#'
#' Per group and species, over the records `.lnk_presence_measures()` marks
#' `counting` (the records the presence check counts, before pooling):
#' distinct sites, waterbodies and years; records whose own 50k code lies in
#' another group; records above a blocking natural barrier, and the fewest
#' and most counting records of the species' pool above any such barrier;
#' kokanee above a barrier with no lake above it; lake records and those in
#' a known sockeye lake; records on a main stem that flows through the
#' group; records on a stream with a historical distribution zone of the
#' species; the elevation range and the major drainages.
#'
#' @param m Data frame from `.lnk_presence_measures()`.
#' @return A data frame, one row per group and species with a counting
#'   record.
#' @noRd
.lnk_presence_cell_measures <- function(m) {
  need <- c("watershed_group_code", "species_code", "counting", "yr",
            "waterbody", "site", "code_other_group", "elevation_m",
            "major_drainage", "barriers_known", "barrier_below",
            "n_class_above", "rearing_lake_ha", "lake_record",
            "known_sockeye_lake", "through_main_stem", "in_hist_zone")
  miss <- setdiff(need, names(m))
  if (length(miss) > 0L) {
    stop("m lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  k <- m[m$counting %in% TRUE, , drop = FALSE]
  if (nrow(k) == 0L) {
    return(data.frame(watershed_group_code = character(0),
                      species_code = character(0)))
  }
  yes <- function(v) sum(v %in% TRUE)
  ndist <- function(v) length(unique(v[!is.na(v) & nzchar(v)]))
  rng <- function(v, f) if (all(is.na(v))) NA_real_ else f(v, na.rm = TRUE)
  key <- paste(k$watershed_group_code, k$species_code, sep = "\r")
  parts <- split(k, factor(key, levels = unique(key)))
  rows <- lapply(parts, function(d) {
    above <- !is.na(d$barrier_below)
    data.frame(
      watershed_group_code = d$watershed_group_code[1],
      species_code = d$species_code[1],
      n_counting = nrow(d),
      n_sites = ndist(d$site),
      n_waterbodies = ndist(d$waterbody),
      n_years = ndist(as.character(d$yr)),
      n_code_other_group = yes(d$code_other_group),
      barriers_known = any(d$barriers_known %in% TRUE),
      n_above_barrier = sum(above),
      above_kinds = paste(sort(unique(d$barrier_below[above])), collapse = ";"),
      min_class_above = rng(d$n_class_above[above], min),
      max_class_above = rng(d$n_class_above[above], max),
      n_ko_no_lake = sum(above & d$species_code == "KO" &
                           is.na(d$rearing_lake_ha)),
      n_lake_records = yes(d$lake_record),
      n_known_sockeye_lake = yes(d$known_sockeye_lake),
      n_main_stem = yes(d$through_main_stem),
      n_hist_zone = yes(d$in_hist_zone),
      elev_min = rng(d$elevation_m, min),
      elev_max = rng(d$elevation_m, max),
      drainages = paste(sort(unique(d$major_drainage[!is.na(d$major_drainage)])),
                        collapse = ";"),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out[order(out$watershed_group_code, out$species_code, method = "radix"), ,
      drop = FALSE]
}

#' One sentence of measures for a cell's story
#'
#' Drafted from a row of `.lnk_presence_cell_measures()`: distinct sites,
#' waterbodies and years, then only the measures that hold for some record
#' (filed under another group's code, above a blocking barrier, kokanee with
#' no lake above it, lake records, main stem, historical zone), then the
#' elevation range. Measures cover the species' own records, not records
#' pooled into it.
#'
#' @param cm Data frame of `.lnk_presence_cell_measures()` rows (NA rows,
#'   from a cell with no counting record, give "").
#' @return Character, one sentence per row.
#' @noRd
.lnk_presence_measure_story <- function(cm) {
  pl <- function(n, one, many = paste0(one, "s")) {
    sprintf("%d %s", n, if (identical(as.integer(n), 1L)) one else many)
  }
  vapply(seq_len(nrow(cm)), function(i) {
    r <- cm[i, , drop = FALSE]
    if (is.na(r$n_counting) || r$n_counting == 0L) return("")
    n <- r$n_counting
    of <- function(k) if (k == n) "all" else sprintf("%d of %d", k, n)
    out <- sprintf("Own records: %s on %s in %s",
                   pl(r$n_sites, "site"), pl(r$n_waterbodies, "waterbody",
                                             "waterbodies"),
                   pl(r$n_years, "year"))
    if (r$n_code_other_group > 0L) {
      out <- c(out, sprintf("%s filed under a 50k code that does not run through the group",
                            of(r$n_code_other_group)))
    }
    if (r$n_above_barrier > 0L) {
      cls <- if (r$min_class_above == r$max_class_above) {
        sprintf("%d", as.integer(r$max_class_above))
      } else {
        sprintf("%d to %d", as.integer(r$min_class_above),
                as.integer(r$max_class_above))
      }
      fmt <- paste0("%s above a natural barrier that blocks it (%s), with %s ",
                    "counting records of its class above")
      out <- c(out, sprintf(fmt, of(r$n_above_barrier),
                            gsub(";", ", ", tolower(r$above_kinds)), cls))
    } else if (!isTRUE(r$barriers_known)) {
      out <- c(out, "no barrier rows in the group")
    }
    if (r$n_ko_no_lake > 0L) {
      out <- c(out, sprintf("%s above a barrier with no lake above it",
                            of(r$n_ko_no_lake)))
    }
    if (r$n_lake_records > 0L) {
      lk <- sprintf("%s in lakes", of(r$n_lake_records))
      if (r$n_known_sockeye_lake > 0L) {
        lk <- sprintf("%s (%d in known sockeye lakes)", lk, r$n_known_sockeye_lake)
      }
      out <- c(out, lk)
    }
    if (r$n_main_stem > 0L) {
      out <- c(out, sprintf("%s on a main stem flowing through the group",
                            of(r$n_main_stem)))
    }
    out <- c(out, if (r$n_hist_zone > 0L) {
      sprintf("%s on a stream with a historical distribution zone of the species",
              of(r$n_hist_zone))
    } else {
      "none on a stream with a historical distribution zone of the species"
    })
    if (!is.na(r$elev_min)) {
      out <- c(out, if (r$elev_min == r$elev_max) {
        sprintf("at %d m", as.integer(round(r$elev_min)))
      } else {
        sprintf("%d to %d m", as.integer(round(r$elev_min)),
                as.integer(round(r$elev_max)))
      })
    }
    paste0(paste(out, collapse = "; "), ".")
  }, character(1))
}
