# Does the installed 'fresh' provide what the pipeline calls?

`link` calls `fresh::` in a dozen places with no
[`requireNamespace()`](https://rdrr.io/r/base/ns-load.html) guard,
including a default argument on an exported function
([`lnk_wsg_downstream_check()`](https://newgraphenvironment.github.io/link/reference/lnk_wsg_downstream_check.md),
whose `outlets` defaults to
[`fresh::frs_wsg_outlets()`](https://rdrr.io/pkg/fresh/man/frs_wsg_outlets.html)).
A `fresh` that is merely *present* is therefore not enough — it has to
export the symbols.

## Usage

``` r
lnk_preflight_fresh(
  required = .lnk_fresh_required(),
  required_internal = .lnk_fresh_required_internal(),
  min_version = .lnk_fresh_floor(),
  quiet = FALSE
)
```

## Arguments

- required:

  Character vector of `fresh` exports the pipeline cannot run without.
  Defaults to the curated list in `.lnk_fresh_required()`.

- required_internal:

  Character vector of non-exported `fresh` objects reached via
  [`utils::getFromNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html).

- min_version:

  Minimum acceptable `fresh` version. Defaults to the floor declared in
  link's own `DESCRIPTION`, so the pin lives in one place.

- quiet:

  Suppress the human-readable report. The report is the point on a
  cypher, where the log is all the operator gets.

## Value

Invisibly, a list with `ok`, `version`, `version_ok`, `missing`,
`missing_internal` and `message`.

## Details

On the cypher droplets the installed version is whatever was baked into
the machine image, and the failure mode is silent: `wsg_run_one.R`
catches the missing-symbol error and `quit(status = 1)`s, the bucket
loop logs `[WARN]` and continues, the host exits 0, and the watershed
groups are simply absent from the persist. Nothing downstream can tell
"not modelled" from "modelled empty". That is the 2026-08 failure this
exists to stop (link#246).

Symbols are checked rather than a version string because a version is a
proxy that fails in both directions: it can read `0.33.0` on a partial
install or against a shadowing library path, and it can read "wrong"
while every needed symbol is present. Loading the namespace also
exercises `fresh`'s own `Imports` resolution, which reading a
`DESCRIPTION` off disk does not.

## See also

Other preflight:
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md),
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md),
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)

## Examples

``` r
res <- lnk_preflight_fresh(quiet = TRUE)
res$ok
#> [1] TRUE
res$version
#> [1] "0.33.0"

# A symbol fresh does not export fails, and is named in the report:
bad <- lnk_preflight_fresh(required = "frs_not_a_real_export", quiet = TRUE)
bad$missing
#> [1] "frs_not_a_real_export"
```
