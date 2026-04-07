# Load override CSVs into a database table

Read one or more correction CSVs, validate their structure, and write
them to a PostgreSQL table. This is step one of the override pipeline:
**load** -\>
[`lnk_override_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_override_validate.md)
-\>
[`lnk_override_apply()`](https://newgraphenvironment.github.io/link/reference/lnk_override_apply.md).

## Usage

``` r
lnk_override_load(
  conn,
  csv,
  to,
  cols_id = "modelled_crossing_id",
  cols_required = NULL,
  cols_provenance = c("reviewer", "review_date", "source"),
  overwrite = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- csv:

  Character. Path to a CSV file, or a vector of paths to load multiple
  files into the same table (e.g., one per field season).

- to:

  Character. Schema-qualified destination table name (e.g.,
  `"working.overrides_modelled"`).

- cols_id:

  Character. Column(s) used as crossing identifier. System-agnostic —
  could be `"stream_crossing_id"`, `"chris_culvert_id"`, or any ID your
  system uses.

- cols_required:

  Character vector. Columns that must exist in every CSV. Fails fast
  with an informative error naming the missing column and file.
  `cols_id` is always required and does not need to be repeated here.

- cols_provenance:

  Character vector. Provenance columns to track who reviewed what and
  when. Kept when present in the CSV, silently skipped when absent. Set
  to `NULL` to disable provenance tracking.

- overwrite:

  Logical. If `TRUE` (default), drop and recreate the table. If `FALSE`,
  append to an existing table.

## Value

The destination table name (invisibly), for piping into
[`lnk_override_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_override_validate.md)
or
[`lnk_override_apply()`](https://newgraphenvironment.github.io/link/reference/lnk_override_apply.md).

## Details

Override CSVs represent hand-reviewed crossing corrections accumulated
across field seasons and imagery review. Each row says "this crossing's
attribute should be changed to this value."

**Fail fast:** structure is validated before any data is written.
Missing required columns produce a clear error naming the column and
file path.

**Multi-file load:** pass a vector of CSV paths to combine overrides
from different sources (field seasons, watersheds, reviewers). The first
file creates the table; subsequent files append.

**Provenance is optional:** teams with mature QA processes track
`reviewer`, `review_date`, and `source`. New projects can start without
these columns and add them later.

## Examples

``` r
# --- What does an override CSV look like? ---
csv_path <- system.file("extdata", "overrides_example.csv", package = "link")
overrides <- read.csv(csv_path)
print(overrides)
#>   modelled_crossing_id barrier_result_code  reviewer review_date         source
#> 1                 1001            PASSABLE  J. Smith  2025-08-15 imagery review
#> 2                 1002             BARRIER  J. Smith  2025-08-15 imagery review
#> 3                 1003                NONE A. Irvine  2025-09-20    field visit
#> 4                 1004            PASSABLE A. Irvine  2025-09-20    field visit
#> 5                 1005             BARRIER  J. Smith  2025-10-01 imagery review
#   modelled_crossing_id barrier_result_code  reviewer review_date        source
# 1                 1001            PASSABLE  J. Smith  2025-08-15 imagery review
# 2                 1002             BARRIER  J. Smith  2025-08-15 imagery review
# 3                 1003                NONE A. Irvine  2025-09-20   field visit
# ...
# Each row corrects one crossing. The reviewer and date tell you
# who made the call and when — your audit trail.

# --- Load into database (the typical workflow) ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Single file — most common case
lnk_override_load(conn,
  csv  = "data/overrides/modelled_xings_fixes.csv",
  to   = "working.overrides_modelled",
  cols_required = c("barrier_result_code"))

# Multiple files from different field seasons
lnk_override_load(conn,
  csv  = c("data/overrides/2024_field.csv",
           "data/overrides/2025_field.csv"),
  to   = "working.overrides_modelled")

# Then validate and apply:
lnk_override_validate(conn, "working.overrides_modelled",
  "working.crossings")
lnk_override_apply(conn, "working.crossings",
  "working.overrides_modelled")
} # }
```
