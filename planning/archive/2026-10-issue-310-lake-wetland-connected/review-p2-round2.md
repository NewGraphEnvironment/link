# Review: #310 Phase 2 staged diff, round 2

## Clean

No bug, security issue or fragile behaviour found in the staged R code or tests. Both
round-1 fixes are correct, and neither introduces a new defect.

### Checked, with evidence

- **The staged tree builds and loads for every bundle.** The staged tree was exported with
  `git checkout-index` to a scratch dir. The staged `R/lnk_rules_build.R` built every
  `configs/*/dimensions.csv` plus `inst/extdata/parameters_habitat_dimensions.csv` in both
  `explicit` and `categories` modes, and each output went through fresh 0.39.0's
  `.frs_load_rules()` (installed fresh is 0.39.0). Two sets of inputs:
  - **HEAD dimensions** (the data this commit ships): all OK, with no connection stamps.
  - **Working-tree dimensions** (the later data commit): all OK. BT, CH, CO, ST, WCT and RB
    get the stamp on W then L at 10000. GR gets it on L only. SK and KO get none.
    `.frs_validate_rear_connected()` and the per-rule rear `requires_connected` checks
    (L/W only, `'spawning'`, finite distance > 0) all pass.
- **The test file passes on the staged tree** (`NOT_CRAN=true`, `load_all`, `test_file`):
  0 failures. That includes the new bcfishpass byte-identity test and the default-bundle
  lake edge-set test.
- **Fix 1: explicit lake codes in both modes.** In categories mode the L rule carries only
  `edge_types_explicit`, and fresh's `.frs_rule_to_sql()` compiles that the same way in
  either mode. The code set matches the comment: 1410, 1425 and 1550 are excluded.
  - fresh's `lake_rearing` bucket is polygon membership plus the ha floor
    (`frs_habitat_predicates.R` ~194-206). It does not read the edge filter, so widening
    `lake_edges` moves `rearing` and leaves the bucket alone.
  - 1250 and 1350 lines in river polygons carry a river `waterbody_key`, so the L rule's
    `waterbody_key IN (lakes ∪ reservoirs)` clause does not pick them up.
- **Fix 2: the area_only refusal now fires only in the additive branch.** The gate
  `!rear_no_fw && !rear_lake_only && rear_lake` is the precedence the rear branch uses, and
  it reads values already coerced to logical, with `isTRUE` guarding NA. The lake-only half
  of the test confirms the column is ignored there.
- **No-rule stop.** A connection distance on a species with no rear rule of that type
  stops the build. That holds for `rear_no_fw` (empty `rear_rules`; vapply on an empty list
  returns `logical(0)`), for `rear_wetland = no`, and for `rear_wetland_polygon = no` with
  an unfloored carve-out, where no W rule exists.
- **"First" means the same rule in link and fresh.** The link loop picks the first rule
  whose `waterbody_type` is identical to L or W. That is the rule
  `.frs_find_waterbody_rule()` returns and the one `.frs_validate_rear_connected()`
  requires. The floored 1050/1150 W rule always comes after the polygon W rule, so it is
  never stamped.
- **`read_cdm()` input handling.**
  - An all-NA column read as logical becomes blank.
  - Scientific notation parses.
  - `0`, negative values, `Inf` and text stop the build.
  - The value written is a double, and fresh accepts it as numeric.
- **Legacy columns.** `rear_requires_connected` and `rear_connected_distance_max` with
  values stop the build. Empty columns pass, and no HEAD bundle sets them.
- **No other consumer.** No other link R code reads `edge_types_explicit`, `thresholds` or
  `requires_connected` from the rules. `lnk_pipeline_connect()` passes them straight to
  fresh's `.frs_run_connectivity()`.

### Noted, not flagged (pre-existing, not changed by this diff)

- **`spawn_connected$waterbody_type` comes from the first rear rule with any
  `waterbody_type`.** In the additive branch that rule is the river rule (`R`). Only the
  lake-only SK and KO use `spawn_connected` today.
- **Rule order decides the spawn anchor for a hypothetical additive species with
  `spawn_requires_connected = rearing`.** The W polygon rule precedes the L rule, so
  fresh's spawn connectivity would anchor on W, not on the lake the new comment names. No
  bundle has such a species.
