# Build `default`'s observation set for the measured groups and the province,
# with the pipeline's own prep helper, into scratch schema zz396_cuts.
#
#   Rscript data-raw/logs/observation_breaks_396/build_obs.R
#
# Writes zz396_cuts.obs_<wsg> (the AOI table `.lnk_pipeline_prep_observations()`
# builds as <schema>.observations) and zz396_cuts.obs_province (its
# <schema>.observations_province), so cuts.sql, code2_class.sql and
# redundancy.sql read exactly what a `default` build breaks on.
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
schema <- "zz396_cuts"
DBI::dbExecute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
for (wsg in c("PARS", "LKEL", "BULK", "ELKR", "UPCE")) {
  link:::.lnk_pipeline_prep_observations(conn, wsg, loaded, schema)
  tbl <- paste0("obs_", tolower(wsg))
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.%s", schema, tbl))
  DBI::dbExecute(conn, sprintf("ALTER TABLE %s.observations RENAME TO %s",
                               schema, tbl))
  message(wsg, ": ", DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) FROM %s.%s", schema, tbl))[[1]], " observations")
}
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.obs_province", schema))
DBI::dbExecute(conn, sprintf(
  "ALTER TABLE %s.observations_province RENAME TO obs_province", schema))
DBI::dbExecute(conn, sprintf(
  "CREATE INDEX ON %s.obs_province (species_code, blue_line_key)", schema))
DBI::dbExecute(conn, sprintf("ANALYZE %s.obs_province", schema))
message("province: ", DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) FROM %s.obs_province", schema))[[1]], " observations")
DBI::dbDisconnect(conn)
