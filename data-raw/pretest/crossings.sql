-- crossings (link#372): PSCIS assessments inside each group. The PSCIS pick
-- (#277) snaps each one and chooses among the modelled crossings near it.
SELECT g.watershed_group_code, count(p.*)::double precision AS value
  FROM whse_basemapping.fwa_watershed_groups_poly g
  JOIN whse_fish.pscis_assessment_svw p ON ST_Intersects(g.geom, p.geom)
 GROUP BY g.watershed_group_code
