-- gradient (link#372): FWA segments at or above 15 % gradient per group, the
-- lowest access threshold any species carries (CH, CO, SK). The gradient
-- barriers, their per-species reduction to the downstream-most position per
-- flow path (#326) and the barrier rows unify stages all grow with them.
SELECT watershed_group_code, count(*)::double precision AS value
  FROM whse_basemapping.fwa_stream_networks_sp
 WHERE gradient >= 0.15
 GROUP BY watershed_group_code
