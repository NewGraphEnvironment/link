# Code-check round 5 (#372): c182c232, and round 4's enumeration re-walked

## Checklist read

- **code-check.md**: index read in full. I read the prose (not the `|` evidence rows) of the `## Mechanisms` H3s, from "A guard that fails toward pass" through "A guard's scope, escape hatches, and remedies"; the rest from their index lines and round 4's reading. Applied: fails toward pass (unreadable as a third state, a hand-kept list as a stand-in), a proxy is not the property (HEAD standing in for the code that runs), the guard's scope (a hand-kept list grows blind), restore the bug and prove the guard fires (probes below), and a fixture that cannot reach the failure mode (the reach test at one tag).
- **code-check-r.md**: index read in full. Applied: `deparse(body(f))` excludes formal defaults; `deparse()` re-encodes, so it answers about itself rather than the file; `on.exit()` at top level; `tryCatch()` nesting and `finally` order; `system2(stdout = TRUE)`; `load_all()` and a dependency floor.
- **code-check-shell.md**: index read in full. Applied: `if ! cmd; rc=$?`, `wait` on a PID, a failed `cd`, `grep -c`, psql quoting. No section needed in full.
- **code-check-spatial.md**: index read in full. No spatial code in this round's diff.

## Probes run

- `devtools::test(filter = "pretest")`: FAIL 0, ERR 0, SKIP 0, PASS 98 (the fresh reach test ran; it created and removed its worktree). `git status --short` empty before and after; `git -C ../fresh worktree list` the same before and after.
- Finding 1: a temp repo, the real `pretest_record_check()`. The record and HEAD are commit A, the map says `R/a.R` is `segments`, and `R/a.R` is edited and not committed (`git status` ` M R/a.R`). The check returns `ok = TRUE`.
- Finding 2: link's reached functions, deparsed as `pretest_reach_fresh()` does. Two of the four `getFromNamespace(..., "fresh")` calls on the path wrap across lines (`.frs_near_river_specs` in `.lnk_near_river_pairs`, `.frs_habitat_models` in `.lnk_wsg_model`), so `by_name` finds only `.frs_run_connectivity` and `.frs_sql_num`. At fresh v0.44.0 (my own worktree, removed afterwards), adding the two missed entries reaches no extra function or file today: both sit in files reached another way (`frs_habitat_predicates.R`, `utils.R`). At v0.44.0, 0 of the 62 fresh functions reached have no srcref.
- `lnk_wsg_downstream_check(outlets = fresh::frs_wsg_outlets())` is a fresh call in a formal default, which `deparse(body())` leaves out. A body elsewhere on the path also names `frs_wsg_outlets`, so nothing is missed today.
- The worktree cleanup in `pretest_reach_fresh_at()`: an error inside `pretest_reach_fresh()` passes through the pick's exiting handler, which unwinds first, so `finally` removes the worktree before `refuse()` calls `quit()`. `on.exit(unload("fresh"))` is registered after the fresh `load_all`. The pick's next step, `pretest_reach_repo()`, reloads link, and link loads the installed fresh again. link imports nothing from fresh in NAMESPACE, so the unload has no users to break. fresh's `zzz.R` holds only an `.onAttach` (the load uses `attach = FALSE`), so the worktree's fresh leaves no options behind.

## Findings

1. **[severity: fragile]** data-raw/pretest.R:454-491 (`pretest_record_check()`), data-raw/pretest_check.R:46, data-raw/study_area_run.sh:1025-1031 and :1155. **The record check stands HEAD in for the code that will run, and a dispatcher-only run goes ahead on a dirty tree.**
   - Every diff the check takes is between two commits: `rec$link_sha` and `--head=$RUN_SHA`, where `RUN_SHA` is `git rev-parse HEAD`. Uncommitted edits are in no changed set.
   - `preflight_local()` refuses a dirty tree only when `N_HOSTS > 0`. With the dispatcher alone it prints `WARN: dispatcher checkout dirty` and carries on, and the dispatcher's leg runs `load_all`, so it models the working tree.
   - So an uncommitted edit to `R/lnk_pipeline_prepare.R` is cleared by any passing record at HEAD. The probe above shows `ok = TRUE`. RUNBOOK §8d says "The check applies to every launch, dispatcher-only included", and "What it does not cover" does not name a dirty tree. The gate refuses a dirty tree on its own side (pretest_run.sh:108); the driver's side has no such check.
   - Fix: in `pretest_check.R`, run `git status --porcelain -- ':(top,exclude)data-raw/logs'` and exit 1 when it is not empty (an aborted `git status` exits 2). Alternatively, diff the record's SHA against the working tree (`git diff --name-only <sha> --` plus `git ls-files --others --exclude-standard`) and judge those files by the map.

2. **[severity: fragile, latent]** data-raw/pretest.R:379-383 (`pretest_reach_fresh()`). **link's calls into fresh are found by matching regexes on `deparse(body(f))` one line at a time, so a call that `deparse()` wraps, or one in a formal default, never enters fresh's walk.**
   - This is the same mechanism as round 3's: a stand-in (deparsed text) filtered without an error. `by_name` needs `getFromNamespace("x", "fresh")` on one line, and `deparse()` breaks long calls between their arguments. Two of the four calls on the path wrap today, so `.frs_near_river_specs` and `.frs_habitat_models` are missed as entries.
   - `body()` drops formals, so `outlets = fresh::frs_wsg_outlets()` is missed as well.
   - Nothing is lost at v0.44.0, because each of the three is reached another way (probe above). But a fresh helper reached only through such a call, in a file mapped `none`, would read as off the path. The `missing` check only tests calls that were found.
   - Fix: walk the parsed functions, not their text. For each reached link function, collect `::`/`:::` calls whose left side is `fresh`, and `getFromNamespace` calls whose second argument is `"fresh"`, from `body(f)` and `formals(f)`. A recursive walk over the language objects does this. Failing that, `deparse(f, width.cutoff = 500L)` with the lines pasted together covers the wrap and the formals (`deparse(f)` includes formals).

3. **[severity: fragile, latent]** data-raw/pretest.R:50-53 (`PRETEST_RULES`). **The gate's rules are a hand-kept list.** Every `data-raw/pretest*` file there is today is on the list, so nothing is missed now. A new gate script (a new helper the pick sources, say) would be judged by HEAD without voiding older records, and nothing tests that the list is complete. Fix: use `":(glob)data-raw/pretest*"` together with `"data-raw/pretest/"`, or add a test that `list.files("data-raw", "^pretest")` is a subset of the rules.

Not findings (checked):

- `pretest_since_covers(repo, since, end, ...)`: both call sites pass the range's end (pick `until_sha`, check `rec$link_sha`); the test covers past-the-end and off-line history. A history build made after the gate on a descendant of `rec$link_sha` now refuses ("not on the line"). That is toward refuse.
- The both-ends map merge: only the map at `until` judges unmapped files; the old map adds inputs and never removes them. A `none` survives only when both maps say `none`. The old map is missing only where `since` predates the gate. When the old map's columns differ, it errors uncaught: the pick exits 1, which is toward refuse, though the signal is wrong (1 reads as a group failure).
- An input named only by the old map with no `.sql` at HEAD refuses ("has no query"), which is toward refuse.
- The start busy check counts every other session (round 4's Finding 9 is fixed). The per-group sample keeps the maximum, `unknown` becomes -1 only when no sample saw load, and the verdict lists -1 as "could not tell" (round 4's Finding 5 is fixed).
- The cloud and worker legs' environment is in `data-raw/study_area_remote.sh:114`, which is sourced by the driver and is not in `PRETEST_LINK_PATHS`. So a change there neither is named nor voids a record. This is inside RUNBOOK's accepted "The driver's own environment for a group" limit, but that bullet's "a change to it is named and voids a record" holds only for `study_area_run.sh`. That is documentation precision.

## Enumeration (confirmed table)

Round 4's rows, against c182c232. Direction: **refuse**, **pass** (finding), **accepted** (documented or listed), **n/a**.

**data-raw/pretest.R**

| place | now | direction |
|---|---|---|
| `PRETEST_ENTRIES` :44 | floor; `pretest_entries()` derives the list | refuse |
| `PRETEST_RULES` :50-53 | all 8 gate files plus `pretest/` (round 4's Finding 3 is fixed); hand-kept | refuse today; latent pass for a new script (Finding 3) |
| `PRETEST_FRESH_JUDGED` | removed; replaced by `pretest_reach_fresh_at()` at `fresh_to` | refuse for fresh `R/`, with the latent gap in Finding 2 |
| `pretest_map_read` :56 | | refuse |
| `pretest_config_chain` :80 | | refuse |
| `pretest_git` :96 | | refuse |
| `PRETEST_LINK_PATHS` :111 | now includes `study_area_run.sh` (`unexercised`); the sourced `study_area_remote.sh` is not | accepted (the driver's environment limit; doc note) |
| `pretest_changed_link` :123 chain filter | | refuse |
| `pretest_fresh_pin` :128 | | refuse |
| `pretest_changed_fresh` :141 | installed fresh not compared with the pin | accepted |
| `pretest_match` :155 | | refuse |
| `pretest_inputs` :184 | | refuse |
| `pretest_pick` :199-200 | | refuse |
| `pretest_pick` :206 any | | n/a |
| `pretest_bound` :237 | | refuse |
| `pretest_verdict` :250 | | refuse |
| `pretest_overall` :260 | | refuse |
| `pretest_reach` :274 functions only | constants documented (RUNBOOK limit) | accepted |
| `pretest_reach` :281 entries | | n/a |
| `pretest_reach` :295 `na.omit` | link guarded by `pretest_reach_repo`; fresh guarded by the `frs_habitat_classify.R` check, and 0 srcref-less at v0.44.0 | refuse (guarded) |
| `pretest_none_reached` :302 | `R/` only; DESCRIPTION documented; `inst/extdata` `none` rows are a per-file judgement (the "input nobody mapped" limit) | refuse for `R/`; accepted otherwise |
| `pretest_history_sql` :314 | | n/a |
| `pretest_since_default` :328 | | refuse |
| `pretest_entries` :341 | | refuse |
| `pretest_reach_repo` :357 | | refuse |
| `pretest_reach_fresh` :374-397 | an empty call set stops, a missing fresh symbol stops, a reach without `frs_habitat_classify.R` stops; calls found from body text one line at a time | refuse; latent pass (Finding 2) |
| `pretest_reach_fresh_at` :401 | worktree removed in `finally` (it runs before the pick's `refuse()` quits); a failed remove leaves a stale registration only | n/a |
| `pretest_is_ancestor` :410 | | refuse |
| `pretest_since_covers` :422 | `since <= h` and `h <= end` (round 4's Finding 1 is fixed) | refuse |
| `pretest_record_check` :459-462 | | refuse |
| :463-467 fresh | | refuse |
| :468 empty history | | refuse |
| :469 cover at `rec$link_sha` | | refuse |
| :471 ancestor of HEAD | | refuse |
| :474 rules diff | all gate scripts | refuse |
| :478 pin | | refuse |
| :482-490 changed since the record | commits only; the working tree is not read | **pass** (Finding 1) |
| k / floor_min / per_input | | accepted |

**data-raw/pretest_pick.R**

| place | now | direction |
|---|---|---|
| :48-57 args | | refuse |
| :66-72 history | | refuse |
| :73-77 since | | refuse |
| :84-90 cover with `until_sha` | | refuse |
| :92-100 chain, pins, changed | | refuse |
| :101-112 map at both ends | union of inputs; unmapped judged at `until` (round 4's Finding 2 is fixed) | refuse |
| :115-123 fresh `none` | walked at `fresh_to` (round 4's Finding 4 is fixed) | refuse; latent (Finding 2) |
| :125-129 reached `none` (link) | | refuse |
| :148-155 unmapped | | refuse |
| :174-188 minutes | | refuse |
| :190-199 queries | | refuse |
| :200 picks | | refuse |
| :217 no picks | | n/a |

**data-raw/pretest_verdict.R**: unchanged since round 4. :69-72 refuse; :78-83 informational; :84-93 refuse; :98-109 no-model path accepted; :110-120 refuse; :138-141 refuse.

**data-raw/pretest_check.R**: :38-42 refuse; :44-48 map, chain and reach at HEAD (guarded by the rules diff), but the working tree is not read: **pass** (Finding 1); :56 errors exit 2, refuse; :35 `on.exit` inside `tryCatch`'s expression (not top level), n/a.

**data-raw/pretest_run.sh**

| place | now | direction |
|---|---|---|
| :49, :75-82 | | refuse |
| :108-111 clean tree, `pg_isready` | | refuse |
| :122-124 pick | | refuse |
| :128-132 until == HEAD | | refuse |
| :136-146 `--only` | | refuse |
| :155-157 live | | accepted (heuristic) |
| :158-168 busy | every other session counted (round 4's Finding 9 is fixed) | refuse; `--allow-busy` accepted |
| :207-211 row regex | | refuse |
| :229-251 watchdog | | refuse |
| :231-236, :253 per-group sample | max kept, -1 only when nothing was readable (round 4's Finding 5 is fixed) | informational |
| :265-269 verdict | | refuse |

**data-raw/study_area_run.sh**

| place | now | direction |
|---|---|---|
| :326-328 `--pretest-note` | | refuse |
| :1025-1031 dirty dispatcher | with `N_HOSTS = 0` only a WARN, and the gate check then reads HEAD | **pass** (Finding 1) |
| :1155-1169 gate | only rc 0 clears | refuse |
| :1521 `--refresh-primitives` | | accepted |
| :1561-1570 override row | | refuse |
