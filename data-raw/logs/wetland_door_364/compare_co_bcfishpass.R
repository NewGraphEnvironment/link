#!/usr/bin/env Rscript
# link#364: coho under the `bcfishpass` bundle, before and after the
# gradient test on its through-wetland (1050/1150) rearing rule, against the
# bcfishpass reference.
#
# bcfishpass's load_habitat_linear_co.sql (smnorris/bcfishpass@620dbe43,
# model_run_id 144) tests `gradient <= rear_gradient_max` on every coho
# rearing row and waives only the size test on 1050/1150. Before #364 the
# bundle's carve-out had no gradient test; after it carries
# `gradient: [0, rear_gradient_max]`.
#
# "before" runs the bundle with main's rules.yaml (from git, ref below),
# "after" with the branch's; each is a full lnk_pipeline_run() into its own
# scratch schema, so the two differ in that one rule (and the PSCIS pick tie,
# which moves at most a segment, CLAUDE.md 2026-09-25).
#
# Usage (repo root):
#   Rscript data-raw/logs/wetland_door_364/compare_co_bcfishpass.R [REF] [WSG...]
#   Rscript data-raw/logs/wetland_door_364/compare_co_bcfishpass.R main ADMS BULK
# Writes data-raw/logs/wetland_door_364/compare_co_bcfishpass.csv and
# compare_co_bcfishpass_stamp.txt; drops the scratch schemas.

pkgload::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(DBI))

args <- commandArgs(trailingOnly = TRUE)
ref <- if (length(args) >= 1) args[1] else "main"
wsgs <- toupper(if (length(args) >= 2) args[-1] else c("ADMS", "BULK"))
stopifnot(grepl("^[A-Za-z0-9_./-]+$", ref), all(grepl("^[A-Z]{4}$", wsgs)))
out_dir <- file.path("data-raw", "logs", "wetland_door_364")

rules_before <- tempfile(fileext = ".yaml")
txt <- system2("git", c("show", paste0(ref, ":inst/extdata/configs/bcfishpass/rules.yaml")),
               stdout = TRUE)
if (!is.null(attr(txt, "status"))) stop("git show failed for ", ref, call. = FALSE)
writeLines(txt, rules_before)

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
conn_ref <- lnk_db_conn()
bcfp <- dbGetQuery(conn_ref, "SELECT model_run_id, model_version
                                FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1")

arms <- list(
  before = list(schema = "zz364_bcfp_before", rules = rules_before),
  after = list(schema = "zz364_bcfp_after",
               rules = lnk_config("bcfishpass")$rules))
rows <- list()
for (arm in names(arms)) {
  cfg <- lnk_config("bcfishpass")
  cfg$pipeline$schema <- arms[[arm]]$schema
  cfg$rules <- arms[[arm]]$rules
  dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", cfg$pipeline$schema))
  loaded <- lnk_load_overrides(cfg)
  for (w in wsgs) {
    t0 <- Sys.time()
    lnk_pipeline_run(conn, aoi = w, cfg = cfg, loaded = loaded,
                     schema = paste0("working_zz364_bcfp_", tolower(w)),
                     mapping_code = FALSE, cleanup_working = TRUE)
    message(sprintf("%s %s: %.1f min", arm, w,
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
    r <- lnk_compare_rollup(conn, aoi = w, cfg = cfg, conn_ref = conn_ref,
                            species = "CO")
    r$arm <- arm
    # The 1050/1150 rearing km, which only the changed rule reaches.
    wf <- dbGetQuery(conn, sprintf(
      "SELECT round((sum(s.length_metre) FILTER (WHERE h.rearing) / 1000)::numeric, 2) AS km
         FROM %1$s.streams s
         JOIN %1$s.streams_habitat_co h USING (id_segment, watershed_group_code)
        WHERE s.watershed_group_code = $1 AND s.edge_type IN (1050, 1150)",
      cfg$pipeline$schema), params = list(w))$km
    r$co_rearing_km_1050_1150 <- wf
    rows[[paste(arm, w)]] <- r
  }
}
res <- do.call(rbind, rows)
utils::write.csv(res, file.path(out_dir, "compare_co_bcfishpass.csv"),
                 row.names = FALSE)
writeLines(c(
  sprintf("date_utc: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  sprintf("link: %s @ %s; before rules from %s", utils::packageVersion("link"),
          system("git rev-parse --short HEAD", intern = TRUE), ref),
  sprintf("fresh: %s", utils::packageVersion("fresh")),
  sprintf("bcfishpass reference: model_run_id %s, %s", bcfp$model_run_id,
          bcfp$model_version),
  sprintf("groups: %s", paste(wsgs, collapse = ", "))),
  file.path(out_dir, "compare_co_bcfishpass_stamp.txt"))
for (arm in names(arms)) {
  dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", arms[[arm]]$schema))
}
print(res)
dbDisconnect(conn)
dbDisconnect(conn_ref)
