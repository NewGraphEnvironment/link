-- report.sql — run after measure.sql in the same psql session (measure.sh).
-- Needs psql variables: schema, out (output directory), ctrl, definite, falls
-- (CSV paths).

-- Summary, one row per measure.
COPY (SELECT * FROM (VALUES ('lines touching more than one group', (SELECT count(*) FROM m386_lines)::text), ('gradient rows on those lines', (SELECT count(*) FROM m386_g)::text), ('gradient positions on those lines', (SELECT count(*) FROM m386_pos)::text), ('positions held by more than one group', (SELECT count(*) FROM m386_pos WHERE cardinality(holders) > 1)::text), ('most holders of one position', (SELECT max(cardinality(holders)) FROM m386_pos)::text), ('rows held by a group that does not own the position', (SELECT count(*) FROM m386_g g JOIN m386_pos p USING (blue_line_key, drm) WHERE g.holder <> p.owner)::text), ('positions whose copies differ in subtype', (SELECT count(*) FROM m386_pos WHERE n_subtype > 1)::text), ('positions whose copies differ in blocks_species', (SELECT count(*) FROM m386_pos WHERE n_blocks > 1)::text), ('(position, built scanner) pairs with no row within 1 m', (SELECT count(*) FROM m386_missing)::text), ('positions with such a missing scanner', (SELECT count(DISTINCT (blue_line_key, drm)) FROM m386_missing)::text), ('positions whose owner holds no row', (SELECT count(*) FROM m386_pos WHERE NOT owner = ANY (holders))::text), ('  of which the owner is built in the schema', (SELECT count(*) FROM m386_pos WHERE NOT owner = ANY (holders) AND owner_built)::text), ('  of which the owner does not scan the line', (SELECT count(*) FROM m386_pos WHERE NOT owner = ANY (holders) AND NOT owner = ANY (scanners))::text), ('positions on no persisted segment', (SELECT count(*) FROM m386_pos WHERE NOT on_persisted)::text), ('rows at positions on no persisted segment', (SELECT count(*) FROM m386_g g JOIN m386_pos p USING (blue_line_key, drm) WHERE NOT p.on_persisted)::text), ('override positions on multi-group lines', (SELECT count(*) FROM m386_ovr_pos)::text), ('  held by more than one group', (SELECT count(*) FROM m386_ovr_pos WHERE n_holders > 1)::text), ('  whose species sets differ between holders', (SELECT count(*) FROM m386_ovr_pos WHERE n_species_sets > 1)::text), ('  whose owner holds none', (SELECT count(*) FROM m386_ovr_pos WHERE NOT owner = ANY (holders))::text)) v(measure, value)) TO STDOUT CSV HEADER \g :out_summary

COPY (SELECT blue_line_key, drm, owner, owner_built, array_to_string(holders, ';') holders, array_to_string(scanners, ';') scanners, on_persisted FROM m386_pos WHERE NOT owner = ANY (holders) OR NOT on_persisted ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_ownerless
COPY (SELECT blue_line_key, drm, owner, string_agg(scanner, ';' ORDER BY scanner) scanners_missing FROM m386_missing GROUP BY 1, 2, 3 ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_missing
COPY (SELECT blue_line_key, drm, owner, array_to_string(holders, ';') holders, array_to_string(species, ' | ') species FROM m386_ovr_pos WHERE n_species_sets > 1 OR NOT owner = ANY (holders) ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_ovr

-- Controls, user-definite and falls: the group each row is filed under against
-- the owner of its position.
DROP TABLE IF EXISTS m386_ctrl;
CREATE TEMP TABLE m386_ctrl (blue_line_key integer, downstream_route_measure double precision, barrier_type text, barrier_ind text, watershed_group_code text, reviewer_name text, review_date text, source text, notes text);
\set load_cmd '\\copy m386_ctrl FROM ' :'ctrl' ' CSV HEADER'
:load_cmd
DROP TABLE IF EXISTS m386_def;
CREATE TEMP TABLE m386_def (barrier_type text, barrier_name text, blue_line_key integer, downstream_route_measure double precision, watershed_group_code text, reviewer_name text, review_date text, source text, notes text);
\set load_cmd '\\copy m386_def FROM ' :'definite' ' CSV HEADER'
:load_cmd
DROP TABLE IF EXISTS m386_falls;
CREATE TEMP TABLE m386_falls (blue_line_key integer, downstream_route_measure double precision, watershed_group_code text, falls_name text, height_m text, barrier_ind text);
\set load_cmd '\\copy m386_falls FROM ' :'falls' ' CSV HEADER'
:load_cmd

COPY (SELECT 'control' AS file, count(*) AS n, count(*) FILTER (WHERE pg_temp.m386_owner(blue_line_key, downstream_route_measure) IS DISTINCT FROM watershed_group_code) AS n_filed_under_non_owner FROM m386_ctrl UNION ALL SELECT 'user_definite', count(*), count(*) FILTER (WHERE pg_temp.m386_owner(blue_line_key, downstream_route_measure) IS DISTINCT FROM watershed_group_code) FROM m386_def UNION ALL SELECT 'falls (barrier_ind true)', count(*), count(*) FILTER (WHERE pg_temp.m386_owner(blue_line_key, downstream_route_measure) IS DISTINCT FROM watershed_group_code) FROM m386_falls WHERE barrier_ind::boolean) TO STDOUT CSV HEADER \g :out_files

-- Each control row filed under a non-owner, and what it does today: the
-- groups holding a gradient row within 1 m (a FALSE row prunes only in the
-- group it is filed under), the groups holding a FALLS or SUBSURFACE row there,
-- and the override rows within 1 m (a TRUE row locks lifts only in the group it
-- is filed under).
COPY (SELECT c.blue_line_key, c.downstream_route_measure, c.barrier_type, c.barrier_ind, c.watershed_group_code AS filed_under, pg_temp.m386_owner(c.blue_line_key, c.downstream_route_measure) AS owner, (SELECT string_agg(DISTINCT b.watershed_group_code || ':' || b.barrier_source, ';') FROM :"schema".barriers b WHERE b.blue_line_key = c.blue_line_key AND abs(b.downstream_route_measure - c.downstream_route_measure) < 1 AND b.barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW')) AS natural_rows_within_1m, (SELECT string_agg(DISTINCT o.watershed_group_code || ':' || o.species_code, ';') FROM :"schema".barrier_overrides o WHERE o.blue_line_key = c.blue_line_key AND abs(o.downstream_route_measure - c.downstream_route_measure) < 1) AS overrides_within_1m, c.notes FROM m386_ctrl c WHERE pg_temp.m386_owner(c.blue_line_key, c.downstream_route_measure) IS DISTINCT FROM c.watershed_group_code ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_ctrl
COPY (SELECT d.blue_line_key, d.downstream_route_measure, d.barrier_type, d.watershed_group_code AS filed_under, pg_temp.m386_owner(d.blue_line_key, d.downstream_route_measure) AS owner, d.barrier_name FROM m386_def d WHERE pg_temp.m386_owner(d.blue_line_key, d.downstream_route_measure) IS DISTINCT FROM d.watershed_group_code ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_def
COPY (SELECT f.blue_line_key, f.downstream_route_measure, f.watershed_group_code AS filed_under, pg_temp.m386_owner(f.blue_line_key, f.downstream_route_measure) AS owner, f.falls_name FROM m386_falls f WHERE f.barrier_ind::boolean AND pg_temp.m386_owner(f.blue_line_key, f.downstream_route_measure) IS DISTINCT FROM f.watershed_group_code ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_falls

-- Every control row on a line several groups scan, filed under its owner or
-- not, with the natural rows and override rows within 1 m: a FALSE row filed
-- under one group leaves the other scanners' copies standing.
COPY (SELECT c.blue_line_key, c.downstream_route_measure, c.barrier_type, c.barrier_ind, c.watershed_group_code AS filed_under, pg_temp.m386_owner(c.blue_line_key, c.downstream_route_measure) AS owner, array_to_string(l.scanners, ';') AS scanners, (SELECT string_agg(DISTINCT b.watershed_group_code || ':' || b.barrier_source, ';') FROM :"schema".barriers b WHERE b.blue_line_key = c.blue_line_key AND abs(b.downstream_route_measure - c.downstream_route_measure) < 1 AND b.barrier_source IN ('GRADIENT', 'FALLS', 'SUBSURFACE_FLOW')) AS natural_rows_within_1m, (SELECT string_agg(DISTINCT o.watershed_group_code || ':' || o.species_code, ';') FROM :"schema".barrier_overrides o WHERE o.blue_line_key = c.blue_line_key AND abs(o.downstream_route_measure - c.downstream_route_measure) < 1) AS overrides_within_1m, c.notes FROM m386_ctrl c JOIN m386_lines l USING (blue_line_key) ORDER BY 1, 2) TO STDOUT CSV HEADER \g :out_ctrl_multi
