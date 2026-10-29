-- dams (link#372): CABD dams inside each group. The dam barriers, the
-- placeholders (#244) and the downstream guard (#227) work over them.
SELECT g.watershed_group_code, count(d.*)::double precision AS value
  FROM whse_basemapping.fwa_watershed_groups_poly g
  JOIN cabd.dams d ON ST_Intersects(g.geom, ST_Transform(d.geom, 3005))
 GROUP BY g.watershed_group_code
