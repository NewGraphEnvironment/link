-- order1_waterbody_filter.sql — #326: sizes bcfishpass's CH / CO / ST / WCT
-- waterbody and edge-type filter on the order-1 rearing exception, which
-- fresh 0.43.0's frs_order_child() does not test (its docs list the three
-- forms). Counts `bcfishpass`-config rearing km in LFRA and KOTR on segments
-- only the exception admits (order 1, parent order >= 5, direct child, known
-- width < 1.5 m, gradient within the species' rearing maximum, accessible),
-- and the km each form would turn away. Waterbody type from fwa_waterbodies
-- (R = river polygon, NULL = none). Thresholds: configs/bcfishpass.
-- Run: psql -h localhost -U postgres -d fwapg -f order1_waterbody_filter.sql
WITH base AS (
  SELECT s.watershed_group_code wsg, s.blue_line_key, s.length_metre, s.edge_type, s.channel_width, s.gradient,
         s.stream_order, s.stream_order_parent, w.waterbody_type wbt,
         s.stream_order = max(s.stream_order) OVER (PARTITION BY s.watershed_group_code, s.blue_line_key) AS direct_child,
         s.id_segment
  FROM fresh.streams s
  LEFT JOIN whse_basemapping.fwa_waterbodies w ON w.waterbody_key = s.waterbody_key
  WHERE s.watershed_group_code IN ('LFRA','KOTR')
), sp(code, gmax) AS (VALUES ('ch',0.0549),('co',0.0549),('st',0.0849),('wct',0.0849)),
h AS (
  SELECT 'ch' sp, * FROM fresh.streams_habitat_ch WHERE watershed_group_code IN ('LFRA','KOTR')
  UNION ALL SELECT 'co', * FROM fresh.streams_habitat_co WHERE watershed_group_code IN ('LFRA','KOTR')
  UNION ALL SELECT 'st', * FROM fresh.streams_habitat_st WHERE watershed_group_code IN ('LFRA','KOTR')
  UNION ALL SELECT 'wct', * FROM fresh.streams_habitat_wct WHERE watershed_group_code IN ('LFRA','KOTR')
)
SELECT b.wsg, h.sp,
  round((sum(b.length_metre) FILTER (WHERE h.rearing)/1000)::numeric,2) AS exc_rear_km,
  round((sum(b.length_metre) FILTER (WHERE h.rearing AND NOT (wbt='R' OR (wbt IS NULL AND edge_type IN (1000,1100,2000,2300))))/1000)::numeric,2) AS fail_ch_form_km,
  round((sum(b.length_metre) FILTER (WHERE h.rearing AND NOT (wbt='R' OR wbt IS NULL OR edge_type IN (1000,1100,2000,2300)))/1000)::numeric,2) AS fail_st_form_km,
  round((sum(b.length_metre) FILTER (WHERE h.rearing AND NOT (wbt='R' OR wbt IS NULL OR edge_type IN (1000,1100,2000,2300,1050,1150)))/1000)::numeric,2) AS fail_co_form_km,
  round((sum(b.length_metre) FILTER (WHERE h.rearing AND wbt IS NULL AND edge_type NOT IN (1000,1100,2000,2300))/1000)::numeric,2) AS nowb_offedge_km,
  string_agg(DISTINCT coalesce(wbt,'-') || ':' || edge_type, ' ') FILTER (WHERE h.rearing) AS mix
FROM base b JOIN h USING (id_segment) JOIN sp ON sp.code = h.sp
WHERE h.watershed_group_code = b.wsg AND b.stream_order = 1 AND b.stream_order_parent >= 5 AND b.direct_child
  AND b.channel_width IS NOT NULL AND b.channel_width < 1.5 AND b.gradient <= sp.gmax AND h.accessible
GROUP BY 1,2 ORDER BY 1,2;
