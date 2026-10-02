# Task: Score the discharge (mad) habitat model against observations, as #284 did for gradient (#300)

Since #286, a bundle can put a watershed group on the discharge model (`mad`). The two models classify different segments, and nothing yet says which is closer to where fish are observed. Fewer habitat segments under `mad` is not by itself a defect. It may be less conservative, or more realistic, and the evidence should decide.

## Context (plan approved 2026-10-02)

Since #286, a bundle can put a watershed group on `mad`. #302 gave BT, GR, KO and RB
MAD ranges in `default_tuned`, and its P10 anchor bands showed that `mad` drops a third or
more of BT stream rearing and four-fifths of GR. Those bands have two limits:

- **Wrong core.** Their core was the `mad` rungs, not the habitat both models keep.
- **Untested pair.** The landed spawning and rearing pair was never built: the P10 rows are
  lower bounds.

Stream size and sampling effort are also confounded. This work answers, per species and
stage, where `mad` instead of `cw` adds or drops habitat that fish use, controlling for
stream size, before any bundle moves a group.

**Decisions taken at the gate (2026-10-02):**

- **Species.** BT, GR and RB are scored on #302's held-out WSGs, from `wsg_roles_302.csv`.
  KO is reported in-sample only. Species whose ranges came from bcfishpass go to a
  follow-up issue.
- **Size proxy.** Stream order, in classes 1, 2, 3 and 4+. Neither model tests it, so it
  favours neither.
- **Verdict of record.** The size-adjusted reading: locations found against those
  expected at the core's rate, order class by order class. A band is habitat when that
  ratio is at least 0.5 and at least 10 locations are expected. The unadjusted ratio is
  written beside it.

**Build.** A fresh build under `--prefix=score300_` with base `default_tuned`, over #302's
20-WSG closure. That is about 60 min for the base and about 10 min per variant.

`score302_*` cannot be reused for two reasons:

- It was classified under `default`, where BT `rear_gradient_max` is 0.1049 and there are
  no MAD ranges.
- The resume gate requires a clean log row at this HEAD.

## Phase 1: Rule and inputs, fixed before any code runs
- [x] `research/habitat_thresholds.md`, new section "cw vs mad (#300)": method and rule.
  - **Core:** habitat both the `cw` base and the `mad` variant keep.
  - **Bands:** `cw`-only and `mad`-only, for each flag (spawning and rearing).
  - **Stages:** the decision reads stage `any`; spawn and rear stages are reported.
  - **Rule:** size-adjusted ratio of record, as stated in Context.
  - **Reading:** what each of the four combinations means (only `cw`-only is habitat,
    only `mad`-only is, both, neither).
  - **Power:** from #302's anchor rows, `cw`-only is well powered (BT 4,505 km rearing).
    `mad`-only is thin (BT 193 km, GR 14 km), so expect "keep (expected < 10)" there.
- [x] `data-raw/habitat_score/variants_300.csv`: base `default_tuned` (cw), plus
  model-only rows `bt_mad`, `gr_mad`, `rb_mad` and `ko_mad`. Each has an empty `column`,
  `model=mad` and `step_from=default_tuned`.
- [x] `data-raw/habitat_score/wsg_roles_300.csv` (KO in KOTL and PARS, both in-sample): `wsg_roles_302.csv`, plus KO
  `in_sample` rows for any KO-present WSG in the closure. Leave KO out if there are none,
  and record that.

## Phase 2: Harness, build side (`data-raw/habitat_variants_build.R`)
- [ ] Add `--base=<bundle>` (default `default`). It replaces `lnk_config("default")`.
  Thin bundles get `extends: <base>`, and the stamp records the base. Under #284's and
  #302's own `--variants`, a `--base` other than `default` stops.
- [ ] The base is the row with an empty `step_from`, not the row with an empty `column`.
- [ ] Allow a **model-only variant**: empty `column`, `model=mad`, `step_from` = base, no
  `set`.
  - Its thin bundle carries only a method table and is checked to differ from the base in
    0 threshold cells.
  - Any other empty-`column` row stops: one on `cw`, one with a `set`, or one stepping from
    a non-base variant.
- [ ] Update the README for `--base`, model-only rows and `variants_300`.

## Phase 3: Harness, score side (`data-raw/habitat_variants_score.R`)
- [ ] Add `--base`, mirrored from the build. Use it in `cfg_of()` and the stamp.
- [ ] The `built.csv` and bundle verification branches for model-only variants: 0
  threshold cells differ, and the method table puts the WSGs on `mad`. Model-only
  variants are excluded from `steps`, so ladders, the walk, taper, elevation and bridge
  are unchanged.
- [ ] New model-comparison section. Per model-only variant × flag × stage, call
  `lnk_habitat_validate_band(schema = <variant>, schema_ref = <base>, schema_core = c(base, variant))`.
  - `added` = `mad`-only; `removed` = `cw`-only.
  - Write `model_bands.csv` and `model_bands_pooled.csv`.
- [ ] Size control: classify each segment of the base network as core, `cw`-only or
  `mad`-only, with its `stream_order` class.
  - Pool rates per class; expected = band km × the core's rate in the same class.
  - Write `model_size.csv` (rates by class) and `model_verdict.csv`.
  - `model_verdict.csv` holds both ratios and both floors, with the size-adjusted decision
    as the decision of record.
- [ ] `habitat_change.csv` already covers model-only variants (km under `cw` vs `mad`).
  Confirm the rows appear.

## Phase 4: Regression, before the build
- [ ] Re-score #302 on the existing `score302_*` schemas
  (`--variants=variants_302.csv --base=default --prefix=score302_ --floor=expected`) into a
  scratch `--out`.
  - All committed `data-raw/logs/habitat_score_302/` outputs must reproduce, up to known
    double-precision ulps (#293).
  - Do the same for #284's `score284_*`.
- [ ] Negative checks: each malformed `variants_300` shape stops with its message.
  - a model-only row on `cw`
  - a model-only row with a `set`
  - a model-only row stepping from a non-base variant
  - a mismatched `--base` between build and score
- [ ] `/code-check`, with three review rounds, on the harness diff.

## Phase 5: Build and score
- [ ] Commit, then launch the build detached at a clean HEAD (`--variants=variants_300.csv
  --roles=wsg_roles_300.csv --base=default_tuned --prefix=score300_
  --out=data-raw/logs/habitat_score_300`). Pre-flight LHAF first, then all.
- [ ] Score with `--floor=expected`. Commit the logs and stamps under
  `data-raw/logs/habitat_score_300/`.

## Phase 6: Read and record
- [ ] Results go in the research section, per species × flag × stage:
  - `cw`-only and `mad`-only km
  - found, expected, raw and size-adjusted ratios, and the decision
  - landed `cw` vs `mad` km (this replaces #302's lower bounds)
  - KO in-sample
  - one line that, under `default`, BT, GR, KO and RB lose all stream habitat on `mad` by
    construction
- [ ] Update the issue #300 body with the outcome. Update CLAUDE.md status and NEWS.

## Validation

- [ ] Tests pass (regression re-scores reproduce #284 and #302)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Critical files
- `data-raw/habitat_variants_build.R` (base at L135, `lnk_config("default")` at L214,
  `write_bundle()` at L241)
- `data-raw/habitat_variants_score.R` (base and verification at L108–278, `steps` at L424,
  `core_of()` at L452, elevation pattern at L762–803, which the size control reuses)
- `R/lnk_habitat_validate_band.R`: reused as is (`schema_core` already takes any set)
- `data-raw/habitat_score/README.md`, `research/habitat_thresholds.md`
