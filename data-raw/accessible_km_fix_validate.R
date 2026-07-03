#!/usr/bin/env Rscript
# accessible_km_fix_validate.R — validate the #223 access-segmentation-frontier fix.
#
# THE BUG (segmentation, not access-decision): the stream break source
# `gradient_barriers_minimal` is fed the frs_barriers_minimal() downstream-most
# reduction of each per-species barrier set (lnk_pipeline_prepare.R:592), so
# streams do NOT break at per-species gradient/falls frontiers. One segment
# straddles the frontier and the whole reach — including the blocked part above
# the barrier — is credited accessible. Over-credit scales with the species
# access_gradient_max (BT 0.25 worst). Root cause: research/accessible_km_divergence.md.
#
# THIS SCRIPT IS READ-ONLY. It asserts against the currently-persisted DB state:
#   - pre-fix  -> FAILS (bug reproduces), exits non-zero.
#   - post-fix -> PASSES once the validation-set WSGs are re-run through
#                 lnk_pipeline_run(..., mapping_code = TRUE) with the fix.
# It never writes; safe to run repeatedly.
#
# Usage: [LNK_LOAD=loadall] Rscript data-raw/accessible_km_fix_validate.R
#   LNK_LOAD=loadall -> pkgload::load_all() (dev checkout)
#   default          -> library(link)
#
# VALIDATION SET:
#   FINA / PARS / PCEA — Peace-region WSGs (above the Bennett dam): BT-only, the
#     over-credit bug. Pre-fix BT accessible_km diverges +23.6% / +3.4% / +40.4%.
#   LKEL — the SMALLEST persisted WSG carrying steelhead AND salmon (BT/ST/CO/CH/
#     CM/PK all present). Pre-fix it is already clean (BT +0.7%, ST/CO 0%). The fix
#     changes segmentation for EVERY species' model, so a salmon+ST WSG is required
#     to prove no-regression — the Peace WSGs cannot (they carry no salmon/ST).
#
# Expected PRE-FIX failures: FINA-BT, PARS-BT, PCEA-BT parity + all four FINA
# structural checks on the canonical evidence segment (blk 359209845).

if (identical(Sys.getenv("LNK_LOAD"), "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
})

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# ---- knobs ----------------------------------------------------------------
tol_pct      <- 1.0          # convergence bar: |link - bcfp| / bcfp * 100
present_min  <- 1.0          # accessible_km above which a (wsg, species) is "present"
frontier_blk <- 359209845L   # canonical evidence blue_line_key (FINA, BT)
frontier_m   <- 3834.78      # the BT frontier barrier measure on that blk
frontier_eps <- 1.0          # metres — position match tolerance

wsgs    <- c("FINA", "PARS", "PCEA", "LKEL")
species <- c("bt", "st", "co", "ch", "cm", "pk", "sk", "wct")
# bcfp reference predicate: barriers_<group>_dnstr = '' (empty = no barrier
# downstream = accessible). Verified identical to bcfp access_<sp> IN (1,2).
# The five salmon species share one combined bcfp barrier column.
bcfp_grp <- c(bt  = "barriers_bt_dnstr",
              st  = "barriers_st_dnstr",
              co  = "barriers_ch_cm_co_pk_sk_dnstr",
              ch  = "barriers_ch_cm_co_pk_sk_dnstr",
              cm  = "barriers_ch_cm_co_pk_sk_dnstr",
              pk  = "barriers_ch_cm_co_pk_sk_dnstr",
              sk  = "barriers_ch_cm_co_pk_sk_dnstr",
              wct = "barriers_wct_dnstr")
# Known #189 species-residence differences ("<WSG>:<sp>"): bcfp models the species
# (shared salmon barrier group populates its access_<sp>), link does not — expected,
# NOT a #223 regression. Allowlisted so the one-sided-presence gate does not flag
# them, while an UNEXPECTED link collapse to ~0 km still fails loudly.
residence_exclude <- c("LKEL:sk")

# ---- failure ledger -------------------------------------------------------
fails <- character(0)
record_fail <- function(msg) {
  fails[[length(fails) + 1L]] <<- msg
  cat("  FAIL:", msg, "\n")
}
record_pass <- function(msg) cat("  pass:", msg, "\n")

# link accessible_km: fresh.streams x fresh.streams_access on the full PK
# (id_segment, watershed_group_code) — the persisted-fresh join discipline (#203).
km_link <- function(wsg, sp) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT coalesce(sum(s.length_metre), 0) / 1000.0 AS km
       FROM fresh.streams s
       JOIN fresh.streams_access a
         ON s.id_segment = a.id_segment
        AND s.watershed_group_code = a.watershed_group_code
      WHERE s.watershed_group_code = '%s' AND a.access_%s IN (1, 2)",
    wsg, sp))$km
}
# bcfp accessible_km: the tunnel-free reference view (fresh.streams_vw_bcfp).
km_bcfp <- function(wsg, sp) {
  DBI::dbGetQuery(conn, sprintf(
    "SELECT coalesce(sum(length_metre), 0) / 1000.0 AS km
       FROM fresh.streams_vw_bcfp
      WHERE watershed_group_code = '%s' AND %s = ''",
    wsg, bcfp_grp[[sp]]))$km
}

# ---- 1. parity sweep ------------------------------------------------------
cat("\n== accessible_km parity: link vs bcfp (assert co-present species |diff| <= ",
    tol_pct, "%) ==\n", sep = "")
rows <- list()
for (w in wsgs) for (sp in species) {
  lk <- km_link(w, sp)
  bc <- km_bcfp(w, sp)
  lk_present <- lk >= present_min
  bc_present <- bc >= present_min
  pct <- if (bc > 0) 100 * (lk - bc) / bc else NA_real_
  # Both present -> assert tolerance. A one-sided presence is a divergence the gate
  # must catch (link zeroing a bcfp-present species is exactly a no-regression
  # failure) — EXCEPT the allowlisted #189 residence cases. Both absent -> skip.
  if (lk_present && bc_present) {
    scope  <- "assert"
    status <- if (abs(pct) <= tol_pct) "pass" else "FAIL"
  } else if (bc_present) {                                  # bcfp has it, link doesn't
    is_known <- paste(w, sp, sep = ":") %in% residence_exclude
    scope  <- if (is_known) "residence" else "link-absent"
    status <- if (is_known) "n/a" else "FAIL"
  } else if (lk_present) {                                  # link has it, bcfp doesn't
    scope  <- "bcfp-absent"
    status <- "FAIL"
  } else {                                                  # absent both sides
    scope  <- "-"
    status <- "n/a"
  }
  rows[[length(rows) + 1L]] <- data.frame(
    wsg = w, sp = toupper(sp), link = round(lk, 1), bcfp = round(bc, 1),
    diff_pct = round(pct, 2), scope = scope, status = status)
}
tab <- do.call(rbind, rows)
print(tab[tab$scope != "-", ], row.names = FALSE)
for (i in seq_len(nrow(tab))) {
  if (tab$status[i] == "n/a") next
  m <- sprintf("%s %s parity %+.2f%% (link %.1f / bcfp %.1f)",
               tab$wsg[i], tab$sp[i], tab$diff_pct[i], tab$link[i], tab$bcfp[i])
  if (tab$status[i] == "pass") record_pass(m) else record_fail(m)
}

# ---- 2. structural checks: canonical evidence segment ---------------------
# FINA blk 359209845, BT frontier 3834.78. Pre-fix a single segment
# [3390.6, 7998.1] straddles the frontier; post-fix it breaks at 3834.78 and the
# reach above is BT-blocked.
cat("\n== structural: FINA blk ", frontier_blk, " BT frontier ", frontier_m, " ==\n", sep = "")

# S1 mechanism: the break source holds the frontier position (skip if the
# working schema was cleaned after persist — fresh.streams checks stand alone).
gbm_exists <- DBI::dbGetQuery(conn,
  "SELECT count(*)::int AS n FROM information_schema.tables
    WHERE table_schema = 'working_fina' AND table_name = 'gradient_barriers_minimal'")$n > 0L
if (!gbm_exists) {
  cat("  skip: working_fina.gradient_barriers_minimal absent (working schema cleaned)\n")
} else {
  fr <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM working_fina.gradient_barriers_minimal
      WHERE blue_line_key = %d AND abs(downstream_route_measure - %f) < %f",
    frontier_blk, frontier_m, frontier_eps))$n
  if (fr > 0L) {
    record_pass("gradient_barriers_minimal holds the frontier break")
  } else {
    record_fail("gradient_barriers_minimal missing the frontier break (minimal reduction dropped it)")
  }
}

# S2 segmentation: no fresh.streams segment straddles the frontier.
span <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM fresh.streams
    WHERE blue_line_key = %d AND watershed_group_code = 'FINA'
      AND downstream_route_measure < %f AND upstream_route_measure > %f",
  frontier_blk, frontier_m, frontier_m))$n
if (span == 0L) {
  record_pass(sprintf("no segment straddles the frontier (streams break at %.2f)", frontier_m))
} else {
  record_fail(sprintf("%d fresh.streams segment(s) straddle the frontier %.2f", span, frontier_m))
}

# S3 reclassification: the segment starting at the frontier is BT-blocked.
seg <- DBI::dbGetQuery(conn, sprintf(
  "SELECT a.access_bt FROM fresh.streams s
     JOIN fresh.streams_access a
       ON s.id_segment = a.id_segment AND s.watershed_group_code = a.watershed_group_code
    WHERE s.blue_line_key = %d AND s.watershed_group_code = 'FINA'
      AND abs(s.downstream_route_measure - %f) < %f",
  frontier_blk, frontier_m, frontier_eps))
if (nrow(seg) == 0L) {
  record_fail(sprintf("no fresh.streams segment starts at frontier %.2f (network did not break there)", frontier_m))
} else if (isTRUE(all(seg$access_bt == 0L))) {
  record_pass(sprintf("segment at %.2f is BT-blocked (access_bt = 0)", frontier_m))
} else {
  record_fail(sprintf("segment at %.2f has access_bt = %s (expected 0)",
                      frontier_m, paste(seg$access_bt, collapse = ",")))
}

# S4 over-credit removed: the accessible BT reach on this blk tops out at the
# frontier (pre-fix it runs to 7998.1, ~4163 m of over-credit).
maxupm <- DBI::dbGetQuery(conn, sprintf(
  "SELECT coalesce(max(s.upstream_route_measure), 0) AS m FROM fresh.streams s
     JOIN fresh.streams_access a
       ON s.id_segment = a.id_segment AND s.watershed_group_code = a.watershed_group_code
    WHERE s.blue_line_key = %d AND s.watershed_group_code = 'FINA' AND a.access_bt IN (1, 2)",
  frontier_blk))$m
if (maxupm <= frontier_m + frontier_eps) {
  record_pass(sprintf("accessible BT reach tops out at %.1f (<= frontier)", maxupm))
} else {
  record_fail(sprintf("accessible BT reach extends to %.1f, above frontier %.2f (over-credit %.0f m)",
                      maxupm, frontier_m, maxupm - frontier_m))
}

# ---- verdict --------------------------------------------------------------
cat("\n== verdict ==\n")
if (length(fails) == 0L) {
  cat("ALL CHECKS PASS - #223 access-segmentation-frontier fix validated.\n")
  quit(status = 0)
}
cat(sprintf("%d CHECK(S) FAILED - #223 bug present / fix incomplete:\n", length(fails)))
for (f in fails) cat("  -", f, "\n")
quit(status = 1)
