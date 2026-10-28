# Code-check round 1: #259 branch (998c986a...HEAD)

## Checklist read

- code-check.md.index, code-check-r.md.index, code-check-shell.md.index and code-check-spatial.md.index: in full.
- code-check.md: the prose of every H3 under `## Mechanisms`, all 14 of them, with the `|` table rows skipped. None of the standalone rules applied.
- code-check-r.md: read these 5 sections in full: "`read.delim()` quotes by default", "`system2(stdout = TRUE)` warns on a non-zero exit", "`Rscript -e` supplies `--args`", "Postgres row order is never fixed", "`ifelse()` with an all-NA test". About 150 other headings were not read beyond their index line.
- code-check-shell.md: read "awk `==` compares version strings as numbers" in full. The other headings were checked against the diff from the index only.
- code-check-spatial.md: index only. Nothing spatial is in the diff.

Probes, run from scratch copies with nothing written to the repo:
- `test-study_area_packing.R`, `test-host_speeds_calibrate.R` and `test-study_area_finish.R`: all pass, with NOT_CRAN=true.
- Simulation re-run: whole-leg 0.706 and per-group means 0.140 at 20 runs. Both match the docs.
- `speeds_calibrate()` probes for findings 1 and 2 below. Their output is quoted in each finding.

## Findings

- **[fragile] A worker's speed is learned under its positional key `worker1`, which contradicts the docs and re-creates the m1→m4 problem.**
  - Where: `data-raw/study_area_buckets.R:144` with `data-raw/study_area_packing.R:178`, against `RUNBOOK.md:2040` and `CLAUDE.md:23`.
  - The docs say a worker is learned only under an alias passed in `--host-names`, and takes the median until then.
  - The code does not enforce that. The packer's default `--host-names` names workers `worker1..N`. `host_names_check()` accepts `worker1`, the plan carries it as `name`, and `speeds_calibrate()` adds any plan name that is new to the state.
  - Probe: a plan with a `worker1` leg, packed at the median, put `worker1 0.9333` into the state after one run.
  - Consequence: the committed state then holds a speed keyed by a driver role. Whatever machine is `worker1` on the next run inherits it. That is exactly what the name keying exists to prevent: a factor keyed `dispatcher` carrying m1's speed onto m4.
  - Fix, either of:
    - the calibrator refuses, or skips with a history row, any name of the form `^worker[0-9]+$`;
    - the packer gives an unnamed worker a name the calibrator recognises as unlearnable.

- **[fragile] The calibrator damps from the speed in the plan, not from the stored factor, so a `--host-speeds` run overwrites the learned state.**
  - Where: `data-raw/host_speeds_calibrate.R:144` and `data-raw/study_area_packing.R:159`.
  - `old` is `plan$speed`, the speed the run was packed at. `state_new$factor` is then set to `0.7·old + 0.3·observed`.
  - Problem case A: a run packed with `--host-speeds`. RUNBOOK §8d still names that as how to set a worker's speed by hand, and the plan records `speed_source = --host-speeds`, but the calibrator ignores that column. The update then starts from the hand-typed number, not from the learned factor.
  - Problem case B: a calibration lands between this run's packing and its calibration, for example two runs packed from one state and calibrated in turn. The earlier update is silently discarded.
  - Probe: state cloud 1.0, run packed at `--host-speeds=1,0.45,0.45,0.45`, true ratio 1.0. After one calibration the state's cloud factor is **0.47**, and m1's is 0.857.
  - That is a one-run move below the documented `[0.5, 2] × old` clamp measured against the stored factor. The history reports `old` = 0.45, so the record shows nothing unusual.
  - Fix, either of:
    - damp and clamp from `state$factor` (median or 1 when absent);
    - refuse a plan whose `speed` differs from the current state's factor, or whose `speed_source` is `--host-speeds`.

- **[fragile] Measured minutes are normalized under one key and speeds are learned under another, and nothing checks that the two meet.**
  - Where: `data-raw/study_area_buckets.R:310` and `data-raw/study_area_packing.R:58-119`.
  - `weights_normalize()` looks up the state by `host_class(log.host)`. `log.host` is `.lnk_host()`: `LNK_HOST_ALIAS` if set, otherwise the full `nodename`. A `cypher-*` host maps to `cloud`.
  - The state is learned under the `--host-names` value, whose default is the nodename with its domain stripped.
  - These diverge whenever:
    - a worker's alias in `--host-names` (say `m2`) is not its log host (its nodename, or a different `LNK_HOST_ALIAS`);
    - cloud hosts are given any name other than `cloud`;
    - a dispatcher's nodename carries a domain, so `x.local` is logged and `x` is learned.
  - In every case the lookup misses and falls back silently to the median. No line of the report says which source normalized which group.
  - The convergence argument (RUNBOOK §8d, "Why it learns slowly") rests on movers being normalized by the learned speed of the host that measured them. Under a mismatch a mover is predicted at the median, and the correction chases that.
  - Fix, both of:
    - count the normalization sources (learned or median) per log host in the report;
    - or refuse a log host that is not a state name or a known class, when a state exists.

- **[doc] Four claims do not match `fit.md` or the code.**
  - **3.6 against 28.9 is quoted without its condition.** `CLAUDE.md:16`, `RUNBOOK.md:2024` and the packer comment at `study_area_buckets.R` around lines 285-290 give "minutes within 3.6 points, segments 28.9" with no qualifier. Those figures come from the table with KTSU and OKAN left out. As logged, `fit.md` gives minutes 16.4 and segments 28.5. `research/study_area_run.md` states the exclusion, but the other three drop it.
  - **The 11 to 20 % range is too wide.** `research/study_area_run.md:247` says "With minutes, every leg is short by 11 to 20 %". The minutes/equal row it describes is −11, −17, −15 and −11 %. The −20 is in the `learned` row.
  - **"Every group" overstates a sum.** `RUNBOOK.md:2068` and `data-raw/study_area_packing.R:26` say "every group ran 13 to 16 % slower". The figure is a summed ratio per class, 1.130 for m1 and 1.159 for cloud. Individual groups vary: cloud → m1 is 0.941.
  - **The worker claim.** "A worker is learned only under an alias" in `CLAUDE.md:23` and `RUNBOOK.md:2040` is false as the code stands. See finding 1.

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
