-- ties_anthropogenic.sql — link#409: can fresh 0.45's new tiebreak (each
-- array's ORDER BY now ends on the feature id) change dam_dnstr_ind? Only where
-- two features of barriers_anthropogenic_unified share wscode, localcode and
-- measure, one in barriers_dams_unified and one not. Read-only.
--   psql -h <dispatcher> -U postgres -d fwapg -At -F' | ' -f ties_anthropogenic.sql
SET statement_timeout = '600s';
WITH a AS (
  SELECT u.barriers_anthropogenic_unified_id AS id, u.wscode_ltree, u.localcode_ltree,
         u.downstream_route_measure AS m,
         (d.barriers_dams_unified_id IS NOT NULL) AS is_dam
  FROM fresh_default.barriers_anthropogenic_unified u
  LEFT JOIN fresh_default.barriers_dams_unified d
    ON d.barriers_dams_unified_id = u.barriers_anthropogenic_unified_id
), g AS (
  SELECT wscode_ltree, localcode_ltree, m, count(*) n,
         count(*) FILTER (WHERE is_dam) n_dam, count(DISTINCT id) n_id
  FROM a GROUP BY 1,2,3 HAVING count(*) > 1)
SELECT 'anthro rows', (SELECT count(*) FROM a)
UNION ALL SELECT 'tie positions', count(*) FROM g
UNION ALL SELECT 'tie positions with >1 distinct id', count(*) FROM g WHERE n_id > 1
UNION ALL SELECT 'mixed dam / non-dam ties', count(*) FROM g WHERE n_dam > 0 AND n_dam < n;
