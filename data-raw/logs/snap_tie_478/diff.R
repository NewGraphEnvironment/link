# Compare the before and after snap-and-pick tables from snap_pick.R (link#478).
#
#   Rscript data-raw/logs/snap_tie_478/diff.R
#
# Writes picks_moved.csv (every PSCIS whose pick appears, disappears or moves
# segment, stream or measure), dams_moved.csv (the same for the CABD dam snap)
# and summary.csv.

out <- "data-raw/logs/snap_tie_478"
conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                       port = 5432L, user = "postgres", password = "postgres")

picks <- DBI::dbGetQuery(conn, "
  SELECT COALESCE(b.stream_crossing_id, a.stream_crossing_id) AS stream_crossing_id,
         b.linear_feature_id AS lfid_before, a.linear_feature_id AS lfid_after,
         b.blue_line_key AS blk_before, a.blue_line_key AS blk_after,
         b.downstream_route_measure AS drm_before, a.downstream_route_measure AS drm_after,
         b.watershed_group_code AS wsg_before, a.watershed_group_code AS wsg_after,
         b.wscode_ltree::text AS wscode_before,
         round(b.distance_to_stream::numeric, 3) AS dist_before,
         round(a.distance_to_stream::numeric, 3) AS dist_after,
         CASE WHEN a.stream_crossing_id IS NULL THEN 'dropped'
              WHEN b.stream_crossing_id IS NULL THEN 'added'
              WHEN a.blue_line_key <> b.blue_line_key THEN 'stream'
              WHEN a.downstream_route_measure <> b.downstream_route_measure THEN 'measure'
              ELSE 'segment' END AS change
  FROM zz478_before.pscis_picked b
  FULL JOIN zz478_after.pscis_picked a USING (stream_crossing_id)
  WHERE a.stream_crossing_id IS NULL OR b.stream_crossing_id IS NULL
     OR a.linear_feature_id <> b.linear_feature_id
     OR a.blue_line_key <> b.blue_line_key
     OR a.downstream_route_measure <> b.downstream_route_measure
  ORDER BY 1")

dams <- DBI::dbGetQuery(conn, "
  SELECT COALESCE(b.dam_id, a.dam_id) AS dam_id,
         b.linear_feature_id AS lfid_before, a.linear_feature_id AS lfid_after,
         b.downstream_route_measure AS drm_before, a.downstream_route_measure AS drm_after
  FROM zz478_before.dams_matched b
  FULL JOIN zz478_after.dams_matched a USING (dam_id)
  WHERE a.dam_id IS NULL OR b.dam_id IS NULL
     OR a.linear_feature_id <> b.linear_feature_id
     OR a.downstream_route_measure <> b.downstream_route_measure
  ORDER BY 1")

# Distances of picks that did not move: did the snap's distance change?
dist <- DBI::dbGetQuery(conn, "
  SELECT count(*) AS n_same_pick,
         max(abs(a.distance_to_stream - b.distance_to_stream)) AS max_abs_dist_diff
  FROM zz478_before.pscis_picked b
  JOIN zz478_after.pscis_picked a USING (stream_crossing_id)
  WHERE a.linear_feature_id = b.linear_feature_id
    AND a.downstream_route_measure = b.downstream_route_measure")
DBI::dbDisconnect(conn)

picks[] <- lapply(picks, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
dams[] <- lapply(dams, function(x) if (inherits(x, "integer64")) as.numeric(x) else x)
utils::write.csv(picks, file.path(out, "picks_moved.csv"), row.names = FALSE)
utils::write.csv(dams, file.path(out, "dams_moved.csv"), row.names = FALSE)
summ <- data.frame(
  kind = c(names(table(picks$change)), "dams_moved", "same_pick", "max_abs_dist_diff_m"),
  n = format(c(as.integer(table(picks$change)), nrow(dams),
               as.numeric(dist$n_same_pick),
               signif(as.numeric(dist$max_abs_dist_diff), 3)),
             scientific = FALSE, drop0trailing = TRUE, trim = TRUE))
utils::write.csv(summ, file.path(out, "summary.csv"), row.names = FALSE)
print(summ)
print(utils::head(picks, 40))
