#!/usr/bin/env Rscript
# parity_crosssection.R — the single accessible + spawning + rearing parity
# validator/proof for the #221 (accessible_km roll-up) + #223 (access-segmentation
# fix) work. Supersedes the earlier accessible_km_proof_co.R (coho-only) and
# accessible_km_fix_validate.R (fix gate) — both folded in here.
#
# Two jobs, one script:
#   1. PARITY SWEEP — link vs bcfp for accessible/spawning/rearing per (WSG, species).
#      link side = lnk_rollup_wsg() (#221): streams x streams_access x streams_habitat_<sp>
#      on the full PK, accessible = access_<sp> IN (1,2).
#      bcfp side = tunnel-free fresh.streams_vw_bcfp, IN (1,2) predicate (bcfp codes
#      access/spawning/rearing 0/1/2/3; a bare `= 1` UNDER-counts). No rearing_cm/_pk
#      (chum/pink don't rear in freshwater).
#   2. STRUCTURAL — the #223 mechanism proof on the canonical evidence segment
#      (FINA blk 359209845, BT frontier 3834.78): streams break at the frontier, the
#      reach above is BT-blocked, the accessible reach tops out at the frontier.
#
# Exits non-zero if any ACCESSIBLE pair breaches tol, any STRUCTURAL check fails, or
# any habitat pair breaches tol that is NOT a known parked departure. Habitat parked
# cases (fresh#190 BULK SK) and #189 residence species (link-absent) are allowlisted.
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
tol_acc     <- 1.0    # accessible: the #223 fix should make this tight
tol_hab     <- 5.0    # spawn / rear: legitimate methodology wiggle
hab_parked  <- c("BULK:SK")   # documented parked habitat departures (fresh#190) — not a #223 regression
col_map     <- c(accessible = "accessible_km", spawning = "spawning_km", rearing = "rearing_km")
bc_prefix   <- c(accessible = "acc_", spawning = "spawn_", rearing = "rear_")

# canonical #223 evidence segment
frontier_blk <- 359209845L
frontier_m   <- 3834.78
frontier_eps <- 1.0

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

# ---- 1. parity sweep ------------------------------------------------------
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
      parked <- m != "accessible" && paste(w, sp_up, sep = ":") %in% hab_parked
      rows[[length(rows) + 1L]] <- data.frame(
        wsg = w, sp = sp_up, metric = m, link = round(lkv, 1), bcfp = round(bcv, 1),
        diff_pct = round(pct, 2), ok = abs(pct) <= tol, parked = parked)
    }
  }
}
tab <- do.call(rbind, rows)
cat("\n============ accessible + spawn + rear parity (link vs bcfp, tunnel-free) ============\n")
print(tab[, c("wsg", "sp", "metric", "link", "bcfp", "diff_pct", "ok")], row.names = FALSE)

cat("\n==== summary by metric (accessible tol", tol_acc, "%, habitat tol", tol_hab, "%) ====\n")
for (m in c("accessible", "spawning", "rearing")) {
  sub <- tab[tab$metric == m, ]
  fails <- sub[!sub$ok, ]
  over <- if (nrow(fails)) {
    paste0("  OVER: ", paste(sprintf("%s/%s %+.1f%%%s", fails$wsg, fails$sp, fails$diff_pct,
                                     ifelse(fails$parked, " (parked)", "")), collapse = "; "))
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

# ---- 2. structural checks: canonical #223 evidence segment ----------------
struct_fail <- character(0)
if ("FINA" %in% wsgs) {
  cat("\n==== structural: FINA blk", frontier_blk, "BT frontier", frontier_m, "====\n")
  # no fresh.streams segment straddles the frontier (breaks round to integer 3835, as bcfp)
  span <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int n FROM fresh.streams WHERE blue_line_key=%d AND watershed_group_code='FINA'
       AND downstream_route_measure < %f AND upstream_route_measure > %f",
    frontier_blk, frontier_m - frontier_eps, frontier_m + frontier_eps))$n
  # the segment starting at the frontier is BT-blocked; accessible BT reach tops out there
  seg <- DBI::dbGetQuery(conn, sprintf(
    "SELECT a.access_bt FROM fresh.streams s JOIN fresh.streams_access a
       ON s.id_segment=a.id_segment AND s.watershed_group_code=a.watershed_group_code
      WHERE s.blue_line_key=%d AND s.watershed_group_code='FINA'
        AND abs(s.downstream_route_measure - %f) < %f", frontier_blk, frontier_m, frontier_eps))
  maxupm <- DBI::dbGetQuery(conn, sprintf(
    "SELECT coalesce(max(s.upstream_route_measure),0) m FROM fresh.streams s JOIN fresh.streams_access a
       ON s.id_segment=a.id_segment AND s.watershed_group_code=a.watershed_group_code
      WHERE s.blue_line_key=%d AND s.watershed_group_code='FINA' AND a.access_bt IN (1,2)", frontier_blk))$m
  checks <- c(
    "no segment straddles the frontier"      = span == 0L,
    "segment at frontier is BT-blocked"      = nrow(seg) > 0L && isTRUE(all(seg$access_bt == 0L)),
    "accessible BT reach tops at frontier"   = maxupm <= frontier_m + frontier_eps)
  for (nm in names(checks)) {
    cat(sprintf("  %s: %s\n", ifelse(checks[[nm]], "pass", "FAIL"), nm))
    if (!checks[[nm]]) struct_fail <- c(struct_fail, nm)
  }
}

# ---- verdict --------------------------------------------------------------
acc_fail <- tab[tab$metric == "accessible" & !tab$ok, ]
hab_fail <- tab[tab$metric != "accessible" & !tab$ok & !tab$parked, ]
cat(sprintf("\nOVERALL: %d/%d parity pairs within tolerance (%d over: %d accessible, %d habitat non-parked)",
            sum(tab$ok), nrow(tab), sum(!tab$ok), nrow(acc_fail), nrow(hab_fail)))
n_fail <- nrow(acc_fail) + nrow(hab_fail) + length(struct_fail)
if (n_fail == 0L) {
  cat("  — PASS\n")
  quit(status = 0)
}
cat(sprintf("  — %d FAILURE(S)\n", n_fail))
quit(status = 1)
