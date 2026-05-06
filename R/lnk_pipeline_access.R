#' Build per-segment access codes + downstream-feature arrays
#'
#' Composes [fresh::frs_network_features()] calls across species (and
#' optionally observations) to produce a `streams_access` wide table
#' that mirrors `bcfishpass.streams_access`'s shape — one row per
#' segment, with per-species `barriers_<sp>_dnstr` arrays and per-
#' species integer `access_<sp>` codes derived via CASE on
#' (wsg-presence × dnstr-empty × observed-upstream).
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
#'    2 = no barriers downstream + species observed upstream
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
#'   localcode_ltree)` keys.
#' @param observations Character or `NULL`. Optional schema-qualified
#'   observations table with `(observation_key, species_code, ...)` +
#'   the standard FWA keys. When provided, drives the access code
#'   distinction between `1` (modelled) and `2` (observed). Default
#'   `NULL` collapses observation-distinguishing logic — every
#'   accessible segment gets `access_<sp> = 1`.
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
#' @return `conn` invisibly, for piping.
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
    wsg_presence = list(),
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
    is.list(wsg_presence),
    is.list(barrier_sources),
    is.null(crossings_table) ||
      (is.character(crossings_table) &&
         length(crossings_table) == 1L &&
         nzchar(crossings_table)),
    is.character(segment_id_col), length(segment_id_col) == 1L
  )

  # 1. Per-species downstream-barrier arrays via fresh's primitive.
  # bcfishpass.barriers_* tables use the `_ltree`-suffixed code columns
  # (defaults), so no per-side override needed here. The bcfp id-column
  # convention is `<table_name_without_schema>_id` — works uniformly for
  # per-species tables (`barriers_bt` -> `barriers_bt_id`) and grouped
  # tables (`barriers_ch_cm_co_pk_sk` -> `barriers_ch_cm_co_pk_sk_id`).
  # Cache the per-table query so multiple species pointing at the same
  # grouped table only run the SQL once.
  dnstr_per_sp <- list()
  dnstr_cache <- list()
  for (sp in names(barriers_per_sp)) {
    barriers_tbl <- barriers_per_sp[[sp]]
    table_only <- sub("^[^.]+\\.", "", barriers_tbl)
    sp_id_col <- paste0(table_only, "_id")

    if (is.null(dnstr_cache[[barriers_tbl]])) {
      dnstr_cache[[barriers_tbl]] <- fresh::frs_network_features(
        conn,
        segments       = segments,
        features       = barriers_tbl,
        segment_id_col = segment_id_col,
        feature_id_col = sp_id_col,
        direction      = "downstream",
        aoi            = aoi,
        include_equivalents = TRUE
      )
    }
    df <- dnstr_cache[[barriers_tbl]]
    names(df)[2] <- paste0("barriers_", sp, "_dnstr")
    dnstr_per_sp[[sp]] <- df
  }

  # 1b. Generic per-source dnstr-barrier arrays (bcfp-shape: anthropogenic,
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
    if (is.null(dnstr_cache[[src_tbl]])) {
      dnstr_cache[[src_tbl]] <- fresh::frs_network_features(
        conn,
        segments       = segments,
        features       = src_tbl,
        segment_id_col = segment_id_col,
        feature_id_col = src_id_col,
        direction      = "downstream",
        aoi            = aoi,
        include_equivalents = TRUE
      )
    }
    df <- dnstr_cache[[src_tbl]]
    names(df)[2] <- paste0("barriers_", src, "_dnstr")
    dnstr_per_source[[src]] <- df
  }

  # 2. Upstream observations (optional). One call returns per-segment
  # arrays of observed species_code. `bcfishpass.observations` uses
  # the unsuffixed `wscode` / `localcode` columns (vs `_ltree` on
  # streams), so override the features-side codes. Returns a list-
  # column of character vectors (fresh#204 v0.29.0+) — the per-species
  # `observed` boolean is then a clean `%in%` per row.
  obsrvtn_species_per_seg <- NULL
  if (!is.null(observations)) {
    obsrvtn_species_per_seg <- fresh::frs_network_features(
      conn,
      segments               = segments,
      features               = observations,
      segment_id_col         = segment_id_col,
      feature_id_col         = "species_code",
      direction              = "upstream",
      aoi                    = aoi,
      include_equivalents    = TRUE,
      features_wscode_col    = "wscode",
      features_localcode_col = "localcode"
    )
    names(obsrvtn_species_per_seg)[2] <- "obsrvtn_species_codes_upstr"
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
  for (sp in names(dnstr_per_sp)) {
    if (nrow(dnstr_per_sp[[sp]]) == 0L) {
      out[[paste0("has_barriers_", sp, "_dnstr")]] <- NA
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

  # Carry the observations list-column onto `out` so per-species
  # `%in%` checks work row-wise. Segments with no upstream observations
  # are absent from the obs tibble (INNER-JOIN semantics) — left-join
  # leaves their list-column as NULL, which `%in%` treats as logical(0)
  # falsey → access_<sp> = 1 (modelled accessible).
  if (!is.null(obsrvtn_species_per_seg)) {
    obs_lookup <- setNames(
      obsrvtn_species_per_seg$obsrvtn_species_codes_upstr,
      as.character(obsrvtn_species_per_seg[[segment_id_col]])
    )
    out$obsrvtn_species_codes_upstr <-
      obs_lookup[as.character(out[[segment_id_col]])]
    out$has_observation_key_upstr <-
      out[[segment_id_col]] %in% obsrvtn_species_per_seg[[segment_id_col]]
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
      observed <- if (!is.null(obsrvtn_species_per_seg)) {
        vapply(out$obsrvtn_species_codes_upstr, function(x) {
          sp_upper %in% x
        }, logical(1))
      } else {
        rep(FALSE, nrow(out))
      }
      ifelse(blocked, 0L, ifelse(observed, 2L, 1L))
    }
  }

  # 5. Optional persistence. dbWriteTable doesn't natively serialize R
  # list-columns to Postgres arrays for CREATE-TABLE, so the wide
  # `streams_access` write keeps scalar per-species columns only
  # (`has_barriers_<sp>_dnstr`, `access_<sp>`). The barriers_<sp>_dnstr
  # / observation arrays themselves stay in-memory on the returned
  # tibble for callers that want them. Persistent array storage is a
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
