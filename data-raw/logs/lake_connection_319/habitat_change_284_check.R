# #284 habitat_change.csv rearing_km / spawning_km, recomputed with
# lnk_rollup_wsg()'s #319 default on the score284_* schemas (#319 step 4).
suppressMessages(pkgload::load_all(quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
DBI::dbExecute(conn, "SET statement_timeout = 180000")
hc <- utils::read.csv("data-raw/logs/habitat_score_284/habitat_change.csv")
n_bad <- 0L
for (i in seq_len(nrow(hc))) {
  w <- hc$watershed_group_code[i]
  v <- lnk_rollup_wsg(conn, w, "BT", schema = paste0("score284_", hc$variant[i]))
  b <- lnk_rollup_wsg(conn, w, "BT", schema = "score284_default")
  ok <- identical(v$rearing_km, hc$rearing_km[i]) &&
    identical(b$rearing_km, hc$rearing_km_base[i]) &&
    identical(v$spawning_km, hc$spawning_km[i]) &&
    v$rearing_lake_connection_km == 0 && b$rearing_lake_connection_km == 0
  if (!ok) { n_bad <- n_bad + 1L; print(cbind(hc[i, 1:3], v, b)) }
}
cat(nrow(hc), "habitat_change rows checked;", n_bad, "differ\n")
DBI::dbDisconnect(conn)
