-- identical.sql — #440: zz432_post and zz440_default hold the same rows in every
-- persisted table, for the four test groups, in both directions. One row per table;
-- only_post and only_440 are both 0 where they match.
\set groups '''KETL'',''KOTL'',''BULK'',''MURT'''
SELECT t AS table_name,
       (xpath('/row/n/text()', query_to_xml(format(
          'SELECT count(*) AS n FROM (SELECT * FROM zz432_post.%I WHERE watershed_group_code IN (%s)
             EXCEPT SELECT * FROM zz440_default.%I WHERE watershed_group_code IN (%s)) d', t, :'groups', t, :'groups'),
          false, true, '')))[1]::text::int AS only_post,
       (xpath('/row/n/text()', query_to_xml(format(
          'SELECT count(*) AS n FROM (SELECT * FROM zz440_default.%I WHERE watershed_group_code IN (%s)
             EXCEPT SELECT * FROM zz432_post.%I WHERE watershed_group_code IN (%s)) d', t, :'groups', t, :'groups'),
          false, true, '')))[1]::text::int AS only_440
  FROM unnest(ARRAY(
    SELECT a.table_name::text FROM information_schema.tables a
      JOIN information_schema.tables b ON b.table_name = a.table_name AND b.table_schema = 'zz432_post'
     WHERE a.table_schema = 'zz440_default' AND a.table_type = 'BASE TABLE'
       AND a.table_name ~ '^(streams|streams_access|streams_mapping_code|streams_habitat_[a-z]+|streams_habitat_near_river|barriers|barrier_overrides)$'
     ORDER BY 1)) t;
