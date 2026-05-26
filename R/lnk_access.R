#' Build per-segment per-species access from schema tables (portable)
#'
#' Schema-aware portable wrapper around [lnk_pipeline_access()] — the
#' access twin of [lnk_mapping_code()]. Builds the per-species
#' `barriers_<sp>_access` + per-source views internally (via
#' [lnk_barriers_views()]) over `table_barriers`, then computes the wide
#' `streams_access` shape for `aoi` and writes it to `table_to`.
#'
#' Works against working-schema tables (mid-pipeline) or persist-schema
#' tables (ad-hoc / post-consolidate recompute) without modification — the
#' caller passes explicit `table_<role>` names. The caller passes ONE
#' `table_barriers` (the unified `barriers` table); the per-species access
#' set and the source-typed views are derived from it internally, so no
#' pre-built `barriers_per_sp` list is needed (that stays the lower-level
#' [lnk_pipeline_access()] surface).
#'
#' @section Merge (recompute) mode:
#' `merge = TRUE` is the **post-consolidate recompute** (link#205). A WSG's
#' accessibility depends on barriers *downstream*, possibly in another WSG
#' (the provincial-accumulation property, RUNBOOK.md §5); when WSGs are
#' modelled on separate hosts each sees only its own barriers, so the
#' per-host `streams_access` can be wrong cross-WSG. Once all barriers are
#' consolidated, `merge = TRUE` re-settles ONLY the cross-WSG columns
#' (`has_barriers_<sp>_dnstr`, `has_barriers_{anthropogenic,pscis,dams}_dnstr`,
#' `dam_dnstr_ind`) against the complete `table_barriers`, reusing the
#' already-persisted `streams` + `streams_habitat` — far cheaper than a full
#' [lnk_pipeline_run()] (which re-derives streams + habitat). It UPDATEs the
#' existing `table_to` rows for `aoi` and **preserves** the within-WSG columns
#' the recompute does not touch:
#' - `remediated_dnstr_ind` (and `has_barriers_remediations_dnstr`) — depend
#'   on the working-schema `crossings`/remediations, correct from the prior
#'   compute and within-WSG in practice.
#' - the observed-upstream distinction in `access_<sp>`: set to `0` when newly
#'   blocked, else kept at `2` where the prior compute had an observation, else
#'   `1`.
#'
#' `observations`/`crossings` are intentionally skipped (`NULL`): they only
#' drive the access 1-vs-2 code + `remediated_dnstr_ind` (both preserved
#' above); mapping_code's `accessible = !has_barriers_<sp>_dnstr` is
#' independent of them.
#'
#' `merge = FALSE` (default) overwrites `table_to` via
#' [lnk_pipeline_access()] — first-compute, intended for a working / scratch
#' table (it drops + recreates the target as a flat `id_segment`-keyed table,
#' so do NOT point it at a persist table; use `merge = TRUE` for persist).
#'
#' @param conn A [DBI::DBIConnection-class] to the local pipeline DB.
#' @param cfg An `lnk_config` object.
#' @param aoi Character. Watershed group code (e.g. `"PARS"`).
#' @param table_streams Character. Schema-qualified `streams` table (the
#'   segments).
#' @param table_barriers Character. Schema-qualified unified `barriers`
#'   table. The per-species `_access` + source `_unified` views are built
#'   over it internally via [lnk_barriers_views()].
#' @param table_to Character. Schema-qualified destination `streams_access`
#'   table. With `merge = TRUE` it must already exist (rows for `aoi` are
#'   UPDATEd in place).
#' @param merge Logical. `FALSE` (default) overwrites `table_to`. `TRUE`
#'   surgically UPDATEs `table_to`'s `aoi` rows (recompute; see Merge mode).
#' @param presence An `lnk_presence` object or `NULL`. Per-species presence
#'   for `aoi`; pass-through to [lnk_pipeline_access()].
#' @param species Character vector of species codes. Default `cfg$species`.
#'
#' @return `conn` invisibly.
#'
#' @family compare
#' @seealso [lnk_mapping_code()], [lnk_pipeline_access()], [lnk_barriers_views()]
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' pres <- lnk_presence(loaded$wsg_species_presence, "PARS")
#'
#' # Post-consolidate recompute against persist (cheap; cross-WSG correct):
#' lnk_access(
#'   conn, cfg, aoi = "PARS",
#'   table_streams  = "fresh.streams",
#'   table_barriers = "fresh.barriers",
#'   table_to       = "fresh.streams_access",
#'   merge          = TRUE, presence = pres)
#' lnk_mapping_code(
#'   conn,
#'   table_access  = "fresh.streams_access",
#'   table_habitat = "fresh.streams_habitat_long_vw",
#'   table_streams = "fresh.streams",
#'   aoi           = "PARS",
#'   table_to      = "fresh.streams_mapping_code",
#'   presence      = pres)
#' }
#'
#' @export
lnk_access <- function(conn, cfg, aoi, table_streams, table_barriers,
                       table_to, merge = FALSE, presence = NULL,
                       species = NULL) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    inherits(cfg, "lnk_config"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.character(table_streams),  length(table_streams)  == 1L, nzchar(table_streams),
    is.character(table_barriers), length(table_barriers) == 1L, nzchar(table_barriers),
    is.character(table_to), length(table_to) == 1L, nzchar(table_to),
    is.logical(merge), length(merge) == 1L,
    is.null(species) || is.character(species)
  )

  species <- if (is.null(species)) cfg$species else species
  if (is.null(species) || length(species) == 0L) {
    stop("species is empty (pass `species` or set cfg$species)", call. = FALSE)
  }
  sp_set <- tolower(species)

  # The barrier views live in the same schema as table_barriers (so they
  # read it + the sibling barrier_overrides). Derive it from the qualified name.
  view_schema <- sub("\\.[^.]+$", "", table_barriers)

  # 1. Per-species `_access` + per-source `_unified` views over table_barriers.
  lnk_barriers_views(conn, schema = view_schema, cfg = cfg,
                     species = toupper(sp_set), barriers_table = table_barriers)

  barriers_per_sp <- stats::setNames(
    as.list(paste0(view_schema, ".barriers_", sp_set, "_access")), sp_set)
  barrier_sources <- list(
    anthropogenic = paste0(view_schema, ".barriers_anthropogenic_unified"),
    pscis         = paste0(view_schema, ".barriers_pscis_unified"),
    dams          = paste0(view_schema, ".barriers_dams_unified"))

  # AOI-scope the segments — and as a real TABLE (with indexes + ANALYZE),
  # NOT a view. `frs_network_features` joins segments to features via
  # `whse_basemapping.fwa_downstream(...)`, which inlines into ltree-containment
  # predicates the planner can use. But the join DIRECTION matters: if the
  # planner picks the ~800k-row barriers as the outer driver instead of the
  # ~26k AOI streams, cost explodes by ~1000× (verified via EXPLAIN: 71M
  # estimated result rows). A `CREATE VIEW` over persist `streams` doesn't
  # carry the small-table row stats, so the planner mis-picks. Materialising
  # to a real table with stats fixes the direction. This mirrors the full
  # pipeline (which is fast because its `working.streams` is a real, indexed
  # table). link#205.
  streams_name <- paste0("zz_lnk_streams_", tolower(aoi))
  streams_scoped <- paste0(view_schema, ".", streams_name)
  .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", streams_scoped))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s AS SELECT * FROM %s WHERE watershed_group_code = %s",
    streams_scoped, table_streams, DBI::dbQuoteLiteral(conn, aoi)))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX ON %s (id_segment)", streams_scoped))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX ON %s USING GIST (wscode_ltree)", streams_scoped))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX ON %s USING GIST (localcode_ltree)", streams_scoped))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX ON %s (blue_line_key)", streams_scoped))
  .lnk_db_execute(conn, sprintf("ANALYZE %s", streams_scoped))
  on.exit(try(.lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", streams_scoped)),
              silent = TRUE), add = TRUE)

  # 2a. Overwrite mode: build straight into table_to (working/scratch).
  if (!isTRUE(merge)) {
    lnk_pipeline_access(conn,
      segments = streams_scoped, aoi = aoi, to = table_to,
      barriers_per_sp = barriers_per_sp, observations = NULL,
      presence = presence, barrier_sources = barrier_sources,
      crossings_table = NULL)
    return(invisible(conn))
  }

  # 2b. Merge mode: build into a scratch table, surgical UPDATE into table_to.
  scratch_name <- paste0("zz_lnk_access_scratch_", tolower(aoi))
  scratch <- paste0(view_schema, ".", scratch_name)
  on.exit(try(.lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", scratch)),
              silent = TRUE), add = TRUE)
  lnk_pipeline_access(conn,
    segments = streams_scoped, aoi = aoi, to = scratch,
    barriers_per_sp = barriers_per_sp, observations = NULL,
    presence = presence, barrier_sources = barrier_sources,
    crossings_table = NULL)

  # Recomputed cross-WSG columns (only those the build actually produced).
  scratch_cols <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = %s AND table_name = %s",
    DBI::dbQuoteString(conn, view_schema),
    DBI::dbQuoteString(conn, scratch_name)))$column_name

  flag_cols <- intersect(
    c(paste0("has_barriers_", sp_set, "_dnstr"),
      "has_barriers_anthropogenic_dnstr", "has_barriers_pscis_dnstr",
      "has_barriers_dams_dnstr", "dam_dnstr_ind"),
    scratch_cols)
  set_flags <- sprintf("%s = sc.%s", flag_cols, flag_cols)

  # access_<sp>: 0 if newly blocked, else keep prior 2 (observed), else 1.
  access_cols <- intersect(paste0("access_", sp_set), scratch_cols)
  set_access <- sprintf(
    "%s = CASE WHEN sc.%s = 0 THEN 0 WHEN t.%s = 2 THEN 2 ELSE 1 END",
    access_cols, access_cols, access_cols)

  set_clause <- paste(c(set_flags, set_access), collapse = ",\n    ")
  if (!nzchar(set_clause)) {
    stop("lnk_access(merge=TRUE): nothing to update — scratch produced no ",
         "recomputable columns for ", aoi, call. = FALSE)
  }

  # id_segment is unique within a WSG; scratch is aoi-scoped and table_to is
  # filtered to aoi, so (id_segment, wsg) keys the UPDATE. remediated_dnstr_ind
  # + has_barriers_remediations_dnstr are NOT in the SET -> preserved.
  .lnk_db_execute(conn, sprintf(
    "UPDATE %s t SET\n    %s\n  FROM %s sc\n  WHERE t.id_segment = sc.id_segment\n    AND t.watershed_group_code = %s",
    table_to, set_clause, scratch, DBI::dbQuoteLiteral(conn, aoi)))

  invisible(conn)
}
