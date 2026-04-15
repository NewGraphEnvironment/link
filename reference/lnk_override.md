# Validate and apply overrides to a table

Check referential integrity (orphans, duplicates) then update matching
rows. Combines validation and application in one call.

## Usage

``` r
lnk_override(
  conn,
  crossings,
  overrides,
  col_id = "modelled_crossing_id",
  cols_update = NULL,
  cols_provenance = c("reviewer", "review_date", "reviewer_name", "source"),
  validate = TRUE,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Schema-qualified table to update.

- overrides:

  Character. Schema-qualified override table (output of
  [`lnk_load()`](https://newgraphenvironment.github.io/link/reference/lnk_load.md)).

- col_id:

  Character. Join column shared by both tables.

- cols_update:

  Character vector. Columns to copy from overrides to crossings. `NULL`
  (default) auto-detects: all columns in both tables excluding `col_id`
  and `cols_provenance`.

- cols_provenance:

  Character vector. Columns to exclude from auto-detection (provenance
  tracking, not data).

- validate:

  Logical. Run referential integrity check before applying. Reports
  orphans and duplicates. Default `TRUE`.

- verbose:

  Logical. Report validation results and update counts.

## Value

A list with `n_updated`, `cols_updated`, and if `validate = TRUE`,
`orphans`, `duplicates`, `valid_count`, `total_count`. Returned
invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Load corrections
lnk_load(conn,
  csv = "data/overrides/modelled_xings_fixes.csv",
  to  = "working.fixes",
  cols_id = "modelled_crossing_id")

# Validate and apply in one step
lnk_override(conn,
  crossings = "working.crossings",
  overrides = "working.fixes")
# Override validation: working.fixes vs working.crossings
#   Total overrides:  947
#   Valid (matched):  940
#   Orphans:            7
#   Duplicates:         0
# Updated 940 of 3597 crossings (barrier_status)
} # }
```
