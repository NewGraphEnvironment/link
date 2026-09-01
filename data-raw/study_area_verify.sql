-- Verification for the 2026-08-31 field-scope run.
-- Independent of the driver's exit code: a wrapper's exit 0 is not the work
-- completing. Every check below reads what actually landed.
--
-- Run against local docker fwapg:
--   psql -h localhost -p 5432 -U postgres -d fwapg -f verify_field_run.sql

\echo '=== 1. Provenance: rows written by THIS run (log) ==='
-- Expect 34 completed (date_end NOT NULL -- a row with date_start and no
-- date_end is a WSG that began and never finished, which is what the killed
-- attempt left behind for FRCN).
--
-- fresh_sha is expected NULL on the DISPATCHER and non-NULL on CYPHERS.
-- Measured 2026-08-31: m1 installs fresh locally (RemoteType: local, no
-- RemoteSha), so there is no SHA to record; cyphers install from GitHub via
-- the DESCRIPTION Remotes pin and do carry one. Asserting it non-NULL
-- everywhere reports a false failure on a healthy dispatcher.
SELECT host,
       count(*)                                       AS n_wsg,
       count(*) FILTER (WHERE link_sha  IS NOT NULL)  AS has_link_sha,
       count(*) FILTER (WHERE fresh_sha IS NOT NULL)  AS has_fresh_sha,
       count(*) FILTER (WHERE fwapg_sha IS NOT NULL)  AS has_fwapg_sha,
       count(*) FILTER (WHERE link_dirty)             AS n_dirty,
       min(date_end)                                  AS first_done,
       max(date_end)                                  AS last_done
  FROM fresh.log
 WHERE date_end > now() - interval '6 hours'
 GROUP BY host
 ORDER BY host;

\echo ''
\echo '=== 1b. Provenance verdict (host-aware) ==='
SELECT host,
       CASE
         WHEN count(*) FILTER (WHERE link_sha IS NULL) > 0
           THEN 'FAIL: link_sha NULL'
         WHEN count(*) FILTER (WHERE fwapg_sha IS NULL) > 0
           THEN 'FAIL: fwapg_sha NULL'
         WHEN host <> 'm1' AND count(*) FILTER (WHERE fresh_sha IS NULL) > 0
           THEN 'FAIL: fresh_sha NULL on a cypher'
         WHEN host = 'm1' AND count(*) FILTER (WHERE fresh_sha IS NOT NULL) > 0
           THEN 'NOTE: dispatcher now carries a fresh_sha (install method changed)'
         ELSE 'OK'
       END AS verdict
  FROM fresh.log
 WHERE date_end > now() - interval '6 hours'
 GROUP BY host
 ORDER BY host;

\echo ''
\echo '=== 1c. Started but never finished (must be empty) ==='
SELECT host, watershed_group_code, date_start
  FROM fresh.log
 WHERE date_start > now() - interval '6 hours' AND date_end IS NULL
 ORDER BY host, watershed_group_code;

\echo ''
\echo '=== 2. The distinct SHAs -- all hosts must agree ==='
SELECT DISTINCT link_sha, fresh_sha, fwapg_sha
  FROM fresh.log
 WHERE date_end > now() - interval '6 hours';

\echo ''
\echo '=== 3. Coverage: every expected WSG has streams rows ==='
-- Absence of evidence must be reported as absence. The LEFT JOIN yields a row
-- for a WSG with no streams rather than a short result nobody counts.
WITH expected(wsg) AS (
  VALUES ('LFRA'),('HARR'),('FRCN'),('SETN'),('BBAR'),('DOGC'),('MFRA'),
         ('TWAC'),('NARC'),('COTR'),('TABR'),('LCHL'),('LSAL'),('MORK'),
         ('WILL'),('BOWR'),('NECR'),('UFRA'),('FRAN'),
         ('LPCE'),('PINE'),('UPCE'),('PCEA'),('PARA'),('CARP'),('NATR'),
         ('PARS'),('CRKD'),
         ('LSKE'),('KLUM'),('KISP'),('ZYMO'),('BULK'),('MORR')
)
SELECT e.wsg,
       coalesce(s.n, 0)          AS n_segments,
       (l.watershed_group_code IS NOT NULL) AS logged_this_run
  FROM expected e
  LEFT JOIN (SELECT watershed_group_code, count(*) n
               FROM fresh.streams GROUP BY 1) s
         ON s.watershed_group_code = e.wsg
  LEFT JOIN (SELECT DISTINCT watershed_group_code
               FROM fresh.log
              WHERE date_end > now() - interval '6 hours') l
         ON l.watershed_group_code = e.wsg
 ORDER BY (coalesce(s.n,0) = 0) DESC, e.wsg;

\echo ''
\echo '=== 4. Any expected WSG with ZERO segments (must be empty) ==='
WITH expected(wsg) AS (
  VALUES ('LFRA'),('HARR'),('FRCN'),('SETN'),('BBAR'),('DOGC'),('MFRA'),
         ('TWAC'),('NARC'),('COTR'),('TABR'),('LCHL'),('LSAL'),('MORK'),
         ('WILL'),('BOWR'),('NECR'),('UFRA'),('FRAN'),
         ('LPCE'),('PINE'),('UPCE'),('PCEA'),('PARA'),('CARP'),('NATR'),
         ('PARS'),('CRKD'),
         ('LSKE'),('KLUM'),('KISP'),('ZYMO'),('BULK'),('MORR')
)
SELECT e.wsg
  FROM expected e
  LEFT JOIN fresh.streams s ON s.watershed_group_code = e.wsg
 GROUP BY e.wsg
HAVING count(s.*) = 0;

\echo ''
\echo '=== 5. Whole-schema picture: the mixture this run leaves behind ==='
-- 93 WSGs were in fresh before; 34 are now provenanced. The remainder keep
-- May-primitive rows. This is issue #256's subject -- report it, do not hide it.
SELECT count(DISTINCT watershed_group_code) AS wsg_in_streams FROM fresh.streams;
SELECT count(DISTINCT watershed_group_code) AS wsg_with_any_log FROM fresh.log;
