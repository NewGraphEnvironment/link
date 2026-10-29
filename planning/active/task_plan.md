# Task: Recompute: test existence instead of building natural-barrier arrays, and walk each barrier set once (#394)

**If we do it:** the recompute stops building arrays it throws away, and stops walking the same barrier set up to seven times a group; the output-bound groups that NewGraphEnvironment/fresh#272's prefilter barely helps (SETN 1.2×) get faster too. **If we never do:** after NewGraphEnvironment/fresh#272 the recompute's remaining cost sits in those groups and in repeated walks, and the next provincial run pays it.

Folds in #409 (adopt the fresh prefilter, fresh#272), bumping fresh to v0.47.0, which also carries `frs_network_features(result = "exists")` (fresh#281).

## Context

The recompute's cost is its `fresh::frs_network_features()` walks (#261). fresh has since shipped
both pieces this issue waited on: the feature prefilter (fresh#272, v0.45.0) and an existence mode,
`result = "exists"` (fresh#281, v0.47.0). In fresh's own measurement the exists mode is 1.00× (SALR)
to 1.24× (SETN) faster end to end, because the join, not the array build, is most of the cost. link
still pins fresh v0.44.0, so neither reaches the recompute (#409 is open for the bump).

In `R/lnk_pipeline_access.R`, the natural per-species walks (`barriers_<sp>_access`) and the `pscis`
source are reduced to `has_barriers_*_dnstr` by `id %in% result$id`, so they can take
`result = "exists"`. The `anthropogenic`, `dams` and `remediations` walks keep arrays (`dam_dnstr_ind`
and `remediated_dnstr_ind` read their first elements), and so does the upstream observation walk.
The returned tibble carries no barrier arrays, so nothing downstream changes.

Lever 2: each species has its own view, so the per-table cache never hits, and CHWK walks five
CH-shaped views that return the same thing. The views differ by `blocks_species` and per-species
overrides, so an exact test is needed: a fingerprint of the rows each view can offer the walk from
this group. `fwa_downstream()` admits only features on one of the group's blue lines or whose wscode
is an ancestor of, or equal to, a group segment's (#261; fresh's `.frs_walk_prefilter()` uses the same
predicate). A superset of what the walk can read is enough for exactness. Province-wide fingerprints
are ruled out: `fresh_default.barriers` holds 7.7 M rows (7.4 GB), and in early mode (#374) it
changes during the run.

## Decided at the gate (operator, 2026-10-28)

- **Fold #409 in.** This branch bumps fresh to v0.47.0 and closes #409. The measurements are
  stepped: main on fresh 0.44.0 (installed on m1 now), main on 0.47.0 (prefilter only), lever 1,
  then lever 2.
- **Lever 2: measure, then build.** After lever 1, count the walks whose result repeats an earlier
  walk in the same group. Build the fingerprint only if those repeats are at least 10 % of the
  access phase's walk time over SALR, CHWK, SETN and LFRA. Otherwise record the number and stop.

## Phase 1: baseline on fresh 0.44.0, then the bump (#409)

- [x] Write `data-raw/logs/recompute_access_394/measure.R <variant> <WSG...>`:
  - load_all from `LNK_SRC` (a worktree for main);
  - refuse when another client backend is active, unless `--allow-busy` is passed, which it records;
  - run `lnk_access(merge = FALSE, build_views = FALSE)` on `fresh_default` into `zz394_<wsg>`,
    timed, and time each walk with a `trace()` on `frs_network_features` (table, result mode,
    seconds, rows);
  - digest the output sorted by `id_segment` over every `has_*`, `access_*` and `dam_dnstr_ind`;
  - append to `measure.tsv` with the variant, link SHA, fresh version and RemoteSha, and the load;
  - drop the scratch table.
- [ ] Run variant `base044` (main worktree, fresh 0.44.0) on SALR, CHWK, SETN and LFRA.
- [ ] Model one or two small `default` groups into a scratch schema at main on 0.44.0, and save
  per-table digests (#409's "outputs should not move").
- [ ] Install fresh v0.47.0 (`--auto-install` path / pak from the tag; confirm `RemoteSha`).
  Bump `DESCRIPTION` (`fresh (>= 0.47.0)`, `Remotes: NewGraphEnvironment/fresh@v0.47.0`). Read
  fresh's NEWS for 0.45 to 0.47 for anything else that could move outputs.
- [x] `lnk_preflight_fresh()`: assert `frs_network_features()` has a `result` formal, so a host on an
  older fresh fails at preflight. Add a test for it.
- [ ] Run variant `prefilter` (main code, fresh 0.47.0), with digests equal to `base044`. Rebuild
  the scratch groups and confirm the per-table digests are identical.

## Phase 2: lever 1, existence walks

- [ ] Tests first, in `tests/testthat/test-lnk_pipeline_access.R` (mocked `frs_network_features`
  recording its `result`): per-species and `pscis` walks ask for `"exists"`; `anthropogenic` and
  `dams` (when both are present) and `remediations` (when `crossings_table` is set) ask for
  `"ids"`; the observation walk asks for `"ids"`; a table in both roles is walked once, in `"ids"`;
  the `has_*` flags and the NA / FALSE zero-row rules are unchanged.
- [ ] `lnk_pipeline_access()`: choose the mode per table (arrays only where a role reads elements),
  and key the cache on table and mode. Correct the roxygen that says the arrays stay on the
  returned tibble.
- [ ] Run variant `exists` on the four groups. Digests must equal `base044`. Record per-walk minutes.
- [ ] Compute lever 2's ceiling from those rows: the time of walks whose segment set repeats an
  earlier walk in the group, as a share of the walk time. `ceiling.tsv` plus a short note.

## Phase 3: lever 2, one walk per identical set (only if the ceiling is at least 10 %)

- [ ] Tests first: tables with equal keys are walked once and each species gets the result; unequal
  keys are walked separately. Restore the bug (force equal keys for views that differ) and show
  the test goes red. Add a live test (skipped without a DB): two species views identical except for
  one override inside the group's reach give different keys, and identical views give equal keys.
- [ ] `.lnk_walk_keys()`: one query over the per-species tables. Each table's admissible rows
  (on the group's blue lines, or with a wscode that is an ancestor of, or equal to, a group
  segment's; the AOI's segments only) are reduced to `md5` over every column the walk reads (id,
  `watershed_group_code`, `blue_line_key`, `downstream_route_measure`, wscode, localcode), in a total
  order. Equal keys then mean identical walk input, whatever the source table.
- [ ] Wire it into `lnk_pipeline_access()` for the `barriers_per_sp` walks only.
- [ ] Run variant `dedup` on the four groups, with digests equal to `base044`, and record the keys'
  own cost.
- [ ] If the ceiling is under 10 %: skip the build, record why in the README and on #377.

## Phase 4: record and docs

- [ ] `data-raw/logs/recompute_access_394/README.md`: the step table (`base044` → `prefilter` →
  `exists` → `dedup`, per group, walk and phase minutes), the digests, the load at each run, and the
  wrong turns.
- [ ] `research/recompute_cost.md`: revise the verdict with what the levers bought (Verified line).
- [ ] RUNBOOK (§8d, hosts need fresh 0.47.0, re-prep with `--auto-install`), and the CLAUDE.md
  status entry. Fill #394's and #409's lines on #377 by editing its body.
- [ ] NEWS entry and version bump as the branch's last commit.

## Owed at the end (reported, done after merge)

- [ ] Re-prep the worker and cloud hosts for fresh v0.47.0 before the next provincial run.
- [ ] The provincial recompute minutes at this release (#377's runs row).

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()` clean, `devtools::check()` clean
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- The bump: `base044` and `prefilter` digests are identical on four groups, and the per-table model
  digests of the scratch groups are identical.
- Lever 1: `exists` digests equal `base044`; the mocked tests pin the mode per role.
- Lever 2: `dedup` digests equal `base044`; a restored-bug test goes red; the live key test sees an
  override difference.
- Each timing is taken with no other active client backend, or marked busy.
