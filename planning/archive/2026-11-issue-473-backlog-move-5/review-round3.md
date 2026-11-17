# Code-check round 3 — #473 (branch 473-backlog-move-5-the-habitat-export-s-cont)

## Checklist read

- code-check.md: read the prose of every H3 under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice; Zero-length, empty, and unset are three different things; plus the index lines of the rest), and Security's "Public bucket" ≠ listable: GetObject vs ListBucket. Not read in full: 25 of 38 H3s.
- code-check-r.md: read `package_version()` errors on a pre-release version string; `$` on a list partial-matches, so a longer sibling key answers for a missing one; `system2(stdout = TRUE)` warns on a non-zero exit instead of raising; jsonlite writes an empty name as the element's position. Index only for the other 118.
- code-check-shell.md: index only (72); the diff's shell surface is unchanged except two `cat(sprintf())` log lines, checked against the drivers' `[wsg_run_one] <WSG> done|SKIP` greps (`study_area_hosts.sh:270`) by hand.
- code-check-spatial.md: index only (94); the spatial change (ST_DWithin prefilter) was ruled "verified earlier, do not re-flag".

Ran, in a detached worktree at HEAD (`de906972`), with `NOT_CRAN=true`: test-lnk_downstream (12), test-lnk_wsg_downstream_check (24), test-lnk_db_load (8), test-lnk_publish (4), test-lnk_streams_md5 (5), test-lnk_scenario_export (27), test-lnk_catalog (5): 0 failures, 0 skips. Worktree removed.

## The mechanism

All six earlier findings share one assumption: **a change to a shared contract (a table's columns, a dependency floor, a database table the code now reads, a manifest field) was written for the state the author's own environment is in, and reached a consumer or environment still in another state** — a table loaded before `access` (R1), a gate map that only knew present paths (R1), a manifest with the dirty flag unrecorded (R1), a modelling host with an older crate (R2), an fwapg without `fwa_watershed_groups_poly` (R2), a reader fetching by key while PUBLISH names versions (R2). The tell is a consumer that is correct for the newest producer and has never met the older, partial or less-privileged one.

## Where the mechanism reaches, and whether each holds

| Changed contract | Consumer / environment | Holds? |
|---|---|---|
| export column `access` | `.lnk_export_conform()`, the segment SQL (`has_code` / `NULL::integer`) | yes |
| | `lnk_db_load()` on an existing older table (ALTER), on an old tree (`.lnk_catalog_cols()` from `datasets`), on a hand-built catalog (whole contract) | yes |
| | `.lnk_manifest_previous()` carrying older-contract parts | yes (refuses, by design) |
| | other repos (knowledge-bayes, peeking, floodplains, stac_floodplains_bc, crate) | no reader of the habitat export found; crate's legacy receipt fixtures quote the old `schema.file` / `contract_md5` as test vectors only (#466 out of scope) |
| crate contract / `.lnk_export_spec()` 0.19.0 check | modelling path (`load_all`, wsg_run_one.R): floor back to 0.0.2, spec not reached (pretest map `none`, call graph) | yes |
| | `lnk_catalog()`, `lnk_downstream_files()`/`_load()` (no spec read) | yes |
| | `lnk_db_load()` (asks after fetching; loud) | yes |
| | test helpers / CI on crate main 0.18.0 | fails until crate 0.19.0 is on main: accepted ordering |
| | `recompute_readers.R` `crate_differs`: a dispatcher upgraded to crate 0.19.0 to export reads every reader built at 0.18 as incompatible | pre-existing design (any crate change), not this branch's defect; worth knowing before the next partial run |
| `log.streams_md5` | existing log tables (`ADD COLUMN IF NOT EXISTS` in `.lnk_log_create_tables`) | yes |
| | consolidate (shared-column COPY, dest brought up first) | yes |
| | `study_area_verify_negative.sh` positional `INSERT … SELECT *` (scratch made `AS SELECT *`, same order) | yes |
| | `.lnk_export_runs()` on an old schema (missing cols filled NA → "no digest") | yes |
| | `lnk_habitat_validate`, `recompute_readers*`, `pretest_history_load.sh` (`LIKE`) | yes |
| guard result (`wsgs_unloaded`, `steps_s`, `elapsed_s`) | wsg_run_one.R (incl. `ignore` mode: empty `steps_s` prints `()`), wsg_recompute_one.R, recompute_readers_check.R (`status == "pass"`), habitat_variants_build.R (`$note`) | yes |
| | host-log greps `\[wsg_run_one\] [A-Z]{4} done` vs the new `… downstream check …` line | yes (no false `done`) |
| guard SQL on `fwa_watershed_groups_poly` | table absent / codes NULL / some codes missing | yes (R2 fix; NULL snaps every dam) |
| manifest `tokens`, `streams_digest`, `crate_version`, `contract_md5` | no reader in link or elsewhere compares them | yes |
| manifest `version_id` | `lnk_catalog()`, `lnk_db_load()`, `lnk_downstream_files()` (parts, dependency map; R2 fix), `lnk_downstream_load()` | yes, **for a reader holding `s3:GetObjectVersion`** — see finding 1 |
| | PUBLISH's local manifest round trip (`fromJSON(simplifyVector = FALSE)` → `write_json(auto_unbox = TRUE)`): length-1 arrays stay arrays (lists), `{}`/`[]` survive, `null` kept | yes |
| | a BUILD after PUBLISH (`.lnk_manifest_previous()` drops `version_id`; PUBLISH re-heads every key) | yes |
| `.lnk_publish_refusals()` | carried-forward configs from older exports (missing fields read as unrecorded → refused) | yes, by design |

Round 2 fixes checked: the `.lnk_export_spec()` version test (`packageVersion("crate") < "0.19.0"`) is a valid `package_version` comparison and runs before the file lookup's message; `.lnk_dams_near_groups()` returns NULL before the query when the table is absent, and its new test would go red without the check (the mocked `FALSE` would otherwise hit the real table and return the codes); `lnk_downstream_files()` carries `version_id` on every row shape (exported, base, empty frame) and into the dependency-map fetch, and its test would go red if the field were dropped.

## Findings

- **[severity: fragile]** R/lnk_db_load.R:193 (`.lnk_part_fetch()`), R/lnk_catalog.R:104-112 (`.lnk_s3_cp()`) and :148-150 (`.lnk_fetch_file()`) — once PUBLISH writes `version_id` into the manifest, every remote part fetch (`lnk_db_load()`, `lnk_downstream_files()`'s dependency map, `lnk_downstream_load()`) asks S3 for a specific version (`s3api get-object --version-id`, `?versionId=`). S3 authorises a request that names a version with `s3:GetObjectVersion`, not `s3:GetObject` (AWS GetObject docs: "If you supply a versionId, you need the s3:GetObjectVersion permission"). The infrastructure's prefix-scoped public-read policy (`public_read_prefixes`, the mechanism #334's remaining item names: "one entry in fresh-bc's `public_read_prefixes`") grants `s3:GetObject` only, and so do its scoped reader users on fresh-bc (checked in the infrastructure repo). So the reader that works today against the 0.82.0 manifest starts failing with AccessDenied / HTTP 403 on every part after the first PUBLISH of this branch, for any reader that is not the operator's admin credentials, and #334's public read will not work as the issue body describes it ("`lnk_catalog()` already reads https"). This is the round's mechanism again: the new field reached readers in an environment (least-privilege or anonymous) the change did not consider. Nothing here fails for the operator today, which is why it is `fragile`, not `bug`. Two ways out, either enough: (a) in `.lnk_part_fetch()`, when the versioned fetch fails with AccessDenied/403, fetch the current object without a version and let the existing size+md5 check decide (the md5 already guarantees the bytes; the version only adds "still readable after a republish"), and say in the error which happened; or (b) record in #334's body and RUNBOOK §6d ("Versions", "Not yet: public read") that the public-read statement and every reader policy must grant `s3:GetObjectVersion` as well, and acceptance-test the https path anonymously with a versioned manifest.
  - **Rule:** code-check.md "\"Public bucket\" ≠ listable: GetObject vs ListBucket" ; code-check.md "A guard's scope, escape hatches, and remedies"

No other real issues found.
