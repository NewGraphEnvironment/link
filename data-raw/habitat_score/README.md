# habitat_score

The inputs for scoring habitat-threshold variants against fish observations (#284 step 5).
The rule and the reasoning behind it are in `research/habitat_thresholds.md`, under
"Scoring design". Two scripts use these files:

- `data-raw/habitat_variants_build.R` models every variant on one shared segmentation.
- `data-raw/habitat_variants_score.R` scores the variants and applies the rule.

Everything species-specific is here, and neither script names a species.

## `variants.csv`

One row per variant. The row with an empty `column` is the base, `default`. Every other
row changes exactly one cell of `default`'s `parameters_habitat_thresholds.csv`.

| column | meaning |
|---|---|
| `variant` | name, and the persist schema suffix (`score284_<variant>`) |
| `species_code` | the row of the thresholds table to change |
| `column` | the threshold column to change |
| `value` | the new value |
| `flag` | which `streams_habitat_<sp>` flag the step moves: `spawning` or `rearing` |
| `obs_stage` | which observations count in the band: `any`, `spawn` or `rear` (the stage the threshold was calibrated on) |
| `step_from` | the neighbour nearer `default` in the ladder; the band is the difference between the two |
| `equals_bundle` | a shipped bundle whose thresholds this variant must equal byte for byte (checked at build) |

## `wsg_roles.csv`

One row per WSG × species: `held_out` WSGs decide the rule; `in_sample` WSGs (among the
WSGs the step-1 percentiles came from) are reported beside it.
