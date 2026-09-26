# Findings — Region-scoped DV→BT observation pooling (#290)

## Issue context

**If we do it:** whether a DV record counts as BT evidence is decided per region, sub-region or WSG, in bundle CSVs that record why, when and from what source. **If we never do:** DV is pooled with BT wherever BT is present. That rule is hard-coded in three places, and it is least defensible in exactly the places where DV and BT differ.

Split out of #236 (question 1, narrowed to observation evidence). **#284 step 5 is parked until this lands**, because its BT evidence is defined by this rule.

## Problem

DV→BT pooling is a biological position, but it lives in code, with one global scope:

- `R/lnk_habitat_validate.R:202`: `species_obs = list(BT = c("BT", "DV"))`, the default.
- `data-raw/query_habitat_thresholds_obs.R:79-87`: `CASE WHEN species_code = 'DV' THEN 'BT'`, gated only on BT presence in the WSG.
- `inst/extdata/configs/default/parameters_fresh.csv`: `observation_species = BT;DV` for the BT access override. This one is **out of scope here** and stays with #236, which needs multi-rule overrides. It should consume the same table when that lands.

The rule matters for #284. BT `rear_gradient_max` 0.1249 vs 0.1349 in `default_tuned` is exactly BT-only vs BT+DV pooled, and in BULK and MORR the "BT" evidence is ~90 % DV records (442 DV / 40 BT, 344 DV / 49 BT, raw A/B locations).

The operator's position (2026-09-26): pool in named regions only, and build up the state of knowledge over time in CSVs.

## Proposed Solution

Two bundle files, declared under `files:` so they are logged in `<schema>.log_*` and enter `config_hash`.

**1. `wsg_regions.csv`**, one row per WSG (246): `watershed_group_code, subregion, region`.

`region` is generated from the first segment of each group's **outlet** `wscode_ltree` (fresh@v0.33.0 `inst/extdata/wsg_outlet.csv`). Reading it at the outlet matters because some groups straddle codes: LFRA touches both 100 and 900. Measured on local fwapg:

| code | region | e.g. |
|---|---|---|
| 100 | Fraser | LFRA, UNTH, LNTH |
| 200 | Mackenzie | PARS, FINA, LIAR |
| 300 | Columbia | ELKR, KOTL, BULL |
| 400 | Skeena | BULK, MORR |

The 500–800 and 9xx codes are northern rivers and the coast; names get confirmed when the generator runs. `subregion` is hand-curated, starting with Kootenay under Columbia. The generator is a `data-raw/` script.

**2. `species_pooling.csv`**, the tracker. Columns: `species_code, species_obs, scope_level, scope, pool, confidence, rationale, source, verified, issue`.

- `scope_level` is `region`, `subregion` or `wsg`.
- Resolution: **the most specific row wins, and anything unlisted is not pooled.** A WSG row overrides its sub-region, which overrides its region; a WSG with no applicable row keeps DV separate.
- Knowledge accrues as dated, sourced rows. Git history of the file is the record.
- Seed rows: `BT, DV, region, {Fraser, Mackenzie, Skeena, Columbia}, pool = yes` and `BT, DV, subregion, Kootenay, pool = yes`. Source: operator call 2026-09-26 (inland DV are bull trout recorded under the other name). The coast and the north are unlisted.

`default` declares both files. `bcfishpass` declares neither: it does not pool, since it is the parity reference.

## Tasks

- [ ] Generator for `wsg_regions.csv`: region from the outlet code, sub-region from a small curated list; commit the output
- [ ] Seed `species_pooling.csv`; add both to `default`'s `files:` and to the config dictionaries
- [ ] One resolver, e.g. `lnk_species_pooling(cfg, loaded, aoi)` → the per-WSG `species_obs` list. Species-agnostic: it knows nothing about BT or DV
- [ ] `lnk_habitat_validate()` and `data-raw/habitat_validate.R` take `species_obs` from the resolver when the bundle declares the tracker
- [ ] `data-raw/query_habitat_thresholds_obs.R` pools through the resolver instead of the hard-coded `CASE`
- [ ] Re-run #284 step 1 under the regional rule; record how far the BT P95 and the verdicts move in `research/habitat_thresholds.md`, and in `default_tuned` if a value changes
- [ ] Tests: resolution precedence (WSG > sub-region > region > unlisted), unlisted means not pooled, and a bundle without the files keeps today's behaviour

Out of scope: the access override's `observation_species` (#236), and DV as a modelled species with its own thresholds (#236, fresh).

Relates to #236, #284, #283, #189



## Errors Encountered

| Error | Resolution |
|-------|------------|
