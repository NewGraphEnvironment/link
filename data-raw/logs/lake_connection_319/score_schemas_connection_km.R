# Lake connection lines flagged `rearing` in the #284 / #300 / #302 / #305
# score schemas (#319). Same lines as .lnk_sql_lake_connection(): edge 1450
# in a lake or reservoir polygon (.lnk_sql_lake_polys()).
suppressMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
tabs <- DBI::dbGetQuery(conn, "
  SELECT table_schema AS s, table_name AS t FROM information_schema.tables
   WHERE table_schema LIKE 'score%' AND table_name LIKE 'streams_habitat_%'")
tabs <- tabs[grepl("^score(284|300|302|305)_", tabs$s) &
               grepl("^streams_habitat_[a-z]+$", tabs$t), ]
out <- list()
for (s in sort(unique(tabs$s))) {
  n_lines <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) AS n, COALESCE(sum(s.length_metre), 0) / 1000 AS km
       FROM %s.streams s JOIN %s l ON l.waterbody_key = s.waterbody_key
      WHERE s.edge_type = 1450", s, .lnk_sql_lake_polys()))
  per_sp <- paste(vapply(tabs$t[tabs$s == s], function(t) sprintf(
    "SELECT '%s' AS species, c.watershed_group_code AS wsg,
            sum(c.length_metre) / 1000 AS rearing_conn_km
       FROM c JOIN %s.%s h
         ON h.id_segment = c.id_segment
        AND h.watershed_group_code = c.watershed_group_code
      WHERE h.rearing GROUP BY c.watershed_group_code",
    toupper(sub("streams_habitat_", "", t)), s, t), ""), collapse = " UNION ALL ")
  r <- DBI::dbGetQuery(conn, sprintf(
    "WITH c AS (SELECT s.id_segment, s.watershed_group_code, s.length_metre
                  FROM %s.streams s JOIN %s l ON l.waterbody_key = s.waterbody_key
                 WHERE s.edge_type = 1450) %s", s, .lnk_sql_lake_polys(), per_sp))
  cat(sprintf("%-26s lake 1450 lines: %6d (%7.1f km); rearing on them: %d species-WSG rows, %.1f km\n",
              s, as.integer(n_lines$n), n_lines$km, nrow(r), sum(r$rearing_conn_km)))
  if (nrow(r)) out[[s]] <- cbind(schema = s, r)
}
d <- if (length(out)) do.call(rbind, out) else
  data.frame(schema = character(), species = character(), wsg = character(),
             rearing_conn_km = numeric())
utils::write.csv(d, "data-raw/logs/lake_connection_319/score_schemas_connection_km.csv",
                 row.names = FALSE)
DBI::dbDisconnect(conn)
