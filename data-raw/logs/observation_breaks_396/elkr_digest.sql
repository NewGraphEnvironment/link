-- Digest of ELKR's persisted rows in both #396 schemas, taken before and after
-- run_elkr_repeat.sh, to show the repeat left them as they were.
--   psql -X -A -F, -f data-raw/logs/observation_breaks_396/elkr_digest.sql
SELECT s.schema, t.tbl,
       md5(string_agg(t.row, '|' ORDER BY t.row)) AS digest, count(*) AS n
FROM (VALUES ('zz396_default_pre'), ('zz396_default_post')) s(schema)
CROSS JOIN LATERAL (
  SELECT 'streams' AS tbl,
         concat_ws(',', blue_line_key, downstream_route_measure,
                   upstream_route_measure, gradient, channel_width) AS row
    FROM (SELECT * FROM zz396_default_pre.streams WHERE s.schema = 'zz396_default_pre'
          UNION ALL SELECT * FROM zz396_default_post.streams WHERE s.schema = 'zz396_default_post') x
   WHERE watershed_group_code = 'ELKR'
  UNION ALL
  SELECT 'streams_access',
         concat_ws(',', s2.blue_line_key, s2.downstream_route_measure, a.access_bt,
                   a.access_wct, a.access_rb, a.access_gr, a.has_barriers_bt_dnstr)
    FROM (SELECT * FROM zz396_default_pre.streams_access WHERE s.schema = 'zz396_default_pre'
          UNION ALL SELECT * FROM zz396_default_post.streams_access WHERE s.schema = 'zz396_default_post') a
    JOIN (SELECT id_segment, watershed_group_code, blue_line_key, downstream_route_measure
            FROM zz396_default_pre.streams WHERE s.schema = 'zz396_default_pre'
          UNION ALL SELECT id_segment, watershed_group_code, blue_line_key, downstream_route_measure
            FROM zz396_default_post.streams WHERE s.schema = 'zz396_default_post') s2
      ON s2.id_segment = a.id_segment AND s2.watershed_group_code = a.watershed_group_code
   WHERE a.watershed_group_code = 'ELKR'
  UNION ALL
  SELECT 'streams_habitat_bt',
         concat_ws(',', s3.blue_line_key, s3.downstream_route_measure, h.accessible,
                   h.spawning, h.rearing)
    FROM (SELECT * FROM zz396_default_pre.streams_habitat_bt WHERE s.schema = 'zz396_default_pre'
          UNION ALL SELECT * FROM zz396_default_post.streams_habitat_bt WHERE s.schema = 'zz396_default_post') h
    JOIN (SELECT id_segment, watershed_group_code, blue_line_key, downstream_route_measure
            FROM zz396_default_pre.streams WHERE s.schema = 'zz396_default_pre'
          UNION ALL SELECT id_segment, watershed_group_code, blue_line_key, downstream_route_measure
            FROM zz396_default_post.streams WHERE s.schema = 'zz396_default_post') s3
      ON s3.id_segment = h.id_segment AND s3.watershed_group_code = h.watershed_group_code
   WHERE h.watershed_group_code = 'ELKR'
) t
GROUP BY s.schema, t.tbl ORDER BY 1, 2;
