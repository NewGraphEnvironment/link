# The defect #321 names, measured: main's lnk_aggregate() sums only the
# crossing's own stream above it; the rebuilt one walks the network.
#
#   Rscript data-raw/logs/crossings_upstream_478/defect.R <main worktree> <persist schema> <WSG>
#
# Runs main's function (load_all from the worktree) on a flat habitat table
# built from the persist schema for one species (CH, else BT), and compares it
# with the branch's lnk_aggregate() output that parity.R left in
# working_<wsg>.crossings_upstream_habitat. Writes defect_<wsg>.csv here.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
main_wt <- args[1]; schema <- args[2]; wsg <- toupper(args[3])
ws <- paste0("working_", tolower(wsg))
out <- "data-raw/logs/crossings_upstream_478"

pkgload::load_all(main_wt, quiet = TRUE)
stopifnot("habitat" %in% names(formals(lnk_aggregate)))  # main's signature
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")
sp <- if (DBI::dbExistsTable(conn, DBI::Id(schema = schema, table = "streams_habitat_ch"))) "CH" else "BT"
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.zz478_flat", ws))
DBI::dbExecute(conn, sprintf("
  CREATE TABLE %1$s.zz478_flat AS
  SELECT s.blue_line_key, s.downstream_route_measure, s.length_metre,
         h.spawning, h.rearing
    FROM %2$s.streams s JOIN %2$s.streams_habitat_%3$s h USING (id_segment, watershed_group_code)",
  ws, schema, tolower(sp)))
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.zz478_old", ws))
suppressMessages(lnk_aggregate(conn, paste0(ws, ".crossings"), paste0(ws, ".zz478_flat"),
                               col_id = "aggregated_crossings_id",
                               to = paste0(ws, ".zz478_old"), verbose = FALSE))
d <- DBI::dbGetQuery(conn, sprintf("
  SELECT o.aggregated_crossings_id, o.spawning_km::float8 AS old_spawning_km,
         n.spawning_km::float8 AS new_spawning_km,
         o.rearing_km::float8 AS old_rearing_km,
         (n.rearing_km + n.rearing_lake_connection_km)::float8 AS new_rearing_km
    FROM %1$s.zz478_old o
    JOIN %1$s.crossings_upstream_habitat n
      ON n.aggregated_crossings_id::text = o.aggregated_crossings_id::text
     AND n.species_code = '%2$s'
   ORDER BY 1", ws, sp))
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.zz478_flat", ws))
DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.zz478_old", ws))
DBI::dbDisconnect(conn)
s <- data.frame(
  wsg = wsg, species_code = sp, n_crossings = nrow(d),
  n_new_spawning_more = sum(d$new_spawning_km > d$old_spawning_km + 0.001),
  n_new_rearing_more = sum(d$new_rearing_km > d$old_rearing_km + 0.001),
  old_spawning_total_km = round(sum(d$old_spawning_km), 1),
  new_spawning_total_km = round(sum(d$new_spawning_km), 1),
  old_rearing_total_km = round(sum(d$old_rearing_km), 1),
  new_rearing_total_km = round(sum(d$new_rearing_km), 1))
utils::write.csv(s, file.path(out, sprintf("defect_%s.csv", tolower(wsg))), row.names = FALSE)
print(s)
