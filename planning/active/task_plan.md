# Task: Main stems with no discharge drop out of mad habitat (#305)

## Problem

`fwa_stream_networks_discharge` has no value on many edge type 1250 segments (main flow through double-line river polygons). Under `mad` a NULL `mad_m3s` fails every size test, so these reaches drop out of stream habitat. #300 measured this as `mad`'s largest loss of used water: for BT rearing on #300's held-out groups, 504 km holding 204 of 246 observation locations, at 2.7x the core rate. Below the MAD minimum, `mad` drops only small water that is little used (BT 0.22 of the size-matched core rate). See `research/habitat_thresholds.md`, "`cw` against `mad`", and `data-raw/logs/habitat_score_300/model_reason.csv`.

**Decision (operator, 2026-10-06):** a network fill in link — no fresh change, no outside data — then re-score with #300's harness.

## Design

- **One source of truth for discharge.** Today it is read in four places:
  - prepare: `R/lnk_pipeline_prepare.R:694`, through `fresh::frs_col_join()`, which
    accepts a `(subquery)` as `from`;
  - the validator: `R/lnk_habitat_validate.R:679` and `:982`, through
    `.lnk_hv_discharge_tbl()`;
  - the score harness: `data-raw/habitat_variants_score.R:605-624`.

  A new internal SQL builder, `.lnk_discharge_sql(aoi, fill)`, returns a subquery
  `(linear_feature_id, mad_m3s, mad_m3s_source)`. All four read it, so a filled value
  can never disagree between classify and the scoring.
- **Fill rule (edge 1250 only).** Where a segment has no value:
  1. take the nearest valued segment **upstream** on the same `blue_line_key` (a lower
     bound, conservative against the MAD minimum);
  2. else the nearest valued segment **downstream** on the same line;
  3. else take a value across lines downstream (`fwa_downstream`), if Phase 1 measures
     that it is accurate enough;
  4. else leave it NULL.

  `mad_m3s_source` is `modelled`, `fill_upstream`, `fill_downstream`,
  `fill_downstream_line` or NULL. Phase 1 validates the rule by masking valued 1250
  segments, filling them, and measuring the error before any code lands. If upstream
  first proves worse than downstream first, the order is swapped and the swap is
  reported.
- **A bundle knob, not a global.** `cfg$pipeline$discharge_fill`. It is `true` in
  `default` (inherited by `default_tuned`) and absent, meaning FALSE, in `bcfishpass`,
  so the parity bundle keeps raw discharge. The run log records it.
- **No storage change.** `mad_m3s` and the new `mad_m3s_source` stay on the working
  streams only, as #286 decided. The persist shape is unchanged.

## Phase 1: Count and validate the fill (no package code)
- [ ] `data-raw/discharge_fill_count.R`:
  - NULL km by edge type × order × WSG, absent rows against NULL values, covered WSGs
    only;
  - the same restricted to #300's held-out WSGs and to BT/GR/RB `cw`-only rearing and
    spawning (from `score300_*`).
  - Log under `data-raw/logs/discharge_fill_305/`.
- [ ] Root cause of the absent 1250 rows: sample a few in one WSG, and record whether
  the discharge source simply skips river-polygon watersheds. Diagnosis only.
- [ ] Fill accuracy: mask valued 1250 segments, fill each tier, and report the
  median / P90 absolute and relative error, plus how often the fill crosses a species'
  MAD minimum wrongly.
- [ ] Fill reach: km per tier on covered WSGs and on #300's `cw`-only bands.
- [ ] Write the results to `research/habitat_thresholds.md` (new subsection under
  "`cw` against `mad`") and correct the issue body's "most" with the numbers.

## Phase 2: Shared discharge source + fill (tests first)
- [ ] Tests (live-DB, `skip_if_no_db()`, a small WSG such as ADMS plus one with 1250
  main stems):
  - fill off returns the raw table's values;
  - fill on: valued segments are unchanged, every filled value comes from the rule's
    tier, and edge types other than 1250 are untouched;
  - prepare and the validator agree on `mad_m3s` per segment.
- [ ] `.lnk_discharge_sql()` (new `R/lnk_discharge.R`, internal).
- [ ] prepare joins `mad_m3s` + `mad_m3s_source` through it, gated on
  `cfg$pipeline$discharge_fill`.
- [ ] Validator: replace both reads of `.lnk_hv_discharge_tbl()` with the builder,
  with fill set from the cfg it is given.
- [ ] `discharge_fill` in `default/config.yaml`, the dictionary entry if config knobs
  have one, and the run-log record (`R/lnk_log.R:206`).
- [ ] RUNBOOK §7 "Channel width or discharge" gets the fill. Remove the docs that say
  a NULL drops out silently, or qualify them as fill-off behaviour.

## Phase 3: Harness reads the same source
- [ ] `data-raw/habitat_variants_score.R`: the `model_reason` discharge read goes
  through the builder, and a `mad_filled` split reports how much of each band rests on
  a filled value.
- [ ] Prove the harness is unchanged with the fill off: re-scoring #300's existing
  `score300_*` schemas reproduces `data-raw/logs/habitat_score_300/` byte for byte.

## Phase 4: Rebuild and re-score
- Run decisions, stated here for approval:
  - config `default_tuned` (fill on);
  - `--base=default_tuned` and `variants_300.csv`, on #300's 20-WSG closure,
    with roles from `wsg_roles_300.csv`;
  - species BT, GR, RB and KO;
  - new prefix `score305`, `--floor=expected`;
  - run detached, about 70 min.
- [ ] Pre-flight PARS, then the full build. Assert the base `cw` habitat digest equals
  #300's: the fill must not move `cw`.
- [ ] Score. Diff `model_verdict.csv`, `habitat_change.csv` and `model_reason.csv`
  against #300's. Does any `cw`-only verdict change? How much `mad_null` is left?
- [ ] Results go to `research/habitat_thresholds.md` and the CLAUDE.md status. The
  archive README gets Measurement + Evidence.

## Validation
- [ ] Tests pass (`devtools::test()`), lint clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

## Verification end-to-end
- Phase 1 numbers reproduce on re-run.
- Fill off: the #300 re-score is byte-identical.
- Fill on: the `cw` base digest is unchanged; `mad_null` km in the `cw`-only bands
  drops by the amount Phase 1 predicted.
