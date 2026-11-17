# Code-check round 2: #473 (branch 473-backlog-move-5-the-habitat-export-s-cont)

## Checklist read

- code-check.md: read the prose (not the `|` table rows) of all 14 H3s under `## Mechanisms`: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice. Rules-that-stand-alone, Security and Spreadsheets sections were read from the index only (about 23 headings), since none of their tools or shapes is in this diff.
- code-check-r.md: read from the index lines only. The headings that apply (`$` partial matching, `system2(stdout = TRUE)` status, the `tryCatch`/`withCallingHandlers` rules, jsonlite NULL/empty-name handling, Postgres row order, `information_schema` lookups) were checked against the code directly. The full-text sections were not opened; about 150 headings not read.
- code-check-shell.md: index only (aws/s3 headings checked against the code); about 110 headings not read.
- code-check-spatial.md: index only (ST_DWithin and the FWA headings checked against the code); about 120 headings not read.

## What round 1's fixes do

1. **lnk_db_load subset check**: correct. A table gains `access` at its end and keeps loading. The round-1 test reloads both an old tree and a new tree into the reordered table. All 31 tests in test-lnk_db_load.R pass.
2. **pretest_inputs.csv row for `^inst/extdata/schemas/`**: restored. The final tree maps it to `none`.
3. **PUBLISH flag**: `!isFALSE(as.logical(x %||% NA))` refuses NULL and NA flags, and also refuses `list()`. Because the refused value is unrecorded rather than dirty, the operator could misread the message, but the refusal itself is correct. On local `fresh_default.log`, all 483 rows record both dirty flags, so the stricter rule does not make real builds cry wolf.

Tests run in a detached worktree at HEAD with NOT_CRAN=true. Results: test-lnk_publish 17 passed, test-lnk_db_load 31, test-lnk_streams_md5 12, test-lnk_scenario_export 183, test-lnk_wsg_downstream_check 59, test-lnk_catalog 16. No failures or errors.

I also ran one extra probe, read-only, on local fwapg under `default` (additions TRUE). 62 of the 246 groups have no downstream group, so the new code returns early for them and also skips the `usa` placeholders. For all 62, the old full probe also finds no dam, so the early return changes no result.

## Findings

- **[severity: bug]** DESCRIPTION:30 (`crate (>= 0.19.0)`), with `Remotes: NewGraphEnvironment/crate` unpinned, and R/lnk_scenario_export.R:463-472 (`.lnk_export_spec_url`)
  - **crate 0.19.0 does not exist upstream yet.**
    - crate's `main` reads `Version: 0.18.0`.
    - No `v0.19.0` tag exists (`git ls-remote --tags` stops at v0.18.0).
    - The YAML is not on crate's `main` (contents API 404).
    - crate PR #72 ("Register link's habitat export as nge/habitat/fwa/v1/segment (0.19.0)") is OPEN.
    - The crate 0.19.0 installed on this machine has no `RemoteSha`. It was installed from a local checkout of that PR's branch.
  - **What this breaks if the branch merges or deploys before crate#72 is merged and tagged:**
    - Every pak install fails to meet the floor: CI R-CMD-check and pkgdown, `cypher_prep.sh`, and a worker's `--auto-install`.
    - `load_all()` refuses an installed dependency below the `Imports:` floor. So `wsg_run_one.R` and `wsg_recompute_one.R`, which run under `load_all()` on every host, would fail to start on any host still at crate 0.18. That stops the modelling run itself, not just the export.
    - The owed list says nothing about reinstalling crate on m1, m4 and the cloud hosts before the next provincial run.
  - **The "released version" guard checks a proxy.** `.lnk_export_spec_url()` refuses only a version string that is not `x.y.z`. The local unreleased 0.19.0 passes it. A BUILD run now would write a manifest citing `blob/v0.19.0/...`, which 404s today and whose content can still change in crate review, and `exported_by.contract_md5` would describe a file no tag holds.
  - **Fix:** merge and tag crate 0.19.0 before this PR, and reinstall crate on every host. Optionally, have the guard check the installed crate's `RemoteSha` or tag rather than only the version's shape.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check-r.md "Two repos pinning the same remote at different tags is an unsolvable install" ; code-check-r.md "`load_all()` refuses an installed dependency below the `Imports:` floor, so measure old-against-new from a frozen worktree"

- **[severity: fragile]** R/lnk_wsg_downstream_check.R:625-633 (`.lnk_dams_near_groups`)
  - The docstring says that where the polygons are absent ("an fwapg without them"), the function returns `NULL` and every dam is snapped "as it always did".
  - That fallback covers missing rows or NULL codes. If `whse_basemapping.fwa_watershed_groups_poly` itself is missing, the `SELECT count(...)` errors instead.
  - The guard reads no other table that the pre-branch guard did not, so this is a new hard dependency. Its failure mode is "the check errors". `wsg_run_one.R` turns that into `quit(status = 1)` on every group, including in `warn` mode.
  - This is exactly the partial or loader-built database #461/#464 target, where the old check ran. The fix is to test `.lnk_table_exists()` first and return `NULL` when the table is absent, matching the documented fallback.
  - **Rule:** code-check.md "A guard that fails toward pass" (its "Which direction it fails" paragraph: the fallback fails toward abort, not toward the documented snap-everything path)

- **[severity: fragile]** R/lnk_downstream.R:81-84 and 91 (`lnk_downstream_files`) against data-raw/habitat_publish.R:472-480
  - PUBLISH now records a `version_id` on every per-group part and on the dependency map, and RUNBOOK §6d says this lets a reader pinned to a manifest read the parts it lists after a republish.
  - Only `lnk_db_load()` uses the version ids. `lnk_downstream_files()` builds its fetch rows without `version_id`, so `.lnk_part_fetch()` always reads the current object.
  - The dependency map is "replaced, never write-once", and per-group parts change with every re-model. So after the next republish, a one-group run pinned to an older manifest stops with "does not match the manifest's size and md5" instead of fetching the version that manifest names.
  - The failure is loud, not wrong data. But the recorded ids for these two kinds of object have no reader, so the pinning #334 adds does not reach the #465 path.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" (the versioned fetch was added to the segment loader, `lnk_db_load()`, but not to the per-group loader, `lnk_downstream_files()`, which shares `.lnk_part_fetch()`)
