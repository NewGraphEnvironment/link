# Task: Backlog move 13: The next fresh pin (#481)

**If we do it:** the persisted near-river table keeps fresh's key, and both connection helpers read the same variables. **If we never do:** the validator errors on the first install of fresh 0.54.0.

**Open since 2026-11-22:** fresh 0.54.0 shipped on 2026-11-20 (0.55.1 is the latest release); the plan reads fresh's NEWS from 0.52.0 to the pinned tag.

Members, one phase each besides the pin and the proof: #452 (`cols_streams_near_river` gains `linear_feature_id` with fresh 0.54.0; the validator passes `near_river_lfid`), #288 (`lnk_db_conn()` reads `PG_*_SHARE` first, fresh reads `PG*` first), #222 (the live `lnk_wsg_resolve` tests route to another database than their skip gate). One PR. `/gh-pr-merge` ticks move 13 in `planning/backlog.md`.

## Decided at the gate

No plan gate in this pane: `/coordinator` dispatched this as a `park review` (soul#928), so the coordinator's plan gate, or the owner, decides `## Open decisions

None open.

## Decided by the owner, 2026-11-22

1. **#288: `lnk_db_conn()` delegates to `fresh::frs_db_conn()`** (option a): explicit args, then `PG*`, then `PG_*_SHARE` (deprecated), never mixed, with fresh 0.55.0's connect timeout and keepalives; link silences fresh's deprecation message for a fully explicit call; `data-raw/wsg_vignette_data.R` passes explicit `PG_*_SHARE` arguments.
2. **#452: add the column, backfill, pass TRUE** (option a): `lnk_persist_init()` adds `linear_feature_id` once where the catalog lacks it and backfills it from `<schema>.streams` on `(id_segment, watershed_group_code)` (`WHERE linear_feature_id IS NULL`); the validator passes `near_river_lfid = TRUE` after refusing a scored schema whose table lacks the column or holds a NULL in the scored groups. The province schemas' migration is an owed step after merge, at a quiet time.
3. **m1's database:** its colima VM lost its guest network at about 2026-11-21 20:46 PDT (ssh and 5432 refused, guest agent still syncing time); restart colima on m1 and build there.

## Phase 1: Baseline at fresh 0.52.0 (before any install)

- [x] Confirm the host is quiet (no other session modelling ADMS or BULK: `lnk_pipeline_run()` drops `working_<wsg>`).
- [x] From a worktree of `origin/main` (link 0.86.0, with `R_LIBS` on a scratch library holding fresh 0.52.0 alone: the shared library holds 0.53.0, installed 2026-11-16), model ADMS and BULK under `default` into scratch `fresh_pin481_before`, and ADMS under `bcfishpass` into `fresh_pin481_bcfp_before`; `LNK_GUARD_DOWNSTREAM=ignore` with its `_NOTE`, the same in both arms. ADMS holds `near_river` rows under CH's `wetland_flow` scope. Record each group's minutes.
- [x] Digest every persisted table per group by named columns: `streams`, `streams_habitat_<sp>`, `barriers`, `barrier_overrides`, `barrier_override_evidence`, `streams_access`, `streams_mapping_code`, `streams_near_river` (`consolidate_persist_core`, `data-raw/schema_consolidate.R:240`), to `data-raw/logs/fresh_pin_481/before/`, with `lnk_stamp()`.
- [x] Install fresh v0.55.1 alone into a scratch library (`R CMD INSTALL -l <lib>` from a worktree of the tag; not `pak`). Confirm `packageVersion("fresh", lib.loc = <lib>)` is 0.55.1 and the shared library still holds 0.52.0. It writes no `RemoteSha`, so the after-arm sets `FRESH_GIT_SHA` to the v0.55.1 commit for its stamps.

## Phase 2: The pin and the preflight

- [x] `DESCRIPTION`: `fresh (>= 0.55.1)`, `Remotes: NewGraphEnvironment/fresh@v0.55.1`.
- [x] `.lnk_fresh_required_formals()` (`R/lnk_preflight_fresh.R`): `frs_habitat_predicates` adds `near_river_lfid`, the comment naming fresh 0.54.0 (fresh#293). Under Open decision 1 (a): `frs_db_conn` joins `.lnk_fresh_required()` (the drift guard at `test-lnk_preflight_fresh.R:124-136` fails without it), and any argument passed through joins the formals.
- [x] `test-lnk_preflight_fresh.R` and `test-pretest.R`'s reach checks pass under `R_LIBS` (43 and 152 passed); fresh's reach at v0.55.1 is walked in Phase 4, once `lnk_db_conn()` calls fresh.

## Phase 3: `streams_near_river` mirrors fresh's table (#452)

- [x] `cols_streams_near_river` (`R/lnk_persist_init.R:218`) gains `linear_feature_id = "bigint"`, last; roxygen says it mirrors fresh 0.54.0's table.
- [x] `lnk_persist_init()` adds the column to an existing table where `.lnk_schema_columns()` (`R/lnk_log.R:520`) shows it missing, taking no lock when present (#369's no-lock test, `test-lnk_persist_init.R:235-275`, covers it); the backfill per Open decision 2.
- [x] `lnk_pipeline_persist()` projects the column from the vector (`R/lnk_pipeline_persist.R:276-283`); confirm no other edit.
- [x] `.lnk_hv_stage_exprs()` (`R/lnk_habitat_validate.R:1095`, `:1108`) passes `near_river_lfid` at both calls, and `.lnk_hv_check_schema()` (`:386-428`) carries the check Open decision 2 picks.
- [x] Tests: `test-lnk_persist_init.R` (an old-shape table gains the column, idempotently, with its backfill), `test-lnk_pipeline_persist.R`, `test-lnk_habitat_validate.R`, whose fixtures gain the column (`:384-395` `streams`, `:1067-1071` `streams_near_river`) and whose INSERT at `:1098` names its columns; restore each defect and see its test fail.
- [x] RUNBOOK §7 ("Persisted and logged", ~`:2065`): the column, the key, the migration. `data-raw/logs/minimal_breaks_415/proof.R:317` calls the predicate without the flag and is left as a record; say so in findings.

## Phase 4: One connection resolver (#288)

- [x] `lnk_db_conn()` (`R/lnk_db_conn.R`) per Open decision 1: signature (NULL defaults; `connect_timeout` and `...` passed through under (a)), roxygen `@details` and examples saying which variables it reads, in what order, the no-environment default, and the deprecation message.
- [x] `data-raw/wsg_vignette_data.R:201-210` passes explicit `PG_*_SHARE` values for the tunnel; comments at `data-raw/host_vintage.R:10` and `data-raw/study_area_buckets.R:235` read the new order.
- [x] `data-raw/pretest_inputs.csv:149`: under (a) or with any `fresh::frs_db_conn` call, `R/frs_db_conn.R` is reached from `wsg_run_one.R` through `lnk_db_conn()` (`PRETEST_ENTRIES`, `data-raw/pretest.R:44-46`), so its row becomes `any` with its reason.
- [x] `tests/testthat/test-lnk_db_conn.R` rewritten: `withr::local_envvar()` clearing `PGHOST`, `PGHOSTADDR`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSERVICE` and the five `PG_*_SHARE`; `DBI::dbConnect` mocked; assert explicit args win, no `PG_*_SHARE` value reaches the call when a `PG*` is set, `PG_*_SHARE` fills only with no `PG*`; reset `fresh:::.frs_state$share_msg_shown` before testing the message.
- [x] CLAUDE.md "Database Connection" and the lines describing the old order, RUNBOOK `:43`, and the `m1-link-db-env` memory read the new order.

## Phase 5: The live resolve tests use the gated connection (#222)

- [x] `tests/testthat/test-lnk_wsg_resolve.R:129-167`: the two closure tests pass `conn = skip_if_no_db()` and skip when that connection has no `whse_basemapping.fwa_downstream()` (the gate can fall back to `lnk_db_conn()`, `tests/testthat/setup.R:28-30`; corrected at the resume: `public.wsg_outlet` was retired by fresh 0.33.0 and dropped from m1 on 2026-08-28, so a gate on it would skip everywhere; closure mode reads only the routine); the province-mode test drops its skip (province mode returns before any connection).
- [x] Prove it: with the local fwapg up and `PG*` pointed at an unreachable host, the closure tests pass on the gated connection.

## Phase 6: Verify the pin moved nothing but the column

- [x] With `R_LIBS=<scratch lib>` and the branch, model the same groups into `fresh_pin481_after` and `fresh_pin481_bcfp_after`; digest as in Phase 1, `streams_near_river` over its old columns. `data-raw/logs/fresh_pin_481/compare.R` asserts every digest identical and stops on anything else. Minutes beside Phase 1's.
- [x] Every row of `fresh_pin481_after.streams_near_river` has a `linear_feature_id` equal to `streams.linear_feature_id` at its `(id_segment, watershed_group_code)`, and none is NULL.
- [x] Under Open decision 2 (a): the branch's `lnk_persist_init()` on a copy of `fresh_pin481_before` backfills the column equal to what fresh wrote in `fresh_pin481_after`.
- [x] `lnk_habitat_validate()` on `fresh_pin481_after` (ADMS, `default`) gives identical results with `near_river_lfid` TRUE and FALSE, with non-zero near-river hits.
- [x] The variants harness: a working schema left by a 0.52.0 build is refused by fresh 0.55.1 (`.frs_habitat_target` adds the column, `.frs_null_key_guard` refuses its NULL rows), and `working_habitat_digest` hashes `t::text` (`data-raw/habitat_variants_build.R:666-669`), so a base recorded before the pin cannot match. Say both in RUNBOOK §7 and the harness header (rebuild with `--step=base`); no probe on a kept schema.
- [ ] Under `R_LIBS`: `devtools::test()`, `devtools::check()`, `lintr::lint_package()` per file and linter against `origin/main`, `pkgdown::check_pkgdown()`.
- [x] Drop the four scratch schemas (and the backfill copy); evidence README in `data-raw/logs/fresh_pin_481/`.

## Phase 7: Release

- [ ] NEWS 0.87.0 and the version bump as the branch's last code commit; CLAUDE.md status block.

## Owed at the end (reported, done after merge)

- [ ] Install fresh 0.55.1 into each host's shared library (`pak` from the pin), and re-prep every host (`--auto-install` at the next launch; m1's worker).
- [ ] Under Open decision 2 (a): migrate `streams_near_river` in `fresh_default`, `fresh` and `fresh_default_minimal` on each host, once, at a quiet time.
- [ ] The pre-run gate runs again before the next provincial run (`R/`, the fresh pin and `pretest_inputs.csv` changed).
- [ ] The variants harness's bases (`score*` schemas, `data-raw/logs/habitat_score_284/` digests) are rebuilt with `--step=base` before the next variants run.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: Phase 6's digest comparison proves the pin changes no output but the new column; the column check and the backfill-on-a-copy check prove the stored data; the TRUE/FALSE validator run proves the re-test; Phase 4's mocked tests and Phase 5's redirected run prove the connection order and the gated tests.
