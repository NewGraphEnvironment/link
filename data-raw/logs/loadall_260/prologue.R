#!/usr/bin/env Rscript
# prologue.R — time the fixed per-job prologue of data-raw/wsg_recompute_one.R
# (link#260), stage by stage, exactly as that script runs it up to `t0`.
#
# Usage (from the repo root): LNK_T_SHELL=<epoch s before Rscript> \
#   Rscript data-raw/logs/loadall_260/prologue.R <loadall|library> <label> [WSG]
# Prints one TSV row: label mode r_start load db_libs connect set config
#   overrides species total (seconds). r_start is the shell's Rscript launch
#   to R's first expression, i.e. R's own startup, paid under either mode.
el <- function() as.numeric(Sys.time())
t_r <- el()
args  <- commandArgs(trailingOnly = TRUE)
mode  <- args[1]
label <- args[2]
wsg   <- if (length(args) >= 3L) args[3] else "SALR"
t_sh  <- as.numeric(Sys.getenv("LNK_T_SHELL", NA))

t <- c(start = el())
if (identical(mode, "loadall")) {
  suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
} else {
  suppressPackageStartupMessages(library(link))
}
t["load"] <- el()
suppressPackageStartupMessages({ library(DBI); library(RPostgres) })
t["db_libs"] <- el()
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
t["connect"] <- el()
invisible(DBI::dbExecute(conn, "SET statement_timeout = '600000'"))
invisible(DBI::dbExecute(conn, "SET lock_timeout = '60000'"))
t["set"] <- el()
cfg <- lnk_config("default")
cfg$pipeline$schema <- "fresh_default"
t["config"] <- el()
loaded <- lnk_load_overrides(cfg)
t["overrides"] <- el()
active <- lnk_pipeline_species(cfg, loaded, wsg)
pres   <- lnk_presence(loaded$wsg_species_presence, wsg)
t["species"] <- el()
DBI::dbDisconnect(conn)

d <- diff(t)
row <- c(r_start = t_r - t_sh, d, total = unname(t["species"] - t["start"]))
cat(label, mode, sprintf("%.3f", row), sep = "\t")
cat("\n")
