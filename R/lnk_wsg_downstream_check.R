# Downstream-state guard (link#227).
#
# `lnk_pipeline_run()` does not compute accessibility from the focal WSG alone:
# it reads the ALREADY-PERSISTED barriers of the WSGs downstream. Run a WSG
# against an empty or partial persist schema and the access query finds no
# downstream dams, concludes nothing blocks, writes `streams_access` /
# `streams_mapping_code` marking segments accessible that are in fact dammed
# off, and exits 0 — a wrong answer indistinguishable from a right one.
#
# `data-raw/wsg_run_one.R` states the DS-first precondition in its own header
# and nothing enforced it until this guard.
#
# Two design points that are load-bearing:
#
#   * **Path, not membership.** The question is not "does a downstream watershed
#     group contain a blocking dam" but "is there a blocking dam on this WSG's
#     downstream flow path". The membership form over-fires badly — BULK's
#     closure holds 18 blocking dams across LSKE/KISP/KLUM, of which ~1 is
#     actually below its outlet. Tested with the measure-aware
#     `whse_basemapping.fwa_downstream()` from `fresh::frs_wsg_outlets()`.
#     This is complete, not merely cheaper: access walks downstream from every
#     segment, and every focal segment exits through the focal outlet, so the
#     out-of-WSG barriers reachable from ANY focal segment are exactly those
#     below the outlet.
#
#   * **Shared SQL, not a second copy.** The dam snap and its edit-CSV filters
#     are defined once, in `.lnk_dams_cabd_sql()` / `.lnk_dams_matched_sql()`
#     below, and consumed by BOTH this guard and `.lnk_pipeline_prep_dams()`.
#     A guard that flags dams the pipeline treats as passable trains operators
#     to reach for the override, and then it means nothing.


# ---------------------------------------------------------------------------
# Shared dam-snap SQL — single source of truth for prep_dams AND the guard
# ---------------------------------------------------------------------------

#' The `cabd` CTE body: apply the edit CSVs to a dam source.
#'
#' Parameterized on where the dams and the three edit tables come from, so the
#' pipeline can read its staged `<schema>.cabd_*` tables while the guard inlines
#' `(VALUES …)` subqueries and touches nothing.
#'
#' @param dams_expr SQL for the dam source, aliased `d`, exposing `cabd_id`,
#'   `passability_status_code` and a `geom` in BC Albers.
#' @param excl_ref,xref_ref,upd_ref SQL table references or `(VALUES …) AS t(…)`
#'   subqueries for exclusions / blue-line xref / passability updates.
#' @noRd
.lnk_dams_cabd_sql <- function(dams_expr, excl_ref, xref_ref, upd_ref) {
  sprintf(
    "SELECT d.cabd_id::text  AS dam_id,
            blk.blue_line_key,
            d.geom,
            d.dam_name_en, d.height_m, d.owner, d.dam_use,
            d.operating_status,
            COALESCE(u.passability_status_code,
                     d.passability_status_code) AS passability_status_code
     FROM %s d
     LEFT OUTER JOIN %s x ON d.cabd_id = x.cabd_id
     LEFT OUTER JOIN %s blk ON d.cabd_id = blk.cabd_id
     LEFT OUTER JOIN %s u ON d.cabd_id = u.cabd_id
     WHERE x.cabd_id IS NULL",
    dams_expr, excl_ref, xref_ref, upd_ref)
}


#' The `matched` CTE body: snap dams to the FWA network.
#'
#' The 65 m lateral nearest-stream snap. This is the most delicate SQL in the
#' package and the whole reason the guard shares rather than copies: a guard
#' that snapped differently would flag dams the pipeline never models.
#'
#' Reads the `cabd` CTE, so both callers must define that first.
#'
#' @noRd
.lnk_dams_matched_sql <- function() {
  "SELECT DISTINCT ON (c.dam_id)
          c.dam_id,
          str.linear_feature_id,
          str.blue_line_key,
          str.wscode_ltree,
          str.localcode_ltree,
          str.watershed_group_code,
          ST_Distance(str.geom, c.geom) AS distance_to_stream,
          ST_InterpolatePoint(str.geom, c.geom) AS downstream_route_measure,
          c.dam_name_en, c.height_m, c.owner, c.dam_use,
          c.operating_status, c.passability_status_code,
          str.geom AS line_geom
   FROM cabd c
   CROSS JOIN LATERAL (
     SELECT linear_feature_id, blue_line_key, wscode_ltree, localcode_ltree,
            watershed_group_code, geom
     FROM whse_basemapping.fwa_stream_networks_sp str
     WHERE str.localcode_ltree IS NOT NULL
       AND NOT str.wscode_ltree <@ '999'::ltree
       AND (
         (c.blue_line_key IS NULL)
         OR (c.blue_line_key = str.blue_line_key)
       )
     -- an exact tie (a dam nearest to a vertex two segments share) goes
     -- to the segment starting there, as measures resolve [downstream,
     -- upstream): not at its own upstream end, then the higher start, then
     -- the lower id (link#478; fwapg's rule on one stream)
     ORDER BY str.geom <-> c.geom,
              ST_LineLocatePoint(str.geom, c.geom) = 1,
              str.downstream_route_measure DESC,
              str.linear_feature_id
     LIMIT 1
   ) str
   WHERE ST_Distance(str.geom, c.geom) <= 65
   ORDER BY c.dam_id, ST_Distance(str.geom, c.geom), str.linear_feature_id"
}


#' The `usa` CTE body: the `cabd_additions` dam placeholders.
#'
#' bcfishpass places dams outside BC (Grand Coulee / Chief Joseph, Ross) on the
#' BC lines they block, as rows of `cabd_additions.csv`. Each is located on the
#' FWA line by its own measure, not snapped. Shared, like the two builders
#' above, so the pipeline and the guard number and filter them the same way.
#'
#' @param additions_ref SQL table reference or `(SELECT … FROM (VALUES …))`
#'   subquery exposing `csv_row` (the row's position in the CSV),
#'   `feature_type`, `name`, `barrier_ind`, `blue_line_key` and
#'   `downstream_route_measure`.
#' @param barrier Logical. `TRUE` gives each placeholder whose `barrier_ind`
#'   is true `passability_status_code` 1 (`BARRIER` in
#'   [.lnk_crossings_union()]); `FALSE` gives every placeholder NULL, which no
#'   consumer reads as a barrier. bcfishpass does the latter (`load_dams.sql`
#'   writes NULL, and `load_crossings.sql` inner-joins `cabd.dams`, which
#'   holds no placeholder), so `FALSE` is the parity behaviour. See
#'   `.lnk_cabd_additions_barriers()`.
#' @noRd
.lnk_dams_usa_sql <- function(additions_ref, barrier = FALSE) {
  stopifnot(is.logical(barrier), length(barrier) == 1L, !is.na(barrier))
  # Numbered in CSV order, as bcfp's `row_number() over()` over the loaded
  # table numbers them, but stated rather than left to the scan: the ids
  # become barrier ids when `barrier` is TRUE, and the guard looks them up
  # in the persisted barriers (link#367). The rounded range join can match a
  # measure at a segment boundary twice (617 such boundaries province-wide;
  # none under a current row), so the order ends on the segment.
  psc <- if (barrier) {
    "CASE WHEN lower(a.barrier_ind::text) IN ('t', 'true', '1')
          THEN 1 END::integer"
  } else {
    "NULL::integer"
  }
  sprintf(
    "SELECT (row_number() OVER (ORDER BY a.csv_row, s.linear_feature_id)
             + 1200000000)::text AS dam_id,
            s.linear_feature_id,
            a.blue_line_key,
            a.downstream_route_measure,
            s.wscode_ltree,
            s.localcode_ltree,
            0::double precision AS distance_to_stream,
            s.watershed_group_code,
            a.name AS dam_name_en,
            NULL::double precision AS height_m,
            NULL::text AS owner,
            NULL::text AS dam_use,
            NULL::text AS operating_status,
            %2$s AS passability_status_code,
            ((ST_Dump(ST_Force2D(
              ST_LocateAlong(s.geom, a.downstream_route_measure)
            ))).geom)::geometry(Point, 3005) AS geom
     FROM %1$s a
     INNER JOIN whse_basemapping.fwa_stream_networks_sp s
       ON a.blue_line_key = s.blue_line_key
      AND ROUND(a.downstream_route_measure::numeric)
            >= ROUND(s.downstream_route_measure::numeric)
      AND ROUND(a.downstream_route_measure::numeric)
            <  ROUND(s.upstream_route_measure::numeric)
     WHERE a.feature_type = 'dams'",
    additions_ref, psc)
}


#' `cabd_additions` with its CSV row position as `csv_row`
#'
#' The placeholders are numbered in CSV order; the pipeline stages this
#' frame and the guard inlines it, so both number from the same column.
#' Other keys pass through.
#' @noRd
.lnk_cabd_additions_rows <- function(df, key = "cabd_additions") {
  if (identical(key, "cabd_additions") && is.data.frame(df)) {
    df$csv_row <- seq_len(nrow(df))
  }
  df
}


#' Whether a bundle treats the `cabd_additions` dams as barriers
#'
#' `cfg$pipeline$cabd_additions_barriers`. Absent means `FALSE`, bcfishpass's
#' behaviour, which the `bcfishpass` bundle keeps; `default` sets it (#244,
#' link#367). Dams never block access, so it moves the `DAM` token of the
#' mapping codes below the placeholders, not accessible km.
#' @noRd
.lnk_cabd_additions_barriers <- function(cfg) {
  isTRUE(cfg$pipeline$cabd_additions_barriers)
}


#' Inline `(VALUES …)` fragments for the three edit CSVs.
#'
#' Lets the guard apply exactly the pipeline's exclusions / xref / passability
#' overrides without staging tables — the same VALUES-list pattern fresh 0.33.0
#' uses to retire `public.wsg_outlet`.
#'
#' An absent or empty CSV yields a typed single-NULL-row sentinel so the LEFT
#' JOIN shape survives (a bare `VALUES` with no rows is a syntax error, and an
#' untyped NULL makes Postgres reject the join predicate).
#'
#' @return named list of SQL strings: `excl`, `xref`, `upd`, and `add` (the
#'   `cabd_additions` rows, for `.lnk_dams_usa_sql()`).
#' @noRd
.lnk_dams_edit_values_sql <- function(conn, loaded) {
  lit <- function(x) {
    if (is.na(x) || !nzchar(as.character(x))) {
      return("NULL")
    }
    as.character(DBI::dbQuoteLiteral(conn, as.character(x)))
  }
  int_lit <- function(x) {
    x <- suppressWarnings(as.integer(x))
    if (is.na(x)) "NULL" else as.character(x)
  }
  num_lit <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    if (is.na(x)) "NULL" else format(x, digits = 15, scientific = FALSE)
  }

  build <- function(key, cols, casts, coercers) {
    df <- .lnk_cabd_additions_rows(loaded[[key]], key)
    if (is.null(df) || nrow(df) == 0L || !all(cols %in% names(df))) {
      row <- paste(sprintf("NULL::%s", casts), collapse = ", ")
      return(sprintf("(SELECT * FROM (VALUES (%s)) AS v(%s))",
                     row, paste(cols, collapse = ", ")))
    }
    rows <- vapply(seq_len(nrow(df)), function(i) {
      vals <- vapply(seq_along(cols), function(j) {
        coercers[[j]](df[[cols[j]]][i])
      }, character(1))
      paste0("(", paste(vals, collapse = ", "), ")")
    }, character(1))
    # Cast the first row so the VALUES list has determinate column types.
    first <- vapply(seq_along(cols), function(j) {
      v <- coercers[[j]](df[[cols[j]]][1L])
      sprintf("%s::%s", v, casts[j])
    }, character(1))
    rows[1] <- paste0("(", paste(first, collapse = ", "), ")")
    # Wrapped as a subquery, not a bare `(VALUES …) AS t(…)`: the caller
    # appends its own alias (x / blk / u), and two aliases is a syntax error.
    sprintf("(SELECT * FROM (VALUES %s) AS v(%s))",
            paste(rows, collapse = ", "), paste(cols, collapse = ", "))
  }

  list(
    excl = build("cabd_exclusions", "cabd_id", "text", list(lit)),
    xref = build("cabd_blkey_xref", c("cabd_id", "blue_line_key"),
                 c("text", "integer"), list(lit, int_lit)),
    upd  = build("cabd_passability_status_updates",
                 c("cabd_id", "passability_status_code"),
                 c("text", "integer"), list(lit, int_lit)),
    add  = build("cabd_additions",
                 c("csv_row", "feature_type", "name", "barrier_ind",
                   "blue_line_key", "downstream_route_measure"),
                 c("integer", "text", "text", "text", "integer",
                   "double precision"),
                 list(int_lit, lit, lit, lit, int_lit, num_lit))
  )
}


# ---------------------------------------------------------------------------
# Probe
# ---------------------------------------------------------------------------

#' Blocking dams on a WSG's downstream flow path.
#'
#' Read-only. Applies the pipeline's own snap and edit CSVs (shared builders
#' above), then the three filters that live *downstream* of
#' `.lnk_pipeline_prep_dams` and decide what actually becomes a barrier:
#'
#'   1. `passability_status_code IN (1, 2)` — the BARRIER/POTENTIAL arms of the
#'      CASE in [.lnk_crossings_union()]. NULL is not blocking, so the
#'      `cabd_additions` US placeholders appear only under a bundle that sets
#'      `pipeline: cabd_additions_barriers` (`additions = TRUE`), as they
#'      become barriers only there.
#'   2. a real `linear_feature_id` join to the FWA network.
#'   3. `blue_line_key = watershed_key` — mainstem only.
#'
#' Then keeps only dams *below the focal outlet*, via the measure-aware
#' `whse_basemapping.fwa_downstream()`.
#'
#' @return data.frame: `dam_id`, `dam_name_en`, `watershed_group_code`,
#'   `passability_status_code`.
#' @noRd
.lnk_dams_blocking_downstream <- function(conn, aoi, loaded, outlets,
                                          additions = FALSE,
                                          near_groups = NULL) {
  o <- outlets[outlets$watershed_group_code == aoi, , drop = FALSE]
  if (nrow(o) == 0L) {
    stop("no outlet for watershed group '", aoi,
         "' in fresh::frs_wsg_outlets()", call. = FALSE)
  }
  empty <- data.frame(dam_id = character(0), dam_name_en = character(0),
                      watershed_group_code = character(0),
                      passability_status_code = integer(0))
  # No downstream group can hold a candidate: the outlet reaches the sea.
  if (!is.null(near_groups) && length(near_groups) == 0L) return(empty)
  v <- .lnk_dams_edit_values_sql(conn, loaded)
  # Snap only the dams within 65 m of the downstream groups' polygons
  # (`.lnk_dams_near_groups()`); NULL snaps every dam.
  near <- if (is.null(near_groups)) {
    ""
  } else {
    sprintf(
      "WHERE EXISTS (
         SELECT 1 FROM whse_basemapping.fwa_watershed_groups_poly p
          WHERE p.watershed_group_code = ANY (%s::text[])
            AND ST_DWithin(p.geom, ST_Transform(d0.geom, 3005), 65))",
      DBI::dbQuoteLiteral(
        conn, paste0("{", paste(near_groups, collapse = ","), "}")))
  }

  sql <- sprintf(
    "WITH cabd AS (
       %1$s
     ),
     matched AS (
       %2$s
     ),
     usa AS (
       %8$s
     ),
     candidates AS (
       SELECT dam_id, dam_name_en, watershed_group_code,
              passability_status_code, linear_feature_id, blue_line_key,
              downstream_route_measure, wscode_ltree, localcode_ltree
         FROM matched
       UNION ALL
       SELECT dam_id, dam_name_en, watershed_group_code,
              passability_status_code, linear_feature_id, blue_line_key,
              downstream_route_measure, wscode_ltree, localcode_ltree
         FROM usa
     )
     SELECT m.dam_id, m.dam_name_en, m.watershed_group_code,
            m.passability_status_code
       FROM candidates m
       JOIN whse_basemapping.fwa_stream_networks_sp s
         ON s.linear_feature_id = m.linear_feature_id
      WHERE m.passability_status_code IN (1, 2)
        AND m.blue_line_key = s.watershed_key
        AND m.watershed_group_code <> %3$s
        AND whse_basemapping.fwa_downstream(
              %4$s::integer, %5$s::double precision,
              %6$s::ltree, %7$s::ltree,
              m.blue_line_key, m.downstream_route_measure,
              m.wscode_ltree, m.localcode_ltree)
      ORDER BY m.watershed_group_code, m.dam_name_en",
    .lnk_dams_cabd_sql(
      dams_expr = sprintf(
        "(SELECT cabd_id, passability_status_code, dam_name_en,
                 height_m, owner, dam_use, operating_status,
                 ST_Transform(geom, 3005) AS geom
            FROM cabd.dams d0 %s)", near),
      excl_ref = v$excl, xref_ref = v$xref, upd_ref = v$upd),
    .lnk_dams_matched_sql(),
    DBI::dbQuoteLiteral(conn, aoi),
    o$blue_line_key[1], o$downstream_route_measure[1],
    DBI::dbQuoteLiteral(conn, o$wscode_ltree[1]),
    DBI::dbQuoteLiteral(conn, o$localcode_ltree[1]),
    .lnk_dams_usa_sql(v$add, barrier = additions))

  DBI::dbGetQuery(conn, sql)
}


#' Which of these dams are already persisted as barriers?
#'
#' Dam-level, not WSG-level: [.lnk_wsg_persisted()] cannot distinguish a WSG
#' persisted with `dams = FALSE`, which would let the guard pass on a schema
#' that has the streams but not the barriers.
#'
#' @return character vector of `id_barrier` values present.
#' @noRd
.lnk_barriers_cabd_persisted <- function(conn, cfg, dam_ids) {
  if (length(dam_ids) == 0L) {
    return(character(0))
  }
  schema <- .lnk_table_names(cfg)$schema
  has <- nrow(DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = %s AND table_name = 'barriers' LIMIT 1",
    DBI::dbQuoteLiteral(conn, schema)))) > 0L
  if (!has) {
    return(character(0))
  }
  ids <- paste(vapply(dam_ids, function(x) {
    as.character(DBI::dbQuoteLiteral(conn, x))
  }, character(1)), collapse = ", ")
  res <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT id_barrier FROM %s.barriers
      WHERE barrier_source = 'CABD' AND id_barrier IN (%s)", schema, ids))
  if (nrow(res) == 0L) character(0) else as.character(res$id_barrier)
}


#' Is `fwa_downstream` available? Fail loud when it is not.
#' @noRd
.lnk_require_fwa_downstream <- function(conn) {
  n <- DBI::dbGetQuery(conn,
    "SELECT count(*) AS n FROM pg_proc p
       JOIN pg_namespace ns ON ns.oid = p.pronamespace
      WHERE ns.nspname = 'whse_basemapping' AND p.proname = 'fwa_downstream'")$n
  if (as.integer(n) == 0L) {
    stop("fwapg routine `whse_basemapping.fwa_downstream` not found \u2014 the ",
         "downstream guard cannot verify anything. Install fwapg, or set ",
         "LNK_GUARD_DOWNSTREAM=ignore deliberately.", call. = FALSE)
  }
  invisible(TRUE)
}


# ---------------------------------------------------------------------------
# The guard
# ---------------------------------------------------------------------------

#' Verify downstream state before modelling a watershed group
#'
#' link computes accessibility by reading the **already-persisted** barriers of
#' the watershed groups downstream of the focal one. Modelling a WSG before its
#' downstream neighbours writes `streams_access` / `streams_mapping_code`
#' marking segments accessible that are in fact dammed off — and exits cleanly,
#' so the wrong answer is indistinguishable from a right one.
#'
#' This checks the precondition instead of asking the operator to assert it:
#' find the blocking dams on the focal WSG's downstream flow path, and confirm
#' each is already persisted as a barrier.
#'
#' Three outcomes:
#'
#' - **pass** — no unpersisted blocking dam downstream. The common case.
#' - **fail** — there are; stop and name them (or warn, per `on_fail`).
#' - **override** — proceed on a stated assumption, which is recorded in the
#'   run log (link#127) so `lnk_log_read()` can later report that this network
#'   was built assuming those dams do not block.
#'
#' @param conn DBI connection to the modelling database.
#' @param aoi Watershed group code.
#' @param cfg An `lnk_config`; supplies the persist schema.
#' @param loaded Output of [lnk_load_overrides()]; supplies the CABD edit CSVs.
#' @param on_fail `"error"` (default), `"warn"`, or `"ignore"`. Use `"warn"`
#'   for multi-host runs where downstream groups are legitimately mid-flight on
#'   another host and a post-consolidate recompute settles access afterwards.
#' @param override Character justification. Non-empty proceeds despite failure
#'   and records the reason. A bare `TRUE` is rejected on purpose: the
#'   justification *is* the mechanism, and an override without one is the hole
#'   this is meant to close.
#' @param outlets Per-group outlet points; defaults to `fresh::frs_wsg_outlets()`.
#' A downstream group whose FWA streams this database does not hold hides
#' every dam on it, so the check refuses it as it refuses an unmodelled dam
#' and names it in `wsgs_unloaded` (link#464). Only dams within 65 m of the
#' downstream groups' polygons are snapped, which leaves the answer as it was
#' and keeps the check's cost to the path (link#461). From link 0.93.0 a
#' gradient barrier is persisted only by the group owning its segment
#' (link#386), so the check also refuses where a modelled group touching a line
#' on `aoi`'s downstream paths (the line rule, for `aoi` alone) holds no rows in
#' the schema's `barriers`, and names those groups in `wsgs_unheld`: a
#' tributary group the outlet closure leaves out can own a stretch of `aoi`'s
#' own line.
#'
#' @return Invisibly, a list with `aoi`, `status`, `dams`, `wsgs_missing`
#'   (groups holding unmodelled dams), `wsgs_unloaded` (downstream groups with
#'   no FWA streams), `wsgs_unheld` (groups on its lines holding no barrier
#'   rows, and modelled groups with no FWA streams in the database, whose
#'   lines the check cannot read), `note`, `elapsed_s` and `steps_s` (seconds per step: outlets,
#'   fwa_downstream, closure, loaded, near, line_deps, holders, fwa_absent,
#'   probe,
#'   persisted).
#' @family wsg
#' @export
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("default")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Verify before a long run.
#' lnk_wsg_downstream_check(conn, "PARS", cfg, loaded)
#'
#' # Multi-host: defer to the post-consolidate recompute, but record it.
#' lnk_wsg_downstream_check(conn, "PARS", cfg, loaded, on_fail = "warn")
#' }
lnk_wsg_downstream_check <- function(conn, aoi, cfg, loaded,
                                     on_fail = c("error", "warn", "ignore"),
                                     override = NA_character_,
                                     outlets = fresh::frs_wsg_outlets()) {
  t0 <- Sys.time()
  if (!inherits(conn, "DBIConnection")) {
    stop("conn must be a DBI connection", call. = FALSE)
  }
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty watershed group code", call. = FALSE)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())", call. = FALSE)
  }
  if (!is.list(loaded)) {
    stop("loaded must be the list from lnk_load_overrides()", call. = FALSE)
  }
  on_fail <- match.arg(on_fail)
  if (is.logical(override)) {
    if (isTRUE(override)) {
      stop("override must be a written justification, not TRUE \u2014 it is ",
           "recorded in the run log and read later by whoever inherits this ",
           "network", call. = FALSE)
    }
    override <- NA_character_
  }
  if (!is.na(override) && !nzchar(trimws(override))) {
    stop("override must be a non-empty justification", call. = FALSE)
  }

  if (identical(on_fail, "ignore")) {
    return(invisible(list(aoi = aoi, status = "pass", dams = NULL,
                          wsgs_missing = character(0),
                          wsgs_unloaded = character(0),
                          wsgs_unheld = character(0), note = NA_character_,
                          elapsed_s = 0, steps_s = numeric(0))))
  }

  # Each step's seconds go in the result (link#461), so a slow run names its
  # slow step. `outlets` is a lazy default: force it in its own step.
  steps <- numeric(0)
  step <- function(name, expr) {
    s <- proc.time()[["elapsed"]]
    v <- expr
    steps[[name]] <<- proc.time()[["elapsed"]] - s
    v
  }
  outlets <- step("outlets", outlets)
  step("fwa_downstream", .lnk_require_fwa_downstream(conn))

  # The groups the focal group drains through, from the outlets this check
  # was given (link#464). An error here refuses: an empty path would pass.
  path <- step("closure", fresh::frs_wsg_drainage(conn, aoi, outlets))
  down <- setdiff(path, aoi)
  # A dam in a species-less WSG is never persisted as a barrier, so demanding
  # it would be an unfixable false alarm.
  closure <- suppressMessages(
    lnk_wsg_resolve(cfg, loaded, wsgs = path, expand = FALSE))

  # A downstream group with no FWA streams loaded hides every dam on it: none
  # can snap, so the probe would pass (link#464).
  unloaded <- step("loaded", .lnk_wsg_fwa_unloaded(conn, down))
  near <- step("near", .lnk_dams_near_groups(conn, setdiff(down, unloaded)))

  # From 0.93.0 a gradient barrier is persisted only by the group owning its
  # segment (link#386), so the walk finds the gradient barriers on this
  # group's downstream paths only where their owners have landed. Every
  # modelled group touching a line on those paths (the line rule, for this
  # group alone) must hold barrier rows in the schema; one that holds none is
  # a group whose barriers this walk would read as open. The outlet closure
  # misses them: a tributary group can own a stretch of the focal group's line.
  # The line rule reads FWA, so on a database holding only some groups' FWA a
  # tributary group whose streams are absent is invisible to it: every
  # modelled group with no FWA streams here is named too, since this check
  # cannot tell whether it touches the lines.
  modelled <- suppressMessages(lnk_wsg_resolve(cfg, loaded, wsgs = NULL))
  deps <- step("line_deps", .lnk_wsg_line_deps(conn, aoi))
  deps <- intersect(deps, modelled)
  unheld <- step("holders", .lnk_wsg_unheld(conn, cfg, deps))
  fwa_absent <- step("fwa_absent",
                     .lnk_wsg_fwa_unloaded(conn, setdiff(modelled, c(aoi, unloaded))))
  unheld <- sort(unique(c(unheld, fwa_absent)))

  dams <- step("probe", .lnk_dams_blocking_downstream(
    conn, aoi, loaded, outlets,
    additions = .lnk_cabd_additions_barriers(cfg), near_groups = near))
  if (nrow(dams) > 0L) {
    dams <- dams[dams$watershed_group_code %in% closure, , drop = FALSE]
  }

  missing_dams <- dams
  if (nrow(dams) > 0L) {
    have <- step("persisted",
                 .lnk_barriers_cabd_persisted(conn, cfg, dams$dam_id))
    missing_dams <- dams[!(dams$dam_id %in% have), , drop = FALSE]
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  wsgs_missing <- sort(unique(missing_dams$watershed_group_code))

  if (nrow(missing_dams) == 0L && length(unloaded) == 0L &&
      length(unheld) == 0L) {
    return(invisible(list(aoi = aoi, status = "pass", dams = dams,
                          wsgs_missing = character(0),
                          wsgs_unloaded = character(0),
                          wsgs_unheld = character(0), note = NA_character_,
                          elapsed_s = elapsed, steps_s = steps)))
  }

  brief <- function(at_dams, at_groups) {
    .lnk_guard_brief(missing_dams, wsgs_missing, unloaded, at_dams, at_groups,
                     unheld = unheld)
  }
  msg <- .lnk_guard_message(aoi, missing_dams, wsgs_missing, cfg, closure,
                            unloaded = unloaded, unheld = unheld)
  out <- function(status, note) {
    invisible(list(aoi = aoi, status = status, dams = missing_dams,
                   wsgs_missing = wsgs_missing, wsgs_unloaded = unloaded,
                   wsgs_unheld = unheld,
                   note = note, elapsed_s = elapsed, steps_s = steps))
  }
  tag <- .lnk_guard_tag(unloaded, unheld, nrow(missing_dams) > 0L)

  if (!is.na(override)) {
    note <- sprintf("%s guard(override): %s \u2014 %s",
                    tag, brief("", ""), trimws(override))
    message(msg)
    message("[guard] OVERRIDE accepted, recorded in the run log: ", trimws(override))
    return(out("override", note))
  }

  note <- sprintf("%s guard(%s): %s",
                  tag, on_fail, brief(" at open", " at open"))

  if (identical(on_fail, "warn")) {
    message(msg)
    return(out("warn", note))
  }

  stop(msg, call. = FALSE)
}


#' Downstream groups with no FWA streams loaded (link#464).
#'
#' One index probe per group on `fwa_stream_networks_sp.watershed_group_code`.
#' FWA, not the persist schema: the dam snap reads FWA lines, and a group
#' downstream need not be modelled yet for the check to pass.
#' @return character vector of the codes in `wsgs` with no stream row.
#' @noRd
.lnk_wsg_fwa_unloaded <- function(conn, wsgs) {
  if (length(wsgs) == 0L) return(character(0))
  have <- DBI::dbGetQuery(conn, sprintf(
    "SELECT g.wsg FROM unnest(%s::text[]) AS g(wsg)
      WHERE EXISTS (SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
                     WHERE s.watershed_group_code = g.wsg)",
    DBI::dbQuoteLiteral(conn, paste0("{", paste(wsgs, collapse = ","), "}"))))
  setdiff(wsgs, have$wsg)
}


#' The groups whose polygons may narrow the dam snap (link#461).
#'
#' A dam the probe can report snapped to a stream of a downstream group, and a
#' group's streams lie inside its polygon, so only dams within 65 m of those
#' polygons can matter. The narrowing leaves the result as it was and makes
#' the snap's cost follow the path, not the province's 2,600 dams. Where any
#' of the polygons is absent (an fwapg without the table, or a group code
#' missing from it), `NULL` asks the probe to snap every dam, as it always did.
#' @return the group codes, `character(0)` when there are none, or `NULL`.
#' @noRd
.lnk_dams_near_groups <- function(conn, wsgs) {
  if (length(wsgs) == 0L) return(character(0))
  if (!.lnk_table_exists(conn, "whse_basemapping.fwa_watershed_groups_poly")) {
    return(NULL)
  }
  n <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(DISTINCT watershed_group_code)::integer AS n
       FROM whse_basemapping.fwa_watershed_groups_poly
      WHERE watershed_group_code = ANY (%s::text[]) AND geom IS NOT NULL",
    DBI::dbQuoteLiteral(conn, paste0("{", paste(wsgs, collapse = ","), "}"))))$n
  if (identical(as.integer(n), length(unique(wsgs)))) wsgs else NULL
}


#' The tag a guard note opens with: the issue whose condition it records.
#' @noRd
.lnk_guard_tag <- function(unloaded, unheld = character(0), dams = TRUE) {
  if (length(unloaded)) "link#464" else if (dams || !length(unheld)) "link#227" else "link#386"
}


#' The modelled groups touching a line on a group's downstream paths
#'
#' The line rule (`.lnk_wsg_deps_line()`) for one group: every other group
#' with a segment on a blue line carrying a code that is an ancestor of, or
#' equal to, one of the group's own codes. FWA only; under a second a group.
#' The sets go through `= ANY (ARRAY(...))` so each lookup uses its index: as
#' joins the planner guessed millions of ancestor codes (there are about ten
#' thousand) and scanned the table, 8 s a group.
#' FWA's unassigned `999` codes are left out, as the province-wide rule does.
#' @return Character vector of group codes.
#' @noRd
.lnk_wsg_line_deps <- function(conn, aoi) {
  DBI::dbGetQuery(conn, sprintf(
    "WITH codes AS (
       SELECT DISTINCT wscode_ltree AS ws
         FROM whse_basemapping.fwa_stream_networks_sp
        WHERE watershed_group_code = %1$s AND wscode_ltree IS NOT NULL
          AND NOT wscode_ltree ~ '999.*'::lquery),
     anc AS (SELECT DISTINCT subpath(ws, 0, i) AS a
               FROM codes, generate_series(1, nlevel(ws)) i)
     SELECT DISTINCT s.watershed_group_code::text AS w
       FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.blue_line_key = ANY (ARRAY(
              SELECT DISTINCT s2.blue_line_key
                FROM whse_basemapping.fwa_stream_networks_sp s2
               WHERE s2.wscode_ltree = ANY (ARRAY(SELECT a FROM anc))))
        AND s.watershed_group_code <> %1$s
      ORDER BY 1", DBI::dbQuoteString(conn, aoi)))$w
}


#' The groups among `wsgs` holding no rows in the persist schema's barriers
#'
#' A schema without the table holds none for any of them.
#' @noRd
.lnk_wsg_unheld <- function(conn, cfg, wsgs) {
  if (length(wsgs) == 0L) return(character(0))
  tbl <- paste0(.lnk_table_names(cfg)$schema, ".barriers")
  if (!.lnk_table_exists(conn, tbl)) return(sort(wsgs))
  have <- DBI::dbGetQuery(conn, sprintf(
    "SELECT g.w FROM unnest(%s::text[]) AS g(w)
      WHERE EXISTS (SELECT 1 FROM %s b WHERE b.watershed_group_code = g.w)",
    DBI::dbQuoteLiteral(conn, paste0("{", paste(wsgs, collapse = ","), "}")),
    tbl))$w
  sort(setdiff(wsgs, have))
}


#' One line naming what the guard found, for the run log's note.
#'
#' The dam part keeps the wording link#227's notes have always had
#' (`<n> unmodelled downstream dam(s) at open — <WSG>(<n>), ...`), so readers
#' of earlier run logs read new ones the same way.
#' @noRd
.lnk_guard_brief <- function(dams, wsgs_missing, unloaded,
                             at_dams = "", at_groups = "",
                             unheld = character(0)) {
  parts <- character(0)
  if (length(unheld)) {
    parts <- c(parts, sprintf(
      "%d group(s) on its lines holding no barrier rows%s \u2014 %s",
      length(unheld), at_groups, paste(unheld, collapse = ", ")))
  }
  if (length(unloaded)) {
    parts <- c(parts, sprintf("%d downstream group(s) with no FWA streams loaded%s \u2014 %s",
                              length(unloaded), at_groups,
                              paste(unloaded, collapse = ", ")))
  }
  if (nrow(dams) > 0L) {
    parts <- c(parts, sprintf(
      "%d unmodelled downstream dam(s)%s \u2014 %s", nrow(dams), at_dams,
      paste(sprintf("%s(%d)", wsgs_missing,
                    as.integer(table(dams$watershed_group_code)[wsgs_missing])),
            collapse = ", ")))
  }
  paste(parts, collapse = "; ")
}


#' Build the operator-facing guard message.
#' @noRd
.lnk_guard_message <- function(aoi, dams, wsgs_missing, cfg, closure,
                               unloaded = character(0),
                               unheld = character(0)) {
  if (length(unheld)) {
    held <- paste0(
      sprintf(paste0("%s BLOCKED (link#386) \u2014 %d modelled group(s) touching a line on ",
                     "%s's downstream paths hold no barrier rows in this schema, or ",
                     "have no FWA streams in this database so the lines they touch ",
                     "cannot be read: %s.\n\n"),
              aoi, length(unheld), aoi, paste(unheld, collapse = ", ")),
      "From link 0.93.0 a gradient barrier is persisted only by the group owning its\n",
      "segment, so the walk would read those groups' barriers as open.\n",
      "Model them (or load their persisted barriers from a build at 0.93.0 or later:\n",
      "lnk_downstream_files() / lnk_downstream_load()), then run again.\n",
      "Or override with a written reason (LNK_GUARD_DOWNSTREAM_NOTE=\"...\").\n")
    if (nrow(dams) == 0L && length(unloaded) == 0L) return(held)
    return(paste0(held, "\nAlso:\n",
                  .lnk_guard_message(aoi, dams, wsgs_missing, cfg, closure,
                                     unloaded = unloaded)))
  }
  if (length(unloaded)) {
    load <- paste0(
      sprintf(paste0("%s BLOCKED (link#464) \u2014 %d watershed group(s) on %s's ",
                     "downstream flow path have no FWA streams in this ",
                     "database: %s.\n\n"),
              aoi, length(unloaded), aoi, paste(unloaded, collapse = ", ")),
      "No dam on them can be found, so the check cannot say whether one blocks.\n",
      "Load their FWA streams (whse_basemapping.fwa_stream_networks_sp), then their\n",
      "persisted barriers (lnk_downstream_files() / lnk_downstream_load()), and run again.\n",
      "Or override with a written reason (LNK_GUARD_DOWNSTREAM_NOTE=\"...\").\n")
    if (nrow(dams) == 0L) return(load)
    return(paste0(load, "\nAlso:\n",
                  .lnk_guard_message(aoi, dams, wsgs_missing, cfg, closure)))
  }
  schema <- tryCatch(.lnk_table_names(cfg)$schema, error = function(e) "<persist>")
  first <- setdiff(closure, aoi)
  rows <- paste(sprintf("    %-5s %-38s %s (psc %s)",
                        dams$watershed_group_code, dams$dam_id,
                        ifelse(is.na(dams$dam_name_en) | !nzchar(dams$dam_name_en),
                               "(unnamed)", dams$dam_name_en),
                        dams$passability_status_code),
                collapse = "\n")
  paste0(
    sprintf("%s BLOCKED (link#227) \u2014 %d blocking dam(s) on %s's downstream flow path have not been modelled yet.\n\n",
            aoi, nrow(dams), aoi),
    "link computes accessibility by reading ALREADY-PERSISTED downstream barriers.\n",
    sprintf("Running %s now would mark segments accessible that are in fact dammed off, and exit 0.\n\n", aoi),
    sprintf("  persist schema : %s\n", schema),
    sprintf("  unmodelled blocking dams downstream of %s:\n%s\n", aoi, rows),
    if (length(first)) sprintf("  model these first, DS-first: %s\n",
                               paste(first, collapse = ", ")) else "",
    "\nFix \u2014 pick one:\n",
    if (length(first)) sprintf(
      paste0("  1. Model the downstream WSGs first:\n",
             "       for w in %s; do ",
             "LNK_SCHEMA=<schema> LNK_RUN_LABEL=<label> Rscript data-raw/wsg_run_one.R $w <config>; done\n"),
      paste(first, collapse = " ")) else "",
    sprintf(paste0("  2. Model %s now and settle access after they land:\n",
                   "       LNK_SCHEMA=<schema> LNK_RUN_LABEL=<label> Rscript data-raw/wsg_recompute_one.R %s <config>\n"),
            aoi, aoi),
    "  3. Override, if those dams are known passable / remediated / irrelevant.\n",
    "     Recorded in the run log and surfaced by lnk_log_read():\n",
    sprintf("       LNK_GUARD_DOWNSTREAM_NOTE=\"...\" LNK_SCHEMA=<schema> LNK_RUN_LABEL=<label> Rscript data-raw/wsg_run_one.R %s <config>\n", aoi)
  )
}
