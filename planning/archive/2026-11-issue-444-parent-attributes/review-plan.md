# Plan review — #444 baseline (Plan agent, 2026-11-03, synchronous at the park)

Findings as returned, with the verdict after each probe. Folded into `task_plan.md` on the baseline commit.

## Blocker
- **Acceptance 2's join key does not exist.** The plan joined the table to `parent_<wsg>.csv.gz` by `(blue_line_key, downstream_route_measure)`, but the CSV holds only `id_segment, wsg, id_segment_minimal, gradient_minimal, length_minimal, overlap_m, straddle_m`, and the `zz415_*` schemas that could resolve ids to positions are gone. **Confirmed** (CSV header read). Fix taken: join on `id_segment` and `id_segment_minimal`, sound because `.lnk_pipeline_break_reassign_id()` numbers `ORDER BY blue_line_key, downstream_route_measure` (`R/lnk_pipeline_break.R:301-309`, confirmed), with length guards: `overlap_m + straddle_m` within 1e-3 m of `fresh_default.streams.length_metre`, `length_minimal` within 1e-3 of `fresh_default_minimal.streams.length_metre` at the matched minimal id (the check `knw_parent_join()` applies). Id equality is the result.

## Gap (all taken)
- `m.dm > 0.5` (`proof.R:193`) is the cut floor, not "above zero": pin `cut_floor_m = 0.5` and cite proof.R.
- No per-group row-count assertion: a full segment shorter than `sliver_m` gets no `pc` row. `lnk_streams_parent()` stops when inserted rows != `n_full`.
- The full side's cut token was unchecked: require a `cut-full-*` token, so `default_minimal` paired with itself is refused.
- Replace was not atomic: `DELETE` + `INSERT` inside `DBI::dbWithTransaction()`; `--verify` also names groups with zero rows.
- `pretest_reach_repo()` re-`load_all`s with `export_all = FALSE` after the driver's own `load_all`, so bindings go stale. The driver calls `pretest_reach(asNamespace("link"), pretest_entries(<wsg_run_one.R>, ns))` on the loaded namespace, as `test-pretest.R:44-56` does, and passes `reached` in.
- Nothing refuses a stale table (persist, consolidate and `host_drop_partials` all leave `streams_parent` alone). Accepted per decision 3; `length_full` (= `overlap_m + straddle_m`) is the reader-side guard, named in the RUNBOOK note, and `--verify` and `prototype_check.R` compare it with `streams.length_metre`.

## Ordering (taken)
- Phase 1 could not be green on its own commit (tests sourcing a Phase 3 helper skip; the vocabulary test is red until Phase 4; `test-pretest.R`'s map coverage is red the moment the `R/` file exists until the map row lands). Each phase now lands its own tests, and the map row lands with the `R/` file in Phase 2.
- `data-raw/streams_parent.R` (helper) and `data-raw/streams_parent_build.R` (driver) are both named in decision 1.

## Assumption
- `none` is judged at HEAD, not at the pair's shas (the same limit `pretest_record_check()` accepts): stated in the driver header.
- Record-check steps rightly dropped for a pair: `verdict`, `since_sha` / `pretest_since_covers`, the ancestor test, the `PRETEST_RULES` diff. `fresh_dirty` FALSE and `fresh_sha` non-NA added to the pair guard. The recompute is not needed (the join reads `streams` only).
- Vocabulary invariants permit a live row no config resolves to (prefix, live axis+spec uniqueness, append-only); no test asserts every live row is matched. Safe.
- The `none` map row holds: the call graph walks from `wsg_run_one.R` only.
- `_pkgdown.yml` has no `reference:` index (confirmed): `check_pkgdown()` is a no-op here; dropped from Phase 2.

## Scope
- Added beyond the issue: `token_flow`/`token_grad` equality, `log.species` equality, the fresh-pin check, `--verify`, provenance columns, the province build, 0.79.0. All kept. `pair.tsv` also records the full side's `config_hash` and `link_sha`.

## Acceptance
- Line 2 closes on the id join with the length guards.
- Line 1 stays knowledge's; the note of the table's shape says `wsg` is `watershed_group_code` here and what `length_full` means, so knowledge's switch from `PARENT_DIR` does not break on the column name.
