# Plan review — #302 (Plan agent, 2026-10-02)

Read-only agent; findings returned in reply and written here by the parent.

## Blockers
1. **Score reads `*_min` step direction backwards** (`habitat_variants_score.R`, `value > value_from` = added). A loosening `mad_min` rung would read `removed`, trip the 1 % against-direction stop, or read `keep (n < 10)`. Latent for #284's width minima too. → fixed (direction inverted for `_min$` columns).
2. **BT/GR rear rungs need a spawn range** (`cluster_rearing = TRUE`, `.frs_cluster_both`); staged spawn evidence is thin across all covered groups (DV 48 spawn-staged, GR 14, KO 461, RB 645). Decide what fills an insufficient spawn cell before rear ladders are built.
3. **KO is unscorable held-out**: KO present only in CARP, KOTL, NATR, PARS — all calibration groups.

## Gaps
1. **A rear range also gates lake/wetland rearing** under `mad` (`fresh/R/frs_habitat_predicates.R` `build_wb_pred`: polygon membership alone while `size_rear` is NULL; `size AND membership` once it exists — confirmed, and the same is true under cw). Measure it; report `rearing_any` and lake/wetland km; correct RUNBOOK §7 ("inherit nothing under either model" is true of the main predicate only).
2. River polygons test `mad` under `mad` (rule-level `channel_width` dropped) — include them (done).
3. `working_of()` ignores `--prefix`: a `score302_` base rebuild overwrites `working_score_*` behind `score284_`. Run any #284 regression with a scratch `--prefix`/`--out`.
4. FISS script hard-codes `habitat_thresholds_284/` and CH/BT name patterns.
5. Score cell checks must count `set` cells (done: `n_set`). `default_tuned` carries BT `rear_gradient_max` 0.1349 while variants copy `default` (0.1049): carry it in `set` for BT rear rungs or the rungs are scored under a cap the landed bundle does not use.

## Ordering
1. Spawn values for BT/GR fixed (or a declared placeholder) before their rear ladders.
2. Decide which n-floor decides (`decision` vs `decision_expected_floor`) before any run; a loosening-only walk is where the found-count floor cannot refuse. Decide what lands when the first loosening rung is underpowered.
3. Amend the issue text: the harness is built here, #300 reuses it.
4. Ladder shape forbids branching below the base: anchor tightest, walk looser.

## Assumptions
1. Measuring on calibration groups (not #300's held-out) departs from the issue's wording — say so.
2. Open `mad_max` departs from the bundle's rearing caps (CH 100, CO 40, ST 60, WCT 40) — report P95/P99.
3. RB evidence may include steelhead juveniles where ST is present.
4. RB rear-staged (~11k) is large enough to be primary for rearing.

## Scope / acceptance
- Landed values change no output (all bundles `cw`); acceptance must name verdict columns and `rearing_any` / lake / wetland km.
- Records: research title, `default_tuned/README.md`, `config.yaml` description + provenance, NEWS, RUNBOOK §7 correction.
- Tests: `test-lnk_config.R:331-356` hard-codes the one #284 diff row; `:358-377` provenance verification needs the new checksum. `shape_checksum` unchanged.

## No-ops / impossible in the plan as written
- "Prove default obs invocation reproduces #284" — moot (sibling script used).
- `mad_max` 9999 is cosmetic (fresh fills NA with Inf when `mad_min` is set); `set` still needed for spawn coupling.
- `schema_core` = cw base + rungs is already `ladder_of()`'s behaviour.
- "Assert classified on mad via validator `model`" is circular (same CSV); use a behavioural check.
- The no-range `mad` schema is never built (only the base may have an empty `column`).
