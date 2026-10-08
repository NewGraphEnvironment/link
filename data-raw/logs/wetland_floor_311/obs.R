# Usage: Rscript obs.R <out_csv> <from_run> <to_run> <aoi>...
# Observation exposure of a rearing change, read from run.R's snapshots
# (zz311_snap.<aoi>_<run>): per species, the observations on segments
# rearing under <from_run> and on those that stop rearing under <to_run>.
# Same filters as lnk_habitat_validate()'s defaults: match-type class A/B (first character), no
# "Releases Database", BT pooled with DV. An observation sits on the
# segment whose [downstream, upstream) measure range holds it (observations
# are break points; the segment starting there is the one upstream).
args <- commandArgs(trailingOnly = TRUE)
out_csv <- args[1]; from <- args[2]; to <- args[3]; aois <- args[-(1:3)]
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
                       host = "localhost", port = 5432L,
                       user = "postgres", password = "postgres")
pool <- list(BT = c("BT", "DV"))
res <- list()
for (aoi in aois) {
  a <- tolower(aoi)
  sps <- DBI::dbGetQuery(conn, sprintf(
    "SELECT DISTINCT species_code FROM zz311_snap.%s_%s", a, from))$species_code
  for (sp in sps) {
    obs_sp <- pool[[sp]] %||% sp
    d <- DBI::dbGetQuery(conn, sprintf("
      WITH seg AS (
        SELECT s.id_segment, s.blue_line_key, s.downstream_route_measure AS dr,
               s.upstream_route_measure AS ur, f.rearing AS r_from, t.rearing AS r_to
        FROM zz311_%1$s.streams s
        JOIN zz311_snap.%1$s_%2$s f USING (id_segment)
        JOIN zz311_snap.%1$s_%3$s t USING (id_segment)
        WHERE f.species_code = '%4$s' AND t.species_code = '%4$s'),
      o AS (
        SELECT DISTINCT o.blue_line_key, o.downstream_route_measure
        FROM bcfishobs.observations o
        WHERE o.watershed_group_code = '%5$s'
          AND o.species_code IN (%6$s)
          AND left(o.match_type, 1) IN ('A', 'B')
          AND o.source IS DISTINCT FROM 'Releases Database')
      SELECT count(*) FILTER (WHERE seg.r_from) AS n_obs_rear_from,
             count(*) FILTER (WHERE seg.r_from AND NOT seg.r_to) AS n_obs_lost,
             count(*) FILTER (WHERE NOT seg.r_from AND seg.r_to) AS n_obs_gained
      FROM o JOIN seg ON seg.blue_line_key = o.blue_line_key
        AND o.downstream_route_measure >= seg.dr
        AND o.downstream_route_measure < seg.ur",
      a, tolower(from), tolower(to), sp, aoi,
      paste0("'", obs_sp, "'", collapse = ", ")))
    d[] <- lapply(d, as.numeric)
    res[[length(res) + 1]] <- data.frame(aoi = aoi, species_code = sp,
                                         from = from, to = to, d)
  }
}
DBI::dbDisconnect(conn)
out <- do.call(rbind, res)
utils::write.csv(out, out_csv, row.names = FALSE)
print(out, row.names = FALSE)
