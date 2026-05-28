#' Resolve the Set of Watershed Groups to Model
#'
#' Bundle-aware WSG resolver. Given a config + loaded overrides and an
#' optional focal set, returns the character vector of WSG codes that
#' should be modelled — composing FWA drainage closure (via
#' [fresh::frs_wsg_drainage()]) with the bundle's species-presence
#' filter (link#157).
#'
#' Three call patterns dispatched by `wsgs` + `expand`:
#'
#'   - `wsgs = NULL` — *province mode*: every WSG in
#'     `loaded$wsg_species_presence` that has at least one of
#'     `cfg$species` flagged present.
#'   - `wsgs = c(...)` + `expand = TRUE` (default) — *closure mode*:
#'     expand the focal set to its drainage closure (focal + every WSG
#'     they flow through, ordered downstream-first), then species-filter.
#'     Requires a DB connection — pass `conn` explicitly, or one is
#'     opened from [lnk_db_conn()] (defaults to env-var-driven) and
#'     closed on exit.
#'   - `wsgs = c(...)` + `expand = FALSE` — *strict mode*: species-filter
#'     the input verbatim, no closure expansion, no DB.
#'
#' Species filter: a WSG is kept if *any* of `tolower(cfg$species)`
#' columns in `loaded$wsg_species_presence` carries `"t"` (or `"TRUE"` /
#' `TRUE`, defensively). DS-first ordering from the closure is preserved.
#'
#' @param cfg An `lnk_config` object from [lnk_config()].
#' @param loaded Named list of tibbles from [lnk_load_overrides()].
#'   Must carry `wsg_species_presence`.
#' @param wsgs Character vector of focal WSG codes, or `NULL` (default)
#'   for province mode. Codes are upper-cased internally before use.
#' @param expand Logical. When `wsgs` is non-`NULL`, `TRUE` (default)
#'   closure-expands via [fresh::frs_wsg_drainage()]; `FALSE` uses the
#'   input as-is (species-filter only).
#' @param conn Optional [DBI::DBIConnection-class]. Only used in closure
#'   mode (`wsgs` non-`NULL` and `expand = TRUE`). When `NULL` (default),
#'   one is opened via [lnk_db_conn()] (env-var-driven) and closed on
#'   exit. Pass an explicit conn to control the target DB (e.g. local
#'   docker fwapg vs an env-pinned tunnel) — recommended in scripts.
#'
#' @return Character vector of WSG codes. Province mode returns the
#'   species-filtered set sorted alphabetically; closure mode preserves the
#'   downstream-first order from [fresh::frs_wsg_drainage()]; strict mode
#'   preserves the caller-provided focal order. WSGs dropped by the
#'   species filter (closure / strict modes) are reported via `message()`.
#'
#' @family wsg
#'
#' @export
#'
#' @examples
#' \dontrun{
#' cfg    <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#'
#' # Province mode — all bundle-species WSGs
#' lnk_wsg_resolve(cfg, loaded)
#'
#' # Study-area mode — focal + drainage closure (default)
#' lnk_wsg_resolve(cfg, loaded, wsgs = c("PARS", "BULK"))
#' #> [1] "KISP" "KLUM" "LKEL" "LSKE" "MSKE" "USKE" "BULK" "FINA"
#' #>     "LBTN" "LPCE" "MORR" "PARA" "PCEA" "UPCE" "PARS"
#'
#' # Strict mode — exactly these, species-filtered, no closure
#' lnk_wsg_resolve(cfg, loaded, wsgs = c("BBAR", "BULK"), expand = FALSE)
#' }
lnk_wsg_resolve <- function(cfg, loaded, wsgs = NULL, expand = TRUE,
                            conn = NULL) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object (from lnk_config())",
         call. = FALSE)
  }
  if (!is.list(loaded)) {
    stop("loaded must be a named list (from lnk_load_overrides())",
         call. = FALSE)
  }
  if (!is.null(wsgs)) {
    bad <- !is.character(wsgs) || length(wsgs) == 0L ||
      anyNA(wsgs) || !all(nzchar(wsgs))
    if (bad) {
      stop("wsgs must be NULL or a non-empty character vector free of NA",
           call. = FALSE)
    }
  }
  if (!is.logical(expand) || length(expand) != 1L || is.na(expand)) {
    stop("expand must be a single logical (TRUE or FALSE)", call. = FALSE)
  }

  wp <- loaded$wsg_species_presence
  if (is.null(wp) || !nrow(wp)) {
    stop("loaded$wsg_species_presence is missing or empty — ",
         "did `lnk_load_overrides(cfg)` populate it?", call. = FALSE)
  }
  spp_cols <- tolower(cfg$species %||%
                        unique(loaded$parameters_fresh$species_code))
  missing_cols <- setdiff(spp_cols, names(wp))
  if (length(missing_cols)) {
    stop("loaded$wsg_species_presence missing species columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  has_spp <- apply(wp[, spp_cols, drop = FALSE], 1,
                   function(r) any(r %in% c("t", "TRUE", TRUE)))
  modelable <- wp$watershed_group_code[has_spp]

  # Province mode --------------------------------------------------------
  if (is.null(wsgs)) return(sort(modelable))

  focal <- toupper(wsgs)

  # Strict mode ----------------------------------------------------------
  if (!expand) {
    kept <- focal[focal %in% modelable]
    dropped <- setdiff(focal, kept)
    if (length(dropped)) {
      message("lnk_wsg_resolve: dropped ", length(dropped),
              " species-less WSG(s): ", paste(dropped, collapse = ", "))
    }
    return(kept)
  }

  # Closure mode ---------------------------------------------------------
  if (is.null(conn)) {
    conn <- lnk_db_conn()
    on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
  }
  closure <- fresh::frs_wsg_drainage(conn, focal)
  # Preserve DS-first order from frs_wsg_drainage by indexing closure,
  # not the modelable set
  kept <- closure[closure %in% modelable]
  dropped <- setdiff(closure, kept)
  if (length(dropped)) {
    message("lnk_wsg_resolve: dropped ", length(dropped),
            " species-less closure WSG(s): ", paste(dropped, collapse = ", "))
  }
  kept
}
