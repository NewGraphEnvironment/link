# Code-check review — #310 Phase 3 (bundle data), round 2

Fresh reviewer, staged diff `p3.diff` (17 files) against HEAD 83dfe16.

## Clean

No bugs, security issues or fragile code found.

## What was verified (by running, in a scratch copy of the tree)

- **The new test can fail.** In a copy, `test-lnk_rules_build.R` passes the new block with
  28 expectations and 0 skips (`NOT_CRAN=true`, installed fresh 0.39.0, so the
  `skip_if_not(.frs_validate_rear_connected)` guard does not skip). I then changed one
  `connected_distance_max: 10000.0` to `9000.0` in the committed `default/rules.yaml` and
  re-ran: the block fails. So the committed-equals-build comparison is live. The other
  assertions also cannot pass vacuously:
  - `find_wb_rule()` returns NULL when a rule is missing. `expect_equal(NULL, "spawning")`
    and `expect_gt(NULL, 0)` then fail.
  - The CO `expect_null(...$lake_ha_min)` sits after the loop that asserts CO's L rule
    exists.
- **The fresh validator is exercised, and the rules satisfy it.** In fresh v0.39.0,
  `frs_params(rules_yaml=)` calls `.frs_load_rules()`. That runs `.frs_validate_rule()` and
  `.frs_validate_rear_connected()`, which together require:
  - `requires_connected` only on the first L or W rule;
  - the value `spawning` on a rear rule;
  - a finite `connected_distance_max` greater than 0.

  In the CO block, the 1050/1150 carve-out no longer has a `waterbody_type`. The W polygon
  rule therefore stays CO's first W rule and carries the connection keys.
- **fresh semantics match the rules.**
  - `.frs_rule_to_sql()` already skips threshold inheritance on L and W rules, so
    `thresholds: false` on the L rule is redundant but harmless.
  - The `lake_ha_min` floor is still applied, via `.frs_rule_ha_min()`.
  - `.frs_bucket_connected()` clears only the `lake_rearing` / `wetland_rearing` flag.
- **Research prose matches the data.**
  - `default`, `default_extrabreaks`, `default_rearbreaks` and `default_tuned` all have
    `cluster_rearing = FALSE` for RB, CT and DV, and `cluster_direction = both` with a
    10 km bridge for the others. So "kept when spawning lies anywhere upstream, or
    downstream within the bridge limits" holds.
  - Every thresholds CSV (all bundles and fresh's) lacks CT and DV rows, so they emit no
    rules: "inert" holds, and the test's `expect_null(r$CT)` holds.
  - CO `rear_lake_ha_min` is NA in every thresholds CSV, so blanking the dimensions cell
    leaves CO unfloored and nothing refills it.
  - The ladder percentages (+0.6 % lakes and +6 % wetlands above 3 km) recompute from the
    table.
- **Provenance.** `lnk_config_verify()` reports no byte drift, shape drift or missing files
  for `default`, `default_extrabreaks`, `default_rearbreaks` and `default_tuned`. The three
  default-family `rules.yaml` files are byte-identical.
- **Top-level `parameters_habitat_rules.yaml`.** It differs from `default/rules.yaml` only by
  SK's `lake_adjacent: false`, because the top-level dimensions have no
  `spawn_connected_lake_adjacent` column. That difference predates this diff.
- **No other consumers.** No R code outside `lnk_rules_build()` reads the changed dimension
  columns. `lnk_habitat_validate()` compiles its predicates through
  `fresh::frs_habitat_predicates()`, so it follows the new rules automatically.

Note, not a defect in this diff: the validator's lake / wetland bucket predicate is
pre-connectivity. Buckets cleared by `.frs_bucket_connected()` will show as `post_predicate`
misses, the same class #299 documents for cluster passes. Phase 4 and the validator docs may
want to name it.
