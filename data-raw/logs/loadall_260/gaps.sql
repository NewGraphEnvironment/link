-- gaps.sql — link#260: how long a slot of the 2026-10-23 pool sat between one job's
-- date_end and the next job's date_start. With 8 slots, the i-th start follows the
-- (i-8)-th end. The gap holds the next job's prologue, its lnk_stamp(), the previous
-- job's exit and the driver's 1 s slot poll; the tail after the last starts is not in it.
-- psql "$DATABASE_URL" -At -F$'\t' -f gaps.sql
WITH r AS (
  SELECT date_start, date_end FROM fresh_default.log_recompute
  WHERE run_uid = '20261023_074321-24d85e8c' AND date_end IS NOT NULL
    AND date_start < '2026-10-23 20:00+00'),
s AS (SELECT date_start, row_number() OVER (ORDER BY date_start) AS i FROM r),
e AS (SELECT date_end,   row_number() OVER (ORDER BY date_end)   AS j FROM r),
g AS (SELECT extract(epoch FROM s.date_start - e.date_end) AS gap
      FROM s JOIN e ON e.j = s.i - 8)
SELECT count(*)                                                                  AS gaps,
       round(percentile_cont(0.1) WITHIN GROUP (ORDER BY gap)::numeric, 2)        AS p10_s,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY gap)::numeric, 2)        AS median_s,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY gap)::numeric, 2)        AS p90_s,
       round(max(gap)::numeric, 2)                                                AS max_s,
       round(sum(gap)::numeric / 60, 1)                                           AS slot_min
FROM g;
