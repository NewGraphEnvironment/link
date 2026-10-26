# Code-check round 3: terminal enumeration of the #260 write-ups

Reviewer: unnamed subagent, 2026-10-26. Read-only. Measurements below came from SELECTs on
local `fwapg` and from two scripts run in the scratchpad (one against a copy of the repo).
No repo file was edited except this one. `measure.sh` was not run.

## Checklist read

- `index_code-check.md`: read in full (39 headings).
- `code-check.md`: read the prose of all 14 `## Mechanisms` H3s, table rows skipped. That
  includes "A guard's scope, escape hatches, and remedies", "Verification that reads its own
  output", "The probe is broken before the world is" and "One fact derived twice". The 25
  other H3s (stand-alone rules, Security, Spreadsheets) were read as index lines only,
  because this diff uses none of their tools.
- `index_code-check-r.md`: read in full (111). Full sections read (3): "`read.delim()` quotes
  by default", "Postgres row order is never fixed…", "A range total taken as the difference…".
  Not read in full: 108.
- `index_code-check-shell.md`: read in full (67). Full sections read (7): "`wait` with no
  argument…", "Empty arrays under `set -u` on bash 3.2", "A second `trap … EXIT` replaces the
  first", "Put cleanup on the EXIT trap, not RETURN", "Parallel writers sharing one output
  file…", "On this Mac `stat` and `date` are GNU…", "psql does not interpolate…". Not read in
  full: 60.
- `index_code-check-spatial.md`: read in full (93). No full sections read, because the diff
  has no spatial code.

## Evidence I re-derived for this round

- **E1** `span.sql` re-run: `240 / 110.3 / 837.0 / 22.75`, identical to `span.tsv`. The
  longest job is LFRA (22.75 min), not CHWK (15.55 in `log_recompute`, 15.56 in the log).
- **E2** The idle slot time inside the 2026-10-23 pool, from `fresh_default.log_recompute`,
  one-second integration of `8 − running`:
  - **37.8 slot-min** fell before the last job started, when the queue was not empty. That
    is the gap between one job's `date_end` and the next job's `date_start` on a slot.
  - **7.8 slot-min** is the tail, after the last start.
  - The sum, 45.6, matches `8 × 110.3 − 837.0 = 45.4`.
- **E3** The same gap, per job, pairing the k-th start with the (k−8)-th end, 232 gaps: min
  1.57 s, p10 7.67, **median 9.70**, mean 9.69, p90 12.01, max 15.73. Total 37.5 slot-min,
  which does not depend on the pairing. **41 of 232 gaps exceed 11.3 s.** That count does
  depend on the approximate pairing.
- **E4** The log's t0-based "recomputed in" minutes sum to 839.2 min. `log_recompute`
  (date_start-based) sums to 837.0 min. That is 0.55 s per job between `t0` and
  `date_start`, plus what runs after `date_end`. So the ~9 s per-job gap of E3 lies almost
  entirely before `t0` or after the script exits: R startup, the prologue, exit, the 1 s poll.
- **E5** `lnk_stamp(cfg, conn = NULL, aoi = "SALR")` timed in a copy of the repo with
  `GIT_OPTIONAL_LOCKS=0`, three runs each:
  - under `load_all()`: 0.44 / 0.24 / 0.24 s (`sha_source = git`);
  - under `library(link)`: 0.042 / 0.039 / 0.040 s (`remote_sha`).

  `.lnk_log_recompute_start()` calls it after `t0` and before the INSERT that sets
  `date_start = now()` (`R/lnk_log.R:1352`, `:1366`), so prologue.R does not time it.
- **E6** The prologue's order, reproduced under `library(link)`: the first
  `lnk_load_overrides()` loads 17 namespaces in 0.234–0.249 s, the second takes 0.054–0.055 s.
- **E7** `git grep -l LNK_LOAD -- 'data-raw/*.R'` gives 12 scripts.
- **E8** `git show v0.48.0:data-raw/wsg_recompute_one.R` puts the load block at :24-28; HEAD
  has it at :26-30.

## Enumeration

### data-raw/logs/loadall_260/README.md

| # | claim | verdict |
|---|---|---|
| R1 | 2026-10-26, dispatcher, 10 CPUs | SUPPORTED: env.txt `date_utc`, `ncpu 10` |
| R2 | no active client backend | SUPPORTED: env.txt `pg_active_before 0` |
| R3 | 1-min load average 4.03 before the run | SUPPORTED: env.txt `uptime_before` |
| R4 | HEAD `c7e23509`, installed link 0.68.0, R 4.5.2 | SUPPORTED: env.txt. env.txt also records `link_dirty 2 paths`, which the README omits; not wrong |
| R5 | 12 `data-raw/` R scripts read `LNK_LOAD` | SUPPORTED: E7 |
| R6 | prologue.R runs what `wsg_recompute_one.R` runs before `t0` (`:26-62`) | SUPPORTED: `t0` at :62, verified in rounds 1–2 |
| R7 | stage list (startup, load, DBI/RPostgres, connect, two SETs, config, overrides, species for SALR) | SUPPORTED: prologue.R |
| R8 | 20 in sequence, first reported as cold | SUPPORTED: measure.sh `N=20`; shares.R `seq1` → cold |
| R9 | 3 waves of 8 at once | SUPPORTED: `WAVES=3`, `WIDTH=8` |
| R10 | 10 in sequence beside 7 CPU-bound R processes, "the -j8 shape" | Counts SUPPORTED (`N/2`, `BUSY=7`). "The -j8 shape" is a proxy that E2–E4 show does not reproduce the run (F1) |
| R11 | `date_start` is written after the prologue, so the summed work leaves every prologue out | SUPPORTED (`now()` at INSERT, after `lnk_stamp`). It also leaves `lnk_stamp` out (F2) |
| R12 | shares.R inputs and outputs | SUPPORTED: shares.R |
| R13 | Measurement table, 9 cells | SUPPORTED: shares.txt `busy/conc/seq`, both blocks |
| R14 | SALR 43 s, 3.6 % | SUPPORTED: log 0.72 min; 1.63/(43.2+1.63) |
| R15 | median 159 s, 1.0 % | SUPPORTED: median 159.3 s |
| R16 | CHWK 934 s, 0.2 % | SUPPORTED: log 15.56 min |
| R17 | SALR 11 s, 12.9 %; CHWK 226 s, 0.7 % | SUPPORTED: arithmetic. The 2026-09-01 times are t0-based (recompute_sweep.sh greps "recomputed in"), so "work" is correct |
| R18 | whole pool 240 × 1.63 / 8 = 0.81 min of 110.3 (0.74 %) | Arithmetic SUPPORTED. **As what the pool paid: UNSUPPORTED**, and E2–E4 contradict it (F1) |
| R19 | `library(link)` saves 0.71 s/job = 0.35 min (0.32 %) | Arithmetic SUPPORTED. **As the saving: understated** (F2) |
| R20 | span 110.3 min, first job's work start to last job's end | SUPPORTED: span.tsv |
| R21 | span exceeds summed work / 8 (104.6) by 5.7 min | SUPPORTED: 110.3 − 837.0/8 |
| R22 | "at most 11.3 s of untimed slot time per job" | **WRONG as worded**: 11.3 s is a mean over jobs, not a per-job ceiling (E3: 41 of 232 gaps exceed it) (F3) |
| R23 | the bound covers everything outside `t0`: prologue, R exit, the driver's 1 s poll, the tail | **Incomplete**: the bound is on time outside `[date_start, date_end]`, which also holds `lnk_stamp` + INSERT after `t0` (E5). The tail is only 7.8 of the 45.4 slot-min (E2) (F1, F2) |
| R24 | "The prologue is 1.6 s of it" | **WRONG/UNSUPPORTED** for the run: the in-queue gap per job is a median 9.7 s (E3), nearly all before `t0` (E4). The bench reproduces ~2.5 s of it (F1) |
| R25 | removing it buys 21 s of a 110 min phase | Arithmetic SUPPORTED (0.355 min). Understated (F2), and bench-based (F1) |
| R26 | every prologue is on the critical path at one slot in eight; span set by summed work (104.6), not longest job (22.75) | SUPPORTED: E1 and span.tsv |
| R27 | 1.63 s on SALR's 11 s is 12.9 % of the job | SUPPORTED |
| R28 | "The recompute's time is its work" | SUPPORTED: 104.6 of 110.3 min is work |
| R29 | CHWK's 15.56 min ≈ 1.9 min of the span | SUPPORTED: log 15.56; 15.56/8 = 1.95 (an approximation, labelled "about") |
| R30 | next lever #374; #261 pays only if CHWK's cause slows other groups | SUPPORTED as reasoning from R26/R29; #377's order puts #374 next |
| R31 | #260 cites `:24-28` (v0.48.0); now `:26-30` | SUPPORTED: E8 |
| R32 | 110 min was a hand-built figure in `research/study_area_run.md` | SUPPORTED: study_area_run.md:231 gives "110 min" |
| R33 | no `_phases.tsv` for that run; phases began with #375 | SUPPORTED: no file in `study_area_run/20261023_074321_*` |
| R34 | `log_recompute` gives 110.3 min | SUPPORTED: E1 |
| R35 | `load_all()` loads Imports in its own stage; `library(link)` defers them | SUPPORTED: E6 |
| R36 | first `lnk_load_overrides()` under `library` loads 17 namespaces in 0.24 s, second 0.05 s | SUPPORTED by reproduction (E6). No committed evidence file records it |
| R37 | overrides 0.24/0.30/0.33 (library) vs 0.11/0.15/0.15 (load_all) | SUPPORTED: timings.tsv medians |
| R38 | totals and the 0.71 s saving unaffected by the namespace deferral | SUPPORTED, as a statement about deferral |

### research/recompute_parallel_2026_09_01.md

| # | claim | verdict |
|---|---|---|
| H1 | header: revised 2026-10-26, "candidate 1, measured" | **INACCURATE SCOPE**: the diff also revises candidate 2 and line 153 (F5) |
| H2 | load block at `wsg_recompute_one.R:26-30` | SUPPORTED: E8 |
| C1a | prologue 1.63 s/job "with seven slots computing beside it" | Number SUPPORTED (bench). "Seven slots" were 7 CPU-bound R loops, and E2–E4 show that condition does not reproduce the run (F1) |
| C1b | 0.81 min of 110.3 (0.74 %) | **UNSUPPORTED as the pool's cost** (F1) |
| C1c | `library(link)` would save 0.35 min | **Understated** (F2) |
| C1d | read by 12 `data-raw/` scripts | SUPPORTED: E7 |
| C1e | `load_all()` makes each job run the tree verified at pre-flight | SUPPORTED: design statement carried from #260's body |
| C2a | the floor held for the 4–8 group sets | SUPPORTED: 242 s vs CHWK 226 s; 287 vs 226 |
| C2b | "At provincial scope it does not" | **WRONG as worded**: the floor (span ≥ slowest job) holds at every scope (110.3 ≥ 22.75); at provincial scope it does not bind (F4) |
| C2c | 110.3 / 5.7 / 104.6 / 22.75 | SUPPORTED: span.tsv |
| C2d | the pool is bound by throughput | SUPPORTED |
| C2e | CHWK reaches the span at one slot in eight | SUPPORTED as an approximation |

### CLAUDE.md, Status (2026-10-26)

| # | claim | verdict |
|---|---|---|
| M1 | 1.63 s with seven slots computing beside it: 0.81 min of 110.3 (0.74 %) | **UNSUPPORTED as the pool's cost** (F1) |
| M2 | `library(link)` would save 0.35 min | **Understated** (F2) |
| M3 | `LNK_LOAD` contract (12 scripts) stays | SUPPORTED: E7 |
| M4 | #377's next item is #374 | SUPPORTED: first unchecked item in #377 |
| M5 | `t0` and `date_start` are set after load, connect, config and overrides (`:62`) | SUPPORTED: `t0` at :62; `date_start` later, at :112 via `.rc_start`, after `lnk_stamp` |
| M6 | span minus summed work over slots (5.7 min at -j8) bounds everything untimed | SUPPORTED as an aggregate (the first wave's prologues fall before the span) |
| M7 | "at most 11.3 s per job" | **WRONG as worded**: a mean (F3) |
| M8 | the 2026-10-23 run has no `_phases.tsv` | SUPPORTED |
| M9 | its 110 min is first start to last end in `log_recompute` | SUPPORTED: E1 |

### #260 body, "Measured" section and acceptance list

| # | claim | verdict |
|---|---|---|
| I1 | the stage list of the prologue | SUPPORTED: prologue.R |
| I2 | beside seven CPU-busy R processes, 1.63 s vs 0.92 s | SUPPORTED: shares.txt busy |
| I3 | 240 groups, -j8, 110.3 min span | SUPPORTED: E1; at most 8 running at once (my query) |
| I4 | 0.81 min, 0.74 % of the phase | **UNSUPPORTED as the phase's cost** (F1) |
| I5 | switching would save 0.35 min (0.32 %) | **Understated** (F2) |
| I6 | SALR 12.9 % / 3.6 %, CHWK 0.7 % / 0.2 % | SUPPORTED: shares.txt |
| I7 | "So the `LNK_LOAD` contract stays" | SUPPORTED at the bound (F1: still ≤ 4.3 % of the span) |
| I8 | "the upper bound on everything untimed, 11.3 s per job" | **WRONG as worded**: a mean (F3) |
| I9 | the prologue is now `:26-30` | SUPPORTED: E8 |
| I10 | 12 scripts read `LNK_LOAD`, not five | SUPPORTED: E7 |
| I11 | [x] measured, recorded as a share of a short and a long WSG | SUPPORTED (bench-measured; SALR and CHWK) |
| I12 | N/A item: "…coherent across all five scripts that share it" | **CONTRADICTS I10** in the same body (F6) |
| I13 | N/A: identity still assertable | SUPPORTED: unchanged |

### #377 body, the #376, #260 and #261 lines

| # | claim | verdict |
|---|---|---|
| P1 | #376: the fifth host; PR #380, v0.68.5 | SUPPORTED: `git log` (merge of #380, "Release v0.68.5"); PR MERGED |
| P2 | #376: expected about 270 → 216 min | SUPPORTED: `buckets_group4.md:84`, `buckets_group5.md:85` |
| P3 | #376: dispatcher and one persistent worker, six groups | SUPPORTED: worker_376/README.md |
| P4 | #376: worker modelled, accounted, consolidated, released; both verifiers pass (Run A) | SUPPORTED: worker_376 README, Run A row |
| P5 | #376: critical path 11.5 min; the worker's consolidate 1.9 min for three groups | SUPPORTED: worker_376 README, "Minutes" |
| P6 | #376: a stalled worker group named, the worker released | SUPPORTED: Run B row |
| P7 | #376: a killed loop caught by its missing end marker and kept | SUPPORTED: Run C row |
| P8 | #376: provincial numbers and `--host-speeds` still owed; #376 stays open | SUPPORTED: README; #376 is OPEN |
| P9 | #260: 1.63 s with seven slots computing, 0.81 min of 110.3 (0.74 %) | **UNSUPPORTED as the pool's cost** (F1) |
| P10 | #260: `library(link)` would save 0.35 min | **Understated** (F2) |
| P11 | #260: not material, so nothing changed | SUPPORTED at the bound (F1) |
| P12 | #261: at provincial scope the pool is bound by summed work, not its slowest job | SUPPORTED: E1 |
| P13 | #261: 110.3 span, 104.6 work over 8 slots, longest 22.75 | SUPPORTED: span.tsv |
| P14 | #261: CHWK alone is about 1.9 min | SUPPORTED: 15.56/8 |
| P15 | #261: pays only if its cause slows other groups | SUPPORTED as reasoning |

## Findings

- **[medium]** README.md:47-52 and 58-59 ("The prologue is 1.6 s of it"), with the same
  figure as the pool's cost in CLAUDE.md:16, the research file at candidate 1, #260
  "Measured" and #377's #260 line. **The run's own `log_recompute` contradicts treating the
  bench's 1.63 s as what the 2026-10-23 pool paid.**
  - Of the 45.4 slot-min of slack, 37.5–37.8 slot-min are gaps between one job's `date_end`
    and the next job's `date_start` while the queue was not empty (E2). Only 7.8 slot-min is
    the tail.
  - Per job, that gap is a median **9.70 s** (p10 7.67, p90 12.01; E3).
  - The t0-based log minutes exceed `log_recompute` by only 0.55 s per job (E4), so about
    8–9 s of each gap lies before `t0` or at process exit.
  - The bench accounts for about 2.5 s of it: prologue 1.63, `lnk_stamp` ~0.24, poll ≤ 1,
    exit.
  - So either the prologue ran ~5× slower in the run than in the "beside 7 busy" proxy, or
    something else unmeasured sits there. Either way, "0.81 min (0.74 %)" and "the prologue
    is 1.6 s of it" are bench numbers written as facts about the run.
  - The verdict survives at the bound: attributing the whole in-queue gap to the prologue
    gives 37.5/8 = 4.7 min, **4.3 % of the span**. The published share and saving could
    still be understated about 5×.
  - Fix: state the in-run gap (median 9.7 s/job, 4.7 min of span) beside the bench figure.
    Call 1.63 s the bench condition, not "seven slots computing beside it". Say the in-run
    excess is unexplained and the verdict rests on the 4.3 % bound.
- **[low]** README.md:45-46 and 60, CLAUDE.md:16, research candidate 1, #260 (`0.35 min
  (0.32 %)`), #377's #260 line. **The `library(link)` saving omits a load_all-only cost
  after `t0`.**
  - `.lnk_log_recompute_start()` runs `lnk_stamp()` between `t0` (:62) and the INSERT that
    sets `date_start` (`R/lnk_log.R:1352`, `:1366`), so neither prologue.R nor the summed
    work times it.
  - Under `load_all()` it takes the git path (0.24 s per call, E5); under `library(link)` it
    reads `RemoteSha` (0.04 s).
  - The switch would therefore save about 0.91 s per job (0.45 min of the span) in sequence,
    not 0.71 s (0.35 min).
  - The verdict is unchanged. README:52 also calls the bound "everything outside `t0`" when
    it is everything outside `[date_start, date_end]`, which includes this stamp.
- **[low]** README.md:51, CLAUDE.md:19 ("at most 11.3 s per job"), #260 ("11.3 s per
  job"), shares.R/shares.txt ("untimed slot time per job, upper bound").
  `(8·span − Σwork)/240` is a **mean** over jobs, not a per-job ceiling. Individual gaps
  run up to 15.7 s, and about 41 of 232 exceed 11.3 s (E3). Write "on average at most
  11.3 s per job".
- **[low]** research/recompute_parallel_2026_09_01.md, candidate 2 ("That floor held for the
  4–8 group sets measured here. At provincial scope it does not"). The makespan floor
  (span ≥ slowest job) holds at every scope: 110.3 ≥ 22.75 min. What changed is that it no
  longer **binds**; the span is set by throughput. As written, the sentence says the span
  fell below the slowest job.
- **[low]** research/recompute_parallel_2026_09_01.md:5. The revision line says only
  "candidate 1, measured" was revised. This diff also rewrites candidate 2 (the floor and
  throughput sentences) and the line reference at :153, so a reader comparing against
  2026-09-01 is not told that candidate 2 changed.
- **[low]** #260 body, acceptance list. The edited N/A item keeps "coherent across all
  **five** scripts that share it", while the same body's new "Measured" section says "12
  `data-raw/` scripts read `LNK_LOAD`, not five" (E7: 12). Edit the item to "all 12" or
  "every script".
