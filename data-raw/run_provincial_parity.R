# Provincial parity-only run — link 0.20.0 single-host baseline
#
# Loops over every WSG with any of our modelled species present, runs
# compare_bcfishpass_wsg() with the bcfishpass bundle, saves per-WSG
# rollup tibbles to `data-raw/logs/provincial_parity/<WSG>.rds`.
#
# Resume-safe: skips WSGs whose RDS file already exists.
# Error-tolerant: a per-WSG failure saves an error stub and moves on.
# Logs progress + timing to `data-raw/logs/<TS>_provincial_parity.txt`.
#
# Known residuals at link 0.20.0:
#   - HORS-class stream-order bypass (fresh#158 not yet shipped)
#   - BULK SK multi-lake (fresh#190 parked)
#   - lake_rearing/wetland_rearing rollup measurement artifacts (-100% rows)
# These are accepted as known gaps in this baseline.
#
# Run from data-raw/:
#   Rscript run_provincial_parity.R > logs/<TS>_provincial_parity.txt 2>&1 &

suppressPackageStartupMessages({
  library(link); library(fresh); library(dplyr); library(DBI); library(RPostgres)
})

source("/Users/airvine/Projects/repo/link/data-raw/compare_bcfishpass_wsg.R")

cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

# Species we model. Any WSG with at least one of these present qualifies.
spp_cols <- c("ch", "cm", "co", "pk", "sk", "st", "bt", "wct", "ct", "dv", "rb")
wsg_pres <- loaded$wsg_species_presence
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1, function(r) {
  any(r %in% c("t", "TRUE", TRUE))
})
wsgs <- wsg_pres$watershed_group_code[has_spp]

out_dir <- "/Users/airvine/Projects/repo/link/data-raw/logs/provincial_parity"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("=== PROVINCIAL PARITY RUN — link 0.20.0 ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    " (epoch", as.integer(Sys.time()), ")\n", sep = "")
cat("WSGs to run:", length(wsgs), "\n")
cat("Output dir :", out_dir, "\n\n")

t_total <- Sys.time()

for (w in wsgs) {
  out_rds <- file.path(out_dir, paste0(w, ".rds"))
  if (file.exists(out_rds)) {
    cat(format(Sys.time(), "%H:%M:%S"), "  ", w, " (cached, skip)\n", sep = "")
    next
  }
  cat(format(Sys.time(), "%H:%M:%S"), "  ", w, " ... ", sep = "")
  t0 <- Sys.time()
  tryCatch({
    out <- compare_bcfishpass_wsg(wsg = w, config = cfg)
    saveRDS(out, out_rds)
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat("done ", round(elapsed, 1), "s, rows ", nrow(out), "\n", sep = "")
  }, error = function(e) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    saveRDS(list(error = conditionMessage(e),
                 elapsed_s = elapsed),
            out_rds)
    cat("ERROR (", round(elapsed, 1), "s): ",
        conditionMessage(e), "\n", sep = "")
  })
}

t_total_s <- as.numeric(difftime(Sys.time(), t_total, units = "secs"))
cat("\n=== DONE ===\n")
cat("Ended:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("Total wall time:", round(t_total_s / 60, 1), "min  (",
    round(t_total_s, 1), "s)\n", sep = "")
cat("WSGs completed:", length(list.files(out_dir, pattern = "\\.rds$")), "\n")
