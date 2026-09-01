-- recompute_checksum.sql — deterministic per-WSG digest of everything the
-- post-consolidate recompute writes (link#250).
--
-- Used by data-raw/recompute_parity.sh to prove that running the recompute
-- N-wide produces byte-identical output to running it serially. Sibling of
-- data-raw/study_area_verify.sql.
--
--   psql -h localhost -p 5432 -U postgres -d fwapg --csv \
--        -v schema=fresh -f data-raw/recompute_checksum.sql
--
-- Design notes, each of which is load-bearing:
--
--   * PER WSG, not one global digest. A single number tells you it broke;
--     per-WSG rows tell you WHICH, which is the difference between a
--     five-minute diagnosis and a re-run.
--
--   * Columns enumerated ORDER BY column_name — alphabetical, NOT
--     ordinal_position. A future ALTER TABLE ADD COLUMN landing in a
--     different order on a different schema would otherwise change the digest
--     of data that did not change.
--
--   * Rows ordered by id_segment WITHIN each watershed_group_code. The PK is
--     (id_segment, watershed_group_code) — id_segment is NOT globally unique
--     across WSGs in the consolidated persist (link#203), so ordering on it
--     alone would be non-deterministic.
--
--   * md5 of concatenated per-row md5s, not of the concatenated rows. Keeps
--     the aggregate state at 32 bytes per row instead of the full row text,
--     so this stays cheap on a 100k-segment WSG.
--
--   * ROW(...)::text distinguishes NULL (nothing between the commas) from the
--     empty string (rendered as ""). Do NOT add a coalesce sentinel here — it
--     would make those two collide.
--
--   * Session settings pinned below so text rendering cannot drift. Neither
--     table has a floating-point column today, but the guard is only useful
--     BEFORE one is added, not after.

\set ON_ERROR_STOP on

SET extra_float_digits = 3;
SET DateStyle = 'ISO, MDY';
SET TimeZone = 'UTC';
SET bytea_output = 'hex';
SET lc_numeric = 'C';

-- Fail loudly if either table is absent. Without this, format() over a NULL
-- column list yields NULL, string_agg silently drops it, and the run would
-- report a clean digest computed over half the data — a narrower measurement
-- wearing a complete one's clothes.
-- The schema travels via a GUC because psql does NOT interpolate :'schema'
-- inside a dollar-quoted body — it is lexed as literal text there.
SELECT set_config('lnk.parity_schema', :'schema', false) \gset chk_

DO $guard$
DECLARE
  sch     text := current_setting('lnk.parity_schema');
  missing text;
BEGIN
  SELECT string_agg(t, ', ') INTO missing
    FROM (VALUES ('streams_access'), ('streams_mapping_code')) v(t)
   WHERE to_regclass(format('%I.%I', sch, v.t)) IS NULL;
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'recompute_checksum: missing in schema %: %', sch, missing;
  END IF;
END
$guard$;

SELECT string_agg(q, E'\nUNION ALL\n' ORDER BY ord) || E'\n ORDER BY 1, 2'
FROM (
  SELECT t.ord,
         format(
           $f$SELECT %L::text AS tbl, s.watershed_group_code,
                     count(*)::bigint AS n_rows,
                     md5(string_agg(md5(s.r::text), '' ORDER BY s.id_segment))
                       AS digest
                FROM (SELECT watershed_group_code, id_segment, ROW(%s) AS r
                        FROM %I.%I) s
               GROUP BY s.watershed_group_code$f$,
           t.tbl, c.cols, :'schema', t.tbl) AS q
    FROM (VALUES (1, 'streams_access'), (2, 'streams_mapping_code'))
           AS t(ord, tbl)
    CROSS JOIN LATERAL (
      SELECT string_agg(quote_ident(column_name), ', ' ORDER BY column_name)
               AS cols
        FROM information_schema.columns
       WHERE table_schema = :'schema' AND table_name = t.tbl
    ) c
) parts
\gexec
