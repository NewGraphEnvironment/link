suppressPackageStartupMessages({
  library(sf); library(mapgl); library(dplyr); library(DBI)
})
sf_use_s2(FALSE)

source("/Users/airvine/Projects/repo/link/data-raw/maps/_lnk_map_compare.R")

local_conn <- function() dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")

ref_conn <- function() dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass",
  user = Sys.getenv("PG_USER_SHARE", "newgraph"),
  password = Sys.getenv("PG_PASS_SHARE"))

lnk_map_compare(
  wsg = "BULK", species = "SK", habitat = "spawning",
  conn_local = local_conn, conn_ref = ref_conn)
