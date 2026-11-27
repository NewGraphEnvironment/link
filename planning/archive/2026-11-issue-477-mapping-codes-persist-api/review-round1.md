# Code-check round 1 — link#477 (branch 477-backlog-move-9-mapping-codes-as-rules-an vs 82cf1d08)

## Checklist read

- **code-check.md:** the prose of every H3 under `## Mechanisms` (table rows skipped): "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", and the rest of the section through "One fact derived twice". Of the standalone rules, also "An ordered dispatch makes severity ordering load-bearing, and nothing enforces it" and "Test the cold/create path of idempotent code, not just the warm no-op". About 30 other headings not read (security, spreadsheets/PDFs, URLs, YAML and so on: no shape in this diff).
- **code-check-r.md:** "`ifelse()` with an all-NA test returns a logical vector…", "`$` on a list partial-matches…", "`match()` treats NA as a matchable VALUE…", "`tryCatch()` nests its handlers…", "Inserting a helper between a roxygen block and its function rebinds `@export`", "`on.exit()` at a script's top level never fires", "A database driver's value is not a base R type…", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package". About 150 not read.
- **code-check-shell.md:** none read in full. The only shell change is a comment in `data-raw/cypher_prep.sh`. Index scanned; about 105 headings not read.
- **code-check-spatial.md:** none read (no spatial code in the diff). Index scanned; about 115 headings not read.

## Clean

No issues found.

What I checked, and how:

- **Rules evaluator (`R/lnk_mapping_code_rules.R`).**
  - The grammar walk refuses every name outside the five aliases, every call other than `&`, `|`, `!` and `(`, and every literal other than `TRUE`. A call in function position also fails: `as.character()` returns length > 1, so `&&` errors. Evaluation runs in an environment whose parent is `emptyenv()`. No escape found.
  - An exhaustive check over every TRUE/FALSE/NA combination of the six input columns, with `dam_dnstr_ind` and `remediated_dnstr_ind` each present or absent (3^6 × 4 cases), found 0 mismatches between the shipped rules and the pre-branch resident and anadromous chains.
- **Rules files.**
  - The package copy, `default` and `bcfishpass` are byte-identical: sha256 `9c1c303e…`, which matches the provenance checksums.
  - `lnk_config_verify()` reports no byte or shape drift for `default`, `bcfishpass` or `default_tuned`.
  - `default_tuned` and `default_minimal` resolve `default`'s file through `extends:`.
  - The files are tracked and none is under `.Rbuildignore`.
- **`.lnk_mc_species` / residence.**
  - Explicit sets (including `character(0)`) pass through `%||%` unchanged.
  - With no `cfg`, the defaults equal the old literal defaults.
  - The persisted build still passes the active species' sets explicitly.
- **Presence.**
  - `.lnk_presence_fn` accepts an `lnk_presence` object and a named logical vector. The `is.list()` short-circuit keeps `$` off an atomic vector.
  - The species `lnk_mapping_code()` derives are lower case, and so are the sets they are compared against.
- **Habitat column default.** `ifelse(has_row, 0, NA_real_)`: `has_row` is never NA, so the type stays numeric.
- **`lnk_access(merge = TRUE)`.** The `-9` CASE comes first. A NULL scratch value falls through as before.
- **`lnk_pipeline_run` cleanup.**
  - The drop handler is registered after setup and appended after the log-fail and `observations_province` handlers.
  - `finished` is set before the success-path drop, so a failed drop is not retried.
  - Only `wsg_run_one.R` (FALSE), `habitat_variants_build.R` (non-focal) and `lnk_compare_run` call it with cleanup, so no caller relies on a kept schema after an error.
- **`.lnk_wide_species_align`.**
  - The catalog is read before any lock is taken, so an up-to-date table takes no lock.
  - `ADD COLUMN IF NOT EXISTS` runs under `SET LOCAL lock_timeout` in one transaction, so two concurrent inits converge.
  - The extra-column regex excludes the source flags.
  - The once-per-session environment is mutable inside the locked namespace.
- **Renames.**
  - No live caller of `lnk_compare_wsg`, `lnk_pipeline_persist`, `.lnk_compare_wsg_*` or the removed argument aliases remains outside `data-raw/logs/`, the history docs and the two hashed config comments.
  - No two top-level definitions share a name across `R/`.
  - `devtools::document()` in a worktree leaves `man/` and `NAMESPACE` unchanged.
  - `git diff --name-only` from far ancestors (`4dfbfa49`) lists only the new paths, so the pre-run gate's map rows still match.
- **Tests run** in a detached worktree with `skip_if_no_db()` forced to skip (no DB writes):
  - all pass: rules, mapping code, pipeline mapping code, persist init, pipeline run, access, compare run, persist write, compare rollup, dictionaries, pretest, preflight fresh, vocabulary and config.
  - Worktree removed afterwards.

Index, diff and changed files read from file.
