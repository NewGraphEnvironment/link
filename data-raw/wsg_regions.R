#!/usr/bin/env Rscript
# wsg_regions.R — build inst/extdata/wsg_regions.csv (link#290).
#
# One row per BC watershed group: the region and sub-region its outlet drains
# to. Geography, not biology, so it ships once at package level; bundles say
# what to do with it (e.g. configs/default/species_pooling.csv).
#
# Inputs:
#   - fresh's inst/extdata/wsg_outlet.csv (fresh >= v0.33.0): each group's
#     outlet point with its wscode_ltree. The outlet, not the group's
#     shallowest code, because a group can touch more than one drainage.
#   - data-raw/wsg_regions_defs.csv (hand-curated): `level` region|subregion,
#     `name`, `wscode_prefix`, `wsgs`, `note`. A region is matched on the
#     outlet code's first segment. A sub-region is either a wscode prefix
#     (the longest one, on whole segments, containing the outlet code) or an
#     explicit `wsgs` list (semicolon-separated), for a split no prefix can
#     draw: MSKE and USKE have their outlets on the Skeena mainstem (400), as
#     LSKE does, so "Skeena above Hazelton" is a list. A sub-region row gives
#     one or the other, never both, and a group may fall in only one
#     sub-region (there is one column). Names marked "draft" in `note` are
#     placeholders until someone who knows the coast confirms them.
#
#   Rscript data-raw/wsg_regions.R
#
# Fails loud if any group is unassigned, any definition matches nothing, or
# the outlet table is not the 246 groups it should be.

path_outlet <- system.file("extdata", "wsg_outlet.csv", package = "fresh")
if (!nzchar(path_outlet)) {
  stop("fresh's wsg_outlet.csv not found: install fresh >= v0.33.0",
       call. = FALSE)
}
repo <- "."
if (!file.exists("DESCRIPTION") ||
    !any(grepl("^Package: link$", readLines("DESCRIPTION")))) {
  stop("run from the link repo root", call. = FALSE)
}

outlet <- utils::read.csv(path_outlet, colClasses = "character")
defs <- utils::read.csv(file.path(repo, "data-raw", "wsg_regions_defs.csv"),
                        colClasses = "character")

stopifnot(
  nrow(outlet) == 246L,
  !anyDuplicated(outlet$watershed_group_code),
  !anyNA(outlet$wscode_ltree), all(nzchar(outlet$wscode_ltree)),
  all(defs$level %in% c("region", "subregion")),
  !anyDuplicated(defs$wscode_prefix[nzchar(defs$wscode_prefix)]),
  # a row is a prefix or a list, never both or neither
  xor(nzchar(defs$wscode_prefix), nzchar(defs$wsgs)),
  all(!nzchar(defs$wsgs[defs$level == "region"])),
  # written unquoted
  !any(grepl(",", defs$name, fixed = TRUE))
)

# TRUE where `code` equals `prefix` or sits below it, on whole segments.
in_prefix <- function(code, prefix) {
  code == prefix | startsWith(code, paste0(prefix, "."))
}

reg <- defs[defs$level == "region", ]
if (any(grepl(".", reg$wscode_prefix, fixed = TRUE))) {
  stop("a region prefix must be a single wscode segment", call. = FALSE)
}
top <- sub("[.].*$", "", outlet$wscode_ltree)
region <- reg$name[match(top, reg$wscode_prefix)]

sub_defs <- defs[defs$level == "subregion" & nzchar(defs$wscode_prefix), ]
subregion <- vapply(outlet$wscode_ltree, function(code) {
  hit <- sub_defs[in_prefix(code, sub_defs$wscode_prefix), , drop = FALSE]
  if (nrow(hit) == 0L) return(NA_character_)
  hit$name[which.max(nchar(hit$wscode_prefix))]
}, character(1), USE.NAMES = FALSE)

list_defs <- defs[defs$level == "subregion" & nzchar(defs$wsgs), ]
listed <- lapply(strsplit(list_defs$wsgs, ";", fixed = TRUE), trimws)
unknown <- setdiff(unlist(listed), outlet$watershed_group_code)
if (length(unknown) > 0L) {
  stop("sub-region lists name unknown groups: ", paste(unknown, collapse = ", "),
       call. = FALSE)
}
for (i in seq_along(listed)) {
  hit <- outlet$watershed_group_code %in% listed[[i]]
  clash <- outlet$watershed_group_code[hit & !is.na(subregion)]
  if (length(clash) > 0L) {
    stop("groups in two sub-regions (", list_defs$name[i], " and another): ",
         paste(clash, collapse = ", "), call. = FALSE)
  }
  subregion[hit] <- list_defs$name[i]
}

out <- data.frame(
  watershed_group_code = outlet$watershed_group_code,
  region = region,
  subregion = subregion,
  wscode_outlet = outlet$wscode_ltree,
  stringsAsFactors = FALSE
)
out <- out[order(out$watershed_group_code), ]

if (anyNA(out$region)) {
  stop("groups with no region: ",
       paste(out$watershed_group_code[is.na(out$region)], collapse = ", "),
       call. = FALSE)
}
pfx <- defs$wscode_prefix[nzchar(defs$wscode_prefix)]
unused <- pfx[!vapply(pfx, function(p) {
  any(in_prefix(outlet$wscode_ltree, p))
}, logical(1))]
if (length(unused) > 0L) {
  stop("definitions that match no group: ", paste(unused, collapse = ", "),
       call. = FALSE)
}

utils::write.csv(out, file.path(repo, "inst", "extdata", "wsg_regions.csv"),
                 row.names = FALSE, na = "", quote = FALSE)
message("wrote ", nrow(out), " groups: ",
        paste(sprintf("%s %d", names(table(out$region)), table(out$region)),
              collapse = ", "))
