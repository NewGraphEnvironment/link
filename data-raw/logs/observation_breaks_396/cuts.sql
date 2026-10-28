-- Observation break positions today against the top per species per line (#396).
--
--   psql -X -A -F, -v wsg=PARS -v obs=obs_pars -v wk=working_pars \
--     -f data-raw/logs/observation_breaks_396/cuts.sql
--
-- Reads `default`'s observation set (zz396_cuts.obs_<wsg>, build_obs.R).
-- frs_break_apply() cuts a segment only where a break sits more than 1 m from
-- both of its current ends, one source after another, and observations are
-- the first source. So an observation position always cuts unless it is within
-- 1 m of an FWA segment end; a later source within 1 m of it is the one that
-- does not. A position "adds a segment" here when it is more than 1 m from
-- every FWA segment end on its line and every other break source's position
-- (gradient_minimal, falls, barriers_definite, habitat_endpoints, crossings):
-- without it, nothing else would cut there. Those sources come from :wk, the
-- working schema of the last build of the group on this host (the bcfishpass
-- config on m4), so the counts are an estimate; Phase 4 counts the segments
-- exactly. Observation positions are all tested in one frs_break_apply() call
-- against the segments' original ends, so two of them 1 m apart both cut:
-- dropping one saves a segment. A later source within 1 m of a removed
-- position cuts in its place, so that one saves nothing.
WITH obs AS (
  SELECT blue_line_key AS blk, species_code AS sp,
         round(downstream_route_measure) AS m
  FROM zz396_cuts.:"obs"
),
pos AS (SELECT DISTINCT blk, m FROM obs),
tops AS (
  SELECT DISTINCT blk, m FROM (
    SELECT blk, max(m) AS m FROM obs GROUP BY blk, sp) t
),
fwa AS (
  SELECT blue_line_key AS blk, downstream_route_measure AS m
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = :'wsg'
  UNION ALL
  SELECT blue_line_key, upstream_route_measure
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = :'wsg'
),
oth AS (
  SELECT blue_line_key AS blk, round(downstream_route_measure) AS m FROM :"wk".gradient_barriers_minimal
  UNION SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".falls
  UNION SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".barriers_definite
  UNION SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".habitat_endpoints
  UNION SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".crossings_breaks
),
other AS (SELECT blk, m FROM fwa UNION ALL SELECT blk, m FROM oth),
flag AS (
  SELECT p.blk, p.m,
         (t.blk IS NOT NULL) AS kept,
         EXISTS (SELECT 1 FROM other o
                 WHERE o.blk = p.blk AND abs(o.m - p.m) <= 1) AS near_other
  FROM pos p LEFT JOIN tops t ON t.blk = p.blk AND t.m = p.m
)
SELECT :'wsg' AS wsg,
       (SELECT count(*) FROM obs)                                    AS observations,
       count(*)                                                      AS positions,
       count(*) FILTER (WHERE kept)                                  AS tops,
       round(100.0 * count(*) FILTER (WHERE kept) / count(*), 1)     AS pct_kept,
       count(*) FILTER (WHERE NOT near_other)                        AS positions_adding_a_segment,
       count(*) FILTER (WHERE kept AND NOT near_other)               AS tops_adding_a_segment,
       count(*) FILTER (WHERE kept AND near_other)                   AS tops_within_1m_of_other_cut,
       count(*) FILTER (WHERE NOT kept)                              AS removed,
       count(*) FILTER (WHERE NOT kept AND NOT near_other)            AS removed_saving_a_segment
FROM flag;
