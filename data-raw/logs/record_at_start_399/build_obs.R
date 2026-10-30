# Rebuild the observation set each #399 build's access walk read, per config
# and group, with the pipeline's own prep helper, into scratch schema zz399_obs.
#
#   Rscript data-raw/logs/record_at_start_399/build_obs.R
#
# The walk reads working_<wsg>.observations, which every build rebuilds, and the
# two configs filter it differently (presence, exclusions), so after run.sh each
# working schema holds whichever config ran last. This writes
# zz399_obs.<config>_<wsg> (the AOI table .lnk_pipeline_prep_observations()
# builds as <schema>.observations) and zz399_obs.province_<config> (its
# <schema>.observations_province; parity_pieces.sql reads
# province_bcfishpass for its upstream-group reading). The helper is unchanged by #399, so PRE and
# POST read the same set.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter, brace_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
schema <- "zz399_obs"
DBI::dbExecute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
groups <- list(default = c("LKEL", "BULK", "UPCE", "PARS", "ELKR"),
               bcfishpass = c("BULK", "PARS"))
for (config in names(groups)) {
  cfg <- lnk_config(config)
  loaded <- lnk_load_overrides(cfg)
  for (wsg in groups[[config]]) {
    link:::.lnk_pipeline_prep_observations(conn, wsg, loaded, schema)
    tbl <- paste0(config, "_", tolower(wsg))
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.%s", schema, tbl))
    DBI::dbExecute(conn, sprintf("ALTER TABLE %s.observations RENAME TO %s",
                                 schema, tbl))
    DBI::dbExecute(conn, sprintf(
      "CREATE INDEX ON %s.%s (species_code, blue_line_key)", schema, tbl))
    message(config, " ", wsg, ": ", DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*) FROM %s.%s", schema, tbl))[[1]], " observations")
  }
  ptbl <- paste0("province_", config)
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.%s", schema, ptbl))
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s.observations_province RENAME TO %s", schema, ptbl))
  DBI::dbExecute(conn, sprintf(
    "CREATE INDEX ON %s.%s (species_code, blue_line_key)", schema, ptbl))
  DBI::dbExecute(conn, sprintf("ANALYZE %s.%s", schema, ptbl))
}
DBI::dbDisconnect(conn)
# nolint end
