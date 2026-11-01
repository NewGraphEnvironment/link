# Run once, 2026-11-01, at the end of the #402 decision session; kept as the record of
# how the committed tracker and presence edits were made. Not to be re-run: the tracker
# is no longer all pending. <scratchpad>/easy_wins_B.csv is committed here as easy_wins.csv.
# Afterwards (code-check round 3) the stories of the 14 Columbia and Mackenzie literature
# rows and of MESI SK were reworded in place; their decisions did not change.
# Record the 2026-11-01 decision session's provisional calls in the #402 tracker.
# Run from the link checkout: Rscript <this> <scratchpad>
s <- commandArgs(TRUE)[1]
f <- "inst/extdata/configs/default/wsg_species_presence_review.csv"
tr <- read.csv(f, colClasses = "character", na.strings = character())
stopifnot(nrow(tr) == 351, all(tr$decision == "pending"))
ew <- read.csv(file.path(s, "easy_wins_B.csv"), colClasses = "character")
key <- function(w, sp) paste(w, sp)
k <- key(tr$watershed_group_code, tr$species_code)
pre <- "Provisional (2026-11-01 decision session): "
call <- data.frame(k = character(), decision = character(), why = character())
put <- function(keys, decision, why) {
  miss <- setdiff(keys, k)
  if (length(miss)) stop("not in tracker: ", paste(miss, collapse = ", "))
  call <<- rbind(call, data.frame(k = keys, decision = decision, why = why))
}
ks <- function(x) key(x$wsg, x$sp)
pairs <- function(...) {
  v <- c(...)
  key(sub(" .*", "", v), sub(".* ", "", v))
}

# salmon and steelhead the table does not mark
put(ks(ew[ew$tier == "1 strong", ]), "add",
    "records at 3 or more sites on 2 or more waterbodies, one since 1990, none above a modelled barrier.")
some_flag <- pairs("ADMS PK", "DOGC PK", "MCGR SK", "MORK SK", "UFRA SK", "MUSK CH")
s2 <- ks(ew[ew$tier == "2 some", ])
put(setdiff(s2, some_flag), "add", "records at 2 or more sites.")
put(some_flag, "add", "records at 2 or more sites; flagged to recheck (unusual this far inland, or records above a modelled barrier).")
one <- ew[ew$tier == "3 one site", ]
rej <- pairs("HORS CM", "STHM CM", "LSAL PK", "WILL PK", "FRAN CO", "STUR CO",
             "CHES CO", "BONP SK", "LNIC SK", "COTR SK")
recent <- ks(one[as.integer(one$since90) > 0, ])
put(setdiff(recent, rej), "add", "one site with a record since 1990.")
put(rej, "keep", "one site with a record since 1990, but not accepted: the species is unusual this far inland and one record could be a misidentification or a misplacement.")
put(ks(one[as.integer(one$since90) == 0, ]), "keep",
    "one site and nothing since 1990; left unmarked.")
put(pairs("BRID ST", "STUL CO"), "keep",
    "every record sits above a mapped falls or hand-entered barrier with at most one other record above it.")
put(pairs("MESI SK"), "keep",
    "its one record (FISS survey 66276, a Johanson Lake / Skeena survey on a Sustut waterbody) is misplaced across the divide.")
lit <- ew[ew$tier == "L literature", ]
put(setdiff(ks(lit[lit$region %in% c("Columbia", "Mackenzie"), ]), pairs("OKAN ST", "SIML ST")), "keep",
    "salmon and steelhead are cut off from the Kootenay and upper Columbia by dams and falls, and do not run into the Mackenzie; left unmarked.")
put(c(ks(lit[lit$region == "Yukon", ]), pairs("OKAN ST", "SIML ST")), "keep",
    "left unmarked until the literature review; it may add this cell.")
# TURN ST stays pending for the Mackenzie literature.

# resident species the table does not mark
put(pairs("LARL GR", "ALBN WCT", "KISP WCT", "KLUM WCT", "LFRA WCT", "SQAM WCT",
          "UPCE WCT", "LPCE WCT", "MURR WCT", "SKGT WCT", "SIML WCT"), "keep",
    "outside the species' native range; left unmarked.")
# BT CHIL CLWR EUCH LKEC LSAL MUSK SALR STUL and CT FINL LOMI stay pending.

# cells marked present with no counting record
put(pairs("UDEN CH", "UDEN CM", "UDEN CO", "UDEN PK", "UDEN SK", "UDEN ST"), "remove",
    "added as a test for Ulkatcho with no record; the test is finished.")
put(pairs("THOM CT", "LNTH CT", "VICT DV", "BULL GR"), "remove",
    "stocked fish are the only records, outside the species' usual range.")
put(pairs("KTSU CH", "KTSU ST"), "keep", "supported by PSE spawning data (the group's note).")
put(pairs("UEUT BT", "UEUT DV", "GUIC DV"), "keep", "undated records only; no date is not evidence of an error.")
put(pairs("UEUT CT"), "keep", "undated records only; kept, flagged (cutthroat there is unusual).")
put(pairs("DRIR CH", "BBAR SK", "TAYR ST"), "keep", "no records, and no evidence it is absent.")
# CT CLRH, CT DUNC stay pending (Columbia literature).

stopifnot(!anyDuplicated(call$k))
i <- match(call$k, k)
tr$decision[i] <- call$decision
tr$story[i] <- paste0(pre, call$why, " ", tr$story[i])
tr$reviewer[i] <- "almac2022"
tr$review_date[i] <- "2026-11-01"
paused <- tr$decision == "pending" & tr$species_code %in% c("KO", "RB")
tr$issue[paused] <- "#432"
print(table(tr$decision))
cat("pending, deferred to #432:", sum(paused), "\n")
write.csv(tr, f, row.names = FALSE, na = "")
