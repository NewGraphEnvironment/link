#' Prepare the Network and Barrier Inputs for a Pipeline Run
#'
#' Third phase of the habitat classification pipeline. Loads the
#' evidence and network data that downstream phases (`break`,
#' `classify`, `connect`) consume:
#'
#' - Falls (from the `fresh` package), user-identified definite
#'   barriers, user barriers-definite control table, and expert
#'   habitat confirmation CSVs from the config bundle
#' - Gradient barriers detected on the raw FWA network via
#'   [fresh::frs_break_find()], pruned against the control table,
#'   enriched with `wscode_ltree` and `localcode_ltree` for
#'   `fwa_upstream()` joins
#' - A natural-barriers table (gradient + falls) used by
#'   `lnk_barrier_overrides()` to compute the per-species skip list.
#'   User-definite barriers are intentionally excluded here and
#'   consumed by later phases directly — bcfishpass parity.
#' - Per-model barrier tables reduced to the minimal downstream-most
#'   set via [fresh::frs_barriers_minimal()], then unioned into
#'   `gradient_barriers_minimal` for segmentation
#' - Base stream segments (`fresh.streams`) loaded from FWA with
#'   channel width, stream order parent, GENERATED gradient / measures
#'   / length columns, and a unique `id_segment`
#'
#' Writes to (under the caller's working schema unless noted):
#'   - `<schema>.falls`, `<schema>.barriers_definite`,
#'     `<schema>.barriers_definite_control`,
#'     `<schema>.user_habitat_classification`
#'   - `<schema>.gradient_barriers_raw` (with ltree)
#'   - `<schema>.natural_barriers` (gradient + falls + opt-in subsurfaceflow)
#'   - `<schema>.barriers_subsurfaceflow` (only when subsurfaceflow opted in
#'     via `cfg$pipeline$break_order`)
#'   - `<schema>.barrier_overrides`
#'   - `<schema>.barriers_<model>` + `<schema>.barriers_<model>_min`
#'     per-model pre/post minimal reduction
#'   - `<schema>.gradient_barriers_minimal` (union of minimal positions)
#'   - `fresh.streams` (base segments — not namespaced by AOI; fresh
#'     owns its output schema)
#'   - `<schema>.dams` (only when `conn_tunnel` is supplied) — pulled
#'     from `bcfishpass.dams` filtered to AOI. Parallel reporting layer;
#'     NOT consumed by habitat classification.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param aoi Character. Watershed group code today; extends to ltree
#'   filters / sf polygons later (same AOI abstraction fresh uses).
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Carries `user_barriers_definite`, `user_barriers_definite_control`,
#'   `user_habitat_classification`, and `parameters_fresh`.
#' @param schema Character. Working schema name (must already exist —
#'   call [lnk_pipeline_setup()] first).
#' @param observations Character. Schema-qualified observations table
#'   used for building barrier overrides. Default
#'   `"bcfishobs.observations"` — matches bcfishpass's reference data
#'   on both M4 and M1 fwapg instances (see `rtj/docs/distributed-fwapg.md`).
#' @param conn_tunnel A [DBI::DBIConnection-class] object pointed at
#'   `db_newgraph` (the tunnel-DB carrying bcfp's pre-built tables).
#'   Optional. When supplied, `<schema>.dams` is populated from
#'   `bcfishpass.dams` filtered to the AOI — parallel reporting layer
#'   for downstream consumers, NOT consumed by habitat classification.
#'   When `NULL`, any existing `<schema>.dams` is dropped and the dams
#'   step is a no-op.
#'
#' @return `conn` invisibly, for pipe chaining.
#'
#' @family pipeline
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn   <- lnk_db_conn()
#' cfg    <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' schema <- "working_bulk"
#'
#' lnk_pipeline_setup(conn, schema)
#' lnk_pipeline_load(conn, "BULK", cfg, loaded, schema)
#' lnk_pipeline_prepare(conn, "BULK", cfg, loaded, schema)
#'
#' DBI::dbGetQuery(conn, sprintf(
#'   "SELECT count(*) FROM %s.gradient_barriers_minimal", schema))
#'
#' DBI::dbDisconnect(conn)
#' }
lnk_pipeline_prepare <- function(conn, aoi, cfg, loaded, schema,
                                 observations = "bcfishobs.observations",
                                 conn_tunnel = NULL) {
  .lnk_validate_identifier(schema, "schema")
  .lnk_validate_identifier(observations, "observations table")
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty string (watershed group code)",
         call. = FALSE)
  }
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.list(loaded)) {
    stop("loaded must be a named list (from lnk_load_overrides())",
         call. = FALSE)
  }

  .lnk_pipeline_prep_load_aux(conn, aoi, loaded, schema)
  .lnk_pipeline_prep_observations(conn, aoi, loaded, schema, observations)
  .lnk_pipeline_prep_gradient(conn, aoi, loaded, schema)
  .lnk_pipeline_prep_natural(conn, aoi, cfg, loaded, schema)
  .lnk_pipeline_prep_overrides(conn, loaded, schema)
  .lnk_pipeline_prep_minimal(conn, aoi, schema)
  .lnk_pipeline_prep_network(conn, aoi, schema)
  .lnk_pipeline_prep_dams(conn, conn_tunnel, aoi, schema, loaded)

  invisible(conn)
}


#' Load auxiliary data: falls, definite barriers, control, habitat confirms
#' @noRd
.lnk_pipeline_prep_load_aux <- function(conn, aoi, loaded, schema) {
  # --- Falls (from fresh) ---
  falls_path <- system.file("extdata", "falls.csv", package = "fresh")
  if (!nzchar(falls_path)) {
    stop("fresh package falls.csv not found — is fresh installed?",
         call. = FALSE)
  }
  falls_all <- utils::read.csv(falls_path, stringsAsFactors = FALSE)
  falls <- falls_all[falls_all$watershed_group_code == aoi &
                       falls_all$barrier_ind == TRUE, ]
  DBI::dbWriteTable(conn, DBI::Id(schema = schema, table = "falls"),
    falls, overwrite = TRUE)

  # --- User definite barriers ---
  definite_all <- loaded$user_barriers_definite
  if (!is.null(definite_all)) {
    definite <- definite_all[definite_all$watershed_group_code == aoi, ]
  } else {
    definite <- data.frame()
  }
  if (nrow(definite) > 0) {
    DBI::dbWriteTable(conn,
      DBI::Id(schema = schema, table = "barriers_definite"),
      definite, overwrite = TRUE)
  } else {
    # Empty but schema-valid table so downstream JOINs don't fail
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE IF EXISTS %s.barriers_definite", schema))
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s.barriers_definite (
         blue_line_key integer,
         downstream_route_measure double precision)", schema))
  }

  # --- Barriers-definite control (per-WSG, used to prune gradient barriers
  # AND to lock positions against observation-based overrides). Mirror the
  # barriers_definite pattern above — whenever the manifest declares the
  # key, ensure a schema-valid table exists even if this AOI has zero rows,
  # so downstream steps can gate on the manifest field rather than probing
  # the DB.
  ctrl_all <- loaded$user_barriers_definite_control
  if (!is.null(ctrl_all)) {
    ctrl <- ctrl_all[ctrl_all$watershed_group_code == aoi, ]
    if (nrow(ctrl) > 0) {
      DBI::dbWriteTable(conn,
        DBI::Id(schema = schema, table = "barriers_definite_control"),
        ctrl, overwrite = TRUE)
    } else {
      .lnk_db_execute(conn, sprintf(
        "DROP TABLE IF EXISTS %s.barriers_definite_control", schema))
      .lnk_db_execute(conn, sprintf(
        "CREATE TABLE %s.barriers_definite_control (
           blue_line_key integer,
           downstream_route_measure double precision,
           barrier_ind text)", schema))
    }
  }

  # --- Expert habitat confirmations (for barrier skip list) ---
  # Mirrors the `user_barriers_definite_control` pattern above — whenever
  # the manifest declares `user_habitat_classification`, write a
  # schema-valid table (populated or empty).
  # `.lnk_pipeline_prep_overrides()` gates on the manifest key directly;
  # creating an empty stub here keeps that gate safe for edge-case
  # manifests that declare a header-only CSV.
  hab_df <- loaded$user_habitat_classification
  if (!is.null(hab_df)) {
    if (nrow(hab_df) > 0) {
      DBI::dbWriteTable(conn,
        DBI::Id(schema = schema, table = "user_habitat_classification"),
        hab_df, overwrite = TRUE)
    } else {
      .lnk_db_execute(conn, sprintf(
        "DROP TABLE IF EXISTS %s.user_habitat_classification", schema))
      .lnk_db_execute(conn, sprintf(
        "CREATE TABLE %s.user_habitat_classification (
           blue_line_key integer,
           downstream_route_measure double precision,
           upstream_route_measure double precision,
           watershed_group_code text,
           species_code text,
           spawning integer,
           rearing integer)", schema))
    }
  }

  invisible(NULL)
}


#' Build per-AOI filtered observations table.
#'
#' Mirrors bcfishpass `model/01_access/sql/load_observations.sql`:
#' filters `bcfishobs.observations` by (a) AOI's species set from
#' `loaded$wsg_species_presence` (only observations of species marked
#' present in the WSG count) and (b) `loaded$observation_exclusions`
#' (rows with `data_error = TRUE` or `release_exclude = TRUE` removed,
#' keyed on `observation_key`). Result: `<schema>.observations`,
#' consumed by `prep_overrides` and `lnk_pipeline_break`'s observation
#' break-source step.
#'
#' Without this filter, link's barrier-override lift counts QA-flagged
#' observations and observations of species not present in the WSG —
#' lifting natural barriers that bcfishpass correctly retains. Surfaced
#' in TWAC BT over-credit (link#92): a 1987 ST observation upstream of
#' the outlet falls lifts the fall in link but bcfishpass excludes it
#' because TWAC has no ST in `wsg_species_presence`.
#'
#' bcfishobs records cutthroat as CT/CCT/ACT/CT/RB; when CT is in the
#' WSG's species set, all four codes are admitted (matches bcfp's
#' `species_code_remap` CTE).
#' @noRd
.lnk_pipeline_prep_observations <- function(conn, aoi, loaded, schema,
                                            observations = "bcfishobs.observations") {
  .lnk_validate_identifier(observations, "observations table")

  if (is.null(loaded$wsg_species_presence)) {
    stop("loaded$wsg_species_presence not present — required for the ",
         "per-AOI observations filter (mirrors bcfishpass parity)",
         call. = FALSE)
  }
  sp <- .lnk_pipeline_break_obs_species(loaded, aoi)

  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.observations", schema))

  if (length(sp) == 0) {
    # No species marked present — empty table mirroring source schema
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s.observations AS
       SELECT * FROM %s WHERE FALSE", schema, observations))
    return(invisible(NULL))
  }

  sp_sql <- paste0(
    vapply(sp, .lnk_quote_literal, character(1)),
    collapse = ", ")

  excl_filter <- ""
  excl_df <- loaded$observation_exclusions
  if (!is.null(excl_df) && nrow(excl_df) > 0) {
    is_excl <- excl_df$data_error %in% c(TRUE, "t") |
               excl_df$release_exclude %in% c(TRUE, "t")
    keys <- excl_df$observation_key[is_excl]
    if (length(keys) > 0) {
      keys_sql <- paste0(
        vapply(keys, .lnk_quote_literal, character(1)),
        collapse = ", ")
      excl_filter <- sprintf(
        "AND o.observation_key NOT IN (%s)", keys_sql)
    }
  }

  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.observations AS
     SELECT * FROM %s o
     WHERE o.watershed_group_code = %s
       AND o.species_code IN (%s)
       %s",
    schema, observations, .lnk_quote_literal(aoi), sp_sql, excl_filter))

  invisible(NULL)
}


#' Detect gradient barriers, prune by control, enrich with ltree
#' @noRd
.lnk_pipeline_prep_gradient <- function(conn, aoi, loaded, schema) {
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.streams_blk", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.streams_blk AS
     SELECT DISTINCT blue_line_key
     FROM whse_basemapping.fwa_stream_networks_sp
     WHERE watershed_group_code = %s
       AND edge_type != 6010",
    schema, .lnk_quote_literal(aoi)))

  fresh::frs_break_find(conn, paste0(schema, ".streams_blk"),
    attribute = "gradient",
    classes = c("1500" = 0.15, "2000" = 0.20,
                 "2500" = 0.25, "3000" = 0.30),
    to = paste0(schema, ".gradient_barriers_raw"))

  # Prune passable controls. Manifest-driven gate — the loaded entry is
  # the direct contract for whether control semantics are active.
  # Previously this probed information_schema for the table name; that
  # worked because .lnk_pipeline_prep_load_aux() writes the table exactly
  # when the manifest declares the key, but the indirection made an
  # empty-table edge case easier to miss (see #44 asymmetric-gating fix).
  if (!is.null(loaded$user_barriers_definite_control)) {
    .lnk_db_execute(conn, sprintf(
      "DELETE FROM %s.gradient_barriers_raw g
       USING %s.barriers_definite_control c
       WHERE g.blue_line_key = c.blue_line_key
         AND abs(g.downstream_route_measure - c.downstream_route_measure) < 1
         AND c.barrier_ind::boolean = false",
      schema, schema))
  }

  # Enrich with ltree (needed by fwa_upstream() joins downstream)
  .lnk_db_execute(conn, sprintf(
    "ALTER TABLE %s.gradient_barriers_raw
       ADD COLUMN IF NOT EXISTS wscode_ltree ltree,
       ADD COLUMN IF NOT EXISTS localcode_ltree ltree",
    schema))
  .lnk_db_execute(conn, sprintf(
    "UPDATE %s.gradient_barriers_raw g
     SET wscode_ltree = s.wscode_ltree, localcode_ltree = s.localcode_ltree
     FROM whse_basemapping.fwa_stream_networks_sp s
     WHERE g.blue_line_key = s.blue_line_key
       AND g.downstream_route_measure >= s.downstream_route_measure
       AND g.downstream_route_measure < s.upstream_route_measure",
    schema))

  invisible(NULL)
}


#' Build natural-barriers table (gradient + falls + opt-in subsurfaceflow)
#'
#' Mirrors bcfishpass's per-species barrier union in
#' `model/01_access/sql/model_access_bt.sql` and
#' `model_access_ch_cm_co_pk_sk.sql`: the natural-barrier set those
#' models filter through `obs_upstr` / `hab_upstr` is gradient + falls +
#' subsurfaceflow. `lnk_barrier_overrides()` consumes
#' `<schema>.natural_barriers` to compute the per-species skip list, so
#' every position that should be liftable by observations or habitat
#' must land here.
#'
#' Subsurfaceflow is opt-in: built only when `cfg$pipeline$break_order`
#' includes `"subsurfaceflow"`. The bcfishpass bundle opts in for
#' parity; the default bundle leaves it out (no
#' `<schema>.barriers_subsurfaceflow` table, no rows in
#' `natural_barriers`, no `streams_breaks` rows downstream — zero
#' behaviour). Subsurfaceflow honours `barriers_definite_control` —
#' a control row with `barrier_ind = FALSE` skips the position
#' (operator override). Source: `whse_basemapping.fwa_stream_networks_sp`
#' filtered to `edge_type IN (1410, 1425)` on main blue lines.
#'
#' `barriers_definite` is intentionally NOT unioned in here.
#' bcfishpass appends user-definite post-filter in `model_access_*.sql`,
#' so upstream observations and habitat never re-open them. link
#' mirrors this by consuming `barriers_definite` separately in
#' `lnk_pipeline_break()` (segmentation) and `lnk_pipeline_classify()`
#' (access gating).
#' @noRd
.lnk_pipeline_prep_natural <- function(conn, aoi, cfg, loaded, schema) {
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.natural_barriers", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.natural_barriers AS
     SELECT g.blue_line_key,
            round(g.downstream_route_measure) AS downstream_route_measure,
            g.label, s.wscode_ltree, s.localcode_ltree
     FROM %s.gradient_barriers_raw g
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON g.blue_line_key = s.blue_line_key
       AND g.downstream_route_measure >= s.downstream_route_measure
       AND g.downstream_route_measure < s.upstream_route_measure",
    schema, schema))
  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s.natural_barriers
     SELECT f.blue_line_key, round(f.downstream_route_measure),
            'blocked', s.wscode_ltree, s.localcode_ltree
     FROM %s.falls f
     JOIN whse_basemapping.fwa_stream_networks_sp s
       ON f.blue_line_key = s.blue_line_key
       AND f.downstream_route_measure >= s.downstream_route_measure
       AND f.downstream_route_measure < s.upstream_route_measure",
    schema, schema))

  if (!"subsurfaceflow" %in% (cfg$pipeline$break_order %||% character())) {
    return(invisible(NULL))
  }

  # Subsurfaceflow positions feed both `natural_barriers` (for the
  # per-species lift via lnk_barrier_overrides) and a standalone
  # `<schema>.barriers_subsurfaceflow` table that lnk_pipeline_break()
  # uses as a segmentation break source and lnk_pipeline_classify()
  # unions into fresh.streams_breaks.
  ctrl_join <- ""
  ctrl_filter <- ""
  if (!is.null(loaded$user_barriers_definite_control)) {
    ctrl_join <- sprintf(
      "LEFT OUTER JOIN %s.barriers_definite_control c
         ON s.blue_line_key = c.blue_line_key
         AND abs(s.downstream_route_measure - c.downstream_route_measure) < 1",
      schema)
    ctrl_filter <- "AND (c.barrier_ind IS NULL OR c.barrier_ind::boolean IS TRUE)"
  }

  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.barriers_subsurfaceflow", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.barriers_subsurfaceflow AS
     SELECT s.blue_line_key,
            round(s.downstream_route_measure) AS downstream_route_measure,
            s.wscode_ltree,
            s.localcode_ltree
     FROM whse_basemapping.fwa_stream_networks_sp s
     %s
     WHERE s.watershed_group_code = %s
       AND s.edge_type IN (1410, 1425)
       AND s.local_watershed_code IS NOT NULL
       AND s.blue_line_key = s.watershed_key
       AND s.fwa_watershed_code NOT LIKE '999%%'
       %s",
    schema, ctrl_join, .lnk_quote_literal(aoi), ctrl_filter))

  .lnk_db_execute(conn, sprintf(
    "INSERT INTO %s.natural_barriers
       (blue_line_key, downstream_route_measure, label,
        wscode_ltree, localcode_ltree)
     SELECT blue_line_key, downstream_route_measure,
            'blocked', wscode_ltree, localcode_ltree
     FROM %s.barriers_subsurfaceflow",
    schema, schema))

  invisible(NULL)
}


#' Compute barrier overrides via lnk_barrier_overrides
#' @noRd
.lnk_pipeline_prep_overrides <- function(conn, loaded, schema) {
  # Manifest-driven gate. `.lnk_pipeline_prep_load_aux` writes
  # `<schema>.user_habitat_classification` exactly when the manifest
  # declares `user_habitat_classification`, so the loaded entry is the
  # direct contract. Consistent with the
  # `user_barriers_definite_control` gate below.
  habitat_arg <- if (!is.null(loaded$user_habitat_classification)) {
    paste0(schema, ".user_habitat_classification")
  } else {
    NULL
  }

  # Manifest-driven gating. `.lnk_pipeline_prep_load_aux` writes
  # `<schema>.barriers_definite_control` exactly when this manifest key
  # is declared on the config bundle, so the loaded entry itself is the
  # direct contract for whether control is in play — no DB probe needed.
  control_arg <- if (!is.null(loaded$user_barriers_definite_control)) {
    paste0(schema, ".barriers_definite_control")
  } else {
    NULL
  }

  # Use <schema>.observations (filtered per-AOI by `prep_observations`)
  # rather than raw bcfishobs.observations. Mirrors bcfishpass's
  # bcfishpass.observations build (species-presence + exclusions
  # already applied). See link#92.
  lnk_barrier_overrides(conn,
    barriers = paste0(schema, ".natural_barriers"),
    observations = paste0(schema, ".observations"),
    habitat = habitat_arg,
    control = control_arg,
    params = loaded$parameters_fresh,
    to = paste0(schema, ".barrier_overrides"),
    verbose = FALSE)

  invisible(NULL)
}


#' Per-model non-minimal barrier reduction + union
#' @noRd
.lnk_pipeline_prep_minimal <- function(conn, aoi, schema) {
  # Per-model gradient class sets (matching bcfishpass model_access_*.sql).
  # TODO (follow-up): move into cfg$pipeline$gradient_models so variants
  # (min-spawn, channel-type-first) can swap these out.
  models <- list(
    bt              = c(2500, 3000),
    ch_cm_co_pk_sk  = c(1500, 2000, 2500, 3000),
    st              = c(2000, 2500, 3000),
    wct             = c(2000, 2500, 3000)
  )

  minimal_tbls <- character(0)
  for (model_name in names(models)) {
    classes <- models[[model_name]]
    class_filter <- paste(classes, collapse = ", ")
    model_tbl <- paste0(schema, ".barriers_", model_name)
    min_tbl <- paste0(model_tbl, "_min")

    # Build pre-minimal set: gradient (class-filtered) + falls
    .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", model_tbl))
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE %s AS
       SELECT blue_line_key, downstream_route_measure,
              wscode_ltree, localcode_ltree
       FROM %s.gradient_barriers_raw
       WHERE gradient_class IN (%s)
       UNION ALL
       SELECT f.blue_line_key, f.downstream_route_measure,
              s.wscode_ltree, s.localcode_ltree
       FROM %s.falls f
       JOIN whse_basemapping.fwa_stream_networks_sp s
         ON f.blue_line_key = s.blue_line_key
         AND f.downstream_route_measure >= s.downstream_route_measure
         AND f.downstream_route_measure < s.upstream_route_measure
       WHERE s.watershed_group_code = %s",
      model_tbl, schema, class_filter,
      schema, .lnk_quote_literal(aoi)))

    fresh::frs_barriers_minimal(conn, from = model_tbl, to = min_tbl)
    minimal_tbls <- c(minimal_tbls, min_tbl)
  }

  # Union all per-model minimal positions
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.gradient_barriers_minimal", schema))
  union_sql <- paste(sprintf(
    "SELECT DISTINCT blue_line_key, downstream_route_measure FROM %s",
    minimal_tbls), collapse = " UNION ")
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s.gradient_barriers_minimal AS %s",
    schema, union_sql))

  invisible(NULL)
}


#' Load base segments into fresh.streams with joined + generated columns
#' @noRd
.lnk_pipeline_prep_network <- function(conn, aoi, schema) {
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS fresh.streams CASCADE")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS fresh.streams_habitat CASCADE")

  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE fresh.streams AS
     SELECT *
     FROM whse_basemapping.fwa_stream_networks_sp
     WHERE watershed_group_code = %s
       AND localcode_ltree IS NOT NULL
       AND edge_type != 6010
       AND wscode_ltree <@ '999'::ltree IS FALSE",
    .lnk_quote_literal(aoi)))

  fresh::frs_col_join(conn, "fresh.streams",
    from = "whse_basemapping.fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

  fresh::frs_col_join(conn, "fresh.streams",
    from = "whse_basemapping.fwa_stream_networks_order_parent",
    cols = "stream_order_parent",
    by = "blue_line_key")

  fresh::frs_col_generate(conn, "fresh.streams")

  .lnk_db_execute(conn,
    "ALTER TABLE fresh.streams ADD COLUMN id_segment integer")
  .lnk_db_execute(conn,
    "WITH numbered AS (
       SELECT ctid, row_number() OVER
         (ORDER BY blue_line_key, downstream_route_measure) AS rn
       FROM fresh.streams
     )
     UPDATE fresh.streams s SET id_segment = numbered.rn
     FROM numbered WHERE s.ctid = numbered.ctid")
  .lnk_db_execute(conn,
    "CREATE UNIQUE INDEX ON fresh.streams (id_segment)")

  invisible(NULL)
}


#' Materialize <schema>.dams from CABD source + 4 edit CSVs
#'
#' Parallel-to-bcfp design: link consumes CABD upstream the same way
#' bcfp does (`cabd.dams` source + the 4 edit CSVs `cabd_exclusions`,
#' `cabd_blkey_xref`, `cabd_passability_status_updates`,
#' `cabd_additions`), applies its own snap + transforms, and writes
#' the result to a local `<schema>.dams` table. Mirrors
#' `bcfp/model/01_access/sql/load_dams.sql` line-for-line at the
#' SQL level.
#'
#' The dams table is NOT used by link's habitat classification —
#' bcfp's per-species access + habitat_linear SQL are dam-blind, and
#' link mirrors that. The data lives here for downstream consumers
#' (memo authors, fish-passage planners, dam-impact analyses) who
#' compose dam awareness with the habitat output.
#'
#' Source paths considered:
#'   - tunnel `cabd.*` on db_newgraph (current default — `conn_tunnel`)
#'   - public CABD download (future, link#104)
#'   - cabd in s3 fwapg dump (future rtj follow-up)
#' All three produce identical local `<schema>.dams`; only the source
#' connection differs.
#'
#' The 4 edit CSVs (`cabd_exclusions`, `cabd_blkey_xref`,
#' `cabd_passability_status_updates`, `cabd_additions`) ship in the
#' bundle overrides directory and arrive via `lnk_load_overrides()`.
#' Each is filtered to the AOI's `feature_type='dams'` rows where
#' applicable (only `cabd_additions` carries the `feature_type` column).
#'
#' Short-circuits when `conn_tunnel` is NULL — drops any existing
#' `<schema>.dams` and returns. Zero-cost opt-out.
#' @noRd
.lnk_pipeline_prep_dams <- function(conn, conn_tunnel, aoi, schema, loaded) {
  if (is.null(conn_tunnel)) {
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE IF EXISTS %s.dams", schema))
    return(invisible(NULL))
  }

  # 1. Stage the 4 edit CSVs into <schema> from `loaded`. All four are
  #    required — the load_dams.sql replication CTE references columns
  #    from each (`blk.blue_line_key`, `u.passability_status_code`,
  #    `a.feature_type`, etc.). Both shipped bundles declare them; a
  #    custom config that opts in to dam reporting must declare them too.
  cabd_keys <- c("cabd_exclusions", "cabd_blkey_xref",
                 "cabd_passability_status_updates", "cabd_additions")
  missing <- cabd_keys[!cabd_keys %in% names(loaded)]
  if (length(missing) > 0) {
    stop("conn_tunnel set but `loaded` is missing required CABD edit ",
         "CSV(s): ", paste(missing, collapse = ", "),
         ". Declare them in cfg$files or pass conn_tunnel = NULL to ",
         "skip dam ingestion.", call. = FALSE)
  }
  for (key in cabd_keys) {
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE IF EXISTS %s.%s", schema, key))
    DBI::dbWriteTable(conn, DBI::Id(schema = schema, table = key),
      loaded[[key]], overwrite = TRUE)
  }

  # 2. Pull `cabd.dams` from tunnel (raw upstream — NOT bcfp's processed output).
  cabd_dams <- DBI::dbGetQuery(conn_tunnel,
    "SELECT cabd_id, dam_name_en, height_m, owner, dam_use,
            operating_status, passability_status_code,
            ST_AsEWKB(ST_Transform(geom, 3005)) AS geom_ewkb
     FROM cabd.dams")

  # Stage cabd.dams locally so the lateral snap can run against
  # local fwa_stream_networks_sp without round-tripping the network.
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %s.cabd_dams_raw", schema))
  DBI::dbWriteTable(conn,
    DBI::Id(schema = schema, table = "cabd_dams_raw"),
    cabd_dams, overwrite = TRUE)

  # 3. Apply the load_dams.sql logic locally:
  #    - drop excluded cabd_ids
  #    - LEFT JOIN blkey_xref to override blue_line_key when set
  #    - lateral snap to fwa_stream_networks_sp within 65 m
  #    - LEFT JOIN passability_status_updates for status override
  #    - UNION ALL with cabd_additions where feature_type='dams' (US placeholders)
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE IF EXISTS %1$s.dams", schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %1$s.dams AS
     WITH cabd AS (
       SELECT d.cabd_id::text  AS dam_id,
              blk.blue_line_key,
              ST_GeomFromEWKB(d.geom_ewkb) AS geom,
              d.dam_name_en, d.height_m, d.owner, d.dam_use,
              d.operating_status,
              COALESCE(u.passability_status_code,
                       d.passability_status_code) AS passability_status_code
       FROM %1$s.cabd_dams_raw d
       LEFT OUTER JOIN %1$s.cabd_exclusions x ON d.cabd_id = x.cabd_id
       LEFT OUTER JOIN %1$s.cabd_blkey_xref blk ON d.cabd_id = blk.cabd_id
       LEFT OUTER JOIN %1$s.cabd_passability_status_updates u
         ON d.cabd_id = u.cabd_id
       WHERE x.cabd_id IS NULL
     ),
     matched AS (
       SELECT DISTINCT ON (c.dam_id)
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
       ORDER BY c.dam_id, ST_Distance(str.geom, c.geom), str.linear_feature_id
     ),
     placed AS (
       SELECT m.dam_id,
              m.linear_feature_id,
              m.blue_line_key,
              m.downstream_route_measure,
              m.wscode_ltree,
              m.localcode_ltree,
              m.distance_to_stream,
              m.watershed_group_code,
              m.dam_name_en, m.height_m, m.owner, m.dam_use,
              m.operating_status, m.passability_status_code,
              ((ST_Dump(ST_Force2D(
                ST_LocateAlong(m.line_geom, m.downstream_route_measure)
              ))).geom)::geometry(Point, 3005) AS geom
       FROM matched m
     ),
     usa AS (
       SELECT (row_number() OVER () + 1200000000)::text AS dam_id,
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
              NULL::integer AS passability_status_code,
              ((ST_Dump(ST_Force2D(
                ST_LocateAlong(s.geom, a.downstream_route_measure)
              ))).geom)::geometry(Point, 3005) AS geom
       FROM %1$s.cabd_additions a
       INNER JOIN whse_basemapping.fwa_stream_networks_sp s
         ON a.blue_line_key = s.blue_line_key
        AND ROUND(a.downstream_route_measure::numeric)
              >= ROUND(s.downstream_route_measure::numeric)
        AND ROUND(a.downstream_route_measure::numeric)
              <  ROUND(s.upstream_route_measure::numeric)
       WHERE a.feature_type = 'dams'
     )
     SELECT * FROM placed
     UNION ALL
     SELECT * FROM usa;",
    schema))

  # 4. Filter the local <schema>.dams to the AOI (per-WSG locality).
  .lnk_db_execute(conn, sprintf(
    "DELETE FROM %s.dams WHERE watershed_group_code <> %s",
    schema, .lnk_quote_literal(aoi)))

  # 5. Cleanup the cabd_dams_raw stage; keep the 4 edit-CSV tables for
  #    debugging visibility (they're small).
  .lnk_db_execute(conn, sprintf(
    "DROP TABLE %s.cabd_dams_raw", schema))

  invisible(NULL)
}
