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
| `build_base.log`, `build_variants.log` | the builds (`--step=base`, then `--step=variants --only=bt_rear_wet_p10`) |
| `closure.txt`, `base_habitat_digest.csv`, `base_recompute.csv`, `built.csv`, `stamp_build.txt`, `bundles/` | what the build script writes for any scoring build |
| `variant_timing.csv` | seconds per step per variant × group, with segment count and load (the build writes it; #404's instrumentation) |
| `analyze.R` → `steps.csv`, `split.csv`, `steps_vs_segments.png` | minutes per step and share of the pass; the model / verification / write split; minutes against segment count per step |

## What happened during the builds

(filled at launch)

## Measurement

(filled after the run)

## Evidence

`data-raw/logs/variant_cost_404/` — this directory.
