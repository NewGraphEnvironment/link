# Findings — Backlog move 18: fresh's internals pinned by argument, at fresh 0.56.0 (#507)

## Issue context

See #507's body (batch 26, member #504) and #504's body: pin the formals link passes to the four fresh internals it reaches through `getFromNamespace()`, have the drift guard report those call sites, and run the pre-run gate when the pin moves (fresh 0.56.0, NewGraphEnvironment/fresh#327). fresh's side: NewGraphEnvironment/fresh#329 (contract test, open), NewGraphEnvironment/fresh#328 (link's tests on fresh PRs, open).

## Measured while planning (2026-11-23)

- **The four internals' signatures are identical at fresh v0.55.1, v0.56.0 and v0.57.0** (read from each tag's tarball): `.frs_run_connectivity(conn, table, habitat, species, params, params_fresh, verbose = TRUE)`, `.frs_habitat_models(wsg_codes, params_method)`, `.frs_near_river_specs(params, species, models = "cw")`, `.frs_sql_num(x)`. m1's shared library holds fresh 0.55.1.
- **link passes every formal of all four.** By name: `.frs_run_connectivity` (`R/lnk_pipeline_connect.R:101`). Positionally: `.frs_habitat_models` (`R/lnk_config.R:410`), `.frs_near_river_specs` (`R/lnk_discharge.R:409`), `.frs_sql_num` (`R/lnk_pipeline_persist.R:299`, through `vapply`). So order matters, and a name-set check would miss a reorder.
- **fresh files changed v0.55.1..v0.56.0:** `frs_cluster.R`, `frs_habitat.R`, `frs_habitat_classify.R`, `frs_habitat_overlay.R`, `frs_near_river.R`, `frs_order_child.R`, `utils.R`; all mapped in `data-raw/pretest_inputs.csv` (segments, near_river_conn, any). v0.56.0..v0.57.0 adds `frs_col_join.R`, `frs_feature_find.R`, `frs_habitat_predicates.R`, `frs_params.R`, also all mapped.
- **0.56.0's NEWS for link:** the `to_barriers` fix is `frs_habitat()`'s, which link does not call; the new refusals reach link's `frs_habitat_classify()`, `frs_near_river()`, `frs_cluster()`, `frs_order_child()` and `frs_habitat_overlay(bridge =)` (link's working `streams` must carry a group on every row); link's one `frs_habitat_overlay()` call uses the default join, not `by = "id_segment"`.
- **fresh v0.57.0 exists** (released 2026-11-23 04:51 UTC) and changes `lake_rearing` (reservoirs counted): an open decision in `task_plan.md`.
- #481's evidence scripts (`data-raw/logs/fresh_pin_481/run.sh`, `digest.R`, `compare.R`) are the template for Phase 3.

## Phase 1 mutation proof (2026-11-23)

Swapped `.frs_habitat_models`'s declared formals to `c("params_method", "wsg_codes")` in `.lnk_fresh_required_internal_formals()` and ran `test-lnk_preflight_fresh.R` (`NOT_CRAN=true`, fresh 0.55.1): FAIL 3 (the live pass at line 4, the exact-equality loop naming `.frs_habitat_models` at 102, and `mismatched_internal_formals` empty at 107). Restored: FAIL 0, PASS 64.

A mocked namespace cannot stand in for fresh inside `lnk_preflight_fresh()` (`getNamespaceExports()` refuses a plain environment), so the end-to-end refusal test declares a reordered list against the real fresh; the helper's cases (reorder, rename, drop, trailing with and without a default, absent) run on plain environments.

## Phase 2 mutation proof (2026-11-23)

In a detached worktree of the Phase 2 commit (Phase 2's commit), appended `.lnk_mutant_507 <- function() getFromNamespace(".frs_fake", "fresh")` to `R/lnk_pipeline_connect.R`: `test-lnk_preflight_fresh.R` FAIL 1, at the set-equality test, naming `.frs_fake` as the extra call site. Worktree removed. On the branch: FAIL 0, PASS 70.

## Phase 3: 0.56.0's refusals against link's calls (2026-11-23)

- link's one `frs_habitat_overlay()` call (`R/lnk_pipeline_classify.R:149`) passes `bridge = <schema>.streams`, so 0.56.0's new bridge refusal (`.frs_group_required(conn, bridge)`) applies to it; the direct-mode `by = "id_segment"` refusal does not (no `by`).
- `frs_cluster()` gains `.frs_group_required()`; `frs_habitat_classify()` now refuses any NULL group, not only on a table carrying `linear_feature_id`. link's working `streams` is the FWA's, with `watershed_group_code` on every row; the after-builds are the check (a NULL would stop them).
- `data-raw/compare_adms.R` (legacy, off the run path) calls `frs_habitat()`, whose 0.56.0 refusal of an unkeyed `to_barriers` would reach it.
- The gate's reach at v0.56.0 is the same 19 files as at v0.55.1 (`data-raw/logs/fresh_pin_507/reach.md`), and all seven changed files are mapped, so `pretest_inputs.csv` does not change. The walk at 0.55.1 now refuses on this branch (`load_all` needs fresh >= 0.56.0), as expected.
- Lint against `origin/main`: new rows are indentation (2,458 stand on main in the same style) and three helper names over 30 characters (`object_length_linter`, 18 on main); the names are the plan's and kept.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff -rq` in a probe ran `git diff` (a shell function shadows `diff`) | `/usr/bin/diff -rq` |
| `git -C <repo> worktree add lint_main` put the worktree inside the repo (relative to `-C`) | removed; absolute path under `/tmp/link507/` |
| A mocked plain environment as fresh's namespace fails `getNamespaceExports()` | end-to-end refusal test declares a reordered list against the real fresh |
