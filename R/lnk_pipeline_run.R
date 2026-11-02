#' Run the link pipeline end-to-end for one watershed group
#'
#' Modelling-only umbrella: chains the `lnk_pipeline_*` phases and the
#' persist write-out into a single call. Produces per-WSG segment data
#' in the persistent province-wide tables (`<persist_schema>.streams`,
#' `streams_habitat_<sp>` per species, `barriers`).
#'
#' This is the **modelling boundary** — the link package's deliverable.
#' Comparison against bcfishpass (or any future reference) lives in
#' [lnk_compare_rollup()], which reads the persisted state. The split
#' lets re-running the pipeline and re-running the comparison happen
#' independently; an orchestrator loop's resume check can probe PG
#' state via `link:::.lnk_wsg_persisted()` rather than the comparison
#' RDS artifact.
#'
#' ## Phase order
#'
#' Before any phase, [lnk_vocabulary_resolve()] names the output on its four
#' axes (cut, access, gradient, flow). A config the vocabulary has no live
#' token for is refused before anything is written, and the tokens go in the
#' run's `<persist_schema>.log` row.
#'
#' 1. [lnk_pipeline_setup()] — create per-WSG working schema.
#' 2. [lnk_pipeline_load()] — crossings + modelled fixes + PSCIS status.
#' 3. [lnk_pipeline_prepare()] — falls, definite + control, habitat
#'    confirms, gradient barriers, natural barriers, barrier overrides,
#'    per-model minimal reduction, base segments. Passes `conn` as
#'    `conn_tunnel` when `dams = TRUE` so CABD dams flow through.
#' 4. [lnk_pipeline_crossings()] — match PSCIS to modelled crossings.
#' 5. [lnk_pipeline_break()] — observations, gradient minimal, definite,
#'    habitat endpoints, crossings — in config-defined order.
#' 6. [lnk_pipeline_species()] — resolve the active species set for this
#'    AOI (cfg$species ∩ wsg_species_presence). Empty is a group where only
#'    species the bundle pauses are present: steps 7 and 8 and the habitat
#'    gate are skipped, and the group is persisted with its segments,
#'    barriers and access annotations but no habitat. A group where no rules
#'    species is present is an error.
#' 7. [lnk_pipeline_classify()] — assemble `streams_breaks` and run
#'    `frs_habitat_classify()`.
#' 8. [lnk_pipeline_connect()] — per-species cluster + connected_waterbody.
#' 9. [lnk_persist_init()] — create persistent target tables if absent.
#' 10. [lnk_barriers_unify()] — unify per-source barriers into a single
#'     working-schema table (always; promotes the mapping_code-only
#'     flag in `lnk_compare_wsg()` to canonical PG state).
#' 10a. **Access phase (always-on, link#218).** Runs between barriers_unify
#'      and persist: a pre-persist of the current WSG (so the next two steps
#'      see cross-WSG barriers), [lnk_barriers_views()] (tunnel-free,
#'      link-canonical per-species views over `<persist_schema>.barriers`),
#'      and [lnk_pipeline_access()] (writes working `streams_access`). Access
#'      is foundational — mapping_code depends on it — so it builds regardless
#'      of `mapping_code`. See link#187, #196.
#' 11. [lnk_pipeline_persist()] — copy per-WSG streams + per-species
#'     habitat + barriers + streams_access into `<persist_schema>`
#'     (idempotent DELETE-WHERE-WSG + INSERT). The group's rows in the habitat
#'     tables of species not classified here (paused, or no longer present)
#'     are then deleted, so no earlier build's habitat outlives its segments.
#' 12. [lnk_habitat_gate()] — settle the persisted habitat flags on
#'     `streams_access`: where `access_<sp>` is 0, `accessible`, `spawning`,
#'     `rearing`, `lake_rearing` and `wetland_rearing` go FALSE (link#349).
#' 13. *Optional* mapping_code token assembly — gated by `mapping_code = TRUE`.
#'     [lnk_mapping_code()] reads the persisted `streams_access` and the
#'     settled habitat, and writes `<persist_schema>.streams_mapping_code`.
#'
#' @param conn DBI connection to the local pipeline database (typically
#'   localhost fwapg).
#' @param aoi Watershed group code (e.g. `"ADMS"`). Validated against
#'   `^[A-Z]{3,5}$`.
#' @param cfg An `lnk_config` object (from [lnk_config()]).
#' @param loaded Named list from [lnk_load_overrides()].
#' @param schema Working schema name. Default
#'   `paste0("working_", tolower(aoi))`. Per-WSG staging tables live
#'   here; dropped on exit when `cleanup_working = TRUE`.
#' @param dams Logical. When `TRUE` (default), pass `conn` as
#'   `conn_tunnel` to [lnk_pipeline_prepare()] so the CABD dams step
#'   runs from local `cabd.dams`. Pass `FALSE` to skip dams entirely.
#' @param cleanup_working Logical. When `TRUE` (default), drop the
#'   `<schema>` working schema at the end. Pass `FALSE` for interactive
#'   debug / manual inspection.
#' @param mapping_code Logical. Gates only the mapping_code **token
#'   assembly** (phase 13) — when `TRUE`, [lnk_mapping_code()] runs and
#'   `<persist_schema>.streams_mapping_code` is produced for the WSG,
#'   consumed downstream by `data-raw/build_species_views.R --bcfp` (QGIS
#'   bcfp-shape symbology). Default `FALSE`. **`streams_access` is built
#'   and persisted regardless of this flag** (phase 10a, link#218) —
#'   access is foundational, not mapping_code-specific. Methodology shift
#'   from pre-#187 compare_wsg: access uses link's own per-species
#'   barriers (via `blocks_species` predicate on `<schema>.barriers`),
#'   not bcfp's tunnel-staged tables.
#' @param habitat_gate Logical. When `TRUE` (default), settle the persisted
#'   habitat flags on `streams_access` with [lnk_habitat_gate()] (phase 12,
#'   link#349). `FALSE` keeps fresh's classify-time flags, for measuring what
#'   the gate changes; the log row's `habitat_gate_*` columns stay NULL.
#' @param log Logical. When `TRUE` (default), record run provenance into
#'   `<persist_schema>.log` and its companion tables (link#127) — which
#'   config produced this network, what that config actually said, which
#'   primitive vintage it read, and when. The open row is written before
#'   any modelling so `wsg_upstream` reflects the state the run started
#'   from; everything after it degrades to a warning rather than failing
#'   the run. Pass `FALSE` for throwaway runs.
#' @param run_uid Character. Identifies one *dispatch* — every host and every
#'   watershed group of a single `data-raw/study_area_run.sh` invocation share
#'   it, so "every row of that run" is one equality rather than a time window
#'   plus a host list (link#262). Defaults to the `LNK_RUN_UID` env var, which
#'   the driver exports to the local leg and into the cypher ssh string. `NA`
#'   for an ad-hoc single-WSG call is correct: there was no dispatch to belong
#'   to. Distinct from `run_id`, which is minted per call and is the log's PK.
#' @param run_label Character. Groups a campaign across hosts and WSGs
#'   (e.g. `"provincial_default_rearbreaks"`). Operator-supplied free text —
#'   never assume it is unique; `run_uid` is the machine identifier. Defaults
#'   to the `LNK_RUN_LABEL` env var so orchestrators can set it once.
#' @param notes Character. Free-form note stored on the run row.
#'
#' @return `conn`, invisibly. Side effects are the writes into
#'   `<persist_schema>.streams`, `streams_habitat_<sp>` (settled on
#'   `streams_access`), `streams_access` and `barriers`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Model one WSG end-to-end (~70s)
#' lnk_pipeline_run(conn = conn, aoi = "ADMS",
#'                  cfg = cfg, loaded = loaded)
#'
#' # Verify PG state
#' DBI::dbGetQuery(conn,
#'   "SELECT count(*) FROM fresh.streams WHERE watershed_group_code = 'ADMS'")
#' }
#'
#' @family pipeline
#' @seealso [lnk_compare_rollup()], [lnk_compare_wsg()],
#'   [lnk_pipeline_setup()], [lnk_pipeline_persist()]
#' @export
lnk_pipeline_run <- function(conn, aoi, cfg, loaded,
                             schema = paste0("working_", tolower(aoi)),
                             dams = TRUE,
                             cleanup_working = TRUE,
                             mapping_code = FALSE,
                             habitat_gate = TRUE,
                             log = TRUE,
                             run_uid = Sys.getenv("LNK_RUN_UID",
                                                  NA_character_),
                             run_label = Sys.getenv("LNK_RUN_LABEL",
                                                    NA_character_),
                             notes = NA_character_) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    inherits(cfg, "lnk_config"),
    is.list(loaded),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    # `schema` is interpolated raw into DDL (DROP TABLE / DROP SCHEMA
    # CASCADE) via sprintf in the phase functions and this one. Whitelist
    # regex makes SQL injection structurally impossible even if a caller
    # overrides the default `working_<aoi>` value.
    grepl("^[a-z_][a-z0-9_]*$", schema),
    is.logical(dams), length(dams) == 1L,
    is.logical(cleanup_working), length(cleanup_working) == 1L,
    is.logical(mapping_code), length(mapping_code) == 1L,
    is.logical(habitat_gate), length(habitat_gate) == 1L, !is.na(habitat_gate),
    is.logical(log), length(log) == 1L
  )

  # The output's name (#414), before anything writes: a config whose cuts,
  # access rules, gradient or flow the vocabulary has no live token for is
  # refused here, logged or not.
  tokens <- lnk_vocabulary_resolve(cfg, loaded)

  # Run provenance (link#127). Opened here, before anything writes, so
  # `wsg_upstream` reflects the cross-WSG state this run actually started
  # from — the pre-persist below mutates it. `on.exit` rather than
  # tryCatch: it preserves traceback() for interactive debugging and keeps
  # the invisible(conn) contract, at the cost of three lines.
  run_log <- NULL
  if (isTRUE(log)) {
    run_log <- .lnk_log_run_start(conn, cfg = cfg, aoi = aoi,
                                  schema_working = schema, dams = dams,
                                  cleanup_working = cleanup_working,
                                  mapping_code = mapping_code,
                                  run_uid = run_uid,
                                  run_label = run_label, notes = notes,
                                  tokens = tokens)
    completed <- FALSE
    on.exit({
      if (!completed) {
        try(.lnk_log_run_fail(conn, cfg, run_log$run_id), silent = TRUE)
      }
    }, add = TRUE)
    .lnk_log_config_snapshot(conn, run_log$schema, cfg, loaded,
                             run_log$config_hash)
    .lnk_log_inputs(conn, run_log$schema, run_log$run_id, aoi, cfg = cfg)
  }

  # Defensive reset of per-WSG staging from any prior partial run.
  DBI::dbExecute(conn, sprintf(
    "DROP TABLE IF EXISTS %1$s.streams, %1$s.streams_habitat,
     %1$s.streams_breaks CASCADE", schema))

  lnk_pipeline_setup(conn, schema, overwrite = TRUE) # nolint: object_usage_linter
  # prepare builds <schema>.observations_province (every group's records) for
  # the barrier lifts and the access walk below. Dropped on exit (return or
  # error), because wsg_run_one.R keeps its working schema and the copy is
  # ~200 MB per group. It stays when R is killed or the DROP itself fails (a
  # lost connection), until the group's next run replaces it.
  drop_obs_province <- sprintf(
    "DROP TABLE IF EXISTS %s.observations_province", schema)
  on.exit(try(DBI::dbExecute(conn, drop_obs_province), silent = TRUE),
          add = TRUE)
  lnk_pipeline_load(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                    loaded = loaded, schema = schema)
  lnk_pipeline_prepare(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       loaded = loaded, schema = schema,
                       conn_tunnel = if (dams) conn else NULL)
  lnk_pipeline_crossings(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                         loaded = loaded, schema = schema)
  lnk_pipeline_break(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                     loaded = loaded, schema = schema)

  # The species classified here: the bundle's modelled species present in
  # the group. Empty is a group where only species the bundle pauses are
  # present (#432): it is still built for its segments, barriers and access
  # annotations, which other groups' recompute reads, and gets no habitat.
  # A group where no rules species is present at all is refused.
  active_species <- lnk_pipeline_species(cfg, loaded, aoi) # nolint: object_usage_linter
  if (length(active_species) == 0L &&
      length(lnk_pipeline_species(cfg, loaded, aoi, paused = TRUE)) == 0L) { # nolint: object_usage_linter
    stop("no active species in ", aoi,
         " — no rules species of the bundle is present in wsg_species_presence.",
         call. = FALSE)
  }
  if (length(active_species) > 0L) {
    lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                          loaded = loaded, schema = schema)
    lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                         loaded = loaded, schema = schema)
  } else {
    message("[lnk_pipeline_run] ", aoi, ": only paused species present (",
            paste(lnk_pipeline_species(cfg, loaded, aoi, paused = TRUE), # nolint: object_usage_linter
                  collapse = ", "),
            "); segments and barriers only, no habitat")
  }

  # Persist DDL sized to the FULL bundle (cfg$species), not the per-WSG
  # active subset (link#194). Wide tables (streams_access,
  # streams_mapping_code) have one column per species — first WSG would
  # lock the column set if we passed active_species, then subsequent WSGs
  # with different active sets would fail INSERT. Per-WSG INSERTs still
  # use active_species (in lnk_pipeline_persist below) so unused species'
  # columns get NULL for WSGs that don't model them. Per-species habitat
  # tables (streams_habitat_<sp>) get created for the full bundle too —
  # empty tables for species no WSG populates are cheap.
  lnk_persist_init(conn, cfg, species = cfg$species) # nolint: object_usage_linter

  # Always unify barriers — makes `<persist_schema>.barriers` canonical
  # for any future reader (e.g. a decoupled mapping_code comparison).
  # Cost is small: one per-WSG unify + copy.
  lnk_barriers_unify(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                     loaded = loaded, schema = schema)

  # Access phase (link#187, always-on per link#218). Tunnel-free build of
  # streams_access in the working schema; the persist phase (below) copies it
  # to <persist_schema>. Access is foundational — mapping_code depends on it,
  # not the reverse — so it runs regardless of `mapping_code`. Methodology vs
  # pre-#187 compare_wsg: ACCESS uses link's own per-species barriers (derived
  # from <schema>.barriers's `blocks_species` predicate via lnk_barriers_views)
  # instead of bcfp's barriers tables staged via the tunnel. See NEWS v0.40.0.
  # Only the mapping_code token assembly (step 4) stays gated by `mapping_code`.
  pres <- lnk_presence(loaded$wsg_species_presence, aoi) # nolint: object_usage_linter

  # 0. Pre-persist current WSG's barriers + streams + habitat into
  # <persist_schema> BEFORE building views. lnk_barriers_views defaults
  # to reading the persist barriers table — necessary for cross-WSG
  # access lookups (e.g. PARS BT through Bennett dams in PCEA/UPCE,
  # link#152). My #187 Phase 4 worked around an ordering issue by
  # pointing views at working <schema>.barriers, but that loses the
  # cross-WSG visibility. Fix: persist current WSG's barriers FIRST,
  # so persist holds current + all previously-persisted WSGs by the
  # time the views are built. Second persist call below re-runs
  # idempotently and adds streams_access. link#196.
  lnk_pipeline_persist(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       species = active_species, schema = schema)
  # That persist replaced this group's streams, and its habitat rows only for
  # the species classified here. A species no longer classified (paused in the
  # bundle, #432, or no longer present) keeps rows from an earlier build, cut
  # to segments that no longer exist, and readers that find species from the
  # tables (lnk_compare_rollup()) would count them. Cleared here, before the
  # access walks, so a later failure cannot leave them beside the new streams.
  .lnk_persist_clear_unmodelled(conn, cfg, aoi = aoi, species = active_species,
                                schema = schema)

  # 1. Per-species + per-source barrier views over PERSIST
  # <persist_schema>.barriers (default — see #196). Province-wide,
  # tunnel-free, link-canonical. Sees current WSG (just persisted) +
  # all previously-persisted WSGs (cross-WSG dam visibility).
  # `species = active_species` so the view set matches the bundle
  # (default config = bt/gr/ko/rb — not the bcfp 8).
  lnk_barriers_views(conn, schema = schema, cfg = cfg, # nolint: object_usage_linter
                     species = active_species)

  # 2. Per-segment access. barriers_per_sp drives `accessible` (token1
  # ACCESS + token2 gate). Uses the per-species `barriers_<sp>_access`
  # views (link#200) — these reproduce bcfp's per-species access set
  # (`barriers_<sp>`, smnorris/bcfishpass model/01_access/sql/
  # model_access_bt.sql): NATURAL barriers only (gradient at the species
  # threshold + falls + subsurface), MINUS the observation/habitat
  # override, ∪ user_definite (override-exempt). Dams/PSCIS/modelled are
  # NOT in the access set — they annotate access via token2
  # (barrier_sources below), never block it. So a dam-downstream segment
  # that is otherwise accessible stays accessible and emits `;DAM`. All
  # inputs are province-wide-persisted (barriers + barrier_overrides via
  # the pre-persist above), so the cross-WSG downstream walk is correct in
  # every WSG, not just the run's own. See RUNBOOK.md §5.
  #
  # Code 2 (the species recorded upstream) reads every group's records, as
  # bcfishpass's walk does: the `spp` CTE of
  # load_streams_upstr_observations.sql joins bcfishpass.observations with no
  # group filter (smnorris/bcfishpass@620dbe4). The group's own records alone
  # read a main stem as unobserved up to its group boundary (link#401).
  # bcfishpass keeps that array only where a record of the segment's own
  # group is upstream (`spp INNER JOIN ids`); `pipeline: observation_upstream:
  # group_gated` (the bcfishpass bundle, and the value when absent) passes the
  # group's own records as that gate, `province` (default) passes none.
  # Breaks still read the group's own `<schema>.observations`.
  sp_set <- tolower(active_species)
  barriers_per_sp <- setNames(
    lapply(sp_set, function(sp) paste0(schema, ".barriers_", sp, "_access")),
    sp_set)

  lnk_pipeline_access(conn, # nolint: object_usage_linter
    segments        = paste0(schema, ".streams"),
    aoi             = aoi,
    to              = paste0(schema, ".streams_access"),
    barriers_per_sp = barriers_per_sp,
    # No species classified here (only paused ones present, #432): nothing
    # reads code 2, so the province-wide walk is skipped.
    observations    = if (length(active_species) > 0L) {
      paste0(schema, ".observations_province")
    },
    observations_gate = if (identical(.lnk_observation_upstream(cfg),
                                      "group_gated")) {
      paste0(schema, ".observations")
    },
    presence        = pres,
    barrier_sources = list(
      anthropogenic = paste0(schema, ".barriers_anthropogenic_unified"),
      pscis         = paste0(schema, ".barriers_pscis"),
      dams          = paste0(schema, ".barriers_dams_unified"),
      remediations  = paste0(schema, ".barriers_remediations")),
    crossings_table = paste0(schema, ".crossings"))

  lnk_pipeline_persist(conn, aoi = aoi, cfg = cfg, # nolint: object_usage_linter
                       species = active_species, schema = schema)

  # 3. Settle the persisted habitat flags on link's access (link#349): where
  # access_<sp> = 0, accessible / spawning / rearing / lake_rearing /
  # wetland_rearing go FALSE (known-habitat overlay rows keep spawning and
  # rearing). fresh's `accessible` was built from this group's own breaks
  # only; access_<sp> is the province-wide answer, so the flags follow it.
  tn <- .lnk_table_names(cfg)
  gate <- NULL
  if (isTRUE(habitat_gate) && length(active_species) > 0L) {
    gate <- lnk_habitat_gate(conn, aoi = aoi, # nolint: object_usage_linter
      table_habitat = paste0(tn$schema, ".streams_habitat"),
      table_access  = paste0(tn$schema, ".streams_access"),
      table_streams = paste0(tn$schema, ".streams"),
      species       = active_species,
      overlay       = .lnk_habitat_gate_overlay(cfg, loaded))
  }

  # 4. Per-segment per-species mapping_code tokens, gated by `mapping_code`
  # (link#218). Built from PERSIST, after the gate, the way the
  # post-consolidate recompute builds them, so SPAWN / REAR tokens never ride
  # on flags the gate blanked (link#349).
  if (isTRUE(mapping_code)) {
    .lnk_mapping_code_persist(conn, schema = tn$schema, aoi = aoi,
                              species = active_species, presence = pres)
  }

  if (isTRUE(cleanup_working)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  }

  if (!is.null(run_log)) {
    completed <- TRUE
    .lnk_log_run_finish(conn, cfg, run_log$run_id, species = active_species,
                        habitat_gate = gate)
  }

  invisible(conn)
}
