# Usage: Rscript model_mad.R <repo> <persist_schema> <method_csv> <aoi>
# Models one WSG with the `default` bundle into a scratch persist schema,
# with the bundle's method table swapped for <method_csv>, and builds
# streams_access (mapping_code) so lnk_habitat_validate() can score it.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; persist <- args[2]; method_csv <- args[3]; aoi <- args[4]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
cfg$pipeline$schema <- persist
cfg$files$parameters_habitat_method <- list(path = normalizePath(method_csv))
loaded <- suppressWarnings(lnk_load_overrides(cfg))
t0 <- Sys.time()
# Own working schema: the default working_<aoi> may hold someone's work.
lnk_pipeline_run(conn, aoi = aoi, cfg = cfg, loaded = loaded,
                 schema = paste0("zz299_w_", tolower(aoi)),
                 mapping_code = TRUE, run_label = "habitat_validate_299")
cat(sprintf("## model_mad %s -> %s method=%s link=%s fresh=%s %.1f min\n",
            aoi, persist, basename(method_csv), utils::packageVersion("link"),
            utils::packageVersion("fresh"),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
print(DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) AS n_segments FROM %s.streams WHERE watershed_group_code = %s",
  persist, DBI::dbQuoteString(conn, aoi))))
DBI::dbDisconnect(conn)
