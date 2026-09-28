# Task: Region-scoped DV→BT observation pooling, tracked in bundle CSVs (#290)

DV→BT pooling is a biological position, but it lives in code, with one global scope:

- `R/lnk_habitat_validate.R:202`: `species_obs = list(BT = c("BT", "DV"))`, the default.
- `data-raw/query_habitat_thresholds_obs.R:79-87`: `CASE WHEN species_code = 'DV' THEN 'BT'`, gated only on BT presence in the WSG.
- `inst/extdata/configs/default/parameters_fresh.csv`: `observation_species = BT;DV` for the BT access override. This one is **out of scope here** and stays with #236, which needs multi-rule overrides. It should consume the same table when that lands.

The rule matters for #284. BT `rear_gradient_max` 0.1249 vs 0.1349 in `default_tuned` is exactly BT-only vs BT+DV pooled, and in BULK and MORR the "BT" evidence is ~90 % DV records (442 DV / 40 BT, 344 DV / 49 BT, raw A/B locations).

The operator's position (2026-09-26): pool in named regions only, and build up the state of knowledge over time in CSVs.

## Plan context

DV→BT pooling is a biological position, but today it is hard-coded with one global scope: "DV counts as BT wherever BT is present". It appears in two places:

- the default of `lnk_habitat_validate(species_obs = list(BT = c("BT","DV")))` (`R/lnk_habitat_validate.R:202`);
- a `CASE` in `data-raw/query_habitat_thresholds_obs.R:79-87`.

The operator's position (2026-09-26) is to pool only in named regions and build up the state of knowledge over time in CSVs. #284 step 5 is parked on this.

What exploration found:

- **Region can be derived.** The first segment of each group's outlet `wscode_ltree` (fresh `inst/extdata/wsg_outlet.csv`) gives 18 codes over 246 WSGs:
  - 100 Fraser (68), 200 Mackenzie (65), 300 Columbia (17), 400 Skeena (12), 500 Nass (7), 600 Stikine (16), 700 Taku (4), 800 Yukon (8);
  - 900–990 are coastal and cross-border codes.
  - `query_habitat_thresholds_obs.R` already uses `split_part(wscode,'.',1) AS region` at segment level.
  - The Kootenay River mainstem is `300.625474`, so a sub-region is just a wscode prefix.
- **The validator already works per WSG.** It builds a per-WSG pooling table internally (`.lnk_hv_spec()`, `R/lnk_habitat_validate.R:357`, columns `watershed_group_code, species_code, obs_species`). So the resolver can emit exactly that shape, and the change inside the validator is small.
- **#284's numbers should not move.** All 55 `fresh_default` WSGs behind the #284 BT evidence are in the four regions being seeded as pooled (Fraser 23, Mackenzie 20, Skeena 9, Columbia 3). The step-1 re-run is expected to be byte-identical: a check, not a change. The new #284 pilot WSGs are also all in pooled regions.
- **The driver compares on shared observations.** `data-raw/habitat_validate.R:321-328` asserts both bundles retained the same observations. So pooling has to be resolved once and applied to both bundles, not taken from each bundle separately.

## Refinement (operator, 2026-09-26, mid-plan): pooling is abstract

"We want to be able to pool to the salmon level if we want. Which species should not matter. Just an abstract tool."

- **Groups are data.** `inst/extdata/configs/default/species_groups.csv` has columns `group_code, species_code`. It is seeded with `SALMON` (CH, CM, CO, PK, SK) and `CHAR` (BT, DV), declared under `files:`, and given a dictionary.
- **Either side of a row can be a group.** In `species_pooling.csv`, both `species_code` (the target) and `species_obs` (the evidence) accept a species code or a group code, and the resolver expands both.
- **Precedence**, in order:
  1. scope specificity (wsg > subregion > region);
  2. then taxon specificity (a row naming both sides as species beats a row naming a group);
  3. any tie left with a different `pool` errors.
- **The resolver contains no species or group literal.** Tests use synthetic codes (`AAA`, `BBB`, group `GRP`) so none of them can pass by accident on BT/DV.
- **Group codes are validated:** a group code may not collide with a species code, and groups do not nest.

## Decisions (gate)

- **`wsg_regions.csv` is package-level** (`inst/extdata/`), one copy, because it is geography. Bundles declare only `species_pooling.csv`, the biological tracker.
- **The resolver is exported as `lnk_species_pooling()`**, because #236's access override will consume it too.
- **Resolution rule:** the most specific row wins (wsg > subregion > region). Anything unlisted is not pooled. A species always counts as itself, and the model species must still be present in the WSG (`wsg_species_presence`), as today.
- **Fallback:** a bundle without the tracker keeps today's behaviour (the validator's list default). Only `default` declares it, and `default_tuned` inherits it. `bcfishpass`, `default_extrabreaks` and `default_rearbreaks` are unchanged.
- **Seed:** `BT, DV, region` for Fraser, Mackenzie, Skeena and Columbia, plus `subregion` Kootenay, all `pool = yes`, source "operator call 2026-09-26". Kootenay is inside Columbia already; its row is there so the tracker can diverge later.

## Phase 1: Region lookup
- [x] `data-raw/wsg_regions_defs.csv`, hand-curated: `level, name, wscode_prefix`, holding 18 region rows and the Kootenay sub-region row. The coastal and cross-border names are drafted from their member WSGs and marked as drafts in the generator header.
- [x] `data-raw/wsg_regions.R`, which reads fresh's `wsg_outlet.csv` and the defs, then assigns region by top code and sub-region by the longest matching prefix. It writes `inst/extdata/wsg_regions.csv` (`watershed_group_code, region, subregion, wscode_outlet`).
  - It asserts 246 rows, every WSG with a region, and every def matched at least once.
- [x] Edit #290's body: regions are package-level (decided at this gate).

## Phase 2: Tracker and resolver
- [x] `inst/extdata/configs/default/species_pooling.csv` (bundle root, not `overrides/`: the README defines that as shared jurisdiction facts) with the seed rows.
  - Columns: `species_code, species_obs, scope_level, scope, pool, confidence, rationale, source, verified, issue`.
  - Declared under `default`'s `files:`, with a provenance entry and checksum.
- [x] `inst/extdata/configs/default/overrides/species_groups.csv` (SALMON, CHAR), declared under `files:` with provenance, plus its dictionary
- [x] Tests for groups: expansion on either side, the taxon-specificity tie-break, a colliding group code errors, a nested group errors
- [x] `inst/extdata/configs/dictionary_species_pooling.csv`, a column dictionary, covered by `tests/testthat/test-dictionaries.R`.
- [x] Tests first, in `tests/testthat/test-lnk_species_pooling.R`:
  - precedence (wsg > subregion > region);
  - a more specific `pool = no` overrides a region's `yes`;
  - unlisted means not pooled;
  - the species counts as itself;
  - the presence gate;
  - an unknown scope, a bad `scope_level` or conflicting rows at one level error.
- [x] `R/lnk_species_pooling.R`: `lnk_species_pooling(loaded, aoi, species)` returns `watershed_group_code, species_code, obs_species, scope_level, scope`. It is species-agnostic, and its `@examples` run against the shipped files.
- [x] `lnk_config_verify(lnk_config("default"))` is clean; `default_tuned` inherits the file

## Phase 3: Consumers
- [x] `lnk_habitat_validate()`: `species_obs` also accepts the resolver's data frame, applied per WSG; the list form and its default are unchanged. Add tests for both forms.
- [x] `data-raw/habitat_validate.R`: add `--pooling=<config>`, defaulting to the first bundle. The driver resolves once and passes the same table to both bundles, which keeps the same-observations assertion true. A bundle without the tracker falls back to the list default.
- [x] `data-raw/query_habitat_thresholds_obs.R`: replace the hard-coded `CASE` and `dv_ok` with a join to the resolved table, pushed as a temp table. The BT-only comparison set is kept.
- [x] Update the method lines in `research/habitat_validation.md` and `research/habitat_thresholds.md` ("DV counts as BT in the regions `species_pooling.csv` lists").

## Phase 4: Verification
- [x] Re-run `query_habitat_thresholds_obs.R`. `data-raw/logs/habitat_thresholds_284/` must come out byte-identical to what is committed, since all 55 WSGs are in pooled regions. Any diff gets root-caused, not accepted.
- [x] Re-run `habitat_validate.R` on the #283 5-WSG check. `summary.csv` rows must be identical to the committed baseline.
- [x] Negative check with a scratch bundle that sets Skeena to `pool = no`: BULK and MORR DV records drop out of BT, and nothing else moves. This proves the resolver is wired and not bypassed.
- [x] Record the per-region pooled-WSG counts in `research/` (the tracker's state of knowledge) and link it from #290

## Validation

- [x] `devtools::test()`: 2135 pass, 3 fail. The 3 are all the `:63333` bcfishpass tunnel being down (`test-lnk_db_conn.R:10`, `test-lnk_wsg_resolve.R:143`, `:154`), in files and functions this branch does not touch.
- [x] `devtools::document()` and `pkgdown::check_pkgdown()` clean
- [x] `lintr`: **not clean**, recorded as-is.
  - New code adds hanging-indent `indentation_linter` style lints, the same pattern as the repo's existing backlog (67 in `test-lnk_log.R` on main).
  - Plus 3 `object_usage_linter` false positives: `.lnk_presence_species_cols` and `.lnk_wsg_regions_path` are absent from the stale installed package.
- [x] `/code-check`:
  - Phase 2: three rounds, ended by enumeration.
  - Phase 3: two rounds, ended by enumeration, one below the skill's floor (stated in progress.md).
  - Phase 1 (generator) and Phase 4 (docs and evidence): self-review and mutation tests only.
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive`, then `/gh-pr-push` ("Fixes #290"); edit #284's body so step 5 is unparked

Out of scope: the access override's `observation_species` (#236), which will consume `lnk_species_pooling()`; the FISS absence taxa in the driver (#284 step 5 plan); logging the tracker into `<schema>.log_*` (the pipeline does not consume it yet).

## Reused
- fresh `inst/extdata/wsg_outlet.csv` (outlet codes); `lnk_config()`, `lnk_load_overrides()`, `lnk_config_verify()`
- `.lnk_hv_spec()` and `.lnk_wsg_species_present()` (`R/lnk_habitat_validate.R`), for the per-WSG shape and the presence gate
- `tests/testthat/test-dictionaries.R` (the dictionary coverage pattern)
