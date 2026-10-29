-- ties_natural.sql — link#409: why element order changed between fresh v0.44.0
-- and v0.46.0 in per-species natural walks. Counts positions (wscode, localcode,
-- measure: fresh's ORDER BY keys before 0.45.0) holding two or more features in
-- one natural view, and how many of those span watershed groups (a barrier on a
-- line several groups share is persisted under each). Read-only.
--   psql -h <host> -U postgres -d fwapg -At -F' | ' -f ties_natural.sql
SET statement_timeout = '300s';
SELECT count(*) AS rows,
       (SELECT count(*) FROM (SELECT 1 FROM fresh_default.barriers_ch_access
          GROUP BY wscode_ltree, localcode_ltree, downstream_route_measure
          HAVING count(*) > 1) t) AS tie_positions,
       (SELECT count(*) FROM (SELECT 1 FROM fresh_default.barriers_ch_access
          GROUP BY wscode_ltree, localcode_ltree, downstream_route_measure
          HAVING count(DISTINCT watershed_group_code) > 1) t) AS cross_group_tie_positions
FROM fresh_default.barriers_ch_access;
