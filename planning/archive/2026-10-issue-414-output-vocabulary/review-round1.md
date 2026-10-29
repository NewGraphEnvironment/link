# Code-check round 1: #414 output vocabulary

Diff: `git diff 24e40f92...e09c60df -- . ':(exclude)planning' ':(exclude)man'`

## Checklist read

- `code-check.md`: the prose of every H3 under `## Mechanisms` (all 14), table rows skipped. Nothing else in the file.
- `code-check-r.md`: "`$` on a list partial-matches", "Cross-function consistency for label/string normalization", "`sort()` and `order()` collate by `LC_COLLATE`", "`Rscript -e` supplies `--args` itself", "`system2(stdout = TRUE)` warns on a non-zero exit", "Under `R CMD check`, tests run from a temp dir", "CSV whitespace", "A `function(...)` mock hides arguments". The rest of the file's roughly 110 headings were not read.
- `code-check-shell.md`: "`if ! cmd; then rc=$?`" and "A failed `git fetch`", from the index line only. None of their full sections and none of the other headings were read.
- `code-check-spatial.md`: no heading applies. Not read.

## Findings

- **[fragile] R/lnk_vocabulary.R:176 (`sort(toupper(cfg$species))`). The acc digest depends on the locale, which contradicts the comment at :196 ("C-locale sorts, so the digest does not depend on the session's collation").** The species list is sorted with the default method, which collates by `LC_COLLATE`. The table and row sorts use `method = "radix"`. Measured: under `LC_ALL=cs_CZ.UTF-8`, `sort()` puts `CH` after `GR`, and `lnk_vocabulary_resolve(lnk_config("default"))` refuses with `no acc token ... sha256:43f4ed92…`. Under en_US it resolves to `acc-v1`. The suite cannot see this, because testthat forces `LC_COLLATE=C`. A host with such a collation would refuse every build, in the pre-flight and per group. Fix: `sort(toupper(cfg$species), method = "radix")`. The digest stays the same on C and en_US hosts, because all the codes are uppercase ASCII.

- **[fragile] R/lnk_vocabulary.R:199-203 (`.lnk_vocabulary_canonical`). The normaliser treats as equal some presence values that the pipeline treats differently, so a presence edit that changes which species are modelled can keep the same acc token.** The canonical form trims whitespace and maps `"TRUE"`/`"True"`/`"t"` all to `"true"`. `lnk_pipeline_species()` → `.lnk_wsg_species_present()` counts a species present only on `identical(x, "t")`. Measured on `default`, ADMS: setting `wsg_species_presence$bt` to `"TRUE"` or to `" t"` drops BT from `lnk_pipeline_species()` (`BT CH CO SK RB` → `CH CO SK RB`), and `.lnk_vocabulary_spec_acc()` returns the identical digest. This is the "Defaults and normalisers" and "proxy" shape: the digest is meant to change whenever the access rules change, and here it fails toward pass. Fix: keep the raw text for character columns, so a value is digested exactly as it was read. Folding `t`/`TRUE` is safe only where every reader of the column folds the same way (`lnk_presence()`'s `.lnk_presence_truthy()` does; `.lnk_wsg_species_present()` does not). The quoting-only and column-order invariance in the test does not depend on the folding.

- **[fragile] R/lnk_vocabulary.R:218-220 (`.lnk_vocabulary_match`). A vocabulary row with an empty `spec` or `axis` resolves every config to an `NA` token, which is logged as NULL.** `vocab$spec == specs[[axis]]` is `NA` for such a row, so `vocab[NA, ]` yields an all-NA row, `is.na(hit$retired)` keeps it, and `nrow(live) == 1` returns `NA_character_`. Measured: a one-row table with `spec` blank returns `c(cut = NA)` for the spec `"anything at all"`. Only the invariant test protects against this, and the runtime reader does not validate the table. One mistyped row added while editing the table, with the test not run (the RUNBOOK's "Adding a token" asks only for a resolve test), turns the refusal into a pass for that axis. Fix: `which(vocab$axis == axis & vocab$spec == specs[[axis]])`, or refuse NA `axis`/`spec`/`token` in `.lnk_vocabulary_read_path()`.

## Checked and found sound

- The spec derivation reads the same effective values as the pipeline: `.lnk_break_order()` is now shared with `lnk_pipeline_break()`; `lnk_pipeline_run()` calls `lnk_pipeline_prepare()` with no `classes` override, so `.lnk_resolve_classes(NULL, cfg)` is what runs; observation_breaks, discharge source and discharge fill go through the pipeline's own helpers; `extends:` merging happens in `lnk_config()` before either reads it. `default_tuned` resolving to `cut-full-top` confirms the inheritance.
- `lnk_pipeline_run()` resolves before `.lnk_log_run_start()` and before any DDL. The refusal test proves it (log start and setup are both mocked and must stay unrun).
- The shell gate: `vocab_out=$(...) && vocab_rc=0 || vocab_rc=$?` is safe under `set -e`; `local` is declared before the assignment; `Rscript -e '…' "$CONFIG"` delivers the config as `commandArgs(TRUE)[1]` (run with both a refusing and a resolving config); the R body contains no single quotes.
- The append-only test, `vocab_append_only()`: handles the NA cases (`is.na(h$retired) | ...`), and fails toward fail when the branch is behind `origin/main`. It skips today because `origin/main` has no table, which is the documented behaviour. A stale local `origin/main` weakens it (a known local-only limitation).
- The tests: `test-lnk_vocabulary.R` (9 run, 1 skip as above), `test-lnk_pipeline_run.R`, `test-lnk_log.R`, `test-lnk_compare_wsg.R` and the `test-study_area_*` files all pass in a worktree at HEAD.
- The acc digest is identical under en_US.UTF-8 and sv_SE.UTF-8 for `default` and `bcfishpass` (it matches `vocabulary.csv`).

## Notes (not findings)

- RUNBOOK "A config with no live token is refused … a bundle loaded by path". A by-path copy of `default` resolves to `cut-full-top / acc-v1 / grad-seg / q-fwapg` (measured). Only a by-path bundle whose specs are new is refused, as with any config. That fits the operator's rule ("refused like any unnamed config"), but the sentence reads as a blanket refusal.
- The shell gate reports "config '$CONFIG' has no output tokens" when `load_all()` or `lnk_config()` itself fails. The fresh gate above it separates harness failure (exit 2) from the real refusal on purpose. The gate still fails closed, and the R error is printed above the line.
