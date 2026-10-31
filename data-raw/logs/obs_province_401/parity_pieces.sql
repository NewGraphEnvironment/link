-- Where link's `bcfishpass` build and the reference view disagree on access
-- code 2, in km, by mechanism (#401; #399's copy is the reading before it).
-- Pieces are measure overlaps per blue_line_key (never an exact segment join),
-- pieces under 1 cm dropped. link's walk counts a same-line record as upstream
-- of a segment only at m >= start + 1 (#399), as bcfishpass's does.
--   at_start: link's segment has a same-line record of the species, from the
--     group's own records (zz401_obs.bcfishpass_<wsg>), in [start - 1, start + 1).
--   upstream_group: a record of the species from another group
--     (zz401_obs.province_bcfishpass) lies upstream of link's segment. Before
--     #401 link's walk read only the group's own records; bcfishpass's reads
--     every group's, and since #401 link's does too.
--   gate: a record of any species from the group's own records lies upstream
--     of link's segment (bcfishpass's `observation_key_upstr`, which link
--     reproduces under `observation_upstream: group_gated` since #401).
-- Placeholders :schema, :wsg and :sp are substituted by rollup.R.
WITH l AS (
  SELECT s.blue_line_key, s.downstream_route_measure AS m0,
         s.downstream_route_measure + s.length_metre AS m1,
         s.wscode_ltree, s.localcode_ltree, a.access_:sp AS code
    FROM :schema.streams s
    JOIN :schema.streams_access a
      ON a.id_segment = s.id_segment
     AND a.watershed_group_code = s.watershed_group_code
   WHERE s.watershed_group_code = ':wsg' AND a.access_:sp IN (1, 2)
), v AS (
  SELECT blue_line_key, downstream_route_measure AS m0,
         downstream_route_measure + length_metre AS m1, access_:sp AS code
    FROM fresh.streams_vw_bcfp
   WHERE watershed_group_code = ':wsg' AND access_:sp IN (1, 2)
), p AS (
  SELECT l.blue_line_key, l.m0 AS l_m0, l.wscode_ltree, l.localcode_ltree,
         l.code AS l_code, v.code AS v_code,
         least(l.m1, v.m1) - greatest(l.m0, v.m0) AS len
    FROM l JOIN v ON v.blue_line_key = l.blue_line_key
     AND v.m0 < l.m1 AND l.m0 < v.m1
   WHERE l.code <> v.code
     AND least(l.m1, v.m1) - greatest(l.m0, v.m0) >= 0.01
)
SELECT ':wsg' AS wsg, upper(':sp') AS species,
       CASE WHEN l_code = 2 THEN 'link_only' ELSE 'bcfp_only' END AS side,
       EXISTS (SELECT 1 FROM zz401_obs.bcfishpass_:wsg o
                WHERE upper(o.species_code) = upper(':sp')
                  AND o.blue_line_key = p.blue_line_key
                  AND o.downstream_route_measure >= p.l_m0 - 1
                  AND o.downstream_route_measure < p.l_m0 + 1) AS at_start,
       EXISTS (SELECT 1 FROM zz401_obs.province_bcfishpass o
                WHERE upper(o.species_code) = upper(':sp')
                  AND o.watershed_group_code <> ':wsg'
                  AND whse_basemapping.fwa_upstream(
                        p.blue_line_key, p.l_m0, p.wscode_ltree, p.localcode_ltree,
                        o.blue_line_key, o.downstream_route_measure,
                        o.wscode, o.localcode, false, 1)) AS upstream_group,
       EXISTS (SELECT 1 FROM zz401_obs.bcfishpass_:wsg o
                WHERE whse_basemapping.fwa_upstream(
                        p.blue_line_key, p.l_m0, p.wscode_ltree, p.localcode_ltree,
                        o.blue_line_key, o.downstream_route_measure,
                        o.wscode, o.localcode, false, 1)) AS gate,
       round(sum(len)::numeric / 1000, 3) AS km, count(*) AS n_pieces
  FROM p
 GROUP BY 1, 2, 3, 4, 5, 6 ORDER BY 3, 4, 5, 6;
