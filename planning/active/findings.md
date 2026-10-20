# Findings — Validate comp_weight against measured modelling time, not just against WSG count (#259)

## Issue context

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
20% *more* segments. That makes it an intrinsically expensive watershed group
on both phases, not a recompute quirk. The cost tracks the downstream barrier
walk, not the segment count.

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


## Planning measurements (2026-10-20, read-only, local docker fwapg)

Run `20261017_004619-3f4c713b` in `fresh_default.log`: 241 finished rows, 4 hosts
(m1, cypher-job1..3), newest row per group, minutes = `date_end - date_start`.
Source segments: `whse_basemapping.fwa_stream_networks_sp` count per group; persisted:
`fresh_default.streams`. May-2026 times: median `elapsed_s` per WSG with `status = ok` over
every `data-raw/logs/**/*_per_wsg_times.csv` (104 WSGs). Components: the 62 in
`data-raw/logs/provincial_246/buckets_default.md`.

| host | n | sum min | source segs | persisted segs | min / 1k source |
|---|---|---|---|---|---|
| cypher-job1 | 49 | 165 | 1,184,045 | 2,516,552 | 0.139 |
| cypher-job2 | 55 | 205 | 1,210,887 | 2,973,165 | 0.169 |
| m1 | 78 | 231 | 1,240,049 | 2,790,932 | 0.186 |
| cypher-job3 | 59 | 272 | 1,205,171 | 3,107,508 | 0.226 |

- Fit, all hosts: R² time ~ source segs **0.483**, ~ persisted segs 0.644; total 873 min, max 16.5 (SETN).
- Within host, R² source: job1 0.602, job2 0.706, job3 0.504, m1 0.569; slopes 0.105–0.233 min per 1k source.
- Out-of-sample, 104 overlap: R² Oct ~ May time **0.830**, Oct ~ source segs 0.530; log-log corr 0.897 vs 0.743.
  Per host: job1 0.908 / 0.564, job2 0.774 / 0.800, job3 0.886 / 0.347, m1 0.915 / 0.700.
- Most expensive per source segment: VICT 0.86, CHWK 0.82, LKEL 0.76, SUST 0.45, SHUL 0.44, PARK 0.44 min / 1k.
  Cheapest: GRNL, UEUT, LKEC 0.06.
- Time-weighted LPT over the 62 components (equal speeds): 3 hosts 291/291/290; **4 hosts 219/219/218/217**;
  5 hosts 205/167/167/167/167 (Fraser component 205 min is the floor).
- Host speed and component composition are confounded (each group ran on one host). job3 held
  BULK, LSKE, ELKR, KISP (0.34–0.38 min / 1k). The May→Oct R² spans different hosts and code.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `Rscript -e` turned `\\|` into `\|` ("unrecognized escape") | Rscript collapses backslashes in `-e`; feed the script on stdin (`Rscript - <<'EOF'`) |
