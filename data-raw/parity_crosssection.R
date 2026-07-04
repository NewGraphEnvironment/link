#!/usr/bin/env Rscript
# parity_crosssection.R — tunnel-free accessible + spawning + rearing parity
# across a WSG cross-section. The provincial-parity harness EXTENDED with the
# accessible column (#221) to prove the #223 access-segmentation fix converges
# accessible_km without regressing habitat.
#
# link side  = lnk_rollup_wsg() (#221): streams x streams_access x streams_habitat_<sp>
#              on the full PK, accessible = access_<sp> IN (1,2).
# bcfp side  = fresh.streams_vw_bcfp (tunnel-free snapshot), IN (1,2) predicate on
#              access_<sp> / spawning_<sp> / rearing_<sp> (bcfp codes these 0/1/2/3;
#              IN (1,2) is the presence predicate — a bare `= 1` UNDER-counts).
# Note: bcfp has no rearing_cm / rearing_pk (chum/pink do not rear in freshwater).
#
# Prereq: each WSG re-run through lnk_pipeline_run(mapping_code = TRUE) with the fix.
# Usage: [LNK_LOAD=loadall] Rscript data-raw/parity_crosssection.R [WSG ...]

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI)
  library(glue)
})

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

args        <- commandArgs(trailingOnly = TRUE)
wsgs        <- if (length(args)) toupper(args) else c("FINA", "PARS", "PCEA", "LKEL")
species     <- c("bt", "st", "co", "ch", "cm", "pk", "sk", "wct")
rear_sp     <- c("bt", "ch", "co", "sk", "st", "wct")
present_min <- 1.0
tol_acc     <- 1.0    # accessible: the fix should make this tight
tol_hab     <- 5.0    # spawn / rear: legitimate methodology wiggle
col_map     <- c(accessible = "accessible_km", spawning = "spawning_km", rearing = "rearing_km")
bc_prefix   <- c(accessible = "acc_", spawning = "spawn_", rearing = "rear_")

bcfp_rollup <- function(w) {
  cols <- unlist(lapply(species, function(sp) {
    r <- if (sp %in% rear_sp) {
      sprintf(paste0("round((coalesce(sum(length_metre) FILTER (WHERE rearing_%s IN (1,2)),0)",
                     "/1000)::numeric,2) rear_%s"), sp, sp)
    } else {
      "NULL::numeric rear_x"
    }
    sprintf("round((coalesce(sum(length_metre) FILTER (WHERE access_%s IN (1,2)),0)/1000)::numeric,2) acc_%s,
             round((coalesce(sum(length_metre) FILTER (WHERE spawning_%s IN (1,2)),0)/1000)::numeric,2) spawn_%s, %s",
            sp, sp, sp, sp, r)
  }))
  DBI::dbGetQuery(conn, glue(
    "select {paste(cols, collapse=',')} from fresh.streams_vw_bcfp where watershed_group_code = '{w}'"))
}
num <- function(x) {
  x <- suppressWarnings(as.numeric(x[1]))
  if (length(x) == 0L || is.na(x)) 0 else x
}

rows <- list()
absent <- character(0)
for (w in wsgs) {
  lk <- lnk_rollup_wsg(conn, aoi = w, species = species, schema = "fresh")
  bc <- bcfp_rollup(w)
  for (sp in species) {
    sp_up <- toupper(sp)
    lk_row <- lk[lk$species == sp_up, ]
    for (m in names(col_map)) {
      if (m == "rearing" && !(sp %in% rear_sp)) next
      bcv <- num(bc[[paste0(bc_prefix[m], sp)]])
      lkv <- if (nrow(lk_row)) num(lk_row[[col_map[m]]]) else 0
      if (max(lkv, bcv) < present_min) next
      if (lkv < present_min && bcv >= present_min) {
        absent <- c(absent, sprintf("%s %s %s (bcfp %.0f, link 0)", w, sp_up, m, bcv))
        next
      }
      pct <- 100 * (lkv - bcv) / bcv
      tol <- if (m == "accessible") tol_acc else tol_hab
      rows[[length(rows) + 1L]] <- data.frame(
        wsg = w, sp = sp_up, metric = m, link = round(lkv, 1), bcfp = round(bcv, 1),
        diff_pct = round(pct, 2), ok = abs(pct) <= tol)
    }
  }
}
tab <- do.call(rbind, rows)
cat("\n============ accessible + spawn + rear parity (link vs bcfp, tunnel-free) ============\n")
print(tab, row.names = FALSE)

cat("\n==== summary by metric (accessible tol", tol_acc, "%, habitat tol", tol_hab, "%) ====\n")
for (m in c("accessible", "spawning", "rearing")) {
  sub <- tab[tab$metric == m, ]
  fails <- sub[!sub$ok, ]
  over <- if (nrow(fails)) {
    paste0("  OVER: ", paste(sprintf("%s/%s %+.1f%%", fails$wsg, fails$sp, fails$diff_pct), collapse = "; "))
  } else {
    ""
  }
  cat(sprintf("  %-11s: %2d pairs / %d WSGs / %d species, max |diff| %5.2f%%, within-tol %d/%d%s\n",
              m, nrow(sub), length(unique(sub$wsg)), length(unique(sub$sp)),
              max(abs(sub$diff_pct)), sum(sub$ok), nrow(sub), over))
}
if (length(absent)) {
  cat("\n  link-absent (bcfp models species, link does not — #189 residence, excluded):\n")
  for (a in absent) cat("   ", a, "\n")
}
cat(sprintf("\nOVERALL: %d/%d pairs within tolerance (%d over)\n", sum(tab$ok), nrow(tab), sum(!tab$ok)))
