# Load configurable severity scoring thresholds

Build a named list of severity thresholds for crossing scoring. Ships
sensible BC fish passage defaults. Override via CSV or inline arguments
for project-specific tuning.

## Usage

``` r
lnk_thresholds(csv = NULL, high = NULL, moderate = NULL, low = NULL)
```

## Arguments

- csv:

  Path to a CSV file with columns `severity`, `metric`, `value`. When
  provided, CSV values override in-code defaults. Use
  `system.file("extdata", "thresholds_default.csv", package = "link")`
  to see the expected format.

- high:

  Named list of metric thresholds for high severity. Merged with CSV
  values (inline wins on conflict).

- moderate:

  Named list of metric thresholds for moderate severity.

- low:

  Named list of metric thresholds for low severity.

## Value

A named list with elements `high`, `moderate`, `low`, each containing a
named list of metric thresholds (numeric values keyed by metric name).

## Details

Thresholds control how
[`lnk_score_severity()`](https://newgraphenvironment.github.io/link/reference/lnk_score_severity.md)
classifies crossings. The default values reflect BC provincial fish
passage assessment criteria:

- High severity:

  outlet_drop \>= 0.6m or slope_length \>= 120 — impassable to most
  species at most flows

- Moderate severity:

  outlet_drop \>= 0.3m or slope_length \>= 60 — flow-dependent,
  potentially passable at migration flows

- Low severity:

  everything else with a crossing present

**System-agnostic:** metric names are user-defined strings, not
hardcoded to any provincial data system. A New Zealand user might define
`high = list(perch_height = 0.5, pipe_gradient = 0.05)`.

**Merge order:** code defaults \< CSV values \< inline arguments. This
lets you ship a project CSV but still tweak one threshold inline.

## Examples

``` r
# Default BC thresholds — zero config
th <- lnk_thresholds()
th$high$outlet_drop
#> [1] 0.6
# [1] 0.6

# Override from bundled CSV (same result, shows the format)
csv_path <- system.file("extdata", "thresholds_default.csv", package = "link")
th_csv <- lnk_thresholds(csv = csv_path)
identical(th, th_csv)
#> [1] TRUE

# Project-specific: bull trout tolerate higher drops
th_bt <- lnk_thresholds(high = list(outlet_drop = 0.8))
th_bt$high$outlet_drop
#> [1] 0.8
# [1] 0.8 — inline override wins

# How thresholds plug into scoring (the integration point)
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
lnk_score_severity(conn, "working.crossings",
  thresholds = lnk_thresholds(high = list(outlet_drop = 0.8)))
} # }
```
