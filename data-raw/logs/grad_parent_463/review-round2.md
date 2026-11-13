# Code check, round 2 (#463)

Reviewed `git diff 50a5d58e...HEAD` (planning/ excluded), including round 1's fixes in
`cb1b052a`. Read only; no database, test, Rscript or repo script was run.

## Checklist read

- **code-check.md**: every index heading read. Full prose of all fourteen H3s under
  `## Mechanisms` read, table rows skipped: A guard that fails toward pass; A fixture that
  cannot reach the failure mode; A proxy is not the property; Verification that reads its own
  output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that
  share a harness; Restore the bug and prove the guard fires; A shared working tree, and what
  generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are
  three different things; The probe is broken before the world is; Written data outlives the
  fix; Serialization loses meaning silently (opening only); One fact derived twice (index line
  only). Not read in full: the 14 headings under "Rules that stand alone", 6 under "Security",
  4 under "Spreadsheets and PDFs" (none names a tool or shape this diff uses), and the rest of
  "Serialization loses meaning silently" and "One fact derived twice".
- **code-check-r.md**: every index heading read. Full sections read: "`system2(stdout = TRUE)`
  warns on a non-zero exit instead of raising…"; "Postgres row order is never fixed unless the
  query fixes it…"; "A database driver's value is not a base R type…"; "`$` on a list
  partial-matches…"; "An `information_schema` lookup by the literal table name misses what
  Postgres resolves"; "Rscript reads a script as it runs…". Not read in full: the other
  roughly 120 headings (index lines only).
- **code-check-shell.md**: every index heading read; the index lines of those touching
  run.sh's shapes (`psql`, `grep -c`, a failed `cd`, `&` and `&&` lists, `wait`) checked
  against run.sh; no full section read (about 75 headings).
- **code-check-spatial.md**: every index heading read; "FWA `upstream_route_measure` misses
  the next segment's start" checked against the 1 mm match by its index line; no full section
  read (about 95 headings).

## Round 1's fixes

- The apply's join on `run_id_full`, `run_id_minimal` and `schema_minimal` is correct, and a
  stale parent row now reads as no parent (`n_no_parent`). One input of the same read is still
  not tied to the judgement: see finding 1.
- `want_tok()` with `%in%` fails a NULL token; `nrow(d) > 0` covers an absent schema. Correct.
- `git()` stops on a non-zero `attr(out, "status")`, including git missing (127). Correct.

## Findings

- **[severity: fragile]** R/lnk_gradient_parent.R:371-383 — the apply ties the parent rows to
  the judged run ids, but still reads `<schema_full>.streams` as it is at apply time, minutes
  (a whole prepare and break) after the judgement. If `schema_full` is re-modelled for the group
  in that window (a consolidate or a `default` build into `fresh_default` on the dispatcher)
  and `streams_parent` is not rebuilt, the judged run's parent rows are still there (nothing on
  the modelling path clears them) but their `id_segment`s now name the new build's segments.
  The working network, cut by the current code, matches the new full segments by position, the
  `run_id`-filtered join finds a row for every `id_segment`, `has_parent` is TRUE throughout,
  and every check passes while each segment gets the gradient of whatever old segment carried
  its number. The judge's length check (`overlap_m + straddle_m` against `length_metre`), which
  would catch most of this, is not repeated here. The result is a wrong `gradient`, and wrong
  habitat, with no error. (proof.R catches the case through its notes check; a production
  build does not.) Fix: in the apply, re-read the group's newest `schema_full` log row and
  refuse unless it is still `judged$run_id_full`, or add the judge's length test to the join
  (`abs(p.overlap_m + p.straddle_m - f.length_metre) <= 1e-3` as a condition of `has_parent`).
  This is round 1's mechanism on the other input of the same join.
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "The probe is broken before the world is"

- **[severity: fragile]** data-raw/logs/grad_parent_463/proof.R:257-262 — the class `CASE WHEN
  hc.changed THEN 'own_gradient'` is applied to every flag, `accessible` included. Nothing that
  decides `accessible` reads segment gradient: fresh's classify decides it from the breaks table
  alone, and the gate from `streams_access`, which this proof requires to be identical. So an
  `accessible` difference on a segment whose gradient changed is a defect, and the proof files
  it as explained. The `conn_ok = "false"` arm, which the header describes as "`accessible`
  never moves by connectivity", covers only the unchanged segments. Under `grad-parent` most
  segments change gradient (a minimal parent's gradient is a longer segment's), so the
  `accessible` check is close to vacuous: a parent build whose `accessible` flags were wrong on
  every changed segment would pass. Fix: class every `accessible` difference `unexplained`
  (for example `WHEN %2$s = 'accessible' THEN 'unexplained'` ahead of the `changed` arm).
  - **Rule:** code-check.md "A proxy is not the property" ; code-check.md "A guard that fails toward pass"

Nothing else found. Checked and clean: the judge's
NULL and empty handling (`%in% FALSE`, `anyNA`, `n_rows > 0` guards, the absent table); the
one-to-one mapping counts and the transactional `DROP EXPRESSION` + `UPDATE` with its row-count
check; `.lnk_gradient_parent_cut()` on an unknown or non-parent token; the `$` reads in
`.lnk_gradient_check()` (no prefix-sibling keys); the move of `.lnk_streams_parent_builds()`
and `.lnk_streams_parent_state()` (no reachable reference to R/lnk_streams_parent.R from the
modelling path; `verify_groups()` keeps its old per-group semantics); the csv sync, which loads
only the synced bundle, not its children; run.sh's probe failures and per-build exit status.
