# Task: Main stems with no discharge drop out of mad habitat (#305)

## Problem

`fwa_stream_networks_discharge` has no value on many edge type 1250 segments (main flow through double-line river polygons). Under `mad` a NULL `mad_m3s` fails every size test, so these reaches drop out of stream habitat. #300 measured this as `mad`'s largest loss of used water: for BT rearing on #300's held-out groups, 504 km holding 204 of 246 observation locations, at 2.7x the core rate. Below the MAD minimum, `mad` drops only small water that is little used (BT 0.22 of the size-matched core rate). See `research/habitat_thresholds.md`, "`cw` against `mad`", and `data-raw/logs/habitat_score_300/model_reason.csv`.

**Decision (operator, 2026-10-06):** a network fill in link — no fresh change, no outside data — then re-score with #300's harness.

## Design (revised 2026-10-06 after Phase 1 and plan review — `review-plan.md`)

- **One source of truth for discharge.** `.lnk_discharge_sql()` (`R/lnk_discharge.R`)
  returns `(linear_feature_id, mad_m3s, mad_m3s_source)`, enumerating lines from
  `fwa_stream_networks_sp` (absent rows included). Consumers: prepare (onto the working
  streams), the validator (both reads, through one `pg_temp` table per call), the score
  harness's `model_reason`. The #302 calibration scripts stay on raw discharge by design.
- **Fill rule (edge 1250 only):** `fill_upstream` (nearest valued line upstream on the same
  `blue_line_key`, any edge type, any WSG, never itself; a lower bound) → `fill_downstream`
  (same line, upper bound) → `fill_tributary_max` (largest value on any line upstream via
  `fwa_upstream()`, never its own `blue_line_key`; a lower bound) → NULL. A downstream
  line is never used: it is the receiving river (the Beatton would take the Peace).
- **Knob:** `cfg$pipeline$discharge_fill`, `true` in `default_tuned` only (S2: `default`'s
  hash does not move); absent = FALSE (`default`, `bcfishpass`, the `extends: ~` bundles).
- **Where it applies** (code-check rounds 2–3): `.lnk_discharge_fill_applied(cfg, w)` — the
  knob AND (`w` on `mad` in cfg's method table OR a rule-level `mad` in fresh's parsed
  rules). Only in groups the discharge table covers. One rule for prepare, log, validator
  (per group), build and score.
- **Recorded state:** `<schema>.log.discharge_fill` per WSG; the validator stops when a
  logged WSG disagrees with its `cfg`. The variants harness records it in `built.csv` and
  the score sets each variant's fill from there (absent = FALSE).
- **Type:** prepare adds `mad_m3s double precision` + `mad_m3s_source text` itself
  (`frs_col_join()` makes a subquery's columns `text`).
- **No persist change.** Working streams only, as #286 decided.

## Phase 1: Count and validate the fill
- [x] `R/lnk_discharge.R`: the builder + candidates SQL (moved here from Phase 2 so the
  measurement runs the shipping SQL)
- [x] `data-raw/discharge_fill_count.R`: coverage by edge type × order × state, per-WSG
  1250, held-out band reach (`score300_*`); log `data-raw/logs/discharge_fill_305/`
- [x] Root cause of absent 1250 rows (diagnosis only)
- [x] Fill accuracy: single-line masking, ≥ 10 km long-gap sample, tributary sample; MAD
  minimum crossings
- [x] Fill reach per tier: covered WSGs and #300's `cw`-only bands
- [x] Results to `research/habitat_thresholds.md`; issue body corrected ("most" → numbers)

## Phase 2: Wire the fill (tests first)
- [x] Tests: builder off = raw table; on: valued lines unchanged, 1250-only, absent-row line
  filled, tier per rule, AOI-independent value; working `mad_m3s` is `double precision`
  on and off; prepare and validator agree; validator stops on a fill mismatch with the log
- [x] prepare: thread `cfg` into `.lnk_pipeline_prep_network()`; add typed columns; fill
  per `cfg$pipeline$discharge_fill`
- [x] Validator: one `pg_temp` discharge table per call, scoped by the scored lines; both
  reads use it; `mad_m3s_source` in the obs output; log check
- [x] `<schema>.log.discharge_fill` column (`cols_log`, migrated by align)
- [x] `discharge_fill: true` in `default_tuned/config.yaml`; `lnk_config()` doc;
  inheritance test
- [x] RUNBOOK §7 + validator/classify docs: the fill, and NULL-drops-out as fill-off

## Phase 3: Harness
- [x] `habitat_variants_build.R`: `built.csv` gains `discharge_fill`; before a `mad`
  variant classifies, refill the working streams' `mad_m3s` from the builder per the
  variant's cfg
- [x] `habitat_variants_score.R`: each variant's fill from `built.csv` (absent = FALSE);
  `model_reason` reads the builder; `mad_m3s_source` split reported
- [x] Regression: re-scoring #300 (`score300_*`, its `built.csv`) reproduces
  `data-raw/logs/habitat_score_300/` — integer/character identical, numeric within 1e-12
  relative

## Phase 4: Re-score on #300's segmentation
- Run decisions: `default_tuned` (fill on); reuse `score300_default_tuned` +
  `working_score300_*` (no base rebuild: the diff is the fill alone); `variants_305.csv` =
  #300's four `mad` variants renamed `*_fill` (new schemas, #300's kept);
  `--step=variants --prefix=score300_ --out=data-raw/logs/habitat_score_305`,
  #300's `base_habitat_digest.csv` copied in; score `--base=default_tuned --floor=expected`;
  roles `wsg_roles_300.csv`
- [x] Build variants (base re-classify digest must match #300's)
- [x] Score; diff `model_verdict`, `habitat_change`, `model_reason` against #300; how much
  `mad_null` remains, and does any `cw`-only verdict change
- [x] Results to `research/habitat_thresholds.md`, CLAUDE.md status; archive README with
  Measurement + Evidence

## Validation
- [x] Tests pass (`devtools::test()`: 2441 pass, 0 fail, 16 warnings as baseline); lint: no new non-indentation lints in touched files
- [x] `/code-check` on the code commit `312e195` (4 rounds, enumeration-terminated); the results commit is logs and prose only
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push`

## Verification end-to-end
- Phase 1 numbers reproduce on re-run.
- Fill off (from `built.csv`): the #300 re-score reproduces within the stated tolerance.
- Fill on: the base re-classify digest equals #300's; `mad_null` km in the `cw`-only bands
  drops by what Phase 1's `band_reach.csv` predicts (same segmentation, same SQL).
