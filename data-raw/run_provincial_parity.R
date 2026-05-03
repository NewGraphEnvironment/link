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

# Relative — script is run from data-raw/, so this works on every host
# (M4, M1, cypher) without path patching.
source("compare_bcfishpass_wsg.R")

# CLI args:
#   --wsgs=<comma-list>  Restrict to a WSG subset (distributed split).
#   --config=<name>      Bundle name (default: "bcfishpass"). Pass "default"
#                        to run the methodology-variant bundle.
#   --schema=<name>      Override cfg$pipeline$schema. Lets you write to
#                        e.g. fresh_default while the bundle config still
#                        says fresh — useful for side-by-side methodology
#                        comparisons without bundle-config edits.
args <- commandArgs(trailingOnly = TRUE)

config_arg <- args[grep("^--config=", args)]
config_name <- if (length(config_arg) > 0) sub("^--config=", "", config_arg[1]) else "bcfishpass"
cfg <- lnk_config(config_name)

schema_arg <- args[grep("^--schema=", args)]
if (length(schema_arg) > 0) {
  cfg$pipeline$schema <- sub("^--schema=", "", schema_arg[1])
}
loaded <- lnk_load_overrides(cfg)

wsgs_arg <- args[grep("^--wsgs=", args)]
spp_cols <- c("ch", "cm", "co", "pk", "sk", "st", "bt", "wct", "ct", "dv", "rb")
wsg_pres <- loaded$wsg_species_presence
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1, function(r) {
  any(r %in% c("t", "TRUE", TRUE))
})
default_wsgs <- wsg_pres$watershed_group_code[has_spp]

if (length(wsgs_arg) > 0) {
  wsgs <- strsplit(sub("^--wsgs=", "", wsgs_arg[1]), ",")[[1]]
  wsgs <- trimws(wsgs)
  invalid <- setdiff(wsgs, default_wsgs)
  if (length(invalid) > 0) {
    stop("--wsgs contains WSGs not in wsg_species_presence (or with no species we model): ",
         paste(invalid, collapse = ", "), call. = FALSE)
  }
} else {
  wsgs <- default_wsgs
}

# Relative to getwd() so the script works on M4, M1, and cypher (which
# don't share the /Users/airvine/... path). Run from data-raw/.
# RDS dir auto-derived from config name unless overridden via --rds-dir
# (so bcfishpass-bundle and default-bundle rollups don't clobber each
# other when run side-by-side).
rds_dir_arg <- args[grep("^--rds-dir=", args)]
default_rds_dir <- if (config_name == "bcfishpass") "provincial_parity" else paste0("provincial_", config_name)
out_dir_name <- if (length(rds_dir_arg) > 0) sub("^--rds-dir=", "", rds_dir_arg[1]) else default_rds_dir
out_dir <- file.path(getwd(), "logs", out_dir_name)
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
