# Classify crossings by biological impact severity

Score crossings into severity levels (high/moderate/low) based on actual
crossing measurements rather than the binary BARRIER/PASSABLE provincial
classification. Thresholds are configurable per project, species, and
life stage via
[`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md).

## Usage

``` r
lnk_score_severity(
  conn,
  crossings,
  thresholds = lnk_thresholds(),
  col_drop = "outlet_drop",
  col_slope = "culvert_slope",
  col_length = "culvert_length_m",
  col_severity = "severity",
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

  Character. Schema-qualified crossings table (after overrides applied).

- thresholds:

  List. Output of
  [`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md).
  Named list with `high`, `moderate`, `low` severity specs.

- col_drop:

  Character. Column name for outlet drop measurement. Default
  `"outlet_drop"` matches PSCIS field names.

- col_slope:

  Character. Column name for culvert slope.

- col_length:

  Character. Column name for culvert length.

- col_severity:

  Character. Name of the output column written to the crossings table.

- to:

  Character. If `NULL` (default), updates `crossings` in-place. If
  specified, writes a scored copy to a new table.

- verbose:

  Logical. Report severity distribution.

## Value

The table name (invisibly) for piping.

## Details

**Beyond binary:** provincial `barrier_result` treats very different
crossings identically. A 1.2m outlet drop and a 0.3m drop with steep
slope are both "BARRIER" but have very different biological impact.

**Measurement-based:** uses actual culvert dimensions, not just the
assessment checkbox. Scoring logic evaluates outlet drop and slope \*
length (a composite metric for sustained velocity barriers).

**Column-agnostic:** `col_drop = "outlet_drop"` is the PSCIS default. A
New Zealand user might pass `col_drop = "perch_height"`. The scoring
logic is identical.

**Threshold-driven:** all cutoffs come from
[`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md)
— nothing is hardcoded in the function body.

## Scoring logic (default thresholds)

|              |                                                |                                      |
|--------------|------------------------------------------------|--------------------------------------|
| **Severity** | **Criteria**                                   | **Interpretation**                   |
| High         | outlet_drop \>= 0.6m OR slope x length \>= 120 | Impassable at most flows             |
| Moderate     | outlet_drop \>= 0.3m OR slope x length \>= 60  | Flow-dependent, potentially passable |
| Low          | everything else with a crossing present        | Likely passable for target species   |

## Examples

``` r
# --- What severity scoring reveals ---
# Two crossings both classified as "BARRIER" by the province:
#   Crossing A: outlet_drop = 1.2m  -> HIGH severity (impassable)
#   Crossing B: outlet_drop = 0.3m  -> MODERATE severity (flow-dependent)
# Same provincial classification, very different biological impact.
# Severity scoring tells you WHERE to invest remediation dollars.

# --- Score with default BC thresholds ---
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Apply overrides first, then score
lnk_override_apply(conn, "working.crossings",
  "working.overrides_modelled")
lnk_score_severity(conn, "working.crossings")
# Severity distribution:
#   high:     234  (impassable at most flows)
#   moderate: 891  (flow-dependent)
#   low:    2,103  (likely passable)
#
# Then produce break sources for fresh:
src <- lnk_break_source(conn, "working.crossings")
frs_habitat(conn, "BULK", break_sources = list(src))

# --- Custom thresholds for bull trout ---
# Bull trout are stronger swimmers — higher drop tolerance
lnk_score_severity(conn, "working.crossings",
  thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))

# --- Non-PSCIS data (column remapping) ---
lnk_score_severity(conn, "working.crossings",
  col_drop = "perch_height",
  col_slope = "pipe_gradient",
  col_length = "pipe_length_m")
} # }
```
