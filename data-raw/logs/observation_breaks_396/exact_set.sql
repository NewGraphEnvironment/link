-- A smaller break set that keeps access code 2 nearly as `all` gives it
-- (#396, code-check rounds 2 and 3). The walk reads a same-line observation as
-- upstream of a segment when it lies above the segment's start or within 1 m
-- of it, so a species' own top break never changes its own code: the segment
-- starting at the top still reads 2. Species X turns from 2 to 1 at the first
-- cut more than 1 m above its raw top raw_t. Keeping, per species, the lowest
-- observation position (of any species) above raw_t + 1 keeps that turn where
-- `all` puts it, except in three cases: a removed position that suppressed a
-- later break within 1 m releases it (RUNBOOK §2c); a kept position within 1 m
-- of an FWA end does not cut; and where an FWA end or another source's cut lies
-- between the top and the kept position, the turn happens there and the
-- position is not needed. The first two make the rule keep too few positions,
-- the third too many, so the count is the rule's own size, not a bound, and the
-- rule is near-exact, not exact. Counted against `all` and `top_per_species`.
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
