-- obs_upstream (link#401): raw fish observation records upstream of each
-- group's outlet, every group's, the group's own included. Since #401 the
-- access walk reads every group's records (<schema>.observations_province,
-- each kept only where its group's presence lists the species; this raw
-- count is a ranking proxy for it, LFRA first either way) and
-- fresh's frs_network_features() applies aoi to segments only, so a main stem
-- below many groups' records costs more than its own records or segment count
-- say (LFRA's Fraser main stem: 126,143 raw above its outlet, about 79,000
-- kept). The outlet is
-- #238's rule: the group's highest stream order, then its shallowest code,
-- then its lowest measure; FWA's 999 codes are left out. The walk's own test,
-- fwa_upstream(..., false, 1). bcfishobs.observations has no wscode index, so
-- this reads the table once per group (about 40 s province-wide on m1).
WITH o AS (
  SELECT DISTINCT ON (watershed_group_code) watershed_group_code, blue_line_key,
         downstream_route_measure, wscode_ltree, localcode_ltree
    FROM (SELECT s.*, max(stream_order) OVER (PARTITION BY watershed_group_code) AS omax
            FROM whse_basemapping.fwa_stream_networks_sp s
           WHERE wscode_ltree IS NOT NULL AND localcode_ltree IS NOT NULL
             AND NOT wscode_ltree <@ '999'::ltree) x
   WHERE stream_order = omax
   ORDER BY watershed_group_code, nlevel(wscode_ltree), downstream_route_measure,
            linear_feature_id
)
SELECT o.watershed_group_code, count(b.*)::double precision AS value
  FROM o
  LEFT JOIN bcfishobs.observations b
    ON b.wscode <@ o.wscode_ltree
   AND whse_basemapping.fwa_upstream(
         o.blue_line_key, o.downstream_route_measure, o.wscode_ltree, o.localcode_ltree,
         b.blue_line_key, b.downstream_route_measure, b.wscode, b.localcode, false, 1)
 GROUP BY o.watershed_group_code
