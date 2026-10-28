-- The main access change the reduced breaks make (#396): an AFTER segment
-- that starts at species X's kept top T and swallows a removed break R more
-- than 1 m above X's raw top reads X = 2 ("observed upstream") along its whole
-- length, where the BEFORE piece starting at R read 1. A pre-build estimate,
-- not a bound: it misses the changes from released breaks (RUNBOOK §2c), and
-- it counts a piece where X is blocked in
-- both builds, or where R never cut because it lay within 1 m of an FWA end.
-- pre_post_diff.R measures the change after the builds.
--
--   psql -X -A -F, -v wsg=PARS -v obs=obs_pars -v wk=working_pars \
--     -f data-raw/logs/observation_breaks_396/code2_class.sql
--
-- For each top (per blue_line_key, species; raw measure raw_t, as the walk
-- compares it with rounded segment starts): the next cut above it is the
-- nearest FWA segment end, other break source position or kept top (any
-- species) more than 1 m above raw_t. Removed positions R in
-- (raw_t + 1, next - 1) cut BEFORE and not AFTER. The piece from the lowest R to
-- the next cut flips unless X is observed upstream of it on another line
-- (fwa_upstream, include_equivalents, 1 m), which the access walk would also
-- read. The walk reads the group's own observations (`<schema>.observations`,
-- lnk_pipeline_run()), so this does too. Same estimate caveat as cuts.sql for
-- the other break sources (:wk).
WITH obs AS (
  SELECT blue_line_key AS blk, species_code AS sp,
         round(downstream_route_measure) AS m,
         downstream_route_measure AS raw_m, wscode, localcode
  FROM zz396_cuts.:"obs"
),
tops_sp AS (SELECT blk, sp, round(max(raw_m)) AS m, max(raw_m) AS raw_t
            FROM obs GROUP BY blk, sp),
pos AS (SELECT DISTINCT blk, m FROM obs),
tops AS (SELECT DISTINCT blk, m FROM tops_sp),
removed AS (SELECT p.blk, p.m FROM pos p
            WHERE NOT EXISTS (SELECT 1 FROM tops t WHERE t.blk = p.blk AND t.m = p.m)),
fwa AS (
  SELECT blue_line_key AS blk, downstream_route_measure AS m
  FROM whse_basemapping.fwa_stream_networks_sp WHERE watershed_group_code = :'wsg'
  UNION ALL
  SELECT blue_line_key, upstream_route_measure
  FROM whse_basemapping.fwa_stream_networks_sp WHERE watershed_group_code = :'wsg'
),
cut AS (
  SELECT blk, m FROM fwa
  UNION ALL SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".gradient_barriers_minimal
  UNION ALL SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".falls
  UNION ALL SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".barriers_definite
  UNION ALL SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".habitat_endpoints
  UNION ALL SELECT blue_line_key, round(downstream_route_measure) FROM :"wk".crossings_breaks
  UNION ALL SELECT blk, m FROM tops
),
nxt AS (
  SELECT t.blk, t.sp, t.m, t.raw_t,
         (SELECT min(c.m) FROM cut c WHERE c.blk = t.blk AND c.m > t.raw_t + 1) AS next_m
  FROM tops_sp t
),
cls AS (
  SELECT n.*, (SELECT min(r.m) FROM removed r
               WHERE r.blk = n.blk AND r.m > n.raw_t + 1 AND r.m < n.next_m - 1) AS r_m
  FROM nxt n
),
hit AS (
  SELECT c.*, s.wscode_ltree, s.localcode_ltree
  FROM cls c
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON s.blue_line_key = c.blk
   AND s.downstream_route_measure <= c.r_m AND c.r_m < s.upstream_route_measure
  WHERE c.r_m IS NOT NULL
),
flip AS (
  SELECT h.*, NOT EXISTS (
    SELECT 1 FROM obs o
    WHERE o.sp = h.sp AND o.blk <> h.blk
      AND o.wscode <@ h.wscode_ltree
      AND whse_basemapping.fwa_upstream(h.blk, h.r_m::double precision,
            h.wscode_ltree, h.localcode_ltree,
            o.blk, o.m::double precision, o.wscode, o.localcode, true, 1)
  ) AS flips
  FROM hit h
)
SELECT :'wsg' AS wsg, t.sp,
       count(*)                                              AS tops,
       (SELECT count(*) FROM flip f WHERE f.sp = t.sp)       AS tops_with_removed_above,
       (SELECT count(*) FROM flip f WHERE f.sp = t.sp AND f.flips) AS pieces_1_to_2,
       coalesce(round(((SELECT sum(f.next_m - f.r_m) FROM flip f
                        WHERE f.sp = t.sp AND f.flips) / 1000)::numeric, 3), 0) AS km_1_to_2
FROM tops_sp t
GROUP BY t.sp
ORDER BY t.sp;
