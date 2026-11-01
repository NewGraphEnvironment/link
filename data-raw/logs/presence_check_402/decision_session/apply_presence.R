# Run once, 2026-11-01, at the end of the #402 decision session; kept as the record of
# how the committed tracker and presence edits were made. Not to be re-run: the tracker
# is no longer all pending. <scratchpad>/easy_wins_B.csv is committed here as easy_wins.csv.
# Apply the tracker's add / remove decisions to default's presence table (#402).
# Run from the link checkout.
f <- "inst/extdata/configs/default/overrides/wsg_species_presence.csv"
raw <- readLines(f)
p <- read.csv(f, colClasses = "character", na.strings = character())
tr <- read.csv("inst/extdata/configs/default/wsg_species_presence_review.csv",
               colClasses = "character", na.strings = character())
d <- tr[tr$decision %in% c("add", "remove"), ]
d$col <- tolower(d$species_code)
stopifnot(all(d$col %in% names(p)), all(d$watershed_group_code %in% p$watershed_group_code))
i <- match(d$watershed_group_code, p$watershed_group_code)
cur <- p[cbind(i, match(d$col, names(p)))]
stopifnot(all(cur[d$decision == "add"] == ""), all(cur[d$decision == "remove"] == "t"))
p[cbind(i, match(d$col, names(p)))] <- ifelse(d$decision == "add", "t", "")

for (w in unique(d$watershed_group_code)) {
  x <- d[d$watershed_group_code == w, ]
  part <- c(if (any(x$decision == "add")) paste("added", paste(sort(x$species_code[x$decision == "add"]), collapse = " ")),
            if (any(x$decision == "remove")) paste("removed", paste(sort(x$species_code[x$decision == "remove"]), collapse = " ")))
  note <- paste0(paste(part, collapse = "; "),
                 " (#402 review 2026-11-01, provisional; reasons in wsg_species_presence_review.csv)")
  j <- p$watershed_group_code == w
  old <- p$notes[j]
  # The Ulkatcho test note describes the cells the review removed.
  if (w == "UDEN") old <- ""
  p$notes[j] <- if (nzchar(old)) paste0(old, "; ", note) else note
}

q <- function(v) ifelse(grepl('[",\n]', v), paste0('"', gsub('"', '""', v), '"'), v)
out <- c(raw[1], apply(p, 1, function(r) paste(q(r), collapse = ",")))
# Rows not touched must come back byte for byte.
untouched <- !p$watershed_group_code %in% d$watershed_group_code
stopifnot(identical(out[-1][untouched], raw[-1][untouched]), length(out) == length(raw))
writeLines(out, f)
cat("cells:", nrow(d), " groups:", length(unique(d$watershed_group_code)), "\n")
