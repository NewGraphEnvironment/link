# Match MOTI culverts to crossings

Link Ministry of Transportation culvert inventory records to modelled
crossings or matched crossings. This linkage does not currently exist in
provincial data systems — MOTI has condition and dimension data on
thousands of highway crossings that could inform severity scoring.

## Usage

``` r
lnk_match_moti(
  conn,
  crossings = "bcfishpass.modelled_stream_crossings",
  moti,
  col_id_cross = "modelled_crossing_id",
  col_id_moti = "chris_culvert_id",
  distance = 150,
  to = "working.matched_moti",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Crossings table to match against (can be the output of
  [`lnk_match_pscis()`](https://newgraphenvironment.github.io/link/reference/lnk_match_pscis.md)).

- moti:

  Character. MOTI culvert table. Must have network position columns.

- col_id_cross:

  Character. Crossing ID column in `crossings`.

- col_id_moti:

  Character. MOTI identifier column.

- distance:

  Numeric. Maximum network distance (metres). Wider default (150m)
  because MOTI GPS positions are road-centreline-derived, not
  stream-snapped.

- to:

  Character. Output table name.

- verbose:

  Logical. Report match statistics.

## Value

The output table name (invisibly).

## Details

**Why MOTI data matters:** MOTI records culvert dimensions, condition
ratings, and replacement history for highway crossings. Linking to PSCIS
adds fish passage assessment data. Together they inform severity scoring
with more complete information than either source alone.

**Wider distance tolerance:** MOTI GPS positions are derived from road
centreline measures, not stream-snapped coordinates. The default 150m
tolerance accounts for this offset.

## Examples

``` r
# --- Three-way linkage: PSCIS + modelled + MOTI ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Step 1: Match PSCIS to modelled
lnk_match_pscis(conn, to = "working.matched_pscis")

# Step 2: Match MOTI to the same modelled crossings
lnk_match_moti(conn,
  crossings = "bcfishpass.modelled_stream_crossings",
  moti = "working.moti_culverts",
  to = "working.matched_moti")
# Matched 1,847 MOTI culverts to modelled crossings within 150m
#
# MOTI records culvert dimensions and condition.
# PSCIS records fish passage assessment.
# Modelled crossings have network position.
# Together: complete picture for severity scoring.

# Step 3: Score with all available data
lnk_score_severity(conn, "working.crossings")
} # }
```
