#' Per-AOI species presence with bcfp species-group expansion
#'
#' Reads a single AOI's row from a `wsg_species_presence` tibble and
#' returns structured presence info: the per-species TRUE/FALSE flags
#' from the row, expanded by user-supplied species groups so that "any
#' group member present" promotes the whole group to present. Mirrors
#' bcfp's `wsg_salmon` / `wsg_ct_dv_rb` JOIN logic in
#' `load_streams_access.sql` — useful as input to per-species pipeline
#' loops that should skip absent species.
#'
#' Coexists with [lnk_pipeline_species()], which returns the
#' intersection of `cfg$species` with AOI-present species as a plain
#' vector. `lnk_presence()` is the structured / group-aware sibling.
#'
#' @param wsg_species_presence Data frame or tibble matching the
#'   `loaded$wsg_species_presence` shape (per [lnk_load_overrides()]):
#'   `watershed_group_code`, then per-species columns (`bt`, `ch`, ...),
#'   plus optional `notes`. Values may be character (`"t"`/`""`/`NA`,
#'   the CSV-bundled form) or logical (`TRUE`/`FALSE`/`NA`, the
#'   PostgreSQL form). `notes` and `watershed_group_code` are excluded
#'   from the species list.
#' @param aoi Character. Watershed group code (e.g. `"ADMS"`).
#' @param groups Named list of character vectors. Each name is a group
#'   tag (e.g. `"salmon"`); each value lists species codes that share
#'   group-presence semantics. Default mirrors bcfp:
#'   - `salmon = c("ch", "cm", "co", "pk", "sk")`
#'   - `ct_dv_rb = c("ct", "dv", "rb")`
#'
#'   A species in a group is reported present iff **any** group member
#'   is present in the AOI row. Pass `list()` to disable expansion.
#'
#' @return A list with:
#'   - `aoi`: echo of input.
#'   - `row`: the raw 1-row tibble for `aoi`.
#'   - `present`: character vector of species codes present after
#'     group expansion.
#'   - `absent`: character vector of species codes not present.
#'   - `is_present(sp)`: vectorised function returning `TRUE` for
#'     species in `present`.
#'
#' @family pipeline
#'
#' @export
#'
#' @examples
#' \dontrun{
#' loaded <- lnk_load_overrides(lnk_config("default_extrabreaks"))
#'
#' # ADMS — BT + salmon-group + ct_dv_rb-group present.
#' pres <- lnk_presence(loaded$wsg_species_presence, "ADMS")
#' pres$present                           # bt, ch, co, sk + cm, pk (group-expanded)
#' pres$absent                            # st, wct, gr, ko
#' pres$is_present(c("bt", "st", "cm"))   # TRUE FALSE TRUE
#'
#' # ELKR — salmon all NULL, no group expansion fires.
#' pres <- lnk_presence(loaded$wsg_species_presence, "ELKR")
#' pres$is_present("ch")                  # FALSE
#'
#' # Disable group expansion.
#' pres <- lnk_presence(loaded$wsg_species_presence, "ADMS",
#'                      groups = list())
#' pres$is_present("cm")                  # FALSE (only literal cm column matters)
#' }
lnk_presence <- function(
    wsg_species_presence,
    aoi,
    groups = list(
      salmon   = c("ch", "cm", "co", "pk", "sk"),
      ct_dv_rb = c("ct", "dv", "rb")
    )) {

  stopifnot(
    is.data.frame(wsg_species_presence),
    "watershed_group_code" %in% names(wsg_species_presence),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.list(groups)
  )

  row <- wsg_species_presence[
                              wsg_species_presence$watershed_group_code == aoi,
                              , drop = FALSE]
  if (nrow(row) == 0L) {
    known <- sort(unique(wsg_species_presence$watershed_group_code))
    stop(sprintf("AOI '%s' not in wsg_species_presence -- known WSGs: %s",
                 aoi, paste(known, collapse = ", ")),
         call. = FALSE)
  }
  if (nrow(row) > 1L) {
    stop(sprintf("AOI '%s' matched %d rows in wsg_species_presence -- expected 1",
                 aoi, nrow(row)),
         call. = FALSE)
  }

  species_cols <- setdiff(names(wsg_species_presence),
                          c("watershed_group_code", "notes"))

  raw_present <- vapply(species_cols, function(sp) {
    .lnk_presence_truthy(row[[sp]])
  }, logical(1))
  names(raw_present) <- species_cols

  for (grp_name in names(groups)) {
    grp_in_cols <- intersect(groups[[grp_name]], species_cols)
    if (length(grp_in_cols) == 0L) next
    if (any(raw_present[grp_in_cols])) {
      raw_present[grp_in_cols] <- TRUE
    }
  }

  present <- names(raw_present)[raw_present]
  absent  <- names(raw_present)[!raw_present]

  list(
    aoi = aoi,
    row = row,
    present = present,
    absent = absent,
    is_present = function(sp) sp %in% present
  )
}

# Internal: coerce a presence-cell value to logical. Accepts both the
# CSV-loaded character form ("t" / "" / NA) and the PostgreSQL-loaded
# logical form (TRUE / FALSE / NA).
.lnk_presence_truthy <- function(x) {
  if (length(x) == 0L) return(FALSE)
  if (is.logical(x)) return(!is.na(x) && isTRUE(x))
  if (is.character(x)) {
    return(!is.na(x) && tolower(x) %in% c("t", "true", "yes", "1"))
  }
  FALSE
}
