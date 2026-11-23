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

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff -rq` in a probe ran `git diff` (a shell function shadows `diff`) | `/usr/bin/diff -rq` |
