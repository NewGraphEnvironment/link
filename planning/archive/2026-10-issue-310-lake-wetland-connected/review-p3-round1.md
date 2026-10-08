# Code-check review — #310 Phase 3 (bundle data), round 1

Reviewed staged diff `p3.diff` (16 files) against HEAD 83dfe16.

## Findings

- **[fragile]** inst/extdata/configs/dictionary_dimensions.csv:5 (`rear_lake` row) — the
  description lists the lake-centreline set as `[1000, 1100, 1200, 1300, 1400, 1450, 1475]`,
  but the builder (`R/lnk_rules_build.R:219-225`) and every regenerated rules.yaml emit
  `1000, 1100, 1200, 1250, 1300, 1350, 1400, 1450, 1475`. The reservoir edges 1250 / 1350 were
  added after the plan review and the dictionary text was not updated. No code reads this
  description, so nothing breaks today. But the dictionary exists so people do not re-derive
  the edge set, and as written it understates which lines the L rule admits. Of the two,
  1250 is the one that matters: river-polygon main-stem lines, which a reader would not
  expect in a lake rule. Fix: add 1250 and 1350 and name the reservoir reason.

No bugs found. Every check below came back clean.

## What was verified (mechanically, not by reading)

- **CSV integrity, by header name.** I parsed the HEAD and staged versions of `default`, the
  two variants and the top-level `parameters_habitat_dimensions.csv` with `colClasses =
  "character"` and compared them column by column.
  - Field counts: default family has 14 rows × 34 fields; the top-level file has 14 × 29. No
    ragged rows.
  - The only changed cells are CO `rear_lake_ha_min` (2 → blank), CO `rear_wetland_ha_min`
    (0.5 → blank) and CO `notes`.
  - The new columns sit second and third from the end, just before `notes`. They hold 10000
    for BT, CH, CO, ST, WCT, CT, DV and RB, plus GR's lake column, and are blank for CM, PK,
    SK, KO and GR's wetland column.
  - Notes text is intact. Quoting is unchanged in style: the default family is quoted with
    bare empty numerics; the top-level file is unquoted.
  - The three default-family CSVs are byte-identical. Trailing newlines are preserved in
    every staged file.
- **rules.yaml is the build.** I rebuilt from the staged CSVs with `lnk_rules_build()` into a
  scratch dir. Ignoring the `# Generated:` line, each rebuild is identical to its committed
  file:
  - `default`, `default_extrabreaks` and `default_rearbreaks`, each with its own thresholds CSV;
  - the top-level file, with fresh's thresholds;
  - `bcfishpass`, which is unchanged.
- **fresh loader.** `fresh::frs_params()` (installed 0.39.0, the pinned version) loads all five
  builds without error, including `.frs_validate_rear_connected`. That validator exists in
  v0.39.0, so the new test's `skip_if_not` does not skip.
- **Provenance.** `lnk_config_verify()` reports no byte drift, shape drift or missing files for
  `bcfishpass`, `default`, `default_extrabreaks`, `default_rearbreaks` and `default_tuned`.
  `generator_sha` 83dfe16 is HEAD, and `R/lnk_rules_build.R` has no uncommitted changes.
- **bcfishpass untouched.** No staged path under `configs/bcfishpass/`.
- **Tests** (`NOT_CRAN=true`):
  - `test-lnk_rules_build.R`: 255 pass, 0 fail, 0 skip;
  - `test-dictionaries.R`: 99 pass;
  - `test-lnk_config.R`: 161 pass;
  - `test-lnk_config_verify.R`: 40 pass.
- **CO unfloored is consistent downstream.** The CO `rear_lake_ha_min` threshold is NA in
  `default`, `default_tuned`, `default_extrabreaks` and `default_rearbreaks`. So fresh's
  `.frs_build_ranges()` adds no `lake_ha` range from the thresholds CSV.
  - fresh's waterbody-connected spawning pass, with its 200 ha default, runs only for species
    whose spawn rules carry `requires_connected`, which is SK and KO. It does not touch CO.
  - CO's first W rule is still the polygon rule. The unfloored 1050/1150 carve-out is now a
    plain edge rule emitted before it, with no `waterbody_type`, which is correct per #311.
- **Research claim checked.** `default/parameters_fresh.csv` does have `cluster_rearing =
  FALSE` for RB, CT and DV, as `research/habitat_thresholds.md` states.
