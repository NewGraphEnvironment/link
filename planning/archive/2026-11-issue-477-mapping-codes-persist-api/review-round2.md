# Code-check round 2: link#477 (branch 477-backlog-move-9-mapping-codes-as-rules-an vs 82cf1d08)

## Checklist read

- **code-check.md:** the prose of every H3 under `## Mechanisms`, table rows skipped: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently" and "One fact derived twice". Of the standalone rules, also "Documentation Staleness" and "Test the cold/create path of idempotent code, not just the warm no-op". About 30 others not read: security, spreadsheets and PDFs, URLs, YAML and so on, none of which this diff uses.
- **code-check-r.md:**
  - "`on.exit()` at a script's top level never fires"
  - "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one"
  - "`$` on a list partial-matches, so a longer sibling key answers for a missing one"
  - "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are"
  - "An `information_schema` lookup by the literal table name misses what Postgres resolves"
  - "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"
  - "Inside a dplyr verb, a column named like a local variable wins"
  - "A database driver's value is not a base R type — and it fails twice"
  - "`expect_message(regexp = "...$")` never matches, because `message()` appends `"\n"`"
  - About 150 not read.
- **code-check-shell.md:** none read in full; the index was scanned, about 105 headings. The only shell change is a comment in `data-raw/cypher_prep.sh`.
- **code-check-spatial.md:** none read; the index was scanned, about 115 headings. No spatial code is in the diff.

## Findings

- **[severity: fragile]** CLAUDE.md:1521: the "Pipeline helpers" line for `lnk_pipeline_run()` still ends "comparison is separate (`lnk_compare_rollup`, `lnk_compare_wsg`)".
  - This branch edited that same line, changing `lnk_pipeline_persist` to `lnk_persist_write`, and left the second rename.
  - `lnk_compare_wsg()` no longer exists: it was hard-renamed with no shim. This is the current function reference that every session loads, so an agent following it calls a function that is not there.
  - Change it to `lnk_compare_run`. The history mentions at CLAUDE.md:845, 1415, 1421 and 1423 are dated status or release notes and can stay.
  - **Rule:** code-check.md "Documentation Staleness"

Nothing else found. What I checked, and how:

- **`lnk_pipeline_run()` exit handlers.**
  - **Order.** The handlers are registered in this order: log-fail (under `log = TRUE`), then the `observations_province` drop, then the working-schema drop (only when `cleanup_working` is TRUE). R runs them in that order on error. Each is wrapped in `try()`, so a failure in the log write cannot stop the drops.
  - **Errors before setup.** The working-schema drop is registered after `lnk_pipeline_setup()`, so the vocabulary refusal and the parent judge drop nothing. This is pinned by the test with `fail_in = "setup"`.
  - **Success path.** `finished` is set before the loud `DROP SCHEMA`.
  - **The schema is dropped before the table inside it.** On the success path the `observations_province` drop runs after the schema is gone. `DROP TABLE IF EXISTS` on a missing schema is only a NOTICE, inside `try()`.
  - **Callers.**
    - `wsg_run_one.R` passes `cleanup_working = FALSE`, so the change does not reach it.
    - `habitat_variants_build.R` passes `!w %in% focal`. A non-focal group's working schema is never read after its base run: resume reads `log` only, and the passes read focal schemas only.
    - `lnk_compare_run()` passes the flag through and reads only persist afterwards.
- **`.lnk_wide_species_align()`, run against the local fwapg in scratch schema `zz_review_r2`, now dropped.**
  - A second connection held ACCESS SHARE. The `ALTER` waited 29.99 s, then stopped with the quiet-time message.
  - The same connection then answered a query with no transaction open, and `lock_timeout` was back to 0. So `SET LOCAL` applies inside `dbWithTransaction()` and is rolled back with it, and the connection stays usable.
  - With the lock released, the columns were added. A second call added nothing.
  - The extra column was named once, and the message held no NA.
  - Each transaction touches one table and the loop always takes `streams_access` before `streams_mapping_code`, so concurrent workers cannot deadlock. They serialise, and `ADD COLUMN IF NOT EXISTS` skips the column already added.
  - The session environment's contents can be changed inside the locked namespace.
  - Every caller of `lnk_persist_init()` was checked: `lnk_pipeline_run`, `lnk_downstream_load`, `habitat_variants_build`, `exp_gradient_extra_breaks`, `cypher_prep.sh`, `worker_prep.sh` and the dispatcher init in `study_area_run.sh`. None calls it inside an open transaction. The dispatcher init runs before any leg and is FATAL on failure.
  - Consolidate copies the columns both sides share, by name, so the columns appended by `ALTER` cannot shift positional copies.
- **Mapping-code presence and residence, across every caller.**
  - The callers are `.lnk_mapping_code_persist()` (from `lnk_pipeline_run` and `wsg_recompute_one.R`) and `lnk_mapping_code()` called directly. Nothing in `data-raw/` outside `logs/` calls `lnk_pipeline_mapping_code()` or `lnk_mapping_code()`.
  - The persisted build passes the active species and an `lnk_presence` object. `.lnk_presence_fn()` handles that object, a named logical vector and NULL.
  - `.lnk_mc_species(cfg, …)` reads residence for all of `cfg$species` even when the sets are explicit. For `default`, `bcfishpass`, `default_tuned`, `default_minimal` and `default_parent` it resolves without error (run in a worktree). `cfg$species` comes from rules built from `dimensions.csv`, so every species has a row there.
  - The ADMS presence example in `lnk_pipeline_species()`'s doc reproduces under `bcfishpass`.
- **`lnk_access(merge = TRUE)`.** The `-9` arm comes first. The recompute passes `species = active`, whose cells `lnk_presence()` always counts as present, so no merged column is `-9`. That matches the README and `minus9.csv`.
- **Renames.**
  - No live reference to a removed name is left in `R/`, `data-raw/` outside `logs/`, `.github/`, `_pkgdown.yml` or fresh's tree.
  - Every `.lnk_*` that `data-raw` reaches through `:::`, `getFromNamespace()` or `get()` is defined.
  - `.lnk_compare_rollup_working` is called only from tests. Its predecessor `.lnk_compare_wsg_rollup_link` was also uncalled at the base, so this is not new.
- **Evidence scripts.** `parity.R` and `compare.R` read without fault. Their top-level `on.exit(dbDisconnect)` never fires, but the process exit closes the connection, so nothing is lost.
- **NEWS and RUNBOOK claims.** The rules chain in RUNBOOK §4, the residence row in the §7 table, the §6 gotcha and every NEWS bullet match the code and the shipped CSV.

The worktree was removed, and no `zz_review*` schema is left (counted 0).

Index, diff and changed files read from file.
