#!/usr/bin/env bash
# Two records written after the #463 proof builds, from tables those builds do
# not write. Run from the repo root: bash data-raw/logs/grad_parent_463/after.sh
#
# artifact_ids.csv (plan A1): each group's newest fresh_default build's
#   log_input artifact rows against m4's provenance.source_artifact, joined on
#   table and object URL (fwa_stream_networks_sp is one object per group).
#   `same` is TRUE only when the URL is found and version id and etag both
#   agree; a row with neither on either side reads TRUE and is not a
#   comparison (cabd.dams, pscis, fwa_stream_networks_order_parent).
#
# near_river_462_distances.csv (#462): on every 1050/1150 segment of
#   fresh_default_parent (all, whatever its CH access), the segment's own CH
#   near-river distance (fresh_default_parent.streams_near_river, channel width
#   15 m within 1000 m) against its parent's (fresh_default_minimal), the
#   parent named by fresh_default.streams_parent. n_cross_1000m counts a
#   segment where one side is within 1000 m and the other is not, or has no
#   row (IS DISTINCT FROM), so a pair missing on one side counts as a cross.
set -euo pipefail
export PGPASSWORD="${PGPASSWORD:-postgres}"
here=$(cd "$(dirname "$0")" && pwd)
wsgs="'BULK','SETN','MORK','COTR'"
pq() { psql -h localhost -U postgres -d fwapg -v ON_ERROR_STOP=1 --csv -c "$1"; }

pq "
WITH newest AS (
  SELECT DISTINCT ON (watershed_group_code) watershed_group_code, run_id
    FROM fresh_default.log
   WHERE watershed_group_code IN ($wsgs) AND date_end IS NOT NULL
   ORDER BY watershed_group_code, date_start DESC),
li AS (
  SELECT n.watershed_group_code, i.table_name, i.artifact_url, i.artifact_version_id, i.artifact_etag
    FROM newest n JOIN fresh_default.log_input i USING (run_id, watershed_group_code)
   WHERE i.artifact_url IS NOT NULL),
cur AS (
  SELECT DISTINCT ON (table_name, url) table_name, url, version_id, etag
    FROM provenance.source_artifact WHERE host = 'm4'
   ORDER BY table_name, url, recorded_at DESC)
SELECT li.watershed_group_code AS wsg, li.table_name, li.artifact_url,
       li.artifact_version_id AS build_version_id, cur.version_id AS db_version_id,
       li.artifact_etag AS build_etag, cur.etag AS db_etag,
       (cur.url IS NOT NULL
        AND li.artifact_version_id IS NOT DISTINCT FROM cur.version_id
        AND li.artifact_etag IS NOT DISTINCT FROM cur.etag) AS same
  FROM li LEFT JOIN cur ON cur.table_name = li.table_name AND cur.url = li.artifact_url
 ORDER BY 1, 2" > "$here/artifact_ids.csv"

pq "
WITH own AS (
  SELECT id_segment, watershed_group_code, dist_m FROM fresh_default_parent.streams_near_river
   WHERE measure = 'channel_width' AND threshold = 15 AND distance_max = 1000),
par AS (
  SELECT id_segment, watershed_group_code, dist_m FROM fresh_default_minimal.streams_near_river
   WHERE measure = 'channel_width' AND threshold = 15 AND distance_max = 1000),
s AS (
  SELECT s.id_segment, s.watershed_group_code AS wsg, p.id_segment_minimal AS id_m
    FROM fresh_default_parent.streams s
    JOIN fresh_default.streams_parent p
      ON p.watershed_group_code = s.watershed_group_code AND p.id_segment = s.id_segment
   WHERE s.watershed_group_code IN ($wsgs) AND s.edge_type IN (1050, 1150))
SELECT s.wsg, count(*) AS n_1050_1150, count(own.dist_m) AS n_own_row, count(par.dist_m) AS n_parent_row,
       count(*) FILTER (WHERE (own.dist_m <= 1000) IS DISTINCT FROM (par.dist_m <= 1000)) AS n_cross_1000m,
       count(*) FILTER (WHERE own.dist_m <> par.dist_m) AS n_distance_differs,
       round(max(abs(own.dist_m - par.dist_m))::numeric, 1) AS max_abs_diff_m
  FROM s
  LEFT JOIN own ON own.id_segment = s.id_segment AND own.watershed_group_code = s.wsg
  LEFT JOIN par ON par.id_segment = s.id_m AND par.watershed_group_code = s.wsg
 GROUP BY 1 ORDER BY 1" > "$here/near_river_462_distances.csv"

echo "[after] wrote artifact_ids.csv ($(($(wc -l < "$here/artifact_ids.csv") - 1)) rows) and near_river_462_distances.csv"
