-- segments (link#372): FWA stream segments per group. Breaking, classifying,
-- persisting, access and mapping code all scale with the group's network.
SELECT watershed_group_code, count(*)::double precision AS value
  FROM whse_basemapping.fwa_stream_networks_sp
 GROUP BY watershed_group_code
