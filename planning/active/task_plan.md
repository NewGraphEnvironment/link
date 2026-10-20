# Task: Validate comp_weight against measured modelling time, not just against WSG count (#259)

`data-raw/study_area_buckets.R:184-194` weights each drainage-independent component by
**stream-segment count** from `whse_basemapping.fwa_stream_networks_sp`, and the greedy LPT
pack at `:196-222` divides that by `host_speeds` to get dispatcher-equivalent minutes. That
weight has been improved twice (#246: WSG count → segment count; #253: speed-aware packing),
and neither step compared it against measured time. So the model is
`time ≈ segments ÷ host_speed`, and the `∝ segments` half has never been checked.

Branch: `259-validate-comp-weight-against-measured-mo`. **Parked 2026-10-20**: the baseline
is written and pushed; no phase runs until the resume instruction.

## Context (measured during planning, read-only, 2026-10-20)

The 241-group provincial run (`20261017_004619-3f4c713b`, m1 + 3 cloud hosts, equal speeds)
holds per-WSG times on every modelable group at HEAD-era code in `fresh_default.log`
(`date_start` / `date_end` / `host`).

| what | value |
|---|---|
| R² time ~ source segments, 241 groups, all hosts | **0.48** (0.50–0.71 within host) |
| R² time ~ persisted segments (an output, not a weight) | 0.64 |
| segment packing: source segments per host | 1.18 / 1.21 / 1.21 / 1.24 M ("balance = 100%") |
| measured minutes per host under that packing | **165 / 205 / 231 / 272** (job3 65% behind job1) |
| time-weighted LPT of the same 62 components, 4 hosts | 219 / 219 / 218 / 217 min predicted |
| **out-of-sample:** May-2026 time predicting Oct-2026 time, 104 overlap | **R² 0.83** vs 0.53 for segments on the same groups |
| min per 1000 source segments | 0.06 (GRNL, UEUT, LKEC) → 0.86 (VICT), CHWK 0.82 |

Per-WSG modelling cost is a stable property of the group across five months of code change,
segment count explains under half of it, and the run that happened finished ~53 min (19%)
later than a time-weighted pack of the same components predicts. The weight should be
measured time, with the loud-failure property segment count had.

## Decided at the gate (operator, 2026-10-20)

1. **Coverage gate:** a modelable group with no finished `log` row makes the packer **refuse**,
   naming the groups; `--fill-missing` opts into `source segments × median(min per source
   segment over the measured groups)` for them. The coverage line (`n measured / n modelable`,
   filled share of total minutes) prints to stderr either way.
2. **Time source:** newest finished row per group in `<schema>.log`, any run_uid, any host;
   schema from `cfg$pipeline$schema`, overridable with `--schema=` (as the driver does).
   Minutes are not normalised by host (October measured the hosts equal; stated as a confound).
3. **`--host-speeds` default becomes equal** (`rep(1, n_hosts)`); the flag stays for a mixed
   fleet. With time weights the report's load is then real minutes.
4. **`research/study_areas.md` is regenerated in this PR** with `--write` (246 focal, `default`,
   4 hosts), so the committed `--focal=` strings are the time-weighted split.
5. `--weights=segments` keeps the old behaviour exactly (same query, same median fill), so the
   validation script can reproduce the run's packing.

## Phase 1: Library and tests — weights and LPT as pure functions

The packer is a top-level script with no tests. Lift its weight and packing logic into a
sourced library so the packer and the validation script derive one fact once, and test it the
way `tests/testthat/test-study_area_hosts.R` tests `data-raw/study_area_hosts.sh` (skips when
`data-raw/` is absent under `R CMD check`; `LNK_TEST_*_LIB` env points at a mutant copy).

- [ ] `data-raw/study_area_pack.R` (sourced, no top-level side effects): `pack_weights_segments(conn)`
      (the current query + median fill), `pack_weights_time(conn, schema)` (newest finished
      `log` row per group → minutes, SQL `DISTINCT ON (watershed_group_code) … ORDER BY date_start DESC`),
      `pack_weight_of(resolved, measured, n_src, fill_missing)` (returns per-component weight
      plus a coverage record: measured / filled groups, filled minutes share; errors naming the
      unmeasured groups unless `fill_missing`), `pack_lpt(weight, host_speeds)` (the loop at
      `:213-223`, returning `assign`, `load`, `seg`).
- [ ] `tests/testthat/test-study_area_pack.R`: LPT picks the earliest-finishing host (a 2-host
      case where equal speeds and 1 / 0.45 speeds assign differently); refusal names every
      unmeasured group and does not fire with full coverage; `fill_missing` uses the median
      *rate* × that group's segments, not the median minutes; a group absent from the network
      table and the log still refuses rather than packing as free; coverage record counts.
      Written first, red against a lib that lacks the gate (restore-the-bug mutant via env var).

## Phase 2: Packer — `--weights=time` default, coverage gate, minutes in the report

- [ ] `data-raw/study_area_buckets.R`: source the lib; new args `--weights=time|segments`
      (default `time`), `--schema=`, `--fill-missing`; `host_speeds` default `rep(1, n_hosts)`.
- [ ] Section 4 comment and the generator paragraph at `:408-417` rewritten to carry the
      rationale (the table above, in one paragraph: R² 0.48 / 0.83, 272 vs 219 min) and drop the
      stale "dispatcher is relabelled" text (`073efebd` removed the relabel; the doc still says it).
- [ ] Report: the host-bucket table gains `est. min` (load in minutes when weights are time) and
      a `weights:` / coverage line; `--write` emits the same.
- [ ] Usage header documents the three flags and the refusal.

## Phase 3: Validate — predicted vs measured on the real run, committed evidence

- [ ] `data-raw/study_area_weights_validate.R --run-uid=<uid> --schema=<schema> [--config=default]`:
      per-WSG table (wsg, host, minutes, source segments, persisted segments, May-2026 median s
      from `data-raw/logs/**/*_per_wsg_times.csv`); fits (R² per weight overall, within host,
      out-of-sample May→Oct); per-host measured minutes under the run's packing against the
      segment weight's prediction (balanced, converted at the run's mean rate) and against
      `pack_lpt()` of the run's components under time weights. Components are taken from the
      packer run in-process (`frs_wsg_drainage` closures, as the packer does), not re-typed.
- [ ] Commit `data-raw/logs/comp_weight_259/` (`per_wsg.csv`, `fit.csv`, `hosts.csv`,
      `README.md` with the environment stamp: link SHA, run_uid, schema, date).
- [ ] Regenerate `research/study_areas.md` with
      `LNK_LOAD=loadall Rscript data-raw/study_area_buckets.R --config=default --hosts=4 --focal=<all 246> --write`
      and confirm two consecutive `--write` runs are byte-identical (the #246 property).

## Phase 4: Record

- [ ] `research/study_area_run.md`, "Hosts against wall clock" bullet: the packing cost 53 min
      against a time-weighted pack; "a fifth host buys nothing" becomes "buys 14 min" (205 floor).
- [ ] `research/recompute_parallel_2026_09_01.md:75-80`: the "not sufficient to change
      comp_weight" paragraph gets a dated superseded note pointing at #259's evidence.
- [ ] `RUNBOOK.md` "Host buckets are derived, not chosen": weights are measured minutes from
      `<schema>.log`; the refusal and `--fill-missing`.
- [ ] `NEWS.md` entry under a new dev heading; `CLAUDE.md` status paragraph (facts not worth
      re-deriving: the R² table, the 272-vs-219 comparison, the May→Oct stability).
- [ ] Issue body: acceptance boxes ticked, "Measured" section updated (done at merge, step 3b).

## Owed at the end (reported, done after merge)

- [ ] The time weight's own prediction is validated on the **next** provincial run: the
      packer's `est. min` per host against that run's `log` sums (`study_area_weights_validate.R`
      with the new run_uid). One run cannot validate both the weight it used and the counterfactual.
- [ ] `data-raw/wsgs_dispatch.sh` (legacy dispatcher) still carries the silent `[LPT] … deterministic
      split` fallback the issue cites; not touched here — note in the archive README.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- `devtools::test()` green (new `test-study_area_pack.R` runs from the source tree, skips under check).
- `Rscript data-raw/study_area_buckets.R --config=default --hosts=4 --focal=<246> --weights=segments`
  reproduces `data-raw/logs/provincial_246/buckets_default.md`'s component table and host
  segment totals (the old behaviour is unchanged).
- `--weights=time` on the same focal set prints coverage `241/241` and per-host minutes within
  a few minutes of 219 / 219 / 218 / 217; a `--focal=` containing an unmodelled group refuses and
  names it; `--fill-missing` then packs it at the median rate.
- `study_area_weights_validate.R` reproduces the planning numbers above (R² 0.48 / 0.83; 165–272 measured).
- `/code-check branch` before the PR; `lintr` on the new R files.
