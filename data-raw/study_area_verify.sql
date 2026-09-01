-- Verification for a study-area run, keyed on run_uid (link#262).
--
-- Independent of the driver's exit code: a wrapper's exit 0 is not the work
-- completing. Every check below reads what actually landed.
--
--   psql -h localhost -p 5432 -U postgres -d fwapg \
--        -v ON_ERROR_STOP=1 -v run_uid=20260901T184455-3f9ac1 \
--        -f data-raw/study_area_verify.sql
--
-- `-v run_uid=` is optional; without it the most recent labelled run is used.
-- `-v schema=` defaults to `fresh`.
--
-- WHAT CHANGED FROM THE 2026-08-31 VERSION, and why it had to
-- ------------------------------------------------------------------
-- That version selected on `date_end > now() - interval '6 hours'` and
-- compared against a hardcoded 34-WSG VALUES list. Both were wrong for the
-- provincial run before it was even attempted:
--
--   * a time window is ambiguous the moment two runs overlap, and fragile
--     across three hosts even when they do not;
--   * a literal WSG list is a scope pinned to nothing — it silently describes
--     whatever the last campaign happened to be, and at 217 WSGs it would have
--     verified the wrong 34.
--
-- The per-WSG detail is now DERIVED from the run's own rows, so it cannot
-- drift from the run it claims to check.
--
-- BUT the COUNT is supplied from outside, via `-v expected_n=`. Deriving the
-- expected set entirely from `fresh.log` would be circular: a WSG that never
-- produced a log row simply vanishes from "expected", and "produced no log
-- row" is precisely the failure the check exists to catch. That is the
-- guard-defeated-by-its-own-operation shape, and it is the reason the old
-- hardcoded VALUES list existed at all — the list was the wrong externality,
-- not proof that no externality was needed.
--
-- expected_n IS THE COUNT OF WSGs EXPECTED TO **MODEL**, WHICH IS NOT THE SIZE
-- OF THE RUN'S BUCKET. A WSG with no bundle-species presence is skipped by
-- wsg_run_one.R with exit 0 and writes no log row (link#157), so passing
-- `csv_count "$ALL_WSGS"` would raise on a perfectly healthy run whenever the
-- closure contains one. The driver already distinguishes the two: bucket_done()
-- parses both `done` and `SKIP` lines, so the modelled count is the `done`
-- lines alone:
--
--   sed -nE 's/^\[wsg_run_one\] ([A-Z]{4}) .*done.*/\1/p' <run log> | sort -u | wc -l
--
-- Omitting expected_n is legitimate and is reported as NOT CHECKED rather than
-- silently skipped -- an unasserted count reads exactly like an asserted one.
--
-- ON_ERROR_STOP=1 is not decoration. The final check RAISEs, so this script
-- exits non-zero on a real failure rather than printing a table nobody reads.
-- It is negative-tested by data-raw/study_area_verify_negative.sh.

\set ON_ERROR_STOP on

\if :{?schema}
\else
\set schema fresh
\endif

-- Optional. Unset means "do not assert the count" -- reported below rather
-- than silently skipped, because an unasserted count reads as an asserted one.
\if :{?expected_n}
\else
\set expected_n ''
\endif

-- Resolve the run. coalesce + a scalar subquery so exactly one row always
-- comes back: `\gset` against an empty result leaves the variable UNSET, and
-- every later `:'run_uid'` would then break with an error about syntax rather
-- than about the missing run.
\if :{?run_uid}
\else
SELECT coalesce((SELECT run_uid FROM :schema.log
                  WHERE run_uid IS NOT NULL
                  ORDER BY date_start DESC LIMIT 1), '') AS run_uid \gset
\endif

-- Absence of evidence reported as absence. An unlabelled run yields zero rows
-- for every check below, and zero rows printed is indistinguishable from
-- "everything passed" — the exact failure mode this file exists to avoid.
SELECT (:'run_uid' <> '') AS have_run \gset
\if :have_run
\else
\echo ''
\echo 'FATAL: no run_uid supplied and none found in the log.'
\echo '  Every check here is scoped to one run, so without an id they would'
\echo '  each return zero rows -- which prints as though nothing was wrong.'
\echo '  Re-run the campaign with data-raw/study_area_run.sh (which mints and'
\echo '  exports LNK_RUN_UID), or pass -v run_uid=<id> explicitly.'
-- RAISE, not `\quit 1`. psql's \quit takes NO exit-code argument: it warns
-- `extra argument "1" ignored` and exits 0 (measured, psql 18.3). So the
-- natural form prints FATAL in red and then reports success — a
-- fail-toward-pass on the exact branch that exists to stop a silent zero-row
-- pass. ON_ERROR_STOP is set at the top of this file, so a raised exception
-- both stops the script and sets a non-zero status.
DO $$ BEGIN
  RAISE EXCEPTION 'no run_uid supplied and none found in the log';
END $$;
\endif

\echo ''
\echo '=== run under verification ==='
-- n_attempted vs n_completed, deliberately separate. The 2026-08-31 version
-- filtered on `date_end > now() - interval '6 hours'`, which EXCLUDED rows
-- with a NULL date_end -- so its single count silently meant "completed".
-- Filtering on run_uid includes started-and-never-finished rows, so reporting
-- one number here would quietly redefine it as "attempted" while every comment
-- still said completed.
SELECT :'run_uid'                           AS run_uid,
       max(run_label)                       AS run_label,
       count(DISTINCT watershed_group_code) AS n_attempted,
       count(DISTINCT watershed_group_code)
         FILTER (WHERE date_end IS NOT NULL) AS n_completed,
       count(DISTINCT host)                 AS n_hosts,
       max(bcfp_model_version)              AS bcfp_reference,
       max(bcfp_pin_source)                 AS bcfp_pin_source,
       min(date_start)                      AS started,
       max(date_end)                        AS finished
  FROM :schema.log
 WHERE run_uid = :'run_uid';

SELECT CASE WHEN :'expected_n' = ''
            THEN 'NOT CHECKED: no -v expected_n= given, so a WSG that never logged is invisible'
            ELSE 'expected_n = ' || :'expected_n' END AS scope_assertion;

\echo ''
\echo '=== 1. Provenance per host ==='
-- fresh_sha is expected NULL on the DISPATCHER and non-NULL on CYPHERS.
-- Measured 2026-08-31: m1 installs fresh locally (RemoteType: local, no
-- RemoteSha), so there is no SHA to record; cyphers install from GitHub via
-- the DESCRIPTION Remotes pin and do carry one. Asserting it non-NULL
-- everywhere reports a false failure on a healthy dispatcher.
--
-- bcfp_model_run_id is likewise expected NULL on a tunnel-free run: the pin
-- comes from the local snapshot ledger, and log.json carries no run id
-- (link#262). bcfp_model_version is the one that must be present.
SELECT host,
       count(*)                                          AS n_wsg,
       count(*) FILTER (WHERE link_sha  IS NOT NULL)     AS has_link_sha,
       count(*) FILTER (WHERE fresh_sha IS NOT NULL)     AS has_fresh_sha,
       count(*) FILTER (WHERE fwapg_sha IS NOT NULL)     AS has_fwapg_sha,
       count(*) FILTER (WHERE bcfp_model_version
                              IS NOT NULL)               AS has_bcfp_version,
       count(*) FILTER (WHERE link_dirty)                AS n_dirty,
       count(*) FILTER (WHERE link_dirty IS NULL)        AS n_dirty_unknown,
       min(date_end)                                     AS first_done,
       max(date_end)                                     AS last_done
  FROM :schema.log
 WHERE run_uid = :'run_uid'
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
         WHEN count(*) FILTER (WHERE bcfp_model_version IS NULL) > 0
           THEN 'FAIL: bcfp_model_version NULL (snapshot ledger unreadable?)'
         WHEN count(*) FILTER (WHERE link_dirty) > 0
           THEN 'FAIL: link_dirty set -- tracked code differed from origin'
         -- NULL is "could not tell", NOT the same as FALSE, and it must not be
         -- collapsed into it: `x OR link_dirty` yields NULL for a NULL row, so
         -- the assertion below cannot see these at all. Reported here rather
         -- than raised, because NA is legitimate for an installed package with
         -- no .git and no <PKG>_GIT_DIRTY -- raising would refuse every
         -- hand-run. Unexpected on a driver run, where cypher_prep writes
         -- LINK_GIT_DIRTY into ~/.Renviron on every worker.
         WHEN count(*) FILTER (WHERE link_dirty IS NULL) > 0
           THEN 'NOTE: link_dirty NULL on some rows -- provenance unknown, not clean'
         WHEN host <> 'm1' AND count(*) FILTER (WHERE fresh_sha IS NULL) > 0
           THEN 'FAIL: fresh_sha NULL on a cypher'
         WHEN host = 'm1' AND count(*) FILTER (WHERE fresh_sha IS NOT NULL) > 0
           THEN 'NOTE: dispatcher now carries a fresh_sha (install method changed)'
         ELSE 'OK'
       END AS verdict
  FROM :schema.log
 WHERE run_uid = :'run_uid'
 GROUP BY host
 ORDER BY host;

\echo ''
\echo '=== 1c. Started but never finished (must be empty) ==='
SELECT host, watershed_group_code, date_start
  FROM :schema.log
 WHERE run_uid = :'run_uid' AND date_end IS NULL
 ORDER BY host, watershed_group_code;

\echo ''
\echo '=== 2. The distinct SHAs -- all hosts must agree ==='
SELECT DISTINCT link_sha, fwapg_sha, bcfp_model_version
  FROM :schema.log
 WHERE run_uid = :'run_uid';

\echo ''
\echo '=== 3. Coverage: every WSG of this run has streams rows ==='
-- The expected set is the run's own log rows, not a literal list. LEFT JOIN so
-- a WSG with no streams yields a row rather than a short result nobody counts.
SELECT l.watershed_group_code AS wsg,
       coalesce(s.n, 0)       AS n_segments
  FROM (SELECT DISTINCT watershed_group_code
          FROM :schema.log WHERE run_uid = :'run_uid') l
  LEFT JOIN (SELECT watershed_group_code, count(*) n
               FROM :schema.streams GROUP BY 1) s
         ON s.watershed_group_code = l.watershed_group_code
 ORDER BY (coalesce(s.n, 0) = 0) DESC, l.watershed_group_code;

\echo ''
\echo '=== 4. Modelled vs recomputed -- the difference, per WSG ==='
-- The gap link#262 exists to close. `log` records when a WSG was MODELLED;
-- the recompute is what rewrites streams_access and streams_mapping_code, and
-- those are the values that ship. A WSG modelled but not recomputed has
-- cross-WSG access -- hence token1/token2 and ;DAM -- computed against an
-- incomplete barrier set. That is bad output, not missing output: every other
-- check on this page passes for it.
SELECT coalesce(m.wsg, r.wsg)                              AS wsg,
       (m.wsg IS NOT NULL)                                 AS modelled,
       (r.wsg IS NOT NULL)                                 AS recomputed,
       m.done                                              AS model_done,
       r.done                                              AS recompute_done,
       CASE
         WHEN m.wsg IS NULL                THEN 'recomputed but never modelled'
         WHEN r.wsg IS NULL                THEN 'MODELLED BUT NOT RECOMPUTED'
         WHEN r.done IS NULL               THEN 'recompute started, never finished'
         WHEN m.done IS NULL               THEN 'model started, never finished'
         WHEN r.done < m.done              THEN 'RECOMPUTE PREDATES THE MODEL'
         ELSE 'ok'
       END                                                 AS state
  FROM (SELECT watershed_group_code AS wsg, max(date_end) AS done
          FROM :schema.log
         WHERE run_uid = :'run_uid' GROUP BY 1) m
  FULL JOIN (SELECT watershed_group_code AS wsg, max(date_end) AS done
               FROM :schema.log_recompute
              WHERE run_uid = :'run_uid' GROUP BY 1) r
         ON r.wsg = m.wsg
 ORDER BY (CASE WHEN m.wsg IS NULL OR r.wsg IS NULL
                  OR r.done IS NULL OR m.done IS NULL THEN 0 ELSE 1 END),
          coalesce(m.wsg, r.wsg);

\echo ''
\echo '=== 5. Whole-schema picture: the mixture this run leaves behind ==='
SELECT count(DISTINCT watershed_group_code) AS wsg_in_streams FROM :schema.streams;
SELECT count(DISTINCT watershed_group_code) AS wsg_with_any_log FROM :schema.log;
SELECT count(DISTINCT run_uid) AS runs_ever_labelled FROM :schema.log;

\echo ''
\echo '=== 6. ASSERTIONS (raise, so this script can actually fail) ==='
-- Everything above prints. This is the part that decides the exit status.
-- Negative-tested by data-raw/study_area_verify_negative.sh, which asserts all
-- three answers: healthy passes, a deleted recompute row fails, a wrong
-- expected_n fails.
--
-- Parameters arrive via set_config, NOT via :'run_uid' inside the block. psql
-- does not interpolate its variables inside a dollar-quoted string -- the body
-- is a string literal to it -- so the natural form fails with
-- `syntax error at or near ":"` at run time while reading perfectly. Found by
-- running it; nothing about the text suggests it.
SELECT set_config('lnk.run_uid',    :'run_uid',    false) AS run_uid,
       set_config('lnk.schema',     :'schema',     false) AS schema,
       set_config('lnk.expected_n', :'expected_n', false) AS expected_n
\gset assert_

DO $$
DECLARE
  v_run    text := current_setting('lnk.run_uid');
  v_sch    text := current_setting('lnk.schema');
  n_expect int  := nullif(current_setting('lnk.expected_n'), '')::int;
  n_model  int;
  n_gap    int;
  n_open   int;
  n_seg    int;
  n_prov   int;
  bad      text;
BEGIN
  EXECUTE format(
    'SELECT count(DISTINCT watershed_group_code) FROM %I.log WHERE run_uid = $1',
    v_sch) INTO n_model USING v_run;

  IF n_model = 0 THEN
    RAISE EXCEPTION 'run % has no rows in %.log', v_run, v_sch;
  END IF;

  -- The externally-supplied count. Without it every check below is scoped to
  -- whatever the run happened to log, so a WSG that never started is invisible
  -- to all of them -- the guard cannot see what its own input omitted.
  IF n_expect IS NOT NULL AND n_model <> n_expect THEN
    RAISE EXCEPTION
      'run %: % WSG(s) in the log, but -v expected_n=% was supplied. A WSG that never produced a log row is invisible to every other check on this page. If the difference is species-skipped WSGs, expected_n should count MODELLED WSGs (the `done` lines), not the run bucket -- see the header.',
      v_run, n_model, n_expect;
  END IF;

  -- Modelled but not recomputed. THE check link#262 exists for: these WSGs'
  -- streams_access and streams_mapping_code still hold pre-consolidate values,
  -- so cross-WSG access -- hence token1/token2 and ;DAM -- is wrong for them.
  -- Bad output, not missing output: every other check on this page passes.
  EXECUTE format(
    'SELECT count(*), coalesce(string_agg(wsg, '','' ORDER BY wsg), '''')
       FROM (SELECT DISTINCT watershed_group_code AS wsg FROM %I.log
              WHERE run_uid = $1
             EXCEPT
             SELECT DISTINCT watershed_group_code FROM %I.log_recompute
              WHERE run_uid = $1 AND date_end IS NOT NULL) t',
    v_sch, v_sch) INTO n_gap, bad USING v_run;

  IF n_gap > 0 THEN
    RAISE EXCEPTION
      'run %: % WSG(s) modelled but not recomputed: %. Re-run just those: LNK_SCHEMA=% LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R <WSG>',
      v_run, n_gap, bad, v_sch;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM %I.log WHERE run_uid = $1 AND date_end IS NULL',
    v_sch) INTO n_open USING v_run;
  IF n_open > 0 THEN
    RAISE EXCEPTION 'run %: % modelling row(s) started and never finished',
      v_run, n_open;
  END IF;

  EXECUTE format(
    'SELECT count(*) FROM (SELECT DISTINCT watershed_group_code w FROM %I.log
       WHERE run_uid = $1) l
       LEFT JOIN (SELECT watershed_group_code w, count(*) n FROM %I.streams
                   GROUP BY 1) s ON s.w = l.w
      WHERE coalesce(s.n, 0) = 0',
    v_sch, v_sch) INTO n_seg USING v_run;
  IF n_seg > 0 THEN
    RAISE EXCEPTION 'run %: % WSG(s) have zero rows in %.streams',
      v_run, n_seg, v_sch;
  END IF;

  -- Provenance that must be present on every row. fresh_sha and
  -- bcfp_model_run_id are deliberately NOT here -- both are legitimately NULL
  -- on a healthy tunnel-free dispatcher (measured 2026-08-31), and asserting
  -- them reports a false failure.
  EXECUTE format(
    'SELECT count(*) FROM %I.log
      WHERE run_uid = $1
        AND (link_sha IS NULL OR fwapg_sha IS NULL
             OR bcfp_model_version IS NULL OR link_dirty)',
    v_sch) INTO n_prov USING v_run;
  IF n_prov > 0 THEN
    RAISE EXCEPTION
      'run %: % row(s) missing link_sha / fwapg_sha / bcfp_model_version, or flagged link_dirty',
      v_run, n_prov;
  END IF;

  RAISE NOTICE 'PASS: run % -- % WSG(s), all modelled, recomputed, segmented and provenanced',
    v_run, n_model;
END $$;

\echo ''
\echo '=== verify: OK ==='
