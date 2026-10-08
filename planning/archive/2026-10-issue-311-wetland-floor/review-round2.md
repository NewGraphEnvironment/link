# Code-check round 2 — #311 Phase 2 (staged diff, tests focus)

## Clean

No bugs, security issues or data-loss risks found in the staged diff.

## What was checked, and how

All work in a temp copy (`scratchpad/r2`, fresh floor lowered to 0.35.0); nothing in the repo
was modified except this file.

### Tests fail when the behaviour they name regresses (mutation, temp copy)

Baseline: `test-lnk_rules_build.R` all green.

| Mutation in `R/lnk_rules_build.R` | Result |
|---|---|
| M1 never floor (`carve_floored <- FALSE`) | 2 tests red: "floors the carve-out (explicit)" and "(categories)", 3 expectations each (type, floor, order) |
| M2 floor regardless of polygon (`carve_floored <- !is.na(rwhm)`) | 1 test red: "rear_wetland_polygon=no keeps the carve-out unfloored", 3 expectations |
| M3 floored carve-out emitted BEFORE the polygon W rule | 4 tests red: both "floors the carve-out" iterations plus the two shipped-bundle guards (first-W-rule edge filter) |

So both `for` iterations run independently (both went red under M1 and M3). `test_that()` runs
its body at once, so the loop variable is not captured late, and the `sprintf()` description
is built eagerly.

Length-0 / length->1 traps: in testthat 3.3.2, `expect_lt(integer(0), 3L)` and
`expect_lt(c(1L, 2L), 3L)` both **error** ("Result of comparison must be TRUE, FALSE, or NA").
So a `which()` that matched nothing or matched twice would turn the test red rather than pass
it quietly. `carve_rules()` matches the carve-out in both modes (`expect_length(carve, 1L)`
holds), and `is_carve` (`isFALSE(thresholds)`) picks out only the carve-out: no other rear rule
in `carve_dims()` carries `thresholds`. `$` partial matching cannot fire, because no key shares
a prefix with `thresholds`, `waterbody_type` or `wetland_ha_min`. `%||%` is link's own
(`R/utils.R:6`).

### Generated artifacts agree with the generator

- Each bundle's `rules.yaml` was rebuilt from its own `dimensions.csv`, using the edge-type mode
  in its header, and compared with the committed file minus the `# Generated:` line. All five
  were identical: bcfishpass, default, default_extrabreaks, default_rearbreaks, and
  default_tuned, which resolves to default's files.
- `lnk_config_verify()` found 0 byte or shape drift on all five bundles.

### Consumer: fresh v0.39.0, loaded from `git show v0.39.0:R/{frs_params,utils}.R`

- `.frs_load_rules()` accepts default `rules.yaml`, bcfishpass `rules.yaml` and the top-level
  `parameters_habitat_rules.yaml`, with `.frs_validate_rear_connected` included.
- `.frs_find_waterbody_rule(rear, "W")` returns the polygon rule (edges 1000/1100) for BT and
  CO.
- The compiled rear predicate carries
  `edge_type IN (1050, 1150) AND waterbody_key IN (… fwa_wetlands_poly WHERE area_ha >= <floor>)`.
- The other v0.39.0 readers take the first W rule, or the first L/W rule:
  - the bucket predicate (`frs_habitat_predicates.R:205`);
  - the connected-bucket pass (`frs_habitat.R:1303`);
  - waterbody-connected spawning (`frs_habitat.R:1252`).

  The new rule is never first, and none of them iterates over every W rule.
- link-side readers are unaffected:
  - `inherits_size()` and `query_width_mad_equivalent.R:78` already exclude `thresholds: false`;
  - `seg_class_sql` classes 1050/1150 as `other` before it reaches `wb_admit_sql`, as the new
    comment says;
  - `spawn_conn$waterbody_type` still resolves to the polygon W rule.

### Other test files that read rules

- These ran green: `test-lnk_config.R`, `test-lnk_config_verify.R`, `test-lnk_log.R`,
  `test-lnk_pipeline_connect.R`, `test-lnk_stamp.R` and `test-lnk_load_overrides.R`.
- `test-lnk_habitat_validate.R` reported 12 errors, and every one is a DB race on the shared
  `zz_lnk_validate_probe` schema:
  - "schema … does not exist" or "already exists";
  - `pg_type_typname_nsp_index` duplicate key.

  None is a rules or predicate failure. **Caveat for the caller:** if another process was
  running that test file at the same time, its errors were very likely caused by my run, so
  re-run it before trusting either result. I did not touch `zz311_*`.

## Notes (not findings)

- The staged diff does not include the `DESCRIPTION` pin bump. `fresh (>= 0.38.0)` and
  `fresh@v0.39.0` are unstaged in the working tree. If this commit lands alone, the branch
  briefly ships floored rules with a 0.35.0 floor. Under fresh < 0.38 the rear predicate does
  not apply `wetland_ha_min`, so the floor would silently not bind. This is harmless once the
  Phase 1 bump is committed on the same branch before merge. Make sure it is.
