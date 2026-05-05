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
    is.character(segment_id_col), length(segment_id_col) == 1L
  )

  # 1. Per-species downstream-barrier arrays via fresh's primitive.
  dnstr_per_sp <- list()
  for (sp in names(barriers_per_sp)) {
    barriers_tbl <- barriers_per_sp[[sp]]
    sp_id_col <- paste0("barriers_", sp, "_id")

    df <- fresh::frs_network_features(
      conn,
      segments       = segments,
      features       = barriers_tbl,
      segment_id_col = segment_id_col,
      feature_id_col = sp_id_col,
      direction      = "downstream",
      aoi            = aoi,
      include_equivalents = TRUE
    )
    names(df)[2] <- paste0("barriers_", sp, "_dnstr")
    dnstr_per_sp[[sp]] <- df
  }

  # 2. Upstream observations (optional). Returns one row per segment
  # with array of observation_key values upstream of it. Then a
  # second-pass query computes the species_code array for the same
  # observation set — that's what bcfp uses for the access integer code.
  obs_upstr <- NULL
  obsrvtn_species_per_seg <- NULL
  if (!is.null(observations)) {
    obs_upstr <- fresh::frs_network_features(
      conn,
      segments       = segments,
      features       = observations,
      segment_id_col = segment_id_col,
      feature_id_col = "observation_key",
      direction      = "upstream",
      aoi            = aoi,
      include_equivalents = TRUE
    )
    names(obs_upstr)[2] <- "observation_key_upstr"

    # Same shape but emit species_code instead of observation_key.
    obsrvtn_species_per_seg <- fresh::frs_network_features(
      conn,
      segments       = segments,
      features       = observations,
      segment_id_col = segment_id_col,
      feature_id_col = "species_code",
      direction      = "upstream",
      aoi            = aoi,
      include_equivalents = TRUE
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

  # NOTE: fresh's `frs_network_features` returns array columns as
  # RPostgres-native `pq__text` (Postgres array literals like
  # `"{a,b,c}"`), not R list-columns. Parsing those into R character
  # vectors is a fresh follow-up. For this commit we use SET
  # MEMBERSHIP — the function's INNER-JOIN semantics mean a segment
  # with zero matches is absent from the result tibble entirely, so
  # `segment_id %in% dnstr_tibble$segment_id` is sufficient to derive
  # the integer access code without parsing the arrays themselves.

  out <- segments_aoi
  for (sp in names(dnstr_per_sp)) {
    blocked <- out[[segment_id_col]] %in% dnstr_per_sp[[sp]][[segment_id_col]]
    out[[paste0("has_barriers_", sp, "_dnstr")]] <- blocked
  }
  if (!is.null(obs_upstr)) {
    out[["has_observation_key_upstr"]] <-
      out[[segment_id_col]] %in% obs_upstr[[segment_id_col]]
    # Map segment_id -> the species-codes pq__text string for
    # later `grepl` checks (avoids parsing the array, just substring-
    # matches the species code in the literal). Coarse but works for
    # uppercase 2-3-letter species codes that don't appear inside
    # other tokens.
    sp_lookup <- setNames(
      as.character(obsrvtn_species_per_seg[[2]]),
      as.character(obsrvtn_species_per_seg[[segment_id_col]])
    )
    out[["obsrvtn_species_lit"]] <- unname(sp_lookup[as.character(out[[segment_id_col]])])
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
      observed <- if (!is.null(obs_upstr)) {
        # Substring-match the species code inside the array literal —
        # `pq__text` looks like `{BT,CO,SK}`. Use regex word-boundary
        # to avoid matching e.g. "CT" inside "WCT".
        lit <- out[["obsrvtn_species_lit"]]
        !is.na(lit) & grepl(sprintf("(^|[\\{,])%s($|[,\\}])", sp_upper), lit)
      } else {
        rep(FALSE, nrow(out))
      }
      ifelse(blocked, 0L, ifelse(observed, 2L, 1L))
    }
  }

  # 5. Optional persistence. dbWriteTable doesn't natively serialize
  # R list-columns to Postgres arrays for CREATE-TABLE — first commit
  # focuses on correctness of access_<sp> integer codes; array
  # persistence is a follow-up that needs a manual pg_array codec.
  # Drops list-columns when writing.
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
