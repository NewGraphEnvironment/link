# Usage (from the repo root, with the bcfishpass tunnel up): Rscript data-raw/logs/lake_connection_317/parity_bcfishpass.R
# #317 symmetric-rule check on the bcfishpass-config persist (`fresh`): lnk_compare_rollup()
# (lake connection lines out of rearing km on both sides) for the WSGs the taxonomy pins
# bands on. Writes parity_bcfishpass.csv.
suppressMessages(devtools::load_all(".", quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L, user = "postgres", password = "postgres")
ref <- lnk_db_conn()
print(DBI::dbGetQuery(ref, "select current_database(), inet_server_port()"))
cfg <- lnk_config("bcfishpass")
w_all <- c("BULK","CHWK","KUMR","LRDO","NASC","NASR","NEVI","QUES","TOBA","THOM","OWIK","STIR","SQAM","NECR","NECL","ATNA","KNIG","BBAR","MFRA")
have <- DBI::dbGetQuery(conn, "select distinct watershed_group_code w from fresh.streams")$w
out <- do.call(rbind, lapply(intersect(w_all, have), function(w) {
  sp <- c("SK","CH","CO","ST")
  r <- tryCatch(lnk_compare_rollup(conn, aoi = w, cfg = cfg, reference = "bcfishpass", conn_ref = ref, species = sp), error = function(e) {message(w, ": ", conditionMessage(e)); NULL})
  r[r$habitat_type %in% c("rearing","rearing_lake","rearing_lake_connection","rearing_stream"), ]
}))
write.csv(out, "data-raw/logs/lake_connection_317/parity_bcfishpass.csv", row.names = FALSE)
print(as.data.frame(out[out$habitat_type %in% c("rearing","rearing_lake_connection"), ]), row.names = FALSE)
