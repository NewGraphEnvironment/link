#' Build barrier override list from evidence sources
#'
#' Processes fish observations, habitat confirmations, and control tables
#' to determine which gradient/falls barriers should be skipped during
#' access classification. Uses `fwa_upstream()` SQL in fwapg to check
#' whether evidence exists upstream of each barrier.
#'
#' This is the interpretation layer — link decides which barriers to skip
#' based on domain-specific evidence and thresholds. fresh receives the
#' output as a simple skip list via `barrier_overrides`.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param barriers Character. Schema-qualified table of barriers with
#'   columns: `blue_line_key`, `downstream_route_measure`, `wscode_ltree`,
#'   `localcode_ltree`, `label`. Typically `fresh.streams_breaks`.
#' @param observations Character or `NULL`. Schema-qualified table of fish
#'   observations with columns: `species_code`, `blue_line_key`,
#'   `downstream_route_measure`, `wscode`, `localcode`, `observation_date`.
#'   Typically `bcfishobs.observations`.
#' @param habitat Character or `NULL`. Schema-qualified table of confirmed
#'   habitat with columns: `species_code`, `blue_line_key`,
#'   `upstream_route_measure`, `habitat_ind`. Any confirmed habitat upstream
#'   of a barrier removes it (threshold = 1).
#' @param exclusions Character or `NULL`. Schema-qualified table of
#'   observation exclusions with column `fish_observation_point_id`. Flagged
#'   observations are removed before counting.
#' @param control Character or `NULL`. Schema-qualified table of barrier
#'   controls with columns: `blue_line_key`, `downstream_route_measure`,
#'   `barrier_ind`. Barriers in this table with `barrier_ind = TRUE` cannot
#'   be overridden — but only for species where
#'   `params$observation_control_apply` is TRUE. Resident species routinely
#'   inhabit reaches upstream of anadromous-blocking falls (post-glacial
#'   connectivity, no ocean-return requirement), so their observations still
#'   count unless this flag says otherwise.
#' @param params Data frame with per-species parameters. Must have columns:
#'   `species_code`, `observation_threshold`, `observation_date_min`,
#'   `observation_buffer_m`, `observation_species`. Optional column
#'   `observation_control_apply` (logical) — when TRUE, the `control` table
#'   blocks overrides for this species; when FALSE/NA/missing, the species
#'   ignores control. Bcfishpass defaults: TRUE for CH/CM/CO/PK/SK/ST,
#'   FALSE for BT/WCT. See `configs/bcfishpass/parameters_fresh.csv`.
#' @param cols_index Character vector. Column names to index on the
#'   barriers table for `fwa_upstream()` performance. Indexes are created
#'   `IF NOT EXISTS`. Default `c("blue_line_key", "wscode_ltree",
#'   "localcode_ltree")` — only columns that exist in the table are indexed.
#' @param to Character. Schema-qualified output table name.
#' @param verbose Logical. Report counts.
#'
#' @return Invisible data frame with override counts per species.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' params <- read.csv(system.file("extdata", "configs", "bcfishpass",
#'   "parameters_fresh.csv", package = "link"))
#'
#' lnk_barrier_overrides(conn,
#'   barriers = "fresh.streams_breaks",
#'   observations = "bcfishobs.observations",
#'   habitat = "working.user_habitat_classification",
#'   params = params,
#'   to = "working.barrier_overrides"
#' )
#'
#' # Pass to fresh
#' fresh::frs_habitat(conn, wsg = "ADMS",
#'   barrier_overrides = "working.barrier_overrides",
#'   ...)
#' }
#'
#' @export
lnk_barrier_overrides <- function(conn,
                                   barriers,
                                   observations = NULL,
                                   habitat = NULL,
                                   exclusions = NULL,
                                   control = NULL,
                                   params,
                                   cols_index = c("blue_line_key",
                                                  "wscode_ltree",
                                                  "localcode_ltree"),
                                   to,
                                   verbose = TRUE) {
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", to))

  # Create output table with unique constraint for ON CONFLICT
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (
      blue_line_key integer,
      downstream_route_measure double precision,
      species_code text,
      UNIQUE (blue_line_key, downstream_route_measure, species_code)
    )", to))

  # Species to process: any with observation threshold OR if habitat table provided
  has_obs_threshold <- !is.na(params$observation_threshold) &
    params$observation_threshold > 0
  species_to_process <- if (!is.null(habitat)) {
    # All species in params when habitat table is available
    params
  } else {
    params[has_obs_threshold, ]
  }

  if (nrow(species_to_process) == 0) {
    if (verbose) message("No species to process — no overrides")
    return(invisible(data.frame(species_code = character(), n_overrides = integer())))
  }

  # Index barriers table for fwa_upstream performance
  if (length(cols_index) > 0) {
    parts <- strsplit(barriers, "\\.")[[1]]
    schema <- if (length(parts) == 2) parts[1] else "public"
    tbl <- parts[length(parts)]
    existing <- DBI::dbGetQuery(conn, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_schema = '%s' AND table_name = '%s'", schema, tbl
    ))$column_name
    ltree_cols <- c("wscode_ltree", "localcode_ltree")
    for (col in cols_index) {
      if (col %in% existing) {
        idx_type <- if (col %in% ltree_cols) "USING GIST" else ""
        DBI::dbExecute(conn, sprintf(
          "CREATE INDEX IF NOT EXISTS %s_%s_idx ON %s %s (%s)",
          gsub("\\.", "_", barriers), col, barriers, idx_type, col))
      }
    }
  }

  results <- list()

  for (i in seq_len(nrow(species_to_process))) {
    sp <- species_to_process$species_code[i]
    threshold <- as.integer(species_to_process$observation_threshold[i])
    if (is.na(threshold)) threshold <- 0L
    date_min <- as.character(species_to_process$observation_date_min[i])
    if (is.na(date_min)) date_min <- "1900-01-01"
    buffer_m <- as.numeric(species_to_process$observation_buffer_m[i])
    if (is.na(buffer_m)) buffer_m <- 20
    obs_sp_str <- as.character(species_to_process$observation_species[i])
    obs_sp_list <- if (is.na(obs_sp_str)) sp else trimws(strsplit(obs_sp_str, ";")[[1]])
    obs_sp_sql <- paste0("'", obs_sp_list, "'", collapse = ", ")

    # Species-level opt-in for the control filter. bcfishpass applies control
    # only in the anadromous access models (CH/CM/CO/PK/SK, ST) — residents
    # (BT, WCT) and sub-CT species routinely live upstream of anadromous
    # barriers (post-glacial headwater connectivity, no ocean-return
    # requirement), so their observations should still override.
    ctrl_apply_col <- species_to_process$observation_control_apply[i]
    ctrl_apply <- isTRUE(as.logical(ctrl_apply_col))

    overrides_found <- 0L

    # Control table: a matching control row with barrier_ind = TRUE
    # blocks the override. `NOT EXISTS` (rather than a LEFT JOIN + filter)
    # keeps two things right in one shot — the barrier is blocked only
    # when at least one TRUE control row matches (mixed TRUE/FALSE within
    # the 1 m tolerance resolves to "blocked"), and the outer GROUP BY /
    # HAVING count(...) aggregation does not get row-multiplied by a join
    # to control. Gated per-species by `observation_control_apply`.
    ctrl_where <- ""
    ctrl_filter <- if (!is.null(control) && ctrl_apply) {
      sprintf(
        "AND NOT EXISTS (
           SELECT 1 FROM %s c
           WHERE c.blue_line_key = b.blue_line_key
             AND abs(b.downstream_route_measure - c.downstream_route_measure) < 1
             AND c.barrier_ind::boolean = true
         )",
        control)
    } else {
      ""
    }

    # --- Observation-based overrides (JOIN pattern, not correlated subquery) ---
    if (!is.null(observations) && threshold > 0) {
      excl_where <- if (!is.null(exclusions)) {
        sprintf(
          "AND o.fish_observation_point_id NOT IN (SELECT fish_observation_point_id FROM %s)",
          exclusions)
      } else {
        ""
      }

      sql <- sprintf(
        "INSERT INTO %s (blue_line_key, downstream_route_measure, species_code)
         SELECT b.blue_line_key, b.downstream_route_measure, '%s'
         FROM %s b
         INNER JOIN %s o
           ON whse_basemapping.fwa_upstream(
             b.blue_line_key, b.downstream_route_measure,
             b.wscode_ltree, b.localcode_ltree,
             o.blue_line_key, o.downstream_route_measure,
             o.wscode, o.localcode,
             false, %s)
         %s
         WHERE o.species_code IN (%s)
         AND o.observation_date >= '%s'
         %s
         %s
         GROUP BY b.blue_line_key, b.downstream_route_measure
         HAVING count(o.observation_key) >= %d
         ON CONFLICT DO NOTHING",
        to, sp,
        barriers, observations, buffer_m,
        ctrl_where,
        obs_sp_sql, date_min, excl_where, ctrl_filter,
        threshold)

      n <- DBI::dbExecute(conn, sql)
      overrides_found <- overrides_found + n
    }

    # --- Habitat confirmation overrides (any confirmed habitat upstream) ---
    if (!is.null(habitat)) {
      sql <- sprintf(
        "INSERT INTO %s (blue_line_key, downstream_route_measure, species_code)
         SELECT DISTINCT b.blue_line_key, b.downstream_route_measure, '%s'
         FROM %s b
         INNER JOIN %s h
           ON h.habitat_ind::boolean = true
           AND h.species_code IN (%s)
         INNER JOIN whse_basemapping.fwa_stream_networks_sp s
           ON s.blue_line_key = h.blue_line_key
           AND round(h.upstream_route_measure::numeric) >= round(s.downstream_route_measure::numeric)
           AND round(h.upstream_route_measure::numeric) <= round(s.upstream_route_measure::numeric)
         %s
         WHERE whse_basemapping.fwa_upstream(
           b.blue_line_key, b.downstream_route_measure,
           b.wscode_ltree, b.localcode_ltree,
           h.blue_line_key, h.upstream_route_measure,
           s.wscode_ltree, s.localcode_ltree,
           false, 200)
         %s
         ON CONFLICT DO NOTHING",
        to, sp,
        barriers, habitat, obs_sp_sql,
        ctrl_where, ctrl_filter)

      n <- DBI::dbExecute(conn, sql)
      overrides_found <- overrides_found + n
    }

    results[[length(results) + 1]] <- data.frame(
      species_code = sp, n_overrides = overrides_found,
      stringsAsFactors = FALSE)

    if (verbose) {
      message("  ", sp, ": ", overrides_found, " barriers overridden")
    }
  }

  result_df <- do.call(rbind, results)
  n_total <- DBI::dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", to))[[1]]

  if (verbose) {
    message("Total barrier overrides: ", n_total, " in ", to)
  }

  invisible(result_df)
}
