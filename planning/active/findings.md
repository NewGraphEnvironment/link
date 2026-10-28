# Findings — Pack hosts from measured minutes: group weights and learned host speeds (#259)

## Issue context

## Scope (2026-10-27): group weights and host speeds together; folds in #163

Packing estimates a host's finish time as **the sum of its groups' weights ÷ its speed**. This issue now covers both halves, so one PR closes it and #163:

- **Group weight (this issue's original question).** Since v0.48.0, `data-raw/study_area_buckets.R` has `--minutes-schema=<schema>`, which weights each group by its newest measured modelling minutes in `<schema>.log` and gives a group with none the median (option 2 below, built). The default is still stream-segment count. What is not done: checking either weight's **predicted** finish times against a run's **measured** ones.
- **Host speed (#163).** `--host-speeds` defaults to equal (set from the 2026-10-17 run, `research/study_area_run.md`, "Equal packing was right"), typed by hand otherwise. #163 asks for factors learned from each run's own times. Its body names the old driver (`trifecta_provincial.sh`) and May hosts; the mechanism carries over to `study_area_run.sh` and its workers (#376). Its feedback-loop warning stands: calibrate on a host's whole-leg time against its prediction, not on per-group means.

**What to do:**
1. From the 2026-10-23 run (`20261023_074321-24d85e8c`; per host, per group, minutes in `fresh_default.log` and the leg times in `data-raw/logs/provincial_361/`), fit minutes per group per host, and compare each weight (segments, measured minutes) and each speed setting by predicted against measured leg time.
2. Learned host speeds: a state file read after `--host-speeds` and before the equal default, updated from `<TS>_phases.tsv` (#375) after each run, damped and clamped as #163 proposes, with an audit log.
3. Keep the loud fallback: a group with no weight takes the median and is counted, never an unweighted split.

**Caveats found 2026-10-27:**
- Every measured minute is on the pre-#326 segmentation; #326 cuts segments 2.1 to 2.7-fold. A weight in minutes per segment carries over; raw minutes per group do not. The next provincial run re-fits both.
- #377 expects little from this: the 2026-10-23 packing estimated about 218 min per host against 247 to 260 actual.
- The dispatcher's speed includes the recompute running beside its leg (#374 measured it doubling dispatcher modelling at `-j8`), and NewGraphEnvironment/fresh#272 will shrink that, so a factor learned before it overstates the dispatcher's slowness. The damping corrects it over later runs.

## Original issue (2026-09-01)

## Problem

`data-raw/study_area_buckets.R:184-194` weights each drainage-independent
component by **stream-segment count** from `whse_basemapping.fwa_stream_networks_sp`,
and the greedy LPT pack at `:196-222` divides that by `host_speeds` to get
dispatcher-equivalent minutes.

That weight has been improved twice, and neither step compared it against
measured time:

- **#246** moved it from **WSG count** to **segment count** — "a one-WSG
  component can outweigh a three-WSG one, so segment count is the better proxy
  for work" (`planning/archive/2026-08-issue-246-preflight-gates/findings.md:210-216`).
  True, and a real improvement — but it establishes only that segments beat
  *WSG count*.
- **#253** made the packing **speed-aware** — finish time rather than raw
  segments, because a cypher is 2.23× slower, so balancing segments balances
  *work* and unbalances *time*. That fixed the **host** axis and left the
  per-WSG weight untouched.

So the model is `time ≈ segments ÷ host_speed`, and the `∝ segments` half has
never been checked.

## Measured

Checked against the **104 WSGs of real modelling times already on disk** in
`data-raw/logs/**/*_per_wsg_times.csv` (median per WSG where a WSG appears more
than once), joined to segment counts:

| | |
|---|---|
| Pearson r | 0.798 |
| Spearman r | 0.791 |
| **R² (time ~ segments)** | **0.636** |
| seconds per 1000 segments | **1.88 → 9.49 — a 5× spread** |

Segments explain about two thirds of modelling time. The unit cost is not
constant, and the spread is not small.

| WSG | segments | s / 1000 segs |
|---|---|---|
| **CHWK** | 5,766 | **9.49** (worst of 104) |
| UTRE | 5,706 | 7.83 |
| BULK | 32,472 | 7.77 |
| … | | |
| FONT | 20,984 | 1.93 |
| LBTN | 27,415 | 1.88 |

**CHWK is the worst per-segment WSG in modelling**, and it is also the WSG that
dominated every recompute set in #250 — 226 s against 11 s for SALR, which has
20% *more* segments. *Corrected 2026-10-27 (#261): the recompute's cost does not
track the barriers downstream of a group (Spearman −0.08 over 240 groups). It is
`frs_network_features()` probing the group's segments once per feature in the
province (`research/recompute_cost.md`). Whether the same explains CHWK's
modelling cost is not measured; modelling is a different code path.*

## Why this is not a straightforward swap

Measured times are more accurate **and less available**. `_per_wsg_times.csv`
only carries WSGs run in that dispatch invocation, so a first run, a new WSG, or
a re-scoped focal set all have gaps — and the failure mode is on record:

> `[LPT] no timing CSVs found; using deterministic split` produced equal-sized
> buckets (44 each) for 217 WSGs across 5 hosts, **ignoring the host_speeds
> parameter entirely**
> — `planning/archive/2026-05-ops-hardening-20260514/findings.md:23-29`

Segment count is one query, always available, and never silently degrades.
That is very likely *why* #246 landed on it, and any change has to keep that
property.

## Options

1. **Leave it.** R² 0.64 may be good enough given the packing is over
   *components* (which aggregate several WSGs and partially average the noise
   out), and the host axis is already handled.
2. **Median-fill hybrid** — measured time where known, `segments × median
   s/1000` where not. Same shape as the existing rule for a WSG missing from the
   network table (`:186-192`, "an unknown never packs as free"), and the same
   rule #250's `recompute_order()` now uses for the pool.
3. **Measured only, with a loud fallback** — refuse to pack silently when
   coverage is below some threshold, rather than degrading.

## What would settle it

Re-run the packer over the 119-WSG and 217-WSG focal sets under each option and
compare **predicted makespan against the measured makespan** of a real run.
The question is not which weight correlates better in the abstract — it is
whether the packing changes, and whether the change is in the right direction.

Note the balance figure the packer already prints (`:306`, "balance = N% (100% =
every host finishes together)") is computed *from the weights*, so it cannot
answer this on its own — it would report improved balance for any weight that
packs more evenly, including a wrong one.

## Acceptance

- [ ] Predicted vs measured makespan compared for at least one real multi-host
      run, per option
- [ ] Whichever option lands, coverage gaps fail **loudly** rather than
      degrading to an unweighted split
- [ ] The chosen rationale recorded where #246's is, so the next change does not
      re-derive it

Relates to #246 (segment count over WSG count), #253 (speed-aware packing),
#250 (where the measurement came from —
`research/recompute_parallel_2026_09_01.md`).
Version pin: link@v0.48.0.



## Exploration (2026-10-27)

- m1's `fresh_default.log`, run `20261023_074321-24d85e8c`, finished rows by host: m1 74 groups / 314 min, cypher-job1 57 / 247, cypher-job2 68 / 260, cypher-job3 42 / 257. The packing (`provincial_361/buckets_default.md`) predicted 217–219 min per host at equal speeds.
- `log.host` and `<TS>_stamps.tsv` name hosts (`m1`, `cypher-job1`); `<TS>_phases.tsv` keys them by driver role (`dispatcher`, `job1`, `worker1`). The 2026-10-23 run has no phases.tsv (#375 came after).
- m4's local `fresh_default` holds only dev rows (#326's); the provincial log rows are on m1. m1's non-interactive ssh PATH lacks psql: run it under `bash -lc`, SQL on stdin.
- Measured-minute weights carry the speed of the host that measured them; under unequal speeds they are not dispatcher-equivalent.
- Tests reach data-raw files by path and skip when `data-raw/` is absent (`test-study_area_recompute.R`).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `ssh m1 psql`: command not found | `bash -lc`, SQL on stdin |
