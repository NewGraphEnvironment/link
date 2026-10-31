## Checklist read

- code-check.md: read the prose of all 14 H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice), table rows skipped. Read from the index only the rest (Rules that stand alone, Security, Spreadsheets and PDFs): about 30 headings not read in full.
- code-check-r.md: read in full "Read-back shape must match write-back shape", "A `data-raw/` script must load the source tree, not the installed package", "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests", "`nzchar(NA)` is TRUE — non-empty checks silently pass NA", "testthat counts an uncaught error under `error`, not `failed`". About 184 headings read from the index only.
- code-check-shell.md: index only (the workflow's shell is `set -euo pipefail`, `$(cat … || echo none)`, `gh … || true`; none of the index's traps matched). All about 100 headings not read in full.
- code-check-spatial.md: index only; nothing spatial in the diff. All headings not read in full.

## Probes run (worktree at HEAD, removed afterwards)

- Loaded the `bcfishpass` presence table at HEAD through `lnk_load_overrides()` and compared it with base `e5899a02`'s CSV read by `read.csv()`: identical names, order and classes, with exactly two differing cells (UTRE `ch`, QUES `st`), as NEWS says.
- `NOT_CRAN=true` test_file on test-lnk_overlay, test-lnk_csv_sync, test-lnk_vocabulary, test-lnk_config, test-pretest, test-lnk_load_overrides, test-lnk_config_verify, test-dictionaries: 0 failed, 0 errors (one skip in test-pretest).
- `lnk_load_overrides()` on bcfishpass, default, default_tuned raises no warnings; the three resolve to acc-bcfp-4 / acc-v3 / acc-v3.
- Counted `canonical_schema` keys in the provenance blocks: 0 of 15 (bcfishpass), 0 of 14 (default).

## Findings

- **[severity: fragile]** data-raw/sync_bcfishpass_csvs.R:195 — the canonical-schema gate never runs. `validate_canonical_schema()` takes its slug from `prov[[rel]]$canonical_schema`, but no provenance entry in either bundle carries that key (0/15 and 0/14 measured); the slug lives under `files: user_habitat_classification: canonical_schema`. So the function returns NULL on every file, `schema_errors` is always empty, and the second of the "belt + suspenders" shape checks the header still advertises (lines 47-51) is dead. Pre-existing (base line 179 reads the same key), carried into the rewritten loop. Consequence: a crate schema failure on `user_habitat_classification` cannot raise `shape` from this check; at best the trial load (`crt_ingest()` inside `.lnk_sync_specs()`) fails and the change is labelled `review` rather than `shape`. Read the slug from `yaml$files[[key]]$canonical_schema` for the entry whose `path` equals `rel`, or drop the claim.
  - **Rule:** code-check.md "A guard that fails toward pass"

Nothing else found. The overlay loader, the config/hash path changes, the trial write and the workflow's `review` arm behave as described.

Not a finding, noted for the merge: `DESCRIPTION` is still 0.73.2 while NEWS heads 0.74.0 and `vocabulary.csv` names 0.74.0 for acc-bcfp-4 and acc-bcfp-3's retirement. task_plan Phase 7 has the bump as an open final commit; per CLAUDE.md it must land in the PR, or `/gh-pr-merge` infers a patch and tags a version the rows do not name.
