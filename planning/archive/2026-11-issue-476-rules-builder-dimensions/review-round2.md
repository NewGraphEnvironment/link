# Code-check round 2 (#476)

Reviewed the branch diff against origin/main (15ca442e) in the reviewer's worktree at
`9fe0eff4`. Nothing edited in either tree; `git status` clean in rev1 after every probe.

## Checklist read

- **code-check.md**: every H3 under `## Mechanisms` read in prose (A guard that fails
  toward pass; A fixture that cannot reach the failure mode; A proxy is not the property;
  Verification that reads its own output; A guard's scope, escape hatches, and remedies;
  A fix lands in one of two callers that share a harness; Restore the bug and prove the
  guard fires; A shared working tree, and what generators leave in it; A wrapper's exit
  is not the work; Zero-length, empty, and unset are three different things; The probe is
  broken before the world is; Written data outlives the fix; Serialization loses meaning
  silently; One fact derived twice). Standalone rules: none matched the diff's shapes
  beyond the index line; 0 bodies read.
- **code-check-r.md**: read in full: "Under `R CMD check`, tests run from a temp dir
  against the INSTALLED package"; "as.POSIXct on character infers ONE format for the whole
  vector"; "A `function(...)` mock hides arguments the real callee no longer accepts";
  "`deparse()` re-encodes non-ASCII, so it answers about itself rather than the file";
  "`ifelse()` with an all-NA test returns a logical vector, whatever `yes` and `no` are";
  "Inserting a helper between a roxygen block and its function rebinds `@export`";
  "Cross-function consistency for label/string normalization". About 180 headings not read
  (index lines only).
- **code-check-shell.md**: no shell changed in the diff; 0 bodies read (index only).
- **code-check-spatial.md**: nothing spatial in the diff; 0 bodies read (index only).

## What was checked and held

- Tests run with `NOT_CRAN=true` on the branch: test-dictionaries (31), test-lnk_rules_build
  (73), test-lnk_mapping_code (4), test-lnk_log (107), test-lnk_config (38), test-pretest
  (36, 2 skips): 0 failed, 0 errors.
- `lnk_rules_build` examples run (`devtools::run_examples(start = "lnk_rules_build")`).
- `tools:::.check_package_ASCII_code(".", FALSE)` is empty; NAMESPACE untouched (the new
  helper sits after `.lnk_mapping_code_persist` with `@noRd`).
- Every reader of dimensions.csv: `lnk_rules_build` (dictionary check; `residence` listed),
  `log_dimensions` (DDL from the dictionary; `ADD COLUMN IF NOT EXISTS residence` pinned),
  `lnk_vocabulary.R` (reads no dimensions, so no token moves), the variants harness (reads
  with `colClasses = "character"`, `na.strings = character(0)`, writes back with `na = ""`;
  `residence` rides through), `habitat_variants_score.R`, `audit_configs.R` (no column
  check on dimensions), `regen_provenance.R`, `rule_flexibility_demo.R`. None breaks on the
  new column. `default_tuned`, `default_parent`, `default_minimal` inherit `default`'s
  dimensions path; `default_extrabreaks` / `default_rearbreaks` have no `residence` and fall
  back.
- `.lnk_species_residence()`: the fallback equals the old persist sets as sets (order
  differs; `lnk_mapping_code` persists by column name, so order does not reach output). A
  BOM or a missing `species` column fails loud ("species with no row"); `""`, `"NA"` or an
  unknown value for an active species stops; whitespace and case are trimmed.
- Both mapping-code callers that persist (`lnk_pipeline_run`, `wsg_recompute_one.R`) pass
  `cfg`; no other caller of `.lnk_mapping_code_persist` outside old log scripts.
- `log_variant_pass()`: `format(..., "%Y-%m-%d %H:%M:%OS3%z")` carries the offset, so the
  `::timestamptz` cast is the right instant; called only for non-base passes that returned
  without error; the variant schema's `log` exists (`lnk_persist_init` runs
  `.lnk_log_create_tables`). `backfill_log.R` parses `built_at` per row as UTC-7
  (`Etc/GMT+7` is UTC-7) and refuses any row not stamped `MST`.
- NEWS 0.92.0, RUNBOOK §7 rows and the CLAUDE.md status block match the code on every claim
  checked (strict warning/error, residence fallback, exported functions still on
  bcfishpass's sets, sample byte-copy and body equality, `config_hash` moving for `default`,
  `bcfishpass` and the bundles inheriting `default`'s dimensions).

## Findings

- **[severity: fragile]** tests/testthat/test-dictionaries.R:333-338 with R/lnk_dictionary_readme.R:118 — the staleness test fails in any non-UTF-8 locale although the README is current. `readLines(..., encoding = "UTF-8")` marks the shipped text UTF-8, while `.lnk_dictionary_readme()` reads the dictionaries with `utils::read.csv()` and no encoding, so in a C/POSIX locale the rendered strings are marked `unknown`. The README carries three em dashes (from `dictionary_dimensions.csv` rows 22, 23, 30), and `identical()` treats the same bytes under different marks as different. Reproduced: under `LC_ALL=C`, `identical(shipped, rendered)` is FALSE, `identical(charToRaw(shipped), charToRaw(rendered))` is TRUE, 3 of 179 lines differ. Under `en_US.UTF-8` it is TRUE. An `R CMD check` or CI leg run with `LANG=C` fails the suite on a correct README. Fix: read the dictionaries with `encoding = "UTF-8"` (or `fileEncoding = "UTF-8"`) in the renderer, or compare bytes in the test.
  - **Rule:** none

- **[severity: fragile]** R/lnk_dictionary_readme.R:101-105 (rendered in inst/extdata/configs/README.md, the `rear_near_river` row) — `cell()` escapes only `|` and newlines, so a description holding an HTML-shaped token outside a code span is read as raw HTML. `rear_near_river`'s description reads "(<stage>_river_*, fresh#263)"; CommonMark parses `<stage>` as an open tag and GitHub's sanitizer drops it, so the rendered page reads "(_river_*, fresh#263)". This is the only such token today (checked over the whole README with code spans stripped), so the loss is one word of documentation. The CSV is the source and unaffected; the renderer would carry the next one silently. Fix: escape `<` as `&lt;` in `cell()` (or put the token in backticks in the dictionary).
  - **Rule:** code-check.md "Serialization loses meaning silently"
