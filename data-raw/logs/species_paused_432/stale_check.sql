-- The #432 assertion of study_area_verify.sql, alone, for a run that fails earlier checks.
SELECT set_config('lnk.run_uid', :'run_uid', false), set_config('lnk.schema', :'schema', false);
DO $$
DECLARE
  v_run text := current_setting('lnk.run_uid'); v_sch text := current_setting('lnk.schema');
  n_sp int; n_stale int := 0; v_sp text; bad text := '';
BEGIN
  -- Habitat no build of the run classified (link#432). A group's newest
  -- finished modelling row of the run lists the species it classified
  -- (log.species). A row in streams_habitat_<sp> for a group whose list
  -- leaves <sp> out is an earlier build's, cut to segments that no longer
  -- exist: a species the bundle now pauses, or no longer present. A full
  -- build clears them (lnk_pipeline_run), and a consolidate's per-group
  -- replace reaches every table both sides share, which a pause leaves in
  -- place (lnk_persist_init). Rows logged before log.species existed (NULL)
  -- are not judged.

  FOR v_sp IN
    SELECT substr(t.table_name, 17)
      FROM information_schema.tables t
     WHERE t.table_schema = v_sch
       AND t.table_name ~ '^streams_habitat_[a-z]+$'
       AND t.table_type = 'BASE TABLE'
     ORDER BY 1
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I.%I h
        WHERE h.watershed_group_code IN (
          SELECT l.watershed_group_code
            FROM (SELECT DISTINCT ON (watershed_group_code)
                         watershed_group_code, species
                    FROM %I.log
                   WHERE run_uid = $1 AND date_end IS NOT NULL
                   ORDER BY watershed_group_code, date_end DESC) l
           WHERE l.species IS NOT NULL AND NOT ($2 = ANY (l.species)))',
      v_sch, 'streams_habitat_' || v_sp, v_sch)
      INTO n_sp USING v_run, upper(v_sp);
    IF n_sp > 0 THEN
      n_stale := n_stale + n_sp;
      bad := concat_ws(', ', nullif(bad, ''), upper(v_sp) || ' ' || n_sp);
    END IF;
  END LOOP;
  IF n_stale > 0 THEN
    RAISE EXCEPTION
      'run %: % habitat row(s) in streams_habitat_<sp> belong to a species the group''s newest build of the run did not classify (%). They are an earlier build''s, on segments that no longer exist (link#432): re-model the group under this run_uid, or delete them.',
      v_run, n_stale, bad;
  END IF;

  RAISE NOTICE 'stale check: OK'; END $$;
