# Code-check round 1: branch 469 (#463 parent gradient), diff 50a5d58e...HEAD

Reviewed by reading only. No database, test, Rscript or repo script was run, and nothing in the
tree was changed apart from this file.

## Checklist read

- **code-check.md** (index read in full). Read in full: the prose of all 14 H3s under
  `## Mechanisms` (table rows skipped): "A guard that fails toward pass", "A fixture that cannot
  reach the failure mode", "A proxy is not the property", "Verification that reads its own
  output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that
  share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what
  generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are
  three different things", "The probe is broken before the world is", "Written data outlives the
  fix", "Serialization loses meaning silently", "One fact derived twice". Also read "An assertion
  that matches an interpolated value cannot see the claim around it" and "Documentation
  Staleness". Not read: the other 20 headings (security, spreadsheets/PDFs, YAML booleans, config
  adoption and similar), none of which applies to this diff.
- **code-check-r.md** (index read in full). Read in full: "`on.exit()` at a script's top level
  never fires", "A `data-raw/` script must load the source tree, not the installed package",
  "`$` on a list partial-matches, so a longer sibling key answers for a missing one", "A database
  driver's value is not a base R type — and it fails twice", "A value compared as `::text` in SQL
  has PostgreSQL's spelling, not R's", "`system2(stdout = TRUE)` warns on a non-zero exit instead
  of raising, so a `tryCatch(error =)` around it never fires", "Postgres row order is never fixed
  unless the query fixes it, so a pick, a float sum and a presence check can each depend on it",
  "An `information_schema` lookup by the literal table name misses what Postgres resolves",
  "`nzchar(NA)` is TRUE — non-empty checks silently pass NA", "`paste()` with a zero-length
  argument returns length ONE, not zero", "Rscript reads a script as it runs, so never edit a
  script while a run of it is in flight". Not read: the other 156 headings.
- **code-check-shell.md** (index read in full). Read in full: "Quoting", "Paths", "A failed `cd`
  lets every later command run in the directory you were already in", "psql does not interpolate
  `:'var'` inside a dollar-quoted string, and `\quit N` exits 0", "On this Mac `stat` and `date`
  are GNU, so the same flag letter means something else", "A value validated with one numeric
  grammar and consumed with another", "`a && b || c` runs `c` when any step before the `||`
  fails", "Empty arrays under `set -u` on bash 3.2". Not read: the other 68 headings.
- **code-check-spatial.md** (index read in full). Read in full: "FWA `upstream_route_measure`
  misses the next segment's start". Not read: the other 118 headings (terra, sf, GDAL, STAC and
  similar; this diff only compares measures).

## Findings

- **[severity: fragile]** R/lnk_gradient_parent.R:370-378 (`.lnk_gradient_parent_apply()`,
  with the judge at :322-339 and the call sites at R/lnk_pipeline_run.R:185 and :245). The
  judgement that `<schema_full>.streams_parent` rows came from the group's newest full and
  minimal builds runs before the log opens. The apply runs after load, prepare, crossings and
  break, minutes later on large groups, and reads the rows again with
  `LEFT JOIN %1$s.streams_parent p USING (id_segment, watershed_group_code)`. Nothing ties them
  to the judged `run_id_full` / `run_id_minimal`. `has_parent` means only that some row exists
  for that `id_segment`. Suppose `schema_full`'s group is re-modelled, or consolidated in from a
  host, in that window. The repo's own facts say nothing on the modelling path clears
  `streams_parent`, so the old rows stay. The one-to-one position check then compares the
  working segments with the new full segments, and passes when the cuts did not move. Each
  segment then takes `gradient_minimal` from whatever stale row now shares its `id_segment`.
  Each build numbers its own ids, so that row can describe a segment elsewhere on the network.
  The persisted habitat would be classified on wrong gradients, with no error, and the log notes
  would name the judged runs.
  - **Fix:** filter the apply's join on the judged run ids, as in
    `LEFT JOIN ... p ON ... AND p.run_id_full = <judged$run_id_full> AND p.run_id_minimal = <judged$run_id_minimal>`.
    A stale row then reads as no parent and is refused. Or re-read the newest log rows of both
    schemas in the apply and refuse if either moved.
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/logs/grad_parent_463/proof.R:104-110 (`want_tok`). The check
  computes `all(d$token_cut == ... & d$token_acc == ... & d$token_grad == grad & d$token_flow == ...)`
  and its result reaches `stop_on()` through `isTRUE()`. Take a build whose four tokens all match
  except one that is NULL in the log (NA in R). That row's `&` is NA, `all()` returns NA, `!NA`
  is NA and `isTRUE(NA)` is FALSE, so the check passes. A parent row logged with a NULL
  `token_grad` would pass the tokens check meant to prove it is `grad-parent`. The guard fails
  toward pass on the unknown state.
  - **Fix:** `isTRUE(all(... %in% TRUE))`, or compare with `identical()` per column, or add
    `anyNA(d[c("token_cut", "token_acc", "token_grad", "token_flow")])` to the condition.
  - **Rule:** code-check.md "A guard that fails toward pass"

- **[severity: fragile]** data-raw/logs/grad_parent_463/proof.R:83 and :121. The check
  `moved <- git("diff", "--name-only", sha, "HEAD", "--", "R", "inst", "DESCRIPTION")` runs
  through `system2(..., stdout = TRUE)`. When git fails (the builds' `link_sha` is not in this
  checkout's object store, the value is malformed, or the `-C repo` path is wrong), `system2`
  only warns, stdout is empty, and `length(moved) > 0` is FALSE. So "R/, inst/ or DESCRIPTION
  changed between the builds' commit and HEAD" passes exactly when the comparison could not be
  made.
  - **Fix:** check `attr(moved, "status")` and refuse when it is not NULL, or resolve the sha
    first with `git cat-file -e <sha>^{commit}` and refuse on failure.
  - **Rule:** code-check-r.md "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising, so a `tryCatch(error =)` around it never fires" ; code-check.md "A guard that fails toward pass"

## Checked and clean (for the record, not findings)

- **Mapping and swap.** The one-to-one test in the apply (`n_w == n_f`, `n_wid == n_w`,
  `n_fid == n_f`, `n_pairs <= min(n_wid, n_fid)`) does force an exact bijection. Each side's
  1 mm `dm` / `um` tolerance is consistent with the FWA measure rule. `DROP EXPRESSION` and
  `UPDATE` are in one transaction, the row count is checked before commit, and a refusal leaves
  the column generated.
- **Persistence.** The persisted `streams.gradient` is a plain `double precision` in
  `cols_streams`, and `lnk_pipeline_persist()` copies it, so the parent value reaches the
  persisted table as documented. Working `streams` always comes through `frs_col_generate()`
  (`lnk_pipeline_prepare.R:875`), so `DROP EXPRESSION` has a generated column to drop. No later
  step re-cuts the working network.
- **Column types.** `run_id`, `run_id_full` and `run_id_minimal` are all `text`, so the
  `identical()` comparisons against `string_agg(DISTINCT ...)` hold. A second distinct run id
  makes them differ, which is a refusal.
- **Moved helpers.** `.lnk_streams_parent_builds()` and `.lnk_streams_parent_state()` now live
  in a file mapped `any`. `R/lnk_streams_parent.R` (mapped `none`) keeps only
  `cols_streams_parent`, `.lnk_streams_parent_create()` and `lnk_streams_parent()`, none of
  which the modelling path reaches.
- **`verify_groups()`.** It is still driven by `pair` through the `all.x` merges, so the rows
  in its output are unchanged.
- **Vocabulary.** `.lnk_vocabulary_specs()` keeps the axis order and names. The parent-of-parent
  check runs before the recursive spec call, so it cannot recurse. The line references in
  `dictionary_species_modelled.csv` resolve to their tokens at R/lnk_config.R:460/477/484/489.
- **run.sh.** It quotes its variables, guards `cd`, validates `QUIET_MIN`, and fails on a failed
  probe.
