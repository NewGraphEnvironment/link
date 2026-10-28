-- observations (link#372): fish observation records per group. They are the
-- first break source (#396) and what barrier lifts count (#349).
SELECT watershed_group_code, count(*)::double precision AS value
  FROM bcfishobs.observations
 WHERE watershed_group_code IS NOT NULL
 GROUP BY watershed_group_code
