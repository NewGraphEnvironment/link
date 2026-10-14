# Habitat export: per-config Parquet + manifest, keyed by FWA position (#308).
#
# Mirrors NewGraphEnvironment/wet#7's discharge publish: long-form rows, one
# part per FWA top-level drainage, Hive keys in the path (config, species), a
# manifest.json carrying each part's md5 and the link log rows that produced
# it. Readers go through the manifest (lnk_catalog()), and lnk_db_load() puts
# the rows in fwapg.

#' Dataset ID of the habitat segment export.
#' @noRd
.lnk_export_dataset <- function() "habitat/fwa/v1/segment"

#' The column contract of the export, in crate's schema shape.
#'
#' Kept in link (`inst/extdata/schemas/habitat_fwa_v1_segment.yaml`) until it
#' is registered in crate; the shape is crate's, so the move is a copy.
#' @return The parsed YAML.
#' @noRd
.lnk_export_spec <- function() {
  p <- system.file("extdata", "schemas", "habitat_fwa_v1_segment.yaml",
                   package = "link")
  if (!nzchar(p)) {
    stop("link's inst/extdata/schemas/habitat_fwa_v1_segment.yaml is missing",
         call. = FALSE)
  }
  yaml::read_yaml(p)
}

#' Column names and types of the export, in file order.
#' @noRd
.lnk_export_cols <- function(spec = .lnk_export_spec()) {
  cols <- spec$canonical$cols
  stats::setNames(vapply(cols, function(x) x$type, character(1)),
                  vapply(cols, function(x) x$name, character(1)))
}

#' Check a part's rows against the contract: exact names, order and types.
#'
#' A check, not a repair: a column the query returns with the wrong type is a
#' defect in the query, and coercing it here would hide that.
#' @noRd
.lnk_export_conform <- function(df, cols = .lnk_export_cols()) {
  if (!identical(names(df), names(cols))) {
    stop("export rows do not match the column contract.\n",
         "  expected: ", paste(names(cols), collapse = ", "), "\n",
         "  got:      ", paste(names(df), collapse = ", "), call. = FALSE)
  }
  is_type <- list(
    integer = is.integer, double = is.double,
    string = is.character, logical = is.logical
  )
  bad <- names(cols)[!vapply(names(cols), function(n) {
    isTRUE(is_type[[cols[[n]]]](df[[n]]))
  }, logical(1))]
  if (length(bad) > 0L) {
    stop("export columns of the wrong type: ",
         paste(sprintf("%s (want %s, got %s)", bad, cols[bad],
                       vapply(df[bad], function(x) class(x)[1], character(1))),
               collapse = "; "), call. = FALSE)
  }
  key_na <- vapply(c("blue_line_key", "downstream_route_measure",
                     "upstream_route_measure", "watershed_group_code"),
                   function(n) anyNA(df[[n]]), logical(1))
  if (any(key_na)) {
    stop("export key columns hold NA: ",
         paste(names(key_na)[key_na], collapse = ", "), call. = FALSE)
  }
  flags <- c("accessible", "spawning", "rearing", "lake_rearing",
             "wetland_rearing")
  flag_na <- vapply(flags, function(n) anyNA(df[[n]]), logical(1))
  if (any(flag_na)) {
    stop("export flags hold NA (a species with no habitat must read FALSE): ",
         paste(flags[flag_na], collapse = ", "), call. = FALSE)
  }
  invisible(df)
}

#' Drop RPostgres' `pq_*` classes so a frame writes as plain R types.
#' @noRd
.lnk_df_plain <- function(df) {
  for (n in names(df)) {
    cl <- class(df[[n]])
    if (any(startsWith(cl, "pq_"))) {
      df[[n]] <- unclass(df[[n]])
      attr(df[[n]], "class") <- setdiff(cl, cl[startsWith(cl, "pq_")])
      if (length(class(df[[n]])) == 0L || identical(class(df[[n]]), "")) {
        df[[n]] <- as.vector(df[[n]])
      }
    }
  }
  df
}

#' Threshold casts from the logged text snapshot: blank and NA read NULL.
#' @noRd
.lnk_export_num <- function(col) {
  sprintf("nullif(btrim(%s), '')::double precision", col)
}

#' The export rows of one species in one watershed group.
#'
#' One query: `streams` LEFT JOIN `streams_habitat_<sp>` on the full persist
#' key, so a group sharing an `id_segment` with another cannot fan out (#203)
#' and a species with no rows in the group reads FALSE. Discharge is the
#' subquery the run classified on, with the run's logged fill. Ratios use the
#' thresholds the run logged at its `config_hash`, so they agree with the
#' flags; where the run logged none (builds before #282), they are NA.
#'
#' @param conn DBI connection.
#' @param schema Persist schema.
#' @param wsg One watershed group code.
#' @param sp One species code.
#' @param run One row of `<schema>.log` (a list or one-row data frame) with
#'   `config_hash` and `discharge_fill`.
#' @return A data frame in the column contract's order, sorted by
#'   `blue_line_key`, `downstream_route_measure`.
#' @noRd
.lnk_export_rows <- function(conn, schema, wsg, sp, run) {
  .lnk_validate_identifier(schema, "schema")
  if (!grepl("^[A-Z]{4}$", wsg)) stop("wsg must be a 4-letter code", call. = FALSE)
  if (!grepl("^[A-Z]{2,3}$", sp)) stop("sp must be a species code", call. = FALSE)

  hab <- sprintf("%s.streams_habitat_%s", schema, tolower(sp))
  has_hab <- .lnk_table_exists(conn, hab)
  has_thr <- .lnk_table_exists(
    conn, paste0(schema, ".log_parameters_habitat_thresholds"))
  has_fresh <- .lnk_table_exists(conn, paste0(schema, ".log_parameters_fresh"))

  hash <- DBI::dbQuoteLiteral(conn, as.character(run$config_hash[[1]]))
  spq <- DBI::dbQuoteLiteral(conn, sp)
  thr_cols <- c("spawn_gradient_max", "spawn_channel_width_min",
                "spawn_mad_min", "rear_gradient_max",
                "rear_channel_width_min", "rear_mad_min")
  thr <- if (has_thr) {
    sprintf("SELECT %s FROM %s.log_parameters_habitat_thresholds
              WHERE config_hash = %s AND species_code = %s",
            paste(sprintf("%s AS %s", .lnk_export_num(thr_cols), thr_cols),
                  collapse = ", "),
            schema, hash, spq)
  } else {
    sprintf("SELECT %s",
            paste(sprintf("NULL::double precision AS %s", thr_cols),
                  collapse = ", "))
  }
  acc <- if (has_fresh) {
    sprintf("SELECT %s AS access_gradient_max FROM %s.log_parameters_fresh
              WHERE config_hash = %s AND species_code = %s",
            .lnk_export_num("access_gradient_max"), schema, hash, spq)
  } else {
    "SELECT NULL::double precision AS access_gradient_max"
  }
  flag <- function(f) {
    if (has_hab) sprintf("coalesce(h.%s, false) AS %s", f, f) else
      sprintf("false AS %s", f)
  }
  ratio <- function(num, den, as) {
    sprintf("%s / nullif(%s, 0) AS %s", num, den, as)
  }
  fill <- isTRUE(as.logical(run$discharge_fill[[1]]))

  sql <- sprintf(
    "WITH thr AS (%s), acc AS (%s)
     SELECT s.blue_line_key::integer AS blue_line_key,
            s.downstream_route_measure::double precision
              AS downstream_route_measure,
            s.upstream_route_measure::double precision
              AS upstream_route_measure,
            s.linear_feature_id::integer AS linear_feature_id,
            s.watershed_group_code::text AS watershed_group_code,
            s.stream_order::integer AS stream_order,
            s.edge_type::integer AS edge_type,
            s.length_metre::double precision AS length_metre,
            s.gradient::double precision AS gradient,
            s.channel_width::double precision AS channel_width,
            s.channel_width_source::text AS channel_width_source,
            d.mad_m3s::double precision AS mad_m3s,
            d.mad_m3s_source::text AS mad_m3s_source,
            %s, %s, %s, %s, %s,
            %s,
            %s, %s, %s,
            %s, %s, %s
       FROM %s.streams s
       %s
       LEFT JOIN %s d ON d.linear_feature_id = s.linear_feature_id
       LEFT JOIN thr ON true
       LEFT JOIN acc ON true
      WHERE s.watershed_group_code = %s
      ORDER BY s.blue_line_key, s.downstream_route_measure",
    thr, acc,
    flag("accessible"), flag("spawning"), flag("rearing"),
    flag("lake_rearing"), flag("wetland_rearing"),
    ratio("s.gradient", "acc.access_gradient_max", "accessible_ratio_gradient"),
    ratio("s.channel_width", "thr.spawn_channel_width_min", "spawning_ratio_cw"),
    ratio("d.mad_m3s", "thr.spawn_mad_min", "spawning_ratio_mad"),
    ratio("s.gradient", "thr.spawn_gradient_max", "spawning_ratio_gradient"),
    ratio("s.channel_width", "thr.rear_channel_width_min", "rearing_ratio_cw"),
    ratio("d.mad_m3s", "thr.rear_mad_min", "rearing_ratio_mad"),
    ratio("s.gradient", "thr.rear_gradient_max", "rearing_ratio_gradient"),
    schema,
    if (has_hab) {
      sprintf("LEFT JOIN %s h ON h.id_segment = s.id_segment
                AND h.watershed_group_code = s.watershed_group_code", hab)
    } else "",
    .lnk_discharge_sql(wsg = wsg, fill = fill),
    DBI::dbQuoteLiteral(conn, wsg))

  out <- .lnk_df_plain(DBI::dbGetQuery(conn, sql))
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::integer AS n FROM %s.streams
      WHERE watershed_group_code = %s",
    schema, DBI::dbQuoteLiteral(conn, wsg)))$n
  if (nrow(out) != n) {
    stop(sprintf(
      "%s %s %s: %d export rows for %d segments (a join fanned out)",
      schema, wsg, sp, nrow(out), n), call. = FALSE)
  }
  .lnk_export_conform(out)
}
