-- Producers for numbers research/crossing_snap.md quotes that no other
-- script writes (link#478). Run on the local docker fwapg after snap_pick.R:
--   psql -h localhost -U postgres -d fwapg -f data-raw/logs/snap_tie_478/claims.sql > data-raw/logs/snap_tie_478/claims.txt

-- 1. The Crescent Slough dam (94dec15b...): segments, and their km, upstream
--    of its position under the old order (the slough's mouth) and under
--    fwapg's plain "higher measure" order (the side channel's top end).
WITH p AS (
  SELECT * FROM (VALUES
    ('lower id: slough mouth', 356326465, 0::float8, 701651673::bigint),
    ('higher measure: side channel top', 355991966, 1041.1218703727518, 701651674::bigint)
  ) v(placement, blk, m, lfid)),
pp AS (SELECT p.*, s.wscode_ltree w, s.localcode_ltree l
         FROM p JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id = p.lfid)
SELECT pp.placement, count(*) AS segments_upstream, round(sum(s.length_metre)::numeric / 1000, 1) AS km_upstream
  FROM pp JOIN whse_basemapping.fwa_stream_networks_sp s
    ON s.watershed_group_code = 'LFRA'
   AND whse_basemapping.fwa_upstream(pp.blk, pp.m, pp.w, pp.l, s.blue_line_key,
         s.downstream_route_measure, s.wscode_ltree, s.localcode_ltree, true, 1)
 GROUP BY 1 ORDER BY 1;

-- 2. Of sweep.R's 20,000 sampled barrier positions, how many no FWA segment
--    holds even with closed, 4-decimal bounds (FWA's gap between segments).
WITH d AS (SELECT DISTINCT blue_line_key, downstream_route_measure m FROM fresh_default.barriers),
b AS (SELECT * FROM d ORDER BY md5(blue_line_key::text || ':' || m::text) LIMIT 20000)
SELECT count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
          WHERE s.blue_line_key = b.blue_line_key
            AND round(b.m::numeric, 4) >= round(s.downstream_route_measure::numeric, 4)
            AND round(b.m::numeric, 4) <= round(s.upstream_route_measure::numeric, 4))) AS in_gap
  FROM b;

-- 3. The Crescent Slough dam's geometry: its distance to the shared vertex,
--    and the slough's first segment's length.
SELECT round(ST_Distance(ST_Transform(d.geom, 3005), s.geom)::numeric, 1) AS dam_to_segment_m,
       s.linear_feature_id, s.blue_line_key, s.edge_type, round(s.length_metre::numeric, 1) AS length_m
  FROM cabd.dams d
  JOIN whse_basemapping.fwa_stream_networks_sp s ON s.linear_feature_id IN (701651673, 701651674)
 WHERE d.cabd_id = '94dec15b-ef2f-4497-b68a-0c98705ef178'
 ORDER BY s.linear_feature_id;

-- 4. CABD dams in an exact distance tie between their two nearest segments
--    (within 65 m), and how many of those ties are on one blue line.
WITH c AS (SELECT cabd_id, ST_Transform(geom, 3005) AS geom FROM cabd.dams),
cand AS (
  SELECT c.cabd_id, s.blue_line_key, ST_Distance(s.geom, c.geom) AS d
    FROM c CROSS JOIN LATERAL (
      SELECT s.blue_line_key, s.geom FROM whse_basemapping.fwa_stream_networks_sp s
       WHERE s.localcode_ltree IS NOT NULL AND NOT s.wscode_ltree <@ '999'
         AND ST_DWithin(s.geom, c.geom, 65)
       ORDER BY s.geom <-> c.geom LIMIT 5) s),
tied AS (
  SELECT cabd_id, count(DISTINCT blue_line_key) AS n_blk
    FROM cand x WHERE d = (SELECT min(d) FROM cand y WHERE y.cabd_id = x.cabd_id)
   GROUP BY cabd_id HAVING count(*) > 1)
SELECT count(*) AS dams_tied, count(*) FILTER (WHERE n_blk = 1) AS tied_on_one_stream FROM tied;

-- 5. The 8 PSCIS picks dropped by the change: their candidates before
--    (zz478_before, main's snap) and after (zz478_after).
WITH dropped AS (
  SELECT b.stream_crossing_id FROM zz478_before.pscis_picked b
   WHERE NOT EXISTS (SELECT 1 FROM zz478_after.pscis_picked a WHERE a.stream_crossing_id = b.stream_crossing_id))
SELECT d.stream_crossing_id,
       (SELECT count(*) FROM zz478_before.pscis_stream_candidates c WHERE c.stream_crossing_id = d.stream_crossing_id) AS candidates_before,
       (SELECT count(*) FROM zz478_before.pscis_stream_candidates c WHERE c.stream_crossing_id = d.stream_crossing_id AND c.wscode_ltree <@ '999') AS on_999_before,
       (SELECT count(*) FROM zz478_after.pscis_stream_candidates c WHERE c.stream_crossing_id = d.stream_crossing_id) AS candidates_after
  FROM dropped d ORDER BY 1;
