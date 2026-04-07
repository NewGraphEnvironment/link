# Compute upstream habitat per crossing

For each crossing, sum the upstream habitat accessible if the crossing
were remediated. This is the demand side of prioritization — severity
tells you how bad the barrier is, upstream habitat tells you what you'd
gain by fixing it.

## Usage

``` r
lnk_habitat_upstream(
  conn,
  crossings,
  habitat,
  col_id = "modelled_crossing_id",
  cols_sum = c(spawning_km = "spawning", rearing_km = "rearing"),
  col_blk = "blue_line_key",
  col_measure = "downstream_route_measure",
  col_length = "length_metre",
  to = NULL,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Schema-qualified crossings table.

- habitat:

  Character. Schema-qualified habitat table (output of
  `frs_habitat_classify()` or similar).

- col_id:

  Character. Crossing identifier column (system-agnostic).

- cols_sum:

  Named character vector. Names = output column names, values = habitat
  columns to sum. Default sums spawning and rearing kilometres.

- col_blk:

  Character. Network key column name.

- col_measure:

  Character. Network measure column name.

- col_length:

  Character. Habitat segment length column for summing.

- to:

  Character. If `NULL`, adds columns to crossings table. Otherwise
  writes to new table.

- verbose:

  Logical. Report summary statistics.

## Value

The table name (invisibly).

## Details

**The other half of prioritization:** severity alone doesn't tell you
where to invest. A high-severity barrier with 50m of upstream habitat is
lower priority than a moderate barrier with 15km of spawning habitat.

**Flexible aggregation:** `cols_sum` lets you sum any habitat metric —
not just spawning/rearing. Lake rearing hectares, wetland area, total
accessible length — whatever the habitat classification produced.

**Data flow:**

    link (score crossings) -> fresh (segment, classify) -> link (rollup)

link scores crossings. fresh segments the network and classifies
habitat. link reads fresh's output to compute per-crossing rollups.

## Examples

``` r
# --- "Two barriers are both high severity.
#      One blocks 0.3km of rearing habitat.
#      The other blocks 12km of spawning habitat for chinook.
#      Which do you fix first?" ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Score crossings
lnk_score_severity(conn, "working.crossings")

# Compute upstream habitat from fresh output
lnk_habitat_upstream(conn,
  crossings = "working.crossings",
  habitat = "fresh.streams_habitat")
# Added spawning_km, rearing_km to working.crossings
# Summary:
#   spawning_km: min=0.0, median=2.3, max=45.1
#   rearing_km:  min=0.0, median=5.7, max=89.2

# Now you have severity + habitat — the full picture
# ORDER BY severity DESC, spawning_km DESC
# to find high-severity barriers blocking the most habitat.

# --- Custom metrics ---
lnk_habitat_upstream(conn,
  crossings = "working.crossings",
  habitat = "fresh.streams_habitat",
  cols_sum = c(spawning_km = "spawning",
               rearing_km = "rearing",
               lake_ha = "lake_rearing"))
} # }
```
