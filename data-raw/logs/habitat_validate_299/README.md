# #299 live verification — validator scores each group on its own model

Local docker fwapg (:5432), 2026-10-02 UTC. Config `default`, ADMS, species CH, CO, BT
(DV pooled per `species_pooling.csv`), buffer 0. fresh 0.36.2. Branch runs are the
working tree on top of `be3be30`, before the Phase 2–3 commit (the `sha=` in their
headers is HEAD, not the tree that ran). Main runs are a detached worktree at `4df1ffc`.

- `model_mad.R` models ADMS with the `default` bundle into the scratch persist schema
  `zz299_mad`, with its method table swapped for `method_adms_mad.csv` (ADMS on `mad`),
  `mapping_code = TRUE`. 39,422 segments, 2.8 min. `km.sql` →
  `20261002_adms_mad_km.txt`: stream spawning / rearing km BT 0 / 0, CH 256.4 / 317.5,
  CO 292.4 / 317.8. BT keeps 318.2 km of lake and wetland rearing.
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
reports as `post_predicate` ("removed by clustering or access gating"), not as a
disagreement. The discriminating numbers are the reasons, in locations
(`20261002_adms_compare.txt` §3). "All" tests every location against that stage's
predicate; "staged" keeps only locations whose records carry the stage, as the summary's
stage rows and the driver's `misses.csv` count them:

| species | reason column | main (cw predicates) | branch (mad predicates) |
|---|---|---|---|
| BT, 37 locations | spawn, all | 24 `post_predicate`, 6 `fails_gradient`, 2 `fails_width`, 1 `width_null`, 2 `fails_gradient_and_width`, 2 `rule_excludes` | 27 `no_mad_threshold`, 8 `fails_gradient_and_width`, 2 `rule_excludes` |
| BT | spawn, staged (1) | 1 `post_predicate` | 1 `no_mad_threshold` |
| BT | rear, all | 27 `post_predicate`, 3 `fails_gradient`, 3 `fails_width`, 1 `width_null`, 1 `fails_gradient_and_width`, 2 captured | 31 `no_mad_threshold`, 4 `fails_gradient_and_width`, 2 captured |
| BT | rear, staged (6) | 4 `post_predicate`, 2 `fails_width` | 6 `no_mad_threshold` |
| CO, 46 locations | spawn, all | 2 `width_null` | 2 `fails_width` |
| CO | rear, all | 2 `width_null`, 2 `post_predicate` | 4 `fails_width` |
| CO | rear, staged (13) | 1 `width_null` | 1 `fails_width` |
| CH, 11 locations | spawn, all | 1 `post_predicate` | 1 `fails_width` |

On the 27 BT locations main calls `post_predicate` against rearing, it tells a reader
the predicate passed and clustering or gating removed them. On a `mad` group they were
never in the predicate, because BT has no MAD range. Main's CO `width_null` are NULL
channel widths the `mad` run never tested; the branch tests their discharge (0.0127 and
0.018 m³/s on the two spawn misses), which is below CO's minimum.

Scratch schemas `zz299_mad` and `zz299_w_adms` were dropped after the runs; the RDS
files were not kept.
