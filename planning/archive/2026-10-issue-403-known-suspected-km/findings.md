# Findings — Known and suspected km per species in the group summaries (#403)

## Issue context

**If done:** `lnk_rollup_wsg()` reports, per group and species, the km accessible with the species recorded upstream (known) and the km accessible with no record upstream (suspected). **If never:** link reports accessible km only, and known against suspected still needs bcfishpass's tables.

### Problem

`lnk_rollup_wsg()`'s default `accessible_km` is `access IN (1, 2)` (`R/lnk_rollup_wsg.R:118`, link@43e34096). No link output tells 2 from 1 (`data-raw/logs/observation_breaks_396/readers_code2.md`). bcfishpass's `aw_linear_summary()` reports the same split as `length_naturallyaccessible_obsrvd_<sp>`.

### Proposed

Two default metrics beside `accessible_km`: km where `access = 2` and km where `access = 1`, which sum to it.

Open:
- **Names.** `accessible_observed_km` / `accessible_unobserved_km`, or `known_km` / `suspected_km`.
- **Habitat too?** Spawning and rearing km split the same way.
- **The export.** `lnk_scenario_export()` carries habitat flags, not `access_<sp>`. Should it carry the code too?

### Blocked by

- **#399.** Without it, known km run past each species' highest fish to the next break.
- **#401.** Without it, corridors below a group boundary read suspected even where the species is recorded just upstream.
- **#398,** for CT.
- **#400,** which defines "known".

The numbers mean something only for groups modelled after B and E land. `fresh_default` needs a re-model first, the next provincial run.

### Acceptance

- `observed + unobserved = accessible_km` on every row, tested.
- Numbers for #396's groups in `research/`.

Related: #396.

## Plan-mode exploration (2026-10-30)

- **Blockers #398, #399, #400, #401 are all open** (`gh issue view`, 2026-10-30); #396 closed 2026-10-28. #402 (presence against records) is open too.
- **bcfishpass tabulates two different "observed" splits** (`db/schema.sql:5272-5400`, local clone `smnorris/bcfishpass@620dbe43`, 2026-10-01):
  - `length_naturallyaccessible_obsrvd_<sp>` = `access_<sp> = 2`, `_model_<sp>` = `access_<sp> = 1`: the split #403 adds.
  - `length_spawningrearing_obsrvd_<sp>` = `greatest(spawning_<sp>, rearing_<sp>) >= 2`, `_model_<sp>` = `= 1`. Habitat code 2 is set in `model/02_habitat_linear/sql/load_habitat_linear.sql:37` where the model says habitat and `user_habitat_classification` (`streams_habitat_known`) says habitat; 3 where only the user table does; -1 / -4 / -5 are user negatives. So this split is expert-confirmed against model-only, not fish recorded upstream.
  - Each has `_access_a` (no dam or PSCIS barrier downstream) and `_access_b` (no anthropogenic barrier downstream) variants, per `assessment_watershed_id`, and spawning and rearing are combined.
- **On the reference view `fresh.streams_vw_bcfp` (local, province-wide):** `access_bt` is -9 / 0 / 1 / 2 (1,236,565 / 1,582,808 / 1,326,780 / 126,230 segments); `spawning_bt` and `rearing_bt` hold only -9 / 0 / 1; `spawning_ch` holds -9 / -1 / 0 / 1 / 2 / 3 (… / 172 / … / 164,755 / 22,585 / 3,952). PARS BT: `spawning_bt = 1` occurs with `access_bt` 1 and 2 alike, so the habitat code carries nothing about fish upstream.
- **link persists no overlay flag**: `lnk_habitat_gate()` takes `overlay = loaded$user_habitat_classification` and matches at gate time (`R/lnk_habitat_gate.R:17-22, 91`). A parity-shaped habitat split would need that flag or the same join.
- **Default-frame readers:** README.md:52-56 prints the default frame for PARS BT / GR (hand-pasted real output); the vignette names `lnk_rollup_wsg()` in prose only (`vignettes/pars-habitat-connectivity.Rmd:241`) and `data-raw/wsg_vignette_data.R:124` writes its own SQL; `lnk_compare_rollup()` passes explicit `km_metrics` (`R/lnk_compare_rollup.R:214-232`); **`lnk_habitat_validate()` calls the rollup with its defaults** (`R/lnk_habitat_validate.R:349`) and merges the whole cost frame into `summary` (`:1382`), with a fixed `cols_km` list in `data-raw/habitat_validate.R:163` (plan review). So two readers change: the README block and the validator's `summary`.
- **Existing exact-names test** at `tests/testthat/test-lnk_rollup_wsg.R:173-175` pins the four default names (plan review); Phase 1 amends it.
- **`R/lnk_rollup_wsg.R:14-16` says an unbuilt access "resolves to 0"**; a `FILTER` sum over no rows is NULL (plan review).
- **m4's `fresh` still holds #396's `bcfishpass` BULK and PARS builds**: `fresh.log` newest rows link `71ccc2ce`, config `bcfishpass`, closed 2026-10-28 08:29 / 08:32 UTC (checked 2026-10-30).
- **Local `fresh_default`** holds 241 groups (0.68.0 build, breaks at every observation). BT codes in the five #396 groups (2 / 1 / 0): BULK 1,743 / 30,602 / 55,295; ELKR 3,237 / 23,723 / 56,397; LKEL 187 / 2,017 / 5,244; PARS 3,021 / 35,913 / 58,603; UPCE 1,904 / 19,669 / 25,050. No NULL or -9.
- **m4 still holds the #396 builds:** `zz396_default_pre` and `zz396_default_post` (23 tables each; `streams_access` rows BULK 42,555, ELKR 38,601, LKEL 3,312, PARS 46,004, UPCE 23,792), `zz396_cuts`. `zz396_default_post.log`: link `71ccc2ce` 0.69.1, fresh 0.43.0, one config hash, every row closed (ELKR twice: the repeat). Postgres is published on 5432 there.
- **Existing live-test pattern** (`tests/testthat/test-lnk_rollup_wsg.R:196-246`, #319): `skip_if_no_db()`, skip when `fresh_default` lacks the tables, pick an aoi by query, unrounded custom metrics at `tolerance = 1e-9`, the default frame within 0.0101, and a direct sum with no polygon join against fan-out.
- **Rounding:** each default column is `round(..., 2)` separately, so the identity holds to 0.01 km, as #319's does.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 4 measurements (2026-10-30)

- **The before-#396 builds are at link `43e34096`, not `71ccc2ce`** (`zz396_default_pre.log`); the plan's stamp named only the after builds' SHA. Both 0.69.1, fresh 0.43.0, different config hashes.
- **Identity holds on all 50 rows** of the five groups in both schemas, largest gap 0.010 km; no row has an empty accessible set.
- **Observed km only rose under `top_per_species`** (0 to 2.29 km), accessible km did not move.
- **link's `bcfishpass` builds read more observed km than the reference view** (BULK BT +14.46, CH +5.46, CO +27.77, PK +4.14, SK +1.91; PARS BT +29.70), with accessible km within 1.3 km. Every disagreeing piece is link 2 / bcfishpass 1 and lies on a link segment starting within 1 m of a same-line record of the species: the segment above a record, #399's subject.
- **bcfishpass's view codes steelhead 2 from sockeye records** (BULK ST observed = SK observed = 312.53). Upstream defect, fixed `smnorris/bcfishpass@3bd2824c` on 2026-10-23 (their issue 938); the view on m4 is from `v0.7.14-113-ga7373af`, before it. Not reported upstream by us: already fixed there.
