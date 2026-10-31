#' Screen fish records for plausibility before they count as evidence
#'
#' Reads per-record features, built in SQL by
#' `data-raw/wsg_species_presence_check.R`, against per-species thresholds,
#' and gives each record a verdict: `fail` (likely an error), `doubt`
#' (possible error, read with the cell's other records) or `pass`, with the
#' reasons that set it. A record fails when:
#' - its UTM zone disagrees with the zone of its own longitude (`utm_zone`),
#'   a transcription error;
#' - it sits higher than the species' elevation ceiling (`elevation`);
#' - it sits on a segment at or above the species' gradient ceiling
#'   (`gradient`);
#' - it is of an anadromous species, above an unlifted natural barrier that
#'   blocks the species, with no more than `lone_max` records of the species
#'   above that barrier and no historical distribution zone of the species on
#'   its stream (`above_barrier_lone`);
#' - it is a kokanee above an unlifted natural barrier with no lake of at
#'   least `lake_ha_min` above that barrier to rear in
#'   (`above_barrier_no_lake`).
#'
#' A record is in doubt when its location is weak (matched to the closest
#' stream, `match_letter` B or E, on a stream whose 50k code is not the
#' record's own; or farther than `distance_max_m` from the stream:
#' `location`), when no other record of the species lies within
#' `isolation_km` (`isolated`), or when it is anadromous and above an
#' unlifted natural barrier with more than `lone_max` records above it
#' (`above_barrier`). Residents (`anadromous` FALSE) above a barrier are not
#' screened for it: resident populations above falls are the norm.
#'
#' A missing feature never fails a record: the screen it feeds reads as not
#' tested.
#'
#' @param x Data frame, one row per record, with `observation_key`,
#'   `species_code`, `match_letter`, `distance_to_stream`, `code50_record`,
#'   `code50_stream` (50k watershed codes as digits, trailing zeros
#'   trimmed), `utm_zone`, `longitude`, `elevation_m`, `gradient`,
#'   `barrier_below` (kind of the nearest unlifted natural barrier below
#'   that blocks the species, NA where none), `n_above_barrier` (records of
#'   the species above that barrier), `rearing_lake_ha` (largest lake above
#'   that barrier), `in_hist_zone` (the record's stream lies in a historical
#'   distribution zone of the species) and `nearest_same_km`.
#' @param params Data frame, one row per species, with `species_code`,
#'   `anadromous`, `elevation_max_m`, `gradient_max`, `distance_max_m`,
#'   `isolation_km`, `lone_max` and `lake_ha_min`. A species with no row is
#'   screened on location and UTM zone only.
#' @return `x` with `screen` (`pass`, `doubt`, `fail`) and `screen_reasons`
#'   (reasons joined by `;`, empty for a pass).
#' @noRd
.lnk_obs_screen <- function(x, params) {
  need <- c("observation_key", "species_code", "match_letter",
            "distance_to_stream", "code50_record", "code50_stream",
            "utm_zone", "longitude", "elevation_m", "gradient",
            "barrier_below", "n_above_barrier", "rearing_lake_ha",
            "in_hist_zone", "nearest_same_km")
  miss <- setdiff(need, names(x))
  if (length(miss) > 0L) {
    stop("x lacks columns: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  pneed <- c("species_code", "anadromous", "elevation_max_m", "gradient_max",
             "distance_max_m", "isolation_km", "lone_max", "lake_ha_min")
  pmiss <- setdiff(pneed, names(params))
  if (length(pmiss) > 0L) {
    stop("params lacks columns: ", paste(pmiss, collapse = ", "),
         call. = FALSE)
  }
  if (anyDuplicated(params$species_code) > 0L) {
    stop("params has more than one row for a species", call. = FALSE)
  }

  p <- params[match(x$species_code, params$species_code), , drop = FALSE]
  yes <- function(v) !is.na(v) & v

  zone_lon <- floor((x$longitude + 180) / 6) + 1
  f_zone <- yes(!is.na(x$utm_zone) & x$utm_zone != zone_lon)
  f_elev <- yes(x$elevation_m > p$elevation_max_m)
  f_grad <- yes(x$gradient >= p$gradient_max)

  above <- !is.na(x$barrier_below) & nzchar(x$barrier_below)
  anad <- yes(as.logical(p$anadromous))
  lone <- yes(x$n_above_barrier <= p$lone_max)
  zoned <- yes(as.logical(x$in_hist_zone))
  f_lone <- above & anad & lone & !zoned
  is_ko <- x$species_code == "KO"
  f_lake <- above & is_ko &
    (is.na(x$rearing_lake_ha) | yes(x$rearing_lake_ha < p$lake_ha_min))

  closest <- x$match_letter %in% c("B", "E")
  code_off <- !is.na(x$code50_record) & !is.na(x$code50_stream) &
    nzchar(x$code50_record) & nzchar(x$code50_stream) &
    x$code50_record != x$code50_stream
  d_loc <- (closest & code_off) |
    yes(x$distance_to_stream > p$distance_max_m)
  d_iso <- yes(x$nearest_same_km > p$isolation_km)
  d_above <- above & anad & !lone & !zoned

  reasons <- cbind(
    utm_zone = f_zone, elevation = f_elev, gradient = f_grad,
    above_barrier_lone = f_lone, above_barrier_no_lake = f_lake,
    location = d_loc, isolated = d_iso, above_barrier = d_above
  )
  fails <- c("utm_zone", "elevation", "gradient", "above_barrier_lone",
             "above_barrier_no_lake")
  x$screen <- ifelse(rowSums(reasons[, fails, drop = FALSE]) > 0L, "fail",
                     ifelse(rowSums(reasons) > 0L, "doubt", "pass"))
  x$screen_reasons <- vapply(seq_len(nrow(x)), function(i) {
    paste(colnames(reasons)[reasons[i, ]], collapse = ";")
  }, character(1))
  x
}
