-- measure.sql — copies of one barrier held by several groups (link#386).
--
-- Reads one persist schema (psql variable `schema`, default fresh_default) and
-- local FWA. Writes temp tables only; the caller (measure.R) reads them.
--
-- The OWNER of a position is the group of the FWA segment it sits on, picked
-- as the pipeline picks: the segment whose [downstream, upstream) measure
-- range holds it, lowest downstream measure then lowest linear_feature_id
-- (the ~1 mm overlap of two segments); for a measure in the gap between two
-- segments, the line's segment nearest the measure (.lnk_sql_locate()'s
-- order). A group SCANS a line when it holds a segment of it with edge type
-- other than 6010 (.lnk_pipeline_prep_gradient()'s streams_blk).

\if :{?schema}
\else
\set schema fresh_default
\endif

-- Lines touching more than one group. A gradient row on any other line is
-- held by the only group that scans it, which owns it.
DROP TABLE IF EXISTS m386_lines;
CREATE TEMP TABLE m386_lines AS
SELECT blue_line_key,
       array_agg(DISTINCT watershed_group_code::text ORDER BY watershed_group_code::text)
         FILTER (WHERE edge_type != 6010) AS scanners
FROM whse_basemapping.fwa_stream_networks_sp
GROUP BY blue_line_key
HAVING count(DISTINCT watershed_group_code) > 1;
CREATE INDEX ON m386_lines (blue_line_key);
ANALYZE m386_lines;

-- Groups built in the schema (a finished log row).
DROP TABLE IF EXISTS m386_built;
CREATE TEMP TABLE m386_built AS
SELECT DISTINCT watershed_group_code::text AS wsg
FROM :"schema".log WHERE date_end IS NOT NULL;

-- Gradient rows on those lines, one per holder.
DROP TABLE IF EXISTS m386_g;
CREATE TEMP TABLE m386_g AS
SELECT b.watershed_group_code::text AS holder, b.blue_line_key,
       b.downstream_route_measure AS drm, b.barrier_subtype AS subtype,
       array_to_string(b.blocks_species, ',') AS blocks
FROM :"schema".barriers b
JOIN m386_lines l USING (blue_line_key)
WHERE b.barrier_source = 'GRADIENT';
CREATE INDEX ON m386_g (blue_line_key, drm);
ANALYZE m386_g;

-- An owner for any (blue_line_key, measure).
CREATE OR REPLACE FUNCTION pg_temp.m386_owner(blk integer, m double precision)
RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT COALESCE(
    (SELECT s.watershed_group_code::text
       FROM whse_basemapping.fwa_stream_networks_sp s
      WHERE s.blue_line_key = blk
        AND m >= s.downstream_route_measure AND m < s.upstream_route_measure
      ORDER BY s.downstream_route_measure, s.linear_feature_id LIMIT 1),
    (SELECT n.watershed_group_code::text
       FROM whse_basemapping.fwa_stream_networks_sp n
      WHERE n.blue_line_key = blk
      ORDER BY least(abs(m - n.downstream_route_measure),
                     abs(m - n.upstream_route_measure)),
               n.linear_feature_id
      LIMIT 1))
$f$;

-- Distinct positions with their owner and holders.
DROP TABLE IF EXISTS m386_pos;
CREATE TEMP TABLE m386_pos AS
SELECT blue_line_key, drm,
       pg_temp.m386_owner(blue_line_key, drm) AS owner,
       array_agg(DISTINCT holder ORDER BY holder) AS holders,
       count(DISTINCT subtype) AS n_subtype,
       count(DISTINCT blocks) AS n_blocks
FROM m386_g GROUP BY blue_line_key, drm;
ALTER TABLE m386_pos ADD COLUMN scanners text[];
UPDATE m386_pos p SET scanners = l.scanners FROM m386_lines l
 WHERE l.blue_line_key = p.blue_line_key;
ALTER TABLE m386_pos ADD COLUMN owner_built boolean;
UPDATE m386_pos SET owner_built = owner IN (SELECT wsg FROM m386_built);
-- On no persisted segment: no streams row of the schema covers it.
ALTER TABLE m386_pos ADD COLUMN on_persisted boolean;
UPDATE m386_pos p SET on_persisted = EXISTS (
  SELECT 1 FROM :"schema".streams s
   WHERE s.blue_line_key = p.blue_line_key
     AND p.drm >= s.downstream_route_measure
     AND p.drm <= s.upstream_route_measure);
CREATE INDEX ON m386_pos (blue_line_key, drm);
ANALYZE m386_pos;

-- Existence disagreement: a built scanner of the line holding no gradient
-- row within 1 m of a position another group holds.
DROP TABLE IF EXISTS m386_missing;
CREATE TEMP TABLE m386_missing AS
SELECT p.blue_line_key, p.drm, p.owner, sc AS scanner
FROM m386_pos p, unnest(p.scanners) sc
WHERE sc IN (SELECT wsg FROM m386_built)
  AND NOT EXISTS (
    SELECT 1 FROM m386_g g
     WHERE g.holder = sc AND g.blue_line_key = p.blue_line_key
       AND abs(g.drm - p.drm) < 1);

-- Override copies: per position, the species set each holder lifts.
DROP TABLE IF EXISTS m386_ovr;
CREATE TEMP TABLE m386_ovr AS
SELECT o.blue_line_key, o.downstream_route_measure AS drm,
       o.watershed_group_code::text AS holder,
       string_agg(o.species_code, ',' ORDER BY o.species_code) AS species
FROM :"schema".barrier_overrides o
JOIN m386_lines l USING (blue_line_key)
GROUP BY 1, 2, 3;
DROP TABLE IF EXISTS m386_ovr_pos;
CREATE TEMP TABLE m386_ovr_pos AS
SELECT blue_line_key, drm, pg_temp.m386_owner(blue_line_key, drm) AS owner,
       count(*) AS n_holders, count(DISTINCT species) AS n_species_sets,
       array_agg(holder ORDER BY holder) AS holders,
       array_agg(species ORDER BY holder) AS species
FROM m386_ovr GROUP BY 1, 2;
