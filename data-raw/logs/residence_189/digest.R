# link#189: residence read from dimensions.csv moves no persisted mapping code.
# For ADMS and PARS (PARS holds GR, the one species default classifies that
# bcfishpass does not), lnk_mapping_code() runs over fresh_default's persisted
# access and habitat twice into scratch tables: once with the sets coded before
# #189, once with .lnk_species_residence(lnk_config("default")). The two
# tables' row digests (ordered on id_segment) must be equal.
#
#   Rscript data-raw/logs/residence_189/digest.R > data-raw/logs/residence_189/digest.txt
pkgload::load_all(quiet = TRUE)
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
cfg$pipeline$schema <- "fresh_default"
loaded <- lnk_load_overrides(cfg)
sch <- "fresh_default"
scratch <- "zz_residence_189"
DBI::dbExecute(conn, sprintf("CREATE SCHEMA IF NOT EXISTS %s", scratch))
cat("link", system("git rev-parse --short HEAD", intern = TRUE),
    "fresh", as.character(utils::packageVersion("fresh")),
    "date", format(Sys.time(), tz = "UTC", usetz = TRUE), "\n")
for (w in c("ADMS", "PARS")) {
  sp <- tolower(lnk_pipeline_species(cfg, loaded, w))
  pres <- lnk_presence(loaded$wsg_species_presence, w,
                       groups = .lnk_presence_groups(loaded))
  old <- .lnk_species_residence(NULL, sp)
  new <- .lnk_species_residence(cfg, sp)
  dig <- character(0)
  for (arm in c("old", "new")) {
    s <- if (arm == "old") old else new
    tbl <- sprintf("%s.mc_%s_%s", scratch, tolower(w), arm)
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
    lnk_mapping_code(conn,
      table_access = paste0(sch, ".streams_access"),
      table_habitat = paste0(sch, ".streams_habitat_long_vw"),
      table_streams = paste0(sch, ".streams"),
      aoi = w, table_to = tbl, presence = pres,
      species_resident = s$resident, species_anadromous = s$anadromous,
      species_spawn_only = s$spawn_only)
    dig[arm] <- DBI::dbGetQuery(conn, sprintf(
      "SELECT count(*)::int AS n, md5(string_agg(t::text, '|' ORDER BY id_segment))
         AS d FROM %s t", tbl))$d
    n <- DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int AS n FROM %s", tbl))$n
    cat(w, arm, "species", paste(sp, collapse = ","), "resident",
        paste(s$resident, collapse = ","), "anadromous",
        paste(s$anadromous, collapse = ","), "spawn_only",
        paste(s$spawn_only, collapse = ","), "rows", n, "md5", dig[arm], "\n")
  }
  cat(w, if (identical(dig[["old"]], dig[["new"]])) "IDENTICAL" else "DIFFER", "\n")
}
DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", scratch))
DBI::dbDisconnect(conn)
