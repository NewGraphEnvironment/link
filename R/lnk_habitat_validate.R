#' Validate modelled habitat against fish observations
#'
#' Scores a persisted run against fish observations rather than against
#' another model. For each watershed group and species it reports how many
#' observations land on modelled accessible, spawning and rearing segments
#' (**capture**), how much habitat the run models to achieve that (**cost**,
#' so capture cannot be bought by calling everything habitat), and, for each
#' observation outside modelled habitat, what excluded its segment
#' (**misses** — the direct evidence for which threshold is binding). Sites
#' sampled with the species not caught can be supplied as **absences**, a
#' false-positive check.
#'
#' Runs over two persist schemas (two config bundles) stack row-wise, so
#' bundles can be diffed on the same observations.
#'
#' @section Which observations count:
#' From `observations` (a `bcfishobs.observations`-shaped table), keeping:
#' - records not flagged `data_error` or `release_exclude` in
#'   `loaded$observation_exclusions` (the pipeline's own filter), and not
#'   from the `Releases Database` source (stocked fish are not evidence of
#'   habitat use);
#' - observation species admitted for the model species by `species_obs`,
#'   and only in WSGs where `loaded$wsg_species_presence` marks the model
#'   species present (so DV records count as BT only where BT is present);
#' - `match_type` classes in `match_types` (default A/B: matched to a
#'   stream within 100 m; C, 100-500 m from a stream, and the D/E
#'   waterbody matches are left out);
#' - one per species x `blue_line_key` x metre (repeat visits are one
#'   location; a location is spawn- or rear-staged if any record there is).
#'
#' Pass a different `observations` table to score a held-out subset (by
#' project, date or WSG).
#'
#' @section Which segment an observation is on:
#' The pipeline breaks streams at observations, so most points sit on a
#' segment boundary. The segment **starting** within 1 m of the point (the
#' upstream one) is used, else the one containing it. A location with no
#' segment is counted in `n_unattached` and nowhere else. All joins between
#' `streams`, `streams_access` and `streams_habitat_<sp>` are on the full key
#' `(id_segment, watershed_group_code)`: `id_segment` repeats across groups.
#'
#' `buffer_m > 0` also counts an observation as captured when modelled
#' habitat starts within `buffer_m` metres **upstream** along the same
#' `blue_line_key` and WSG, because observation points often mark the
#' downstream end of a sampled site. It follows the mainstem only (never a
#' tributary), stops at the WSG boundary, and is measured along the stream,
#' so it does not depend on segmentation. Accessibility is always the point's
#' own segment. Near lakes the buffer reaches connector flow lines, which
#' are rearing without any threshold test, so buffered rearing capture there
#' says nothing about thresholds.
#'
#' @section Reading the numbers:
#' - **Accessible** is `streams_access.access_<sp> IN (1, 2)`, the definition
#'   [lnk_rollup_wsg()]'s `accessible_km` uses, so capture and cost agree.
#'   The spawning and rearing flags are gated by the pipeline's own
#'   `streams_habitat.accessible`, which differs slightly, so
#'   `share_spawning` is not strictly a subset of `share_accessible`.
#' - **Accessible capture is partly circular.** Observations are pipeline
#'   inputs: they lift barriers (`observation_threshold` in
#'   `parameters_fresh.csv`), they are break points, and where
#'   `apply_habitat_overlay` is on, `user_habitat_classification` forces
#'   habitat. Spawning and rearing capture is the score.
#'   `n_in_uhc_spawn` / `n_in_uhc_rear` count locations inside a
#'   `user_habitat_classification` reach confirming that habitat type for the
#'   species (indicator 1); with `overlay_applied` TRUE the segments wholly
#'   inside such a reach are forced to habitat, so most of those locations are
#'   captured by construction. `share_spawning_outside_uhc` and
#'   `share_rearing_any_outside_uhc` repeat the capture without them, which is
#'   the part of the score the observations did not decide.
#' - **Thresholds set from these observations score in-sample.** A cutoff
#'   calibrated on the same records (e.g. a use quantile) is partly
#'   guaranteed its capture; hold records out to score it fairly.
#' - `rearing` is stream rearing, the flag thresholds govern and that
#'   `rearing_km` costs. `rearing_any` adds lake and wetland rearing.
#' - Known biases, reported rather than corrected: observation points often
#'   sit at the downstream end of a site (see `buffer_m`); sampling clusters
#'   near road access; and fish are only observed where they have access, so
#'   observed gradients are cut off at the access limit.
#'
#' @section Miss reasons:
#' `miss_reason_spawn` keys on `spawning` and `miss_reason_rear` on
#' `rearing_any`, so a location on lake or wetland rearing is captured for
#' the rear reason (compare them with `n_rearing_any`, not `n_rearing`).
#' Both re-evaluate the bundle's own
#' habitat predicates ([fresh::frs_habitat_predicates()] over `cfg$rules`
#' and its thresholds CSV, channel-width model) on the segment, then again
#' with the gradient and the channel width each moved to the stage's
#' minimum:
#' - `NA` — captured; `no_segment` — the location attaches to no segment;
#' - `not_accessible` — the segment's `access_<sp>` is not 1 or 2;
#' - `fails_gradient` / `fails_width` / `width_null` — passes once that one
#'   value is relaxed (`width_null` when the width is NULL);
#'   `gradient_below_min` when the gradient fails by sitting below the
#'   window (a negative gradient), not above it;
#' - `fails_gradient_or_width` — either relaxation alone passes (through
#'   different branches of the rule);
#' - `fails_gradient_and_width` — passes only with both relaxed;
#' - `rule_excludes` — fails even then: edge type, waterbody or lake size;
#' - `post_predicate` — passes the predicate but is not habitat: removed by
#'   clustering (connectivity to spawning) or access gating.
#'
#' @param conn A [DBI::DBIConnection-class] object (from [lnk_db_conn()]).
#' @param aoi Character vector of watershed group codes. Each must be
#'   persisted in `schema`, with `streams_access` built (fails loud
#'   otherwise).
#' @param cfg An `lnk_config` object from [lnk_config()]: the bundle that
#'   produced `schema`. Supplies the rules and thresholds for the miss
#'   reasons. Where `<schema>.log` records a WSG's run, its `config_name`
#'   must be `cfg$name`.
#' @param loaded Named list from [lnk_load_overrides()]. Uses
#'   `observation_exclusions`, `wsg_species_presence`, `parameters_fresh`
#'   and (when present) `user_habitat_classification`.
#' @param species Character vector of model species codes (e.g.
#'   `c("CH", "BT")`). Each must name `<schema>.streams_habitat_<sp>` and
#'   `<schema>.streams_access.access_<sp>`.
#' @param schema Persist schema to score. Required: a bundle's
#'   `pipeline.schema` is not a reliable guide to which schema it built
#'   (`default` declares `fresh`, which the `bcfishpass` bundle writes).
#' @param observations Schema-qualified observations table. Default
#'   `"bcfishobs.observations"`. Needs `observation_key`, `species_code`,
#'   `watershed_group_code`, `blue_line_key`, `downstream_route_measure`,
#'   `match_type`, `activity_code`, `activity`, `life_stage`, `source`.
#' @param species_obs Named list mapping a model species to the observation
#'   species codes that count as it. Species not named map to themselves.
#'   Default pools DV records with BT (`list(BT = c("BT", "DV"))`).
#' @param match_types Character vector of `match_type` classes (first
#'   letter) to keep. Default `c("A", "B")`.
#' @param buffer_m Numeric scalar >= 0. Upstream distance within which
#'   modelled habitat still captures an observation. Default 0.
#' @param absences Optional data frame of sites sampled with the species
#'   not caught: `watershed_group_code`, `blue_line_key`,
#'   `downstream_route_measure`, `species_code` (model species). The caller
#'   locates them on the network. Rows for a species not present in the WSG
#'   are dropped. Absences are captured the same way observations are,
#'   `buffer_m` included, so the two rates stay comparable. A WSG x species
#'   with no rows in `absences` reports `NA` (not assessed), so pass only
#'   sites from the areas that were surveyed. Default `NULL`.
#'
#' @return A list of two data frames:
#'   - `summary`: one row per `watershed_group_code` x `species_code` x
#'     `stage` (`any`, `spawn`, `rear`), with `schema`, `config_name`,
#'     `buffer_m`, `overlay_applied`, `run_logged` (whether `<schema>.log`
#'     records the WSG), `n_obs` (locations on a segment), `n_unattached`,
#'     `n_accessible`, `n_inaccessible`, `n_spawning`, `n_rearing`,
#'     `n_rearing_any`, `n_habitat` (spawning or any rearing), the matching
#'     `share_*` (of `n_obs`; `NA` when `n_obs` is 0), `n_in_uhc_spawn`,
#'     `n_in_uhc_rear`, the `*_outside_uhc` counts and shares, and cost
#'     `accessible_km`, `spawning_km`, `rearing_km` from [lnk_rollup_wsg()].
#'     With `absences`, also `n_absence`, `n_absence_accessible`,
#'     `n_absence_spawning`, `n_absence_rearing` (stream) and
#'     `n_absence_rearing_any` (the same on every stage).
#'   - `observations`: one row per retained location, with its segment's
#'     `gradient`, `channel_width`, `channel_width_source`, `edge_type`,
#'     `stream_order`, `waterbody_type`, `access`, the capture flags,
#'     `in_uhc_spawn`, `in_uhc_rear`, the predicate results, and the two miss
#'     reasons.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
#'                     user = "postgres", password = "postgres")
#' cfg <- lnk_config("default")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # How many CH and BT observations in Morice sit on modelled habitat in
#' # the `default` bundle's schema, and at what cost in km?
#' v <- lnk_habitat_validate(conn, aoi = "MORR", cfg = cfg, loaded = loaded,
#'                           species = c("CH", "BT"),
#'                           schema = "fresh_default")
#' v$summary[v$summary$stage == "rear",
#'           c("species_code", "n_obs", "share_rearing_any", "rearing_km")]
#'
#' # What keeps the rearing misses out of habitat?
#' table(v$observations$miss_reason_rear, useNA = "ifany")
#' }
#'
#' @family compare
#' @seealso [lnk_rollup_wsg()], [lnk_compare_rollup()]
#' @export
# nolint start: indentation_linter
lnk_habitat_validate <- function(conn, aoi, cfg, loaded, species, schema,
                                 observations = "bcfishobs.observations",
                                 species_obs = list(BT = c("BT", "DV")),
                                 match_types = c("A", "B"),
                                 buffer_m = 0,
                                 absences = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    inherits(cfg, "lnk_config"),
    is.list(loaded),
    is.character(aoi), length(aoi) >= 1L, !anyNA(aoi),
    all(grepl("^[A-Z]{3,5}$", aoi)),
    is.character(species), length(species) >= 1L, !anyNA(species),
    # Interpolated into `streams_habitat_<sp>` / `access_<sp>`.
    all(grepl("^[A-Za-z]+$", species)),
    is.character(schema), length(schema) == 1L, !is.na(schema),
    grepl("^[a-z_][a-z0-9_]*$", schema),
    is.list(species_obs),
    length(species_obs) == 0L || !is.null(names(species_obs)),
    all(vapply(species_obs, is.character, logical(1))),
    is.character(match_types), length(match_types) >= 1L,
    all(grepl("^[A-Z]$", match_types)),
    is.numeric(buffer_m), length(buffer_m) == 1L, !is.na(buffer_m),
    buffer_m >= 0, is.finite(buffer_m),
    is.null(absences) || is.data.frame(absences)
  )
  .lnk_validate_identifier(observations, "observations table")
  for (nm in c("wsg_species_presence", "parameters_fresh")) {
    if (is.null(loaded[[nm]])) {
      stop("loaded$", nm, " is required", call. = FALSE)
    }
  }
  aoi <- unique(aoi)
  species <- unique(toupper(species))
  species_obs <- lapply(species_obs, toupper)
  names(species_obs) <- toupper(names(species_obs))

  .lnk_hv_check_schema(conn, schema, aoi, species)
  logged <- .lnk_hv_check_log(conn, schema, aoi, cfg)

  spec <- .lnk_hv_spec(loaded$wsg_species_presence, aoi, species,
                       species_obs)
  obs <- .lnk_hv_obs(conn, schema, observations, spec, loaded, species,
                     match_types, buffer_m)
  obs <- .lnk_hv_dedup(obs)
  obs <- .lnk_hv_predicates(conn, schema, obs, cfg, loaded, species)
  obs <- .lnk_hv_reasons(obs)

  cost <- do.call(rbind, lapply(aoi, function(w) {
    lnk_rollup_wsg(conn, aoi = w, species = species, schema = schema)
  }))
  names(cost)[names(cost) == "wsg"] <- "watershed_group_code"
  names(cost)[names(cost) == "species"] <- "species_code"

  abs_sum <- NULL
  if (!is.null(absences)) {
    abs_sum <- .lnk_hv_absences(conn, schema, absences, spec, aoi, species,
                                buffer_m)
  }

  summary <- .lnk_hv_summary(obs, cost, abs_sum, aoi, species)
  summary$run_logged <- summary$watershed_group_code %in% logged
  summary <- cbind(
    data.frame(
      schema = schema, config_name = cfg$name %||% NA_character_,
      buffer_m = buffer_m,
      overlay_applied = !is.null(loaded$user_habitat_classification) &&
        isTRUE(cfg$pipeline$apply_habitat_overlay %||% TRUE),
      stringsAsFactors = FALSE),
    summary)
  rownames(obs) <- NULL
  list(summary = summary, observations = obs)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Fail loud on WSGs or species the schema cannot score.
#' @noRd
.lnk_hv_check_schema <- function(conn, schema, aoi, species) {
  aoi_arr <- paste0("{", paste(aoi, collapse = ","), "}")
  have <- DBI::dbGetQuery(conn, sprintf(
    "SELECT 'streams' AS tbl, watershed_group_code
       FROM (SELECT DISTINCT watershed_group_code FROM %1$s.streams
              WHERE watershed_group_code = ANY($1)) s
     UNION ALL
     SELECT 'streams_access', watershed_group_code
       FROM (SELECT DISTINCT watershed_group_code FROM %1$s.streams_access
              WHERE watershed_group_code = ANY($1)) a", schema),
    params = list(aoi_arr))
  miss_streams <- setdiff(aoi, have$watershed_group_code[have$tbl == "streams"])
  if (length(miss_streams) > 0L) {
    stop("not persisted in ", schema, ".streams: ",
         paste(miss_streams, collapse = ", "), call. = FALSE)
  }
  miss_access <- setdiff(
    aoi, have$watershed_group_code[have$tbl == "streams_access"])
  if (length(miss_access) > 0L) {
    stop("no ", schema, ".streams_access rows for: ",
         paste(miss_access, collapse = ", "),
         " (build access with lnk_pipeline_run(mapping_code = TRUE))",
         call. = FALSE)
  }
  for (sp in species) {
    tbl <- paste0("streams_habitat_", tolower(sp))
    if (!DBI::dbExistsTable(conn, DBI::Id(schema = schema, table = tbl))) {
      stop(schema, ".", tbl, " does not exist", call. = FALSE)
    }
  }
  invisible(NULL)
}

#' WSGs whose latest logged run is recorded, after checking the config.
#'
#' A schema is scored with `cfg`'s rules, so a WSG logged as built by a
#' different config is an error. WSGs with no log row (built before the log
#' existed) are allowed and returned as unlogged.
#' @noRd
.lnk_hv_check_log <- function(conn, schema, aoi, cfg) {
  if (!DBI::dbExistsTable(conn, DBI::Id(schema = schema, table = "log"))) {
    return(character(0))
  }
  lg <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT ON (watershed_group_code)
            watershed_group_code, config_name
       FROM %s.log
      WHERE watershed_group_code = ANY($1)
      ORDER BY watershed_group_code, date_start DESC", schema),
    params = list(paste0("{", paste(aoi, collapse = ","), "}")))
  bad <- lg[!is.na(lg$config_name) & lg$config_name != cfg$name, ,
            drop = FALSE]
  if (nrow(bad) > 0L) {
    stop(schema, ".log records these WSGs as built by another config than '",
         cfg$name, "': ",
         paste(sprintf("%s (%s)", bad$watershed_group_code, bad$config_name),
               collapse = ", "),
         call. = FALSE)
  }
  lg$watershed_group_code
}

#' Admitted (WSG, model species, observation species) triples.
#'
#' An observation species counts for a model species only in WSGs where
#' the model species is present.
#' @noRd
.lnk_hv_spec <- function(presence, aoi, species, species_obs) {
  rows <- lapply(aoi, function(w) {
    row <- presence[presence$watershed_group_code == w, , drop = FALSE]
    if (nrow(row) == 0L) return(NULL)
    present <- intersect(species, .lnk_wsg_species_present(row[1, ]))
    if (length(present) == 0L) return(NULL)
    do.call(rbind, lapply(present, function(sp) {
      data.frame(watershed_group_code = w, species_code = sp,
                 obs_species = unique(species_obs[[sp]] %||% sp),
                 stringsAsFactors = FALSE)
    }))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) {
    out <- data.frame(watershed_group_code = character(0),
                      species_code = character(0),
                      obs_species = character(0), stringsAsFactors = FALSE)
  }
  out
}

#' Spawn / rear stage from bcfishobs activity and life stage.
#'
#' Spawning from activity; rearing from activity or a juvenile life stage.
#' Adult, holding, migrating and plain "observed" records carry no stage.
#' @noRd
.lnk_obs_stage <- function(activity_code, activity, life_stage) {
  act <- paste(activity_code, activity)
  list(
    is_spawn = grepl("\\bSPL\\b|\\bSPM\\b|\\bS\\b|Spawning", act),
    is_rear = grepl("\\bR\\b|\\bREA\\b|Rearing", act) |
      grepl("Fry|Parr|Juvenile", life_stage)
  )
}

#' SQL for "this flag, or the flag on habitat starting within the buffer".
#' @noRd
.lnk_hv_buffered <- function(schema, sp, flag_sql, buf) {
  sprintf(
    "(coalesce(%3$s, false) OR EXISTS (
        SELECT 1 FROM %1$s.streams s2
          JOIN %1$s.streams_habitat_%2$s h
            ON h.id_segment = s2.id_segment
           AND h.watershed_group_code = s2.watershed_group_code
         WHERE s2.blue_line_key = a.blue_line_key
           AND s2.watershed_group_code = a.watershed_group_code
           AND s2.downstream_route_measure >= a.seg_drm
           AND s2.downstream_route_measure < a.m + %4$s
           AND (%3$s)))",
    schema, sp, flag_sql, buf)
}

#' Drop a session temp table if present (a bare DROP IF EXISTS NOTICEs).
#' @noRd
.lnk_hv_drop_temp <- function(conn, name) {
  hit <- DBI::dbGetQuery(conn, "SELECT to_regclass($1) IS NOT NULL AS x",
                         params = list(paste0("pg_temp.", name)))$x
  if (isTRUE(hit)) .lnk_db_execute(conn, paste0("DROP TABLE pg_temp.", name))
  invisible(NULL)
}

#' Filter observations, attach each to its segment, and flag capture.
#' @noRd
.lnk_hv_obs <- function(conn, schema, observations, spec, loaded, species,
                        match_types, buffer_m) {
  excl <- loaded$observation_exclusions
  keys <- character(0)
  if (!is.null(excl) && nrow(excl) > 0L) {
    keys <- excl$observation_key[excl$data_error %in% c(TRUE, "t") |
                                   excl$release_exclude %in% c(TRUE, "t")]
  }
  DBI::dbWriteTable(conn, "lnk_vd_excl",
                    data.frame(observation_key = as.character(keys)),
                    temporary = TRUE, overwrite = TRUE)
  DBI::dbWriteTable(conn, "lnk_vd_spec", spec,
                    temporary = TRUE, overwrite = TRUE)
  uhc <- loaded$user_habitat_classification
  uhc <- if (is.null(uhc) || nrow(uhc) == 0L) {
    data.frame(species_code = character(0), blue_line_key = integer(0),
               downstream_route_measure = numeric(0),
               upstream_route_measure = numeric(0),
               spawning = integer(0), rearing = integer(0))
  } else {
    # Indicator 1 is confirmed habitat, the only value the overlay forces;
    # -1 / -4 are confirmed non-habitat.
    as.data.frame(uhc)[, c("species_code", "blue_line_key",
                           "downstream_route_measure",
                           "upstream_route_measure", "spawning", "rearing")]
  }
  DBI::dbWriteTable(conn, "lnk_vd_uhc", uhc, temporary = TRUE,
                    overwrite = TRUE)

  .lnk_hv_drop_temp(conn, "lnk_vd_obs")
  DBI::dbExecute(conn, sprintf(
    "CREATE TEMP TABLE lnk_vd_obs AS
     SELECT o.observation_key, sp.species_code,
            o.species_code AS obs_species,
            o.watershed_group_code, o.blue_line_key,
            o.downstream_route_measure AS m,
            left(o.match_type, 1) AS match_class,
            o.activity_code, o.activity, o.life_stage
       FROM %s o
       JOIN pg_temp.lnk_vd_spec sp
         ON sp.watershed_group_code = o.watershed_group_code
        AND sp.obs_species = o.species_code
      WHERE NOT EXISTS (SELECT 1 FROM pg_temp.lnk_vd_excl e
                         WHERE e.observation_key = o.observation_key)
        AND coalesce(o.source, '') NOT LIKE 'Releases Database%%'
        AND left(o.match_type, 1) = ANY($1)", observations),
    params = list(paste0("{", paste(match_types, collapse = ","), "}")))

  # The segment the model tests: the one STARTING within 1 m (upstream),
  # else the one containing the point. n_cand > 1 is the expected case of
  # a point just below a break.
  .lnk_hv_drop_temp(conn, "lnk_vd_att")
  .lnk_db_execute(conn, sprintf(
    "CREATE TEMP TABLE lnk_vd_att AS
     SELECT o.*, s.id_segment, s.n_cand, s.seg_drm, s.gradient,
            s.channel_width, s.channel_width_source, s.edge_type,
            s.stream_order, s.waterbody_key
       FROM pg_temp.lnk_vd_obs o
       LEFT JOIN LATERAL (
         SELECT s.id_segment, s.downstream_route_measure AS seg_drm,
                s.gradient, s.channel_width, s.channel_width_source,
                s.edge_type, s.stream_order, s.waterbody_key,
                count(*) OVER ()::int AS n_cand
           FROM %s.streams s
          WHERE s.blue_line_key = o.blue_line_key
            AND s.watershed_group_code = o.watershed_group_code
            AND (abs(s.downstream_route_measure - o.m) < 1
                 OR (s.downstream_route_measure <= o.m
                     AND o.m < s.upstream_route_measure))
          ORDER BY (abs(s.downstream_route_measure - o.m) < 1) DESC,
                   s.downstream_route_measure DESC
          LIMIT 1) s ON true", schema))

  buf <- format(buffer_m, scientific = FALSE)
  per_species <- paste(vapply(species, function(sp) {
    spl <- tolower(sp)
    sprintf(
      "SELECT a.*, wb.waterbody_type,
              x.access_%1$s AS access,
              coalesce(x.access_%1$s IN (1, 2), false) AS accessible,
              %3$s AS spawning,
              %4$s AS rearing,
              %5$s AS rearing_any,
              EXISTS (
                SELECT 1 FROM pg_temp.lnk_vd_uhc u
                 WHERE u.species_code = a.species_code
                   AND u.blue_line_key = a.blue_line_key
                   AND u.spawning = 1
                   AND a.m BETWEEN u.downstream_route_measure
                               AND u.upstream_route_measure) AS in_uhc_spawn,
              EXISTS (
                SELECT 1 FROM pg_temp.lnk_vd_uhc u
                 WHERE u.species_code = a.species_code
                   AND u.blue_line_key = a.blue_line_key
                   AND u.rearing = 1
                   AND a.m BETWEEN u.downstream_route_measure
                               AND u.upstream_route_measure) AS in_uhc_rear
         FROM pg_temp.lnk_vd_att a
         LEFT JOIN %2$s.streams_access x
           ON x.id_segment = a.id_segment
          AND x.watershed_group_code = a.watershed_group_code
         LEFT JOIN %2$s.streams_habitat_%1$s h
           ON h.id_segment = a.id_segment
          AND h.watershed_group_code = a.watershed_group_code
         LEFT JOIN whse_basemapping.fwa_waterbodies wb
           ON wb.waterbody_key = a.waterbody_key
        WHERE a.species_code = %6$s",
      spl, schema,
      .lnk_hv_buffered(schema, spl, "h.spawning", buf),
      .lnk_hv_buffered(schema, spl, "h.rearing", buf),
      .lnk_hv_buffered(schema, spl,
                       "h.rearing OR h.lake_rearing OR h.wetland_rearing",
                       buf),
      .lnk_quote_literal(sp))
  }, character(1)), collapse = "\n UNION ALL\n ")

  out <- DBI::dbGetQuery(conn, paste(per_species,
                                     "ORDER BY species_code, observation_key"))
  # A location with no segment has no habitat to test.
  none <- is.na(out$id_segment)
  out$accessible[none] <- NA
  out$spawning[none] <- NA
  out$rearing[none] <- NA
  out$rearing_any[none] <- NA
  out
}

#' One row per species x blue_line_key x metre.
#'
#' Stage flags are OR-ed across the records at a location; the first
#' record (by observation_key) supplies everything else.
#' @noRd
.lnk_hv_dedup <- function(obs) {
  st <- .lnk_obs_stage(obs$activity_code, obs$activity, obs$life_stage)
  obs$is_spawn <- st$is_spawn
  obs$is_rear <- st$is_rear
  obs$n_records <- rep(1L, nrow(obs))
  if (nrow(obs) == 0L) return(obs)
  loc <- paste(obs$species_code, obs$blue_line_key, round(obs$m))
  ord <- order(loc, obs$observation_key)
  obs <- obs[ord, , drop = FALSE]
  loc <- loc[ord]
  any_spawn <- tapply(obs$is_spawn, loc, any)
  any_rear <- tapply(obs$is_rear, loc, any)
  n_rec <- tapply(obs$observation_key, loc, length)
  sp_rec <- tapply(obs$obs_species, loc,
                   function(x) paste(sort(unique(x)), collapse = ";"))
  keep <- !duplicated(loc)
  out <- obs[keep, , drop = FALSE]
  k <- loc[keep]
  out$is_spawn <- unname(any_spawn[k])
  out$is_rear <- unname(any_rear[k])
  out$n_records <- as.integer(unname(n_rec[k]))
  out$obs_species <- unname(sp_rec[k])
  out
}

#' One species' predicate inputs, assembled as frs_habitat_classify() does.
#' @noRd
.lnk_hv_sp_params <- function(params, params_fresh, sp) {
  ps <- params[[sp]]
  fp <- params_fresh[params_fresh$species_code == sp, , drop = FALSE]
  if (is.null(ps) || nrow(fp) == 0L) {
    stop("no habitat parameters for species ", sp, " in the bundle",
         call. = FALSE)
  }
  gmin <- fp$spawn_gradient_min[1]
  list(species_code = sp,
       spawn_gradient_max = ps$spawn_gradient_max,
       spawn_gradient_min = if (is.null(gmin) || is.na(gmin)) 0 else gmin,
       params_sp = ps)
}

#' The stage minimums the predicates test against, from the same inputs.
#'
#' Spawning's gradient floor is `spawn_gradient_min` (parameters_fresh),
#' which fresh's spawn predicate uses directly; rearing's is the literal 0
#' fresh writes into the rear predicate (`c(0, rear_g[2])`). Widths are the
#' `ranges$<stage>$channel_width` minimums both predicates inherit. No
#' bundled rules.yaml sets a rule-level gradient, and the rule-level
#' `channel_width: [0, 9999]` on river polygons contains every minimum.
#' @noRd
.lnk_hv_stage_min <- function(spp) {
  rng <- spp$params_sp$ranges
  list(
    spawn = c(gradient = spp$spawn_gradient_min,
              width = rng$spawn$channel_width[1] %||% 0),
    rear = c(gradient = 0,
             width = rng$rear$channel_width[1] %||% 0))
}

#' A predicate with s.gradient and/or s.channel_width fixed to a value.
#' @noRd
.lnk_hv_relax <- function(pred, gradient = NULL, width = NULL) {
  if (!is.null(gradient)) {
    pred <- gsub("\\bs\\.gradient\\b",
                 sprintf("(%s::double precision)", format(gradient, scientific = FALSE)),
                 pred, perl = TRUE)
  }
  if (!is.null(width)) {
    pred <- gsub("\\bs\\.channel_width\\b",
                 sprintf("(%s::double precision)", format(width, scientific = FALSE)),
                 pred, perl = TRUE)
  }
  pred
}

#' Evaluate the bundle's habitat predicates on each observation's segment.
#'
#' Adds pred_<stage>, pred_<stage>_g (gradient relaxed), pred_<stage>_w
#' (width relaxed) and pred_<stage>_gw. The rear stage ORs stream, lake and
#' wetland rearing, as `rearing_any` does.
#' @noRd
.lnk_hv_predicates <- function(conn, schema, obs, cfg, loaded, species) {
  cols <- paste0("pred_", rep(c("spawn", "rear"), each = 4L),
                 c("", "_g", "_w", "_gw"))
  for (cl in cols) obs[[cl]] <- rep(NA, nrow(obs))
  obs$gradient_min_spawn <- rep(NA_real_, nrow(obs))
  obs$gradient_min_rear <- rep(NA_real_, nrow(obs))
  att <- obs[!is.na(obs$id_segment), , drop = FALSE]
  if (nrow(att) == 0L) return(obs)

  params <- fresh::frs_params(csv = .lnk_habitat_thresholds_csv(cfg),
                              rules_yaml = cfg$rules)
  seg <- unique(att[, c("species_code", "id_segment",
                        "watershed_group_code")])
  DBI::dbWriteTable(conn, "lnk_vd_seg", seg, temporary = TRUE,
                    overwrite = TRUE)

  for (sp in species) {
    mins <- .lnk_hv_stage_min(
      .lnk_hv_sp_params(params, loaded$parameters_fresh, sp))
    is_sp <- obs$species_code == sp
    obs$gradient_min_spawn[is_sp] <- mins$spawn[["gradient"]]
    obs$gradient_min_rear[is_sp] <- mins$rear[["gradient"]]
  }

  res <- lapply(species, function(sp) {
    if (!any(seg$species_code == sp)) return(NULL)
    spp <- .lnk_hv_sp_params(params, loaded$parameters_fresh, sp)
    pr <- fresh::frs_habitat_predicates(spp, model = "cw")
    mins <- .lnk_hv_stage_min(spp)
    stage_pred <- list(
      spawn = pr$spawn,
      rear = sprintf("(%s) OR (%s) OR (%s)", pr$rear, pr$lake_rear,
                     pr$wetland_rear))
    exprs <- unlist(lapply(c("spawn", "rear"), function(st) {
      g <- mins[[st]][["gradient"]]
      w <- mins[[st]][["width"]]
      p <- stage_pred[[st]]
      v <- c(p,
             .lnk_hv_relax(p, gradient = g),
             .lnk_hv_relax(p, width = w),
             .lnk_hv_relax(p, gradient = g, width = w))
      sprintf("coalesce((%s), false) AS pred_%s%s", v, st,
              c("", "_g", "_w", "_gw"))
    }))
    DBI::dbGetQuery(conn, sprintf(
      "SELECT %s AS species_code, s.id_segment, s.watershed_group_code,
              %s
         FROM %s.streams s
         JOIN pg_temp.lnk_vd_seg k
           ON k.id_segment = s.id_segment
          AND k.watershed_group_code = s.watershed_group_code
          AND k.species_code = %s",
      .lnk_quote_literal(sp), paste(exprs, collapse = ",\n              "),
      schema, .lnk_quote_literal(sp)))
  })
  res <- do.call(rbind, res)
  key_o <- paste(obs$species_code, obs$id_segment, obs$watershed_group_code)
  key_r <- paste(res$species_code, res$id_segment, res$watershed_group_code)
  i <- match(key_o, key_r)
  hit <- !is.na(obs$id_segment) & !is.na(i)
  for (cl in cols) obs[[cl]][hit] <- res[[cl]][i[hit]]
  obs
}

#' Miss reason for one stage from its capture flag and predicate results.
#' @noRd
.lnk_habitat_miss_reason <- function(captured, accessible, channel_width,
                                     p, p_g, p_w, p_gw,
                                     gradient = NA_real_,
                                     gradient_min = NA_real_) {
  below <- gradient < gradient_min
  out <- rep(NA_character_, length(captured))
  out[is.na(captured)] <- "no_segment"
  miss <- captured %in% FALSE
  set <- function(cond, why) {
    idx <- miss & is.na(out) & (cond %in% TRUE)
    out[idx] <<- why
  }
  set(!accessible, "not_accessible")
  set(p, "post_predicate")
  set(p_g & !p_w & below, "gradient_below_min")
  set(p_g & !p_w, "fails_gradient")
  set(p_w & !p_g & is.na(channel_width), "width_null")
  set(p_w & !p_g, "fails_width")
  # Either relaxation alone passes (different OR-branches of the rule).
  set(p_g & p_w, "fails_gradient_or_width")
  set(p_gw, "fails_gradient_and_width")
  set(rep(TRUE, length(out)), "rule_excludes")
  out
}

#' Add miss_reason_spawn / miss_reason_rear.
#' @noRd
.lnk_hv_reasons <- function(obs) {
  obs$miss_reason_spawn <- .lnk_habitat_miss_reason(
    obs$spawning, obs$accessible, obs$channel_width, obs$pred_spawn,
    obs$pred_spawn_g, obs$pred_spawn_w, obs$pred_spawn_gw,
    obs$gradient, obs$gradient_min_spawn)
  obs$miss_reason_rear <- .lnk_habitat_miss_reason(
    obs$rearing_any, obs$accessible, obs$channel_width, obs$pred_rear,
    obs$pred_rear_g, obs$pred_rear_w, obs$pred_rear_gw,
    obs$gradient, obs$gradient_min_rear)
  obs
}

#' Attach absence sites to their segment and count capture.
#' @noRd
.lnk_hv_absences <- function(conn, schema, absences, spec, aoi, species,
                             buffer_m) {
  cols <- c("watershed_group_code", "blue_line_key",
            "downstream_route_measure", "species_code")
  miss <- setdiff(cols, names(absences))
  if (length(miss) > 0L) {
    stop("absences is missing columns: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  a <- as.data.frame(absences)[, cols]
  a$species_code <- toupper(a$species_code)
  present <- paste(spec$watershed_group_code, spec$species_code)
  a <- a[paste(a$watershed_group_code, a$species_code) %in% present, ,
         drop = FALSE]
  DBI::dbWriteTable(conn, "lnk_vd_abs", a, temporary = TRUE,
                    overwrite = TRUE)
  buf <- format(buffer_m, scientific = FALSE)
  per_species <- paste(vapply(species, function(sp) {
    spl <- tolower(sp)
    sprintf(
      "SELECT a.watershed_group_code, a.species_code,
              a.id_segment IS NOT NULL AS attached,
              coalesce(x.access_%1$s IN (1, 2), false) AS accessible,
              %4$s AS spawning,
              %5$s AS rearing,
              %6$s AS rearing_any
         FROM (
       SELECT b.watershed_group_code, b.species_code, b.blue_line_key,
              b.downstream_route_measure AS m, s.id_segment, s.seg_drm
         FROM pg_temp.lnk_vd_abs b
         LEFT JOIN LATERAL (
           SELECT s.id_segment, s.downstream_route_measure AS seg_drm
             FROM %2$s.streams s
            WHERE s.blue_line_key = b.blue_line_key
              AND s.watershed_group_code = b.watershed_group_code
              AND (abs(s.downstream_route_measure
                       - b.downstream_route_measure) < 1
                   OR (s.downstream_route_measure <= b.downstream_route_measure
                       AND b.downstream_route_measure < s.upstream_route_measure))
            ORDER BY (abs(s.downstream_route_measure
                          - b.downstream_route_measure) < 1) DESC,
                     s.downstream_route_measure DESC
            LIMIT 1) s ON true
        WHERE b.species_code = %3$s) a
         LEFT JOIN %2$s.streams_access x
           ON x.id_segment = a.id_segment
          AND x.watershed_group_code = a.watershed_group_code
         LEFT JOIN %2$s.streams_habitat_%1$s h
           ON h.id_segment = a.id_segment
          AND h.watershed_group_code = a.watershed_group_code",
      spl, schema, .lnk_quote_literal(sp),
      .lnk_hv_buffered(schema, spl, "h.spawning", buf),
      .lnk_hv_buffered(schema, spl, "h.rearing", buf),
      .lnk_hv_buffered(schema, spl,
                       "h.rearing OR h.lake_rearing OR h.wetland_rearing",
                       buf))
  }, character(1)), collapse = "\n UNION ALL\n ")
  d <- DBI::dbGetQuery(conn, per_species)
  d <- d[d$attached, , drop = FALSE]
  grid <- expand.grid(watershed_group_code = aoi, species_code = species,
                      stringsAsFactors = FALSE)
  key_d <- factor(paste(d$watershed_group_code, d$species_code),
                  levels = paste(grid$watershed_group_code, grid$species_code))
  # A WSG x species with no absence rows was not assessed: NA, not 0.
  count_by <- function(flag) {
    n <- tapply(flag, key_d, sum)
    as.integer(ifelse(is.na(n), NA_integer_, n))
  }
  grid$n_absence <- count_by(rep(TRUE, nrow(d)))
  grid$n_absence_accessible <- count_by(d$accessible)
  grid$n_absence_spawning <- count_by(d$spawning)
  grid$n_absence_rearing <- count_by(d$rearing)
  grid$n_absence_rearing_any <- count_by(d$rearing_any)
  grid
}

#' Per WSG x species x stage capture table, joined to cost and absences.
#' @noRd
.lnk_hv_summary <- function(obs, cost, abs_sum, aoi, species) {
  stages <- c("any", "spawn", "rear")
  grid <- expand.grid(stage = stages, species_code = species,
                      watershed_group_code = aoi, stringsAsFactors = FALSE)
  grid <- grid[, c("watershed_group_code", "species_code", "stage")]
  rows <- lapply(seq_len(nrow(grid)), function(i) {
    g <- grid[i, ]
    d <- obs[obs$watershed_group_code == g$watershed_group_code &
               obs$species_code == g$species_code, , drop = FALSE]
    if (g$stage == "spawn") d <- d[d$is_spawn, , drop = FALSE]
    if (g$stage == "rear") d <- d[d$is_rear, , drop = FALSE]
    un <- is.na(d$id_segment)
    n_un <- sum(un)
    d <- d[!un, , drop = FALSE]
    n <- nrow(d)
    share <- function(k) if (n == 0L) NA_real_ else k / n
    n_acc <- sum(d$accessible)
    n_sp <- sum(d$spawning)
    n_re <- sum(d$rearing)
    n_ra <- sum(d$rearing_any)
    n_hab <- sum(d$spawning | d$rearing_any)
    data.frame(
      n_obs = n, n_unattached = n_un,
      n_accessible = n_acc, n_inaccessible = n - n_acc,
      n_spawning = n_sp, n_rearing = n_re, n_rearing_any = n_ra,
      n_habitat = n_hab,
      share_accessible = share(n_acc), share_spawning = share(n_sp),
      share_rearing = share(n_re), share_rearing_any = share(n_ra),
      share_habitat = share(n_hab),
      n_in_uhc_spawn = sum(d$in_uhc_spawn),
      n_in_uhc_rear = sum(d$in_uhc_rear),
      # The same capture with the overlay's reaches taken out: the part of
      # the score the observations did not decide by construction.
      n_obs_outside_uhc_spawn = sum(!d$in_uhc_spawn),
      n_spawning_outside_uhc = sum(d$spawning & !d$in_uhc_spawn),
      n_obs_outside_uhc_rear = sum(!d$in_uhc_rear),
      n_rearing_any_outside_uhc = sum(d$rearing_any & !d$in_uhc_rear))
  })
  out <- cbind(grid, do.call(rbind, rows))
  out$share_spawning_outside_uhc <- ifelse(
    out$n_obs_outside_uhc_spawn > 0,
    out$n_spawning_outside_uhc / out$n_obs_outside_uhc_spawn, NA_real_)
  out$share_rearing_any_outside_uhc <- ifelse(
    out$n_obs_outside_uhc_rear > 0,
    out$n_rearing_any_outside_uhc / out$n_obs_outside_uhc_rear, NA_real_)
  out <- merge(out, cost, by = c("watershed_group_code", "species_code"),
               all.x = TRUE, sort = FALSE)
  if (!is.null(abs_sum)) {
    out <- merge(out, abs_sum, by = c("watershed_group_code", "species_code"),
                 all.x = TRUE, sort = FALSE)
  }
  out <- out[order(out$watershed_group_code, out$species_code,
                   match(out$stage, stages)), , drop = FALSE]
  rownames(out) <- NULL
  out
}
# nolint end: indentation_linter
