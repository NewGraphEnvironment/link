# Task: Why is CHWK 20x SALR at 80% of its size? Test the downstream-barrier-walk hypothesis (#261)

Recompute cost does not track segment count, and the spread is extreme: measured 2026-09-01 during #250, CHWK (8,866 segments) took 226 s and SALR (10,663 segments) 11 s. Test whether cost tracks the barriers downstream of a group before scoping any optimisation.

## Context

#261 (filed at link@v0.48.0, 2026-09-01) asks why CHWK's recompute costs ~20× SALR's at 80 % of
its size, and proposes one hypothesis to test before anything is built: cost tracks the number of
barriers **downstream** of a group, walked by `fresh::frs_network_features()`.

It still holds at provincial scale. From the committed per-group logs:

| run | width | CHWK | SALR | ratio |
|---|---|---|---|---|
| `20261017_004619` | `-j4` | 9.26 min | 0.51 min | 18× |
| `20261023_074321` | `-j8` | 15.56 min | 0.72 min | 22× |

Tracker #377 frames the payoff: the provincial pool is bound by summed work, not its slowest job, so
CHWK alone is ~1.9 min of the 110 min span. **This pays only if the cause also slows other groups.**
The deliverable is a verdict with numbers, not an optimisation.

What exploration established (read-only):

- **The recompute walks no observations.** `lnk_access(merge = TRUE)` (`R/lnk_access.R:204`) passes
  `observations = NULL`. Per group it runs `frs_network_features(direction = "downstream")` once per
  **present species** (`<schema>.barriers_<sp>_access`, each a *view*) and once per source
  (`barriers_anthropogenic_unified`, `_pscis_unified`, `_dams_unified`); `R/lnk_pipeline_access.R:144-200`.
  Then the habitat gate and the mapping-code rebuild (`data-raw/wsg_recompute_one.R`).
- **The walk's SQL** (fresh `R/frs_network_features.R`): AOI segments INNER JOIN every feature
  province-wide on `fwa_downstream(...)`, ordered, `array_agg` per segment. Its output is one row per
  (segment, feature downstream of it) pair, so cost plausibly tracks **Σ over the group's segments of
  features on each segment's downstream path**, which grows with crossings *inside* the group as much
  as with barriers below its outlet.
- So there are rival explanations the issue does not name: present-species count (walks per group),
  within-group crossing density (pairs per walk), and the non-walk steps. Each gets measured, not assumed.
- **m1 holds `fresh_default` exactly as the 2026-10-23 run left it** (241 groups, last log write
  2026-10-23 20:23 UTC), so timings and database state match. m4's local schemas are partial (30 groups).

## Decided at the gate (operator approved the plan, 2026-10-27)

1. **Measure on m1's `fresh_default`**, read-only: the walks run as `SELECT`s against a session `TEMP`
   copy of the group's segments (indexed, `ANALYZE`d, as `lnk_access()` builds it), never writing to
   the schema. Each script checks for an active run (`pg_stat_activity`, `study_area_run` processes)
   and refuses if one is going. Alternative refused: m4's partial local schemas, which cannot reproduce
   cross-group walks.
2. **One instrumented end-to-end re-run of CHWK and SALR only** (`LNK_LOG=0`, on m1), to time the gate
   and mapping-code steps that the read-only harness cannot reach. The recompute is idempotent on
   unchanged inputs; a digest of each group's `streams_access`, `streams_mapping_code` and
   `streams_habitat` rows is taken before and after, and any difference stops the work and is reported.
   If you would rather not write to `fresh_default` at all, say so and Phase 1 infers the non-walk share
   from the logs instead (weaker: contended times).
3. **No optimisation in this branch** (the issue's own rule). A fresh-side cause gets a **drafted**
   fresh issue shown to you, not filed (link's "never file without body review").
4. **Measurement-only branch: no version bump or release**, unless a script lands in `R/`.

## Phase 0: baseline and review

- [ ] PWF baseline committed; Plan agent reviews `task_plan.md` against the issue and code (background,
      findings to `planning/active/review-plan.md`)

## Phase 1: where the time goes (decompose CHWK against SALR)

- [ ] `data-raw/logs/recompute_cost_261/walks.R`: for a group, build the TEMP segments table, then time
      each walk `lnk_access()` would run (per present species view, per source) with
      `EXPLAIN (ANALYZE, BUFFERS)` and record rows out (pairs), segments, and the plan's driver
      (which side is outer)
- [ ] Run it on CHWK, SALR, LKEL, CHES (#261's four), the 2026-10-23 longest job, and two median groups;
      write `walks.tsv`
- [ ] Gate decision 2: instrumented re-run of CHWK and SALR with per-step timing; digests before/after
      in `rerun_digest.tsv`; `steps.tsv` gives walk / gate / mapping-code / other seconds
- [ ] Read the result: which step and which walk carries CHWK's excess, and whether its pair count or its
      per-pair cost is what differs (plan shape, view evaluation, index use)

## Phase 2: does the cause generalise? (all 241 groups)

- [ ] `data-raw/logs/recompute_cost_261/predictors.R`: per group, from m1's `fresh_default` and FWA:
      segments; present species; barriers downstream of the group's outlet (`fresh::frs_wsg_outlets()`
      + measure-aware `fwa_downstream()`, as `lnk_wsg_downstream_check()` does: #261's own predictor);
      features of each walked table inside the group; and the Phase 1 mechanism's predictor (e.g. Σ
      downstream pairs) if it is cheaper than the walk itself, else on a stratified sample
- [ ] Measured minutes per group from both runs' committed logs (`20261017_004619_recompute.log`,
      `20261023_074321_recompute.log`); first check rank stability between them (Spearman), so noise
      from `-j4`/`-j8` contention is sized before any predictor is judged
- [ ] Spearman and log-log fit of each predictor against minutes, segment count alongside as #261
      asks; `correlations.tsv` and one figure; name the groups the best predictor misses
- [ ] Verdict: #261's hypothesis confirmed or refuted, the mechanism named, and how many of the
      pool's minutes it accounts for beyond CHWK (the tracker's "pays only if" test)

## Phase 3: record and hand off

- [ ] `data-raw/logs/recompute_cost_261/README.md`: question, method, stamps (link / fresh SHAs, run_uid,
      m1 load), measurement, evidence; keep the wrong turns
- [ ] `research/recompute_cost.md` (new topic file; the dated `recompute_parallel_2026_09_01.md` is not
      renamed): the durable verdict; `research/README.md` row if one exists
- [ ] If the cause is in fresh: draft the fresh issue with the EXPLAIN output attached, shown in the final
      report, not filed. If it is in link: a follow-up link issue drafted the same way, with the expected
      saving in minutes
- [ ] Edit #261's body with the verdict (acceptance boxes), fill #377's "Measured:" line for #261,
      CLAUDE.md Status block, RUNBOOK §8d only if a mechanic changed
- [ ] `/code-check branch`, `/planning-archive`, `/gh-pr-push`

## Owed at the end (reported, done after merge)

- [ ] Re-run `predictors.R` against the next provincial run (v0.69.0, #326 segmentation roughly halves
      segments), since every number here is on the pre-#326 build
- [ ] File the drafted fresh / link follow-up once you approve its body

## Validation

- [ ] Tests pass (`devtools::test()`; scripts are `data-raw/`, so mainly a no-regression check)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each claim is proved:
- Read-only harness: the schema's `pg_stat_user_tables` write counters for `fresh_default` do not move
  across a harness run (checked before and after).
- Decomposition: the summed step times of the instrumented re-run land within 10 % of that run's wall
  clock, and the walk times from the harness agree with the re-run's walk step.
- Idempotence: before/after digests identical for CHWK and SALR.
- Correlation: reported for both runs, with the runs' own rank agreement as the noise ceiling.

