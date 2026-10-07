# Usage: Rscript mad_check.R <repo> <aoi> <schema> <method_csv>
# Classify ONLY (no overlay, no connect) on a prepared working schema with the
# given method table, then check fresh's mad invariants straight off
# frs_habitat_classify's output:
#   - every spawning / rearing segment has mad_m3s inside [*_mad_min, *_mad_max]
#   - no segment with NULL mad_m3s is spawning or rearing
# *_nowb: segments outside any waterbody (waterbody_key IS NULL) -- the
# "stream habitat" that species without MAD thresholds must have none of.
# and report stream / lake / wetland km per species. Config `default`.
#
# Adapted for #307 from ../params_method_286/mad_check.R: the invariant is
# also counted on stream segments only (`*_out_nowb`, `*_null_nowb`, waterbody_key
# IS NULL). Rows that the L/W rules and the `thresholds: false` 1050/1150 edges
# admit inherit no size test, so once a species has a range they read as `*_out`
# by design (#286 found 222 CH and 128 CO such rows on ADMS); only `*_nowb` is the
# invariant.
args <- commandArgs(trailingOnly = TRUE)
repo <- args[1]; aoi <- args[2]; schema <- args[3]; method_csv <- args[4]
suppressMessages(devtools::load_all(repo, quiet = TRUE))
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
cfg$pipeline$apply_habitat_overlay <- FALSE
loaded <- suppressWarnings(lnk_load_overrides(cfg))
lnk_pipeline_classify(conn, aoi = aoi, cfg = cfg, loaded = loaded,
                      schema = schema, method_csv = method_csv)
th <- utils::read.csv(.lnk_habitat_thresholds_csv(cfg))
th <- th[, c("species_code", "spawn_mad_min", "spawn_mad_max",
             "rear_mad_min", "rear_mad_max")]
DBI::dbWriteTable(conn, DBI::Id(schema = schema, table = "zz_mad_th"), th,
                  overwrite = TRUE)
q <- sprintf(
  "SELECT h.species_code,
     sum(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)/1000 AS spawn_km,
     sum(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)/1000 AS rear_km,
     sum(CASE WHEN h.spawning AND s.waterbody_key IS NULL THEN s.length_metre ELSE 0 END)/1000 AS spawn_km_nowb,
     sum(CASE WHEN h.rearing AND s.waterbody_key IS NULL THEN s.length_metre ELSE 0 END)/1000 AS rear_km_nowb,
     sum(CASE WHEN h.lake_rearing THEN s.length_metre ELSE 0 END)/1000 AS lake_km,
     sum(CASE WHEN h.wetland_rearing THEN s.length_metre ELSE 0 END)/1000 AS wetland_km,
     count(*) FILTER (WHERE h.spawning AND s.mad_m3s IS NULL) AS spawn_null_mad,
     count(*) FILTER (WHERE h.rearing AND s.mad_m3s IS NULL) AS rear_null_mad,
     count(*) FILTER (WHERE h.spawning AND NOT (s.mad_m3s BETWEEN t.spawn_mad_min AND t.spawn_mad_max)) AS spawn_out,
     count(*) FILTER (WHERE h.spawning AND t.spawn_mad_min IS NULL) AS spawn_no_th,
     count(*) FILTER (WHERE h.rearing AND NOT (s.mad_m3s BETWEEN t.rear_mad_min AND t.rear_mad_max)) AS rear_out,
     count(*) FILTER (WHERE h.rearing AND t.rear_mad_min IS NULL) AS rear_no_th,
     count(*) FILTER (WHERE h.spawning AND s.waterbody_key IS NULL AND NOT (s.mad_m3s BETWEEN t.spawn_mad_min AND t.spawn_mad_max)) AS spawn_out_nowb,
     count(*) FILTER (WHERE h.rearing AND s.waterbody_key IS NULL AND NOT (s.mad_m3s BETWEEN t.rear_mad_min AND t.rear_mad_max)) AS rear_out_nowb,
     count(*) FILTER (WHERE (h.spawning OR h.rearing) AND s.waterbody_key IS NULL AND s.mad_m3s IS NULL) AS null_nowb
   FROM %1$s.streams_habitat h
   JOIN %1$s.streams s USING (id_segment)
   LEFT JOIN %1$s.zz_mad_th t USING (species_code)
   GROUP BY h.species_code ORDER BY h.species_code", schema)
d <- DBI::dbGetQuery(conn, q)
num <- vapply(d, is.numeric, logical(1))
d[num] <- lapply(d[num], function(x) round(as.numeric(x), 1))
cat(sprintf("## mad_check %s %s method_csv=%s link=%s fresh=%s (classify only, overlay off)\n",
            aoi, schema, basename(method_csv), utils::packageVersion("link"),
            utils::packageVersion("fresh")))
print(d, row.names = FALSE)
DBI::dbExecute(conn, sprintf("DROP TABLE %s.zz_mad_th", schema))
DBI::dbDisconnect(conn)
