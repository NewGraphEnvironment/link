# variant_cost_404 — where a threshold variant's pass spends its time (#404)

## Run decision (written before any build)

- **What is measured.** One tuning iteration's per-variant pass in
  `data-raw/habitat_variants_build.R`, split into its seven steps (classify, connect, the
  working-habitat digest, persist, the access copy with `ANALYZE`, the habitat gate, the
  persisted digests) per group, with the base run's model and recompute minutes beside them.
  Nothing is made faster here; the change this names goes on #377.
- **Why the base is rebuilt.** m4 holds no `score*` or `working_score*` schema (queried
  `pg_namespace` on 2026-10-28), so the issue's "reuse an existing closure" cannot apply on
  this host. The base is #331's: `default` over the 17-group closure of REVL, ELKR, KOTR,
  UARL, MURR, UBTN, LHAF, PARS and KOTL (`variants_331.csv`, `wsg_roles_331.csv`), into
  `score404_default` with working schemas `working_score404_<wsg>`, so the totals sit beside
  the 2026-10-15 log (`habitat_score_331/build_20261015_full.log`). That comparison carries a
  caveat: #326 and #396 changed segmentation since, and m4 is not m1.
- **The variant.** `bt_rear_wet_p10` (BT `rear_mad_min` 0.043 on `mad`, discharge from wet),
  the first rung of #331's ladder, over its nine scoring groups. The `default` pass that
  every variants run makes first (all species, steps 1, 2, 3 and 7 only) is measured too.
- **Host and software.** m4 (Apple M4 Max, 128 GB), local docker fwapg (`fresh-db`),
  serial (`-j` 1, one group at a time). fresh 0.44.0 installed on 2026-10-28 19:03 UTC from
  the `v0.44.0` tag (`RemoteSha 22034c1a`, equal to `git rev-parse v0.44.0^{commit}`),
  replacing 0.43.0; link at the branch commit the stamp names (`stamp_build.txt`), run from
  a git worktree so this checkout can take commits while it runs. Discharge: wet's annual
  pick, `discharge.fwa_v1_segment_monthly` built 2026-10-15T02:06:57Z (wet `acb820f`).
- **Primitives.** `lnk_preflight_vintage()` passed on 2026-10-28 19:05 UTC, oldest load
  stamp 3.6 days (`whse_fish.pscis_assessment_svw`), so nothing was re-pulled.
- **Load from elsewhere.** At planning (11:40 PDT) the host's load average was 4.4 / 5.1 /
  5.3 with no R process of ours, so each timing row carries the 1-minute load average at its
  pass's start (`load_1min`); minutes are read beside it. The load at launch is in "What
  happened during the builds".
- **Parallel groups are not run.** The bound the issue estimates (passes over groups in
  parallel at about four jobs) is computed from the serial numbers only.
- **Statement depth only if one step holds more than half the pass** (median over the nine
  groups), on one group, through `PGOPTIONS='-c log_min_duration_statement=0'` and the
  container's log; no code change.
- **Schemas stay.** `score404_*` and `working_score404_*` are kept, as every `score*` schema
  has been.

## Files

| file | what it is |
|---|---|
| `build_base.log`, `build_preflight_revl.log`, `build_variants.log` | the builds (`--step=base`; the REVL pre-flight; then `--step=variants --only=bt_rear_wet_p10`) |
| `launch_state.txt` | each build's launch and exit time, the host's load average and the other client backends on the database at that moment |
| `closure.txt`, `base_habitat_digest.csv`, `base_recompute.csv`, `built.csv`, `stamp_build.txt`, `bundles/` | what the build script writes for any scoring build |
| `variant_timing.csv` | seconds per step per variant × group, with segment count and load (the build writes it; #404's instrumentation) |
| `analyze.R` → `steps.csv`, `split.csv`, `steps_vs_segments.png` | minutes per step and share of the pass; the model / verification / write split; minutes against segment count per step |

## What happened during the builds

`launch_state.txt` holds each boundary as it was taken. All three builds ran serially from
the worktree at `45b12b2e`, with no other backend on the database at any boundary
(`pg_stat_activity`, client backends other than the build's own).

| build | launched (UTC) | last log line (UTC) | the script's own "done in" | host load (1 min) at launch |
|---|---|---|---|---|
| `--step=base` (17 groups, then 9 recomputes) | 19:09:47 | 20:19:23 | 69.6 min | 2.4 |
| pre-flight `--step=variants --only=bt_rear_wet_p10 --wsgs=REVL` | 20:20:36 | 20:21:24 | 0.8 min | 2.2 (the base-end reading, 42 s before) |
| `--step=variants --only=bt_rear_wet_p10` (9 groups, `default` pass first) | 20:22:17 | 20:36:09 | 13.8 min | 2.1 |

The last log line is the script's own clock (PDT in the logs, UTC here); its total excludes
R start-up and `load_all()`. `launch_state.txt`'s "exited" lines are a waiter's first reading
after the process was gone (within 30 s), and its end-of-run snapshot was taken at 20:36:35.

Another process loaded the host during the variant builds: the 1-minute load average each
pass started at (`load_1min`) runs 2.1 to 6.3, highest at LHAF (6.3) and UBTN (6.3) in the
variant pass, and 3.7 at the end. The REVL pre-flight and the full pass produced the same
habitat digests (`default` `778f7c72`, `bt_rear_wet_p10` `15073c87`), so the re-run changed
no output; `variant_timing.csv` holds the full pass's rows for REVL.

## Measurement

**A variant's pass costs 0.3 to 1.0 min per group on m4 (5.6 min over the nine), and the
two verification steps are 0.4 % of it.** Pooled over the nine groups of `bt_rear_wet_p10`
(BT only, `mad` on wet's discharge), the pass splits as:

| step | kind | minutes (9 groups) | share of the pass |
|---|---|---|---|
| 1 classify (`lnk_pipeline_classify()`) | model | 2.04 | 36.5 % |
| 2 connect (`lnk_pipeline_connect()`) | model | 1.73 | 30.9 % |
| 3 `working_habitat_digest()` | verification | 0.005 | 0.1 % |
| 4 persist (`lnk_pipeline_persist()`) | write | 1.69 | 30.3 % |
| 5 `copy_access()` + `ANALYZE` | write | 0.09 | 1.6 % |
| 6 `lnk_habitat_gate()` | model | 0.02 | 0.3 % |
| 7 `digest_of()` over `streams` and `streams_access` | verification | 0.02 | 0.3 % |
| total | | 5.58 | |

So the split is **model 67.7 %, verification 0.4 %, write 31.9 %** (`split.csv`). Per group
the median shares are classify 0.35, connect 0.30 and persist 0.29, and no step's median
reaches half the pass, so the statement-depth probe (gate decision 6) was not run. The
seven steps sum to each pass's printed "done in" minutes within the log's 0.1 min rounding
(`analyze.R` asserts it on all 18 passes).

**The `default` pass that every variants run makes first** (all present species, steps 1, 2,
3 and 7 only) costs 6.8 min over the nine groups (0.3 to 1.5 per group): classify 48.5 %,
connect 51.0 %, the two digests 0.5 %. Outside both totals, the discharge join before each
pass costs 0.6 min per variant over the nine groups (0.8 for `default`), and
`lnk_persist_init()` under 1 s per variant.

**Steps scale with the group** (`steps_vs_segments.png`, 25,044 to 46,004 persisted segments):
classify and connect rise about linearly with segment count in both passes, with the
all-species pass about twice the one-species pass per segment; persist rises more slowly from
a floor of about 0.1 min. The point furthest above the connect fit (UBTN, 0.17 min where
REVL and UARL, of about its size, take 0.06 and 0.07) is a pass that started at a load of
6.3 from another process.

**Beside the base.** The base run modelled the 17-group closure in 67.1 min (`base_model`
rows: 1.7 min for LPCE to 7.0 for KOTR; 2.9 to 7.0 for the nine focal groups) and recomputed
the nine focal groups in 2.4 min. One variant over the nine groups is therefore about 8 %
of the base model, and its classify-plus-connect (3.8 min) about 9 % of the base's model
time for those nine groups (42.4 min): the base's cost is in what a variant does not re-run
(prepare, breaks, barriers, persisting every species).

**Parallel bound** (`analyze.R`, longest-first greedy, from the serial numbers only): four
jobs over groups would take one variant's pass from 5.6 min to 1.6 (longest group PARS 1.0),
and the `default` pass from 6.8 to 1.8. On #331's ladder (12 rungs, 13 passes with the
`default` one) that is about 12 × 4.0 + 5.0 = 53 min saved of about 82 serial
(12 × (5.6 + 0.6 join) + 6.8 + 0.8).

**Against the 2026-10-15 log (m1, link 0.65.1 / fresh 0.39.0, `habitat_score_331`),** the
same variant on the same nine groups took 9.8 min (0.5 REVL to 2.4 PARS) against 5.6 here,
and the `default` pass 12.0 against 6.8, while the base model took 42.7 min there against
67.1 here. The caveat the run decision names applies: #326 and #396 cut `default`'s segment
count two- to three-fold since, which is the axis the variant steps scale on, fresh moved
from 0.39.0 to 0.44.0, and m4 is not m1. The comparison says only that the variant pass has
not grown.

**Verdict.** Steps 3 and 7 are a rounding error (1.4 s over nine groups) and are ruled out
as a target. No step inside a variant's pass dominates: classify, connect and persist each
hold about a third. The per-variant cost is small beside the base (one pass is 8 % of the
base model), but a ladder repeats it, so the one change this names for #377's
iteration-speed list is running a variant's groups in parallel in
`habitat_variants_build.R` (the loop over `wsgs_v` in `run_variant()`), expected to save
about 4 min per variant over nine groups and about 53 min on #331's 12-rung ladder. Making
anything faster is outside this issue.

## Evidence

`data-raw/logs/variant_cost_404/` — this directory. The build logs (`build_base.log`,
`build_preflight_revl.log`, `build_variants.log`), the boundaries (`launch_state.txt`,
`stamp_build.txt`), the rows (`variant_timing.csv`) and the analysis
(`analyze.R` → `steps.csv`, `split.csv`, `steps_vs_segments.png`). Planning archive:
`planning/archive/2026-10-issue-404-*/`.
