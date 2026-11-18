# Run once, 2026-11-18, to make default's species presence table bcfishpass's
# copy plus an overlay (link#431, backlog move 4, #472). Kept as the record of
# how the committed copy and overlay were made; it refuses to run again once
# default's table is the copy.
#
# 1. Reads default's table as it stood (link's hand-edited fork).
# 2. Copies the bcfishpass bundle's table (bcfishpass's own at
#    smnorris/bcfishpass@3bd2824, which the weekly sync keeps) byte for byte
#    over it.
# 3. Writes one overlay row for every species cell where the fork differs from
#    the copy, each from its decided row in wsg_species_presence_review.csv
#    (#402): the reason is the decision and the story's opening sentence, which
#    states the reason; the full story stays in the tracker. Plus the four ko
#    cells, worded as the bcfishpass bundle's overlay words them (#106).
# 4. Stops unless copy + overlay gives the fork's species cells and column
#    order exactly. Only `notes` moves: the fork's notes were pointers to the
#    tracker, and each overlay row now carries its cell's reason.
#
# Run from the link checkout: Rscript data-raw/logs/presence_overlay_431/build_overlay.R

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))

cfgs <- file.path("inst", "extdata", "configs")
fork_path <- file.path(cfgs, "default", "overrides", "wsg_species_presence.csv")
copy_path <- file.path(cfgs, "bcfishpass", "overrides", "wsg_species_presence.csv")
ovl_path <- file.path(cfgs, "default", "overrides",
                      "wsg_species_presence_overlay.csv")
tracker_path <- file.path(cfgs, "default", "wsg_species_presence_review.csv")

read_text <- function(p) {
  utils::read.csv(p, colClasses = "character", na.strings = character(0),
                  check.names = FALSE)
}
if (identical(unname(tools::md5sum(fork_path)), unname(tools::md5sum(copy_path)))) {
  stop("default's presence table is already the copy; nothing to convert")
}
stopifnot(!file.exists(ovl_path))

fork <- read_text(fork_path)
copy <- read_text(copy_path)
tracker <- read_text(tracker_path)
stopifnot(identical(sort(fork$watershed_group_code),
                    sort(copy$watershed_group_code)),
          !anyDuplicated(fork$watershed_group_code))

key <- "watershed_group_code"
sp <- setdiff(.lnk_presence_species_cols(fork), "ko")
stopifnot(setequal(sp, .lnk_presence_species_cols(copy)))
copy_m <- copy[match(fork[[key]], copy[[key]]), , drop = FALSE]

diffs <- do.call(rbind, lapply(sp, function(s) {
  w <- which(fork[[s]] != copy_m[[s]])
  if (length(w) == 0L) return(NULL)
  data.frame(watershed_group_code = fork[[key]][w], column = s,
             value = fork[[s]][w], copy = copy_m[[s]][w])
}))
stopifnot(all(diffs$value %in% c("t", "")), all(diffs$copy %in% c("t", "")))

# Each departure is a decided tracker row.
tk <- paste(tracker$watershed_group_code, tolower(tracker$species_code))
hit <- match(paste(diffs$watershed_group_code, diffs$column), tk)
if (anyNA(hit)) {
  stop("departures with no tracker row: ",
       paste(diffs$watershed_group_code[is.na(hit)], diffs$column[is.na(hit)],
             collapse = ", "))
}
tr <- tracker[hit, , drop = FALSE]
want <- ifelse(diffs$value == "t", "add", ifelse(tr$flag == "absent_recorded",
                                                  "keep", "remove"))
if (!identical(tr$decision, want)) {
  bad <- tr$decision != want
  stop("tracker decisions that do not explain the cell: ",
       paste(diffs$watershed_group_code[bad], diffs$column[bad], tr$decision[bad],
             collapse = ", "))
}
prefix <- "Provisional (2026-11-01 decision session): "
opening <- sub("^(.*?\\.)( |$).*", "\\1", tr$story, perl = TRUE)
stopifnot(all(startsWith(opening, prefix)))
verb <- c(add = "added", remove = "removed", keep = "kept absent")[tr$decision]
reason <- sprintf("%s in the #402 review (2026-11-01, provisional): %s",
                  verb, substring(opening, nchar(prefix) + 1L))
# LARL GR: the review kept the cell link had already dropped (322389a3), whose
# reason says why the copy's cell is not taken.
larl <- diffs$watershed_group_code == "LARL" & diffs$column == "gr"
reason[larl] <- paste0(reason[larl], " Dropped in 322389a3: four records from ",
                       "1954 to 1995 in a Columbia group, likely stocking that ",
                       "did not establish; asked upstream as ",
                       "NewGraphEnvironment/bcfishpass#14.")
ovl <- data.frame(watershed_group_code = diffs$watershed_group_code,
                  column = diffs$column, value = diffs$value, reason = reason,
                  issue = tr$issue)

ko <- fork[[key]][fork$ko == "t"]
stopifnot(all(fork$ko %in% c("t", "")))
ovl <- rbind(ovl, data.frame(
  watershed_group_code = ko, column = "ko", value = "t",
  reason = "link models kokanee; bcfishpass's presence table has no KO column",
  issue = "#106"))
ovl <- ovl[order(ovl$watershed_group_code, ovl$column, method = "radix"), ]

# Prove it before writing: copy + overlay gives the fork's species cells.
# Quoted only where a field needs it, as the bcfishpass bundle's overlay is.
q <- function(v) ifelse(grepl('[",\n]', v), paste0('"', gsub('"', '""', v), '"'), v)
tmp <- tempfile(fileext = ".csv")
writeLines(c(paste(names(ovl), collapse = ","),
             apply(ovl, 1, function(r) paste(q(r), collapse = ","))), tmp)
got <- .lnk_overlay_apply(copy, tmp, key = "wsg_species_presence")
got <- got[match(fork[[key]], got[[key]]), , drop = FALSE]
cols <- c(key, .lnk_presence_species_cols(fork))
stopifnot(identical(names(got), names(fork)),
          identical(unname(as.list(got[, cols])), unname(as.list(fork[, cols]))))

file.copy(copy_path, fork_path, overwrite = TRUE)
stopifnot(identical(unname(tools::md5sum(fork_path)),
                    unname(tools::md5sum(copy_path))))
file.copy(tmp, ovl_path)
cat(sprintf("overlay: %d rows (%d species cells, %d ko); notes moved on %d groups\n",
            nrow(ovl), nrow(diffs), length(ko),
            sum(fork$notes != copy_m$notes)))
print(table(verb))
