-- pretest_override.sql (link#372): a run launched without a passing pre-run
-- gate record, on --pretest-note. study_area_run.sh runs it with
--   psql -v schema= -v config= -v sha= -v note= -v uid=
-- The `override` verdict is never read as a gate by pretest_record_check().
-- The table's shape matches pretest_verdict.R's.
CREATE TABLE IF NOT EXISTS :"schema".log_pretest (
  run_at      timestamptz NOT NULL DEFAULT now(),
  config_name text NOT NULL,
  link_sha    text,
  link_dirty  boolean,
  fresh_sha   text,
  since_sha   text NOT NULL,
  until_sha   text NOT NULL,
  scratch     text NOT NULL,
  k           double precision NOT NULL,
  floor_min   double precision NOT NULL,
  per_input   integer NOT NULL,
  groups      text,
  verdict     text NOT NULL CHECK (verdict IN ('pass', 'fail', 'override')),
  notes       text);
INSERT INTO :"schema".log_pretest (config_name, link_sha, since_sha, until_sha, scratch, k,
  floor_min, per_input, verdict, notes)
VALUES (:'config', :'sha', :'sha', :'sha', '', 0, 0, 0, 'override',
        'run_uid ' || :'uid' || ': ' || :'note');
