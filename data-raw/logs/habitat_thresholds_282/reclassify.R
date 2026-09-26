# Usage: Rscript reclassify.R <repo> <config name|path> <aoi> <schema>
# Re-runs ONLY classify + connect on an already-prepared working schema, so
# segmentation is held fixed and only the threshold path is exercised.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; cfg_arg <- args[2]; aoi <- args[3]; schema <- args[4]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(cfg_arg)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
d <- DBI::dbGetQuery(conn, sprintf(
  "SELECT species_code, count(*) AS n,
          sum(spawning::int) AS n_spawn, sum(rearing::int) AS n_rear,
          md5(string_agg(t::text, '|' ORDER BY id_segment, species_code)) AS digest
   FROM %s.streams_habitat t GROUP BY species_code ORDER BY species_code", schema))
cat(sprintf("## reclassify %s %s %s repo=%s\n", aoi, cfg$name, schema, basename(repo)))
print(d, row.names = FALSE)
DBI::dbDisconnect(conn)
