# Code-check round 3 (#372): diff 22034de5...27a71f63

## Checklist read

- **code-check.md**: I read the index in full. I read the prose (not the `|` table rows) of all 14 `## Mechanisms` H3s: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. I did not read in full the 22 standalone, security and spreadsheet/PDF sections; their index lines ruled them out.
- **code-check-r.md**: I read the index in full (111 headings). I applied the index sentences for `system2(stdout = TRUE)`, `read.delim()` quoting, `on.exit()` at top level, `match()` with NA, `nzchar(NA)`, `ifelse()` all-NA, `information_schema` by literal name, Postgres row order, Rscript reading a running script, and `tryCatch()` nesting. I did not read any section in full (111 not read in full); the index sentences settled each question this diff raises.
- **code-check-shell.md**: I read the index in full (67 headings). I applied the index sentences for a failed `cd`, `wait` on PIDs, psql `:'var'` in dollar quotes, heredoc delimiters, `local` self-reference, and `if ! cmd; rc=$?`. I did not read any section in full (67 not read in full).
- **code-check-spatial.md**: I read the index in full (93 headings). The diff's only spatial content is two `ST_Intersects` count queries, so I read no section in full (93 not read in full).

## Mechanism

Every judgement the gate makes reads a stand-in for the code it is about. The stand-in is either fixed at another time or place (a SHA, a DESCRIPTION pin, a hand-kept list, a call graph frozen at fresh v0.44.0), or it is read from the tree being judged, whose own changes the diff never shows. Where a stand-in comes back missing or empty, the code filters it out (`na.omit`, `intersect`, `%in%`, a loop over an empty set) rather than refusing.

The shared assumption is that "the code that last ran", "the code the gate modelled" and "the code the run will use" are each one link SHA, and that git can derive everything about them from that SHA. That is false in four places, and each is a prior round's bug:

1. fresh is the installed package, not the pin (R1, R2).
2. A dirty build's code is not its SHA (R2 fixed only the NA case).
3. The static reach depends on a hand-kept entry list (R2's fix rests on it).
4. The gate's own rulebook (map, path list, entry list) is read at HEAD, and its edits fall outside every diff (new, this round).

The two lists that happen to agree:

- `PRETEST_ENTRIES` against the `lnk_*` calls in `wsg_run_one.R`.
- `PRETEST_LINK_PATHS` against what a run reads.
- The map at HEAD against the map that judged the gate.
- fresh's `none` rows (judged at v0.44.0) against fresh at the pin.

## Enumeration (every place, pass/refuse direction)

**data-raw/pretest.R**

| place | stand-in or empty case | direction |
|---|---|---|
| `pretest_map_read` :47 | empty pattern/input/why or a bad repo stops; an input typo becomes a query with no `.sql`, and the pick refuses at :169 | refuse |
| `pretest_config_chain` :71 | reads the working tree's `extends:`; a change to it shows as a `config.yaml` change, which maps to `any`/`segments`/… | refuse |
| `pretest_git` :87 | a non-zero exit is an error; stderr goes to a file | refuse |
| `PRETEST_LINK_PATHS` :102 / `pretest_changed_link` :109 | a fixed list stands in for "what a run reads". I checked R/ (all `.R`), `inst/` (only `extdata` is read at run time) and `wsg_run_one.R` (sources nothing). With renames on by default, `--name-only` lists only the new name, which is unmapped and refuses. The list itself is outside the diff (Finding 1). | pass only via Finding 1 |
| `pretest_fresh_pin` :118 | anything other than exactly one pin stops | refuse |
| `pretest_changed_fresh` :131 | identical pins give an empty diff, and the installed fresh is never compared with the pin | pass (accepted, A5) |
| `pretest_match` :145 | `{config}` with an empty chain matches nothing, so the file is unmapped | refuse |
| `pretest_pick` :184 | NA values and groups with no history are dropped (correct); if nothing is left it stops; `any` drops NA minutes | refuse |
| `pretest_bound` :225 | NA minutes stops | refuse |
| `pretest_verdict` :240 | NA exit is `failed`; NA minutes is `no_row` | refuse |
| `pretest_overall` :250 | empty is `fail` (the no-model path bypasses it by design) | refuse |
| `pretest_reach` :259 | `intersect(entries, fns)` silently drops an entry that is not a function. A NULL srcref becomes NA and `na.omit` drops it. An empty or partial reach makes every `none` file read as off-path, and no use site asserts the reach is non-empty (only the test does, at :52). Measured under Rscript today: 40 files, srcrefs present, no entry missing. | **pass** (Finding 2) |
| `pretest_none_reached` :290 | a NULL or empty `reached` returns nothing. It looks only at link `^R/`: link `inst/extdata` `none` rows are a judgement, and fresh `none` rows are frozen at v0.44.0 | **pass** (Finding 4 for fresh) |
| `pretest_history_sql` :302 | filtered by config, finished builds only | n/a |
| `pretest_since_default` :316 | drops NA `link_sha`, which the cover check then refuses; refuses dirty rows, but only on this path | refuse here, pass elsewhere (Finding 3) |
| `pretest_since_covers` :345 | `anyNA` refuses and an unknown SHA errors, but an empty history returns `""` and `link_dirty` is never seen | **pass** on empty or dirty history (Finding 3) |
| `pretest_record_check` :369 | verdict, dirty, NA fresh, fresh identity, ancestry, pin and unmapped all refuse. The `map`, `chain`, `PRETEST_LINK_PATHS` and `PRETEST_ENTRIES` it judges with come from HEAD (Finding 1). `k`, `floor_min` and `per_input` are not read, so a `--k=1000` record clears like any other. | **pass** via Finding 1; the k/floor point is an operator-chosen escape hatch, noted only |

**data-raw/pretest_pick.R**

| place | stand-in or empty case | direction |
|---|---|---|
| :73 explicit `--since` | skips `pretest_since_default`'s dirty refusal | **pass** (Finding 3) |
| :84 cover check | as above | as above |
| :97 map | the working tree at until (= HEAD); a map edit inside the range is not a changed file | **pass** (Finding 1) |
| :100 reach | the working tree; see `pretest_reach` | pass on an empty reach (Finding 2) |
| :149-159 minutes | NA becomes the median; if every value is NA the median is NA and `pretest_bound` stops | refuse |

**data-raw/pretest_run.sh**

| place | stand-in or empty case | direction |
|---|---|---|
| :100 clean tree | checked once, before the pick; skipped on `--pick-only`, which writes no record | refuse |
| :120 until == HEAD | | refuse |
| :128-136 `--only` | the record is always `fail` | refuse |
| :141 busy check | counts only non-idle sessions whose *current* query text names the schema or `working_`. A live run between statements, or a concurrent gate on another persist schema sharing `fresh_pretest_<config>`, reads 0 | pass (a heuristic: timing and scratch collisions, not the record's logic) |
| :186 row regex | | refuse |
| :202-215 watchdog | killed gives 124, which is `bound` | refuse |

**data-raw/pretest_verdict.R**

| place | stand-in or empty case | direction |
|---|---|---|
| :76-77 | `unique(na.omit(rows$link_sha / fresh_sha))`: a scratch row with NA is ignored if the others agree. Latent: every group runs in one environment. | pass (latent) |
| :78 dirty | `any(is.na | TRUE)` | refuse |
| :91-97 no-model path | `link_sha <- range[2]` and `dirty <- FALSE` are hard-coded, standing in for the tree the pick read (the working tree's chain, map and reach). The run's clean check covers only the window up to the pick's start. The fresh SHA is read at verdict time, not pick time. | pass (latent; window of seconds) |
| :105 | a modelled pass needs one link SHA = until, one fresh SHA and clean rows | refuse |

**data-raw/pretest_check.R**

| place | stand-in or empty case | direction |
|---|---|---|
| :264 | `log` absent gives empty history, and `pretest_since_covers` passes vacuously | pass (only after a hand drop of `log` beside a surviving `log_pretest`) |
| :277 | any error gives exit 2, which the driver refuses unless `--pretest-note` | refuse |

**data-raw/study_area_run.sh** :1156-1169: only rc 0 clears; anything else fails the pre-flight or, under a note, proceeds and is recorded. `RUN_SHA` is taken at start on a tree the pre-flight requires clean. Refuse.

**data-raw/pretest_override.sql**: the `override` verdict is filtered out at `pretest_record_check` :373. Refuse.

## Findings

- **[severity: fragile]** data-raw/pretest_check.R:267 with data-raw/pretest.R:102,392-397 (and data-raw/pretest_pick.R:97). **The record check judges what changed since the gate by the rulebook as it stands at HEAD, and edits to the rulebook are outside the diff.**
  - `pretest_inputs.csv`, `PRETEST_LINK_PATHS` and `PRETEST_ENTRIES` are read from the working tree when the run launches.
  - None of `data-raw/pretest_inputs.csv`, `data-raw/pretest.R` or `data-raw/pretest/` is under `PRETEST_LINK_PATHS`, so a commit that relabels a modelling file `none` (or narrows the path list) shows up as no change at all.
  - `pretest_none_reached()` catches this only for a link `R/` file that the static graph reaches. A bundle file (`rules.yaml`, `parameters_fresh.csv`, …), an `inst/extdata` file or `wsg_run_one.R` relabelled `none` and edited in the same post-gate range clears the run.
  - **Probed** (temp repo, the real `pretest_record_check`): `rules.yaml` was mapped `segments` at the gate. After the gate, one commit edits `rules.yaml` and relabels its row `none`. With the map at HEAD, which is what `pretest_check.R` reads, the result is `ok = TRUE`. With the map read at `rec$link_sha` it is `ok = FALSE` ("on the modelling path: inst/extdata/configs/default/rules.yaml"). The diff's changed set holds only `rules.yaml`.
  - The pick has the same blind spot for a relabel inside since..until.
  - Fix: match each changed file against the map at both ends (`git show <rec$link_sha or since>:data-raw/pretest_inputs.csv` and HEAD) and take the union of inputs. Also refuse a record when `data-raw/pretest.R` differs between `rec$link_sha` and HEAD (it holds the path and entry lists).

- **[severity: fragile]** data-raw/pretest.R:43-45,270. **`PRETEST_ENTRIES` is a hand copy of the link functions `wsg_run_one.R` calls. R2's fix (a `none` file the path now reaches counts as moved) rests on it, and nothing ties the two together.**
  - No test or use site compares the list with `wsg_run_one.R`; it matches today (7 of 7). `pretest_reach()` keeps `intersect(entries, fns)`, so an entry that is renamed or missing silently shrinks the walk.
  - Suppose `wsg_run_one.R` gains a call to a `none` function (say `lnk_rollup_wsg()`). The gate that covers that commit models it, because `wsg_run_one.R` maps to `any`. A later commit touching only `R/lnk_rollup_wsg.R` then reads as off-path at the record check, and the run clears with no gate.
  - The test's own control (`test-pretest.R:52`, "the walk must see the pipeline") exists only in the test. Neither `pretest_pick.R:100` nor `pretest_check.R:269` asserts the reach is non-empty, so a load without srcrefs gives an empty reach, and every `none` label is accepted.
  - Fix: derive the entries at use time from `wsg_run_one.R`'s parse data (function-call symbols that are functions in the namespace, plus `link:::` names). Stop when any derived entry is not a function in the namespace. At both use sites, assert that `lnk_pipeline_run.R` is in the reach.

- **[severity: fragile]** data-raw/pretest.R:345-356 with data-raw/pretest_pick.R:73-86 and data-raw/pretest_check.R:268. **A history build from a dirty tree is covered by its SHA alone, everywhere except a defaulted `--since`.**
  - R2 made an NA `link_sha` in history refuse. Its sibling, a SHA whose code was not the commit (`link_dirty` TRUE or NA), still passes in two places: `pretest_since_covers()` on an explicit `--since=`, and `pretest_record_check()` at every launch. `pretest_check.R` passes only `hist$link_sha`, although `pretest_history_sql()` already selects `link_dirty`.
  - A group re-modelled by hand from a dirty tree after the gate therefore cannot void the record, and the uncommitted code it ran is in no diff.
  - Latent: `fresh_default`'s 241 newest rows have 0 dirty and 0 NA SHAs (measured).
  - Fix: pass `link_dirty` into `pretest_since_covers()` and refuse a dirty or NA row as an NA SHA is refused.

- **[severity: fragile]** data-raw/pretest_inputs.csv (the `fresh,…,none` rows) with data-raw/pretest.R:290-296. **fresh's `none` labels are a witness frozen at v0.44.0, which no code re-checks.** R2's fix (a `none` file the path now reaches counts as moved) was applied to link only.
  - Take a fresh release that adds a call from a mapped file into a `none` file (say `frs_network.R`). It is picked for through the caller.
  - The next release, touching only that file, maps entirely to `none`. The gate picks nothing, records a pass with the installed fresh, and the run clears.
  - RUNBOOK §8d leaves this to an operator re-running `reach_fresh.R`, and a human step is not a control.
  - Fix: record in the map (or a constant) the fresh version the `none` rows were judged at, and have the pick refuse when `fresh_to` differs from it and a fresh `none` file is in the changed set.

Not findings (checked):

- Probed: `devtools::test(filter = "pretest")` gives FAIL 0, ERROR 0, PASS 86, and `git status` is clean before and after.
- Probed: `pretest_reach_repo()` under Rscript returns 40 files, with no entry missing.
- R1 and R2 fixes hold:
  - a record with NA fresh refuses;
  - the no-model path records the installed fresh;
  - history is filtered by config;
  - an NA SHA in history refuses;
  - picks.tsv has no empty field;
  - the injection test runs in `r$dir`;
  - `OUT` is absolute.
- Accepted per the brief and not re-raised: the installed fresh against the pin (A5). Here the history's fresh and the pins agree today: `e9793047` = v0.42.0 at `1d00c04c`, and the installed fresh is v0.44.0 = `22034c1a` = HEAD's pin.

