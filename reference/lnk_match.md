# Match crossing records across data systems

Link crossing records from different sources using network position
(blue_line_key + downstream_route_measure) within a distance tolerance.
Bidirectional 1:1 dedup ensures each record matches at most once on each
side.

## Usage

``` r
lnk_match(
  conn,
  sources,
  xref_csv = NULL,
  col_blk = "blue_line_key",
  col_measure = "downstream_route_measure",
  distance = 100,
  to = "working.matched_crossings",
  overwrite = TRUE,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- sources:

  List of source specs. Each spec is a named list with:

  table

  :   (required) Schema-qualified table name.

  col_id

  :   (required) The ID column for this source.

  where

  :   (optional) Raw SQL filter. Developer API only — applied within a
      subquery.

  col_blk

  :   (optional) Override network key column.

  col_measure

  :   (optional) Override measure column.

- xref_csv:

  Character. Optional path to a CSV of known matches. Must have two
  columns matching the `col_id` of the first two sources. Applied first
  — matched IDs are excluded from spatial matching.

- col_blk:

  Character. Default network key column.

- col_measure:

  Character. Default measure column.

- distance:

  Numeric. Maximum network distance (metres) for a match.

- to:

  Character. Output table name.

- overwrite:

  Logical. Overwrite output table if it exists.

- verbose:

  Logical. Report match counts.

## Value

The output table name (invisibly). The table contains columns:
`source_a`, `id_a`, `source_b`, `id_b`, `distance_m`.

## Details

**N-way matching:** two or more sources produce pairwise comparisons.

**1:1 dedup:** two-pass DISTINCT ON keeps only the closest match per
record on both sides. No many-to-many inflation.

**xref priority:** when `xref_csv` is provided, those known matches are
applied first (distance = 0). Already-matched IDs are excluded from
spatial matching.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Two-source match
lnk_match(conn,
  sources = list(
    list(table = "whse_fish.pscis_assessment_svw",
         col_id = "stream_crossing_id"),
    list(table = "bcfishpass.modelled_stream_crossings",
         col_id = "modelled_crossing_id")),
  to = "working.matched_crossings")

# With hand-curated xref corrections
lnk_match(conn,
  sources = list(
    list(table = "working.pscis", col_id = "stream_crossing_id"),
    list(table = "working.crossings", col_id = "modelled_crossing_id")),
  xref_csv = "data/overrides/pscis_modelled_xref.csv",
  to = "working.matched")
} # }
```
