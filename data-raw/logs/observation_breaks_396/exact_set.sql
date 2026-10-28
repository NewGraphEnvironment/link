-- The break set that keeps access code 2 exactly as `all` gives it (#396,
-- code-check round 2). The walk reads a same-line observation as upstream of a
-- segment when it lies above the segment's start or within 1 m of it, so a
-- species' own top break never changes its own code: the segment starting at
-- the top still reads 2. Species X turns from 2 to 1 at the first cut more than
-- 1 m above its top T_X. Under `all` that is the lowest of the line's other
-- cuts and its observation positions above T_X + 1; so keeping, per species,
-- the lowest observation position (of any species) above T_X + 1 keeps every
-- flip where `all` puts it. Counted here against `all` and `top_per_species`.
--
--   psql -X -A -F, -v wsg=PARS -v obs=obs_pars \
--     -f data-raw/logs/observation_breaks_396/exact_set.sql
-- Breaks are rounded to the metre and the walk compares the raw record measure
-- with the rounded segment start, so the flip test uses the raw top (raw_t).
WITH obs AS (
  SELECT blue_line_key AS blk, species_code AS sp,
         downstream_route_measure AS raw_m,
         round(downstream_route_measure) AS m
  FROM zz396_cuts.:"obs"
),
pos AS (SELECT DISTINCT blk, m FROM obs),
tops_sp AS (SELECT blk, sp, max(raw_m) AS raw_t FROM obs GROUP BY blk, sp),
tops AS (SELECT DISTINCT blk, round(raw_t) AS m FROM tops_sp),
exact AS (
  SELECT DISTINCT e.blk, e.m FROM (
    SELECT t.blk, (SELECT min(p.m) FROM pos p
                    WHERE p.blk = t.blk AND p.m > t.raw_t + 1) AS m
    FROM tops_sp t) e
  WHERE e.m IS NOT NULL
)
SELECT :'wsg' AS wsg,
       (SELECT count(*) FROM pos)   AS positions_all,
       (SELECT count(*) FROM tops)  AS positions_top_per_species,
       (SELECT count(*) FROM exact) AS positions_exact;
