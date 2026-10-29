# Code-check round 4 (#372): diff 22034de5...2f7d39fc (enumeration round)

## Checklist read

- **code-check.md**: I read the index in full, and the prose (not the `|` table rows) of all 14 `## Mechanisms` H3s: A guard that fails toward pass (table rows read too); A fixture that cannot reach the failure mode (table rows read too); A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. The standalone, security and spreadsheet/PDF sections were ruled out by their index lines.
- **code-check-r.md**: index read in full. Applied from it: `system2(stdout = TRUE)` warns rather than raises; `on.exit()` at top level; `read.delim()` quoting; `match()` with NA; `nzchar(NA)`; Postgres row order; `information_schema` by literal name; Rscript reads a script as it runs; `tryCatch()` nesting. No section needed in full.
- **code-check-shell.md**: index read in full. Applied: `if ! cmd; rc=$?`; `wait` on PIDs; a failed `cd`; psql `:'var'` in dollar quotes; `grep -c`; `local` self-reference; a `pgrep -f` waiter. No section needed in full.
- **code-check-spatial.md**: index read in full. The diff's spatial content is count queries over FWA (`data-raw/pretest/*.sql`); no section applies.

## Probes run

- `devtools::test(filter = "pretest")`: FAIL 0, ERROR 0, SKIP 0, PASS 94. `git status --short` empty before and after.
- `pretest_reach_repo(".")` under Rscript: 40 files; 338 namespace functions, 0 without a srcref.
- Finding 1, in a temp repo with the real `pretest_since_covers()` and `pretest_record_check()`: history built at an unmerged branch commit B that edits `R/a.R` (mapped `segments`), gate range A..C on main. `since_covers(A, B)` returns `""`; the range's changed set is `DESCRIPTION` only; `git diff B C` is `DESCRIPTION R/a.R`; `record_check` returns `ok = TRUE`.
- Finding 5, the watchdog's max in bash: samples `5 -1 0 3` report `others` as 5, -1, **0**, 3.
- Constants in `none` files: parsed every link `R/` file mapped `none` (26) for top-level non-function assignments: 0.

## Enumeration (final table)

Direction: **refuse** (the empty or missing case stops), **pass** (the empty or stand-in case lets a run through; a finding unless accepted), **accepted** (a documented tradeoff), **n/a** (no decision).

**data-raw/pretest.R**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| `PRETEST_ENTRIES` :44 | now a floor only; `pretest_entries()` derives the real list | refuse |
| `PRETEST_RULES` :50 | the gate's rules = `pretest.R`, the map, `pretest/`. Leaves out `pretest_pick.R`, `pretest_verdict.R`, `pretest_run.sh`, `pretest_check.R` | **pass** (Finding 3) |
| `PRETEST_FRESH_JUDGED` :56 | a frozen witness; enforced at the pick only (the record check relies on the pin check) | refuse |
| `pretest_map_read` :61-77 | bad columns, repo, empty cell, uncompiled pattern stop | refuse |
| `pretest_config_chain` :84 | NULL/NA/"" `extends` ends the chain; a cycle or missing bundle stops | refuse |
| `pretest_git` :104 | non-zero status stops; stderr to a file | refuse |
| `PRETEST_LINK_PATHS` :113 | fixed list of what a run reads. Covers R/, inst/extdata, DESCRIPTION, the entry scripts. Not `study_area_run.sh`, whose dispatcher leg sets the modelling env (`LNK_HABITAT_GATE`, `LNK_GUARD_DOWNSTREAM`, `PGOPTIONS`) that `pretest_run.sh` copies | **pass**, latent (Finding 8) |
| `pretest_changed_link` :124 `bundle %in% chain` | bundles outside the chain dropped; a chain change is a `config.yaml` change, mapped `any` | refuse |
| `pretest_fresh_pin` :132 | anything but one pin stops | refuse |
| `pretest_changed_fresh` :143 | identical pins give an empty set; installed fresh not compared with the pin | accepted (A5) |
| `pretest_match` :163-173 | `{config}` with an empty chain matches nothing, so unmapped | refuse |
| `pretest_inputs` :186 | `setdiff` of specials; an input with no `.sql` refuses at the pick | refuse |
| `pretest_pick` :200-201 | NA values and groups with no history dropped; empty after that stops | refuse |
| `pretest_pick` :207-212 | `any` alone picks the fastest group with history | n/a |
| `pretest_bound` :238 | NA minutes stops | refuse |
| `pretest_verdict` :253-256 | NA exit is `failed`; NA minutes `no_row`; 124 `bound` | refuse |
| `pretest_overall` :262 | empty is `fail` | refuse |
| `pretest_reach` :274 `intersect(findGlobals, fns)` | functions only: a non-function constant has no srcref, so a constant in a `none` file is never on the path (0 today) | **pass**, latent (Finding 7) |
| `pretest_reach` :281 `intersect(entries, fns)` | entries now come from `pretest_entries()`, which only returns namespace functions | n/a |
| `pretest_reach` :294 `na.omit(files)` | a srcref-less reached function's file dropped; 0 of 338 today, and `pretest_reach_repo` asserts the pipeline files | refuse (guarded) |
| `pretest_none_reached` :302 | NULL `reached` or no hits returns nothing. Every caller now passes a reach from `pretest_reach_repo()`, which errors on a pipeline-less reach. Only link `^R/` files are tested; link `inst/extdata` and `DESCRIPTION` `none` rows remain judgements | refuse for R/; **pass** for the DESCRIPTION row (Finding 6) |
| `pretest_history_sql` :320 | finished builds under the config only | n/a |
| `pretest_since_default` :328-335 | NA SHAs dropped, none left stops; dirty or NA-dirty stops | refuse |
| `pretest_entries` :342-349 | `SYMBOL_FUNCTION_CALL` only (a link function passed as a value or built by `do.call` is not an entry); a missing floor entry stops | refuse (floor); latent pass for value/`do.call` entries, which matches the documented "calls built at run time are not seen" |
| `pretest_reach_repo` :359-365 | no srcref stops; reach without `lnk_pipeline_run.R`/`lnk_pipeline_prepare.R` stops | refuse |
| `pretest_is_ancestor` :374-376 | only 0/1 are answers; anything else stops | refuse |
| `pretest_since_covers` :383-393 | NA SHA refuses; dirty/NA-dirty refuses; tests only `since` ≤ each history SHA, never history SHA ≤ until/HEAD | **pass** (Finding 1) |
| `pretest_record_check` :413-416 | no record, newest is fail: refuse | refuse |
| :417-422 | dirty/NA dirty, NA fresh, fresh ≠ installed: refuse | refuse |
| :423 | empty history refuses | refuse |
| :426 | record SHA not an ancestor of HEAD refuses | refuse |
| :429 | rules diff `rec$link_sha..HEAD` over `PRETEST_RULES` | refuse for those paths; **pass** for the pick/verdict/run scripts (Finding 3) |
| :434 | pin differs refuses | refuse |
| :439 | unmapped refuses | refuse |
| :442 | non-`none` input, or a reached `none` R/ file, refuses | refuse |
| k / floor_min / per_input not read | | accepted |

**data-raw/pretest_pick.R**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| :48-57 args | missing/invalid refuse | refuse |
| :66-72 history tables | absent `log` or no rows refuse | refuse |
| :73-77 default `--since` | `pretest_since_default` | refuse |
| :84-86 cover | `pretest_since_covers` | **pass** on history off HEAD's ancestry (Finding 1) |
| :88-96 chain, pins, changed | errors refuse | refuse |
| :97-98 map | read at the working tree (until); a relabel inside since..until is not a changed file, and files are matched only against the relabelled map | **pass** (Finding 2) |
| :100-106 fresh `none` | refuses unless `fresh_to` is `PRETEST_FRESH_JUDGED`; the remedy it prints points at `reach_fresh.R`, which carries its own copy of the entries and loads `<dir>/fresh044` | refuse; remedy wrong (Finding 4) |
| :108-112 reached `none` | refuse | refuse |
| :131-138 unmapped | refuse | refuse |
| :157-171 minutes | NA to median; all-NA median stops in `pretest_bound` (uncaught R error, exit 1) | refuse |
| :175-177 queries | missing `.sql` refuses | refuse |
| :183 picks | `pretest_pick` errors refuse | refuse |
| :200-203 no picks | goes on to the no-model path | n/a |

**data-raw/pretest_verdict.R**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| :43-49 exits | read only with picks | n/a |
| :69-72 match | missing exit is `failed`; missing row `no_row` | refuse |
| :78-83 `others` | informational; never moves the verdict | n/a (Finding 5 for its value) |
| :84-85 `na.omit` SHAs | now paired with `anyNA` at :91 and :116 | refuse |
| :86 dirty | `any(is.na | x)`; empty rows read FALSE, but then 0 SHAs fail | refuse |
| :98-109 no-model path | `link_sha <- range[2]`, `dirty <- FALSE` hard-coded; fresh read at verdict time | pass, latent (window of seconds after the clean check; unchanged from round 3) |
| :110-120 overall | | refuse |
| :138-141 `--subset` | always fail | refuse |
| :148-168 table | literal-name lookup on a regex-validated schema | n/a |

**data-raw/pretest_check.R**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| :216-218 args | stop, exit 2 | refuse |
| :228-229 no `log_pretest` | exit 1 | refuse |
| :232 no `log` | stop, exit 2 | refuse |
| :236-238 | map and chain at HEAD (guarded by the rules diff); reach at HEAD | refuse |
| :246 any error | exit 2 | refuse |
| :225 top-level `on.exit` | never fires | accepted |

**data-raw/pretest_run.sh**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| :49 bash version | refuse | refuse |
| :75, :78-82 args | refuse | refuse |
| :108-110 clean tree | status failure or dirt refuses; skipped on `--pick-only` (no record) | refuse |
| :111 `pg_isready` | refuse | refuse |
| :122 pick status | propagated | refuse |
| :128 until == HEAD | refuse | refuse |
| :136-141 `--only` | regex, none kept refuses; record never passes | refuse |
| :149-154 `live` | heuristic on current query text | accepted |
| :149-151, :155 `busy` | excludes `application_name LIKE 'pretest\_%'`; at start the gate has no session of its own, so this hides only another gate (which shares `fresh_pretest_<config>` under the same config and drops it) | **pass** (Finding 9) |
| :160-163 `--allow-busy` | recorded in notes | accepted |
| :167 empty picks | no scratch, verdict's no-model path | n/a |
| :207-208 row regex | malformed refuses | refuse |
| :225-242 watchdog | kill at bound, 124; backends terminated | refuse |
| :226-230 per-group sample | max resets after a -1 (Finding 5) | informational |
| :252-255 notes | | n/a |
| :257-259 verdict | exit propagated | refuse |

**data-raw/study_area_run.sh**

| place | stand-in, or empty/missing case | direction |
|---|---|---|
| :326-328 `--pretest-note` | empty refuses | refuse |
| :1155-1169 gate | only rc 0 clears; empty `fresh_sha_local` already fails above, and gives a mismatch here | refuse |
| :1521 `--refresh-primitives` before the gate check | primitives after the gate | accepted (RUNBOOK) |
| :1561-1570 override row | after `--preflight-only` exits; failure is FATAL | refuse |

## Findings

1. **[severity: fragile]** data-raw/pretest.R:381-396 (`pretest_since_covers`), used at pretest_pick.R:84 and pretest.R:424. **The range is held to start at or before every history build, never to end at or after it, so a build whose SHA is not on HEAD's ancestry is "covered" while its code is in no diff.**
  - The check is `since` ancestor-of `h`. Every change the gate and the record see is a tree diff between two commits on HEAD's line (`since..until`, `rec$link_sha..HEAD`). For a history build at a commit H that is not an ancestor of HEAD, the code that last ran differs from HEAD by `git diff H HEAD`, and the commits only on H's side are in neither diff.
  - Probed (temp repo, the real functions): A on main; B on an unmerged branch edits `R/a.R` (mapped `segments`), and history is built at B; C on main. `pretest_since_covers(A, B)` is `""`; the range A..C changes `DESCRIPTION` only; `git diff B C` is `DESCRIPTION R/a.R`; `pretest_record_check()` returns `ok = TRUE`.
  - How it arises here: a group re-modelled into the persist schema from a worktree on an unmerged branch (CLAUDE.md: "Run from a worktree"), or a branch later squash-merged.
  - Fix: in `pretest_since_covers()`, also require each history SHA to be an ancestor of the range's end (`until` at the pick, `rec$link_sha` at the record check), and refuse otherwise. That is the stand-in ("since..until") made equivalent to the property ("every difference between the code that last ran and this code").

2. **[severity: fragile]** data-raw/pretest_pick.R:97-98. **Round 3's Finding 1 was fixed for the record check only; the pick still matches the range's files against the map at `until`, and the map's own edits inside `since..until` are in no changed set.**
  - `data-raw/pretest_inputs.csv` is not under `PRETEST_LINK_PATHS`, so a commit in the range that edits `inst/extdata/configs/default/rules.yaml` and relabels its row `none` (or from `segments` to an input that picks other groups) shows the file as `none` and picks nothing for it. The gate records a pass at `until`; the record check's rules diff starts at `rec$link_sha` = `until`, so it sees nothing. `pretest_none_reached()` covers this only for a link `R/` file the static graph reaches.
  - Round 3 named both halves ("The pick has the same blind spot for a relabel inside since..until"); commit 2f7d39fc's fix list does not mention the pick.
  - Fix: where `git show <since>:data-raw/pretest_inputs.csv` exists, match the changed files against both maps and take the union of inputs (an input in either map is picked; `none` holds only if both say so).

3. **[severity: fragile]** data-raw/pretest.R:48-50. **`PRETEST_RULES` lists the map, the queries and `pretest.R`, but not the scripts that pick, model and judge: `pretest_pick.R`, `pretest_run.sh`, `pretest_verdict.R` (and `pretest_check.R`).**
  - A record certifies a pick made by `pretest_pick.R` (the median fill, the fresh-`none` refusal, the reach refusal, the cover check), modelled by `pretest_run.sh` (the env it gives `wsg_run_one.R`, the busy refusal, the watchdog) and judged by `pretest_verdict.R` (one SHA, no NA SHA, equal to the range end). A fix to any of them leaves a record made under the old rule clearing runs, which is the mechanism the rules diff exists to close. Round 3's own fixes to `pretest_run.sh` and `pretest_verdict.R` voided older records only because the same commit also touched `pretest.R`.
  - Fix: `PRETEST_RULES <- c(":(glob)data-raw/pretest*", "data-raw/pretest/")`, or name each script. The test at test-pretest.R:311-314 then needs a case per script.

4. **[severity: fragile]** data-raw/pretest_pick.R:101-105 with data-raw/logs/pretest_372/reach_fresh.R:6,14. **The remedy the fresh-`none` refusal prints cannot do what it says.**
  - The refusal says "re-run data-raw/logs/pretest_372/reach_fresh.R at <fresh_to>". That script hard-codes `pkgload::load_all(file.path(sp, "fresh044"))`, so it judges whatever sits in `<dir>/fresh044`, and it carries its own hand copy of the entries (line 6), the stand-in round 3's Finding 2 removed from `pretest.R`. A link call added to `wsg_run_one.R` reaches fresh through a function the re-judge never walks, so a fresh file it reaches can be re-labelled `none` on the re-run's word.
  - Fix: have `reach_fresh.R` take the fresh worktree path as its argument and take its entries from `pretest_entries()` (and walk with `pretest_reach()`), so the re-judge reads the same stand-ins the gate does.

5. **[severity: fragile]** data-raw/pretest_run.sh:226-230. **The per-group "most other sessions seen" resets after a sample that could not tell.** `[ "$o" -le "$others" ] || others=$o` treats -1 as a value, so after `others=-1` any later sample replaces it. Measured on samples `5, -1, 0`: the group reports 0. The verdict then leaves the group out of the "other sessions active" note (pretest_verdict.R:78), which round 3 added so that a breach under load is not read as a regression. Informational only (it never moves the verdict). Fix: keep the max and a separate "unknown" flag (`[ "$o" -ge 0 ] || unk=1`) and write both.

6. **[severity: fragile]** data-raw/pretest_inputs.csv (`link,^DESCRIPTION$,none,"...the rest is metadata"`) with data-raw/pretest.R:409-447. **The `DESCRIPTION` row is a judgement that is false beyond the fresh pin, and nothing records installed dependencies other than fresh.** `crate` is called on every group (`lnk_load_overrides()` → `crate::crt_ingest()`), and `DBI`/`RPostgres`/`yaml` likewise; an `Imports:` floor or a `Remotes: NewGraphEnvironment/crate` change maps `none`, and an upgrade of any of them installed between the gate and the run changes no diff and no recorded SHA. This is A5 one package over; A5 as accepted covers fresh only, and the record check compares the installed fresh exactly for this reason. Fix: either record and compare the installed `crate` (as `fresh_sha`), or accept it in RUNBOOK §8d's "What it does not cover" and correct the row's `why`.

7. **[severity: fragile, latent]** data-raw/pretest.R:270-295. **The reach walks functions only, so a non-function object (a `cols_*` vector, a lookup table) used on the modelling path is never on it.** Such objects carry no srcref, so a changed `none` file holding one reads as off the path at the pick and at the record check. 0 today (the 26 link `R/` files mapped `none` define only functions). The documented limit names calls built at run time, not constants. Fix: in `pretest_reach_repo()`, refuse when a file mapped `none` defines a top-level non-function binding (parse the file, as the probe above does), or note the limit beside the other in RUNBOOK §8d.

8. **[severity: fragile, latent]** data-raw/pretest_run.sh:213-219 against data-raw/study_area_run.sh:1951-1953. **The gate's invocation of `wsg_run_one.R` is a copy of the dispatcher leg's, and the leg's file is outside `PRETEST_LINK_PATHS`.** They agree today (`LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0`, a `PGOPTIONS` statement bound). A driver change to the leg's environment (a new knob `wsg_run_one.R` reads) is in no changed set, and the gate keeps modelling the old way. Fix: name `data-raw/study_area_run.sh` in `PRETEST_LINK_PATHS` with its own map row (an input of `any`), or hold the leg's environment in one place both source.

9. **[severity: fragile]** data-raw/pretest_run.sh:149-151,155. **The start-time busy check excludes `application_name LIKE 'pretest\_%'`, which at start can only be another gate.** The exclusion is there for the per-group sample, where the gate's own group runs as `pretest_<WSG>`. At start the gate has no session of its own (psql's is excluded by pid), so the filter hides exactly a second gate. Under the same config the second gate then `DROP SCHEMA fresh_pretest_<config> CASCADE` under the first, and the first's later writes land in the second's new schema by name. The `live` check catches the first gate only while one of its statements is running on a `working_` schema. Fix: at start, drop the `pretest_%` exclusion (or exclude only the gate's own pid); in the per-group sample exclude only `pretest_${wsg}`.

Not findings (checked):

- Round 3's four findings, against 2f7d39fc: Finding 1 is fixed for the record check (`PRETEST_RULES` diff, test at test-pretest.R:311-314) and open for the pick (Finding 2 above). Finding 2 is fixed: entries come from `wsg_run_one.R`'s parse data, a missing floor entry stops, and both use sites go through `pretest_reach_repo()`, which errors on a missing srcref or a pipeline-less reach. Finding 3 is fixed: `history_dirty` reaches `pretest_since_covers()` from the pick (`built$link_dirty`) and the check (`hist$link_dirty`), and dirty, NA-dirty and empty history refuse. Finding 4 is fixed in the pick (refusal unless `fresh_to` is `PRETEST_FRESH_JUDGED`); its remedy is Finding 4 above.
- The scratch-row NA SHA (round 3's latent `na.omit` in the verdict) now fails at :91 and :116.
- `--fresh-sha=""` (an unresolved fresh) cannot clear: the driver already fails at :1134, and `identical(rec$fresh_sha, "")` is FALSE.
- A gate that crashes before its INSERT leaves the previous record, which is still judged against HEAD on its own SHA: not a pass by default.
- RUNBOOK §8d still describes the start check as "any session active on the persist schema or a `working_` schema" and does not name `--allow-busy`, the rules-diff void or `PRETEST_FRESH_JUDGED`'s refusal; documentation only.
