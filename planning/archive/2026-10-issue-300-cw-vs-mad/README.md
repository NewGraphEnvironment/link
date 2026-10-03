# #300 — Score the discharge (`mad`) habitat model against observations

## Outcome

This compared the `cw` and `mad` habitat models on the habitat fish use, at
`default_tuned`'s landed MAD ranges. The harness gained three things:

- **A `--base` bundle.** The base row is the one with no `step_from`, and it must equal
  `--base`.
- **Model-only variants:** no threshold cell changed, the species' WSGs moved to `mad`.
- **A score section** that reads the `cw`-only and `mad`-only bands against the habitat
  both models keep, within stream-order classes.

The rule was fixed in the research doc before any build.

What was learned: **`mad`'s most-used loss is not a threshold.** It is river-polygon main
stems (edge type 1250) with no discharge value, where fish are found at 2.7× the core
rate. Below its minimum, `mad` drops small water that fish use at about a fifth of the
size-matched rate (BT). So the minimum does what a minimum should, and the discharge
layer must be filled on main stems before any group moves to `mad`.

The size adjustment changed BT's reading from 0.33 to 0.71. It could do nothing for GR,
which has no small-water core. Results and reading:
[`research/habitat_thresholds.md`](../../../research/habitat_thresholds.md),
"`cw` against `mad`".

## Measurement

Held-out WSGs, stage `any`. The ratio of record is size-adjusted: found ÷ expected at
the core's rate per stream-order class.

| Species × flag | `cw`-only ratio | `mad`-only ratio | Reading |
|---|---|---|---|
| BT rearing | 0.71 (unadj. 0.33) | underpowered | `cw`-only habitat |
| BT spawning | 0.69 | 0.42 | `cw` closer |
| GR rearing | 0.49 (no size control possible) | underpowered | `cw`-only not habitat |
| GR spawning | 0.72 | underpowered | `cw`-only habitat |
| RB rearing | 1.49 | 0.54 | each misses habitat the other finds |
| RB spawning | 2.33 | 0.35 | `cw` closer |

**What `mad` costs against `cw`** at the landed pair. This replaces #302's lower bounds.

| Species | Rearing | Spawning |
|---|---|---|
| BT | −35.7 % | −29.0 % |
| GR | −82.5 % | −73.3 % |
| RB | −4.5 % | +11.9 % |

**The `cw`-only band splits in two.** For BT rearing:

| Part | km | Locations | Rate |
|---|---|---|---|
| No discharge | 504 | 204 of 246 | 40 per 100 km, against the core's 15 |
| Below the MAD minimum | 4,459 | 41 | orders 1–3: 0.22 of the size-matched core |

**Checks:**

- Band identity holds per WSG within 0.01 km.
- Re-scoring #302 and #284 reproduced their committed outputs, to ≤ 9.5e-15 relative.
- #302's 18 bundles regenerate byte for byte (`--step=bundles`).

**Wrong turns, kept:**

- The #284 regression silently never ran the first time. `&` bound the whole `&&` chain,
  so its subshell had neither the scratch path nor the repo as its working directory.
- The first full build stopped at "No space left on device".
  - I first sent the operator to Docker Desktop's disk setting. The database actually runs
    in colima, so that was the wrong app.
  - `colima start --disk 300` fixed it, and nothing was dropped.
- The plan review found what the plan had missed: a GR core with almost no small water,
  which forced the class-merge rule before the run, and the main-stem discharge gap.
  Three code-check rounds followed: round 1 found 3 issues, and rounds 2 and 3 were clean.

## Evidence

- `data-raw/logs/habitat_score_300/*`
  - build: `build_20261003_full.log`; the disk-full attempt is `build_20261002_full.log`
  - PARS pre-flight: `*_preflight_pars.log`
  - score: `score_20261003.log`, `model_*.csv`, `habitat_change.csv`
- `review-*.md` in this directory: the plan review and code-check rounds 1–3

Closed by: PR for #300 (branch `300-score-the-discharge-mad-habitat-model-ag`)
