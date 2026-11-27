#' Build per-segment per-species mapping_code strings (bcfp parity)
#'
#' Mirrors `bcfishpass.streams_mapping_code` -- a per-segment per-species
#' semicolon-token compound describing the segment's habitat label, the
#' most-relevant downstream barrier source, and an intermittent flag if
#' applicable. Pure derivation over the bcfp-shape inputs (no SQL).
#'
#' Vocabulary (per species):
#'
#' \preformatted{
#' {ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED|REMEDIATED} [;INTERMITTENT]
#' }
#'
#' Token 1 (habitat) per bcfp:
#'   - `ACCESS`: species' barriers all upstream (i.e. accessible to
#'     species) AND segment has no spawning AND no rearing eligibility
#'     for the species
#'   - `SPAWN`: spawning eligibility > 0 (always wins over REAR)
#'   - `REAR`: rearing eligibility > 0 AND no spawning
#'   - `""` (empty): species has at least one downstream barrier blocking
#'     it (so habitat label is suppressed -- inaccessible).
#'   - For species without rearing semantics (CM, PK), the rearing
#'     conditions drop out -- only `ACCESS` (no spawn, no barriers) and
#'     `SPAWN` (spawning > 0) emit.
#'
#' Token 2 (barrier source) only emits when the species' barriers
#' downstream is empty (i.e. accessible). It comes from the bundle's
#' `parameters_mapping_code_rules.csv` (link#197): per residence, rows in
#' `precedence` order, first matching `when` wins, so a bundle adds or reorders
#' a token with no code change. A bundle that declares no file, or a call with
#' no `cfg`, reads the package copy, bcfishpass's order. Resident and
#' anadromous species differ there in their CASE order:
#'   - Resident:    REMEDIATED > DAM (the next barrier down is a dam) >
#'                  ASSESSED (anthropogenic + pscis + no dam) > MODELLED
#'                  (anthropogenic + no pscis + no dam) > NONE.
#'   - Anadromous:  REMEDIATED > DAM (any dam) > ASSESSED (any pscis) >
#'                  MODELLED (any anthropogenic) > NONE.
#'
#' Token 3 emits `INTERMITTENT` when the segment's `feature_code` matches
#' the bcfp intermittent code (default `"GA24850150"`) AND the species'
#' barriers downstream is empty.
#'
#' Empty / NULL tokens are dropped via `paste(..., collapse = ";")`-style
#' composition so an inaccessible segment yields `""` (empty string) and
#' an accessible no-habitat-no-intermittent segment yields `"ACCESS;NONE"`.
#'
#' @param access A tibble or data.frame keyed by `segment_id_col` with
#'   `has_barriers_<sp>_dnstr` boolean per species, plus the bcfp-shape
#'   sources `has_barriers_anthropogenic_dnstr`,
#'   `has_barriers_pscis_dnstr`, `has_barriers_dams_dnstr`, and (optional)
#'   `has_remediated_dnstr`. Typically the output of
#'   [lnk_pipeline_access()] called with `barrier_sources` populated.
#' @param habitat A tibble keyed by `segment_id_col` with
#'   `spawning_<sp>` and `rearing_<sp>` numeric columns per species.
#'   Mirrors bcfp's `streams_habitat_linear` shape. A species with no
#'   `spawning_<sp>` or `rearing_<sp>` column reads 0 there, as bcfishpass
#'   pre-allocates every species' columns (link#153); a segment with no
#'   habitat row at all still reads `NA`.
#' @param feature_code Named character or data.frame. Either a named
#'   character vector mapping `segment_id` -> `feature_code`, or a
#'   data.frame with `segment_id_col` and `"feature_code"` columns.
#'   Used for the `INTERMITTENT` flag.
#' @param to Character or `NULL`. Optional schema-qualified destination
#'   table. When supplied, the result tibble is written via
#'   `dbWriteTable(overwrite = TRUE)` and the tibble is also returned
#'   (so callers can chain into `lnk_persist_write` / `build_species_views.R`).
#'   Default `NULL` returns-only.
#' @param conn A [DBI::DBIConnection-class]. Required only when `to` is
#'   supplied; ignored otherwise.
#' @param species_resident Character or `NULL`. Species using the resident
#'   flavor of `mapping_code_barrier`. `NULL` (the default) takes the
#'   bundle's resident species from `cfg` (its `dimensions.csv` `residence`
#'   column, link#512), or `c("bt", "wct")` with no `cfg`. With `cfg`, the sets
#'   cover every species the bundle models (`cfg$species`); a persisted build
#'   codes only the group's active ones.
#' @param species_anadromous Character or `NULL`. Species using the
#'   anadromous flavor: from `cfg` as above, or
#'   `c("ch", "cm", "co", "pk", "sk", "st")` with no `cfg`. A species in both
#'   sets is refused.
#' @param species_spawn_only Character or `NULL`. Species without rearing
#'   semantics (token 1 only emits SPAWN, never REAR): from `cfg`
#'   (`rear_no_fw = yes`), or `c("cm", "pk")` with no `cfg`. Mirrors bcfp.
#' @param presence `NULL` (the default), an `lnk_presence` object, or a named
#'   logical vector keyed by lower-case species code (link#351). A species it
#'   marks absent, or does not name, emits `""` in its token column; with
#'   `NULL` every species is coded.
#' @param segment_id_col Character. Default `"id_segment"`.
#' @param intermittent_feature_code Character. The `feature_code` value
#'   that flags an intermittent stream. Default `"GA24850150"` (bcfp).
#' @param cfg An [lnk_config()] object, or `NULL`. Supplies the residence sets
#'   not passed and the mapping-code rules (`parameters_mapping_code_rules`
#'   under `files:`).
#' @param rules_mapping_code A data frame of mapping-code rules (`residence`,
#'   `precedence`, `token`, `when`), or `NULL` to read them from `cfg`, else
#'   the package copy.
#'
#' @return A tibble keyed by `segment_id_col` with one
#'   `mapping_code_<sp>` character column per species in
#'   `union(species_resident, species_anadromous)`.
#'
#' @family pipeline
#'
#' @export
lnk_pipeline_mapping_code <- function(
    access,
    habitat,
    feature_code,
    to = NULL,
    conn = NULL,
    presence = NULL,
    species_resident = NULL,
    species_anadromous = NULL,
    species_spawn_only = NULL,
    segment_id_col = "id_segment",
    intermittent_feature_code = "GA24850150",
    cfg = NULL,
    rules_mapping_code = NULL) {

  stopifnot(
    is.data.frame(access),
    is.data.frame(habitat),
    segment_id_col %in% names(access),
    segment_id_col %in% names(habitat),
    is.character(segment_id_col), length(segment_id_col) == 1L,
    is.character(intermittent_feature_code),
    length(intermittent_feature_code) == 1L
  )

  sets <- .lnk_mc_species(cfg, species_resident, species_anadromous,
                          species_spawn_only)
  species_resident   <- sets$resident
  species_anadromous <- sets$anadromous
  species_spawn_only <- sets$spawn_only
  rules <- .lnk_mc_rules(cfg, rules_mapping_code)

  # Normalise feature_code into a named character vector keyed by
  # segment_id.
  fc_lookup <- if (is.data.frame(feature_code)) {
    setNames(
      as.character(feature_code$feature_code),
      as.character(feature_code[[segment_id_col]])
    )
  } else if (is.character(feature_code) && !is.null(names(feature_code))) {
    feature_code
  } else {
    stop("`feature_code` must be a named character vector or a ",
         "data.frame with segment_id_col + 'feature_code' columns.",
         call. = FALSE)
  }

  # Align habitat + feature_code to access's segment order. left-join
  # behaviour: any access segment without a habitat row gets NA; any
  # without a feature_code lookup gets NA.
  ids <- as.character(access[[segment_id_col]])
  habitat_aligned <- habitat[match(ids, as.character(habitat[[segment_id_col]])), , drop = FALSE]
  fc <- fc_lookup[ids]

  is_intermittent <- !is.na(fc) & fc == intermittent_feature_code

  present_fn <- .lnk_presence_fn(presence)
  has_row <- !is.na(match(ids, as.character(habitat[[segment_id_col]])))

  # Token 2 per residence, from the rules (link#197).
  alias <- .lnk_mc_alias_values(access)
  mc_barrier_resident <- .lnk_mc_rules_eval(rules, alias, "resident")
  mc_barrier_anadr    <- .lnk_mc_rules_eval(rules, alias, "anadromous")

  out <- data.frame(stub = ids, stringsAsFactors = FALSE)
  names(out) <- segment_id_col
  out[[segment_id_col]] <- access[[segment_id_col]]

  all_species <- union(species_resident, species_anadromous)
  for (sp in all_species) {
    # When `presence` is supplied and the species is absent, emit ""
    # for every row and skip the per-row token construction. Avoids
    # the salmon-group-absent over-emission that the multi-WSG sweep
    # caught in ELKR + HORS (we'd otherwise emit ACCESS;X for segments
    # with no barriers downstream, even though the species isn't in
    # the WSG).
    if (!is.null(present_fn) && !isTRUE(present_fn(sp))) {
      out[[paste0("mapping_code_", sp)]] <- rep("", length(ids))
      next
    }

    has_col <- paste0("has_barriers_", sp, "_dnstr")
    has_barriers_raw <- if (has_col %in% names(access)) access[[has_col]] else FALSE
    # When `has_barriers_<sp>_dnstr` is NA for a row, bcfp's
    # `barriers_<sp>_dnstr IS NULL` clause path is the equivalent --
    # emit "" (no token1/2/3) for that segment. We track per-row.
    no_data <- is.na(has_barriers_raw)
    has_barriers_sp <- !is.na(has_barriers_raw) & as.logical(has_barriers_raw)
    accessible <- !has_barriers_sp & !no_data

    # A species with no habitat column reads 0 (bcfishpass pre-allocates every
    # species' columns, link#153); a segment with no habitat row stays NA.
    hab_col <- function(col) {
      if (col %in% names(habitat_aligned)) habitat_aligned[[col]]
      else ifelse(has_row, 0, NA_real_)
    }
    spawning <- hab_col(paste0("spawning_", sp))
    rearing  <- hab_col(paste0("rearing_", sp))

    # bcfp's `spawning < 1` evaluates to NULL when spawning is NULL,
    # which makes any AND-chain involving it short-circuit to NULL --
    # i.e. the surrounding CASE clause does not fire. Mirror that
    # with `!is.na(x) & x < 1` so an NA spawn/rear value falls through
    # to the next clause (or NA token1) instead of triggering ACCESS.
    spawning_pos <- !is.na(spawning) & spawning > 0
    rearing_pos <- !is.na(rearing) & rearing > 0
    spawning_zero <- !is.na(spawning) & spawning < 1
    rearing_zero <- !is.na(rearing) & rearing < 1

    is_spawn_only <- sp %in% species_spawn_only

    if (is_spawn_only) {
      token1 <- ifelse(accessible & spawning_zero, "ACCESS",
                       ifelse(spawning_pos, "SPAWN", NA_character_))
    } else {
      token1 <- ifelse(accessible & spawning_zero & rearing_zero, "ACCESS",
                       ifelse(spawning_pos, "SPAWN",
                              ifelse(spawning_zero & rearing_pos, "REAR",
                                     NA_character_)))
    }

    mc_barrier <- if (sp %in% species_resident) {
      mc_barrier_resident
    } else {
      mc_barrier_anadr
    }
    token2 <- ifelse(accessible, mc_barrier, NA_character_)
    token3 <- ifelse(accessible & is_intermittent, "INTERMITTENT", NA_character_)

    out[[paste0("mapping_code_", sp)]] <- vapply(
      seq_along(ids),
      function(i) {
        if (isTRUE(no_data[i])) return("")
        toks <- c(token1[i], token2[i], token3[i])
        toks <- toks[!is.na(toks)]
        paste(toks, collapse = ";")
      },
      character(1)
    )
  }

  if (!is.null(to)) {
    if (is.null(conn) || !inherits(conn, "DBIConnection")) {
      stop("`to` requires a DBI connection in `conn`.", call. = FALSE)
    }
    schema_table <- strsplit(to, "\\.", fixed = FALSE)[[1]]
    target <- if (length(schema_table) == 2L) {
      DBI::Id(schema = schema_table[1], table = schema_table[2])
    } else {
      to
    }
    DBI::dbWriteTable(conn, target, out, overwrite = TRUE)
  }

  tibble::as_tibble(out)
}


#' A presence test from what `presence` was given
#'
#' `NULL` stays `NULL` (every species coded); an `lnk_presence` object gives its
#' `is_present`; a named logical vector gives a test of its `TRUE` names
#' (link#351: [lnk_mapping_code()] derives one when it is given none).
#'
#' @noRd
.lnk_presence_fn <- function(presence) {
  if (is.null(presence)) return(NULL)
  if (is.list(presence) && is.function(presence$is_present)) {
    return(presence$is_present)
  }
  if (is.logical(presence) && !is.null(names(presence))) {
    present <- tolower(names(presence))[!is.na(presence) & presence]
    return(function(sp) tolower(sp) %in% present)
  }
  stop("`presence` must be NULL, an lnk_presence object, or a named logical ",
       "vector", call. = FALSE)
}
