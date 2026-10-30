-- Where link's `bcfishpass` build and the reference view disagree on access
-- code 2 (#403), in km, by mechanism. Pieces are measure overlaps per
-- blue_line_key (never an exact segment join), pieces under 1 cm dropped.
-- `at_start`: link's segment starts within 1 m of a record of the species on
-- the same line (bcfishobs, any group), which link's walk counts as upstream
-- of that segment (m >= start - 1).
--   psql -h <host> -d fwapg -v wsg=BULK -v sp=co -f parity_pieces.sql
WITH l AS (
  SELECT s.blue_line_key, s.downstream_route_measure AS m0,
         s.downstream_route_measure + s.length_metre AS m1,
         a.access_:sp AS code
    FROM fresh.streams s
    JOIN fresh.streams_access a
      ON a.id_segment = s.id_segment
     AND a.watershed_group_code = s.watershed_group_code
   WHERE s.watershed_group_code = :'wsg' AND a.access_:sp IN (1, 2)
), v AS (
  SELECT blue_line_key, downstream_route_measure AS m0,
         downstream_route_measure + length_metre AS m1, access_:sp AS code
    FROM fresh.streams_vw_bcfp
   WHERE watershed_group_code = :'wsg' AND access_:sp IN (1, 2)
), p AS (
  SELECT l.blue_line_key, l.m0 AS l_m0, l.code AS l_code, v.code AS v_code,
         least(l.m1, v.m1) - greatest(l.m0, v.m0) AS len
    FROM l JOIN v ON v.blue_line_key = l.blue_line_key
     AND v.m0 < l.m1 AND l.m0 < v.m1
), o AS (
  SELECT blue_line_key, downstream_route_measure AS m
    FROM bcfishobs.observations WHERE species_code = upper(:'sp')
)
SELECT :'wsg' AS wsg, upper(:'sp') AS species,
       CASE WHEN l_code = 2 THEN 'link_only' ELSE 'bcfp_only' END AS side,
       EXISTS (SELECT 1 FROM o WHERE o.blue_line_key = p.blue_line_key
                AND o.m BETWEEN p.l_m0 - 1 AND p.l_m0 + 1) AS at_start,
       round(sum(len)::numeric / 1000, 2) AS km, count(*) AS n_pieces
  FROM p
 WHERE l_code <> v_code AND len >= 0.01
 GROUP BY 1, 2, 3, 4 ORDER BY 3, 4;
