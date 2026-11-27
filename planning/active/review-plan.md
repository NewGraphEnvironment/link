# Plan review of #477 (Plan agent, 2026-11-27, background beside Phase 1)

Blockers raised: 4
Owner forks: 0

Verdicts after probing (B2, B4 and S1 checked against the code; the rest read against it):

| id | finding | verdict |
|---|---|---|
| B1 | Today's chains end on `!any_anth`, not `TRUE`; a TRUE-fallthrough validator refuses them | accepted: ship row 5 as `NONE,TRUE`; the grid proves it equal |
| B2 | `on.exit` at `lnk_pipeline_run.R:209` exists only under `log = TRUE` | confirmed (`if (isTRUE(log))` at :200): own flag and handler, registered after `lnk_pipeline_setup` |
| B3 | NULL `species_*` inside `lnk_mapping_code()` empties its species set | accepted: one shared resolver at the top of both functions |
| B4 | pretest map rows name the old files; new files unmapped | confirmed (`pretest_inputs.csv:28`, `:76`): rename rows, add rows for the new files |
| G1 | Callers and mocks the rename misses (`lnk_compare_rollup.R`, mocks in `test-lnk_pipeline_run.R`, `test-lnk_compare_rollup.R`) | accepted: named in Phase 3 |
| G2 | One species in both residence sets | accepted: refuse an overlap |
| G3 | `rules` collides with `cfg$rules` | accepted: `rules_mapping_code` |
| G4 | Tokens unchecked | accepted: `^[A-Z][A-Z_]*$`, refuse ACCESS/SPAWN/REAR/INTERMITTENT |
| G5 | Grammar walker details | accepted |
| G6 | Dictionary test's fixed stem list | accepted |
| G7 | No run-log snapshot of the rules | decided: none; `config_hash` and the export's config files are the record (a new log table would need `lnk_persist_init()` on each host) |
| G8 | Drift check before CREATE; unreadable catalog; races | accepted: skip absent tables, leave alone on an unreadable catalog, `ADD COLUMN IF NOT EXISTS` |
| G9 | ADD COLUMN lock under readers | accepted: `SET LOCAL lock_timeout`; an owed item |
| G10 | Extra-column message per group | accepted: once per session |
| G11 | New arguments break positional callers | accepted: appended last |
| G12 | Two read paths for the rules | accepted: one reader, text columns |
| G13 | Package fallback not hashed | written down, not changed: only `default_rearbreaks` / `default_extrabreaks` read it, and both refuse to run |
| O1 | BEFORE and AFTER separated in time | accepted: BEFORE re-run back to back with AFTER in Phase 5 |
| O2 | config_hash settled only if 0.95.0 merges before #479's re-model | accepted: an owed item |
| O3 | Baseline bullet listed last | accepted |
| O4 | lintr compare across renames | accepted: map old to new names |
| A1 | Parity does not test the #351 merge | accepted: a `-9` count check in Phase 5, and the argument in the README |
| A2 | `wsg_compare.R` does not call `lnk_compare_wsg`; `wsgs_run_host.R` is gone | accepted: dropped from Phase 3 |
| A3 | #159 does not reach `wsg_run_one.R` (`cleanup_working = FALSE`) | accepted: say so in NEWS and the close comment |
| A4 | With `cfg`, exported functions code every modelled species | accepted: roxygen |
| S1 | Comments in `default_rearbreaks` / `default_extrabreaks` config.yaml are hashed | confirmed: those two files are left untouched |
| S2 | `.lnk_compare_wsg_*` helpers serve rollup | accepted: rename to `.lnk_compare_rollup_*` |
| S3, S4 | Vocabulary and `extends:` unaffected | noted |
| AC1 | Parity set differs between plan and script | accepted: plan says what the schemas hold (`fresh` has no ADMS, HORS) |
| AC2 | #351 landed in `lnk_pipeline_mapping_code()` (`.lnk_presence_fn`) | accepted: plan text updated |
| AC3 | Grid misses raw-column fallbacks | accepted: a raw-column grid |
| AC4 | Moot or differently met acceptance items | accepted: close comments say so |
| AC5 | README regeneration and dictionary row shape | accepted |

## Files the plan names

R/lnk_pipeline_mapping_code.R
R/lnk_mapping_code.R
R/lnk_access.R
R/lnk_pipeline_run.R
R/lnk_pipeline_persist.R
R/lnk_compare_wsg.R
R/lnk_compare_rollup.R
R/lnk_persist_init.R
data-raw/pretest_inputs.csv
tests/testthat/test-dictionaries.R
