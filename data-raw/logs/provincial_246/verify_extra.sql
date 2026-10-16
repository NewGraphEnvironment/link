-- verify_extra.sql — the provenance checks study_area_verify.sql does not make,
-- for one dispatch (link#246). Raises (exit 3 under ON_ERROR_STOP) on failure.
--
--   psql -h localhost -p 5432 -U postgres -d fwapg \
--     -v schema=fresh_default -v run_uid=<run_uid> -v expected_n=241 \
--     -f data-raw/logs/provincial_246/verify_extra.sql
--
-- Asserts, for the run_uid:
--   1. exactly expected_n groups logged, one config_hash, none NULL, no config_drift
--   2. every group in <schema>.streams has its newest log row from this run
--   3. every run_id has log_input rows, with row_count set
--   4. log_parameters_fresh, log_dimensions and log_parameters_habitat_thresholds
--      hold rows for the run's config_hash
--   5. loader version ids for bcfishobs.observations and
--      fresh.modelled_stream_crossings agree across hosts, and so does
--      row_count for every snapshot-loaded (non-FWA) input table
-- Reports (does not assert) per-host artifact rows for FWA tables, which are
-- probes, and api sources, whose version ids are NULL by design.

\set ON_ERROR_STOP on
SELECT set_config('lnk.schema', :'schema', false),
       set_config('lnk.run_uid', :'run_uid', false),
       set_config('lnk.expected_n', :'expected_n', false);

DO $$
DECLARE
  s   text := current_setting('lnk.schema');
  ru  text := current_setting('lnk.run_uid');
  en  int  := current_setting('lnk.expected_n')::int;
  n   int;
  h   text;
  fails text[] := '{}';
BEGIN
  -- 1
  EXECUTE format('SELECT count(DISTINCT watershed_group_code) FROM %I.log WHERE run_uid = $1', s) INTO n USING ru;
  IF n <> en THEN fails := fails || format('groups logged %s, expected %s', n, en); END IF;
  EXECUTE format('SELECT count(*) FROM %I.log WHERE run_uid = $1 AND (config_hash IS NULL OR config_drift IS DISTINCT FROM false)', s) INTO n USING ru;
  IF n > 0 THEN fails := fails || format('%s rows with NULL config_hash or config_drift not FALSE', n); END IF;
  EXECUTE format('SELECT count(DISTINCT config_hash) FROM %I.log WHERE run_uid = $1', s) INTO n USING ru;
  IF n <> 1 THEN fails := fails || format('%s distinct config_hash values', n); END IF;
  EXECUTE format('SELECT min(config_hash) FROM %I.log WHERE run_uid = $1', s) INTO h USING ru;

  -- 2
  EXECUTE format($q$
    SELECT count(*) FROM (SELECT DISTINCT watershed_group_code FROM %1$I.streams) g
    WHERE NOT EXISTS (
      SELECT 1 FROM %1$I.log l
      WHERE l.watershed_group_code = g.watershed_group_code AND l.run_uid = $1
        AND l.date_start = (SELECT max(date_start) FROM %1$I.log m
                            WHERE m.watershed_group_code = g.watershed_group_code))$q$, s)
    INTO n USING ru;
  IF n > 0 THEN fails := fails || format('%s groups in streams whose newest log row is not this run', n); END IF;

  -- 3
  EXECUTE format($q$
    SELECT count(*) FROM %1$I.log l WHERE l.run_uid = $1
      AND NOT EXISTS (SELECT 1 FROM %1$I.log_input i WHERE i.run_id = l.run_id AND i.row_count IS NOT NULL)$q$, s)
    INTO n USING ru;
  IF n > 0 THEN fails := fails || format('%s run_ids with no log_input row_count', n); END IF;

  -- 4
  EXECUTE format('SELECT count(*) FROM %I.log_parameters_fresh WHERE config_hash = $1', s) INTO n USING h;
  IF n = 0 THEN fails := fails || 'no log_parameters_fresh rows for the config_hash'::text; END IF;
  EXECUTE format('SELECT count(*) FROM %I.log_dimensions WHERE config_hash = $1', s) INTO n USING h;
  IF n = 0 THEN fails := fails || 'no log_dimensions rows for the config_hash'::text; END IF;
  EXECUTE format('SELECT count(*) FROM %I.log_parameters_habitat_thresholds WHERE config_hash = $1', s) INTO n USING h;
  IF n = 0 THEN fails := fails || 'no log_parameters_habitat_thresholds rows for the config_hash'::text; END IF;

  -- 5
  EXECUTE format($q$
    SELECT count(*) FROM (
      SELECT i.table_name FROM %1$I.log_input i JOIN %1$I.log l USING (run_id)
      WHERE l.run_uid = $1
        AND i.table_name IN ('bcfishobs.observations', 'fresh.modelled_stream_crossings')
      GROUP BY i.table_name
      HAVING count(DISTINCT coalesce(i.artifact_version_id, '<NULL>')) <> 1) x$q$, s)
    INTO n USING ru;
  IF n > 0 THEN fails := fails || format('%s loader tables read at different versions across hosts', n); END IF;
  -- row_count is the table-wide reltuples estimate, logged per group. The
  -- snapshot-loaded tables are analyzed at load, so their estimate must agree
  -- across hosts; FWA tables come from each host's own load and their
  -- estimates drift with autovacuum (2026-09-01: two values on three hosts),
  -- so they are reported below, not asserted.
  EXECUTE format($q$
    SELECT count(*) FROM (
      SELECT i.table_name FROM %1$I.log_input i JOIN %1$I.log l USING (run_id)
      WHERE l.run_uid = $1 AND i.table_name NOT LIKE 'whse_basemapping.%%'
      GROUP BY i.table_name HAVING count(DISTINCT i.row_count) > 1) x$q$, s)
    INTO n USING ru;
  IF n > 0 THEN fails := fails || format('%s snapshot-loaded tables with differing row_count across hosts', n); END IF;

  IF array_length(fails, 1) > 0 THEN
    RAISE EXCEPTION 'verify_extra FAILED for % in %: %', ru, s, array_to_string(fails, '; ');
  END IF;
  RAISE NOTICE 'verify_extra PASS: % groups, config_hash %, run_uid %', en, h, ru;
END $$;

-- Report: per-host artifact identity, the axis the assertions above cannot judge.
SELECT l.host, i.table_name, i.artifact_recorded_by, i.artifact_version_id,
       count(*) AS n_rows, min(i.row_count) AS row_count_min, max(i.row_count) AS row_count_max
FROM :"schema".log_input i JOIN :"schema".log l USING (run_id)
WHERE l.run_uid = :'run_uid'
GROUP BY 1, 2, 3, 4 ORDER BY 2, 1;
