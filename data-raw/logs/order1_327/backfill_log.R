# link#476: write each variant schema's log rows for this build, as
# habitat_variants_build.R's log_variant_pass() now does at the end of a pass.
# The build ran at 9306e581, before that function existed, so its variant
# schemas held no log rows and the validator refused them (it read them as
# walking no near-river pair, where default's CH pair is walked). Each row
# takes the pass's time, link head and dirty flag from built.csv, and the
# near-river pairs, fill and source from the variant's own bundle.
#
#   Rscript <link checkout>/data-raw/logs/order1_327/backfill_log.R <out dir>
#   (run with the link checkout as the working directory: load_all)
pkgload::load_all(quiet = TRUE)
out <- commandArgs(TRUE)[1]
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
built <- utils::read.csv(file.path(out, "built.csv"), colClasses = "character")
built <- built[built$variant != "default", ]
stopifnot(all(grepl(" MST$", built$built_at)))
for (i in seq_len(nrow(built))) {
  b <- built[i, ]
  cfg <- lnk_config(file.path(out, "bundles", b$variant))
  stopifnot(identical(cfg$pipeline$schema, b$schema),
            identical(digest::digest(file = cfg$dimensions, algo = "sha256"),
                      b$dimensions_sha256))
  # MST is UTC-7 (BC dropped the clock change).
  when <- format(as.POSIXct(sub(" MST$", "", b$built_at), tz = "Etc/GMT+7"),
                 "%Y-%m-%d %H:%M:%OS3%z")
  DBI::dbExecute(conn, sprintf(
    "DELETE FROM %s.log WHERE watershed_group_code = $1", b$schema),
    params = list(b$watershed_group_code))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end,
       config_name, link_sha, link_dirty, discharge_fill, discharge_source,
       near_river, schema_persist, notes)
     VALUES ($1, $2, $3::timestamptz, $3::timestamptz, $4, $5, $6, $7, $8,
       $9, $10, $11)", b$schema),
    params = list(
      paste("variant", cfg$name, b$watershed_group_code, when, sep = ":"),
      b$watershed_group_code, when, cfg$name, b$link_head,
      as.logical(b$dirty),
      .lnk_discharge_fill_applied(cfg, b$watershed_group_code),
      .lnk_discharge_source(cfg),
      .lnk_near_river_logged(cfg, b$watershed_group_code), b$schema,
      paste0("variant pass by data-raw/habitat_variants_build.R on ",
             "score327_default's segmentation (backfilled, link#476)")))
  cat(b$schema, b$watershed_group_code,
      .lnk_near_river_logged(cfg, b$watershed_group_code), "\n")
}
DBI::dbDisconnect(conn)
