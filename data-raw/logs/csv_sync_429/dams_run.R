# Runs dams.sql against local fwapg and the bcfishpass reference database,
# and reads Keogh Dam's crossing in the reference (#429). Writes dams.txt.
pkgload::load_all(quiet = TRUE)
sql <- paste(readLines("data-raw/logs/csv_sync_429/dams.sql"), collapse = "\n")
ids <- "('298b0f7e-41d5-479a-95d7-af685224cf3f', '1c16395b-0411-4bad-bfc2-3445b1e94bcc', '242fa0e4-82ff-4ff6-9fa1-a2d892d4b41f')"
out <- c(sprintf("date: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z", tz = "UTC")))
loc <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                   user = "postgres", password = "postgres")
out <- c(out, "", "== local fwapg (link's builds)",
         sprintf("cabd.dams rows: %s", DBI::dbGetQuery(loc, "SELECT count(*) FROM cabd.dams")[[1]]),
         utils::capture.output(print(DBI::dbGetQuery(loc, sql))))
DBI::dbDisconnect(loc)
ref <- lnk_db_conn()
out <- c(out, "", "== bcfishpass reference",
         utils::capture.output(print(DBI::dbGetQuery(ref,
           "SELECT model_version, date_completed FROM bcfishpass.log ORDER BY model_run_id DESC LIMIT 1"))),
         sprintf("cabd.dams rows: %s", DBI::dbGetQuery(ref, "SELECT count(*) FROM cabd.dams")[[1]]),
         utils::capture.output(print(DBI::dbGetQuery(ref, sql))),
         "", "bcfishpass.dams and bcfishpass.crossings rows for the three ids:",
         utils::capture.output(print(DBI::dbGetQuery(ref, paste(
           "SELECT 'dams' AS tbl, dam_id::text AS id, watershed_group_code, passability_status_code::text AS status FROM bcfishpass.dams WHERE dam_id::text IN", ids,
           "UNION ALL SELECT 'crossings', dam_id::text, watershed_group_code, barrier_status FROM bcfishpass.crossings WHERE dam_id::text IN", ids)))))
DBI::dbDisconnect(ref)
writeLines(out, "data-raw/logs/csv_sync_429/dams.txt")
cat(out, sep = "\n")
