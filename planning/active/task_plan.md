# Task: Backlog move 18: fresh's internals pinned by argument, at fresh 0.56.0 (#507)

**If we do it:** link's pre-flight checks the arguments of the four fresh internals it calls, as it already does for fresh's exports, its drift guard names every `getFromNamespace()` call site, and link pins fresh 0.56.0 with the pre-run gate run on it. **If we never do:** a fresh change to one of these internals' arguments passes link's pre-flight and fails only when a watershed group reaches that phase, and link stays on fresh 0.55.1 while fresh's per-group barrier fix and its new refusals wait for the next bump.

One batch (26), one member (#504), one PR. Touches `R/lnk_preflight_fresh.R`, `tests/testthat/test-lnk_preflight_fresh.R`, `DESCRIPTION`, `RUNBOOK.md`, `data-raw/pretest_inputs.csv` (checked; see Phase 3), `NEWS.md`, `man/lnk_preflight_fresh.Rd`, and a new evidence directory `data-raw/logs/fresh_pin_507/`.

## Decided at the gate

No plan gate in this pane: a headless `park review` dispatched by the coordinator (soul#928). These were decided while drafting (mechanism, `agent-operations.md` §4); the owner's forks are under `## Open decisions`.

- **Decided at the sweep (2026-11-23, owner):** this move bumps the pin to fresh 0.56.0.
- **0.56.0, not 0.57.0 (owner, 2026-11-23, option a; #507 `## Decisions`):** fresh v0.57.0 (released 2026-11-23) changes output (`lake_rearing` counts reservoirs) and tightens rules-file refusals that reach `lnk_rules_build()`'s output, so it gets its own move with a re-model and a rules check; this move stays a no-output-change bump proved by digests.
- **Pin the full ordered signature, not a set of names** (refined by the Plan review, 2026-11-23: exact in the test, tolerant at run time). Measured on fresh v0.55.1, v0.56.0 and v0.57.0 (tarballs, 2026-11-23): the four internals' formals are identical across all three, and link passes every formal of each one: `.frs_run_connectivity(conn, table, habitat, species, params, params_fresh, verbose)` by name; `.frs_habitat_models(wsg_codes, params_method)`, `.frs_near_river_specs(params, species, models)` and `.frs_sql_num(x)` **positionally**. So "the formals link passes" and "the full signature" are the same list today, and positional calls make order load-bearing: the exports check (`setdiff()` on names) cannot see a reorder. **At run time** `lnk_preflight_fresh()` passes when the declared list is the leading run of the installed formals (`identical(head(have, length(want)), want)`) and every extra formal has a default, because the floor is `>=` and the check gates real launches (`study_area_run.sh:1019`, `cypher_prep.sh:237`, `worker_prep.sh:105`): a later fresh adding a trailing optional argument must not refuse a provincial run. **In the test** the declared list equals the installed fresh's formals exactly (`identical()`), mirroring fresh#329. fresh#329 asks for "formal names", not order, so the lists match only if fresh copies the order: the owed comment says so.
- **Land before NewGraphEnvironment/fresh#329, not after.** Neither side depends on the other's code; the list is read from fresh's own source, so fresh#329 can copy it. After merge, a comment on fresh#329 (our repo) gives it link's list and the test name (Owed).
- **The drift guard is a second walker, not a change to `.lnk_fresh_callsites()`'s contract.** `.lnk_fresh_callsites()` returns `fresh::`/`fresh:::` symbols that must be exports (so a `fresh:::.frs_x` in R/ already fails its test, line 142); a new per-function helper `.lnk_fresh_internal_calls_in(fun)` normalises each `getFromNamespace` call with `match.call(utils::getFromNamespace, call)` (bare, `utils::` or `utils:::` head, as `pretest_ns_calls()` in `data-raw/pretest.R:265` already reads them), returns `x` where `ns` is `"fresh"`, and errors on a non-literal `x` or `ns` (a guard that fails toward pass is what this exists to stop); `.lnk_fresh_internal_callsites(pkg = "link")` maps it over link's namespace. Known limit, written in the comment: `get(…, envir = asNamespace("fresh"))`, `asNamespace("fresh")$x` and `getExportedValue()` are not seen.
- **The new pre-flight argument:** `required_internal_formals`, a named list (internal → ordered formal names), default `.lnk_fresh_required_internal_formals()`; mismatches reported in a new result field `mismatched_internal_formals` as `"fn(want: a, b; have: a, c)"` and folded into `ok` and the message. `required_internal` keeps its type (character vector, existence check), and one source holds the list: `.lnk_fresh_required_internal()` becomes `names(.lnk_fresh_required_internal_formals())`.
- **The pre-run gate is owed, not run here** (Plan review): its record clears a launch only when its fresh SHA equals the dispatcher's installed fresh (`data-raw/pretest.R:590`), which needs fresh 0.56.0 in the shared library (the owner's machine change), and any `R/` change merged after it voids it. So this branch runs the gate's pick (`--pick-only`, writes nothing) to prove the map covers fresh's changes and to list picks and bounds, and the full gate runs after merge, at main, once the shared library holds 0.56.0. The PR and the closing comment say the move lands without the gate (#504 item 3 asks for it before the next provincial run).
- **Version 0.90.0** (minor: an exported function gains an argument and a result field).
- **Measure before and after from scratch libraries** (CLAUDE.md, #481): fresh 0.55.1 and 0.56.0 each installed alone into a scratch library; the shared library is not touched (a machine change is the owner's).

## Open decisions

None open.

## Phase 1: The internals pinned by ordered signature

- [x] `.lnk_fresh_required_internal_formals()` in `R/lnk_preflight_fresh.R` (and `.lnk_fresh_required_internal()` derived from its names): the four internals with their ordered formals as measured above, each with a comment naming its link call site (`lnk_pipeline_connect()`, `.lnk_wsg_model()` in `R/lnk_config.R`, `.lnk_near_river_pairs()` in `R/lnk_discharge.R`, `.lnk_near_river_pair_sets()` in `R/lnk_pipeline_persist.R`) and which are called positionally
- [x] `lnk_preflight_fresh(required_internal_formals = )`: input checks, an `.lnk_fresh_mismatched_internal_formals(ns, x)` helper (leading-run test plus defaults on any extra formal; an absent internal reports nothing here, since `missing_internal` already names it), result field `mismatched_internal_formals`, folded into `ok` and `.lnk_fresh_message()` ("  changed internal signatures: …"); the absent-fresh branch reports every entry
- [x] roxygen: the argument, the result field, and why order is checked for internals and not for exports; `devtools::document()`
- [x] The drivers' failure line reads "missing required symbols" when only a signature changed: reword it in `data-raw/study_area_run.sh:1027` and the matching lines in `cypher_prep.sh` and `worker_prep.sh` (check each)
- [x] Tests (`test-lnk_preflight_fresh.R`): passes on the installed fresh; a reordered, renamed and dropped formal each fail and are named, a trailing extra formal with a default passes and one without fails (mocked namespace, as the existing absent-fresh tests do); names of the formals list equal `.lnk_fresh_required_internal()`; every declared internal's formals are `identical()` to the installed fresh's
- [x] Mutation proof, recorded in `findings.md`: swap two formals in the default list and confirm the live test goes red; restore

## Phase 2: The drift guard names every `getFromNamespace()` call site

- [x] `.lnk_fresh_internal_calls_in(fun)` and `.lnk_fresh_internal_callsites(pkg = "link")` as decided above (`match.call()` normalisation; bare, `utils::`, `utils:::`; refuse a non-literal `x` or `ns`)
- [x] Tests: `setequal(.lnk_fresh_internal_callsites(), .lnk_fresh_required_internal())`, non-empty; `.lnk_fresh_internal_calls_in()` on throwaway functions finds a bare, a `utils::` and a `utils:::` call, a named-argument call (`ns = "fresh", x = ".frs_y"`), ignores a call on another namespace, and errors on a non-literal `x` and a non-literal `ns`
- [x] Mutation proof, recorded: add a fake `getFromNamespace(".frs_fake", "fresh")` call in a scratch copy and confirm the test goes red (in a `git worktree`, not this tree)
- [x] Comment above `.lnk_fresh_required_internal_formals()`: a change to the list is a change to fresh#329's contract test too; `data-raw/query_habitat_thresholds_mad.R:164` reaches a fifth internal (`fresh:::.frs_rule_to_sql`), off the run path and outside the namespace walk, so it is not pinned

## Phase 3: fresh pin v0.55.1 → v0.56.0, proved by digests

- [ ] `DESCRIPTION`: `fresh (>= 0.56.0)` and `NewGraphEnvironment/fresh@v0.56.0`
- [ ] Scratch libraries: fresh v0.55.1 and v0.56.0, each alone (`R CMD INSTALL -l <lib>` from a worktree of each tag; `FRESH_GIT_SHA` for the stamp)
- [ ] Check 0.56.0's new refusals against link's calls (close to a no-op: a streams table carrying `linear_feature_id` was already refused with a NULL group before 0.56.0, and link's working `streams` carries it): confirm it carries `watershed_group_code` on every row where `frs_habitat_classify()`, `frs_near_river()`, `frs_cluster()`, `frs_order_child()` and `frs_habitat_overlay(bridge = )` read it; link's only `frs_habitat_overlay()` call (`R/lnk_pipeline_classify.R`) uses the default join, not `by = "id_segment"`; note in findings that `data-raw/compare_adms.R` (legacy) calls `frs_habitat()`, whose 0.56.0 refusal of an unkeyed `to_barriers` would reach it
- [ ] `data-raw/logs/fresh_pin_507/`: copy and adapt #481's `run.sh`, `digest.R`, `compare.R`; build ADMS and BULK under `default` and ADMS under `bcfishpass` once on main + fresh 0.55.1 and once on this branch + fresh 0.56.0, into scratch schemas, after five quiet minutes on the database; `compare.R` stops on any difference; drop the scratch schemas after; README with the answer, how, and minutes
- [ ] The gate's reach at v0.56.0: `data-raw/pretest_reach_fresh.R` against a fresh checkout with tag v0.56.0 fetched (`test-pretest.R:584` walks it at the pin), saved as `reach.md`; a file mapped `none` that becomes reached gets a row
- [ ] `data-raw/pretest_inputs.csv`: every fresh file changed v0.55.1..v0.56.0 (`frs_cluster.R`, `frs_habitat.R`, `frs_habitat_classify.R`, `frs_habitat_overlay.R`, `frs_near_river.R`, `frs_order_child.R`, `utils.R`) is already mapped (checked 2026-11-23); re-check at the build and add rows only for a file left unmapped, so the file may not change
- [ ] Full suite twice: on fresh 0.56.0 from the scratch library (all pass), and on the shared library's 0.55.1 (only the floor's live checks fail, by design; name them); lint (per-file diff against `origin/main`); `devtools::check()` on the scratch 0.56.0. `FRESH_GIT_SHA` is the full commit (`git rev-parse v0.56.0^{commit}`), never the tag object

## Phase 4: RUNBOOK, NEWS, version

- [ ] `RUNBOOK.md` §8d (pre-flight, near line 2281): `lnk_preflight_fresh()` also pins the four internals' ordered signatures and the drift guard covers `getFromNamespace()`; the pin is 0.56.0; the pre-run gate owes a run on it after the shared library holds 0.56.0
- [ ] `NEWS.md` 0.90.0 and `DESCRIPTION` version as the branch's last code commit
- [ ] `CLAUDE.md` status block for #507 (what landed, owed, facts not worth re-deriving)

## Phase 5: The pre-run gate's pick on fresh 0.56.0

- [ ] `data-raw/pretest_run.sh --config=default --schema=fresh_default --pick-only` with `R_LIBS` on the scratch 0.56.0 and `--fresh-repo` on a fresh checkout holding tag v0.56.0: no unmapped changed file; the picks and bounds go into the evidence README (writes nothing to the database)
- [ ] The PR body says the move lands without the full gate, and names where it is owed

## Owed at the end (reported, done after merge)

- [ ] A comment on NewGraphEnvironment/fresh#329 giving link's ordered list (compared with `identical()` in link's test, leading-run at run time), the test that pins it, and the fifth internal `data-raw/` reaches (`.frs_rule_to_sql`)
- [ ] fresh 0.56.0 into each host's shared library and a re-prep (the owner's word: a machine change)
- [ ] The full pre-run gate on fresh 0.56.0 at main, after the shared-library install and before the next provincial run (`data-raw/pretest_run.sh --config=default --schema=fresh_default`)

## Validation

- [ ] Tests pass (scratch 0.56.0: all; shared 0.55.1: only the floor's live checks fail)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the internals check by tests on a mocked namespace (reorder, rename, add, drop) and a mutation of the default list; the drift guard by a mutation in a worktree and a set-equality test; the pin by table-group digests identical across fresh 0.55.1 and 0.56.0 (`compare.R` stops on any difference) and the gate's reach and pick at v0.56.0; the full gate is owed.
