# Code review, round 1 (#476)

Branch head `9fe0eff4`, diff against `15ca442e` (origin/main), read in the rev1 worktree.

## Checklist read

- **code-check.md**: the prose of every H3 under `## Mechanisms` (14, table rows skipped), read in full for "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "Verification that reads its own output", "One fact derived twice" and "A fix lands in one of two callers that share a harness", skimmed for the rest. Under "Rules that stand alone" none applied beyond those (0 of the stand-alone headings read in full).
- **code-check-r.md**: read "A `data-raw/` script must load the source tree, not the installed package", "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "A `function(...)` mock hides arguments the real callee no longer accepts", "`expect_gt()` and friends take no `info` argument". About 130 headings not read (no tool or shape in the diff they name).
- **code-check-shell.md**: none read; the diff has no shell code. 0 of about 110 read.
- **code-check-spatial.md**: none read; the diff has no spatial code. 0 of about 140 read.

## What was checked, by running it

- `.lnk_species_residence()`: `default` and `bcfishpass` `residence` / `rear_no_fw` columns give exactly the pre-#189 sets (CH CM CO PK SK ST anadromous, CM PK spawn-only, rest resident); `default_tuned` / `_minimal` / `_parent` inherit `default`'s `dimensions.csv`; `default_extrabreaks` / `_rearbreaks` lack the column and take the fallback. Set membership equals the old `union(intersect(bt,wct), setdiff(...))`; only order differs, and `.lnk_mapping_code_persist()` inserts by explicit column name, so persisted column order cannot move. Active species are a subset of rules species, which are a subset of `dimensions.csv` rows, so the "no row" stop cannot fire on a shipped bundle.
- `wsg_recompute_one.R` has `cfg` in scope (line 61) before the `.mc_persist(..., cfg = cfg)` call; `getFromNamespace` resolves the loaded namespace.
- `log_variant_pass()`: every global it reads (`conn`, `head_sha`, `dirty`, `cfgs`, `base_variant`, `schema_of`) exists in the build process, which is the only process that calls `record_pass()`; the variant schema's `log` table exists (`lnk_persist_init()` calls `.lnk_log_create_tables()`); every NOT NULL column of `log` (`run_id`, `watershed_group_code`, `date_start`) is filled; the validator's config-name check compares against the same `config.yaml` the score script loads.
- Provenance checksums in both `config.yaml` files match `shasum -a 256` of the edited `dimensions.csv`; `rules.yaml` bodies unchanged.
- `inst/extdata/configs/README.md` is not excluded by `.Rbuildignore`, so the render test sees it under `R CMD check`.
- `pretest_inputs.csv` maps the new R file and README; `test-pretest.R` passes (160 pass, 2 skip).
- Tests run with `NOT_CRAN=true`: test-lnk_mapping_code (12 pass), test-lnk_rules_build (363), test-dictionaries (173), test-lnk_log (344), test-lnk_pipeline_run (37): 0 failures, 0 errors.
- `lnk_rules_build()` examples run (`devtools::run_examples(start = "lnk_rules_build")`); `data-raw/audit_configs.R` reports no findings.
- `expect_no_error(..., message = b)` in "every shipped dimensions.csv passes strict" uses `message` as a matcher, not a label; probed: a non-matching error propagates and the test still fails, so it is not vacuous.

## Clean

No issues found.
