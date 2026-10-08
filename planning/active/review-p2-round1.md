# Review: #310 Phase 2 staged diff, round 1

Verdict: no blocking bug. The explicit-mode output loads through fresh 0.39.0's
`.frs_load_rules()` / `frs_params()`. That was tested on the `default` bundle with
`rear_{lake,wetland}_connected_distance_max = 10000` set for every species except SK and KO,
in both edge-type modes. The stamp goes on the polygon W rule (1000/1100) and on the L
rule, and never on the floored 1050/1150 W rule. Of the bundles, only bcfishpass has no
additive `rear_lake = yes` species, so its rules are unchanged. The test file passes in a
scratch copy (`NOT_CRAN=true`, `load_all`).

Checked and fine:
- fresh's `.frs_rule_to_sql()` already turns off threshold inheritance for L / W rules, so
  `thresholds: false` on the L rule changes no SQL. No link code other than the
  test helpers tells the carve-out apart by `thresholds: false`. The validator builds its
  predicates from fresh's compiled SQL.
- The SK / KO spawn-connectivity anchor, the first rear L / W rule in
  `.frs_run_connectivity()`, is unchanged. Those species take the `rear_lake_only` branch,
  so their first L rule is the same.
- No bundle sets values in the legacy columns, and no bundle sets `rear_lake_area_only = yes`
  on SK / KO, so every shipped `dimensions.csv` still builds.

## Findings

- **[fragile]** R/lnk_rules_build.R:220-225. In categories mode the lake edge set does not
  match the explicit set or its own comment.
  - `c("stream", "construction", "connector")` resolves, through fresh's `edge_types.csv`,
    to 150, 1000, 1050, 1100, 1150, 1200, 1250, 1300, 1325, 1350, 1375, **1400, 1410,
    1450, 6010**, 1475 and 1550.
  - So it admits 1410 (network connector), 1550 (lakeshore construction line) and the
    1325 / 1375 delimiters, which the comment says are excluded ("1410 ... and 1425 ...
    are left out").
  - Categories is `lnk_rules_build()`'s default `edge_types`, so a caller who takes the
    default gets a wider lake `rearing` set than the explicit mode it is documented
    against.
  - No shipped bundle builds in categories mode (all `data-raw` callers pass
    `"explicit"`), so today's outputs are unaffected.
  - Fix: either spell the categories-mode set as the same explicit codes, or say in the
    comment that categories mode is wider.

- **[fragile]** R/lnk_rules_build.R:267-271. The `rear_lake_area_only` refusal for
  `spawn_requires_connected = rearing` species also fires in the `rear_lake_only` branch.
  - That branch never emits `area_only` (`add_ao()` is applied only in the additive
    branch, and the existing test "rear_lake_only branch L rule does NOT carry edge filter
    or area_only" asserts this).
  - So SK / KO with `rear_lake_only = yes` and `rear_lake_area_only = yes` built cleanly
    before, with the flag ignored, and now stops with a message that is false for that
    branch ("would remove the lake rearing its spawning is anchored to").
  - The new test "area_only on the lake rule is refused where spawning requires rearing"
    uses exactly that configuration, `lake_only = "yes"`. It therefore pins the
    over-refusal rather than the case the guard was written for: a hypothetical additive
    SK, whose `area_only` L rule would really leave spawning without its anchor.
  - No shipped bundle hits this, because all have `rear_lake_area_only = no` for SK / KO.
  - Fix: gate the check on the branch that emits `area_only`
    (`!d$rear_no_fw && !d$rear_lake_only && d$rear_lake`), or accept the stricter rule and
    reword the message.
