# Match crossing records across multiple data systems

Link crossing records from different sources using network position
(blue_line_key + downstream_route_measure) within a distance tolerance.
This is the generic matcher —
[`lnk_match_pscis()`](https://newgraphenvironment.github.io/link/reference/lnk_match_pscis.md)
and
[`lnk_match_moti()`](https://newgraphenvironment.github.io/link/reference/lnk_match_moti.md)
are convenience wrappers with BC defaults.

## Usage

``` r
lnk_match_sources(
  conn,
  sources,
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

  :   (optional) Raw SQL filter predicate. Developer API only — must not
      contain user input. Applied within a subquery so column names are
      unambiguous.

  col_blk

  :   (optional) Override the network key column for this source.

  col_measure

  :   (optional) Override the measure column for this source.

- col_blk:

  Character. Default network key column name across sources. Default
  `"blue_line_key"`.

- col_measure:

  Character. Default measure column name across sources. Default
  `"downstream_route_measure"`.

- distance:

  Numeric. Maximum network distance (metres) for a match. Records
  further apart are not matched.

- to:

  Character. Output table name for matched pairs.

- overwrite:

  Logical. Overwrite output table if it exists.

- verbose:

  Logical. Report match counts per source pair.

## Value

The output table name (invisibly). The table contains columns:
`source_a`, `id_a`, `source_b`, `id_b`, `distance_m`.

## Details

**N-way matching:** not limited to two sources. Three sources produce
three pairwise comparisons. Each pair is matched independently.

**Network-first:** matches on linear referencing position
(blue_line_key + downstream_route_measure). Records on the same stream
(same blue_line_key) within `distance` metres are matched.

**System-agnostic:** each source declares its own ID column and
optionally its own network position column names. Works for any
jurisdiction's crossing data.

## Examples

``` r
# --- What matching solves ---
# PSCIS assessments have field measurements (outlet drop, culvert slope).
# Modelled crossings have network position (blue_line_key, measure).
# Matching links the measurements to the network so you can score.

if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Two-source match: PSCIS assessments to modelled crossings
lnk_match_sources(conn,
  sources = list(
    list(table = "whse_fish.pscis_assessment_svw",
         col_id = "stream_crossing_id"),
    list(table = "bcfishpass.modelled_stream_crossings",
         col_id = "modelled_crossing_id")),
  to = "working.matched_crossings")
# Matched 4,231 pairs within 100m on the same stream.
# Source A: whse_fish.pscis_assessment_svw (stream_crossing_id)
# Source B: bcfishpass.modelled_stream_crossings (modelled_crossing_id)

# Three-way match including MOTI
lnk_match_sources(conn,
  sources = list(
    list(table = "whse_fish.pscis_assessment_svw",
         col_id = "stream_crossing_id"),
    list(table = "bcfishpass.modelled_stream_crossings",
         col_id = "modelled_crossing_id"),
    list(table = "working.moti_culverts",
         col_id = "chris_culvert_id")),
  distance = 150,
  to = "working.matched_all")
# Three pairwise comparisons, wider tolerance for MOTI GPS.

# Filtered match — only assessed crossings in a watershed
lnk_match_sources(conn,
  sources = list(
    list(table = "whse_fish.pscis_assessment_svw",
         col_id = "stream_crossing_id",
         where = "watershed_group_code = 'BULK'"),
    list(table = "bcfishpass.modelled_stream_crossings",
         col_id = "modelled_crossing_id",
         where = "watershed_group_code = 'BULK'")),
  to = "working.matched_bulk")
} # }
```
