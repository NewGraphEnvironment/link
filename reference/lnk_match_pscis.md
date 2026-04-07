# Match PSCIS assessments to modelled crossings

Convenience wrapper around
[`lnk_match_sources()`](https://newgraphenvironment.github.io/link/reference/lnk_match_sources.md)
with BC PSCIS defaults. Optionally applies a hand-curated
cross-reference CSV first — these known matches take priority over
spatial matching.

## Usage

``` r
lnk_match_pscis(
  conn,
  crossings = "bcfishpass.modelled_stream_crossings",
  pscis = "whse_fish.pscis_assessment_svw",
  xref_csv = NULL,
  distance = 100,
  to = "working.matched_pscis",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Modelled crossings table.

- pscis:

  Character. PSCIS assessment table.

- xref_csv:

  Character. Optional path to a CSV of known PSCIS-to-modelled matches
  (GPS error corrections from field work). Must have columns
  `stream_crossing_id` and `modelled_crossing_id`. Applied first;
  remaining unmatched records go through spatial matching.

- distance:

  Numeric. Maximum network distance (metres) for spatial matching.

- to:

  Character. Output table name.

- verbose:

  Logical. Report match statistics.

## Value

The output table name (invisibly).

## Details

**Why matching matters:** PSCIS assessments have field measurements
(outlet drop, culvert slope, channel width). Modelled crossings have
precise network position (blue_line_key, downstream_route_measure).
Matching links the measurements to the network so
[`lnk_score_severity()`](https://newgraphenvironment.github.io/link/reference/lnk_score_severity.md)
can classify crossings using real data.

**xref CSV priority:** the most valuable part of this function.
Hand-curated matches from field work represent thousands of hours of GPS
correction. When provided, these override spatial matching — if a PSCIS
crossing is in the xref, it won't be re-matched spatially.

## Examples

``` r
# --- Zero-config for BC ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Default tables — just works
lnk_match_pscis(conn)
# Matched 4,231 pairs: PSCIS <-> modelled within 100m
#
# Now your crossings table has both stream_crossing_id AND
# modelled_crossing_id — the bridge between field data and network.

# With hand-curated corrections from field work
lnk_match_pscis(conn,
  xref_csv = "data/overrides/pscis_modelled_xref.csv")
# Applied 892 known matches from xref
# Matched 3,339 additional pairs spatially
# Total: 4,231 matches

# Then score using the linked measurements
lnk_score_severity(conn, "working.crossings")
} # }
```
