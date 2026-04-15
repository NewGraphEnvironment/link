# Score crossings

Classify crossings by severity or rank them by weighted criteria.

## Usage

``` r
lnk_score(
  conn,
  crossings,
  method = c("severity", "rank"),
  thresholds = lnk_thresholds(),
  col_drop = "outlet_drop",
  col_slope = "culvert_slope",
  col_length = "culvert_length_m",
  col_severity = "severity",
  rules = NULL,
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

- method:

  Character. `"severity"` for biological impact classification
  (high/moderate/low), or `"rank"` for weighted multi-criteria ranking.

- thresholds:

  List. For `method = "severity"`. Output of
  [`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md).

- col_drop, col_slope, col_length:

  Character. Column names for `method = "severity"`. Defaults match
  PSCIS field names.

- col_severity:

  Character. Output column name for severity.

- rules:

  Named list. For `method = "rank"`. Each rule has `col` or `sql`,
  optional `weight` and `direction`.

- col_id:

  Character. Primary key for `method = "rank"`.

- col_score:

  Character. Output column name for rank score.

- to:

  Character. If `NULL`, updates in-place. Otherwise copies.

- verbose:

  Logical. Report distribution.

## Value

The table name (invisibly).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Severity classification
lnk_score(conn, "working.crossings", method = "severity")

# Custom thresholds
lnk_score(conn, "working.crossings", method = "severity",
  thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))

# Weighted ranking
lnk_score(conn, "working.crossings", method = "rank",
  rules = list(
    habitat = list(col = "spawning_km", weight = 3),
    severity = list(sql = "CASE severity
      WHEN 'high' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END",
      weight = 2)))
} # }
```
