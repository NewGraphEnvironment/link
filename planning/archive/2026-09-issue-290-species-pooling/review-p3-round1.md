# Review — Phase 3 staged diff, round 1 (#290)

Scope: R/lnk_habitat_validate.R, tests/testthat/test-lnk_habitat_validate.R,
data-raw/habitat_validate.R, data-raw/query_habitat_thresholds_obs.R (context:
R/lnk_species_pooling.R). Validator test file run under NOT_CRAN=true against
local docker fwapg: FAIL 0 | PASS 113. No blocker found. Three findings, all
low severity: two are the "two lists agree on a key" mechanism, latent today,
and one is a stamp that can misreport.

## Findings

- **[fragile]** data-raw/query_habitat_thresholds_obs.R:94-101. The
  one-target guard runs *after* the self rows are dropped, so it only checks
  pooled rows against each other. Say a tracker row pools one model species
  into the other in some WSG (for example `CH <- BT`, or a group row that
  expands to it). The `(W, BT)` pair then appears once and the guard passes.
  But `coalesce(pl.species_code, o.species_code)` relabels every BT record in
  W as CH, so it silently stops being BT evidence. The validator counts such a
  record for both species, so the two consumers would disagree without
  saying so. The comment says the guard makes sure each record is assigned to
  one species, but it does not stop a record leaving its own species. This is
  latent: default's tracker pools only DV into BT, and the script's species
  are fixed at CH and BT. The fix is to also refuse any
  `pool$obs_species %in% species`.

- **[fragile]** data-raw/habitat_validate.R:216-235 and
  data-raw/query_habitat_thresholds_obs.R:87-93. The pooling table comes from
  the **pooling bundle's** `wsg_species_presence`. `lnk_species_pooling()`
  emits no row for a WSG where that bundle marks the model species absent.
  The consumer then filters on a **different** presence table: the scored
  bundle's in the validator, and `cfg` ("default") at step 4 in the query
  script. Suppose the scored bundle marks BT present in a WSG where the
  pooling bundle marks it absent. `.lnk_hv_spec()` then maps BT to itself
  only there, so DV is dropped with no error. In the driver, the
  same-observations assertion (line ~368) catches this only on *shared* WSGs.
  A WSG scored by one bundle only narrows silently. In the query script, with
  `--pooling=<other>`, those DV rows fall out at step 3 instead of step 4. It
  is latent today, because I measured the default and bcfishpass presence
  tables as identical (246 rows; bt, ch and dv differ in 0 WSGs). A cheap
  guard would assert that the pooling bundle's presence equals each scored
  bundle's (or `cfg`'s) for `species` over the aoi.

- **[fragile]** data-raw/habitat_validate.R:237-240 and
  data-raw/query_habitat_thresholds_obs.R:555-557. The stamp's rule list is
  built as `paste(unique(paste0(x$species_code, "<-", x$obs_species)),
  collapse = ", ")`. On zero pooled rows it returns `"<-"`, not `""`: the
  `paste()` zero-length trap, which I measured (it prints `[1] "<-"`). A
  tracker that pools nothing in the run's WSGs, such as a scratch bundle with
  every row `pool = no`, then stamps `0 WSG x species pairs pooled (<-)` in
  the driver and `pooling: X species_pooling.csv; <-` in the query script.
  The query script's stamp has no count beside it, so `<-` is all a reader
  sees. This is minor, but the stamp is the provenance record. Guard it with
  `if (nrow(pooled) == 0L) "none" else ...`.

## Checked and clean

- A data frame passes `is.list()` in the `stopifnot`. The data-frame branch
  in `.lnk_hv_species_obs()` runs first and returns before the list checks.
  The list-form checks moved there with the same logic, and zero-row data
  frames normalise without error.
- `c(list(...), args_pool)` keeps the data frame as a single `species_obs`
  argument, and an empty `args_pool` leaves the default in place.
- The mixed positional `%1$s` / `%2$s` placeholders and the `%%` escape in the
  query `sprintf` are correct, and no other `%` sits in that SQL string. The
  IN-lists are quoted with `dbQuoteString`. An empty `species` would give
  `IN ()`, which is a loud SQL error rather than a silent one.
- `t_pool` is written with RPostgres's default `row.names = FALSE`. A
  zero-row `pool` creates typed text columns, and the LEFT JOIN still works.
- `lnk_config(...)$files$species_pooling` resolves to default's file for
  `default_tuned`, which inherits it, so the sha256 in the stamp is taken over
  the right file.
- `--pooling=bcfishpass` (which has no tracker) and `--pooling=` (empty) both
  fail loud.
- Dropping the `'DV' -> 'BT'` `CASE` changes nothing downstream. Unpooled DV
  records now carry `species_code = 'DV'`, but they are removed at step 3
  (`dv_ok` FALSE) before any `species_code` test. `BT_spawn_dv` and
  `BT_rear_dv` select by `obs_species`.
