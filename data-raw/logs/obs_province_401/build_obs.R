# Rebuild the record sets each #401 build's access walk read, per config and
# group, with the pipeline's own prep helper, into scratch schema zz401_obs.
#
#   Rscript data-raw/logs/obs_province_401/build_obs.R
#
# The working schemas keep whichever config ran last, and every run drops its
# province table, so this rebuilds them: zz401_obs.<config>_<wsg> (the group's
# own records, <schema>.observations: the walk's gate under group_gated, and
# all PRE read) and zz401_obs.province_<config> (every group's,
# <schema>.observations_province: what POST's walk reads). It also checks
# that each group's slice of the province table equals its own table row for
# row, which is what makes "a 1 -> 2 needs a record from another group" hold.
pkgload::load_all(quiet = TRUE)
# nolint start: indentation_linter, brace_linter
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
schema <- "zz401_obs"
q <- function(sql) DBI::dbGetQuery(conn, sql)
ex <- function(sql) invisible(DBI::dbExecute(conn, sql))
ex(sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
groups <- list(default = c("LKEL", "BULK", "UPCE", "PARS", "ELKR", "LNTH"),
               bcfishpass = c("BULK", "PARS", "UPCE"))
for (config in names(groups)) {
  cfg <- lnk_config(config)
  loaded <- lnk_load_overrides(cfg)
  for (wsg in groups[[config]]) {
    .lnk_pipeline_prep_observations(conn, wsg, loaded, schema)
    tbl <- paste0(config, "_", tolower(wsg))
    ex(sprintf("DROP TABLE IF EXISTS %s.%s", schema, tbl))
    ex(sprintf("ALTER TABLE %s.observations RENAME TO %s", schema, tbl))
    ex(sprintf("CREATE INDEX ON %s.%s USING gist (wscode)", schema, tbl))
    ex(sprintf("ANALYZE %s.%s", schema, tbl))
    d <- q(sprintf(
      "SELECT (SELECT count(*) FROM (SELECT * FROM %1$s.%2$s EXCEPT ALL
                SELECT * FROM %1$s.observations_province
                 WHERE watershed_group_code = '%3$s') x) AS own_only,
              (SELECT count(*) FROM (SELECT * FROM %1$s.observations_province
                 WHERE watershed_group_code = '%3$s' EXCEPT ALL
                SELECT * FROM %1$s.%2$s) x) AS province_only,
              (SELECT count(*) FROM %1$s.%2$s) AS n", schema, tbl, wsg))
    message(config, " ", wsg, ": ", d$n, " records; own-only ", d$own_only,
            ", province-only ", d$province_only)
    if (d$own_only != 0 || d$province_only != 0) {
      stop(config, " ", wsg, ": the group's slice of the province table is ",
           "not its own table", call. = FALSE)
    }
  }
  ptbl <- paste0("province_", config)
  ex(sprintf("DROP TABLE IF EXISTS %s.%s", schema, ptbl))
  ex(sprintf("ALTER TABLE %s.observations_province RENAME TO %s", schema, ptbl))
  ex(sprintf("ANALYZE %s.%s", schema, ptbl))
}
DBI::dbDisconnect(conn)
# nolint end
