-- coheld.sql: groups whose only link to another is a barrier row that group
-- holds on the reader's own segments (link#274, acceptance 3).
-- Rows held by a group that owns no segment where they sit, by holder and the
-- group that owns that segment, with whether each row lies downstream of one
-- of the owner's own segments (so the owner's recompute walk reads it).
-- Run: psql -h localhost -U postgres -d fwapg -f coheld.sql (from the repo root)
\set ON_ERROR_STOP 1
SET statement_timeout = '10min';
\copy (SELECT b.watershed_group_code AS holder, s.watershed_group_code AS owner, b.id_barrier, b.barrier_source, b.blue_line_key, round(b.downstream_route_measure::numeric, 1) AS dm, EXISTS (SELECT 1 FROM fresh_default.streams u WHERE u.watershed_group_code = s.watershed_group_code AND u.localcode_ltree IS NOT NULL AND u.wscode_ltree <@ b.wscode_ltree AND whse_basemapping.fwa_downstream(u.wscode_ltree, u.localcode_ltree, b.wscode_ltree, b.localcode_ltree)) AS owner_reads FROM fresh_default.barriers b JOIN fresh_default.streams s ON s.blue_line_key = b.blue_line_key AND b.downstream_route_measure >= s.downstream_route_measure AND b.downstream_route_measure < s.upstream_route_measure WHERE s.watershed_group_code <> b.watershed_group_code AND b.localcode_ltree IS NOT NULL AND NOT EXISTS (SELECT 1 FROM fresh_default.streams s2 WHERE s2.watershed_group_code = b.watershed_group_code AND s2.blue_line_key = b.blue_line_key AND b.downstream_route_measure >= s2.downstream_route_measure - 0.001 AND b.downstream_route_measure <= s2.upstream_route_measure + 0.001) ORDER BY 1, 2, 5, 6) TO 'data-raw/logs/partial_readers_274/coheld.csv' WITH (FORMAT csv, HEADER)
