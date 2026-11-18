suppressMessages(library(DBI))
conn <- dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost", port = 5432L, user = "postgres", password = "postgres")
cols <- dbGetQuery(conn, "SELECT column_name FROM information_schema.columns WHERE table_schema='zz472_main' AND table_name='streams_access' ORDER BY ordinal_position")$column_name
key <- c("id_segment", "watershed_group_code")
for (c in setdiff(cols, key)) {
  r <- dbGetQuery(conn, sprintf("SELECT m.%1$s::text AS main, h.%1$s::text AS head, count(*)::int n, round(sum(s.length_metre)::numeric/1000, 2) km
    FROM zz472_main.streams_access m JOIN zz472_head.streams_access h USING (id_segment, watershed_group_code)
    JOIN zz472_head.streams s USING (id_segment, watershed_group_code)
    WHERE m.watershed_group_code='GUIC' AND m.%1$s IS DISTINCT FROM h.%1$s GROUP BY 1,2 ORDER BY 3 DESC", c))
  if (nrow(r)) { cat("--", c, "\n"); print(r) }
}
print(dbGetQuery(conn, "SELECT count(*) FROM zz472_main.streams_access WHERE watershed_group_code='GUIC' AND access_ch = 2"))
print(dbGetQuery(conn, "SELECT count(*) FROM zz472_head.streams_access WHERE watershed_group_code='GUIC' AND access_ch = 2"))
