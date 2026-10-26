# Code-check round 4 — terminal enumeration (#260)

## Checklist read

- `index_code-check.md` (37 headings): read in full. `code-check.md`: the prose of all 14 H3s under `## Mechanisms` read in full (tables skipped); of the 23 "Rules that stand alone" / Security / Spreadsheets headings, none names a tool or shape this diff uses, so 0 read in full (23 not).
- `index_code-check-r.md` (111 headings): read in full. Full sections read: "Postgres row order is never fixed…", "Rscript reads a script as it runs…", "`read.delim()` quotes by default…", "`Rscript -e` supplies `--args`…", "A range total taken as the difference…", "`system2(stdout = TRUE)` warns…" (6 read; 105 not — none names a tool or shape in this diff beyond these; `on.exit()` and `data-raw/` load-the-source-tree are covered by the index line and the code already obeys them).
- `index_code-check-shell.md` (67 headings): read in full. Full sections read: "`wait` with no argument…", "Empty arrays under `set -u` on bash 3.2", "A second `trap … EXIT` replaces the first", "A failed `cd` lets every later command run…", "Parallel writers sharing one output file…", "psql does not interpolate `:'var'`…", "Put cleanup on the EXIT trap, not RETURN…" (7 read; 60 not).
- `index_code-check-spatial.md` (93 headings): read in full; no heading names a tool this diff uses (0 read in full; 93 not).

## How each claim was checked

Re-ran `span.sql` and `gaps.sql` read-only against local `fwapg` (both reproduce `span.tsv` / `gaps.tsv` exactly); recomputed every median in `timings.tsv` in R; re-derived the share table from `20261023_074321_recompute.log` (SALR 0.72 min, CHWK 15.56, LFRA 22.76, median 159.3 s, 240 lines); decomposed the span's slack in SQL (gap slot-min 37.5, tail slot-min 8.04, head slot-min 0.01; no ties in `date_start` / `date_end`; no negative paired gap, min 1.57 s); measured `lnk_stamp(cfg, conn = NULL, aoi = "SALR")` in the job's order (after `lnk_load_overrides()`, species, presence): under `load_all()` in the real checkout 0.092 / 0.100 / 0.095 s (3 processes, first call), under `library(link)` from the repo root 0.040 s and from scratch 0.037 / 0.036 s; re-counted the namespaces `lnk_load_overrides()` loads under `library(link)` (17, 0.241 s first call, 0.058 s second, twice); counted `LNK_LOAD` readers (12); checked line refs at HEAD and v0.48.0; checked `proc.time()` against a shell-launch clock (0.079 vs 0.105 s at R's first expression).

**The round-3 `lnk_stamp` dispute:** the author's re-measurement is right. The job's call (first `lnk_stamp()`, after overrides) costs 0.10 s under `load_all()` and 0.04 s under `library(link)`, a 0.06 s difference. Round 3's 0.24 s matches `lnk_load_overrides()`'s first call under `library(link)` (its deferred namespace loads), not the stamp.

## Claim table

### `data-raw/logs/loadall_260/README.md`

| # | claim | verdict |
|---|---|---|
| 1 | 10 CPUs | SUPPORTED `env.txt` ncpu |
| 2 | no active client backend | SUPPORTED `env.txt` pg_active_before 0 |
| 3 | 1-min load average 4.03 before the run | SUPPORTED `env.txt` |
| 4 | link HEAD `c7e23509`, installed 0.68.0, R 4.5.2 | SUPPORTED `env.txt` |
| 5 | every pool job is a fresh `Rscript wsg_recompute_one.R` under `LNK_LOAD=loadall` | SUPPORTED `study_area_run.sh:705-710` |
| 6 | 12 `data-raw/` R scripts read `LNK_LOAD` | SUPPORTED `grep -l LNK_LOAD data-raw/*.R` = 12 |
| 7 | `prologue.R` runs what the job runs before `t0` (`:26-62`) | SUPPORTED (load block at 26, `t0` at 62; config/schema hardcoded to `default`/`fresh_default`, as the 2026-10-23 run used) |
| 8 | 20 in sequence (first as `cold`), 3 waves of 8, 10 beside 7 CPU-bound R | SUPPORTED `timings.tsv` counts 1+19 / 24 / 10 per mode |
| 9 | `date_start` written after the prologue, so summed work leaves every prologue out | SUPPORTED `R/lnk_log.R:1352-1365` (`now()` at insert, after `lnk_stamp`) |
| 10 | bench table 1.10/0.62/0.74, 1.44/0.82/0.94, 1.63/0.92/1.08 | SUPPORTED recomputed medians (1.097/0.625/0.739; 1.435/0.816/0.935; 1.630/0.919/1.084) |
| 11 | SALR 43 s → 3.6 %; median 159 s → 1.0 %; CHWK 934 s → 0.2 % | SUPPORTED recompute.log + p/(w+p) |
| 12 | SALR 11 s → 12.9 %; CHWK 226 s → 0.7 % (#260's framing) | SUPPORTED arithmetic; #260 body cites 11 s / 226 s |
| 13 | whole pool 240 × 1.63 / 8 = 0.81 min of 110.3 = 0.74 % | SUPPORTED `span.tsv`, arithmetic |
| 14 | `library(link)` saves 0.71 s/job in the prologue | SUPPORTED 1.630 − 0.919 |
| 15 | plus 0.06 s in `lnk_stamp()` (0.10 under `load_all`, 0.04 under `library`) | SUPPORTED re-measured 0.092–0.100 vs 0.036–0.040 (not in an evidence file) |
| 16 | about 0.78 s/job, 0.39 min of the span | SUPPORTED 0.711 + 0.06 ≈ 0.77–0.78; 240 × 0.78 / 8 / 60 = 0.39 |
| 17 | median gap 9.70 s, p10 7.67, p90 12.01, max 15.73, 232 gaps, 37.5 slot-min | SUPPORTED `gaps.sql` re-run |
| 18 | gap holds next prologue + `lnk_stamp()`, previous exit, slot poll (≤ 1 s) | SUPPORTED `study_area_run.sh` pool loop (`sleep 1`), `wsg_recompute_one.R` tail after `.rc_finish` (also the `information_schema` probe in `.lnk_log_recompute_start`, negligible) |
| 19 | the bench explains about 3 s of it | SUPPORTED as an approximation (1.63 + 0.10 + ≤ 1 s poll ≈ 2.7 s; exit unmeasured) |
| 20 | the other 6 to 7 s are unmeasured | SUPPORTED-approx (9.7 − ~2.7 ≈ 7.0) |
| 21 | span 110.3 min exceeds summed work / 8 (104.6) by 5.7 min | SUPPORTED `span.tsv` (837.0 / 8 = 104.6) |
| 22 | those gaps 37.5 / 8 = 4.7 min, and the tail 1.0 min | SUPPORTED (tail slot-min 8.04 / 8 = 1.0; head 0.01) |
| 23 | in-run bound 4.7 min, 4.3 % of the span | SUPPORTED as "of the span" (4.7 / 110.3 = 4.26 %); see finding 1 for "of the phase/pool" |
| 24 | `library(link)` removes only part: about 0.78 s/job | SUPPORTED (#16) |
| 25 | about 2 min (under 2 %) if the in-run prologue is five times the bench | SUPPORTED 0.78 × 5 × 240 / 8 / 60 = 1.95 min = 1.77 % |
| 26 | `load_all()` makes each job run the tree verified at pre-flight | SUPPORTED as the issue's stated design (holds only under "never touch the repo mid-run"; inherited, not a number) |
| 27 | span set by summed work over slots (104.6), not the longest job (22.75) | SUPPORTED `span.tsv` longest 22.75 (LFRA) |
| 28 | each prologue on the critical path at one slot in eight | SUPPORTED (throughput-bound pool, #27) |
| 29 | 1.63 s on SALR's 11 s is 12.9 % of the job | SUPPORTED |
| 30 | CHWK 15.56 min ≈ 1.9 min of the span | SUPPORTED recompute.log 15.56; /8 = 1.95 |
| 31 | next lever #374 (overlap the recompute with the slowest leg) | SUPPORTED #374 body ("most of the recompute would then overlap with the slowest leg") |
| 32 | `wsg_recompute_one.R` now prints `[wsg_recompute_one] <WSG> prologue <s> s` at `t0`, `proc.time()` elapsed from the R process's start | SUPPORTED diff; `proc.time()` measured from R's start (excludes ~25 ms of the `Rscript`→`R` wrapper) |
| 33 | so the next run's log … "says what the other 6 to 7 s of each gap are" | UNSUPPORTED — finding 2 |
| 34 | #260 cites `:24-28` (v0.48.0); now `:26-30` | SUPPORTED `git show v0.48.0:` and HEAD |
| 35 | 110 min hand-built in `research/study_area_run.md`; no `_phases.tsv` for that run | SUPPORTED `research/study_area_run.md:231`; no `20261023_074321_phases.tsv` |
| 36 | `log_recompute` gives 110.3 min | SUPPORTED `span.tsv` |
| 37 | `load_all()` loads Imports in its stage; `library(link)` defers them | SUPPORTED by the namespace count (#38) |
| 38 | first `lnk_load_overrides()` under `library(link)` loads 17 namespaces, 0.24 s | SUPPORTED re-measured 17, 0.241 s (not in an evidence file) |
| 39 | its second call 0.05 s | WRONG (trivial) — finding 3 |
| 40 | overrides 0.24/0.30/0.33 vs 0.11/0.15/0.15 | SUPPORTED recomputed medians (0.237/0.296/0.328; 0.108/0.147/0.150) |
| 41 | totals and the 0.71 s saving unaffected | SUPPORTED (#14 uses totals) |

### `research/recompute_parallel_2026_09_01.md` (header + candidates 1 and 2)

| # | claim | verdict |
|---|---|---|
| 42 | header: revised its line reference, candidate 1, candidate 2 | SUPPORTED diff touches exactly those three |
| 43 | `wsg_recompute_one.R:26-30` | SUPPORTED |
| 44 | cand 1: 1.63 s beside seven loops; saves about 0.78 s | SUPPORTED (#10, #16) |
| 45 | cand 1: median 9.7 s, 4.7 min of 110.3, at most 4.3 % of it (the span) | SUPPORTED (#17, #23) |
| 46 | cand 1: read by 12 `data-raw/` scripts | SUPPORTED |
| 47 | cand 2: floor binds for the 4–8 group sets measured here | SUPPORTED headline table (CHWK 226 s vs 242 / 287 s at `-j4`) |
| 48 | cand 2: 110.3 span, 5.7 above 104.6, longest 22.75; throughput-bound; CHWK reaches the span at one slot in eight | SUPPORTED `span.tsv` |

### `CLAUDE.md` "Status (2026-10-26)"

| # | claim | verdict |
|---|---|---|
| 49 | prologue at most 4.3 % of the 2026-10-23 pool | SUPPORTED of the span; finding 1 for the pool/phase |
| 50 | `LNK_LOAD` contract (12 scripts) stays | SUPPORTED |
| 51 | 1.63 s beside seven loops (0.81 min of 110.3); saves about 0.78 s | SUPPORTED |
| 52 | median 9.7 s (4.7 min of the span); bench explains about 3 s | SUPPORTED (#17, #19) |
| 53 | job prints its prologue at `t0` | SUPPORTED diff |
| 54 | #377's next item is #374 | SUPPORTED #377 order (next unchecked after #260) |
| 55 | `t0` and `date_start` set after load/connect/config/overrides (`:62`) | SUPPORTED |
| 56 | span − summed work / slots = 5.7 min, everything outside `[date_start, date_end]`: 4.7 min gaps + 1.0 min tail (`gaps.sql`) | SUPPORTED (gaps.sql gives the 4.7; the tail is the remainder against span.sql) |
| 57 | no `_phases.tsv` for 2026-10-23 (began with #375); 110 min is first start to last end in `log_recompute` | SUPPORTED |

### #260 body (Measured + acceptance)

| # | claim | verdict |
|---|---|---|
| 58 | 1.63 s vs 0.92 s; ~0.78 s/job with the stamp, 0.39 min | SUPPORTED |
| 59 | 240 groups, `-j8`, 110.3 min span; median 9.7 s; 4.7 min | SUPPORTED |
| 60 | bench explains about 3 s, rest unmeasured | SUPPORTED-approx |
| 61 | "at most 4.3 % of the phase" | UNSUPPORTED as a strict bound on the phase — finding 1 |
| 62 | shares SALR 12.9 / 3.6, CHWK 0.7 / 0.2 | SUPPORTED |
| 63 | prologue now `:26-30`, 12 scripts read `LNK_LOAD`, not five | SUPPORTED (v0.48.0 body names four siblings + this one) |
| 64 | acceptance: measured and recorded as a share of a short and a long WSG | SUPPORTED README share table |
| 65 | N/A items (not changed; twelve by 2026-10-26) | SUPPORTED |

### #377 lines

| # | claim | verdict |
|---|---|---|
| 66 | #376: PR #380, v0.68.5 | SUPPORTED `gh pr view 380`, `git tag --contains` |
| 67 | #376: expected about 270 → 216 min (`buckets_group5.md`) | 216 SUPPORTED; 270 UNSUPPORTED by the cited file — finding 4 |
| 68 | #376: dispatcher + one worker, six groups, both verifiers pass, Run A critical path 11.5 min, worker consolidate 1.9 min for three groups | SUPPORTED `worker_376/README.md` |
| 69 | #376: stalled worker group named and worker released; killed loop caught by missing end marker and kept | SUPPORTED `worker_376/README.md` Runs B, C |
| 70 | #376: provincial numbers and `--host-speeds` still owed | SUPPORTED |
| 71 | #260: at most 4.3 % of the 2026-10-23 pool (median 9.7 s, 4.7 of 110.3), 1.63 s, ~0.78 s saved | SUPPORTED; finding 1 for "of the pool" |
| 72 | #261: pool bound by summed work (110.3, 104.6 over 8, longest 22.75); CHWK ≈ 1.9 min | SUPPORTED `span.tsv`, recompute.log |

### Code: the new `cat()` in `data-raw/wsg_recompute_one.R`

No defect. `proc.time()[["elapsed"]]` works on the `proc_time` object; it sits after the SKIP `quit()`, so a skipped group prints nothing new; the line cannot match `recompute_order()`'s sed (`study_area_run.sh:747`, anchored on `recomputed in`), `recompute_sweep.sh:137` (`recomputed in [0-9.]* min`), `shares.R`'s regex, or `fanout_judge.R` (reads the `.rc` TSV, not logs); no test asserts this script's stdout (the `test-study_area_*` tests mock `Rscript` calls); `study_area_finish.sh:621` only concatenates the per-job logs.

## Findings

- **[low]** CLAUDE.md (2026-10-26 status, first sentence), #260 body ("at most 4.3 % of the phase"), #377 #260 line ("at most 4.3 % of the 2026-10-23 pool") — the 4.7 min bound is gaps inside the span, and the span starts at the first job's `date_start`, so the first wave's eight prologues (all eight `date_start` within one second at 18:06:49) run before it and are in neither the gaps nor the span. As a bound on the phase it is (4.7 + one prologue) / (110.3 + one prologue): about 4.4 % if the in-run prologue is near the gap's ~10 s. The README and research file say "of the span", which is right. The verdict does not change; either say "of the span" in the three places or fold in the first wave.
- **[low]** `data-raw/logs/loadall_260/README.md`, "Owed" — "so the next provincial run's `<TS>_recompute.log` measures it in place, and says what the other 6 to 7 s of each gap are". The new line reports only the prologue up to `t0` (measured from R's own start). It cannot say what the rest is: `lnk_stamp()` plus the `information_schema` probe, the previous job's exit and the poll stay unmeasured. It can say only whether the prologue fills the gap. Reword to "and whether the prologue accounts for the other 6 to 7 s".
- **[low]** `data-raw/logs/loadall_260/README.md`, Notes — "its second 0.05 s". Re-measured in two processes in the prologue's order under `library(link)`: 0.058 s both times, so 0.06. The 17 namespaces and 0.24 s reproduce. Neither figure is recorded in an evidence file.
- **[low]** #377, #376 line — "Expected: about 270 → 216 min (`data-raw/logs/provincial_361/buckets_group5.md`)". `buckets_group5.md` holds 216 (and 231 under component atoms) but no 270. The 270 is four hosts' makespan in `buckets_group4.md:84`. Cite both. This text may predate the branch.
