# Code review, round 5 (enumeration): staged diff for #284 step 5

Mechanism under test: **a partial producer read by a whole-population reader.**
Probes ran in `scratchpad/r5/` and read-only against docker fwapg (`score284_*`,
`working_score_bull`). No repo file other than this one was touched.

## Round-4 fixes, re-checked for a defect inside each

| fix | verdict | evidence |
|---|---|---|
| 1. ladder validation, bounded `chain_to` | **HOLDS** | The real 4-row `variants.csv` passes all three checks (probed: every `step_from` listed, `anyDuplicated(below) == 0`, walk terminates). A NA `step_from` on a non-base row stops ("names no listed variant: NA"). A self-loop and a two-cycle both stop. |
| 2. bundles written in `run_variant()`, `built.csv` sha, score cross-check | **HOLDS per variant, FAILS per WSG** | See Finding 2. `record_built()` on first write: `NULL[logical(0), , drop = FALSE]` is `NULL`, and `rbind(NULL, row)` is `row` (probed). |
| 3. score dirty pathspec widened to `inst/extdata` | **HOLDS** | score.R:116-119. The build reads nothing in link's `inst/extdata` outside `configs/` (`wsg_regions.csv` is pooling, which is score-only), so its narrower pathspec is right. |
| 4. `habitat_validate.R` pathspec and HEAD at launch | **Pathspec HOLDS, timing FAILS (low)** | HEAD is taken at launch (:99), but `link_dirty` is still computed at the end (:286). See Finding 4. |
| 5. branching ladders rejected | **HOLDS** | Same as 1. |
| 6. score re-checks access digest per variant × WSG; base re-classify in every variants pass | **HOLDS** | The licence runs over the same `focal` as every variant's `wsgs_v` in that pass, so each WSG a variant builds is licensed in the same pass. With the base working schema dropped, `--step=variants` stops at build.R:426-428 ("run --step=base first"). `run_base()`'s `done` check then re-runs that WSG, because it requires the working schema for focal WSGs (:310-311). The loop does not deadlock. |

## Enumeration

For every artifact the build writes: its writers, and each reader in the build and score.

| # | artifact | writer (scope written) | reader | can the reader take a subset for the whole? |
|---|---|---|---|---|
| 1 | `<prefix>default` schema (streams, habitat, barriers, access, log) | `run_base()`, per closure WSG. Access is re-settled for the invocation's `focal` only. | build `run_base()` resume `done` (:306-311) | **FAILS** (Finding 1). `done` reads the DB, which pre-flight and earlier invocations have filled. The licence data it needs lives in the `--out` directory. `done` cannot tell a WSG built by *this* build from one built by another invocation, dirty tree included. |
| 1 | 〃 | 〃 | build `run_variant()` streams / access digests (:454-459) | **HOLDS**: compared per WSG. |
| 1 | 〃 | 〃 | build `copy_access()` | **HOLDS**: per WSG, same column set asserted. |
| 1 | 〃 | 〃 | build `write_stamp()` `run_uid` from `.log` | **FAILS (low)**, part of Finding 1. It reads the log for focal WSGs, but never the log's `link_sha` / `link_dirty`. A resumed dirty-built WSG sits under a stamp line reading clean HEAD. |
| 1 | 〃 | 〃 | score: `digest_access`, `lnk_habitat_validate`, band ref/core, `abs_obs`, bridge `sr` | **HOLDS** for presence and segmentation. A WSG missing from every schema stops in `.lnk_hv_check_schema()` ("not persisted in …streams"). Access `NA`-vs-`NA` equality cannot mask that. |
| 2 | `working_score_<wsg>` | `run_base()` for focal WSGs; overwritten by each `run_variant()` classify/connect | build `done` check (existence of `streams`) | **HOLDS**: `done` also needs base access rows, which persist last in `lnk_pipeline_run()`. |
| 2 | 〃 | 〃 | build `run_variant()` classify / `working_habitat_digest` / persist source | **HOLDS**. The working table ends a pass at the last variant's BT value. The base re-classify always runs first in the next pass and restores every species, and the licence digest proves it. |
| 3 | `<prefix><variant>` schemas | `run_variant()`, for `wsgs_v` of that invocation | build digest checks (written then checked) | **HOLDS**. |
| 3 | 〃 | 〃 | score access-digest loop (:184-194), validator, band fn, bridge | **HOLDS for presence and segmentation; FAILS for threshold provenance per WSG** (Finding 2). Read-only probe of the BULL pre-flight: spawning is identical base vs `bt_rear_0p1249` on 44,830 segments, and 0 rearing segments are removed, so the one-species re-classify path adds nothing beyond the step. |
| 4 | `bundles/<v>/` | `run_variant()`, before its WSG loop | build `cfgs` | **HOLDS**. |
| 4 | 〃 | 〃 | score `cfg_of`; sha vs `built.csv`; `n_diff` vs current default; value check | **HOLDS per variant.** If a crash lands between the bundle write and `record_built()`, the sha check catches a changed value. An unchanged value leaves the schema consistent. Per WSG: Finding 2. |
| 5 | `built.csv` | `record_built()`: one row per variant, **replaced by the latest invocation**, which may cover a `--wsgs` subset | score (:140-172) | **FAILS** (Finding 2). The score reads only `variant` and `thresholds_sha256`. It never reads `wsgs`, `schema`, `link_head` or `dirty`. |
| 6 | `base_habitat_digest.csv` | `run_base()`, per focal WSG **that this `--out`'s base runs built** | build `run_variant(default)` licence (:436-444) | **FAILS** across `--out` directories (Finding 1). HOLDS within one directory. |
| 7 | `base_recompute.csv` | `run_base()`, per-WSG merge | none in code | **HOLDS**: a labelled report, merged per WSG. First-write `NULL` path probed OK. |
| 8 | `closure.txt` | `run_base()`, overwritten with *this invocation's* closure | none in code | **HOLDS for code.** Note: a `--wsgs` subset base pass overwrites the full closure. Phase 4's "23 WSGs in `score284_default`" must be checked from the DB, not from this file. |
| 9 | `stamp_build.txt` | appended per **successful** invocation | none in code | **FAILS (low)**, Finding 3. Nothing joins a score to the build it verified. |
| 10 | score outputs (`summary.csv` … `stamp_score.txt`) | score; unlinked at score start | build | **FAILS (low)**, Finding 3. The build never clears them, so a later build into the same `--out` leaves them beside a `built.csv` they never read. |

## Findings

### [bug] Finding 1: the planned full build will stop at the licence for BULL, and would otherwise stamp a dirty-built base as clean

**Location:** data-raw/habitat_variants_build.R:305-315, 416, 436-444, 473-476, 484-486. **Inside round-4 fix 6**: the licence now runs in every pass, so this path is reached on every variants pass.

**Mechanism.** One build is keyed by two independent stores.
- The DB schemas are keyed by `--prefix`.
- The licence digests, bundles and `built.csv` are keyed by `--out`.
- `run_base()`'s resume test reads only the DB, while the licence reads only the `--out` file.

**The live case: the pre-flight left its state in both stores.**
- **DB:** `score284_default` holds BULL, KOTL and LARL, and `working_score_bull` survives. Checked: `to_regclass('working_score_bull.streams')` is `t`, and BULL and LARL access rows are `t`.
- **Files:** the licence digest went to `scratchpad/preflight/base_habitat_digest.csv`.
- **Default `--out`:** `data-raw/logs/habitat_score_284/` holds only `power_windows.*`.

**What happens on launch.** The task plan's full build (`--prefix=score284_`, default `--out`, 12 focal WSGs) runs as follows:
1. `run_base()` marks BULL `done` and skips it. LARL is skipped the same way.
2. KOTL is re-run, because it is focal now and its working schema was cleaned up.
3. `run_variant(default)` licenses ELKR.
4. At BULL, `want` is `character(0)`. The probe gave `length(want) == 0` and `identical(dg, want)` FALSE.
5. It stops with "gave habitat digest …, not the base run's : the re-classify path is not a pure threshold change". That is a misdiagnosis: the digest was never recorded here.
6. A relaunch stops identically, because BULL stays `done`. The ~75 min base has completed by then.

**Provenance, even if the stop is avoided.**
- LARL and BULL keep bases built at `823fde7` with `link_dirty = t` (`score284_default.log`: all three rows are `t`). The pre-flight ran `--allow-dirty`.
- The build's clean-tree gate (:84-91) is bypassed by resume.
- `stamp_build.txt` would read `link @ <HEAD>` with no "dirty". Its `run_uid` line reads the log but not `link_sha` / `link_dirty`.
- LARL is non-focal but lies downstream of KOTL and BULL, so its barriers feed their access.

**Fix.** Before launch:
- Drop the pre-flight state (`score284_*` and `working_score_bull`). That is a separate asked step per task_plan.md:130, so ask now.
- Or re-point the full build's `--out` at the pre-flight directory. That does not fix the dirty LARL/BULL bases.

In code:
- **(a)** Make `done` for a focal WSG also require its row in `path_base_digest`. A missing row re-runs the base WSG, which is safe because every variant is rebuilt in the pass after it.
- **(b)** Refuse to resume a WSG whose latest `<schema>.log` row has `link_dirty` or a `link_sha` other than HEAD while the run is clean. At minimum, print those per WSG in the stamp.
- **(c)** When `want` has length 0, say "no base digest for w in <out>".

### [fragile] Finding 2: `built.csv` is one row per variant, written by a `--wsgs` subset and read as covering the score's whole aoi

**Location:** data-raw/habitat_variants_build.R:250-269, 463; data-raw/habitat_variants_score.R:148-159. **Inside round-4 fix 2.** Round 5's question 1, answered yes.

**What the record holds.**
- `record_built(v)` replaces the variant's row with this invocation's `wsgs`, `link_head`, `dirty` and sha. The rows for the WSGs it did not rebuild are dropped.
- The score keys on `variant` alone and reads only `thresholds_sha256`. `wsgs` and `schema` are written and never read.
- Probe: the pre-flight `built.csv` (`wsgs = BULL` on all three rows) passes the score's built check unchanged for the 12-WSG aoi.

**What the score's checks cannot see.**
- None of the three checks sees a WSG built from a different bundle than the one `built.csv` now names:
  - the sha vs the bundle on disk;
  - the bundle = current default + one cell;
  - the access digest, since access does not depend on thresholds.
- **Example.** Build 12 WSGs, then correct a `variants.csv` value (or `default`'s BT row, plus a base re-run of one WSG) and rebuild `--wsgs=ELKR`. The score passes and labels 11 WSGs with a value they were not built from.
- **No incidental guard.** The segmentation and access checks catch schema-shape drift, not threshold drift.
- **Same on the base row.** `default`'s row names only the licence invocation's `focal`.

**Fix.**
- Write one row per variant × WSG, keyed `(variant, watershed_group_code)`. Replace only the rows rebuilt.
- In the score, stop unless every `(v, w in aoi_of(species_of(v)))` has a row and all of a variant's rows share one sha.
- Also check `b$schema == schema_of(v)`. `--prefix` and `--out` are independent, so a score can validate bundle X and score schema Y.

### [fragile] Finding 3: the score's stamp does not name the build it verified

**Location:** data-raw/habitat_variants_score.R:501-527; habitat_variants_build.R:467-501. **Inside round-4 fix 2**: round 4 recommended printing the shas in `stamp_score.txt`, and this was not done.

**What `stamp_score.txt` omits.**
- It carries the score's own HEAD and `--variants` md5.
- It carries no bundle sha and no build `link_head` / `dirty` / `built_at`.

**Consequences.**
- The pre-flight's stamp reads `823fde7 (dirty)` for the score, but nothing in it says the schemas were also built dirty.
- The build never unlinks the score outputs. A rebuild into the same `--out` therefore leaves `verdict.csv` / `summary.csv` beside a newer `built.csv` and `stamp_build.txt` block, with no join key between them.

**Fix.** Copy the `built.csv` rows the score checked into `stamp_score.txt`: variant, schema, sha (12), `link_head`, `dirty`, `wsgs`, `built_at`.

### [low] Finding 4: `habitat_validate.R` takes HEAD at launch and `dirty` at the end

**Location:** data-raw/habitat_validate.R:99 vs 286-289. **Inside round-4 fix 4.**

**What is wrong.** The stamp pairs launch HEAD with end-of-run dirtiness. A tree dirty at launch and committed mid-run stamps `<old HEAD>` clean. The score script and the build both take the two together at launch.

**Fix.** Move the `link_dirty` block up beside `head_sha` at :99.

## Note

`digest_sql$streams_access` (build.R:276) and `digest_access` (score.R:177) hash `t::text`. That depends on column **order**, while `copy_access()` asserts only `setequal`. A future order difference fails loud, as a false "differs from" at build or score. It cannot fail silently, and the pre-flight shows the orders match today.
