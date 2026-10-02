# habitat_score

The inputs for scoring habitat-threshold variants against fish observations (#284 step 5,
the MAD ranges of #302, and `cw` against `mad` in #300).
The rule and the reasoning behind it are in `research/habitat_thresholds.md`, under
"Scoring design". Two scripts use these files:

- `data-raw/habitat_variants_build.R` models every variant on one shared segmentation.
- `data-raw/habitat_variants_score.R` scores the variants and applies the rule.

Everything species-specific is here, and neither script names a species.

## `variants.csv`

One row per variant. The row with an empty `step_from` is the base. Its `equals_bundle`
names the bundle it is, and both scripts take that bundle as `--base` (default `default`;
#300's is `default_tuned`), stopping when the two disagree. Every other row changes
exactly one cell of the base's `parameters_habitat_thresholds.csv`, except a model-only
row (below).

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
| `model` | optional (#302): `cw` (empty) or `mad`. A `mad` variant's bundle also carries a `parameters_habitat_method.csv` with every WSG holding a role for its species on `mad` |
| `set` | optional (#302): further cells the variant fixes, `col=value;col=value`, held constant along a ladder (a MAD rung's open maximum; the spawning range a clustered rearing ladder needs) |

### MAD ladders (#302)

A species with no MAD range has no "current value" to walk out from: under `mad` it has no
stream habitat at all. So a MAD ladder starts with an **anchor**, a rung that steps from the
`cw` base straight to `mad` at the tightest candidate. The score marks it
`take (anchor: model change)`, reports its bands both ways (what `mad` keeps that `cw` drops,
and the reverse) and decides nothing with them. The walk then scores the loosening rungs
beyond it as #284 did. The core is the habitat every ranged rung keeps: the `cw` base is
left out of it, because it tests a width floor (and fails NULL widths) that no `mad` rung
tests, so a core cut by it would differ from the bands on an axis no step is about.

A `mad` variant's `set` may name only `*_mad_min` / `*_mad_max` cells, so the rungs carry
`default`'s gradient cutoffs and every band differs from its neighbour in discharge alone. (`default_tuned`'s BT
`rear_gradient_max` 0.1349 was scored on its own, in #284.) The score checks that every
`set` cell holds its value, that a ladder holds `set` fixed past its anchor, that each step
reads the same species, column, flag and stage as its `step_from`, and that each bundle's
method table puts its WSGs on the variant's `model`.

### Model-only variants (#300)

A row with an empty `column` that is not the base changes the habitat model and nothing
else. It must be on `mad`, step from the base, name its species, and leave `value`,
`flag`, `obs_stage`, `equals_bundle` and `set` empty. No row may step from it. Its bundle carries the base's thresholds unchanged and a method
table putting every WSG with a role for its species on `mad`, so spawning and rearing
switch together, as a real switch would.

It is not a ladder step. The score compares it with the base in both flags: the core is
the habitat both keep, the `removed` band is what only `cw` keeps and the `added` band
what only `mad` keeps. Each band is read against the core within stream-order classes
(1, 2, 3, 4+, merged upward while a class's core holds fewer than 10 locations), and the
decision of record is on the size-adjusted ratio. The outputs are `model_bands.csv`,
`model_bands_pooled.csv`, `model_size.csv`, `model_reason.csv` and `model_verdict.csv`.

`habitat_variants_build.R --step=bundles` writes the variant bundles to `--out` and stops,
touching no schema. It is how a harness change is checked against a committed build's
bundles. The rule
is in `research/habitat_thresholds.md`, "`cw` against `mad`".

The inputs for #300 are `variants_300.csv` and `wsg_roles_300.csv` (#302's roles plus KO,
in-sample only).

A second scoring run gets its own `--prefix`; its working networks are then
`working_<prefix><wsg>` (#284's, under `score284_`, stay `working_score_<wsg>`).

The inputs for #302 are `variants_302.csv` and `wsg_roles_302.csv`.

## `wsg_roles.csv`

One row per WSG × species: `held_out` WSGs decide the rule; `in_sample` WSGs (among the
WSGs the step-1 percentiles came from) are reported beside it.
