# Validate override referential integrity

Check that override records reference real crossings and flag orphans,
duplicates, and conflicts. Optional step between
[`lnk_override_load()`](https://newgraphenvironment.github.io/link/reference/lnk_override_load.md)
and
[`lnk_override_apply()`](https://newgraphenvironment.github.io/link/reference/lnk_override_apply.md)
— recommended for production workflows where overrides accumulate across
field seasons.

## Usage

``` r
lnk_override_validate(
  conn,
  overrides,
  crossings,
  col_id = "modelled_crossing_id",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- overrides:

  Character. Schema-qualified override table.

- crossings:

  Character. Schema-qualified crossings table to validate against.

- col_id:

  Character. Join column (system-agnostic).

- verbose:

  Logical. Print a summary of findings.

## Value

A list with:

- orphans:

  Override IDs not found in crossings (GPS error? wrong watershed?
  crossing removed from model?)

- duplicates:

  Crossing IDs that appear more than once in overrides (conflicting
  corrections — which one wins?)

- valid_count:

  Number of overrides that will apply cleanly.

- total_count:

  Total override records.

## Details

**Non-blocking:** returns findings but does not error. The user decides
whether orphans are acceptable (they often are — crossings get removed
from models between versions).

**Why validate?** Override CSVs accumulate over years. Crossings get
renumbered, GPS coordinates get corrected, models get rebuilt. Without
validation, stale overrides silently fail to match and corrections are
lost.

## Examples

``` r
# --- Why validation matters ---
# You loaded 3 years of field reviews (1,200 overrides).
# The modelled crossings layer was rebuilt last month.
# How many overrides still point at valid crossings?
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

lnk_override_load(conn,
  csv = c("data/overrides/2023_field.csv",
          "data/overrides/2024_field.csv",
          "data/overrides/2025_field.csv"),
  to  = "working.overrides_all")

result <- lnk_override_validate(conn,
  overrides = "working.overrides_all",
  crossings = "working.crossings")
# Override validation: working.overrides_all vs working.crossings
#   Total overrides:  1,200
#   Valid (matched):  1,147
#   Orphans:             48  <-- crossings removed from model
#   Duplicates:           5  <-- same crossing corrected twice
#
# The 48 orphans are expected — the model was rebuilt.
# The 5 duplicates need manual review: which correction wins?

# Inspect the orphans
result$orphans
# [1] 5042 5108 5203 ...

# Inspect the duplicates
result$duplicates
# [1] 1004 1007 ...

# If satisfied, apply
lnk_override_apply(conn, "working.crossings",
  "working.overrides_all")
} # }
```
