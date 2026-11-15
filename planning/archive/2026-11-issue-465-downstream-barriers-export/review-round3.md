# Code-check round 3 (#465): findings

Worktree reviewed: `scratchpad/wt_r3` at `02174b02`. Diff: `git diff 3c0ab0bc...HEAD`
(planning/, data-raw/logs/ and man/ left out).

## Checklist read

- `ALL_INDEX.md` in full.
- `code-check.md`, `## Mechanisms`: the prose of every H3 (tables skipped). Read in full:
  "A guard that fails toward pass", "A guard's scope, escape hatches, and remedies",
  "Zero-length, empty, and unset are three different things". Also "A proxy is not the
  property", "Verification that reads its own output", "A fix lands in one of two callers
  that share a harness", "Restore the bug and prove the guard fires", "Written data
  outlives the fix", "Serialization loses meaning silently" and "One fact derived twice".
- `code-check-r.md`: read the index lines for the R shapes this diff uses (`$`
  partial matching, `paste()` with zero-length input, `[[` on atomic vectors,
  `data.frame()` recycling, `on.exit()`, `data-raw/` loading the source tree, `match()`
  and NA, Postgres row order, `dbWithTransaction`).
- `code-check-shell.md`: read the index lines for the `run_export_hint` shapes (`grep -c`,
  `a && b || c`, `$( )` heredocs). None apply.
- `code-check-spatial.md`: read the index lines for WKB and SRID. The hex WKB round trip
  is accepted.

## Mechanism

Every earlier finding read an absent or unlisted answer as a valid one. In each case the
guard or label took its scope from what the producer happened to list, and the consumer
asked about a wider set. A full provincial build makes the two lists agree, so nothing
showed the gap:

| finding | what the producer listed | what the consumer asks about |
|---|---|---|
| R1 inputs | entries that carry `table` | every input a dependency build read |
| R1 FWA | whatever FWA the database held | every pair a walk reads |
| R2 FWA guard | groups the export holds | every target |
| R2 map coverage | groups that have a map row | every target ("no row" read as "no dependencies") |
| R2 hint | a run that reached the summary | a run whose flags are settled |

Round 3 finds the same mechanism in two more places:

- The class `not_held` is worked out from `<schema>.streams`, but the walk reads
  `<schema>.barriers` and `barrier_overrides`.
- `inputs_differ` is empty both when the inputs agree and when nothing could be compared.

## Enumeration (every place the mechanism reaches)

**Readers of the export's manifest**

1. `lnk_downstream_files()`, `m$dependencies` NULL: refuses (`R/lnk_downstream.R:66`). **Holds.**
2. `d$groups` NULL, or a target outside it: refuses (`R/lnk_downstream.R:70`). **Holds.**
   Tested with a target of `ZZZZ`.
3. A target inside `groups` that has no row in the map reads as "no dependencies"
   (`R/lnk_downstream.R:86-89`). **Holds, at the group grain.** The guard behind it,
   `.lnk_export_fwa_groups()` (`R/lnk_export_groups.R:196`), asks only for at least one
   segment per group. It cannot tell a truncated load of a group from a complete one. That
   check is accepted, so this is not a finding.
4. Config missing from `m$configs`: refuses (`:75`). **Holds.**
5. The map file is fetched and checked against its size and md5 (`.lnk_part_fetch`,
   `R/lnk_db_load.R:156`). **Holds.**
6. Class `exported`: `setequal` against every per-group dataset (`:117`). **Holds.**
7. Class `skipped`, from `entry$skipped[[w]]` (exact `[[`): the loader refuses. **Holds.**
8. Class `not_held` (`:144-147`): **does not hold.** See finding 1.
9. A missing `scope` (a manifest from before #465, carried forward) falls back to
   `"named"`, so the class is `not_exported` and the loader refuses. **Holds** (it fails
   toward refusal).
10. `run_of(w)` NULL: `config_hash` becomes NA, and the loader reports "another bundle".
    **Holds.**
11. `fwa_tmpl` empty: `data.frame()` stops on the differing row counts. **Holds** (loud).
12. `attr(out, "inputs")` → `.lnk_downstream_inputs()` (`:179-200`): a run entry with no
    `inputs` (carried forward from before #465) gives no rows. **Does not hold** (finding 2).

**`lnk_downstream_load()`**

13. Required columns, and one target and config (`:283-294`). **Holds.**
14. `miss` covers `skipped` and `not_exported` only (`:295`). A `not_held` row passes
    unrefused, so this guard is only as good as item 8. **Does not hold**, through
    finding 1.
15. `ex` empty: returns before touching the database (`:303`). **Holds.**
16. Rows built here, or of unknown origin: refuses unless `replace` (`:322-351`).
    **Holds.** This covers only the groups being loaded. A schema keeps rows from an earlier
    load of a group the new files class `not_held`, or `skipped` under `allow_missing`.
    Those rows stay recorded in `log_downstream_load`, so this is not a finding.
17. Columns, row counts (read and written), and group per part, all inside the
    transaction (`:369-398`). **Holds.**
18. Run on a row subset of `files`: R's `[` drops the `manifest` attribute. The log
    insert into a NOT NULL column then fails and the transaction rolls back. **Holds**
    (loud). Such a subset also drops `inputs` silently (finding 2).

**`.lnk_downstream_inputs_compare()` (`:463-508`)**

19. A row with `table` NA (`not read`) is left out on purpose. A `changed since build`
    row carries its table (the round 1 fix). **Holds.**
20. A table absent here: `here` is NA, so the row is reported. **Holds.**
21. No ledger table, or no loader row on this host: `here` is NA, so the row is
    reported. **Holds.**
22. A snapshot row with `content_md5` NA (`no content identity at build`), or a cited row
    with `version_id` NA: compared against nothing, and reported nowhere. **Does not
    hold** (finding 2).

**The export (writer side)**

23. `.lnk_export_dependencies()`. FWA must hold every BC group (246), every exported group
    and every group holding barrier rows (`R/lnk_export_groups.R:220-236`). `groups` is
    recorded. **Holds.** `wsg_regions.csv` is checked against fresh's 246 outlets.
24. `.lnk_wsg_deps_line()` refuses an empty map (`R/lnk_wsg_deps.R:74`). **Holds.**
25. Class source: `held` comes from `<schema>.streams` (`R/lnk_scenario_export.R`, the
    `held <- lapply(configs, ...)` block). The same export lists barrier holders from
    `<schema>.barriers` for the FWA guard. These are two lists that agree only in a full
    build. **Does not hold** (finding 1).
26. `.lnk_export_inputs()`: a missing `artifact_content_md5` column, or a missing
    `log_input` row, becomes `no content identity at build`. A missing `arg_dams` is
    treated as dams read. **Holds** as a record. The silence is on the reader side
    (item 22).
27. `.lnk_manifest_previous_groups()` checks each carried-forward part's md5 on disk.
    **Holds.**
28. `.lnk_manifest_regressions()` compares group pairs. An old manifest with no
    `group_parts` gives the empty set, which is correct. **Holds.**

**Publishing and the run driver**

29. `verify_tree` covers `group_parts`, `dependencies` and `files` (inputs included).
    **Holds.**
30. The pre-write regression check (group pairs included) runs against the live manifest.
    **Holds.**
31. The read-back compares group-part keys and md5s and the dependencies md5. Both NULL
    compare equal, which is correct for a pre-#465 root. Readers then refuse it (item 1).
    **Holds.**
32. Stale deletion is limited to `segment/`, `barriers/` and `barrier_overrides/`
    (accepted). **Holds.**
33. `run_export_hint` (`data-raw/study_area_finish.sh:786-801`) checks `RUN_INCOMPLETE`,
    `RECOMPUTE_FAIL`, `KEPT_CAUSE_N`, `COMPARE_FAIL` and `RECOMPUTE_RAN`. These are set
    before `run_finish_report`, and nothing after the hint changes them. **Holds today.**
    It is a second copy of the INCOMPLETE predicate further down, so a new failure cause
    added there will not reach the hint.
34. `recompute_deps.R` now calls `pkgload::load_all()`. The driver runs it after
    `cd "$REPO_ROOT"`, and link has no `src/`. **Holds.**

## Findings

- **[severity: bug]** `R/lnk_downstream.R:144-147`, with the class source at the
  `held <- lapply(configs, ... FROM %s.streams)` block of `R/lnk_scenario_export.R`.
  - **What is wrong.** Under `scope = "held"`, a dependency with no exported build and no
    skip entry is classed `not_held`, with the reason "the exported schemas held no build
    of it, so no walk read rows of it". `lnk_downstream_load()` loads without it and
    without refusing. But "held" means "has rows in `<schema>.streams`", and the
    provincial walk reads `<schema>.barriers` and `barrier_overrides` by position, not by
    group.
  - **When it happens.** A group can hold barrier or override rows in the exported schema
    with no `streams` rows. This happens when its first build there died after
    `lnk_barriers_unify()` (`R/lnk_pipeline_run.R:260`) and before
    `lnk_pipeline_persist()` (`:283`). It also happens in a schema that received
    `lnk_downstream_load()`, which writes barriers and overrides but no streams. Either
    way the walks in that schema read those rows. The export then tells a one-group
    machine that nothing read them, and the machine's walk misses them silently: wrong
    access, no error.
  - **The export already knew.** `.lnk_export_dependencies()` queries `<schema>.barriers`
    for exactly these groups (`R/lnk_export_groups.R:222-226`).
  - **Proved in the worktree.** I added a KOTL row to the fixture's `barriers`, with no
    `streams` rows, and exported with `wsgs = NULL`. `lnk_downstream_files(p, "ADMS", ...)`
    returned KOTL as class `not_held` with the reason above, while the manifest's
    `dependencies$groups` listed KOTL. The scratch test was removed and the worktree is
    clean.
  - **Fix.** Work out the class from groups that hold rows in the per-group tables of the
    exported schemas, not from `streams`. A dependency holding rows there with no exported
    build is a gap (refused unless `allow_missing`). `not_held` should mean "the schemas
    hold no barrier or override rows of it".
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** `R/lnk_downstream.R:179-200` and `:463-508`.
  - **What is wrong.** The loader cannot tell "the inputs agree" from "no input could be
    compared". A snapshot input whose build recorded no content md5
    (`no content identity at build`), a cited input with no `version_id`, and a run entry
    with no `inputs` all produce no row in `attr(rep, "inputs_differ")` and no message.
    That is the same output as a match.
  - **How often.** Every build before #465 is in this state. Measured read-only on
    `fresh_default`: `log_input` has no `artifact_content_md5` column. Of 241 runs, none
    has an identity for `cabd.dams` or `whse_fish.pscis_assessment_svw`, and all 241 have
    a `version_id` for observations and modelled crossings. So the first real use of the
    loader against today's provincial build compares CABD and PSCIS for no dependency.
    Its silence reads as "the dams these barriers were built from are the dams here".
  - **What this is not about.** Reporting rather than refusing is accepted. The problem
    is that "not compared" never appears.
  - **Fix.** Return a third state: a row per uncompared input with `here`/`built` set to
    `"not recorded"`, or a separate `inputs_uncompared` attribute and message.
  - **Rule:** code-check.md "A guard that fails toward pass"

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
