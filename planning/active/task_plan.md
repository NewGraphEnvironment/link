# Task: Tuning iterations: measure where a threshold variant's time goes (seven steps, two of them verification) (#404)

**If we do it:** we know which step makes a tuning loop slow before trying to speed it up, and the right change goes on #377's iteration-speed list. **If we never do:** speed work keeps landing on the access walk (NewGraphEnvironment/fresh#272, #394), which a tuning loop runs once per closure, while the cost paid on every variant goes unmeasured.

## What exploration found (shapes the phases)

- **m4 cannot run the script today:** installed fresh is **0.43.0** (`RemoteSha 18d92ceb`),
  `DESCRIPTION` pins `fresh (>= 0.44.0)` / `Remotes: NewGraphEnvironment/fresh@v0.44.0`, and
  `load_all()` refuses an installed dependency below the floor. The fresh checkout holds the
  `v0.44.0` tag. Installing is Phase 1 and the issue's own Environment requirement.
- **No `score*` or `working_score*` schema exists on m4** (queried `pg_namespace`), so the
  base is rebuilt, as the issue's Groups section says. Its Measure section ("do not rebuild
  the base, reuse an existing closure") does not apply on this host; the record says so.
- **m4 holds what #331's set needs:** `discharge.fwa_v1_segment_monthly` (wet annual pick,
  built 2026-10-15, wet `acb820f`), `bcfishobs`, `cabd`, `fresh_default`. The #331 variants
  are all `mad` on `wet` or `fwapg`; `.lnk_discharge_join()` runs **before** `t0`
  (`:784`), so it is outside the issue's seven and outside the existing total.
- **The base variant (`default`) always runs first in a variants pass** and re-classifies
  every species, running only steps 1, 2, 3 and 7 (`:809-818`, `:847-852`), so one
  `--only=<variant>` run measures two shapes for free: all-species classify+connect+verify,
  and one-species full pass.
- **`run_base()` already has a per-group `t0` around `lnk_pipeline_run()`** (`:655-673`) and
  a per-group recompute loop (`:684-721`): the "base pass's minutes beside them" the issue
  asks for are two more rows in the same file.
- **`path_base_digest` and `built.csv` live in `--out`** (`:545`, `:617`), so a fresh
  `--out=data-raw/logs/variant_cost_404` is the base's out too: `--step=base` writes
  `closure.txt`, `base_habitat_digest.csv`, `base_recompute.csv` there, and the variants
  pass reads them from there. The score script (`habitat_variants_score.R`) reads only
  named files from `--out`, so one more CSV there breaks nothing.
- **Nothing in fresh times `frs_habitat_classify()` or `frs_cluster()`** (no `Sys.time` in
  either), and nothing in `R/` is a reusable step timer: `lnk_stamp` times a whole run.
  Statement depth, if needed, needs no code: `PGOPTIONS='-c log_min_duration_statement=0'`
  reaches RPostgres through libpq (the #371 mechanism) and `docker logs fresh-db` holds the
  durations.
- **m4 is loaded by something else right now** (load average 4.4 / 5.1 / 5.3 at 11:40 PDT, no
  R process of ours). The #396 campaign met the same and recorded the 1-minute load at each
  step; the timing rows carry it too.
- **The #331 numbers are a comparison with a caveat**, not a target: #326 and #396 changed
  segmentation since, and m4 is not m1.

## Decided at the gate

1. **Groups: #331's set** (`variants_331.csv`, `wsg_roles_331.csv`; focal REVL, ELKR, KOTR,
   UARL, MURR, UBTN, LHAF, PARS, KOTL; 17-group closure), base `default`, so the totals sit
   beside the 2026-10-15 log. Alternative, not taken: #364's five CH/CO groups.
2. **Variant: `bt_rear_wet_p10`** (the first `wet` rung; `mad`, one species). The `default`
   pass that precedes it gives the all-species shape.
3. **Install fresh v0.44.0 on m4** (`pak::pak("NewGraphEnvironment/fresh@v0.44.0")`), the
   pin `DESCRIPTION` names. A machine change, so it is the operator's call here.
4. **Timing is always on**, no flag: `Sys.time()` costs nothing, and every later tuning build
   (and fresh#275) gets the split for free.
5. **Parallel-over-groups is estimated from the serial numbers only** (sum / 4 against the
   longest group), never run: running it is speed work, out of scope.
6. **Statement depth only if one step holds more than half the pass** (median over the nine
   groups), on one group, through `PGOPTIONS` + container log, no code.
7. **Schemas `score404_*` and `working_score404_*` stay** after the run, as every `score*`
   schema has (2026-10-16 status).
8. **Run from a git worktree at the branch**, with an absolute `--out` into this checkout,
   so docs can be committed here while it runs (`load_all()` and `lnk_stamp` read the tree).

## Phase 1: environment (before any build)
- [x] Install fresh v0.44.0 on m4; confirm `packageDescription("fresh")$RemoteSha` equals
      `git -C ~/Projects/repo/fresh rev-parse v0.44.0^{commit}` and `pkgload::load_all()` loads
      (installed 2026-10-28 19:03 UTC, `RemoteSha 22034c1a` = the tag commit)
- [x] `lnk_preflight_vintage()` passes (7-day default) on docker fwapg; record the oldest stamp
      (OK at 19:05 UTC, oldest 3.6 d, `whse_fish.pscis_assessment_svw`)
- [x] Write `data-raw/logs/variant_cost_404/README.md` "Run decision" (host, fresh, link SHA,
      closure, variant, load at launch, why the base is rebuilt), before the build, as
      `observation_breaks_396/README.md` does

## Phase 2: split the timer in `habitat_variants_build.R`
- [x] `run_variant()`: a `Sys.time()` around each of the seven steps, named `classify`,
      `connect`, `digest_working`, `persist`, `copy_access_analyze`, `gate`, `digest_persist`;
      the `discharge_join` before `t0` timed too, as a row outside the total; keep the
      existing `say("variant %s %s done in %.1f min ...")` line as the total. The total is
      taken right after step 7, before `record_built()` and the timing row's own queries
      (plan review), so the seven sum to it with only R overhead as residual
- [x] `lnk_persist_init()`, once per variant outside `t0`, gets a `persist_init` row with no
      group (plan review)
- [x] `run_base()`: rows `base_model` (around `lnk_pipeline_run()`) and `base_recompute`
      (per focal group) in the same file, outside the total
- [x] Rows go to `<out>/variant_timing.csv`: `variant, watershed_group_code, species, step,
      seconds, in_total, n_segments, load_1min, built_at, link_head, fresh_version`;
      `n_segments` from `<base schema>.streams` for the group; `load_1min` from `uptime`
      (NA on failure), taken at the pass's start; a pass writes its rows once, and they
      replace earlier rows for the same (variant, group, step), not the pair (plan review:
      the pair key would drop the base rows)
- [x] One `say()` per group listing the step minutes, beside the total line
- [x] Header comment and `data-raw/habitat_score/README.md` name the file
- [x] `--step=bundles` runs at the branch. It stopped on main and the branch alike: the
      `write_thresholds()` self-check (`default`'s CSV byte for byte) failed because its quote
      list named `species_code` and `*_edge_types` and #364 added the text column
      `rear_river_measure` (`"model"`). Fixed by quoting every column holding a non-numeric
      value, which reproduces `default`, `bcfishpass` and `default_tuned` byte for byte.
      Byte-identity of the bundles across the instrumentation cannot be shown against main
      (main stops first); the real build's digest invariants are that check

## Phase 3: build and measure
- [x] Commit Phase 2 and push the branch before any build (`45b12b2e`, pushed): the dirty check covers the script,
      and the worktree checks the branch out (plan review)
- [ ] At launch (done: `launch_state.txt`, no other backend, load 2.4) and at the end, a `pg_stat_activity` snapshot (other backends and their
      `application_name`) into the README, beside the load average: the issue's "whether
      the run shared the database with anything else" (plan review)
- [ ] `--step=base --variants=data-raw/habitat_score/variants_331.csv
      --roles=data-raw/habitat_score/wsg_roles_331.csv --prefix=score404_
      --out=<abs>/data-raw/logs/variant_cost_404`, detached (`nohup … & disown`), from the
      worktree; ~45 min base + recompute on #331's m1 numbers
- [ ] Pre-flight: `--step=variants --only=bt_rear_wet_p10 --wsgs=REVL` (smallest focal);
      check the seven `in_total` seconds sum to the total line within 2 %
- [ ] Full: `--step=variants --only=bt_rear_wet_p10` over the nine groups (the `default` pass
      runs first); keep the build log in the campaign dir
- [ ] Stamp: `stamp_build.txt` (the script writes it), plus host class, `-j` (serial, 1),
      and the load average through the run in the README

## Phase 4: analysis
- [ ] `data-raw/logs/variant_cost_404/analyze.R` → `steps.csv` (minutes per step per group,
      share of the pass), `split.csv` (model / verification / write share per group and
      pooled), `steps_vs_segments.png` (minutes against `n_segments`, one line per step, so a
      step that scales with the group is told from a fixed cost); it asserts the residual
      between the summed steps and the total line
- [ ] The parallel bound from the serial numbers: sum of the nine groups' pass minutes / 4
      against the longest group
- [ ] Only if one step holds more than half the pass (gate decision 6): re-run that variant
      on one group under `PGOPTIONS='-c log_min_duration_statement=0'`, take the statement
      durations from `docker logs fresh-db` filtered to the session's `pg_backend_pid()`
      (the log holds every session's statements; plan review), record them as
      `statements_<step>.csv`

## Phase 5: record and verdict
- [ ] README: Measurement (numbers with units, the model / verification / write split, the
      #331 comparison with its caveat) and Evidence (the dir's prefix), file table
- [ ] Verdict, one of: steps 3 and 7 are a rounding error (say so, close on the issue's own
      terms), or a named next change, added to #377's "Iteration speed" list with its
      expected saving (`gh issue edit 377 --body-file`)
- [ ] fresh#275 gets the classify and cluster minutes per group as a comment (our repo), so
      its record describes the same calls; say that the rows wrap link's entry points
      (`frs_params()` + `frs_habitat_classify()`; `.frs_run_connectivity`, cluster plus the
      connected-waterbody pass, not `frs_cluster()` alone) (plan review)
- [ ] `CLAUDE.md` Status entry (facts not worth re-deriving), `NEWS.md` line; tick #404's
      acceptance boxes

## Validation

- [ ] Tests pass (`devtools::test()`; the script has no tests, the pre-flight is its check)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification of each change: Phase 2 by the REVL pre-flight (step seconds sum to the total,
`built.csv` and both digest invariants still pass, bundles byte-identical); Phase 3 by
`variant_timing.csv` holding 9 groups × (4 `default` + 7 variant + 2 `discharge_join`) rows,
2 `persist_init` rows, one `base_model` row per group modelled in this run (17 on a clean
base; a resumed group writes none, plan review) and 9 `base_recompute` rows; Phase 4 by `analyze.R`'s residual
assertion; Phase 5 by the acceptance boxes on #404.

