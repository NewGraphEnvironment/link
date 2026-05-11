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
#' Per-species views:
#' - `<schema>.barriers_<sp>_unified` for each species (`bt`, `ch`, `cm`,
#'   `co`, `pk`, `sk`, `st`, `wct`) — filtered by
#'   `'<SP>' = ANY(blocks_species)`. `_unified` suffix avoids name
#'   collision with the per-WSG `<schema>.barriers_<sp>` tables that
#'   `.lnk_pipeline_prep_minimal` builds for the break-time path.
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
#'
#' @return `invisible(conn)`. Side effect: drops + recreates one view
#'   per species + three source-typed views in `schema`.
#'
#' @details
#' Views are dropped + recreated on each call (`CREATE OR REPLACE VIEW`)
#' so reruns are safe. The underlying `<persist_schema>.barriers`
#' table must exist — typically initialized by [lnk_persist_init()] and
#' populated by [lnk_barriers_unify()] + [lnk_pipeline_persist()] for
#' all WSGs in the regional scope.
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
                                           "PK", "SK", "ST", "WCT")) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    inherits(cfg, "lnk_config"),
    is.character(species), length(species) > 0L
  )

  tn <- .lnk_table_names(cfg)
  persist_barriers <- paste0(tn$schema, ".barriers")

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
    .lnk_db_execute(conn, sprintf("DROP VIEW IF EXISTS %s", view_name))
    .lnk_db_execute(conn, sql_view)
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
    .lnk_db_execute(conn, sprintf("DROP VIEW IF EXISTS %s", view_name))
    .lnk_db_execute(conn, sql_view)
  }

  invisible(conn)
}
