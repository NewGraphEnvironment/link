# Code-check round 2 (#465), branch 3c0ab0bc...a06b7852

## Checklist read

- `ALL_INDEX.md`: read in full.
- `code-check.md`: every H3 under `## Mechanisms`, prose only (A guard that fails toward pass;
  A fixture that cannot reach the failure mode; A proxy is not the property; Verification that
  reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two
  callers that share a harness; Restore the bug and prove the guard fires; A shared working tree,
  and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and
  unset are three different things; The probe is broken before the world is; Written data
  outlives the fix; Serialization loses meaning silently; One fact derived twice). Rules that
  stand alone, Security, Spreadsheets: from the index only (about 22 headings not read in full).
- `code-check-r.md`: Postgres row order is never fixed unless the query fixes it; A value
  compared as `::text` in SQL has PostgreSQL's spelling, not R's; plus the index lines for
  `$` partial matching, `[[` on atomic vectors, `data.frame()` recycling, information_schema
  lookups, jsonlite/yaml serialization, `on.exit()` at top level, `data-raw/` load_all,
  duckdb, `tryCatch`. Roughly 150 headings not read in full.
- `code-check-shell.md`: index only (the shell change is four `echo` lines); about 80 not read.
- `code-check-spatial.md`: index only (geometry here is hex WKB through PostGIS, no sf/terra);
  about 95 not read.

Tests run in the worktree, all green: test-lnk_downstream (9), test-lnk_export_groups (8),
test-lnk_export_inputs (4), test-lnk_wsg_deps (3), test-pretest (30, 1 skip),
test-study_area_finish (44), test-lnk_artifact (21), test-lnk_scenario_export (27).
A probe test (added to the worktree, run, removed; the tree is clean) confirmed finding 1.

## Findings

- **[severity: bug]** R/lnk_export_groups.R:206-220 (round 1 fix 2), with R/lnk_downstream.R:81-98 and data-raw/habitat_publish.R:206-212 — the FWA guard on the dependency map checks only the groups this export holds and the groups holding barrier rows in this export's schemas, while the map it guards is published as province-wide and read for any target. The check is one axis narrower than the property:
  - A target the exporting database's FWA lacks has no row in the map, and `lnk_downstream_files()` cannot tell that from a group with no dependency (38 of 246 groups legitimately have none: 2,211 pairs over 208 readers, `line_rule_identity.md`). It returns zero rows and `lnk_downstream_load()` says "no downstream group's rows to load" and proceeds. Probed in the worktree on the test fixture: target `ZZZZ` gives 0 rows and the loader's message; the manifest's `dependencies` entry records no group list (`key,rule,rows,bytes,md5,readers,fwa,computed_by`), so the reader has nothing to check against. A mistyped but well-formed target passes the same way.
  - Groups of configs carried forward from the root's previous manifest are not in `held` (`groups` and `schemas` come only from this export's `runs`/`configs`). An export of config Y from a database whose FWA covers Y's groups replaces the map that config X's readers use, and drops every pair through X's groups the FWA lacks, with no refusal.
  - The fixture shows it: `.lnk_export_fwa_groups` is mocked to 3 groups and the export succeeds, writing a "province-wide" map.
  - PUBLISH replaces the live map unconditionally ("replaced, never write-once") and `.lnk_manifest_regressions()` does not look at it, so a narrower map reaches the bucket.
  - Remedy: refuse unless the FWA holds every BC group (e.g. `fresh::frs_wsg_outlets()$watershed_group_code` or `inst/extdata/wsg_regions.csv`), and record the group list in `dependencies` so `lnk_downstream_files()` refuses a target outside it.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "A guard that fails toward pass" ; code-check.md "Zero-length, empty, and unset are three different things"

- **[severity: fragile]** data-raw/study_area_finish.sh:781-788, 835 — `run_export_hint` prints "republish the habitat export from this run" with the BUILD and `LNK_PUBLISH=1` commands on every run that modelled, including runs the same report then declares `INCOMPLETE`, where it says a failed recompute means "output is silently WRONG". `study_area_run.sh` models with `LNK_HABITAT_GATE=0` and relies on the recompute to settle the flags, and `lnk_scenario_export()` does not refuse a build with no later recompute (`.lnk_export_recompute()` only collects them). An operator who follows the printed commands after a failed recompute publishes unsettled habitat over the live parts, and the regressions check passes it (it is a newer build). Gate the hint on the run's success flags (`RUN_INCOMPLETE`, `RECOMPUTE_FAIL`, `KEPT_CAUSE_N`, `COMPARE_FAIL`), or print it after the INCOMPLETE branch.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

Round 1 fix 1 (`table` carried on `changed since build`, dropped on `not read`) checked one axis over: `no content identity at build` keeps its table with a NULL md5 and cited entries with no ledger row have no version id, so neither is compared, as documented. No defect found there.
