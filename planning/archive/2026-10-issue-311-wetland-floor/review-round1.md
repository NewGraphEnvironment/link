# Code-check round 1: #311 floored wetland carve-out (staged diff)

## Clean

No issues found.

## What was checked (evidence, not findings)

- **Generated YAML matches the generator.** In a temp copy of the working tree (fresh floor lowered
  to 0.35.0), `lnk_rules_build()` was re-run for `parameters_habitat_rules.yaml` and for
  `default`, `default_extrabreaks`, `default_rearbreaks` and `bcfishpass`, each with its bundle's
  thresholds CSV. Every output is identical to the committed file apart from the `# Generated:` line.
  `bcfishpass` is identical too, so leaving it unregenerated is correct.
- **Provenance.** `lnk_config_verify()` reports no byte drift, shape drift or missing file for
  rules.yaml or dimensions.csv in default, default_extrabreaks, default_rearbreaks, default_tuned
  or bcfishpass. `shape_checksum` stays the same, as it should.
- **fresh v0.39.0 accepts the YAML.** Loaded with `pkgload::load_all()` on `git archive v0.39.0`,
  `.frs_load_rules()` loads all five rules files. In particular, `wetland_ha_min` sits on
  `waterbody_type: W`, `thresholds: false` sits beside a W type, and `.frs_validate_rear_connected`
  passes because no rule carries `requires_connected`. For BT, CH, CO, ST, WCT and RB,
  `.frs_find_waterbody_rule(rear, "W")` still returns the polygon mainline rule (1000/1100). The
  compiled BT rear predicate shows the carve-out as
  `edge_type IN (1050,1150) AND waterbody_key IN (wetlands WHERE area_ha >= 1)`.
- **fresh v0.39.0 consumers.** fresh reads a W rule in four places, and the floored carve-out
  sits after the polygon rule, so none of them changes behaviour:
  - `build_wb_pred` / `.frs_find_waterbody_rule` take the first W rule only.
  - The waterbody-connected spawning loop takes the first L or W rule.
  - The `area_only` filter only affects the polygon rule. The carve-out carries no `area_only`.
  - The `.frs_rule_to_sql` L/W branch already skips threshold inheritance.
- **The 40-line NULL-key claim.** Measured on local fwapg:
  - 1050: 40 NULL `waterbody_key` (7 km) and 309,047 in wetlands.
  - 1150: 2,451, all in wetlands.
  - No 1050 or 1150 line has a key outside `fwa_wetlands_poly`, so a W type drops nothing else.
- **link-side consumers of the rules.**
  - In `query_habitat_thresholds_mad.R`, `wb_admit_sql` puts 1050/1150 in the `other` class
    first (`edge_type NOT IN edges_stream`), so the new comment holds. Its `inherits_size()` and
    the one in `query_width_mad_equivalent.R` already exclude the carve-out (`thresholds: false`).
  - `lnk_habitat_validate` uses fresh's predicates.
  - No other R/ or data-raw code selects W rules.
  - The `spawn_connected` `rear_wb` lookup in `lnk_rules_build()` gives the same first waterbody
    type as before.
- **Pre-existing, not introduced:** `add_rc()` stamps `rear_requires_connected` on the floored
  carve-out, and fresh would then refuse it as a second W rule. Before this change the unfloored
  carve-out was already refused ("requires_connected without waterbody_type: L or W"). Both are
  covered by #310.
- **Tests.** `devtools::test(filter = "rules|config|dictionar")` in the temp copy: 501 expectations,
  0 failed, 0 skipped, 0 errors, 0 warnings.
