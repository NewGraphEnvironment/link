# Plan review — #349 (Plan agent, 2026-10-19, run in plan mode on the design draft)

Reviewer read link `849d1f3e` and fresh `441d58e`. Items marked ✓ were verified against the
code in the session and are folded into `task_plan.md`; the rest are carried as given.

## Mechanism A and dropping the `round()`

1. ✓ Blocker — dropping `round()` alone fixes 123 of DUNC BT's 228, not 228. fresh's same-line
   test is exact `<=` (`frs_habitat_classify.R:245-246`, `:455`). Of the 228, raw positions
   would block 123 and miss 105 (barrier 0–4.9 mm above the start); link blocks all 228 via
   `fwa_downstream`'s ltree criterion 2 (barrier at N−ε carries the lower FWA feature's ltree,
   `lnk_pipeline_prepare.R:376-383`), not via a measure tolerance. Remedy: a fresh measure
   tolerance on that `<=`, or snapping breaks to segment starts. Plan: the settle step covers
   the outcome; the fresh tolerance is a drafted follow-up.
2. ✓ Blocker — dropping `round()` in classify alone disables every observation / habitat lift
   in fresh: override anti-join is exact `=` (`:459`, `:473`); overrides come from
   `natural_barriers`, which rounds (`lnk_pipeline_prepare.R:423, 433, 467`). Plan: `round()`
   stays.
3. Gap — a Phase 2 unit test on classify SQL alone would prove a half-fix; it must cover
   `.lnk_pipeline_prep_natural` and the subsurface branch too. Moot while `round()` stays.

## Mechanism B and the settle's premise

4. Blocker (gate) — for B, `access_<sp> = 0` is a dam-face artefact. Rows `GRADIENT-3556/…`
   at 1,684,183.020 and `-3557/…` at 1,706,109.930 on blk 359572348, plus a third at
   1,706,197.220 blocking the 15 % species incl. KO; lifted for SK/GR/CO/CH/ST/CM/BT/PK only.
   Alternative: a `user_barriers_definite_control` row with `barrier_ind = f` (prepare
   `:360-368` prunes `gradient_barriers_raw`, unify reads the pruned table). Operator chose
   observation lifts for RB/KO instead (decision 2); the control-row alternative is recorded
   in findings.md.
5. Scope — `barrier_subtype` is the literal `'gradient'` on all 7,239,212 GRADIENT rows;
   `gradient_class` exists only in `gradient_barriers_raw`. Deriving a label from
   `blocks_species` works (max `access_gradient_max` of the blocked set × 10,000). Moot:
   persist-wide breaks rejected.

## Settle step: placement and consumers

6. ✓ Ordering — in `lnk_pipeline_run` the settle goes after the second persist only
   (`:315-316`): `streams_access` is persisted there; anything between the two persists is
   overwritten (`persist.R:63-73`).
7. ✓ Ordering — mapping_code (`:293-313`) reads working habitat before persist and emits
   SPAWN/REAR with no access gate (`lnk_pipeline_mapping_code.R:262-268`). Plan: build
   mapping_code from persist after the settle, as `wsg_recompute_one.R:168-203` does; the
   pinned order in `test-lnk_pipeline_run.R:264-274` changes.
8. ✓ Blocker — do not settle the working long table: `habitat_variants_build.R:544-556` digests
   it after `lnk_pipeline_run` and `:681-688` asserts classify + connect reproduce it.
9. ✓ Ordering — in `wsg_recompute_one.R` the settle sits between step 1 (`:149-154`) and step 2
   (`:168-177`).
10. Gap — `habitat_variants_build.R` replicates the recompute (`:573-590`, `:697-710`) and needs
    the settle too; new `_finish` args must default.
11. Gap — a single-group run with no recompute records the settle nowhere: put the counts on
    `cols_log` as well as `cols_log_recompute` (precedent #264, `NEWS.md:325`).
12. ✓ Hazard — the settle is lossy and the recompute is not monotone: `lnk_access(merge)`'s
    CASE (`lnk_access.R:224-228`) returns 1 where a prior 0 is lifted; blanked habitat cannot
    return, so repeated recomputes ratchet down. Options: (a) gate at read time, (b) persist
    pre-settle flags, (c) accept and document. Plan: (c) with a counted "lifted-after-settle"
    guard reported non-zero.
13. ✓ Gap — `frs_habitat_overlay` flips spawning/rearing with no `accessible` predicate
    (`frs_habitat_overlay.R:258-270`); a settle wipes expert-confirmed habitat on blocked
    segments. Plan: overlay rows exempt from the four habitat flags.
14. Consumers. Read `accessible`: `lnk_scenario_export.R:69-75, 203, 205`;
    `data-raw/build_species_views.R:84-96`; fresh at classify time only (`frs_order_child.R:193`,
    `frs_habitat.R:1917`). Read spawning/rearing/lake/wetland (their km move):
    `lnk_rollup_wsg.R:119-126,170`; `lnk_compare_rollup.R:214-232, 243-284`;
    `lnk_habitat_validate.R:845-879, 1211-1243`; `lnk_habitat_validate_band.R:140`;
    `lnk_mapping_code.R:155-168`; `data-raw/wsg_vignette_data.R:121-141` (schema `fresh`);
    `lnk_compare_wsg.R` (working schema, pre-persist, so its km will differ from
    `lnk_compare_rollup`'s). Pre-settle: every `data-raw/logs/habitat_score_*` number and
    `research/habitat_thresholds.md`.
15. Acceptance — re-score parity, not only the A/B counts: run `lnk_compare_rollup` on the
    rebuilt groups and record direction; re-score the 48/50 baseline before release;
    `study_area_verify.sql` gains the invariant `NOT EXISTS (accessible AND access = 0)`.
16. ✓ Ordering — B = 0 post-settle is tautological; measure before and after the settle. DUNC
    has no B (headwater); CARP's classify-time `accessible` stays TRUE for B by design.
17. Scope — existing schemas (`fresh_default`, `fresh`, `score284_default`, variants) stay
    unsettled unless backfilled; `study_area_finish.sh --recompute-only --run-uid=…` applies
    it to `fresh_default` without re-modelling. Phase 5 says which.

## log_recompute

18. ✓ New columns are safe by construction: `.lnk_log_align_columns` issues
    `ADD COLUMN IF NOT EXISTS` (`lnk_log.R:483-492`) from `lnk_persist_init`, run start,
    consolidate step 0 and `study_area_finish.sh`; consolidate copies the shared-column
    intersection so older hosts' rows land NULL; `test-lnk_log.R:709-716` auto-covers any added
    name. Hazard: `_finish`'s single UPDATE (`:1311-1315`) fails softly on a schema that
    predates the columns, leaving `date_end` NULL. Plan: counts written in a second soft
    statement; existing types only.

## fresh connectivity

19. Nothing beyond the named class, plus one: `.frs_bucket_connected` (`frs_habitat.R:
    1302-1315`) keeps `lake_rearing` on a polygon connected to final spawning; if that spawning
    is blanked, the polygon's accessible segments keep `lake_rearing` with no connected
    spawning. Count in Phase 1.

## Phase 1 additions

20. The reverse direction has two testable causes: (i) link's view anti-joins province-wide
    overrides while fresh reads the AOI's working table; (ii) fresh uses `fwa_upstream` for
    other-line breaks, link `fwa_downstream` with tolerance 1 (`schema.sql:953-992` vs
    `:2161-2200`). #351 is out for B/C.

## Docs

21. ✓ `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:123-132` still says "accessible counts
    it as above nothing" (retracted); RUNBOOK §6d `:690-712` and `CLAUDE.md:60` have the
    corrected text; also RUNBOOK §3 `:135-157`, §6c `:566-600`.

## Options

22. No option is clearly better; the decisive constraint is item 2. Recommended order: decide
    item 4 → ship the settle (item 12's choice explicit) → a minimal fresh tolerance → drop
    `round()` in prepare and classify together → defer the rest.
