# Code-check round 4 (#401): branch 47bb3dfa...4034aa79

## Checklist read

- **code-check.md:** read in full the prose of all 14 H3s under `## Mechanisms` (table rows skipped).
- **code-check-r.md:** read in full "`on.exit()` at a script's top level never fires", "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one", "`tryCatch(warning = )` DISCARDS the value the expression produced". None is triggered: the drop is an `on.exit()` inside a function (`lnk_pipeline_run()`), wrapped in `try(silent = TRUE)` with no handler that raises.

## Fix commits checked against the code

- `R/lnk_pipeline_run.R:196-205`: the drop is registered with `on.exit(add = TRUE)` after `lnk_pipeline_setup()` and before `lnk_pipeline_load()` / `lnk_pipeline_prepare()`, after the log-fail handler (which therefore runs first). "Dropped on exit (return or error)" holds (an interrupt also unwinds through it). "It stays when R is killed or the DROP itself fails (a lost connection)" holds: `try(..., silent = TRUE)` swallows the failure. No other failure of the DROP is reachable at HEAD: nothing in `R/` creates a view over the table (`grep "CREATE.*VIEW" R/` hits only `lnk_barriers_views.R` and `lnk_persist_init.R`, over persist tables), and fresh v0.48.0's upstream walk creates no temp object (its only temp table is the downstream scoped walk's, of segments).
- `data-raw/wsg_run_one.R:137` passes `cleanup_working = FALSE`, so "wsg_run_one.R keeps its working schema" holds.
- `lnk_pipeline_setup(overwrite = TRUE)` runs `DROP SCHEMA IF EXISTS … CASCADE` then `CREATE SCHEMA`, and prepare rebuilds the table (`.lnk_pipeline_prep_obs_province()` drops and creates it), so "until the group's next run replaces it" holds for a run through `lnk_pipeline_run()`.
- `R/lnk_pipeline_prepare.R:34-38` / `man/lnk_pipeline_prepare.Rd:96-100`: prepare builds `<schema>.observations` (breaks read it; the gate too) and `<schema>.observations_province` (lifts at `:604`, access walk via `lnk_pipeline_run.R:315`), and returns with the latter in place (`:611-613`). "~200 MB": the one copy in the local database (a leftover in `working_dunc`) is 176 MB total. True as an approximation.
- RUNBOOK §2c's on.exit sentences (`:246-249`): true as written.

No defect in the code of either commit.

## Findings

- **[severity: fragile]** `RUNBOOK.md:243-244`, `CLAUDE.md:23`, `data-raw/pretest/obs_upstream.sql:6` — "over every group's records a Fraser main-stem segment in LFRA has about 126,000 above it" / "has about 126,000 records upstream" / "(LFRA's Fraser main stem has about 126,000 above it)" describe the table the access walk reads, but 126,000 is the raw `bcfishobs.observations` count, every species, no presence filter, no exclusions. The walk reads `<schema>.observations_province`, which keeps a record only where its own group's presence row admits the species. Measured read-only on m1 with the pipeline's own `.lnk_pipeline_break_obs_species()` pairs (`default`; `bcfishpass` gives the same): under wscode `100`, 126,371 raw against 79,321 kept; upstream of LFRA's outlet (`obs_upstream.sql`'s own query), 126,143 raw against 79,160 kept, before exclusions. The branch's own evidence agrees: `walk_time.csv` LFRA `pairs_province` is 22,634,909 pairs, about 78,900 per main-stem segment over the README's 287 (126,000 would give about 36 M). The README's source sentence ("126,371 bcfishobs records under wscode `100`", `data-raw/logs/obs_province_401/README.md:46`) is true; the restatements gained a scope it does not have. The same overcount sits in `RUNBOOK.md:1663` ("`obs_upstream` (every group's records upstream of the group's outlet, what the access walk reads since #401)"): the input counts raw records, a third more than the walk reads on the Fraser. As a pick ranking it holds where it matters today (LFRA first either way, then HARR and FRCN), but it reorders below that (THOM 7th raw, 4th kept; LPCE 6th raw, 15th kept). Fix: say "about 79,000" (or "about 126,000 bcfishobs records, 79,000 of them kept by presence") in the three restatements, and either describe `obs_upstream` as raw records or join the presence pairs in the query. Round 2 judged the input a close proxy; this measures the size of the gap.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression runs both ways: a restatement added a scope its source does not carry)

- **[severity: fragile]** `CLAUDE.md:25` — "A temp view depending on a table blocks that table's `DROP` (found dropping `observations_province` in `on.exit()`)": it was not found in an `on.exit()`. `planning/active/findings.md:35` records where: `walk_time.R` stopped at BULK when `.lnk_pipeline_prep_obs_province()`'s own `DROP TABLE IF EXISTS` rebuilt the table for the next group under the measurement script's per-species temp view (`walk_time.R:88-95`). No committed version of `walk_time.R` has an `on.exit()` (`git log --follow`, both commits). As written, the fact reads as the shipped `lnk_pipeline_run()` drop having been seen to fail, which nothing at HEAD can cause (see above). Fix: "(found rebuilding `observations_province` under a measurement script's temp view)".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression adds a claim: an attribution moved to a second place)

## Enumeration

Commands (all at HEAD `4034aa79`, `git -C /Users/airvine/Projects/repo/link`):

```
git grep -n "observations_province" -- ':!planning/archive' ':!*.log' ':!*.csv' ':!*.out'
git grep -c "observations_province" -- ':!planning/archive'          # to see which hits are run logs (outputs, not claims)
git grep -n -i "province table\|200 MB\|drops it\|drop it\|dropping it\|the drop\b\|owns the drop\|kept working schema\|working schema holds" -- ':!planning/archive' ':!*.log' ':!*.csv' ':!*.out' ':!data-raw/logs/study_area_run'
git grep -n "obs_upstream" -- (same exclusions)
grep -n "obs_upstream\|lnk_pipeline_run\|lnk_pipeline_prepare\|lnk_pipeline_access" data-raw/pretest_inputs.csv
git diff 47bb3dfa...HEAD -- R man RUNBOOK.md CLAUDE.md research NEWS.md data-raw/pretest data-raw/pretest_inputs.csv inst tests | grep '^+' | grep -i "cost\|cheap\|dearer\|[0-9] s\b\|10^5\|126\|200 MB\|on exit\|on\.exit\|drop"
git diff 47bb3dfa...HEAD -- research/ | grep '^+' | grep -i "cost\|walk\|drop\|province\|126"
grep -nF "10^5" R/lnk_pipeline_access.R
```

Run logs (`*.log`, `*.out`, `*.csv` under `data-raw/logs/`) are outputs, not claims, and are not judged. Hits about other tables' drops (barriers views, worker partial groups, Docker) are out of scope and omitted.

| file:line | claim | verdict |
|---|---|---|
| `R/lnk_pipeline_run.R:197-198` | prepare builds `observations_province` for the lifts and the access walk below | true |
| `R/lnk_pipeline_run.R:198-199` | dropped on exit (return or error), because `wsg_run_one.R` keeps its working schema | true (`wsg_run_one.R:137`) |
| `R/lnk_pipeline_run.R:199-200` | the copy is ~200 MB per group | true (176 MB measured, one copy) |
| `R/lnk_pipeline_run.R:200-201` | stays when R is killed or the DROP fails (a lost connection), until the group's next run replaces it | true (`try(silent = TRUE)`; setup drops the schema; no dependent object at HEAD) |
| `R/lnk_pipeline_run.R:287-298` | code 2 reads every group's records; breaks read the group's own | true |
| `R/lnk_pipeline_prepare.R:34-38` (and `man/lnk_pipeline_prepare.Rd:96-100`) | prepare writes both tables; lifts and access walk read the province table; prepare leaves it; the caller drops it; `lnk_pipeline_run()` does, on exit | true |
| `R/lnk_pipeline_prepare.R:293-305` | builds the province table, indexed on the ltrees; the access walk reads it; `lnk_pipeline_run()` drops it when the run ends | true |
| `R/lnk_pipeline_prepare.R:596-601` | lifts count over the province table | true (`:604`) |
| `R/lnk_pipeline_prepare.R:611-612` | kept: the access walk reads it, `lnk_pipeline_run()` drops it when the run ends | true |
| `R/lnk_pipeline_access.R:56-67` (and `man/lnk_pipeline_access.Rd`) | the walk scopes segments to `aoi`, not records; `lnk_pipeline_run()` passes the province table; distinct walk costs one element per species, not per record | true (LFRA elements 35,987 vs 3,177,744) |
| `R/lnk_pipeline_access.R:304-312` | a main stem under the Fraser carries ~10^5 segment-record pairs; distinct over every group costs no more than the array over the group's own (LFRA 65 to 37 s, BULK 21 to 8 s) | true (~79,000 is order 10^5; `walk_fresh_distinct.csv`) |
| `R/lnk_pipeline_break.R:22-26`, `:153-156` (and Rd) | code 2 is computed from every group's records (`observations_province`) | true |
| `RUNBOOK.md:196-198` | the access walk reads every group's records itself, not the breaks table | true |
| `RUNBOOK.md:225-231` | `group_gated` / `province`; before #401 both read the group's own records; breaks still read the group's own | true |
| `RUNBOOK.md:240-243` | the array walk returned every pair; distinct walk plus a gate existence walk | true |
| `RUNBOOK.md:243-244` | over every group's records an LFRA main-stem segment has about 126,000 above it | **false** (~79,000 in the walked table; 126,000 is raw bcfishobs; finding 1) |
| `RUNBOOK.md:244-246` | distinct over every group costs less than array over own (LFRA 65 to 37, BULK 21 to 8, SETN 47 to 45 s) | true (`walk_fresh_distinct.csv`: SETN 47.66/46.84 vs 44.28/46.4) |
| `RUNBOOK.md:246-249` | `lnk_pipeline_run()` drops it in `on.exit()`; held after a killed run or failed DROP until the next run replaces it; a direct prepare caller owns the drop | true |
| `RUNBOOK.md:617-623` | since #349 prepare builds it and the lifts count over it; since #401 the access walk reads it; ~4 s per group to build (#349's measurement) | true |
| `RUNBOOK.md:1663-1664` | `obs_upstream` is every group's records upstream of the outlet, what the access walk reads | **false** as a count (raw records, 126,143 vs 79,160 kept for LFRA); ranking top holds (finding 1) |
| `CLAUDE.md:16` | the walk reads `observations_province`; one distinct call plus a gate existence walk; breaks read own records | true |
| `CLAUDE.md:23` | distinct over every group costs less than array over own (LFRA 64–65 → 37–39, BULK 20.5 → 8, SETN 47–48 → 44–46); existence per species 3 to 7 times more | true (`walk_time.csv`: 205/65, 320/48, 55/21) |
| `CLAUDE.md:23` | an LFRA main-stem segment has about 126,000 records upstream | **false** in context (finding 1) |
| `CLAUDE.md:25` | a temp view blocks the DROP, found dropping `observations_province` in `on.exit()` | **false** provenance (finding 2) |
| `CLAUDE.md:153` | before #401 code 2 read only the group's own records; lifts read the province table since #349 | true (historical, marked superseded) |
| `CLAUDE.md:315` | lifts count every group's observations (`observations_province`), #349 | true |
| `NEWS.md:209` | lifts count observations from every group (#349) | true (no #401 entry yet; release bump not made) |
| `research/access_columns.md:80-84` | lifts count over it since #349; since #401 the walk reads it too; dropped when `lnk_pipeline_run()` ends, not after the lifts, so it lives through break, classify and connect | true |
| `data-raw/pretest/obs_upstream.sql:1-10` | counts records upstream of each outlet, every group's; the walk reads `observations_province`; fresh scopes aoi to segments only; `fwa_upstream(…, false, 1)`; no wscode index on bcfishobs; about 40 s | true (only index is the pkey; round 3 timed 36 s) |
| `data-raw/pretest/obs_upstream.sql:6` | LFRA's main stem has about 126,000 above it | **false** in the walk's frame, true of the query's raw count (finding 1) |
| `data-raw/pretest_inputs.csv:23-24`, `:108` | access.R and fresh's `frs_network_features.R` map to `segments` and `obs_upstream` | true (both drive cost) |
| `data-raw/pretest_inputs.csv:13` | `lnk_pipeline_run.R` maps to `any` | accepted (pre-existing convention) |
| `data-raw/logs/obs_province_401/README.md:3-5` | the walk reads `observations_province`, each record kept by its own group's presence, minus exclusions | true |
| `data-raw/logs/obs_province_401/README.md:38-47` | walk timings; existence walks dropped for fresh's distinct mode; LFRA holds 287 Fraser main-stem segments with 126,371 bcfishobs records under wscode `100` | true (126,371 re-measured; 287 consistent with `pairs_province` / 79,000) |
| `data-raw/logs/obs_province_401/README.md:68-70` | `build_obs.R` rebuilt each province table with the pipeline's own helper; each group's slice equals its own table | true (`build_obs.log`, per round 1 and 3) |
| `data-raw/logs/obs_province_401/build_obs.R:6-7` | every run drops its province table, so this rebuilds them | true |
| `data-raw/logs/obs_province_401/walk_time.R:94` | the view depends on the province table, which the next group rebuilds | true |
| `data-raw/overrides_scope_time_349.R:8-10` | #349's timing script over both tables | true (historical) |
| `tests/testthat/test-lnk_pipeline_run.R:174-176` | a run that stops still drops the province copy prepare built | true (the stop is after prepare; drop captured) |
| `tests/testthat/test-lnk_pipeline_run.R:303-311` | dropped when the run ends, after the walk read it (last DROP) | true |
| `tests/testthat/test-lnk_pipeline_prepare.R:1155-1157` | kept by prep_overrides; `lnk_pipeline_run()` drops it when the run ends | true |
| `planning/active/task_plan.md:28-29` | `prep_overrides` drops it after the lifts | true of the base (the plan's problem frame, at `43e34096`) |
| `planning/active/task_plan.md:52`, `:66`, `:75` | dropped when `lnk_pipeline_run()` ends / after access and on the early return | true (on.exit covers both; deviation recorded at `progress.md:10`) |
| `planning/active/progress.md:10` | drop is an `on.exit()`; `DROP TABLE IF EXISTS` on a dropped schema is a NOTICE | true (as recorded; not re-run, read-only here) |
| `planning/active/findings.md:35` | `lnk_pipeline_access()` must drop its own views, or the try()-wrapped drop fails | true as a conditional; at HEAD access makes no views |
| `planning/active/review-*.md` | earlier rounds' findings | not claims about HEAD; rounds 1–3's lifetime findings are fixed as above |

Terminal state: every lifetime claim (when, where, by whom `observations_province` is built, kept or dropped) is true at HEAD. The remaining false sentences are about what the walk's cost depends on (the 126,000 figure, three places plus RUNBOOK §8d's description of `obs_upstream`) and one provenance note in CLAUDE.md.
