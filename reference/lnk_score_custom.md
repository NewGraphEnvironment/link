# Apply user-defined scoring rules

Compute a custom priority score beyond standard severity classification.
For project-specific metrics like cost-effectiveness, species-weighted
priority, or multi-criteria ranking.

## Usage

``` r
lnk_score_custom(
  conn,
  crossings,
  rules,
  col_id = "modelled_crossing_id",
  col_score = "priority_score",
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

- rules:

  Named list of scoring rule specs. Each rule is a named list with:

  col

  :   Column to evaluate (required).

  weight

  :   Numeric weight (default 1).

  direction

  :   `"higher"` (default) or `"lower"` is better.

  sql

  :   Optional raw SQL expression instead of `col`. Developer API — must
      not contain user input.

- col_id:

  Character. Primary key column in the crossings table. Used for joining
  scores back to rows.

- col_score:

  Character. Name of output score column.

- to:

  Character. If `NULL`, updates in-place. Otherwise writes to new table.

- verbose:

  Logical. Report score distribution summary.

## Value

The table name (invisibly).

## Details

**Composable:** severity from
[`lnk_score_severity()`](https://newgraphenvironment.github.io/link/reference/lnk_score_severity.md)
is one input. Upstream habitat value (from
[`lnk_habitat_upstream()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_upstream.md))
is another. Custom scoring combines them into a single priority number.

**Weighted rank:** each rule produces a rank (1 = best), multiplied by
its weight, summed into a composite score. Lower composite = higher
priority. This avoids unit-mixing problems (you can't add metres of
habitat to severity categories, but you can add their ranks).

## Examples

``` r
# --- "Which 10 crossings should we fix first?" ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Score severity first
lnk_score_severity(conn, "working.crossings")

# Then add upstream habitat (from fresh output)
lnk_habitat_upstream(conn, "working.crossings", "fresh.habitat")

# Now rank: severity weight 2x, habitat weight 3x
lnk_score_custom(conn, "working.crossings",
  rules = list(
    severity = list(col = "severity", weight = 2,
      sql = "CASE severity
             WHEN 'high' THEN 3
             WHEN 'moderate' THEN 2
             ELSE 1 END"),
    habitat  = list(col = "spawning_km", weight = 3)))
# Priority score distribution:
#   min: 5.0  median: 12.3  max: 42.7
#
# Lower score = higher priority for remediation.
# Top 10: SELECT * FROM working.crossings
#         ORDER BY priority_score LIMIT 10
} # }
```
