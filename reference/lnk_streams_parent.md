# Join each full segment to the minimal segment it was cut from

Builds `<schema>.streams_parent` for one watershed group: for every
segment of the full network (`schema`, for example `fresh_default`) the
segment of the minimal network (`schema_minimal`, for example
`fresh_default_minimal`) it lies in, with that segment's gradient and
length. A habitat rule tuned on the minimal network can then read the
gradient it was tuned on at each full segment.

## Usage

``` r
lnk_streams_parent(
  conn,
  wsg,
  schema,
  schema_minimal,
  tol_m = 1.01,
  sliver_m = 0.01,
  cut_floor_m = 0.5,
  run_id_full = NULL,
  run_id_minimal = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the database holding both persist schemas.

- wsg:

  Character. One watershed group code.

- schema:

  Character. The full network's persist schema; the table is written
  there.

- schema_minimal:

  Character. The minimal network's persist schema.

- tol_m:

  Numeric. How far, in metres, a minimal cut may lie from the nearest
  full cut.

- sliver_m:

  Numeric. Overlap pieces shorter than this, in metres, are dropped.

- cut_floor_m:

  Numeric. A minimal segment starting above this measure is a cut; one
  starting at or below it starts its line.

- run_id_full, run_id_minimal:

  Character or `NULL`. When given, the `log.run_id` of the build a
  caller judged on each side; the join is refused if the group's newest
  build is another one (it was re-modelled after the judgement).

## Value

A one-row data frame, invisibly: `wsg`, `n_full`, `n_minimal`, `km`,
`n_straddle` (full segments with `straddle_m` of `sliver_m` or more),
`km_straddle`, `max_straddle_m`.

## Details

Segments are matched by measure overlap on each `blue_line_key`, never
by `id_segment` (each build numbers its own). Pieces shorter than
`sliver_m` are dropped (an FWA segment's upstream measure can overshoot
the next one's start by a few millimetres), and each full segment takes
the minimal segment it overlaps most. The join is refused unless every
minimal cut above `cut_floor_m` on its line has a full cut within
`tol_m` of it, so a full segment straddles a minimal cut by at most
about `tol_m`; the full build skips a cut within 1 m of an existing end.
It is also refused when the pieces do not cover both networks' km, or
when a full segment would get no row.

The group's rows are replaced in one transaction, so a refusal leaves
its earlier rows in place. Nothing on the modelling path reads or writes
the table: a re-model of either network leaves its rows behind, and
`run_id_full`, `run_id_minimal` and `overlap_m + straddle_m` (the full
segment's length) are what tell a stale row. Whether the two builds ran
the same modelling code is judged by the caller
(`data-raw/streams_parent_build.R`).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
lnk_streams_parent(conn, "BULK", schema = "fresh_default",
                   schema_minimal = "fresh_default_minimal")
DBI::dbGetQuery(conn, "
  SELECT s.id_segment, s.gradient, p.gradient_minimal, p.straddle_m
    FROM fresh_default.streams s
    JOIN fresh_default.streams_parent p USING (id_segment, watershed_group_code)
   WHERE s.watershed_group_code = 'BULK' LIMIT 5")
} # }
```
