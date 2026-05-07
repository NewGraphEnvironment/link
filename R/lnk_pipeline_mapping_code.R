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
#' downstream is empty (i.e. accessible). Resident-flavor (BT, WCT) and
#' anadromous-flavor (CH/CM/CO/PK/SK/ST) differ in their CASE order:
#'   - Resident:    REMEDIATED > DAM > ASSESSED (anthropogenic + pscis +
#'                  no dam) > MODELLED (anthropogenic + no pscis + no
#'                  dam) > NONE (no anthropogenic).
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
#'   Mirrors bcfp's `streams_habitat_linear` shape.
#' @param feature_code Named character or data.frame. Either a named
#'   character vector mapping `segment_id` -> `feature_code`, or a
#'   data.frame with `segment_id_col` and `"feature_code"` columns.
#'   Used for the `INTERMITTENT` flag.
#' @param to Character or `NULL`. Optional schema-qualified destination
#'   table. When supplied, the result tibble is written via
#'   `dbWriteTable(overwrite = TRUE)` and the tibble is also returned
#'   (so callers can chain into `lnk_pipeline_persist` / `build_species_views.R`).
#'   Default `NULL` returns-only.
#' @param conn A [DBI::DBIConnection-class]. Required only when `to` is
#'   supplied; ignored otherwise.
#' @param resident_species Character. Species using the resident flavor
#'   of `mapping_code_barrier`. Default `c("bt", "wct")`.
#' @param anadromous_species Character. Species using the anadromous
#'   flavor. Default `c("ch", "cm", "co", "pk", "sk", "st")`.
#' @param spawn_only_species Character. Species without rearing
#'   semantics (token 1 only emits SPAWN, never REAR). Default
#'   `c("cm", "pk")`. Mirrors bcfp.
#' @param segment_id_col Character. Default `"id_segment"`.
#' @param intermittent_feature_code Character. The `feature_code` value
#'   that flags an intermittent stream. Default `"GA24850150"` (bcfp).
#'
#' @return A tibble keyed by `segment_id_col` with one
#'   `mapping_code_<sp>` character column per species in
#'   `union(resident_species, anadromous_species)`.
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
    resident_species = c("bt", "wct"),
    anadromous_species = c("ch", "cm", "co", "pk", "sk", "st"),
    spawn_only_species = c("cm", "pk"),
    segment_id_col = "id_segment",
    intermittent_feature_code = "GA24850150") {

  stopifnot(
    is.data.frame(access),
    is.data.frame(habitat),
    segment_id_col %in% names(access),
    segment_id_col %in% names(habitat),
    is.character(resident_species), is.character(anadromous_species),
    is.character(spawn_only_species),
    is.character(segment_id_col), length(segment_id_col) == 1L,
    is.character(intermittent_feature_code),
    length(intermittent_feature_code) == 1L
  )

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

  # Generic mapping_code_barrier helpers (resident vs anadromous flavors).
  na_to_false <- function(x) !is.na(x) & as.logical(x)
  has <- function(col) {
    if (col %in% names(access)) {
      na_to_false(access[[col]])
    } else {
      rep(FALSE, length(ids))
    }
  }
  any_anth <- has("has_barriers_anthropogenic_dnstr")
  any_pscis <- has("has_barriers_pscis_dnstr")
  # bcfp uses *different* dam-detection signals per flavor:
  #   - resident (mcbi_r): `dam_dnstr_ind` (sequence-aware, TRUE iff
  #     the next downstream barrier is a dam, not "any dam exists").
  #   - anadromous (mcbi_a): `barriers_dams_dnstr IS NOT NULL` (any
  #     dam exists downstream, regardless of barrier sequence).
  # When the access tibble doesn't carry `dam_dnstr_ind`, we fall back
  # to the presence-only signal for the resident flavor too -- it's
  # the best approximation we have without sequence-aware tracking.
  any_dam_resident <- if ("dam_dnstr_ind" %in% names(access)) {
    has("dam_dnstr_ind")
  } else {
    has("has_barriers_dams_dnstr")
  }
  any_dam_anadr <- has("has_barriers_dams_dnstr")
  any_remed <- if ("remediated_dnstr_ind" %in% names(access)) {
    has("remediated_dnstr_ind")
  } else {
    has("has_remediated_dnstr")
  }

  mc_barrier_resident <- rep(NA_character_, length(ids))
  mc_barrier_resident[any_remed] <- "REMEDIATED"
  mc_barrier_resident[is.na(mc_barrier_resident) & any_dam_resident] <- "DAM"
  mc_barrier_resident[is.na(mc_barrier_resident) &
                        any_anth & any_pscis & !any_dam_resident] <- "ASSESSED"
  mc_barrier_resident[is.na(mc_barrier_resident) &
                        any_anth & !any_pscis & !any_dam_resident] <- "MODELLED"
  mc_barrier_resident[is.na(mc_barrier_resident) & !any_anth] <- "NONE"

  mc_barrier_anadr <- rep(NA_character_, length(ids))
  mc_barrier_anadr[any_remed] <- "REMEDIATED"
  mc_barrier_anadr[is.na(mc_barrier_anadr) & any_dam_anadr] <- "DAM"
  mc_barrier_anadr[is.na(mc_barrier_anadr) & any_pscis] <- "ASSESSED"
  mc_barrier_anadr[is.na(mc_barrier_anadr) & any_anth] <- "MODELLED"
  mc_barrier_anadr[is.na(mc_barrier_anadr) & !any_anth] <- "NONE"

  out <- data.frame(stub = ids, stringsAsFactors = FALSE)
  names(out) <- segment_id_col
  out[[segment_id_col]] <- access[[segment_id_col]]

  all_species <- union(resident_species, anadromous_species)
  for (sp in all_species) {
    # When `presence` is supplied and the species is absent, emit ""
    # for every row and skip the per-row token construction. Avoids
    # the salmon-group-absent over-emission that the multi-WSG sweep
    # caught in ELKR + HORS (we'd otherwise emit ACCESS;X for segments
    # with no barriers downstream, even though the species isn't in
    # the WSG).
    if (!is.null(presence) && !isTRUE(presence$is_present(sp))) {
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

    spawning <- if (paste0("spawning_", sp) %in% names(habitat_aligned)) {
      habitat_aligned[[paste0("spawning_", sp)]]
    } else {
      rep(NA_real_, length(ids))
    }
    rearing <- if (paste0("rearing_", sp) %in% names(habitat_aligned)) {
      habitat_aligned[[paste0("rearing_", sp)]]
    } else {
      rep(NA_real_, length(ids))
    }

    # bcfp's `spawning < 1` evaluates to NULL when spawning is NULL,
    # which makes any AND-chain involving it short-circuit to NULL --
    # i.e. the surrounding CASE clause does not fire. Mirror that
    # with `!is.na(x) & x < 1` so an NA spawn/rear value falls through
    # to the next clause (or NA token1) instead of triggering ACCESS.
    spawning_pos <- !is.na(spawning) & spawning > 0
    rearing_pos <- !is.na(rearing) & rearing > 0
    spawning_zero <- !is.na(spawning) & spawning < 1
    rearing_zero <- !is.na(rearing) & rearing < 1

    is_spawn_only <- sp %in% spawn_only_species

    if (is_spawn_only) {
      token1 <- ifelse(accessible & spawning_zero, "ACCESS",
                       ifelse(spawning_pos, "SPAWN", NA_character_))
    } else {
      token1 <- ifelse(accessible & spawning_zero & rearing_zero, "ACCESS",
                       ifelse(spawning_pos, "SPAWN",
                              ifelse(spawning_zero & rearing_pos, "REAR",
                                     NA_character_)))
    }

    mc_barrier <- if (sp %in% resident_species) {
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
