# Code-check round 1: branch 473-backlog-move-5 (0.85.0)

Reviewed `git diff a974f988...HEAD` (planning/ and CLAUDE.md excluded) and the full current files named in the brief.

## Checklist read

- **code-check.md**: the prose of every H3 under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice, the last two skimmed). A shared working tree was not read. The headings under "Rules that stand alone", "Security" and "Spreadsheets and PDFs" were not read (about 20).
- **code-check-r.md**: read `$` on a list partial-matches; A database driver's value is not a base R type; jsonlite writes an empty name; `system2(stdout = TRUE)` warns instead of raising; Postgres row order is never fixed; An `information_schema` lookup by the literal table name. About 140 headings not read.
- **code-check-shell.md**: none read, because the diff changes no shell. About 100 headings not read.
- **code-check-spatial.md**: none read. The diff's spatial SQL is one `ST_DWithin` prefilter, which I checked against the snap SQL directly. About 100 headings not read.

## Verification done

- I ran the six changed or related test files in a detached worktree at HEAD, with `NOT_CRAN=true` and `load_all`: test-lnk_db_load, test-lnk_publish, test-lnk_streams_md5, test-lnk_scenario_export, test-lnk_wsg_downstream_check and test-lnk_catalog. All passed: 0 failed and 0 skipped across 72 expectations. The worktree is removed.
- I reproduced finding 1 by adding a third `lnk_db_load()` to the shipped "tree exported before access" test. It fails with "has other columns than this export".
- I reproduced finding 2 by matching `inst/extdata/schemas/habitat_fwa_v1_segment.yaml` against every link row of `data-raw/pretest_inputs.csv`. No pattern matches it, and `git diff --name-only a974f988 HEAD -- inst/extdata/` lists that path.
- **Checked, and not a finding:**
  - Row-subsetting a catalog keeps its `datasets` attribute (R 4.5), so `lnk_db_load(configs=)` still reads the tree's columns.
  - The 65 m prefilter is sound for the probe. A reported dam is snapped to within 65 m of a stream of a closure group, and that stream lies inside the group's polygon.
  - The note wording is unchanged for the dam-only case.
  - The `step()` closure and the lazy `outlets` force are correct.
  - The JSON round trip of the manifest in PUBLISH is idempotent: same writer settings, digits = NA.
  - `.lnk_log_run_finish` runs after both persists in `lnk_pipeline_run()`, and only the working schema's streams are updated before persist (`lnk_gradient_parent.R`).

## Findings

- **[severity: bug]** `R/lnk_db_load.R:95-108` (with the order check at :99): a table that gains `access` through the new `ALTER TABLE … ADD COLUMN` is refused by every later `lnk_db_load()`.
  - `ADD COLUMN` appends `access` as the table's last physical column. The contract places it between `has_barriers_dnstr` and `accessible_ratio_gradient`.
  - The existence check is `identical(have, names(ddl)[names(ddl) %in% have])`. `have` comes from `SELECT * … LIMIT 0`, so it is in physical order and ends `…, rearing_ratio_gradient, access`. `names(ddl)` in contract order has `access` in the middle.
  - So the very next load, of any tree, stops with "<table> has other columns than this export. A new column contract belongs in a new table". That is exactly the upgrade path NEWS and RUNBOOK §6d promise ("a table loaded before it gains the column").
  - Reproduced: the shipped test's sequence followed by a third load into the same table errors. The shipped test stops after the second load, so it never sees this.
  - Any reader table loaded from the 2026-11-14 tree breaks permanently after its first load at 0.85.0.
  - Fix: compare as a set with a subset check (have ⊆ contract), not by order. `dbAppendTable` inserts by name, so column order does not matter to the load.
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode" ; code-check.md "Written data outlives the fix"

- **[severity: bug]** `data-raw/pretest_inputs.csv` (the removed row `link,^inst/extdata/schemas/,none,…`): the pre-run gate will refuse every record range that spans this release.
  - `pretest_changed_link()` (`data-raw/pretest.R:118`) runs `git diff --name-only <since> <until> -- … inst/extdata/ …` with no `--diff-filter`. So the deleted `inst/extdata/schemas/habitat_fwa_v1_segment.yaml` is listed as a changed file.
  - With its map row gone, `pretest_match()` puts it in `unmapped`. `pretest_check.R` then refuses with "changed since the gate and unmapped: inst/extdata/schemas/habitat_fwa_v1_segment.yaml". `pretest_run.sh` also refuses a range holding an unmapped file.
  - The next provincial run's gate (owed by NEWS, "the pre-run gate runs again") cannot pass from any record older than this commit.
  - Fix: keep the row, or one matching the old path. A row that matches a deleted path is still live while any record predates the deletion.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** `R/lnk_publish.R:26,36-37,47`: the PUBLISH gate passes a build whose dirty flag is unknown.
  - `flag()` is `isTRUE(as.logical(x %||% NA))`, so `link_dirty` / `fresh_dirty` that is NULL or NA in a run row, in a recompute row or in `exported_by` reads as clean.
  - `.lnk_pkg_git_dirty()` returns NA where it cannot read git, for example an installed rather than `load_all`ed link at export, or a run row from a host that could not resolve it. Such a build is published as one "a floodplain item could name and rebuild", which is the claim the gate exists to make.
  - Today's data does not hit this: 0 of 483 `fresh_default.log` rows and 0 of 241 `log_recompute` rows have a NULL dirty flag locally. So this is latent.
  - Fix: refuse an unknown flag ("link_dirty unknown") the same way as TRUE, so `LNK_PUBLISH_ALLOW` must name it.
  - **Rule:** code-check.md "A guard that fails toward pass"
