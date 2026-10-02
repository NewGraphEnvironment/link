# Review: variants harness extended for MAD ladders (#302), round 1

Scope: working-tree diff of `data-raw/habitat_variants_build.R`,
`data-raw/habitat_variants_score.R`, `data-raw/habitat_score/README.md`.
Reviewed by reading. Nothing was run against the DB.

## Findings

- **[severity: bug]** `data-raw/habitat_variants_score.R:595-603` (taper / elevation / elevation_adjusted):
  `band_case` gives each segment to the FIRST step in `lad` whose flag differs from its
  `step_from`. That is only right when the ladder is nested. A MAD ladder is not nested: the
  anchor's band is two-way (cw base vs mad P10), so the segments that cw keeps, P10 drops
  and P05 adds back all match the anchor's `WHEN` first and get labelled `band <anchor>`.
  - `bands.csv` / `verdict.csv` count those segments in P05's band, because
    `lnk_habitat_validate_band` compares P05 with the anchor.
  - `taper.csv`, `elevation.csv` and `elevation_adjusted.csv` leave them out of P05's band.
    So for every post-anchor rung, the elevation-adjusted ratio describes a different, smaller
    set of segments than the verdict, and nothing marks the difference.
  - The anchor's own row mixes the "mad adds" and "mad drops" directions into one rate.
  - If the anchor row comes after P05 in the CSV, the misassignment runs the other way.
  - #284 quoted the elevation-adjusted ratios beside the verdict ("0.75 and 0.89
    elevation-adjusted"), so these figures would be read as evidence.
  - Fix: build the band classes the way the band function does, from each step against its
    own step_from (one segment can sit in two bands). Or leave the anchor out of `band_case`
    and the core comparison.
  - Separately, the taper's core bins are gradient bins (`grad_bins`), which say nothing
    about a `_mad_min` ladder.

- **[severity: bug]** `data-raw/habitat_variants_score.R:385-388, 410` together with the planned
  ladder shape in `habitat_score/README.md`:
  - The core is `ladder_of()` = cw base ∩ every rung, and the base is `default`.
  - The planned BT/GR rear rungs carry `set` cells that differ from `default`. BT
    `rear_gradient_max` goes 0.1049 -> 0.1349, and the spawn range changes.
  - So the core is cut at default's rear gradient max of 0.1049, while every MAD band (P05 vs
    P10, P02 vs P05, all at 0.1349) can include segments between 0.1049 and 0.1349.
  - The band is therefore compared against a core that by construction excludes the gradient
    window #284 measured at density ratio 0.60-0.71, which biases MAD steps toward "refuse"
    for a gradient reason. The verdict will look like a discharge finding.
  - The core needs a cw reference that carries the same `set` cells, or the band's gradient
    window has to match the core's.

- **[severity: fragile]** `data-raw/habitat_variants_score.R:212-224`: the score checks only the
  number of `set` cells (`1L + n_set(r$set)`), never their names or values, and never checks
  `model` against the bundle.
  - The bundle on disk is still verified against built.csv. So if variants.csv is edited
    after a build (a `set` value changed, or `model` flipped) and that variant is not rebuilt,
    the score passes and labels results with values the bundle does not hold.
  - A `model` flip changes which step is treated as the anchor and the step direction.
  - Parse `set` the way the build does, compare each cell to the bundle, and assert that a
    `mad` variant's method table is its own and not default's.

- **[severity: fragile]** No check that `set` is held constant along a ladder, although the README
  states it as the rule.
  - Each rung is checked only against `default` (build `n_diff == length(cells)`, score
    `n_set`), so a rung that drops or changes a `set` cell its step_from carries passes both
    scripts. The step's band then mixes that cell's effect into the MAD verdict.
  - The 1 % against-direction stop (score :448-459) catches this only when the inconsistency
    removes habitat, for example a dropped spawn range or a lower gradient max. A `set` cell
    that only adds habitat passes silently.
  - Assert that `sets[[v]]` equals `sets[[step_from]]` for every non-anchor step.

- **[severity: fragile]** `data-raw/habitat_variants_score.R:207-208`: an NA `method_sha256` (a
  pre-#302 row) is accepted for any `cw` variant without checking that the method table
  resolved *now* still puts its WSGs on cw.
  - If `default`'s method table later moves a group to `mad`, a pre-#302 `cw` schema is
    re-scored by the validator under `mad` (it takes `models` from the current cfg), while it
    was classified on cw. That is exactly the mismatch #299 exists to prevent.
  - Accept NA only where `.lnk_wsg_model()` of the current table gives cw for every scored
    WSG.

- **[severity: fragile]** `data-raw/habitat_variants_build.R` `working_of()` (pre-existing, made
  live by #302): working schemas are named `working_score_<wsg>` with no prefix.
  - The plan says #302 is rebuilt "into a new prefix rather than patched". But a `score302_`
    base over the #284 WSGs it shares (BULL, ELKR, UARL, …) overwrites #284's
    `working_score_*`.
  - #284 can then no longer be extended or rebuilt with `--step=variants` without a new base.
    The digest check stops that loudly, so this is not silent.
  - Two builds on different prefixes running at once would corrupt each other.

## Checked and fine

- Walk with an anchor:
  - `startsWith(NA, "take")` is NA, and `dec[NA] <- "take"` is a permitted length-1 assign
    (verified).
  - Refused at the first post-anchor rung gives the anchor's value.
  - Underpowered there gives NA.
  - `stop_at == 1` cannot occur while the anchor row is present.
  - The band function always emits `added` rows, so `rule` keeps the anchor.
- Value columns:
  - `value_of` for the anchor gives the default cell (NA for the missing ranges).
  - `loosens` NA OR `model_step` TRUE gives "added".
  - The `value_from` join-back after `aggregate()` is keyed on variant, and the column order
    is restored.
- Build side:
  - `write_bundle` method table: the rbind works with zero new rows, the columns match
    default's (`watershed_group_code,model`), unquoted like default, and it uses the full
    roles file, so it is independent of `--wsgs`.
  - Provenance: the verify loop keys match `lnk_config_verify()$file`, the child entry
    overrides the inherited one, and `normalizePath` is fine.
  - `record_built`: back-compat column add and reorder are correct.
- Score side:
  - Bridge `$4`: `in_window` is NULL for MAD and anchor steps.
  - `copy_access` and the access digests are unaffected by the model, because classify
    and connect do not touch access.
  - `.lnk_hv_obs` uses `models` only to add a column, so `obs_key` does not move.
