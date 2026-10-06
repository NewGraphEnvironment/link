# Usage: Rscript verify_classify.R <repo> <config name|path> <aoi> <schema>
# Runs link phases setup..connect into a scratch working schema (never persists),
# then prints a per-species digest of <schema>.streams_habitat.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; cfg_arg <- args[2]; aoi <- args[3]; schema <- args[4]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(cfg_arg)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
t0 <- Sys.time()
lnk_pipeline_setup(conn, schema, overwrite = TRUE)
lnk_pipeline_load(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_prepare(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema,
                     conn_tunnel = conn)
lnk_pipeline_crossings(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_break(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
cols <- DBI::dbGetQuery(conn, sprintf(
  "SELECT column_name FROM information_schema.columns
   WHERE table_schema = '%s' AND table_name = 'streams_habitat'
   ORDER BY column_name", schema))$column_name
keycols <- intersect(c("id_segment", "species_code"), cols)
d <- DBI::dbGetQuery(conn, sprintf(
  "SELECT species_code, count(*) AS n,
          sum(spawning::int) AS n_spawn, sum(rearing::int) AS n_rear,
          md5(string_agg(t::text, '|' ORDER BY %s)) AS digest
   FROM %s.streams_habitat t GROUP BY species_code ORDER BY species_code",
  paste(keycols, collapse = ", "), schema))
seg <- DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*) AS n, md5(string_agg(id_segment::text || ':' ||
          round(gradient::numeric, 6)::text, '|' ORDER BY id_segment)) AS digest
   FROM %s.streams", schema))
cat(sprintf("## %s %s %s  link=%s fresh=%s  cfg_hash=%s  %.1f min\n", aoi,
            cfg$name, schema, utils::packageVersion("link"),
            utils::packageVersion("fresh"), .lnk_config_hash(cfg),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat(sprintf("streams n=%s digest=%s\n", format(seg$n), seg$digest))
print(d, row.names = FALSE)
DBI::dbDisconnect(conn)
