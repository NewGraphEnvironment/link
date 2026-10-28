-- Question 5 (#396): a line's top observation of species X is redundant when
-- X is also observed up a tributary that joins above it. The segment below the
-- confluence then reads X = 2 without the top's break, so the break changes no
-- access code. Counted against the group's own observations, as the access
-- walk reads them (fwa_upstream, include_equivalents, 1 m).
--
--   psql -X -A -F, -v wsg=PARS -v obs=obs_pars \
--     -f data-raw/logs/observation_breaks_396/redundancy.sql
WITH obs AS (
  SELECT blue_line_key AS blk, species_code AS sp,
         round(downstream_route_measure) AS m, wscode, localcode
  FROM zz396_cuts.:"obs"
),
tops_sp AS (
  SELECT DISTINCT ON (blk, sp) blk, sp, m, wscode, localcode
  FROM obs ORDER BY blk, sp, m DESC
),
red AS (
  SELECT t.*, EXISTS (
    SELECT 1 FROM obs o
    WHERE o.sp = t.sp AND o.blk <> t.blk
      AND o.wscode <@ t.wscode
      AND whse_basemapping.fwa_upstream(t.blk, t.m::double precision,
            t.wscode, t.localcode, o.blk, o.m::double precision,
            o.wscode, o.localcode, true, 1)
  ) AS redundant
  FROM tops_sp t
),
pos AS (SELECT DISTINCT blk, m FROM obs),
keep AS (SELECT DISTINCT blk, m FROM red WHERE NOT redundant)
SELECT :'wsg' AS wsg,
       (SELECT count(*) FROM red)                         AS tops_species,
       (SELECT count(*) FROM red WHERE redundant)         AS tops_species_redundant,
       (SELECT count(DISTINCT (blk, m)) FROM red)         AS top_positions,
       (SELECT count(*) FROM keep)                        AS top_positions_if_removed,
       (SELECT count(*) FROM pos)                         AS positions_today;
