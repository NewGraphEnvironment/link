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
     ORDER BY str.geom <-> c.geom
     LIMIT 1
   ) str
   WHERE ST_Distance(str.geom, c.geom) <= 65
   ORDER BY c.dam_id, ST_Distance(str.geom, c.geom), str.linear_feature_id"
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
#' @return named list of SQL strings: `excl`, `xref`, `upd`.
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

  build <- function(key, cols, casts, coercers) {
    df <- loaded[[key]]
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
                 c("text", "integer"), list(lit, int_lit))
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
#'      CASE in [.lnk_crossings_union()]. NULL is not blocking, which is why the
#'      `cabd_additions` US placeholders never appear.
#'   2. a real `linear_feature_id` join to the FWA network.
#'   3. `blue_line_key = watershed_key` — mainstem only.
#'
#' Then keeps only dams *below the focal outlet*, via the measure-aware
#' `whse_basemapping.fwa_downstream()`.
#'
#' @return data.frame: `dam_id`, `dam_name_en`, `watershed_group_code`,
#'   `passability_status_code`.
#' @noRd
.lnk_dams_blocking_downstream <- function(conn, aoi, loaded, outlets) {
  o <- outlets[outlets$watershed_group_code == aoi, , drop = FALSE]
  if (nrow(o) == 0L) {
    stop("no outlet for watershed group '", aoi,
         "' in fresh::frs_wsg_outlets()", call. = FALSE)
  }
  v <- .lnk_dams_edit_values_sql(conn, loaded)

  sql <- sprintf(
    "WITH cabd AS (
       %1$s
     ),
     matched AS (
       %2$s
     )
     SELECT m.dam_id, m.dam_name_en, m.watershed_group_code,
            m.passability_status_code
       FROM matched m
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
      dams_expr = "(SELECT cabd_id, passability_status_code, dam_name_en,
                           height_m, owner, dam_use, operating_status,
                           ST_Transform(geom, 3005) AS geom
                      FROM cabd.dams)",
      excl_ref = v$excl, xref_ref = v$xref, upd_ref = v$upd),
    .lnk_dams_matched_sql(),
    DBI::dbQuoteLiteral(conn, aoi),
    o$blue_line_key[1], o$downstream_route_measure[1],
    DBI::dbQuoteLiteral(conn, o$wscode_ltree[1]),
    DBI::dbQuoteLiteral(conn, o$localcode_ltree[1]))

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
    stop("fwapg routine `whse_basemapping.fwa_downstream` not found — the ",
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
#' @return Invisibly, a list with `aoi`, `status`, `dams`, `wsgs_missing`,
#'   `note` and `elapsed_s`.
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
      stop("override must be a written justification, not TRUE — it is ",
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
                          wsgs_missing = character(0), note = NA_character_,
                          elapsed_s = 0)))
  }

  .lnk_require_fwa_downstream(conn)

  dams <- .lnk_dams_blocking_downstream(conn, aoi, loaded, outlets)

  # A dam in a species-less WSG is never persisted as a barrier, so demanding
  # it would be an unfixable false alarm. lnk_wsg_resolve() species-filters.
  closure <- tryCatch(
    lnk_wsg_resolve(cfg, loaded, wsgs = aoi, expand = TRUE, conn = conn),
    error = function(e) character(0))
  if (nrow(dams) > 0L && length(closure) > 0L) {
    dams <- dams[dams$watershed_group_code %in% closure, , drop = FALSE]
  }

  missing_dams <- dams
  if (nrow(dams) > 0L) {
    have <- .lnk_barriers_cabd_persisted(conn, cfg, dams$dam_id)
    missing_dams <- dams[!(dams$dam_id %in% have), , drop = FALSE]
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  wsgs_missing <- sort(unique(missing_dams$watershed_group_code))

  if (nrow(missing_dams) == 0L) {
    return(invisible(list(aoi = aoi, status = "pass", dams = dams,
                          wsgs_missing = character(0), note = NA_character_,
                          elapsed_s = elapsed)))
  }

  brief <- paste(sprintf("%s(%d)", wsgs_missing,
                         as.integer(table(missing_dams$watershed_group_code)[wsgs_missing])),
                 collapse = ", ")
  msg <- .lnk_guard_message(aoi, missing_dams, wsgs_missing, cfg, closure)

  if (!is.na(override)) {
    note <- sprintf("link#227 guard(override): %d unmodelled downstream dam(s) — %s — %s",
                    nrow(missing_dams), brief, trimws(override))
    message(msg)
    message("[guard] OVERRIDE accepted, recorded in the run log: ", trimws(override))
    return(invisible(list(aoi = aoi, status = "override", dams = missing_dams,
                          wsgs_missing = wsgs_missing, note = note,
                          elapsed_s = elapsed)))
  }

  note <- sprintf("link#227 guard(%s): %d unmodelled downstream dam(s) at open — %s",
                  on_fail, nrow(missing_dams), brief)

  if (identical(on_fail, "warn")) {
    message(msg)
    return(invisible(list(aoi = aoi, status = "warn", dams = missing_dams,
                          wsgs_missing = wsgs_missing, note = note,
                          elapsed_s = elapsed)))
  }

  stop(msg, call. = FALSE)
}


#' Build the operator-facing guard message.
#' @noRd
.lnk_guard_message <- function(aoi, dams, wsgs_missing, cfg, closure) {
  schema <- tryCatch(.lnk_table_names(cfg)$schema, error = function(e) "<persist>")
  first <- setdiff(closure, aoi)
  rows <- paste(sprintf("    %-5s %-38s %s (psc %s)",
                        dams$watershed_group_code, dams$dam_id,
                        ifelse(is.na(dams$dam_name_en) | !nzchar(dams$dam_name_en),
                               "(unnamed)", dams$dam_name_en),
                        dams$passability_status_code),
                collapse = "\n")
  paste0(
    sprintf("%s BLOCKED (link#227) — %d blocking dam(s) on %s's downstream flow path have not been modelled yet.\n\n",
            aoi, nrow(dams), aoi),
    "link computes accessibility by reading ALREADY-PERSISTED downstream barriers.\n",
    sprintf("Running %s now would mark segments accessible that are in fact dammed off, and exit 0.\n\n", aoi),
    sprintf("  persist schema : %s\n", schema),
    sprintf("  unmodelled blocking dams downstream of %s:\n%s\n", aoi, rows),
    if (length(first)) sprintf("  model these first, DS-first: %s\n",
                               paste(first, collapse = ", ")) else "",
    "\nFix — pick one:\n",
    if (length(first)) sprintf(
      paste0("  1. Model the downstream WSGs first:\n",
             "       for w in %s; do ",
             "Rscript data-raw/wsg_run_one.R $w <config>; done\n"),
      paste(first, collapse = " ")) else "",
    sprintf(paste0("  2. Model %s now and settle access after they land:\n",
                   "       Rscript data-raw/wsg_recompute_one.R %s <config>\n"),
            aoi, aoi),
    "  3. Override, if those dams are known passable / remediated / irrelevant.\n",
    "     Recorded in the run log and surfaced by lnk_log_read():\n",
    sprintf("       LNK_GUARD_DOWNSTREAM_NOTE=\"...\" Rscript data-raw/wsg_run_one.R %s <config>\n", aoi)
  )
}
