# Usage: Rscript reclassify.R <repo> <config name|path> <aoi> <schema> [method_csv]
# Re-runs ONLY classify + connect on an already-prepared working schema, so
# segmentation is held fixed and only the classify path is exercised. With a
# 5th argument, passes it as method_csv (needs a repo that has the argument).
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; cfg_arg <- args[2]; aoi <- args[3]; schema <- args[4]
method_csv <- if (length(args) >= 5L) args[5] else NULL
# LNK_LIBPRE: a library to put first, e.g. one holding fresh v0.33.0.
if (nzchar(Sys.getenv("LNK_LIBPRE"))) .libPaths(c(Sys.getenv("LNK_LIBPRE"), .libPaths()))
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config(cfg_arg)
loaded <- suppressWarnings(lnk_load_overrides(cfg))
if (is.null(method_csv)) {
  lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
} else {
  lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema,
                        method_csv = method_csv)
}
lnk_pipeline_connect(conn, aoi = aoi, cfg = cfg, loaded = loaded, schema = schema)
d <- DBI::dbGetQuery(conn, sprintf(
  "SELECT h.species_code, count(*) AS n,
          sum(h.spawning::int) AS n_spawn, sum(h.rearing::int) AS n_rear,
          round(sum(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS spawn_km,
          round(sum(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS rear_km,
          md5(string_agg(h::text, '|' ORDER BY h.id_segment, h.species_code)) AS digest
   FROM %1$s.streams_habitat h JOIN %1$s.streams s USING (id_segment)
   GROUP BY h.species_code ORDER BY h.species_code", schema))
cat(sprintf("## reclassify %s %s %s repo=%s method_csv=%s link=%s fresh=%s\n", aoi,
            cfg$name, schema, basename(repo), method_csv %||% "<bundle/default>",
            utils::packageVersion("link"), utils::packageVersion("fresh")))
print(d, row.names = FALSE)
DBI::dbDisconnect(conn)
