# #302 — MAD (discharge) ranges for BT, GR, KO and RB

## Outcome

`default_tuned` now carries mean-annual-discharge ranges for the four species that no
bundle gave one, so a watershed group moved to the `mad` model keeps their stream
habitat. The values are inert while every group is on `cw`.

How it was done:

- **Measurement.** `data-raw/query_habitat_thresholds_mad.R` measures discharge at fish
  observations. It uses `lnk_habitat_validate()` as the instrument, with every
  calibration group put on `mad`.
- **Harness.** The #284 variants harness gained MAD ladders: `model`/`set` columns, an
  anchor rung from cw to `mad`, `_min` direction, a core made of the rungs only,
  `--floor`, and a derived working prefix.
- **Scoring.** A rule fixed before any build scored each candidate on held-out groups.

Each rung was decided like this:

- **BT, GR and RB rearing, and BT and GR spawning:** every P10 → P05 loosening was
  refused, so they land at P10.
- **RB spawning:** P05 was taken.
- **KO:** it has no held-out group, so it lands its unscored candidate.

At the landed values a `mad` group keeps at least a third less BT rearing, and four-fifths
less GR rearing, than `cw` does. Stream size and sampling effort are not yet separated,
and that is the next tuning before any group moves to `mad`. The verdict, method,
literature and results are in [`research/habitat_thresholds.md`](../../../research/habitat_thresholds.md),
"MAD (discharge) ranges for BT, GR, KO and RB (#302)".

What was learned along the way:

- **Classifiers must come from fresh's compiled SQL, not from `rules.yaml`.** fresh's rear
  predicate ignores `wetland_ha_min`, and its `L` rules reach reservoirs.
- **`rearing` and the lake/wetland bucket columns differ under a rear range.** A rear
  range gates `lake_rearing` and `wetland_rearing`, but not `rearing`.
- **A size ladder's core must not include the cw base.** The base cuts on a width floor,
  and NULL widths fail it.
- **Prose numbers must be computed over the population the claim is about.** Three
  rounds of review each found the same slip: a number over one segment set cited for a
  different one.

## Measurement

Calibration: 46 `fresh_default` WSGs with discharge (`a7f919e`). P05 values in m³/s:

| Species | Spawning | Rearing |
|---|---|---|
| BT | 0.027 (any-stage fallback) | 0.027 |
| GR | 0.095 (any-stage fallback) | 0.095 |
| KO | 0.57 | — |
| RB | 0.011 | 0.0094 |

- BC-native `cw` equivalents: 1.5 m ≈ 0.021, 2 m ≈ 0.041 and 4 m ≈ 0.20 m³/s. That
  agrees with Woll et al. 2017's Alaskan relation.
- Score on held-out WSGs (`c2fed37`; 20-WSG closure; 18 variants; build 145 min):
  - The P10 → P05 bands are used at 0.12–0.46 of the core rate. RB spawning is the
    exception, at 0.80.
  - The small water P05/P02 restore is used at 0.08 (BT rear) to 0.47 (GR spawn) of the
    core rate.
  - Landed rearing against `cw`: BT −33 %, GR −82 % (both lower bounds) and RB −4 %.
- **Wrong turns kept:**
  - I first read the low ratios as a sampling artefact, citing elevation-adjusted
    figures that described only the residual band. Review disproved it.
  - Round 1 of the harness review would have scored a `_min` ladder backwards.
  - The #284 regression caught a `paste0()` zero-length crash.

## Evidence

- `data-raw/logs/habitat_thresholds_302/*` (Phase 1 and FISS)
- `data-raw/logs/habitat_score_302/*` (power, build, score)
- `review-*.md` in this directory (plan review, 9 code-check rounds), `literature.md`

Closed by: PR for #302 (branch `302-tune-mad-discharge-thresholds-for-bt-gr-`)
