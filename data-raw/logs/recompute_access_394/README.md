# recompute_access_394: what the recompute's access step costs at each change

Evidence for link#394, folding in #409 (both tracked on #377). Measured 2026-10-29 03:15 to
05:59 UTC on m1's `fresh_default`, which held the 2026-10-23 provincial `default` build
(PostgreSQL 17.5, R 4.5.2). The verdict is in
[`research/recompute_cost.md`](../../../research/recompute_cost.md).

#409 itself shipped separately, as v0.69.6 (PR #412, fresh v0.46.0, its record in
[`prefilter_409/`](../prefilter_409/), measuring each group's whole recompute). This branch
merged it and pins fresh v0.47.0, which carries the same prefilter, so the `prefilter`
variant here stands for #409's change on the access step. The scratch library held fresh
alone (installed with `R CMD INSTALL -l` from a checkout of the tag), so the 0.47.0
variants differ from `base044` only in fresh.

## The question

#261 found the recompute is mostly its `fresh::frs_network_features()` walks. Two fixes
were proposed, plus a third lever:

- **The prefilter** (fresh#272, fresh v0.45.0): cut the feature side to what
  `fwa_downstream()` can return. It needs no link change beyond the pin (#409).
- **Existence walks** (fresh#281, fresh v0.47.0): `result = "exists"` returns the segments
  that have a feature downstream, without building the arrays. It suits every walk link
  reads only as `id %in% result$id`: the per-species views and `pscis`.
- **One walk per distinct barrier set**: each species has its own view, so the per-table
  cache never hit, and CHWK walked five CH-shaped views that returned the same segments.

What does each buy, and do outputs move?

## Method

- `measure.R <variant> <WSG...>` runs the recompute's access step the way
  `lnk_access(merge = FALSE)` does: the same species, presence, views and scoped segments
  table. It calls `lnk_pipeline_access()` directly, under its own table names
  (`zz394_streams_<aoi>`, `zz394_<aoi>_out`), and drops them on exit. Each walk is timed
  through a mocked `frs_network_features()` that calls the real one. For each run it
  appends a row to `measure.tsv` (wall seconds, walk seconds, an md5 of every output
  column ordered by `id_segment`, the 1-minute load, the other active client backends,
  and the write counters of `barriers`, `barrier_overrides` and `streams` at start and
  end) and one row per walk to `walks.tsv` (table, result mode, seconds, rows, an md5 of
  the returned segment ids).
- Variants are code plus the installed fresh, each loaded from a `git worktree`:

  | variant | link | fresh |
  |---|---|---|
  | `base044` | main `64f8de0a` | 0.44.0 (`22034c1a`, the shared library) |
  | `prefilter` | main `64f8de0a` | 0.47.0 (`2c35e3eb`, a scratch library; `fresh_sha` is blank because it was installed from a checkout of the tag) |
  | `exists` | `caba1876` (existence walks) | 0.47.0 |
  | `dedup` | `4ea2d05b` (plus one walk per distinct set) | 0.47.0 |

- Groups: SALR (small), CHWK and LFRA (main-stem probes), SETN (output-bound). Round 1 ran
  `base044`, `prefilter`, `exists`, `exists`, `prefilter`, `base044` per group, so load
  drift falls on every variant alike. Round 2 ran `exists`, `dedup`, `dedup`, `exists`.
- `analyze.R` writes `steps.tsv` (per group and variant: runs, mean walk and access
  seconds, whether every digest equals `base044`'s) and `ceiling.tsv` (lever 2's ceiling,
  below). It stops if any digest differs.
- `model_digest.R <variant> <WSG...>` models groups into a scratch persist schema
  (`zz394_<variant>`, its own working schemas, `log = FALSE`, mapping codes on) and digests
  every persisted table per group (`model_digest.tsv`). It also counts the paths the
  access step feeds (`model_codes.tsv`, plus `dam_dnstr_ind` and `remediated_dnstr_ind`
  counts in the log). ADMS (SK, CH, CO) and ELKR (BT, WCT, Elko Dam) were built as `m044`
  (main, 0.44.0), `m047` (main, 0.47.0), `b047` (existence walks) and `d047` (dedup).

## Measurement

Access step in seconds, the mean of two runs (four at `exists`, which both rounds ran) (`steps.tsv`):

| group | `base044` | `prefilter` | `exists` | `dedup` | walks (`dedup`) |
|---|---|---|---|---|---|
| SALR | 26.9 | 3.9 | 4.0 | 4.0 | 5 |
| CHWK | 535.0 | 21.5 | 19.6 | 9.3 | 7 of 11 |
| LFRA | 1,145.7 | 89.5 | 74.5 | 35.3 | 7 of 11 |
| SETN | 763.6 | 347.3 | 292.0 | 136.5 | 7 of 11 |

- **Every run's output digest equals `base044`'s** in all four groups, and no run saw
  its inputs written (`inputs_start` = `inputs_end` on every row).
- **The prefilter is most of it** in groups whose cost was the probe: CHWK 25×, LFRA 13×,
  SALR 7×. SETN gains 2.2×, because its cost is the output.
- **Existence walks** take SETN's species walks from 327 to 270 s (CH-shaped walks
  50 → 40 s each) and LFRA's from 83 to 68 s. They leave SALR unchanged.
- **Lever 2's ceiling** (`ceiling.tsv`): at `exists`, walks whose returned segments repeat
  an earlier walk in the same run are 58 % of walk seconds in CHWK and SETN, 57 % in
  LFRA and 0 in SALR (4 of 8 species walks repeat in each of the three). Over the four
  groups that is 57.1 %, against the 10 % gate set at plan approval, so it was built.
- **One walk per distinct set:** species views with equal keys share one walk, so CHWK, LFRA and SETN run 7 walks instead of 11, and their access steps take 9.3, 35.3 and 136.5 s, against 19.6, 74.5 and 292.0 at `exists` (2.1× each). The key query costs 0.7, 2.2 and 9.2 s there (access minus walk seconds, `dedup` against `exists`). SALR's two species views differ, so nothing is shared and the key's 0.16 s is the whole effect: 4.02 s against 3.96. That is inside the 3.84 to 4.15 s spread of SALR's four `exists` runs. Every `dedup` digest equals `base044`'s.
- **Scratch models are identical:** all 20 per-table, per-group digests (11 tables
  holding ADMS rows, 9 holding ELKR's) agree across `m044`, `m047`, `b047` and `d047` (80 rows, one digest per table and group). So the 0.44 → 0.47 bump
  moves no persisted row, and neither does either lever, on the model-time path. That
  path also exercises `remediations` (with crossings) and the observation walk, which the
  recompute does not. The groups exercise the paths that matter: `dam_dnstr_ind` true on
  117 (ADMS) and 9,164 (ELKR) segments, `remediated_dnstr_ind` on 92 and 2, and access code
  2 on 3,530 and 8,396 segment-species.
- **The prefilter costs small source walks a fixed overhead.** In SETN the `pscis` walk
  (3,016 rows) went from 0.2 to 3.3 s and `dams` from 1.2 to 4.2 s, because fresh builds
  its group-scoped temp table and admissible set for every walk whatever the feature
  table's size. That is 7.8 s against the 481 s the species walks gave back (all four `exists` runs). It does not
  change the verdict.
- Load: the 1-minute load average was 2.9 to 6.6 at run starts. Another client was
  connected throughout (below), and the other active client backends seen at any walk's
  end were 0 or 1.

## Wrong turns

- **The first measure.R collided with a live recompute.** Another client, reaching m1's
  database through an ssh tunnel, was recomputing SETN on `fresh_default`. measure.R first
  went through `lnk_access()`, which drops and recreates `<schema>.zz_lnk_streams_<aoi>`,
  the same name that recompute uses. The plan review caught it before the round reached
  SETN. The round was stopped, and the orphan backend it left walking
  `zz_lnk_streams_chwk` finished on its own (terminating it was refused). measure.R now
  takes its own names, sets `lock_timeout`, and drops its tables on exit. The SALR rows taken
  through `lnk_access()` before the change are kept as `measure_round0.tsv` and
  `walks_round0.tsv`. They also have identical digests across variants. A side finding:
  `lnk_access()`'s scoped table duplicates the per-walk temp table fresh builds since
  0.45.0.
- **The fingerprint's first test could not see a NULL.** The review asked for a key over
  record text, because `concat_ws()` skips a NULL (153 `fresh_default.barriers` rows have
  no `localcode_ltree`) and `||` drops the row. The first live test's fixtures held no NULL
  `localcode_ltree`, so mutating the key to `concat_ws()` passed. A fixture row with a NULL
  in that column was added, and now the mutation fails the test.
- **The shared library holds one fresh.** `load_all()` of the branch refuses fresh 0.44.0
  against its 0.47.0 floor, and the baseline needs 0.44.0. So 0.47.0 went into a scratch
  library (`R_LIBS`), which let the variants interleave. The shared library is upgraded
  after the last `base044`/`m044` run.

## Files

| file | what |
|---|---|
| `measure.R` | one access step per group per variant, timed walk by walk |
| `model_digest.R` | scratch models and per-table digests |
| `analyze.R` | `steps.tsv`, `ceiling.tsv`, the lever-2 gate |
| `measure.tsv`, `walks.tsv` | rounds 1 and 2 |
| `measure_round0.tsv`, `walks_round0.tsv` | SALR through `lnk_access()`, before the collision fix |
| `steps.tsv`, `ceiling.tsv` | written by `analyze.R` |
| `model_digest.tsv`, `model_codes.tsv` | scratch models (`m044`, `m047`, `b047`, `d047`) |
