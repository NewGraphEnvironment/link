# Task: streams_habitat_<sp>.accessible disagrees with streams_access.access_<sp> (#349)

## Problem (from the issue, 2026-10-19)


In a `default` build, `streams_habitat_<sp>.accessible` and `streams_access.access_<sp>` disagree. Counts are segments, joined on `id_segment` and `watershed_group_code`:

| species | `accessible` TRUE, `access_<sp>` = 0: `fresh_default` (province-wide run `20261017_004619-3f4c713b`, 241 groups) | the same in `score284_default` (link 0.53.0, 2026-09-30, 23 groups) |
|---|---|---|
| BT | 48,728 (1.8 % of `accessible`), 8,867 of them `rearing`, 4,697 `spawning` | 2,948 (0.7 %), 40 `rearing` |
| CH | 14,242 (1.6 %), 330 `rearing` | 1,923 (1.7 %), 43 `rearing` |
| CO | 12,717 (2.0 %), 531 `rearing` | not checked |
| GR | 30,996 (3.5 %), 7,170 `rearing` | not checked |
| RB | 481,275 (17 %), 147,445 `rearing`, 66,983 `spawning` | 99,992 (27 %), 27,056 `rearing` |
| KO | 55,989 (90 %), 983 `rearing` | not built |

The other species (CM, PK, SK, ST, WCT) are at 1.3–2.3 %. The reverse (`accessible` FALSE, `access_<sp>` > 0) is at most about 1,000 segments per species. A few segments have `spawning` while `accessible` is FALSE (CH 178, CO 760, CM 280), probably the user-habitat overlay.

It is in the older build too, so it is not only the cross-group recompute of `streams_access`. Its cause is not established. It could be rearing and spawning gated before access was settled, or the two columns built from different inputs (observation overrides, a different rule for resident species).


## Context

In a `default` build, fresh's `accessible` flag (which gates `spawning` / `rearing` /
`lake_rearing` / `wetland_rearing` inside `frs_habitat_classify()`) and link's
`streams_access.access_<sp>` disagree: `accessible` TRUE with `access_<sp>` = 0 on 1.8 %
of BT's accessible segments, 17 % of RB's, 90 % of KO's. Consumers pick one of two columns
and get different km. #336 is the DUNC BT instance (228 segments).

**Measured today (read-only SQL on `fresh_default`, run `20261017_004619-3f4c713b`): four
mechanisms. A, A′ and B make fresh say accessible where link says blocked; C is why link
says blocked at all for RB and KO.**

| | mechanism | evidence |
|---|---|---|
| **A** | **Metre rounding at classify.** `.lnk_pipeline_classify_build_breaks()` (`R/lnk_pipeline_classify.R`) writes every break at `round(drm)`; fresh's CTE blocks on `b.drm <= s.drm` (fresh `R/frs_habitat_classify.R:245`). Gradient barriers sit at FWA segment starts (mm precision), so the rounded break lands *above* the start and the segment starting at the barrier is never blocked. | DUNC BT: 225 of 228 disagreeing segments have `round(barrier) > segment start`; all 228 GRADIENT, offsets −5.0 to +4.9 mm. |
| **A′** | **link blocks the near-equal case by ltree, not measure.** `frs_network_features()` → `fwa_downstream(…, 1)`: criterion 1 excludes a barrier within 1 m, criterion 2 fires because the barrier at N−ε carries the lower FWA feature's ltree (`R/lnk_pipeline_prepare.R:376-383`) and the segment at N the upper's. fresh's `<=` is exact, so even unrounded breaks miss the 105 cases where the barrier is 0–5 mm above the start. | the +ε cases (reviewer re-measured: raw positions would block 123, miss 105). |
| **B** | **Cross-group barriers.** fresh's breaks table is AOI-filtered (`WHERE s.watershed_group_code = <aoi>`); link's `barriers_<sp>_access` view reads province-wide `<persist>.barriers`. A blocking natural barrier in a downstream group is invisible to fresh. | RB and KO at **100 %** in whole groups (PARS, NATR, CARP, FINL, PCEA, INGR, TOOD, OSPK, MESI, …: the Williston drainage; LEUT/UEUT; CANO; GR at 100 % in ELKR, TURN, BULL). For the Peace: GRADIENT rows on `blue_line_key` 359572348 at 1,684,183 m and 1,706,110 m (both in UPCE per FWA; the Peace Canyon / Bennett dam faces read as ≥25 % gradient; a third at 1,706,197 m blocks the 15 % species incl. KO), `blocks_species` = all 13. |
| **C** | **Observation lifts count the group's own observations only.** `.lnk_pipeline_prep_observations()` keeps `o.watershed_group_code = <aoi>` (that group's presence) and `lnk_barrier_overrides()` joins `<schema>.natural_barriers` to it. bcfishpass counts every observation upstream, province-wide (RUNBOOK §5; `smnorris/bcfishpass@v0.7.15` `model_access_bt.sql`, to be re-read and pinned in Phase 1). A barrier is lifted only if some group whose `gradient_barriers_raw` held it (the whole line's barriers: FINA, LPCE, PCEA and UPCE each persist the Peace rows) had ≥ threshold observations *inside itself*. | Above 1,706,110 m: **0** observations of any species inside UPCE, yet BT is lifted — the `barrier_overrides` rows there are FINA's and PCEA's. KO: 172–244 post-1990 observations upstream province-wide, all in PARS / NATR / CARP where KO is present; the four groups holding the barrier list KO absent, so its threshold of 5 is never met. RB: 2,420–2,660 observations upstream, and **no rule at all** in `default/parameters_fresh.csv`. |

**Why A is not fixed by dropping the `round()`:** fresh matches overrides to breaks by exact
`=` (`.frs_access_with_overrides`) and `natural_barriers` is rounded too, so unrounded breaks
would end every observation lift; A′ and B are untouched by it. **Why nothing at classify
time can be the fix:** `streams_access` is province-wide, override-applied, re-settled
post-consolidate (`lnk_access(merge = TRUE)`) and parity-scored against bcfishpass
(`accessible_km`, #221/#223); `streams_habitat_<sp>` is never recomputed, so on a multi-host
run a downstream group's barriers may not exist when a group classifies.

Side findings, not in scope here: the same gradient barrier persists under four group codes
(1,863 duplicate gradient rows); `<persist>.barriers` carries no gradient class
(`barrier_subtype` is the literal `'gradient'`); mechanism C is also a *reverse-direction*
cause (a lift written by group Y's run reaches link's province-wide view but not group X's
own fresh run).

**Design review** (Plan agent, 22 findings, verified where load-bearing): working-side
settle refused (`habitat_variants_build.R:544-556, 681-688` digests the working habitat and
asserts classify + connect reproduce it); `lnk_access(merge = TRUE)` can *unblock*
(`R/lnk_access.R:226`, `ELSE 1`), so a settle is lossy; `frs_habitat_overlay()` sets
spawning / rearing with no access gate; `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:
123-132` still carries #336's retracted boundary story; new log columns are safe by
construction (`.lnk_log_align_columns`, `ADD COLUMN IF NOT EXISTS`), but `_finish`'s single
UPDATE fails softly on a schema that predates them.

## Decided at the gate (operator, 2026-10-19, with the reviewer's findings folded in)

1. **`streams_access.access_<sp>` is authoritative; one settle step makes the habitat flags
   agree.** New exported `lnk_habitat_gate()` (family `lnk_habitat_*`): where
   `access_<sp> = 0`, set `accessible`, `spawning`, `rearing`, `lake_rearing`,
   `wetland_rearing` FALSE on the **persist** per-species tables; returns the counts
   (species × flag, segments and km). One shape only.
   - In `lnk_pipeline_run()`: after the second `lnk_pipeline_persist()`, then mapping_code is
     built **from persist** (`streams_habitat_long_vw` + persist `streams_access`, exactly
     `wsg_recompute_one.R:168-203`) instead of from the working tables before persist, so
     SPAWN / REAR tokens never ride on blanked flags. The pinned phase order in
     `test-lnk_pipeline_run.R` moves with it.
   - In `data-raw/wsg_recompute_one.R`: between `lnk_access(merge = TRUE)` and
     `lnk_mapping_code()`; `habitat_variants_build.R`'s own recompute loop gets the same call.
   - **Lossy by decision (c):** a segment the settle blanked is restored only by a re-model;
     a later recompute that lifts a settled segment (`access_<sp>` 0 → 1/2 where the flags
     are already FALSE) is counted and reported non-zero as "re-model needed", never
     silently. Rejected: gating at read time in every consumer (the issue exists because
     consumers disagree), persisting fresh's pre-settle flags beside the settled ones (five
     more columns per species).
   - **The overlay is exempt:** rows `frs_habitat_overlay()` set from
     `user_habitat_classification` keep spawning / rearing (fresh's own convention; bcfishpass
     forces known habitat), found by the same `(blue_line_key, [drm, urm])` containment on
     `streams`, from `loaded$user_habitat_classification` written to a scratch table (the
     working schema is gone at recompute time). `accessible` is still set FALSE.
   - Counts on `log_recompute` **and** `log` (a single-group run opens no recompute row;
     #264's precedent), written in a second soft statement after `date_end`.
   - Rejected: persist-wide breaks at classify (cannot cover a barrier absent at classify
     time; derives the gradient class twice); a fresh change now (the reviewer's minimal
     `tolerance_m` on fresh's `<=` and override anti-join, plus dropping link's rounding in
     prepare and classify together, would fix A/A′ *at classify time*: filed as a follow-up,
     not done here).
2. **RB and KO are lifted by observations like BT ("an oversight, nothing to debate").** Two
   changes, because KO already has a rule and mechanism C defeats it:
   - `configs/default/parameters_fresh.csv` gains an RB rule on BT's resident pattern:
     `observation_threshold 1, observation_date_min NA, observation_buffer_m 20,
     observation_species RB, observation_control_apply FALSE`. KO's row stays.
   - `lnk_barrier_overrides()` counts observations **province-wide**: a second prepared
     table of every bcfishobs observation, each row filtered by its *own* group's presence
     and the QA exclusions (bcfishpass's `observations`), replaces the AOI table in the
     override count only. `<schema>.observations` stays AOI-filtered for breaks and for
     access code 2. The habitat-confirmation lift keeps its current scope (noted).
   - The reviewer's alternative, a `user_barriers_definite_control` row with
     `barrier_ind = f` on the dam faces, is recorded in `findings.md` as data the operator
     may add later; it is not what was decided.
3. **Verification build:** config `default`; persist schema `fresh_349` (scratch, seeded
   with `fresh_default.barriers` + `barrier_overrides`); **DUNC** and **CARP**, built singly
   with `data-raw/wsg_run_one.R` under `LNK_SCHEMA=fresh_349` then `wsg_recompute_one.R`;
   species = `default` × presence; `dams` TRUE, `mapping_code` TRUE. `fresh_default` is not
   written by this issue. Measured **before and after** the settle so the gate's effect is
   attributed, not assumed.
4. **The provenanced `fresh_default` re-gate is owed after merge, operator's call then**
   (`study_area_finish.sh --recompute-only --run-uid=20261017_004619-3f4c713b`); the RB/KO
   lifts need a re-model, so Peace RB/KO habitat appears province-wide on the next full run.

## Phase 1: Characterise province-wide by mechanism
- [x] `data-raw/access_disagree_349.R` → `data-raw/logs/access_disagree_349/`: per species in
      `fresh_default`, split `accessible AND access_<sp> = 0` into **A/A′** (a species-blocking
      natural barrier within 1 m on the same `blue_line_key`, by offset sign and
      `round(barrier) > start`), **B** (the group has a species-blocking, un-lifted natural
      barrier on its downstream outlet path, found with `fwa_downstream()` from
      `fresh::frs_wsg_outlets()` the way `.lnk_dams_blocking_downstream()` finds dams), **C**
      (rest). Assert the classes sum to the per-species totals in the issue.
- [x] Same script: the reverse direction by class (incl. the province-vs-AOI override cause);
      overlay rows among the `access = 0` set (what the exemption keeps); `lake_rearing`
      kept on a polygon whose connected spawning the settle would blank; #351 ruled out
      (no `-9`, no absent species among disagreeing rows).
- [x] `groups_blocked.csv`: per species × group at ≥ 99 %, the blocking barriers (source,
      line, measure, FWA group), observations upstream province-wide vs inside the holding
      group (the mechanism-C evidence), and the km of spawning / rearing at stake.
- [x] Read `model_access_bt.sql` at a pinned bcfishpass ref (read-only `gh api`) and record
      the observation scope it counts over, in `findings.md`.
- [ ] Commit `classes.csv`, `groups_blocked.csv`, `summary.md` with an environment stamp
      (link SHA, fresh version, run_uid); put the table in the #349 body.

## Phase 2: `lnk_habitat_gate()` — the settle step
- [x] Failing tests first (`tests/testthat/test-lnk_habitat_gate.R`): mocked-SQL shape test
      (one UPDATE per species, the five flags, keyed on `(id_segment,
      watershed_group_code)`, `access_<sp> = 0` only, AOI-filtered, overlay rows exempt from
      the four habitat flags) plus a DB-backed fixture test on `test-lnk_access.R`'s pattern
      (`skip_if_no_db()`, `zz_lnk_*` probe schema, `withr::defer`): `access_bt = 0` → all five
      FALSE; `access_bt = 1` and `-9` untouched; an overlay row keeps spawning; a settled row
      later lifted is counted as `n_lifted_settled`; the DB test fails with the UPDATE
      stubbed out.
- [x] `R/lnk_habitat_gate.R`: `lnk_habitat_gate(conn, aoi, table_habitat, table_access,
      table_streams, species, overlay = NULL)` (`table_<role>` args; `table_habitat` is the
      `<prefix>` of `<prefix>_<sp>`; `overlay` a canonical-shape tibble or table); returns
      `species, flag, n_segments, km, n_lifted_settled` (km from `streams.length_metre` on
      the full key, #203).
- [x] Wire into `lnk_pipeline_run()` after the second persist; move the mapping_code phase
      after it, reading persist (the recompute's shape); update `test-lnk_pipeline_run.R`'s
      pinned order. Wire into `wsg_recompute_one.R` between steps 1 and 2 and into
      `habitat_variants_build.R`'s recompute loop; `.lnk_log_recompute_finish()` /
      `.lnk_log_*` take the counts with defaults so existing callers run unchanged.
- [x] `cols_log` + `cols_log_recompute` gain `habitat_gate_n integer`, `habitat_gate_km
      double precision`-compatible text, `habitat_gate_lifted integer`, `habitat_gate_species
      text[]` (existing types only); written in a second soft statement.
- [x] `study_area_verify.sql` gains the invariant per species: no row with `accessible AND
      access_<sp> = 0` (and `study_area_verify_negative.sh` proves it fires).
- [x] `devtools::document()`, pkgdown reference check (clean); NEWS entry in Phase 5.
- [x] Added for Phase 4: `lnk_pipeline_run(habitat_gate = FALSE)` / `LNK_HABITAT_GATE=0` in
      `wsg_run_one.R`, so the classify-time state can be measured before the settle.

## Phase 3: RB lift rule and province-wide observation counting
- [x] Failing test: `lnk_barrier_overrides()` given a province table lifts a barrier whose
      only upstream observations lie in another group (fixture); with the AOI table it does
      not.
- [x] `.lnk_pipeline_prep_observations()` also builds `<schema>.observations_province`
      (all groups; each row kept when its own group's presence row and the exclusions admit
      it: the presence pairs reach SQL as a `VALUES` list, so nothing else is written);
      `.lnk_pipeline_prep_overrides()` passes it as `observations`.
- [x] Time the override step on DUNC and CARP before and after (`fwa_upstream` join of the
      group's natural barriers against province-wide observations); record in `findings.md`;
      if it is minutes per group, index the scratch table on the ltrees before judging.
- [x] Add the RB row to `configs/default/parameters_fresh.csv`; `data-raw/audit_configs.R`
      and `test-dictionaries.R` pass; `config_hash` moves (noted in NEWS).
- [x] Test that an RB-blocking barrier with one RB observation upstream is lifted in a
      `default` fixture (the rule, not the scope).

## Phase 4: Verification build
- [x] Seed `fresh_349` (`lnk_persist_init()`, then copy `barriers` + `barrier_overrides`
      from `fresh_default`); build DUNC and CARP under `default` with
      `LNK_SCHEMA=fresh_349` **with the settle disabled for the measurement**, run the Phase
      1 script (classify-time state), then recompute (which settles) and run it again.
- [x] After: forward-direction disagreement = 0 for both groups; per species what the gate
      removed and what the lifts restored (DUNC BT: #336's 85 km blocked in both columns;
      CARP RB and KO: the Peace rows lifted for both, both columns *accessible*); the
      reverse direction before/after; segments above an observation-lifted barrier
      unchanged (the mechanism-C regression check). All in
      `data-raw/logs/access_disagree_349/after/`.
- [x] `lnk_rollup_wsg()` and `lnk_compare_rollup()` on `fresh_349` for both groups:
      `accessible_km` and the habitat km move by exactly what the gate and the lifts report;
      DUNC BT spawning / rearing km move *toward* bcfishpass. (UPCE added; `lnk_compare_rollup()`
      not run, tunnel down: DUNC BT compared with the local `fresh.streams_vw_bcfp` instead.)
- [ ] Suite: `devtools::test()`, `lintr::lint_package()`; `/code-check branch`.

## Phase 5: Docs and issues
- [ ] RUNBOOK §3: "accessible is settled from streams_access" (the four mechanisms, the gate,
      where it runs, the lossy rule and its counter); §5: observation lifts count
      province-wide; §6c: the recompute settles habitat; §6d: replace the "different barrier
      sets" paragraph; `inst/extdata/schemas/habitat_fwa_v1_segment.yaml:123-132` and
      `R/lnk_scenario_export.R` roxygen on the two columns.
- [ ] `research/access_columns.md` (new topic file, provenance line, cites the log prefix);
      `research/README.md` row. Which existing schemas stay unsettled (`fresh_default`,
      `fresh`, `score284_*`) and what restores them.
- [ ] CLAUDE.md status block; NEWS.
- [ ] Edit the #349 and #336 bodies (findings are the spec; #336's "fresh's breaks table
      lacks those barriers" becomes "holds them at rounded positions"); PR closes #336.
- [ ] Draft (for body review, not filed) the follow-up: fresh `tolerance_m` + dropping
      link's rounding, so A/A′ are right at classify time.

## Owed at the end (reported, done after merge)
- [ ] Provincial `--recompute-only` re-gate of `fresh_default` (decision 4) — operator's call.
- [ ] Re-score the 48/50 bcfishpass parity baseline (ADMS, BULK, BABL, ELKR) after that
      re-gate.
- [ ] File the fresh-tolerance follow-up after body review; note the duplicate-persisted
      barrier rows (1,863) as a candidate issue.

## Validation
- [ ] Tests pass
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: Phase 1's classes sum to the issue's totals per species; Phase 2's
fixture test goes red with the UPDATE stubbed out and the verify SQL's negative test fires;
Phase 3's fixture lifts only with the province table and the RB rule; Phase 4 measures the
two groups before and after the settle, shows zero forward disagreement after, CARP RB/KO
accessible in both columns, and the rollups moving by the reported amounts; the
province-wide table is re-measured only when decision 4 runs.

Parked 2026-10-19 (baseline only); the run-to-PR mandate starts at the resume instruction in progress.md.
