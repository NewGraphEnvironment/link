# Review round 3 — consumers of rules.yaml / rear rules (#311, staged diff)

## Clean

No real issues found. Every consumer of the rear rules either does not see the
second W rule, sees it exactly as intended (fresh v0.39.0 compiles the floor into
`rearing`), or keeps reading the polygon W rule because it comes first.

## Enumeration: link (R/ and data-raw/)

| Reader | What it reads | Effect of a second W rule (thresholds: false, edges 1050/1150, wetland_ha_min) after the polygon W rule |
|---|---|---|
| `R/lnk_pipeline_classify.R:109-111` (`frs_params` → `frs_habitat_classify`) | the whole rules file, through fresh | Intended change: fresh v0.39.0 compiles `(edge_type IN (1050,1150) AND waterbody_key IN (fwa_wetlands_poly WHERE area_ha >= floor))` into `rear`. The bucket still reads the polygon rule. |
| `R/lnk_pipeline_classify.R:169-176` (the stream-order bypass loop) | `channel_width_min_bypass` only | None. |
| `R/lnk_pipeline_connect.R:94-108` → `fresh:::.frs_run_connectivity` | see the fresh rows below | None beyond fresh's own reading. |
| `R/lnk_habitat_validate.R:1028` and `.lnk_hv_stage_exprs` (`frs_habitat_predicates`) | the compiled rear / lake / wetland predicates | Same predicate as classify, so the validator agrees with the run. `.lnk_hv_relax` substitutes `s.gradient` / `s.channel_width` / `s.mad_m3s`, and a W rule carries none of them, so no relaxation reaches the floor (as intended). |
| `R/lnk_discharge.R:248` `.lnk_rules_read_mad` | whether any rule has a `mad` key | None. |
| `R/lnk_config.R:117` | species names only | None. |
| `R/lnk_log.R:62` | `cfg$rules` path for the config hash | The hash moves with the bytes, as intended. |
| `R/lnk_rules_build.R:409-415` (`spawn_conn$waterbody_type`, first rear rule with any type) | first typed rear rule | None. The river R rule (or the polygon W) still comes first, and the floored carve-out is emitted later. |
| `data-raw/query_habitat_thresholds_mad.R:153-159` `wb_admit_sql` | L/W rear rules → `.frs_rule_to_sql` | Now ORs in the floored carve-out. It changes nothing: `seg_class_sql` classes `edge_type NOT IN (1000,1100,2000,2300)` as `other` before the predicate is read. The comment at :151-152 is accurate. |
| `data-raw/query_habitat_thresholds_mad.R:332-338` `inherits_size`; `data-raw/query_width_mad_equivalent.R:78` | rules with no `thresholds: false` and no `waterbody_type` on 1000/1100 | Excluded before (`thresholds: false`) and after (also typed). None. |
| `data-raw/audit_configs.R:86-108` §2 (regenerate and compare) | every bundle through `lnk_config()` | Re-ran it in a temp copy. default, default_extrabreaks, default_rearbreaks, default_tuned and bcfishpass all match structurally, and match byte for byte apart from the `# Generated:` line. |
| `data-raw/audit_configs.R:369` §6 | mtime of the top-level yaml only | None. |
| `data-raw/rule_flexibility_demo.R:115` | the CO block, for display | None. |
| `data-raw/habitat_variants_build.R` / `_score.R` | thresholds CSVs only. Rules are inherited. | None. |

## Enumeration: fresh v0.39.0 (`git grep … v0.39.0 -- R/`)

| Reader | Effect |
|---|---|
| `frs_params.R:126-174` `.frs_load_rules` / `.frs_validate_rule` | Accepts the rule: `wetland_ha_min` is on `waterbody_type: W`, it is a numeric scalar, `thresholds` is logical, and the edges are integers. Every regenerated file (top-level, default, extrabreaks, rearbreaks, bcfishpass) loads through v0.39.0 `frs_params()`, tested by `load_all` of a `git archive v0.39.0` copy. |
| `frs_params.R:185-206` `.frs_validate_rear_connected` | Would error if a later W rule carried `requires_connected`. No default species sets `rear_requires_connected`, so nothing fires today. Under `add_rc()` it would also have errored before this change (an untyped rear rule with `requires_connected`). That is #310's, and accepted. |
| `utils.R:235` `.frs_rule_to_sql` | A W type forces `inherit_thresholds <- FALSE`, so there is no gradient / cw / mad inheritance under either model, the same as the old `thresholds: false`. Compiled: `s.edge_type IN (1050, 1150) AND s.waterbody_key IN (SELECT … fwa_wetlands_poly WHERE area_ha >= 1)` (CO 0.5) for BT, CH, CO, RB, ST and WCT. |
| `frs_habitat_predicates.R:166-171` (main rear, `area_only` filter) | The carve-out carries no `area_only`, so it stays in `rear`, even when the polygon rule is `area_only`. |
| `frs_habitat_predicates.R:205-206`, `utils.R:406` `.frs_find_waterbody_rule` (wetland bucket) | Takes the first W rule, which is still the polygon rule. The compiled `wetland_rear` is unchanged: polygon membership plus the floor, with no edge filter. |
| `frs_habitat.R:1252-1262` (waterbody-connected spawning: the first L or W rear rule) | The polygon W still comes before the carve-out and the L rule, so this is unchanged. |
| `frs_habitat.R:1302-1313` (fresh#240 bucket-connected pass) | Reads the first L / W rule, so this is unchanged. |
| `frs_params.R:65`, `frs_habitat.R:248` (default `rules_yaml`) | `system.file(..., package = "fresh")`. They read **fresh's** bundled yaml, never link's. |

## Top-level `inst/extdata/parameters_habitat_rules.yaml`

No R code in link reads it. The only references are `data-raw/build_rules.R` (the writer), an `@examples` path in `R/lnk_rules_build.R:27`, and the mtime print in `audit_configs.R` §6. fresh reads its own copy, so the regenerated file is documentation / legacy. It matches a fresh rebuild (installed thresholds) apart from the date line.

## Provenance / checksums

- The staged `rules.yaml` is byte-identical across default, default_extrabreaks and default_rearbreaks (sha256 `99728919…`), and that equals the staged `checksum:` in all three `config.yaml`.
- `shape_checksum` is a hash of the first line only (`.lnk_shape_fingerprint`), and the first line did not change, so leaving it alone is correct.
- `lnk_config_verify()` reports no byte or shape drift for all five bundles.
- Nothing else in the repo pins the old checksum `68380b1d…`.

## Tests run (temp copy, installed fresh 0.36.2)

- test-lnk_rules_build 201 pass. config_verify, config, discharge, load_overrides, log, pipeline_classify, pipeline_connect and stamp all pass.
- test-lnk_habitat_validate: 17 errors, all `schema "zz_lnk_validate_probe" does not exist` / `relation … exists` races. Another process was using that fixture schema at the same time, so these are unrelated to the diff. **Heads-up:** this run touched `zz_lnk_validate_probe`, so if the parent ran that file in the same window, its errors may be mine.
- Under fresh 0.36.2 the floored carve-out compiles **without** its floor (wetland membership only). It needs the v0.39.0 pin, which lands in the separate commit (accepted).
