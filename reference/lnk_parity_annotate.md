# Annotate a parity rollup against the bcfp divergence taxonomy

Joins each row of a parity rollup (from
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md)
or the `data-raw/compare_bcfishpass_wsg.R` wrapper) to the first
taxonomy entry whose `wsg`, `species`, `metric`, `pattern`, and
(optional) `diff_range` all match. Unmatched rows with
`|diff_pct| >= tolerance` are tagged
`class = UNEXPLAINED, status = NEEDS_INVESTIGATION`; smaller residuals
become `class = WITHIN_TOLERANCE, status = CLOSED`. Rows with `NA`
diff_pct (NA ref value, divide-by-zero) become `class = NOT_APPLICABLE`.

## Usage

``` r
lnk_parity_annotate(rollup, taxonomy, to = NULL, tolerance = 2)
```

## Arguments

- rollup:

  A tibble with columns `wsg`, `species`, `habitat_type`, `link_value`,
  `diff_pct`, plus one of `ref_value` (library shape) or
  `bcfishpass_value` (data-raw wrapper shape). Both shapes pass through
  — the function normalizes internally.

- taxonomy:

  Path to a YAML file or a parsed list (from
  [`yaml::read_yaml()`](https://yaml.r-lib.org/reference/read_yaml.html)).
  When a path, the function reads it. When a parsed list, it must have
  an `entries` element holding the per-pattern records.

- to:

  Optional character path. When set, writes the annotated tibble to a
  CSV and returns it invisibly.

- tolerance:

  Numeric. Rows with `|diff_pct| < tolerance` and no taxonomy match are
  tagged `WITHIN_TOLERANCE` instead of `UNEXPLAINED`. Default `2`
  (matching the acceptance bar in \#162).

## Value

A tibble extending `rollup` with annotation columns `taxonomy_id`,
`class`, `mechanism`, `status`, `refs`. `refs` is a semicolon-collapsed
string for CSV-friendliness.

## Details

First-match-wins: taxonomy entries are evaluated in the order they
appear in the YAML file. Put the most specific entries first.

## See also

[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md)

## Examples

``` r
if (FALSE) { # \dontrun{
rollup <- readRDS("data-raw/logs/provincial_parity/ADMS.rds")
annotated <- lnk_parity_annotate(
  rollup,
  taxonomy = "research/bcfp_divergence_taxonomy.yml",
  to = "data-raw/logs/provincial_parity/ADMS_annotated.csv"
)

# Acceptance check
unexplained <- annotated[annotated$class == "UNEXPLAINED" &
                          abs(annotated$diff_pct) >= 2, ]
stopifnot(nrow(unexplained) == 0L)
} # }
```
