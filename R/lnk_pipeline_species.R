#' Resolve the Species Set for an AOI
#'
#' The species the config classifies, filtered to those present in the
#' AOI. Used by [lnk_pipeline_classify()] and [lnk_pipeline_connect()]
#' to pick which species to run, and exposed for callers that need to
#' derive the same list outside the pipeline (e.g. a custom
#' `compare_bcfishpass_wsg()` that queries bcfishpass reference tables
#' only for these species).
#'
#' The returned set is the intersection of:
#'
#'   - `cfg$species` — species the rules YAML classifies (parsed at
#'     `lnk_config()` load time)
#'   - species flagged present for `aoi` in `cfg$wsg_species` — the
#'     wide-form presence table where each species column (`bt`, `ch`,
#'     `cm`, ...) holds `"t"` for present and `"f"` for absent
#'
#' When `cfg$wsg_species` is not populated the function returns
#' `cfg$species` unfiltered. When the AOI is not found in the table
#' the function returns `character(0)`.
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param aoi Character. AOI identifier — today a watershed group code
#'   (e.g. `"BULK"`) matched against `cfg$wsg_species$watershed_group_code`.
#'
#' @return Character vector of species codes. Empty when neither
#'   config nor AOI carries species.
#'
#' @family pipeline
#'
#' @export
#'
#' @examples
#' cfg <- lnk_config("bcfishpass")
#' lnk_pipeline_species(cfg, "BULK")
#' lnk_pipeline_species(cfg, "ADMS")
lnk_pipeline_species <- function(cfg, aoi) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
    stop("aoi must be a single non-empty string", call. = FALSE)
  }

  configured <- cfg$species %||% unique(cfg$parameters_fresh$species_code)

  wsg_sp <- cfg$wsg_species
  if (is.null(wsg_sp)) return(configured)

  row <- wsg_sp[wsg_sp$watershed_group_code == aoi, ]
  if (nrow(row) == 0) return(character(0))

  spp_cols <- c("bt", "ch", "cm", "co", "ct", "dv",
                "pk", "rb", "sk", "st", "wct")
  present <- vapply(spp_cols,
    function(x) identical(row[[x]], "t"), logical(1))
  aoi_species <- toupper(spp_cols[present])

  intersect(configured, aoi_species)
}
