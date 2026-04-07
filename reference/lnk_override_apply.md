# Apply overrides to a crossings table

Join loaded overrides onto a crossings table and update matching
columns. Step two (or three) of the override pipeline:
[`lnk_override_load()`](https://newgraphenvironment.github.io/link/reference/lnk_override_load.md)
-\>
[`lnk_override_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_override_validate.md)
-\> **apply**.

## Usage

``` r
lnk_override_apply(
  conn,
  crossings,
  overrides,
  col_id = "modelled_crossing_id",
  cols_update = NULL,
  cols_provenance = c("reviewer", "review_date", "source"),
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- crossings:

  Character. Schema-qualified crossings table to update (e.g.,
  `"working.crossings"`).

- overrides:

  Character. Schema-qualified override table (output of
  [`lnk_override_load()`](https://newgraphenvironment.github.io/link/reference/lnk_override_load.md)).

- col_id:

  Character. Join column — the crossing identifier shared by both
  tables. System-agnostic.

- cols_update:

  Character vector. Columns to copy from overrides to crossings. `NULL`
  (default) auto-detects: all columns in overrides that also exist in
  crossings, excluding `col_id` and provenance columns.

- cols_provenance:

  Character vector. Columns to exclude from auto-detection (they track
  who reviewed, not crossing attributes).

- verbose:

  Logical. Report how many rows were updated.

## Value

A list with `n_updated` (rows changed) and `cols_updated` (columns that
were updated), invisibly.

## Details

**Auto-detect mode:** when `cols_update = NULL`, the function finds
columns that exist in both the overrides and crossings tables (excluding
the join column and provenance columns) and updates those. This means if
your override CSV has `barrier_result_code` and your crossings table has
`barrier_result_code`, it just works — no configuration needed.

**Explicit mode:** set `cols_update = c("barrier_result_code")` when you
want precision about exactly which columns change.

**Idempotent:** running twice produces the same result.

## Examples

``` r
# --- The override pipeline: load, then apply ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Step 1: Load overrides
lnk_override_load(conn,
  csv = "data/overrides/modelled_xings_fixes.csv",
  to  = "working.overrides_modelled")

# Step 2: Apply — auto-detects which columns to update
result <- lnk_override_apply(conn,
  crossings = "working.crossings",
  overrides = "working.overrides_modelled")
# Updated 342 of 15,230 crossings (barrier_result_code)
#
# The verbose output tells you the magnitude of changes —
# essential for QA. 342 corrections from 3 years of field work.

# Step 3: Score the corrected crossings
lnk_score_severity(conn, "working.crossings")
# Severity scores now reflect field-verified barrier status,
# not just the raw modelled data.

# --- Explicit column selection ---
lnk_override_apply(conn,
  crossings   = "working.crossings",
  overrides   = "working.overrides_modelled",
  cols_update = c("barrier_result_code"))
# Only updates barrier_result_code, even if the override table
# has other columns that match.
} # }
```
