#' Create working-schema views over `<persist_schema>.barriers`
#'
#' Emits per-species + per-source views in the working schema that
#' filter the unified province-wide `<persist_schema>.barriers` table
#' (link#152). Each view exposes the bcfp-shape `<table>_id` column
#' [lnk_pipeline_access()] expects (`barriers_bt_id`, `barriers_dams_id`,
#' ...) so the existing `barriers_per_sp` + `barrier_sources`
#' consumer code paths run unchanged.
#'
#' The views point at the province-wide table — cross-WSG dnstr walks
#' resolve correctly because [fresh::frs_network_features()] walks
#' FWA topology and reads from the view (which is the unified table).
#' Fixes the PARS BT 60% defect (PARS drains through dams in PCEA /
#' UPCE WSGs) and unblocks any regional run.
#'
#' Per-species views (two per species `bt`, `ch`, `cm`, `co`, `pk`, `sk`,
#' `st`, `wct`):
#' - `<schema>.barriers_<sp>_unified` — filtered by
#'   `'<SP>' = ANY(blocks_species)` (ALL barrier families incl dams).
#'   `_unified` suffix avoids name collision with the per-WSG
#'   `<schema>.barriers_<sp>` tables that `.lnk_pipeline_prep_minimal`
#'   builds for the break-time path.
#' - `<schema>.barriers_<sp>_access` — the per-species **accessibility**
#'   set that drives `accessible` in mapping_code (link#200). Reproduces
#'   bcfp `barriers_<sp>`: NATURAL barriers only
#'   (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')` — the
#'   gradient-at-species-threshold is already encoded in `blocks_species`)
#'   MINUS the observation/habitat override (anti-join `barrier_overrides`),
#'   ∪ all `USER_DEFINITE` (override-exempt). Dams/PSCIS/modelled are
#'   excluded — they annotate token2 via the per-source views, never block
#'   access. Same feature shape (`barriers_<sp>_access_id` + ltrees + geom)
#'   so [lnk_pipeline_access()] / [fresh::frs_network_features()] consume it
#'   unchanged. See `RUNBOOK.md` §5.
#'
#' Per-source views (matching the bcfp source-typed tables consumed by
#' the `barrier_sources` arg of `lnk_pipeline_access`):
#' - `<schema>.barriers_anthropogenic_unified` — `barrier_source IN ('PSCIS','CABD','MODELLED')`.
#' - `<schema>.barriers_pscis_unified` — `barrier_source = 'PSCIS'`.
#' - `<schema>.barriers_dams_unified` — `barrier_source = 'CABD'`.
#'
#' (Remediations stay sourced from `<schema>.barriers_remediations`
#' built by [lnk_barriers_emit()] — they're consumed by the
#' `remediated_dnstr_ind` path which joins to `<schema>.crossings`
#' directly, not via the unified barriers table.)
#'
#' @param conn A DBI connection.
#' @param schema Working schema name where the views are created.
#' @param cfg An `lnk_config` object (resolves `cfg$pipeline$schema`
#'   for the underlying persist-schema reference).
#' @param species Character vector of species codes the views should
#'   cover. Default `c("BT","CH","CM","CO","PK","SK","ST","WCT")`.
#' @param barriers_table Character or `NULL`. Source barriers table the
#'   views read from. Default `NULL` → uses `<persist_schema>.barriers`
#'   from `cfg` (the original behaviour). Pass a working-schema name
#'   (e.g. `paste0(schema, ".barriers")`) to build the views over a
#'   per-WSG working table — used by [lnk_pipeline_run()]'s mapping_code
#'   phase, which runs BEFORE the per-WSG persist write so persist
#'   barriers may not yet hold current data. Tunnel-free / link-canonical
#'   either way (the underlying table has `blocks_species` from
#'   [lnk_barriers_unify()]).
#' @param recreate Logical. `FALSE` (default) emits `CREATE OR REPLACE VIEW`
#'   only. `TRUE` restores the historical `DROP VIEW IF EXISTS` +
#'   `CREATE OR REPLACE VIEW` pair — needed only when a view's **column
#'   shape** has changed, since `CREATE OR REPLACE` may not rename, retype,
#'   reorder or drop an output column. See Details for why the default
#'   changed (link#250).
#'
#' @return `invisible(conn)`. Side effect: creates or replaces two views
#'   per species (`_unified` + `_access`) + three source-typed views in
#'   `schema`.
#'
#' @details
#' Reruns are safe: each view is emitted with `CREATE OR REPLACE VIEW`, which
#' is atomic — a concurrent reader sees either the old definition or the new
#' one, never nothing.
#'
#' Until link 0.47.3 every statement was preceded by `DROP VIEW IF EXISTS`.
#' Each statement autocommits, so that pair left a real interval in which the
#' view **did not exist**, and a concurrent
#' [fresh::frs_network_features()] walk could fail with
#' `relation ... does not exist`. The DROP was belt-and-braces from the
#' function's first commit rather than a fix for anything, and the view column
#' list has not changed since, so `CREATE OR REPLACE` alone is sufficient.
#' `RUNBOOK.md` §6 records the DROP's cost in the *sequential* case as well:
#' an orphaned backend holding a lock on `barriers_bt_access` blocked every
#' later `DROP VIEW` indefinitely.
#'
#' If a future change alters a view's column shape, `CREATE OR REPLACE` will
#' fail and the error names `recreate = TRUE`. That is deliberately not an
#' automatic fallback — silently reverting to DROP + CREATE would reintroduce
#' the window at the worst moment, part-way through a parallel recompute
#' (link#250).
#'
#' The underlying `<persist_schema>.barriers` table must exist — typically
#' initialized by [lnk_persist_init()] and populated by [lnk_barriers_unify()]
#' + [lnk_pipeline_persist()] for all WSGs in the regional scope.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # ... lnk_persist_init + lnk_pipeline_* + lnk_barriers_unify +
#' #     lnk_pipeline_persist all already run for all WSGs ...
#'
#' lnk_barriers_views(conn, schema = "working_pars", cfg = cfg)
#'
#' lnk_pipeline_access(
#'   conn,
#'   segments        = "working_pars.streams",
#'   aoi             = "PARS",
#'   barriers_per_sp = setNames(
#'     paste0("working_pars.barriers_", c("bt","ch","cm","co","pk","sk","st","wct"), "_unified"),
#'     c("bt","ch","cm","co","pk","sk","st","wct")),
#'   barrier_sources = list(
#'     anthropogenic = "working_pars.barriers_anthropogenic_unified",
#'     pscis         = "working_pars.barriers_pscis_unified",
#'     dams          = "working_pars.barriers_dams_unified",
#'     remediations  = "working_pars.barriers_remediations"))
#' }
#'
#' @family barriers
#' @seealso [lnk_barriers_unify()], [lnk_pipeline_access()],
#'   [lnk_barriers_emit()]
#' @export
lnk_barriers_views <- function(conn, schema, cfg,
                               species = c("BT", "CH", "CM", "CO",
                                           "PK", "SK", "ST", "WCT"),
                               barriers_table = NULL,
                               recreate = FALSE) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    inherits(cfg, "lnk_config"),
    is.character(species), length(species) > 0L,
    is.null(barriers_table) ||
      (is.character(barriers_table) && length(barriers_table) == 1L &&
        nzchar(barriers_table)),
    is.logical(recreate), length(recreate) == 1L, !is.na(recreate)
  )

  # `barriers_table` defaults to `<persist_schema>.barriers` for the
  # existing callers (compare_wsg). Pass `paste0(schema, ".barriers")` to
  # build views over a per-WSG working barriers table — used by
  # lnk_pipeline_run's mapping_code phase, which runs BEFORE the per-WSG
  # persist write so persist.barriers may not have current data (link#187).
  tn <- .lnk_table_names(cfg)
  persist_barriers <- if (!is.null(barriers_table)) {
    barriers_table
  } else {
    paste0(tn$schema, ".barriers")
  }

  # The per-species access view (barriers_<sp>_access) anti-joins the
  # barrier-overrides skip list. Read it from the SAME schema as the
  # barriers source so persist-barriers pairs with the province-wide
  # overrides (link#200) and a working-schema barriers_table (if ever
  # passed) pairs with that schema's per-WSG overrides. link#200.
  overrides_table <- sub("\\.barriers$", ".barrier_overrides", persist_barriers)

  # Per-species views. Each view re-exposes id_barrier as
  # `barriers_<sp>_unified_id` so fresh::frs_network_features's
  # `feature_id_col = "<table>_id"` convention works unchanged.
  # `_unified` suffix avoids name collisions with the per-WSG
  # `<schema>.barriers_<sp>` tables that .lnk_pipeline_prep_minimal
  # builds for the break-time path (kept for working-schema diagnostics).
  for (sp in species) {
    sp_lower <- tolower(sp)
    sp_lit <- .lnk_quote_literal(sp)
    view_name <- paste0(schema, ".barriers_", sp_lower, "_unified")
    id_col <- paste0("barriers_", sp_lower, "_unified_id")
    sql_view <- sprintf(
      "CREATE OR REPLACE VIEW %s AS
       SELECT id_barrier AS %s,
              barrier_source, barrier_subtype, passability,
              blocks_species,
              linear_feature_id, blue_line_key, watershed_key,
              downstream_route_measure, wscode_ltree, localcode_ltree,
              watershed_group_code, geom
       FROM %s
       WHERE %s = ANY(blocks_species)",
      view_name, id_col, persist_barriers, sp_lit
    )
    .lnk_views_execute(conn, sql_view, recreate = recreate, view = view_name)

    # Per-species ACCESS view (link#200). The set that drives `accessible`
    # in mapping_code — reproduces bcfp `barriers_<sp>`: NATURAL barriers
    # only (gradient at the species threshold — already encoded in
    # blocks_species — ∪ falls ∪ subsurface) MINUS the observation/habitat
    # override, ∪ all user_definite (override-EXEMPT). Dams/PSCIS/modelled
    # are NOT here (they annotate token2 via barrier_sources, never block
    # access). Same feature shape as `_unified` (id + ltrees + geom) so
    # fresh::frs_network_features walks it unchanged. The override anti-join
    # reads province-wide `overrides_table` so a natural barrier in ANY WSG
    # a downstream walk crosses is lifted correctly. See RUNBOOK.md §5.
    access_view <- paste0(schema, ".barriers_", sp_lower, "_access")
    access_id   <- paste0("barriers_", sp_lower, "_access_id")
    sql_access <- sprintf(
      "CREATE OR REPLACE VIEW %s AS
       SELECT id_barrier AS %s,
              barrier_source, barrier_subtype, passability,
              blocks_species,
              linear_feature_id, blue_line_key, watershed_key,
              downstream_route_measure, wscode_ltree, localcode_ltree,
              watershed_group_code, geom
       FROM %s b
       WHERE %s = ANY(blocks_species)
         AND barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW', 'USER_DEFINITE')
         AND (
           barrier_source = 'USER_DEFINITE'
           OR NOT EXISTS (
             SELECT 1 FROM %s o
             WHERE o.species_code = %s
               AND o.blue_line_key = b.blue_line_key
               AND abs(o.downstream_route_measure - b.downstream_route_measure) < 1
           )
         )",
      access_view, access_id, persist_barriers, sp_lit, overrides_table, sp_lit
    )
    .lnk_views_execute(conn, sql_access, recreate = recreate, view = access_view)
  }

  # Per-source views — unified (cross-WSG) shape exposed under a
  # `_unified` suffix to avoid colliding with the per-WSG tables that
  # lnk_barriers_emit() emits (kept per the link#152 design — they
  # remain useful primitives for diagnostics).
  source_filters <- list(
    anthropogenic_unified = "barrier_source IN ('PSCIS', 'CABD', 'MODELLED_CROSSINGS')",
    pscis_unified         = "barrier_source = 'PSCIS'",
    dams_unified          = "barrier_source = 'CABD'"
  )
  for (src in names(source_filters)) {
    view_name <- paste0(schema, ".barriers_", src)
    id_col <- paste0("barriers_", src, "_id")
    sql_view <- sprintf(
      "CREATE OR REPLACE VIEW %s AS
       SELECT id_barrier AS %s,
              barrier_source, barrier_subtype, passability,
              blocks_species,
              linear_feature_id, blue_line_key, watershed_key,
              downstream_route_measure, wscode_ltree, localcode_ltree,
              watershed_group_code, geom
       FROM %s
       WHERE %s",
      view_name, id_col, persist_barriers, source_filters[[src]]
    )
    .lnk_views_execute(conn, sql_view, recreate = recreate, view = view_name)
  }

  invisible(conn)
}

#' Emit one barrier view, atomically by default
#'
#' `CREATE OR REPLACE VIEW` is atomic — a concurrent reader sees the old
#' definition or the new one, never nothing. `DROP VIEW` + `CREATE` is not:
#' each statement autocommits, so it leaves a window in which the view is
#' absent. That window is invisible in a serial run and is a defect under the
#' parallel recompute (link#250).
#'
#' `CREATE OR REPLACE` cannot rename, retype, reorder or drop an output
#' column. When that is what a caller needs, it must say so with
#' `recreate = TRUE` — we do NOT fall back automatically. An automatic
#' fallback would reintroduce the DROP window exactly when nobody is watching:
#' mid-fan-out, where the resulting `relation does not exist` in a sibling
#' surfaces as a per-WSG `[WARN]` rather than as an operator error.
#'
#' @noRd
.lnk_views_execute <- function(conn, sql, recreate, view) {
  if (isTRUE(recreate)) {
    .lnk_db_execute(conn, sprintf("DROP VIEW IF EXISTS %s", view))
    return(.lnk_db_execute(conn, sql))
  }
  tryCatch(
    .lnk_db_execute(conn, sql),
    error = function(e) {
      msg <- conditionMessage(e)
      # Postgres' three shape-change refusals. Matched on the message because
      # it does not raise a distinguishable condition class through DBI.
      shape_re <- paste0("cannot (change name of|change data type of|",
                         "drop columns from) view column")
      shape_change <- grepl(shape_re, msg)
      if (!shape_change) stop(e)
      stop("lnk_barriers_views(): the definition of ", view, " changed shape, ",
           "so CREATE OR REPLACE cannot apply it.\n",
           "  Re-run with recreate = TRUE, which drops and recreates. NOTE ",
           "that a DROP leaves an interval in which the view does not exist, ",
           "so do not do it while a parallel recompute is running (link#250).",
           "\n  Original: ", msg, call. = FALSE)
    }
  )
}
