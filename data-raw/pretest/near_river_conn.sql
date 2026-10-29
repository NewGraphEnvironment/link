-- near_river_conn (link#372): fresh's frs_near_river() sizes its walk's
-- prefilter and cap as distance_max + conn_max, where conn_max is the longest
-- connector run (FWA edge types 1400, 1450) per waterbody on main flow plus
-- the longest on a side line (fresh R/frs_near_river.R, v0.44.0). The same
-- query per group; connector length per waterbody does not depend on where
-- the network is broken, so FWA's own lines give the walk's value.
SELECT watershed_group_code,
       (coalesce(max(l) FILTER (WHERE main), 0)
        + coalesce(max(l) FILTER (WHERE NOT main), 0))::double precision AS value
  FROM (SELECT watershed_group_code, blue_line_key = watershed_key AS main,
               sum(length_metre) AS l
          FROM whse_basemapping.fwa_stream_networks_sp
         WHERE edge_type IN (1400, 1450) AND waterbody_key IS NOT NULL
         GROUP BY watershed_group_code, waterbody_key, blue_line_key, watershed_key) x
 GROUP BY watershed_group_code
