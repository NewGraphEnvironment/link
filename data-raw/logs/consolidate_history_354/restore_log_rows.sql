-- Restore the log rows run_uid 20261017_004619-3f4c713b's consolidate deleted
-- from fresh_default (link#354). Source: the driver's pre-consolidate backup
-- /tmp/fresh_default_pre_consolidate_202610162242.dump (machine-local), its
-- log / log_input / log_recompute data loaded into zz354_restore first:
--
--   pg_restore --data-only -t <t> -f <t>.sql <dump>
--   sed 's/^COPY fresh_default\./COPY zz354_restore./' <t>.sql | psql
--
-- Additive: a row whose primary key is present is left alone, so re-running
-- this changes nothing. Columns added since the dump take NULL.
\set ON_ERROR_STOP on
BEGIN;

SELECT 'before' AS at,
       (SELECT count(*) FROM fresh_default.log)       AS log,
       (SELECT count(*) FROM fresh_default.log_input) AS log_input;

INSERT INTO fresh_default.log
SELECT * FROM zz354_restore.log
ON CONFLICT (run_id) DO NOTHING;

INSERT INTO fresh_default.log_input
SELECT * FROM zz354_restore.log_input
ON CONFLICT (run_id, table_name) DO NOTHING;

SELECT 'after' AS at,
       (SELECT count(*) FROM fresh_default.log)       AS log,
       (SELECT count(*) FROM fresh_default.log_input) AS log_input;

-- Every restored log_input row belongs to a restored log row.
SELECT l.watershed_group_code, l.run_id, l.date_start::date, l.link_version,
       (SELECT count(*) FROM fresh_default.log_input i
         WHERE i.run_id = l.run_id) AS log_input_rows
  FROM fresh_default.log l
 WHERE l.run_id IN (SELECT run_id FROM zz354_restore.log)
   AND l.run_uid IS DISTINCT FROM '20261017_004619-3f4c713b'
 ORDER BY 1;

COMMIT;
