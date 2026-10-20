#!/usr/bin/env Rscript
# overrides_scope_time_349.R — what counting barrier lifts over province-wide
# observations costs and changes, per group (link#349).
#
# For each group: prepare a scratch working schema up to `natural_barriers`
# (load aux, observations, gradient, natural), then run lnk_barrier_overrides()
# twice, over `<schema>.observations` (the group's own records, the old scope)
# and over `<schema>.observations_province` (every group's, each filtered by
# its own group's presence), timing each, and count the override rows per
# species both ways. The province table's build time is timed separately.
#
# Writes data-raw/logs/access_disagree_349/overrides_scope_time.csv.
# Loads the source tree (pkgload::load_all), never the installed link.
#
# Usage: Rscript data-raw/overrides_scope_time_349.R [WSG ...]   (default DUNC CARP)

suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
wsgs <- toupper(commandArgs(trailingOnly = TRUE))
if (!length(wsgs)) wsgs <- c("DUNC", "CARP")
stopifnot(all(grepl("^[A-Z]{3,5}$", wsgs)))
out <- "data-raw/logs/access_disagree_349"

conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)
secs <- function(expr) {
  t0 <- Sys.time()
  force(expr)
  as.numeric(difftime(Sys.time(), t0, units = "secs"))
}

rows <- list()
for (w in wsgs) {
  schema <- paste0("zz349_time_", tolower(w))
  lnk_pipeline_setup(conn, schema, overwrite = TRUE)
  .lnk_pipeline_prep_load_aux(conn, w, loaded, schema)
  t_obs <- secs(.lnk_pipeline_prep_observations(conn, w, loaded, schema))
  .lnk_pipeline_prep_gradient(conn, w, loaded, schema,
                              .lnk_resolve_classes(NULL, cfg))
  .lnk_pipeline_prep_natural(conn, w, cfg, loaded, schema)
  n_nat <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) AS n FROM %s.natural_barriers", schema))$n
  for (scope in c("observations", "observations_province")) {
    to <- sprintf("%s.ov_%s", schema, scope)
    t <- secs(lnk_barrier_overrides(conn,
      barriers = paste0(schema, ".natural_barriers"),
      observations = paste0(schema, ".", scope),
      habitat = paste0(schema, ".user_habitat_classification"),
      control = paste0(schema, ".barriers_definite_control"),
      params = loaded$parameters_fresh, to = to, verbose = FALSE))
    n <- DBI::dbGetQuery(conn, sprintf(
      "SELECT species_code, count(*) AS n FROM %s GROUP BY 1 ORDER BY 1", to))
    rows[[length(rows) + 1L]] <- data.frame(
      watershed_group_code = w, scope = scope, natural_barriers = as.integer(n_nat),
      secs_overrides = round(t, 1),
      secs_prep_observations_both_tables = round(t_obs, 1),
      species_code = n$species_code, n_overrides = as.integer(n$n))
  }
  DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", schema))
  message(w, " done")
}
res <- do.call(rbind, rows)
utils::write.csv(res, file.path(out, "overrides_scope_time.csv"), row.names = FALSE)
print(res)
DBI::dbDisconnect(conn)
