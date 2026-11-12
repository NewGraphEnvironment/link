-- #465 / review acceptance 4: is the line rule a superset of the groups whose
-- rows a walk reads? It is, if every persisted barrier and override row sits on
-- a blue line its own group touches in FWA (the line rule lists every group
-- touching a line of the reader's codes, by blue line). Expect 0 in each count.
-- Run: psql -v schema=fresh_default -f superset.sql
\set ON_ERROR_STOP 1
\timing on
SELECT 'barriers' AS tbl, b.barrier_source, count(*) AS rows_off_own_lines
FROM :schema.barriers b
WHERE NOT EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = b.blue_line_key
    AND s.watershed_group_code = b.watershed_group_code)
GROUP BY 1, 2 ORDER BY 1, 2;
SELECT 'barrier_overrides' AS tbl, count(*) AS rows_off_own_lines
FROM :schema.barrier_overrides o
WHERE NOT EXISTS (
  SELECT 1 FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE s.blue_line_key = o.blue_line_key
    AND s.watershed_group_code = o.watershed_group_code);
SELECT 'totals' AS tbl, (SELECT count(*) FROM :schema.barriers) AS barriers,
       (SELECT count(*) FROM :schema.barrier_overrides) AS barrier_overrides;
