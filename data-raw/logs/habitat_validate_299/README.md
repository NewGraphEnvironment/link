# #299 live verification — validator scores each group on its own model

Local docker fwapg (:5432), 2026-10-02 UTC. Config `default`, ADMS, species CH, CO, BT
(DV pooled per `species_pooling.csv`), buffer 0. fresh 0.36.2. Branch runs are the
working tree on top of `be3be30`, before the Phase 2–3 commit (the `sha=` in their
headers is HEAD, not the tree that ran). Main runs are a detached worktree at `4df1ffc`.

- `model_mad.R` models ADMS with the `default` bundle into the scratch persist schema
  `zz299_mad`, with its method table swapped for `method_adms_mad.csv` (ADMS on `mad`),
  `mapping_code = TRUE`. 39,422 segments, 2.8 min. Stream km: BT 0 / 0, CH 256.4
  spawning / 317.5 rearing, CO 292.4 / 317.8.
- `validate_run.R` runs `lnk_habitat_validate()` from a given repo, swapping the method
  table on the same `cfg` object it validates with.
- `compare.R` compares the four runs: `20261002_adms_compare.txt`.

## Result

| check | result |
|---|---|
| cw no-change: `fresh_default` ADMS, branch vs main | `observations` identical apart from the new columns; `summary` identical apart from `model` (94 locations) |
| `mad_m3s` on mad-group locations | 94 of 94 |
| persisted TRUE, re-built predicate FALSE (outside UHC) | 0 on branch, **and 0 on main**: this metric does not discriminate (see below) |

**The planned metric was the wrong direction.** On a `mad` run, main re-builds the *cw*
predicate. For BT it is looser than the `mad` one that classified the run, so it passes
where classify failed. That is persisted FALSE with predicate TRUE, which the validator
reports as `post_predicate`, not as a disagreement. The discriminating numbers are the
reasons:

| species | stage | main (cw predicates) | branch (mad predicates) |
|---|---|---|---|
| BT | spawn | 24 `post_predicate`, 6 `fails_gradient`, 2 `fails_width`, 1 `width_null`, 2 `fails_gradient_and_width`, 2 `rule_excludes` | 27 `no_mad_threshold`, 8 `fails_gradient_and_width`, 2 `rule_excludes` |
| BT | rear | 27 `post_predicate`, 3 `fails_gradient`, 3 `fails_width`, 1 `width_null`, 1 `fails_gradient_and_width` | 31 `no_mad_threshold`, 4 `fails_gradient_and_width` |
| CO | spawn | 2 `width_null` | 2 `fails_width` |
| CO | rear | 2 `width_null`, 2 `post_predicate` | 4 `fails_width` |
| CH | spawn | 1 `post_predicate` | 1 `fails_width` |

Main tells a reader that 51 BT misses were removed by clustering. On a `mad` group they
were never in the predicate, because BT has no MAD range. Main's CO `width_null` are
NULL channel widths the `mad` run never tested; the branch tests their discharge, which
is below the minimum.

Scratch schema `zz299_mad` and the RDS files were not kept.
