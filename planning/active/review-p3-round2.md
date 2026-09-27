# Review — #290 phase 3, round 2 (staged diff)

Scope: the round-1 fixes plus the rest of the staged diff (R/lnk_habitat_validate.R,
data-raw/habitat_validate.R, data-raw/query_habitat_thresholds_obs.R, tests).
Test file `test-lnk_habitat_validate.R` run against docker fwapg with NOT_CRAN=true:
113 pass / 0 fail / 0 skip.

## Findings

- **[fragile]** data-raw/query_habitat_thresholds_obs.R:112-127 (`presence_cols()`):
  the round-1 presence-equality assert **drops the key it sorts on**.
  `p[] <- lapply(p, ...)` turns `watershed_group_code` into a logical too, so the code
  removes the column, and the tables are compared **by row position** after sorting. So
  two presence tables with the same row count and the same CH/BT flag pattern in sort
  order compare `identical()` even when their WSG codes differ. That is the named
  mechanism, one axis over from the fix: the flags are checked but the key is not.
  `lnk_species_pooling(loaded, aoi = presence$watershed_group_code, ...)` then finds no
  pooling-presence row for the cfg WSG. It returns nothing for that WSG, so its DV
  records get `dv_ok = FALSE` and are dropped at ledger step 3. Nothing fails.

  Repro (scratch copy, nothing in the repo edited):
  `scratchpad/probe_cols.R`. Take the default bundle's loaded presence and change
  `MORR` to `MORQ`, which sorts into the same slot. Then:
  - `presence_cols` still reports `identical: TRUE`.
  - The pooling table has 0 MORR rows, against 3 from the clean table.
  - The same happens for `MORS`.

  Fix: compare the key too. Convert only the species columns and keep
  `toupper(trimws(watershed_group_code))` as a column. Or key the comparison with
  `match()` over cfg's WSGs, the way the driver's `presence_flags(p, w)` already does.
  The driver's version is keyed, so it does not have this hole.

## Checked and clean

- Driver `presence_flags()`: keyed on `w` via `match()`. A WSG missing from one table
  gives NA -> FALSE, and that differs from a "t" in the other table, so it stops. A WSG
  missing from both is FALSE on both sides. This matches `lnk_species_pooling()` and
  `.lnk_hv_spec()`, which both return nothing for it. A species column missing from one
  table fails loudly ("undefined columns"). An all-empty column read by read.csv
  (logical NA) reads as FALSE, as it does in `.lnk_wsg_species_present()`.
  default and bcfishpass differ only in `gr` (LARL), so `--bundles=default:…,bcfishpass:…`
  with CH,BT passes, as probed.
- Query one-target guard and model-into-model guard: both run on the non-self rows.
  A group row such as `CH <- CHAR` trips the duplicate guard or the model-species guard.
  The `LEFT JOIN t_pool` cannot fan out once `(wsg, obs_species)` is unique. `sprintf` has
  the `%%` escaped on the only LIKE, and the positional `%1$s`/`%2$s` are correct.
- Zero pooled rows: both stamps say "none". A zero-row `t_pool` writes and joins fine.
- `.lnk_hv_species_obs()`: the data-frame branch is tested before the list checks. A
  zero-row frame, a tibble or factor columns normalise correctly, and NA or empty codes
  are rejected before the `nzchar` test.
- `default_tuned` (extends) resolves `species_pooling` to the parent's file. `digest` is
  in DESCRIPTION.
- The `$` partial-match risk on `files$species_pooling` / `loaded$species_pooling`: no
  bundle has a key with that prefix.
