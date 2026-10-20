# access_disagree_349 — evidence for link#349

`streams_habitat_<sp>.accessible` (fresh's, classify time) against
`streams_access.access_<sp>` (link's, province-wide), by mechanism.

| path | what | producer |
|---|---|---|
| `summary.md`, `classes.csv`, `groups_blocked.csv`, `residual_groups.csv`, `side_effects.csv` | `fresh_default`, all 241 groups, run `20261017_004619-3f4c713b` (before #349) | `data-raw/access_disagree_349.R` |
| `overrides_scope_time.csv` | the override step over the group's own vs every group's observations, DUNC and CARP | `data-raw/overrides_scope_time_349.R` |
| `baseline/` | `fresh_default`, UPCE + CARP + DUNC only | `access_disagree_349.R --wsgs=UPCE,CARP,DUNC` |
| `before/` | scratch `fresh_349`: the three groups rebuilt at this branch (province-wide lifts, RB rule) with the gate off (`LNK_HABITAT_GATE=0`) | `verify_build_349.sh` |
| `after/summary.md` … | `fresh_349` after `wsg_recompute_one.R` (which settles) | `verify_build_349.sh` |
| `after/access_transitions.csv`, `rollup.csv`, `gate.csv`, `bcfp_dunc_bt.csv` | `fresh_349` against `fresh_default`, per group | `data-raw/access_verify_349.R` |

`fresh_349` was seeded with `fresh_default`'s barriers and overrides; the groups were built
downstream first (UPCE, which holds the Peace rows, then CARP, then DUNC) under `default`.
