#' Build per-segment access codes + downstream-barrier indicators
#'
#' Composes [fresh::frs_network_features()] calls across species (and
#' optionally observations) to produce a `streams_access` wide table
#' that mirrors `bcfishpass.streams_access`'s shape — one row per
#' segment, with per-species `has_barriers_<sp>_dnstr` booleans and per-
#' species integer `access_<sp>` codes derived via CASE on
#' (wsg-presence × dnstr-empty × observed-upstream).
#'
#' A walk whose result is read only for membership (every
#' `barriers_per_sp` table, and each `barrier_sources` table no ordered
#' indicator reads) asks fresh whether any barrier lies downstream
#' (`result = "exists"`) rather than for the array of them. Arrays are
#' built only for the `"anthropogenic"` and `"dams"` sources when both are
#' given (`dam_dnstr_ind` reads the first element), for `"remediations"`
#' when `crossings_table` is set (`remediated_dnstr_ind`), and for the
#' upstream observation walk (species codes). A table given in several
#' roles is walked once, as an array if any role reads its elements.
#'
#' This phase runs after [lnk_pipeline_classify()] returns and before
#' [lnk_pipeline_persist()] cleanup_working drops the working schema —
#' it needs the per-species `barriers_<sp>` tables that prepare/break
#' built. Output goes to `<schema>.streams_access` (working schema,
#' picked up by persist on the next commit).
#'
#' Access integer codes per species (mirroring bcfp):
#'   -9 = species not present in WSG (per `wsg_presence`)
#'    0 = barriers downstream (blocked)
#'    1 = no barriers downstream + species not observed upstream
#'        (modelled accessible)
#'    2 = no barriers downstream + species recorded upstream, as fwapg's
#'        `fwa_upstream()` reads it: at least 1 m above the segment's start
#'        on its own line, or on a line its watershed codes put upstream.
#'        By the same-line measure test, a record less than 1 m above the
#'        segment's start is not upstream of it, as in bcfishpass, so the segment starting at a
#'        species' top record on a line normally reads 1 (`RUNBOOK.md` §2c
#'        has the other records the walk counts and when a top does not
#'        cut).
#'
#' @param conn A [DBI::DBIConnection-class] object pointing at fwapg.
#' @param segments Character. Schema-qualified segments table.
#' @param to Character or `NULL`. Optional schema-qualified output
#'   table. When supplied, the wide `streams_access` shape is written
#'   via `dbWriteTable(overwrite = TRUE)`; in either case the tibble
#'   is returned invisibly. Default `NULL` returns-only.
#' @param aoi Character. Watershed group code (e.g. `"ADMS"`). Filter
#'   applied to segments via `watershed_group_code = aoi`.
#' @param barriers_per_sp Named list. Each name is a species code (e.g.
#'   `"bt"`); each value is a schema-qualified barriers table for that
#'   species (e.g. `"working_adms.barriers_bt"`). Each barriers table
#'   must have a `<sp>_id` column (e.g. `barriers_bt_id`) plus the
#'   standard `(blue_line_key, downstream_route_measure, wscode_ltree,
#'   localcode_ltree)` keys, and `watershed_group_code`, which the key
#'   that lets identical tables share one walk reads (as
#'   [lnk_barriers_views()] provides).
#' @param observations Character or `NULL`. Optional schema-qualified
#'   observations table with `(observation_key, species_code, ...)` +
#'   the standard FWA keys. When provided, drives the access code
#'   distinction between `1` (modelled) and `2` (observed). The walk
#'   scopes segments to `aoi`, never these records, so a record in any
#'   group upstream counts; [lnk_pipeline_run()] passes every group's
#'   (`<schema>.observations_province`, link#401). Default
#'   `NULL` collapses observation-distinguishing logic — every
#'   accessible segment gets `access_<sp> = 1`. Walked once for the
#'   distinct species upstream of each segment (fresh's
#'   `result = "distinct"`), so a main stem below many groups' records
#'   costs one element per species rather than one per record (link#401).
#' @param observations_gate Character or `NULL`. Optional schema-qualified
#'   table of the same shape. When given, a segment reads `2` only where a
#'   record from this table, of any species, is also upstream: bcfishpass's
#'   reading, whose species array is kept only where a record of the
#'   segment's own group is upstream (`spp INNER JOIN ids` in
#'   `load_streams_upstr_observations.sql`). [lnk_pipeline_run()] passes the
#'   group's own records here under `pipeline: observation_upstream:
#'   group_gated`, and nothing under `province`.
#' @param wsg_presence Named logical. One per species (matching
#'   `barriers_per_sp` keys), `TRUE` when the species is present in
#'   `aoi`. Sets `access_<sp> = -9` for species marked `FALSE`. Default
#'   empty list assumes all species present (no -9 codes emitted).
#' @param barrier_sources Named list. Each name is an arbitrary source
#'   tag (e.g. `"anthropogenic"`, `"pscis"`, `"dams"`,
#'   `"remediations"`); each value is a schema-qualified barriers table
#'   for that source. Output gains one `has_barriers_<source>_dnstr`
#'   boolean column per source. Unlike `barriers_per_sp`, sources here
#'   don't drive the species access integer code -- they're the
#'   bcfp-shape dnstr indicators consumed by
#'   [lnk_pipeline_mapping_code()]. Optional; default empty.
#'
#'   When both `"anthropogenic"` and `"dams"` are present, the output
#'   gains a `dam_dnstr_ind` boolean column: TRUE iff the next-
#'   downstream anthropogenic barrier is also a dam (sequence-aware,
#'   mirrors bcfp's `array[barriers_anthropogenic_dnstr[1]] &&
#'   barriers_dams_dnstr` SQL). Required for resident-flavor
#'   `mapping_code_bt` / `mapping_code_wct` parity with bcfp.
#'
#'   When `"remediations"` is present AND `crossings_table` is set,
#'   the output gains a `remediated_dnstr_ind` boolean column.
#' @param crossings_table Character or `NULL`. Schema-qualified
#'   crossings table with `aggregated_crossings_id` and `pscis_status`
#'   columns (e.g. `"bcfishpass.crossings"`). Used only to compute
#'   `remediated_dnstr_ind` (TRUE iff the next-downstream remediation
#'   is a crossing whose `pscis_status IN ('REMEDIATED', 'PASSABLE')`).
#'
#'   bcfp's own `streams_access.remediated_dnstr_ind` is currently
#'   buggy (see smnorris/bcfishpass#690): the JOIN clause
#'   `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` is
#'   contradictory and always FALSE -- verified against 4.2M rows. link
#'   computes the bcfp-intended `IN` semantics, so link's mapping_code
#'   may emit `REMEDIATED` tokens on segments where bcfp's current
#'   output emits `DAM` / `MODELLED` / `ASSESSED`. PR filed against
#'   the `NewGraphEnvironment/bcfishpass` fork; once it lands +
#'   propagates upstream the outputs converge. Default `NULL` skips
#'   the `remediated_dnstr_ind` column.
#' @param segment_id_col Character. Default `"id_segment"`.
#'
#' @return A tibble, one row per segment in `aoi`: `segment_id_col`, the
#'   `has_barriers_*_dnstr` flags, `access_<sp>` codes, `dam_dnstr_ind` /
#'   `remediated_dnstr_ind` when computed, and, with `observations`, the
#'   `obsrvtn_species_codes_upstr` list-column. Written to `to` (scalar
#'   columns only) when given.
#'
#' @family pipeline
#'
#' @export
lnk_pipeline_access <- function(
    conn,
    segments,
    aoi,
    to = NULL,
    barriers_per_sp = list(),
    observations = NULL,
    observations_gate = NULL,
    wsg_presence = list(),
    presence = NULL,
    barrier_sources = list(),
    crossings_table = NULL,
    segment_id_col = "id_segment") {

  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(segments), length(segments) == 1L, nzchar(segments),
    is.null(to) || (is.character(to) && length(to) == 1L && nzchar(to)),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    grepl("^[A-Z]{3,5}$", aoi),
    is.list(barriers_per_sp),
    is.null(observations) ||
      (is.character(observations) &&
         length(observations) == 1L &&
         nzchar(observations)),
    is.null(observations_gate) ||
      (is.character(observations_gate) &&
         length(observations_gate) == 1L &&
         nzchar(observations_gate)),
    is.list(wsg_presence),
    is.null(presence) || is.list(presence),
    is.list(barrier_sources),
    is.null(crossings_table) ||
      (is.character(crossings_table) &&
         length(crossings_table) == 1L &&
         nzchar(crossings_table)),
    is.character(segment_id_col), length(segment_id_col) == 1L
  )

  # When `presence` is supplied (an `lnk_presence` object), let it
  # override the legacy `wsg_presence` arg AND short-circuit the SQL
  # round-trip for absent species. Saves 1-2 frs_network_features
  # queries per WSG when species are absent (e.g. salmon in ELKR).
  if (!is.null(presence)) {
    wsg_presence <- as.list(setNames(
      vapply(names(barriers_per_sp),
             function(s) isTRUE(presence$is_present(s)),
             logical(1)),
      names(barriers_per_sp)
    ))
  }

  # 1. Per-species downstream-barrier arrays via fresh's primitive.
  # bcfishpass.barriers_* tables use the `_ltree`-suffixed code columns
  # (defaults), so no per-side override needed here. The bcfp id-column
  # convention is `<table_name_without_schema>_id` — works uniformly for
  # per-species tables (`barriers_bt` -> `barriers_bt_id`) and grouped
  # tables (`barriers_ch_cm_co_pk_sk` -> `barriers_ch_cm_co_pk_sk_id`).
  # Cache the per-table query so multiple species pointing at the same
  # grouped table only run the SQL once.
  #
  # Each walk asks for arrays only where an indicator reads their elements:
  # `dam_dnstr_ind` (anthropogenic + dams, both present) and
  # `remediated_dnstr_ind` (remediations, with a crossings table). Every
  # other walk is read only as `id %in% result$id`, so it takes fresh's
  # existence walk (fresh#281), the same join without the arrays (#394).
  # The mode is a function of the table, so the cache stays keyed on it,
  # and a table also given in an array role is walked once, as arrays.
  array_roles <- character(0)
  if (all(c("anthropogenic", "dams") %in% names(barrier_sources))) {
    array_roles <- c(array_roles, "anthropogenic", "dams")
  }
  if ("remediations" %in% names(barrier_sources) && !is.null(crossings_table)) {
    array_roles <- c(array_roles, "remediations")
  }
  array_tables <- unlist(barrier_sources[array_roles], use.names = FALSE)
  walk_result <- function(tbl) if (tbl %in% array_tables) "ids" else "exists"

  # One walk per distinct barrier set (#394). The per-species views over one
  # barriers table differ only by `blocks_species` and each species'
  # overrides, so several often hold the same rows: CHWK walked five
  # CH-shaped views that returned the same segments. An existence walk reads
  # only the rows `fwa_downstream()` can admit from this AOI, so two tables
  # whose admissible rows are identical give the same answer, and they share
  # one cache entry keyed on those rows (`.lnk_walk_keys()`). Array walks keep
  # the table as their key: the ids they return are the view's own.
  walked_sp <- names(barriers_per_sp)
  if (!is.null(presence)) {
    walked_sp <- walked_sp[vapply(walked_sp,
                                  function(s) isTRUE(presence$is_present(s)),
                                  logical(1))]
  }
  key_tables <- unique(unlist(barriers_per_sp[walked_sp], use.names = FALSE))
  key_tables <- key_tables[!key_tables %in% array_tables]
  cache_key <- stats::setNames(as.list(key_tables), key_tables)
  if (length(key_tables) > 1L) {
    keys <- .lnk_walk_keys(conn, segments = segments, aoi = aoi,
                           tables = key_tables)
    cache_key[key_tables] <- as.list(paste0("rows:", keys[key_tables]))
  }
  walk_cache_key <- function(tbl) {
    if (is.null(cache_key[[tbl]])) tbl else cache_key[[tbl]]
  }

  dnstr_per_sp <- list()
  dnstr_cache <- list()
  for (sp in names(barriers_per_sp)) {
    # Skip absent species when presence is supplied -- saves the SQL
    # round-trip and signals "no data" downstream (mapping_code
    # short-circuits to "" for these).
    if (!is.null(presence) && !isTRUE(presence$is_present(sp))) next

    barriers_tbl <- barriers_per_sp[[sp]]
    table_only <- sub("^[^.]+\\.", "", barriers_tbl)
    sp_id_col <- paste0(table_only, "_id")

    key <- walk_cache_key(barriers_tbl)
    if (is.null(dnstr_cache[[key]])) {
      dnstr_cache[[key]] <- fresh::frs_network_features(
        conn,
        segments       = segments,
        features       = barriers_tbl,
        segment_id_col = segment_id_col,
        feature_id_col = sp_id_col,
        direction      = "downstream",
        aoi            = aoi,
        include_equivalents = TRUE,
        result         = walk_result(barriers_tbl)
      )
    }
    df <- dnstr_cache[[key]]
    names(df)[2] <- paste0("barriers_", sp, "_dnstr")
    dnstr_per_sp[[sp]] <- df
  }

  # 1b. Generic per-source dnstr-barrier walks (bcfp-shape: anthropogenic,
  # pscis, dams, remediations, ...). Same INNER-JOIN semantics as the
  # per-species call: a segment with at least one matching source dnstr
  # appears in the tibble; segments without matches are absent. Reuses
  # the dnstr_cache so callers passing the same table for both per-sp
  # and bcfp-source roles only run the SQL once.
  dnstr_per_source <- list()
  for (src in names(barrier_sources)) {
    src_tbl <- barrier_sources[[src]]
    table_only <- sub("^[^.]+\\.", "", src_tbl)
    src_id_col <- paste0(table_only, "_id")
    key <- walk_cache_key(src_tbl)
    if (is.null(dnstr_cache[[key]])) {
      dnstr_cache[[key]] <- fresh::frs_network_features(
        conn,
        segments       = segments,
        features       = src_tbl,
        segment_id_col = segment_id_col,
        feature_id_col = src_id_col,
        direction      = "downstream",
        aoi            = aoi,
        include_equivalents = TRUE,
        result         = walk_result(src_tbl)
      )
    }
    df <- dnstr_cache[[key]]
    names(df)[2] <- paste0("barriers_", src, "_dnstr")
    dnstr_per_source[[src]] <- df
  }

  # 2. Upstream observations (optional): which segments have a record of
  # each species upstream. `bcfishpass.observations` uses the unsuffixed
  # `wscode` / `localcode` columns (vs `_ltree` on streams), so override
  # the features-side codes.
  #
  # `include_equivalents = FALSE`, as bcfishpass's own walk calls
  # `FWA_Upstream(..., False, 1)` (load_streams_upstr_observations.sql):
  # its same-line measure test counts a record only at `m >= start + 1`, so a record
  # at a segment's start is not upstream of it. Breaks are rounded to the
  # metre, so the segment starting at a species' top record on a line
  # normally reads 1 (#399; RUNBOOK §2c has the other records the walk
  # counts and when a top does not cut). The barrier walks above keep TRUE:
  # a barrier at a segment's start must still block it.
  #
  # One walk returning each segment's distinct species (fresh's
  # result = "distinct", fresh#284), as bcfishpass's `spp` CTE takes
  # `SELECT DISTINCT segment, species_code` (link#401): the array walk
  # returns every segment-record pair, and a main stem below every other
  # group's records (LFRA under the Fraser's) carries ~10^5 of them. Over
  # every group's records it costs no more than the array walk over the
  # group's own (LFRA 65 to 37 s, BULK 21 to 8 s;
  # data-raw/logs/obs_province_401/). Under `observations_gate`, one
  # existence walk over that table, any species.
  obs_upstr <- list()
  obs_gate_ids <- NULL
  if (!is.null(observations)) {
    obs_walk <- function(features, result) {
      fresh::frs_network_features(
        conn,
        segments               = segments,
        features               = features,
        segment_id_col         = segment_id_col,
        feature_id_col         = "species_code",
        direction              = "upstream",
        aoi                    = aoi,
        include_equivalents    = FALSE,
        features_wscode_col    = "wscode",
        features_localcode_col = "localcode",
        result                 = result
      )
    }
    sp_up <- obs_walk(observations, "distinct")
    obs_upstr <- setNames(sp_up$feature_ids,
                          as.character(sp_up[[segment_id_col]]))
    if (!is.null(observations_gate)) {
      obs_gate_ids <- obs_walk(observations_gate, "exists")[[segment_id_col]]
    }
  }

  # 3. Start from segments in the AOI to make sure every segment gets
  # a row (even those with no dnstr barriers / no upstream obs).
  segments_sql <- sprintf(
    "SELECT %s FROM %s WHERE watershed_group_code = '%s'",
    segment_id_col, segments, aoi
  )
  segments_aoi <- DBI::dbGetQuery(conn, segments_sql)

  # When the source barriers table has zero rows for the AOI, the
  # species has *no data* in this WSG -- mirrors bcfp's NULL-column
  # semantics for absent-species barriers (e.g. `barriers_st` is empty
  # in WSGs without ST). Propagate that as `NA` for all segments rather
  # than `FALSE`, so downstream `lnk_pipeline_mapping_code` can suppress
  # the per-species CASE (matching bcfp's `barriers_<sp>_dnstr IS NULL`
  # branch, which yields `mapping_code_<sp> = ""`).
  out <- segments_aoi
  for (sp in names(barriers_per_sp)) {
    # Absent species (skipped above) get NA — signals "no data" to
    # downstream lnk_pipeline_mapping_code which short-circuits to "".
    if (is.null(dnstr_per_sp[[sp]])) {
      out[[paste0("has_barriers_", sp, "_dnstr")]] <- NA
    } else if (nrow(dnstr_per_sp[[sp]]) == 0L) {
      # Zero rows is "no data" only when nothing says the species is here.
      # A species known present with no barrier in the AOI has none
      # downstream (FALSE), so the mapping code keeps it: as NA it emitted
      # "" for every UPET RB segment (link#246).
      out[[paste0("has_barriers_", sp, "_dnstr")]] <-
        if (isTRUE(wsg_presence[[sp]])) FALSE else NA
    } else {
      out[[paste0("has_barriers_", sp, "_dnstr")]] <-
        out[[segment_id_col]] %in% dnstr_per_sp[[sp]][[segment_id_col]]
    }
  }
  for (src in names(dnstr_per_source)) {
    if (nrow(dnstr_per_source[[src]]) == 0L) {
      out[[paste0("has_barriers_", src, "_dnstr")]] <- NA
    } else {
      out[[paste0("has_barriers_", src, "_dnstr")]] <-
        out[[segment_id_col]] %in% dnstr_per_source[[src]][[segment_id_col]]
    }
  }

  # `dam_dnstr_ind`: TRUE iff the *next* downstream anthropogenic barrier
  # is also a dam. Mirrors bcfp's
  # `array[barriers_anthropogenic_dnstr[1]] && barriers_dams_dnstr` SQL.
  # Both source tables populate their primary key from
  # `crossings.aggregated_crossings_id`, so the IDs returned by
  # `frs_network_features` are in a shared space — `%in%` works
  # directly. Without sequence-aware logic the resident-flavor
  # `mapping_code_bt` over-emits `DAM` where bcfp emits `ASSESSED` on
  # PSCIS-then-dam stacks.
  if (all(c("anthropogenic", "dams") %in% names(dnstr_per_source))) {
    anth_arrs <- dnstr_per_source$anthropogenic[[2]]
    anth_keys <- as.character(dnstr_per_source$anthropogenic[[segment_id_col]])
    dam_arrs  <- dnstr_per_source$dams[[2]]
    dam_keys  <- as.character(dnstr_per_source$dams[[segment_id_col]])
    out_keys <- as.character(out[[segment_id_col]])
    anth_idx <- match(out_keys, anth_keys)
    dam_idx <- match(out_keys, dam_keys)
    out$dam_dnstr_ind <- vapply(seq_along(out_keys), function(i) {
      ai <- anth_idx[i]
      di <- dam_idx[i]
      if (is.na(ai)) return(FALSE)
      anth <- as.character(anth_arrs[[ai]])
      if (length(anth) == 0L || is.na(anth[1])) return(FALSE)
      if (is.na(di)) return(FALSE)
      dams <- as.character(dam_arrs[[di]])
      if (length(dams) == 0L) return(FALSE)
      anth[1] %in% dams
    }, logical(1))
  }

  # `remediated_dnstr_ind`: TRUE iff the next-downstream remediation is
  # a crossing currently in PASSABLE/REMEDIATED status. Computed per
  # bcfp's *intended* logic. bcfp's own
  # `bcfishpass.streams_access.remediated_dnstr_ind` regressed in
  # smnorris/bcfishpass#690 ("db v070", 2025-09-24) — the JOIN clause
  # `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` is
  # contradictory and emits FALSE for every row (verified: 4.2M rows).
  # link computes the bcfp-intended `IN ('REMEDIATED','PASSABLE')`
  # semantics so resident-flavor mapping_code can correctly emit
  # REMEDIATED tokens. Once smnorris/bcfishpass merges the upstream
  # fix this matches bcfp's output again.
  if ("remediations" %in% names(dnstr_per_source) &&
        !is.null(crossings_table)) {
    remed_arrs <- dnstr_per_source$remediations[[2]]
    remed_keys <- as.character(dnstr_per_source$remediations[[segment_id_col]])
    out_keys <- as.character(out[[segment_id_col]])
    remed_idx <- match(out_keys, remed_keys)
    next_remed <- vapply(seq_along(out_keys), function(i) {
      ri <- remed_idx[i]
      if (is.na(ri)) return(NA_character_)
      arr <- as.character(remed_arrs[[ri]])
      if (length(arr) == 0L) return(NA_character_)
      arr[1]
    }, character(1))
    needed <- unique(next_remed[!is.na(next_remed)])
    if (length(needed) == 0L) {
      out$remediated_dnstr_ind <- FALSE
    } else {
      ids_lit <- paste0("'", needed, "'", collapse = ",")
      sql <- sprintf(
        "SELECT aggregated_crossings_id::text AS id, pscis_status FROM %s WHERE aggregated_crossings_id::text IN (%s)",
        crossings_table, ids_lit
      )
      lookup <- DBI::dbGetQuery(conn, sql)
      pass_ids <- as.character(
        lookup$id[lookup$pscis_status %in% c("REMEDIATED", "PASSABLE")]
      )
      out$remediated_dnstr_ind <- !is.na(next_remed) & next_remed %in% pass_ids
    }
  }

  # Carry the observations onto `out`: the species with a record upstream of
  # each segment, each once (character(0) where none), and whether a record
  # of `observations_gate` is upstream (any record at all where no gate is
  # given). Neither is persisted.
  if (!is.null(observations)) {
    ids <- as.character(out[[segment_id_col]])
    sp_seg <- unname(obs_upstr[ids])
    sp_seg[vapply(sp_seg, is.null, logical(1))] <- list(character(0))
    out$obsrvtn_species_codes_upstr <- sp_seg
    out$has_observation_key_upstr <- if (!is.null(observations_gate)) {
      ids %in% as.character(obs_gate_ids)
    } else {
      ids %in% names(obs_upstr)
    }
  }

  # 4. Per-species access integer codes.
  for (sp in names(barriers_per_sp)) {
    access_col <- paste0("access_", sp)
    sp_upper <- toupper(sp)
    present <- isTRUE(wsg_presence[[sp]]) || length(wsg_presence) == 0L

    out[[access_col]] <- if (!present) {
      rep(-9L, nrow(out))
    } else {
      blocked <- out[[paste0("has_barriers_", sp, "_dnstr")]]
      observed <- if (!is.null(observations)) {
        o <- vapply(out$obsrvtn_species_codes_upstr, function(x) {
          sp_upper %in% x
        }, logical(1))
        if (!is.null(observations_gate)) o & out$has_observation_key_upstr else o
      } else {
        rep(FALSE, nrow(out))
      }
      # `blocked` is still all NA when no presence was given and the
      # species has no barrier in the AOI (above). Nothing blocks it, so it
      # is accessible; `ifelse(NA, ...)` would return a logical NA column,
      # which persist rejects against the integer `access_<sp>` (UPET RB,
      # link#246).
      blocked <- !is.na(blocked) & blocked
      ifelse(blocked, 0L, ifelse(observed, 2L, 1L))
    }
  }

  # 5. Optional persistence. dbWriteTable doesn't natively serialize R
  # list-columns to Postgres arrays for CREATE-TABLE, so the wide
  # `streams_access` write keeps scalar per-species columns only
  # (`has_barriers_<sp>_dnstr`, `access_<sp>`). The observation
  # list-column stays on the returned tibble; no barrier array reaches it
  # (most walks return none, #394). Persistent array storage is a
  # downstream improvement (would need a manual pg_array codec via
  # DBI::sqlInterpolate or a SQL `INSERT ... ARRAY[...]` builder).
  if (!is.null(to)) {
    out_scalar <- out[, !vapply(out, is.list, logical(1)), drop = FALSE]
    schema_table <- strsplit(to, "\\.", fixed = FALSE)[[1]]
    target <- if (length(schema_table) == 2L) {
      DBI::Id(schema = schema_table[1], table = schema_table[2])
    } else {
      to
    }
    DBI::dbWriteTable(conn, target, out_scalar, overwrite = TRUE)
  }

  tibble::as_tibble(out)
}

#' Fingerprint the rows each walk could read from an AOI
#'
#' For each features table, the md5 of every row `fwa_downstream()` could
#' admit from a segment of `aoi`: rows on one of the AOI's blue lines, or
#' whose `wscode_ltree` is an ancestor of, or equal to, an AOI segment's
#' (fwa_downstream's two criteria; subpaths from length 0, so an empty code
#' is included). That is a superset of what the walk reads, so two tables
#' with equal keys give the same downstream walk from this AOI. The key
#' covers every column the walk reads plus `watershed_group_code`, as record
#' text (NULL-safe: `concat_ws()` would skip a NULL and `||` would drop the
#' row), in a total text order.
#'
#' @param conn A DBI connection.
#' @param segments Schema-qualified segments table with `watershed_group_code`,
#'   `blue_line_key` and `wscode_ltree`.
#' @param aoi Watershed group code (validated by the caller).
#' @param tables Schema-qualified features tables; each exposes the bcfp-shape
#'   `<table>_id` column and the standard FWA keys.
#' @return Named character vector of md5 keys, one per table.
#' @noRd
.lnk_walk_keys <- function(conn, segments, aoi, tables) {
  stopifnot(is.character(tables), length(tables) > 0L,
            grepl("^[A-Z]{3,5}$", aoi))
  branch_sql <- "SELECT %d AS i,
         md5(coalesce(string_agg(r, '|' ORDER BY r COLLATE \"C\"), '')) AS key
       FROM (
         SELECT row(f.%s, f.watershed_group_code, f.blue_line_key,
                    f.downstream_route_measure, f.wscode_ltree,
                    f.localcode_ltree)::text AS r
         FROM %s f
         WHERE f.wscode_ltree = ANY (ARRAY(SELECT code FROM codes))
            OR f.blue_line_key = ANY (ARRAY(SELECT blue_line_key FROM lines))
       ) x"
  branches <- vapply(seq_along(tables), function(i) {
    id_col <- paste0(sub("^[^.]+\\.", "", tables[i]), "_id")
    sprintf(branch_sql, i, id_col, tables[i])
  }, character(1))
  scope_sql <- "WITH seg AS (
       SELECT DISTINCT blue_line_key, wscode_ltree FROM %s
       WHERE watershed_group_code = '%s'),
     lines AS (SELECT DISTINCT blue_line_key FROM seg),
     codes AS (
       SELECT ''::ltree AS code
       UNION
       SELECT subpath(wscode_ltree, 0, k)
       FROM seg, generate_series(1, nlevel(wscode_ltree)) k
       WHERE wscode_ltree IS NOT NULL)
     %s"
  sql <- sprintf(scope_sql, segments, aoi,
                 paste(branches, collapse = "\n     UNION ALL\n     "))
  res <- DBI::dbGetQuery(conn, sql)
  keys <- res$key[match(seq_along(tables), res$i)]
  if (length(keys) != length(tables) || anyNA(keys)) {
    stop(".lnk_walk_keys(): expected one key per table, got ", nrow(res),
         " rows for ", length(tables), " tables", call. = FALSE)
  }
  stats::setNames(keys, tables)
}


#' Which fish records make a segment read "observed upstream"
#'
#' The bundle's `pipeline: observation_upstream:` value:
#' - `province`: a record of the species in any watershed group upstream
#'   (link#401).
#' - `group_gated` (also when absent): as `province`, but only where a record
#'   of the segment's own group, of any species, is also upstream. That is
#'   what bcfishpass computes (`spp INNER JOIN ids`,
#'   `load_streams_upstr_observations.sql`, `smnorris/bcfishpass@620dbe4`).
#' @noRd
.lnk_observation_upstream <- function(cfg) {
  v <- cfg$pipeline[["observation_upstream"]] %||% "group_gated"
  .lnk_observation_upstream_check(v, paste0("cfg '", cfg$name %||% "", "'"))
}

#' Validate an observation_upstream value
#' @noRd
.lnk_observation_upstream_check <- function(v, what = "observation_upstream") {
  ok <- c("province", "group_gated")
  if (!is.character(v) || length(v) != 1L || is.na(v) || !v %in% ok) {
    stop(what, ": observation_upstream must be one of ",
         paste(ok, collapse = ", "), call. = FALSE)
  }
  v
}
