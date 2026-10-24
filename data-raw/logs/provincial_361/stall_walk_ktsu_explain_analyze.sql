EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE OFF)
     WITH origins AS (
       SELECT id_segment, watershed_group_code,
         channel_width::double precision AS val, blue_line_key,
         downstream_route_measure, wscode_ltree, localcode_ltree, geom
       FROM working_ktsu.streams
       WHERE (channel_width IS NULL OR channel_width < 15)
         -- FWA_Downstream() would still join a row with no local code to
         -- the bottom row of every ancestor line (its wscode = localcode
         -- branch never reads the origin's local code), skipping the
         -- network between; such a row has no place to start from.
         AND localcode_ltree IS NOT NULL
     ),
     downstream AS (
       SELECT o.id_segment AS origin_id, o.watershed_group_code,
         o.val AS origin_val, t.id_segment, t.edge_type,
         t.channel_width::double precision AS val,
         t.length_metre, t.waterbody_key, t.wscode_ltree,
         t.downstream_route_measure, t.geom,
         coalesce(LAG(ST_StartPoint(t.geom)) OVER (PARTITION BY o.id_segment
           ORDER BY t.wscode_ltree DESC, t.downstream_route_measure DESC, t.id_segment DESC), ST_StartPoint(o.geom)) AS prev_pt,
         -- The row directly above this one on its own line. If it is on
         -- the path but the prefilter dropped it, the walk cannot reach
         -- this row without it: the path is cut here.
         EXISTS (
           SELECT 1 FROM (
             SELECT r.blue_line_key, r.downstream_route_measure,
               r.wscode_ltree, r.localcode_ltree, r.geom
             FROM working_ktsu.streams r
             WHERE r.blue_line_key = t.blue_line_key
               AND r.downstream_route_measure > t.downstream_route_measure
             ORDER BY r.downstream_route_measure LIMIT 1) r
           WHERE (r.blue_line_key <> o.blue_line_key
                  OR r.downstream_route_measure < o.downstream_route_measure)
             AND NOT ST_DWithin(r.geom, o.geom, 2205.493764)
             AND FWA_Downstream(
               o.blue_line_key, o.downstream_route_measure,
               o.wscode_ltree, o.localcode_ltree,
               r.blue_line_key, r.downstream_route_measure,
               r.wscode_ltree, r.localcode_ltree)) AS above_dropped
       FROM origins o
       INNER JOIN working_ktsu.streams t ON FWA_Downstream(
         o.blue_line_key, o.downstream_route_measure,
         o.wscode_ltree, o.localcode_ltree,
         t.blue_line_key, t.downstream_route_measure,
         t.wscode_ltree, t.localcode_ltree)
       WHERE t.blue_line_key = t.watershed_key
         AND (t.blue_line_key <> o.blue_line_key
              OR t.downstream_route_measure < o.downstream_route_measure)
         AND ST_DWithin(t.geom, o.geom, 2205.493764)
     ),
     entered AS (
       SELECT origin_id, watershed_group_code, origin_val, id_segment,
         edge_type, val, length_metre, waterbody_key, wscode_ltree,
         downstream_route_measure,
         ST_Distance(prev_pt, geom) AS jump_m,
         length_metre * ST_LineLocatePoint(ST_Force2D(geom),
           ST_Force2D(prev_pt)) AS below_m,
         CASE WHEN ST_Distance(prev_pt, geom) > 0.001 AND waterbody_key IS NOT NULL THEN least(0, coalesce((SELECT sum(ST_Length(ST_Intersection(ST_MakeLine(ST_Force2D(downstream.prev_pt), ST_Force2D(ST_ClosestPoint(downstream.geom, downstream.prev_pt))), p.geom))) FROM (SELECT waterbody_key, geom FROM whse_basemapping.fwa_rivers_poly UNION ALL SELECT waterbody_key, geom FROM whse_basemapping.fwa_lakes_poly UNION ALL SELECT waterbody_key, geom FROM whse_basemapping.fwa_manmade_waterbodies_poly UNION ALL SELECT waterbody_key, geom FROM whse_basemapping.fwa_wetlands_poly) p WHERE p.waterbody_key = downstream.waterbody_key), 0)) ELSE 0 END AS entry_in_m, above_dropped
       FROM downstream
     ),
     walked AS (
       SELECT origin_id, watershed_group_code, origin_val, edge_type,
         val, below_m,
         SUM(below_m + jump_m) OVER w - below_m AS path_m,
         CASE WHEN waterbody_key IS NULL THEN 0 ELSE least(1205.493764, SUM(CASE WHEN edge_type IN (1400, 1450) THEN below_m ELSE 0 END + entry_in_m) OVER (PARTITION BY origin_id, waterbody_key ORDER BY wscode_ltree DESC, downstream_route_measure DESC, id_segment DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) END AS connector_m,
         bool_or(above_dropped) OVER w AS cut
       FROM entered
       WINDOW w AS (PARTITION BY origin_id ORDER BY wscode_ltree DESC, downstream_route_measure DESC, id_segment DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
     ),
     capped AS (
       SELECT * FROM walked WHERE path_m <= 2205.493764 AND NOT cut
     )
     SELECT c.origin_id, c.watershed_group_code, q.threshold,
       greatest(min(c.path_m - c.connector_m), 0) AS dist_m
     FROM capped c
     INNER JOIN (VALUES (15::double precision, 1000::double precision)) AS q(threshold, distance_max)
       ON c.val >= q.threshold
      AND c.edge_type NOT IN (1400, 1450)
      AND (c.origin_val IS NULL OR c.origin_val < q.threshold)
      AND c.path_m - c.connector_m <= q.distance_max
     GROUP BY c.origin_id, c.watershed_group_code, q.threshold
