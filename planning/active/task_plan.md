# Task: Parallelise the post-consolidate recompute (#250)

The post-consolidate recompute in `data-raw/study_area_run.sh:976-982` is a serial
loop over every WSG in the run, on a 10-core / 64 GB host. Per WSG it is already
cheap — #205 delivered that in v0.36.0. The cost is entirely in doing them one at
a time: **48 min of a 124 min run**, single-threaded, while nine cores idle, with
the cyphers already burned so it is pure dispatcher time.

Two findings from exploration reshape the work (both recorded in `findings.md`):

1. **The issue's safety argument has a hole.** `lnk_access()` unconditionally
   rebuilds ~38 **schema-scoped** barrier views per call. At N-wide that is a
   non-existence window *and* a lock convoy. The hoist is load-bearing; removing
   the redundant `DROP VIEW` is defence in depth.
2. **Recompute failures already cannot fail the run.** `|| echo` is inside the
   loop, `RUN_INCOMPLETE` is assigned before it, and `✓ recompute done` is
   unconditional. Today a run in which all 50 recomputes failed exits 0 and writes
   a compare CSV. The issue's "must still exit non-zero" is a fix, not a property
   to preserve.

## Phase 1 — remove the redundant `DROP VIEW` (v0.47.3, ships alone)

- [x] `R/lnk_barriers_views.R`: add `recreate = FALSE`; default emits
      `CREATE OR REPLACE VIEW` only (19 statements, not 38)
- [x] `.lnk_views_execute()` internal: on a genuine shape-change error, **stop with
      instructions naming `recreate = TRUE`** — never silently fall back to
      DROP+CREATE, which reintroduces the window mid-fan-out
- [x] `tests/testthat/test-lnk_barriers_views.R`: `38L` → `19L`; new `recreate = TRUE`
      case asserting `38L` and the DROP; mocked shape-change error asserting guidance
- [x] Version 0.47.3 + NEWS

## Phase 2 — hoist the view build (v0.48.0)

- [x] `R/lnk_access.R`: add `build_views = TRUE`; when `FALSE`, **verify the views
      exist** and `stop()` naming `lnk_barriers_views()` rather than trusting
- [x] `data-raw/barriers_views_build.R`: thin entry point on the `host_vintage.R`
      model, builds the family once for `cfg$species`
- [x] `data-raw/wsg_recompute_one.R`: read `LNK_VIEWS_PREBUILT=1`, pass
      `build_views = FALSE`; absent env var → unchanged behaviour
- [x] `tests/testthat/test-lnk_access.R`: guard fires on absent views; confirm
      `.lnk_table_exists()` is true for a **view**, not just a table
- [x] Exercise serially on a real WSG set before Phase 4

## Phase 3 — `lnk_fanout_judge()` (pure addition, no caller)

- [x] `R/lnk_fanout_judge.R`: five statuses — `none_expected`, `none_ran`,
      `all_failed`, `ok`, `partial`. Takes expected job **names**, not a count.
      `expected` has **no default** (per `lnk_preflight_parity(n_expected)`)
- [x] Malformed rc (`NA`, `""`, non-numeric) is a **failure**, not a neutral
- [x] `data-raw/fanout_judge.R` shell entry point; handles the zero-byte TSV itself
- [x] `tests/testthat/test-lnk_fanout_judge.R` — all five statuses, malformed rc,
      duplicate and unexpected job ids, `expected` omitted
- [x] Restore-the-bug check on each branch

## Phase 4 — the shell fan-out

- [x] `--recompute-jobs=N` (default 4) on the `--vintage-max-days=` template, with
      an upper bound, echoed in the banner
- [x] Hand-rolled bounded pool: `kill -0` liveness + `wait <pid>` (bash 3.2 —
      `wait -n` unavailable). Per-job `.rc` file is the source of truth, not the harness
- [x] Per-job logs in `$LOG_DIR/${TS}_recompute.d/`, concatenated via
      `find ... -exec cat {} +`, subdir removed on success and kept on failure
- [x] `.gitignore` for the `.d/` + one-level descent in `redact_log_addresses()`
- [x] Hoisted view build before fan-out; **no fallback** to per-WSG builds on failure

## Phase 5 — wire failure into the exit code

- [x] `RECOMPUTE_FAIL` initialised with the other flags, ORed with `RUN_INCOMPLETE`
      at the final gate; `:958` assignment does not move
- [x] Separate message per cause — an incomplete recompute is *silently wrong*
      output, not missing output, and needs the re-run command

## Phase 6 — prove byte-identical output

- [ ] `data-raw/recompute_checksum.sql`: per WSG, columns `ORDER BY column_name`,
      rows `ORDER BY watershed_group_code, id_segment` (#203), session settings pinned
- [ ] `data-raw/recompute_parity.sh`: three passes — A serial, B serial again
      (idempotence), C parallel with **shuffled** order (order/width invariance)
- [ ] `H_A == H_B == H_C`

## Phase 7 — measure and release

- [ ] `-j ∈ {1,2,4,6,8}` on a fixed subset; peak backends from `pg_stat_activity`
- [ ] Wall clock before/after, recorded in the PR
- [ ] v0.48.0 + NEWS naming the exit-code fix explicitly, not as a side effect

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
