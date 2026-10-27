-- link#261, refuted: does a walk cost track the province features whose code
-- can have descendants in the group code range [lo, hi]? SETN (range 0.75 M)
-- walks about twice as long as CHWK (range 7.2 M, codes 100 to 970), and LFRA
-- (range 7.2 M) only a little longer than SETN. Run with psql from this directory against fwapg.
\timing on
SELECT count(*) AS others FROM pg_stat_activity WHERE backend_type='client backend' AND state<>'idle' AND pid<>pg_backend_pid();
CREATE TEMP TABLE bw AS
  SELECT sp, wscode_ltree AS w, count(*)::bigint AS n
  FROM fresh_default.barriers b, unnest(b.blocks_species) sp
  WHERE barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')
  GROUP BY 1,2;
CREATE TEMP TABLE bc AS SELECT sp, w, n, sum(n) OVER (PARTITION BY sp ORDER BY w) AS cum FROM bw;
CREATE INDEX ON bc (sp, w);
ANALYZE bc;
CREATE TEMP TABLE g AS
  SELECT a.wsg, a.lo, b.hi, c.segs FROM
  (SELECT DISTINCT ON (watershed_group_code) watershed_group_code wsg, wscode_ltree lo FROM fresh_default.streams ORDER BY watershed_group_code, wscode_ltree) a
  JOIN (SELECT DISTINCT ON (watershed_group_code) watershed_group_code wsg, wscode_ltree hi FROM fresh_default.streams ORDER BY watershed_group_code, wscode_ltree DESC) b USING (wsg)
  JOIN (SELECT watershed_group_code wsg, count(*) segs FROM fresh_default.streams GROUP BY 1) c USING (wsg);
SELECT count(*) FROM g;
\copy (SELECT g.wsg, g.lo::text, g.hi::text, g.segs, s.sp, coalesce((SELECT cum FROM bc WHERE bc.sp=s.sp AND bc.w <= g.hi ORDER BY bc.w DESC LIMIT 1),0) - coalesce((SELECT cum FROM bc WHERE bc.sp=s.sp AND bc.w < g.lo ORDER BY bc.w DESC LIMIT 1),0) + coalesce((SELECT sum(n) FROM bc, generate_series(1, nlevel(g.lo)-1) k WHERE bc.sp=s.sp AND bc.w = subpath(g.lo,0,k)),0) AS in_range FROM g CROSS JOIN (SELECT DISTINCT sp FROM bc) s ORDER BY 1,5) TO 'range_hypothesis.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER)
