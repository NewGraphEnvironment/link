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
