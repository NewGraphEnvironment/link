-- span.sql — link#260: the 2026-10-23 recompute pool as fresh_default.log_recompute
-- recorded it. date_start is written after the job prologue, so the span is
-- first job's work start to last job's end, and the sum leaves every prologue out.
-- psql "$DATABASE_URL" -At -F$'\t' -f span.sql
SELECT count(*)                                                     AS jobs,
       min(date_start)                                              AS first_start,
       max(date_end)                                                AS last_end,
       round(extract(epoch FROM max(date_end) - min(date_start)) / 60, 1) AS span_min,
       round(sum(extract(epoch FROM date_end - date_start)) / 60, 1)      AS job_min_sum,
       round(max(extract(epoch FROM date_end - date_start)) / 60, 2)      AS longest_min
FROM fresh_default.log_recompute
WHERE run_uid = '20261023_074321-24d85e8c'
  AND date_end IS NOT NULL
  AND date_start < '2026-10-23 20:00+00';  -- the pool; OKAN's later finish is not in it
