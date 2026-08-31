# Verify downstream state before modelling a watershed group

link computes accessibility by reading the **already-persisted**
barriers of the watershed groups downstream of the focal one. Modelling
a WSG before its downstream neighbours writes `streams_access` /
`streams_mapping_code` marking segments accessible that are in fact
dammed off — and exits cleanly, so the wrong answer is indistinguishable
from a right one.

## Usage

``` r
lnk_wsg_downstream_check(
  conn,
  aoi,
  cfg,
  loaded,
  on_fail = c("error", "warn", "ignore"),
  override = NA_character_,
  outlets = fresh::frs_wsg_outlets()
)
```

## Arguments

- conn:

  DBI connection to the modelling database.

- aoi:

  Watershed group code.

- cfg:

  An `lnk_config`; supplies the persist schema.

- loaded:

  Output of
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md);
  supplies the CABD edit CSVs.

- on_fail:

  `"error"` (default), `"warn"`, or `"ignore"`. Use `"warn"` for
  multi-host runs where downstream groups are legitimately mid-flight on
  another host and a post-consolidate recompute settles access
  afterwards.

- override:

  Character justification. Non-empty proceeds despite failure and
  records the reason. A bare `TRUE` is rejected on purpose: the
  justification *is* the mechanism, and an override without one is the
  hole this is meant to close.

- outlets:

  Per-group outlet points; defaults to
  [`fresh::frs_wsg_outlets()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_outlets.html).

## Value

Invisibly, a list with `aoi`, `status`, `dams`, `wsgs_missing`, `note`
and `elapsed_s`.

## Details

This checks the precondition instead of asking the operator to assert
it: find the blocking dams on the focal WSG's downstream flow path, and
confirm each is already persisted as a barrier.

Three outcomes:

- **pass** — no unpersisted blocking dam downstream. The common case.

- **fail** — there are; stop and name them (or warn, per `on_fail`).

- **override** — proceed on a stated assumption, which is recorded in
  the run log (link#127) so
  [`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md)
  can later report that this network was built assuming those dams do
  not block.

## See also

Other wsg:
[`lnk_wsg_resolve()`](https://newgraphenvironment.github.io/link/reference/lnk_wsg_resolve.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

# Verify before a long run.
lnk_wsg_downstream_check(conn, "PARS", cfg, loaded)

# Multi-host: defer to the post-consolidate recompute, but record it.
lnk_wsg_downstream_check(conn, "PARS", cfg, loaded, on_fail = "warn")
} # }
```
