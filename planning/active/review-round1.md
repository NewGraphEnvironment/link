## Checklist read

- code-check.md: every H3 under `## Mechanisms`, prose without table rows; the stand-alone and security sections by index line only.
- code-check-shell.md: "Over Tailscale SSH to a Mac, `ssh` exits 0 whatever the remote command returned"; "A second `trap … EXIT` replaces the first"; about 110 others by index line only.
- code-check-r.md: "`on.exit()` at a script's top level never fires"; "A `data-raw/` script must load the source tree, not the installed package"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; about 130 others by index line only.
- code-check-spatial.md: no heading names anything this diff uses; 0 read.

## Findings

- **[severity: fragile]** data-raw/pretest_pick.R:89 and data-raw/pretest_check.R:54 (with data-raw/pretest.R:374) — the short-history guard is keyed to the flag `borrowed`, not to the outcome, so one own build turns it off.
  With any finished row under the config in `<schema>.log`, the flags are refused (`own_rows > 0L`), the history becomes that schema's own rows, the pick's `if (hist_src$borrowed)` skips the check, and the launch check's `identical(src$config, config)` skips it too. The gate then picks only among those rows and its pass clears a 241-group launch. This is the 2026-11-01 failure the branch exists to refuse (a 4-group history picked exactly its 4), reached by another door.
  Doors: the single-group command `default_minimal`'s own README prints (`LNK_SCHEMA=fresh_default_minimal Rscript data-raw/wsg_run_one.R ADMS default_minimal`), or a first provincial run that stops after some groups and needs a re-gate after a code change. In that second case the operator cannot borrow any more, so the fuller history is unavailable to the very gate that needs it.
  Reproduced in a temporary worktree at HEAD, schema `zzrev_rec`, with 2 rows copied to `default_minimal` (ADMS, BULK): `pretest_pick.R --pick-only` printed picks BULK and ADMS with no refusal, across 7 inputs. `pretest_check.R` then read a pass record and exited 0 ("gate passed"), against 241 modelable groups. (That pass record was hand-inserted; the check does not look at what it picked, which is the point.)
  The same reach applies to `default` on m4 (`fresh_default` holds 4 groups); that part is pre-existing, and the RUNBOOK's sentence "Once it has any, a gate must cover those" does not say the picks shrink.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/pretest_pick.R:82 and data-raw/study_area_run.sh:1204 (the second not in the diff) — the remedies printed for the state this branch adds do not work.
  On a bundle with no builds, the launch refusal says `Run: bash data-raw/pretest_run.sh --config=default_minimal --schema=fresh_default_minimal`. That command refuses with `fresh_default_minimal.log does not exist: no history`, and neither message names `--history-schema` or `--history-config`. The alternative it offers, `--pretest-note`, ends `FATAL: could not record` on a schema that does not exist yet, and this branch deleted the README sentence saying the schema must exist first. Both stop loud, so no wrong run results; the cost is an operator at launch with no working next step on screen. Note that editing study_area_run.sh voids a gate record (mapped `unexercised`), so do it before the gate.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

## Checked and sound

Run on this branch, scratch schemas dropped afterwards:

- Loader through a stub `ssh` from local `fresh_default` to `zzrev_hist`, load and reload: 8 rows, `log_pkey` and three indexes under the new schema, comment set, exit 0. `log.run_id` is text with no sequence, so a reload is not blocked by a scratch table's default.
- Awk rename: COPY rows skipped, only schema-qualified names changed; a `\.` cannot appear as a data row.
- Scratch `DO` block with a history schema holding only `log`: 1 table, 4 indexes, primary key rebuilt, no error. `lnk_persist_init()` was read, not run; no gate has yet modelled a pick on a history-only scratch schema (the plan's gate phase is the first).
- `pretest_override.sql` on a schema with no `log_pretest`: rc 0, and `pretest_check.R` then exits 2 with the no-history message, as before this branch for a missing `log`. An override row is not read as a record.
- Launch check pass path on a borrowed 241-group history: exit 0, with both `load_all()` calls in one process.
- The newest fail or `--only` record stays read as a failure before anything clears; the pre-column `log_pretest` shape reads as no borrow (test) and is altered by the verdict.
- `mins` reuse in pretest_pick.R:196 when `--minutes-schema` equals the record schema is reachable only by naming a schema with an empty `log`; no effect on the bound beyond using the history's minutes.
