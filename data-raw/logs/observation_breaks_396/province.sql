-- Province-wide observation positions against the top per species per line,
-- on `default`'s observation set (zz396_cuts.obs_province, build_obs.R: each
-- record filtered by its own group's presence, exclusions applied).
--
--   psql -X -A -F, -f data-raw/logs/observation_breaks_396/province.sql
WITH obs AS (
  SELECT blue_line_key AS blk, species_code AS sp,
         round(downstream_route_measure) AS m
  FROM zz396_cuts.obs_province
),
pos AS (SELECT DISTINCT blk, m FROM obs),
tops AS (SELECT DISTINCT blk, m FROM (
  SELECT blk, max(m) AS m FROM obs GROUP BY blk, sp) t)
SELECT 'province' AS wsg,
       (SELECT count(*) FROM obs) AS observations,
       (SELECT count(*) FROM pos) AS positions,
       (SELECT count(*) FROM tops) AS tops,
       round(100.0 * (SELECT count(*) FROM tops) / (SELECT count(*) FROM pos), 1) AS pct_kept;
