# default_diff.R — `default` before (main, zz326_default_pre) against after
# (#326 branch, fresh_default) on PCEA, FINA, PARS and LKEL: km per species.
# Run from the repo root: Rscript data-raw/logs/segmentation_326/default_diff.R
suppressPackageStartupMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
sp_of <- function(schema) toupper(sub("^streams_habitat_", "", DBI::dbGetQuery(conn, sprintf(
  "SELECT table_name FROM information_schema.tables
   WHERE table_schema = '%s' AND table_name ~ '^streams_habitat_[a-z]+$'", schema))$table_name))
species <- intersect(sp_of("zz326_default_pre"), sp_of("fresh_default"))
rows <- list()
for (w in c("PCEA", "FINA", "PARS", "LKEL")) {
  for (s in c("zz326_default_pre", "fresh_default")) {
    r <- lnk_rollup_wsg(conn, aoi = w, species = species, schema = s)
    r$schema <- s
    rows[[length(rows) + 1]] <- r
  }
}
x <- do.call(rbind, rows)
utils::write.csv(x, "data-raw/logs/segmentation_326/default_diff_long.csv", row.names = FALSE)
print(x, row.names = FALSE)
DBI::dbDisconnect(conn)
