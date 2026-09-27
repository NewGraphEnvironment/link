#' Resolve which observation species count as each model species, per WSG
#'
#' Reads a bundle's pooling tracker (`species_pooling.csv`) and species
#' groups (`species_groups.csv`) and returns, for each watershed group in
#' `aoi` and each model species present there, the observation species
#' whose records count as evidence for it. The tool knows nothing about any
#' particular species: pooling Dolly Varden records into bull trout, or all
#' salmon together, is a row in the tracker.
#'
#' A tracker row is `species_code` (the model species or a group of them),
#' `species_obs` (the observation species or a group), `scope_level`
#' (`region`, `subregion` or `wsg`), `scope` (a name in
#' `inst/extdata/wsg_regions.csv`, or a WSG code) and `pool` (`yes` / `no`).
#' Other columns (`confidence`, `rationale`, `source`, `verified`, `issue`)
#' are the record of why, and are not read here.
#'
#' For each WSG, target and observation species pair, the applicable rows
#' are resolved in order:
#' 1. the most specific scope wins (`wsg` over `subregion` over `region`);
#' 2. at equal scope, the row naming fewer groups wins (a species-to-species
#'    row beats one that names a group);
#' 3. rows still tied must agree on `pool`, or the call errors.
#'
#' Anything no row covers is not pooled. A species always counts as itself,
#' and a model species yields rows only where `wsg_species_presence` marks it
#' present.
#'
#' @param loaded Named list from [lnk_load_overrides()]. Uses
#'   `wsg_species_presence` (required: its species columns are also the set of
#'   known species codes), `species_pooling` and `species_groups` (both
#'   optional; without a tracker nothing is pooled).
#' @param aoi Character vector of watershed group codes.
#' @param species Character vector of model species codes.
#' @param regions Data frame with `watershed_group_code`, `region` and
#'   `subregion`, or `NULL` (default) for the package's
#'   `inst/extdata/wsg_regions.csv`.
#'
#' @return A data frame, one row per WSG x model species x observation
#'   species: `watershed_group_code`, `species_code`, `obs_species`,
#'   `scope_level` (`self` for the species itself, else the winning row's
#'   level), `scope` and `rule` (the winning row's number in the tracker, `NA`
#'   for `self`). Codes are upper case.
#'
#' @seealso [lnk_presence()], [lnk_habitat_validate()]
#' @export
#'
#' @examples
#' cfg <- lnk_config("default")
#' loaded <- suppressWarnings(lnk_load_overrides(cfg))
#'
#' # Which observation species count as each model species in three groups
#' # on different drainages?
#' p <- lnk_species_pooling(loaded, aoi = c("MORR", "ELKR", "COMX"),
#'                          species = c("BT", "CO"))
#' p
#'
#' # The pooled rows alone, with the tracker row that decided each one
#' p[p$scope_level != "self", ]
lnk_species_pooling <- function(loaded, aoi, species, regions = NULL) {
  stopifnot(
    is.list(loaded),
    is.character(aoi), length(aoi) > 0L, !anyNA(aoi),
    is.character(species), length(species) > 0L, !anyNA(species),
    is.null(regions) || is.data.frame(regions)
  )
  presence <- loaded$wsg_species_presence
  if (!is.data.frame(presence) ||
      !"watershed_group_code" %in% names(presence)) {
    stop("loaded$wsg_species_presence is required", call. = FALSE)
  }
  norm <- function(x) toupper(trimws(as.character(x)))
  aoi <- unique(norm(aoi))
  species <- unique(norm(species))

  if (is.null(regions)) {
    regions <- utils::read.csv(.lnk_wsg_regions_path(),
                               stringsAsFactors = FALSE, na.strings = "")
  }
  miss <- setdiff(c("watershed_group_code", "region", "subregion"),
                  names(regions))
  if (length(miss) > 0L) {
    stop("regions lacks columns: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  regions$watershed_group_code <- norm(regions$watershed_group_code)
  if (anyNA(regions$watershed_group_code) ||
      anyDuplicated(regions$watershed_group_code)) {
    stop("regions$watershed_group_code must be unique and not NA",
         call. = FALSE)
  }
  unknown_aoi <- setdiff(aoi, regions$watershed_group_code)
  if (length(unknown_aoi) > 0L) {
    stop("WSGs not in the region lookup: ",
         paste(unknown_aoi, collapse = ", "), call. = FALSE)
  }

  known_species <- norm(.lnk_presence_species_cols(presence))
  unknown_sp <- setdiff(species, known_species)
  if (length(unknown_sp) > 0L) {
    stop("species not in wsg_species_presence: ",
         paste(unknown_sp, collapse = ", "), call. = FALSE)
  }
  groups <- .lnk_sp_groups(loaded$species_groups, known_species)
  rules <- .lnk_sp_rules(loaded$species_pooling, groups, known_species,
                         regions)

  presence$watershed_group_code <- norm(presence$watershed_group_code)
  out <- lapply(aoi, function(w) {
    prow <- presence[which(presence$watershed_group_code == w), , drop = FALSE]
    if (nrow(prow) == 0L) return(NULL)
    if (nrow(prow) > 1L) {
      stop("wsg_species_presence has ", nrow(prow), " rows for ", w,
           call. = FALSE)
    }
    present <- intersect(species, .lnk_wsg_species_present(prow))
    if (length(present) == 0L) return(NULL)
    reg <- regions[which(regions$watershed_group_code == w), , drop = FALSE]
    hit <- rules[
      (rules$scope_level == "wsg" & rules$scope_key == w) |
        (rules$scope_level == "subregion" &
           rules$scope_key %in% norm(reg$subregion)) |
        (rules$scope_level == "region" &
           rules$scope_key %in% norm(reg$region)),
      , drop = FALSE]
    hit <- hit[hit$target %in% present, , drop = FALSE]
    self <- data.frame(watershed_group_code = w, species_code = present,
                       obs_species = present, scope_level = "self",
                       scope = NA_character_, rule = NA_integer_,
                       stringsAsFactors = FALSE)
    if (nrow(hit) == 0L) return(self)
    won <- lapply(split(hit, paste(hit$target, hit$obs)), function(h) {
      h <- h[h$scope_rank == min(h$scope_rank), , drop = FALSE]
      h <- h[h$taxon_rank == min(h$taxon_rank), , drop = FALSE]
      if (length(unique(h$pool)) > 1L) {
        stop(sprintf(
          "species_pooling conflict for %s <- %s in %s: rows %s tie at %s scope and disagree on pool",
          h$target[1], h$obs[1], w, paste(sort(unique(h$rule)), collapse = ", "),
          h$scope_level[1]), call. = FALSE)
      }
      h[order(h$rule), ][1, ]
    })
    won <- do.call(rbind, won)
    won <- won[won$pool, , drop = FALSE]
    rbind(self, data.frame(watershed_group_code = rep(w, nrow(won)),
                           species_code = won$target,
                           obs_species = won$obs,
                           scope_level = won$scope_level,
                           scope = won$scope,
                           rule = won$rule,
                           stringsAsFactors = FALSE))
  })
  out <- do.call(rbind, out)
  if (is.null(out)) {
    out <- data.frame(watershed_group_code = character(0),
                      species_code = character(0),
                      obs_species = character(0),
                      scope_level = character(0), scope = character(0),
                      rule = integer(0), stringsAsFactors = FALSE)
  }
  out <- out[order(out$watershed_group_code, out$species_code,
                   out$scope_level != "self", out$obs_species), ]
  rownames(out) <- NULL
  out
}

#' Path to the package's WSG region lookup (`inst/extdata/wsg_regions.csv`).
#' One place, so the resolver and `.lnk_config_hash()` read the same file.
#' @noRd
.lnk_wsg_regions_path <- function() {
  p <- system.file("extdata", "wsg_regions.csv", package = "link")
  # system.file() returns "" for a missing file, and read.csv("") reads stdin
  if (!nzchar(p)) stop("link's inst/extdata/wsg_regions.csv is missing", call. = FALSE)
  p
}

#' Validate species groups; named list group_code -> member species.
#' @noRd
.lnk_sp_groups <- function(species_groups, known_species) {
  if (is.null(species_groups) || nrow(species_groups) == 0L) return(list())
  miss <- setdiff(c("group_code", "species_code"), names(species_groups))
  if (length(miss) > 0L) {
    stop("species_groups lacks columns: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  g <- toupper(trimws(species_groups$group_code))
  s <- toupper(trimws(species_groups$species_code))
  if (anyNA(g) || anyNA(s) || !all(nzchar(g)) || !all(nzchar(s))) {
    stop("species_groups has an empty group_code or species_code",
         call. = FALSE)
  }
  clash <- intersect(unique(g), known_species)
  if (length(clash) > 0L) {
    stop("species_groups group codes that are also species codes: ",
         paste(clash, collapse = ", "), call. = FALSE)
  }
  nested <- intersect(unique(s), unique(g))
  if (length(nested) > 0L) {
    stop("species_groups may not nest groups; members that are groups: ",
         paste(nested, collapse = ", "), call. = FALSE)
  }
  unknown <- setdiff(s, known_species)
  if (length(unknown) > 0L) {
    stop("species_groups members that are not known species: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  lapply(split(s, g), unique)
}

#' Validate the tracker and expand groups into one row per target x obs.
#' @noRd
.lnk_sp_rules <- function(species_pooling, groups, known_species, regions) {
  empty <- data.frame(target = character(0), obs = character(0),
                      scope_level = character(0), scope = character(0),
                      scope_key = character(0), pool = logical(0),
                      scope_rank = integer(0), taxon_rank = integer(0),
                      rule = integer(0), stringsAsFactors = FALSE)
  if (is.null(species_pooling) || nrow(species_pooling) == 0L) return(empty)
  cols <- c("species_code", "species_obs", "scope_level", "scope", "pool")
  miss <- setdiff(cols, names(species_pooling))
  if (length(miss) > 0L) {
    stop("species_pooling lacks columns: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  p <- species_pooling
  up <- function(x) toupper(trimws(as.character(x)))
  for (col in cols) {
    v <- trimws(as.character(p[[col]]))
    bad <- which(is.na(v) | !nzchar(v))
    if (length(bad) > 0L) {
      stop(sprintf("species_pooling has an empty %s in rows %s", col,
                   paste(bad, collapse = ", ")), call. = FALSE)
    }
  }
  level <- tolower(trimws(p$scope_level))
  bad <- which(!level %in% c("region", "subregion", "wsg"))
  if (length(bad) > 0L) {
    stop(sprintf("species_pooling rows %s: scope_level must be region, subregion or wsg",
                 paste(bad, collapse = ", ")), call. = FALSE)
  }
  pool <- tolower(trimws(p$pool))
  bad <- which(!pool %in% c("yes", "no"))
  if (length(bad) > 0L) {
    stop(sprintf("species_pooling rows %s: pool must be yes or no",
                 paste(bad, collapse = ", ")), call. = FALSE)
  }
  key <- up(p$scope)
  valid <- list(
    region = unique(up(stats::na.omit(regions$region))),
    subregion = unique(up(stats::na.omit(regions$subregion))),
    wsg = up(regions$watershed_group_code))
  bad <- which(!mapply(function(l, k) k %in% valid[[l]], level, key))
  if (length(bad) > 0L) {
    stop(sprintf("species_pooling rows %s name a scope not in the region lookup: %s",
                 paste(bad, collapse = ", "),
                 paste(unique(trimws(p$scope[bad])), collapse = ", ")),
         call. = FALSE)
  }
  expand <- function(code) {
    if (code %in% names(groups)) return(groups[[code]])
    if (code %in% known_species) return(code)
    stop("species_pooling names '", code,
         "', which is neither a known species nor a species_groups group",
         call. = FALSE)
  }
  scope_rank <- c(wsg = 1L, subregion = 2L, region = 3L)
  rows <- lapply(seq_len(nrow(p)), function(i) {
    t_code <- up(p$species_code[i])
    o_code <- up(p$species_obs[i])
    grid <- expand.grid(target = expand(t_code), obs = expand(o_code),
                        stringsAsFactors = FALSE)
    grid <- grid[grid$target != grid$obs, , drop = FALSE]
    if (nrow(grid) == 0L) return(NULL)
    data.frame(grid, scope_level = level[i], scope = trimws(p$scope[i]),
               scope_key = key[i], pool = pool[i] == "yes",
               scope_rank = scope_rank[[level[i]]],
               taxon_rank = (t_code %in% names(groups)) +
                 (o_code %in% names(groups)),
               rule = i, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) empty else out
}
