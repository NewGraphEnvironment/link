# Usage: Rscript measure.R <repo> <out_dir>
# #317: rearing km with lake connection lines (edge 1400 / 1450 inside a
# lake or reservoir polygon) reported apart from the total. Reads #310's
# run-B snapshots (zz310_snap.<wsg>_b, default at link 892a09f, fresh 0.39.0)
# on their own segmentation (zz311_<wsg>.streams); nothing is re-classified.
# The bcfishpass side applies the same rule to the local
# fresh.streams_vw_bcfp (rearing_<sp> IN (1, 2)).
# Writes <out_dir>/measure.csv (link) and <out_dir>/reference.csv (bcfp).
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; out_dir <- args[2]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
writeLines(utils::capture.output(print(lnk_stamp(lnk_config("default"), conn = conn, aoi = "ADMS"))),
           file.path(out_dir, "stamp.txt"))

wb_join <- .lnk_sql_waterbody_join()
wb_class <- .lnk_sql_waterbody_class()
conn_pred <- sprintf("(%s = 'lake' AND s.edge_type IN (1400, 1450))", wb_class)

km_cols <- function(flag) sprintf("
  sum(s.length_metre) FILTER (WHERE %1$s) / 1000 AS rear_flag_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND NOT %2$s) / 1000 AS rear_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %3$s = 'stream') / 1000 AS rear_stream_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %3$s = 'lake') / 1000 AS rear_lake_flag_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %3$s = 'lake' AND NOT %2$s) / 1000 AS rear_lake_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %3$s = 'wetland') / 1000 AS rear_wetland_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %2$s) / 1000 AS rear_connection_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %2$s AND s.edge_type = 1400) / 1000 AS rear_connection_1400_km,
  sum(s.length_metre) FILTER (WHERE %1$s AND %2$s AND s.edge_type = 1450) / 1000 AS rear_connection_1450_km",
  flag, conn_pred, wb_class)

num <- function(d) {
  d[] <- lapply(d, function(x) {
    if (inherits(x, "integer64")) x <- as.numeric(x)
    if (is.numeric(x)) round(ifelse(is.na(x), 0, x), 3) else x
  })
  d
}

wsgs <- c("ADMS", "NATR")
link <- do.call(rbind, lapply(wsgs, function(w) {
  d <- num(DBI::dbGetQuery(conn, sprintf("
    SELECT h.species_code, %s
    FROM zz310_snap.%s_b h
    JOIN zz311_%s.streams s USING (id_segment)
    %s
    GROUP BY 1 ORDER BY 1", km_cols("h.rearing"), tolower(w), tolower(w),
    wb_join)))
  cbind(aoi = w, d)
}))
link$parts_minus_total <- round(link$rear_stream_km + link$rear_lake_km +
                                  link$rear_wetland_km - link$rear_km, 3)
utils::write.csv(link, file.path(out_dir, "measure.csv"), row.names = FALSE)

bcfp_cols <- DBI::dbGetQuery(conn, "
  SELECT column_name FROM information_schema.columns
  WHERE table_schema = 'fresh' AND table_name = 'streams_vw_bcfp'
    AND column_name LIKE 'rearing\\_%'")$column_name
ref <- do.call(rbind, lapply(bcfp_cols, function(cl) {
  d <- num(DBI::dbGetQuery(conn, sprintf("
    SELECT s.watershed_group_code AS aoi, %s
    FROM fresh.streams_vw_bcfp s
    %s
    WHERE s.watershed_group_code IN (%s)
    GROUP BY 1", km_cols(sprintf("s.%s IN (1, 2)", cl)), wb_join,
    paste0("'", wsgs, "'", collapse = ", "))))
  if (nrow(d)) d$species_code <- toupper(sub("^rearing_", "", cl))
  d
}))
utils::write.csv(ref, file.path(out_dir, "reference.csv"), row.names = FALSE)

# Adams Lake, the case that opened the issue
adams <- num(DBI::dbGetQuery(conn, sprintf("
  SELECT h.species_code, s.edge_type,
         sum(s.length_metre) / 1000 AS rear_km
  FROM zz310_snap.adms_b h
  JOIN zz311_adms.streams s USING (id_segment)
  JOIN whse_basemapping.fwa_lakes_poly l ON l.waterbody_key = s.waterbody_key
  WHERE h.rearing AND l.gnis_name_1 = 'Adams Lake'
  GROUP BY 1, 2 ORDER BY 1, 2")))
utils::write.csv(adams, file.path(out_dir, "adams_lake.csv"), row.names = FALSE)
DBI::dbDisconnect(conn)
