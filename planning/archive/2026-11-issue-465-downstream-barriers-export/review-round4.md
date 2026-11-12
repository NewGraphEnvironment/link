# Code-check round 4 (#465): enumeration and findings

Worktree reviewed: `scratchpad/wt_r4` at `2b4b041d`. Diff: `git diff 3c0ab0bc...HEAD`
(planning/, data-raw/logs/ and man/ left out), plus round 3's fix diff (`round3_fix.diff`).
Nothing in the worktree was changed; `git status --short` is clean after the probes.

## Checklist read

- `ALL_INDEX.md` in full.
- `code-check.md`, `## Mechanisms`: the prose of every H3, tables skipped. Applied here:
  "A guard that fails toward pass", "A proxy is not the property", "A guard's scope, escape
  hatches, and remedies", "Zero-length, empty, and unset are three different things",
  "One fact derived twice", "Serialization loses meaning silently", "Written data outlives
  the fix", "A fix lands in one of two callers that share a harness".
- `code-check-r.md`, by heading: `$` partial matching, `[[` on a named atomic vector,
  `paste()` with a zero-length argument, `data.frame()` recycling a scalar against a
  zero-length column, `match()` and NA, Postgres row order, `on.exit()` at top level,
  `data-raw/` loading the source tree.
- `code-check-shell.md`, by heading: `a && b || c`, `if ! cmd; then rc=$?`, `grep -c`.
  `run_complete` uses none of the failing shapes.
- `code-check-spatial.md`: hex WKB / SRID lines (accepted).

## What I ran

- `test-lnk_downstream.R` 57 pass, `test-lnk_export_groups.R` 59, `test-lnk_export_inputs.R`
  23, `test-study_area_finish.R` 301; 0 fail, 0 error, 0 skip in each.
- `run_complete` alone in bash: default 0; `RECOMPUTE_FAIL=1` 1; `KEPT_CAUSE_N=2` 1;
  `KEPT_CAUSE_N=x` 2 (the `[` error is now read as incomplete; before the fix a non-numeric
  value read as complete).
- `.lnk_export_barrier_holders()` empty-result shapes in R: both tables empty gives
  `character(0)`, which serialises as `[]` and reads back as `list()`. Both tables absent gives
  `NULL`, and `I(NULL)` errors, but `.lnk_export_group_rows()` stops on the missing table first
  (the group-part loop runs before the config entry is built), so that error is never reached.
- Read-only on `fresh_default`: 0 barrier rows with a NULL group code (the column is NOT NULL);
  the groups holding `barriers` or `barrier_overrides` rows minus the groups in `streams` = 0.
  So on today's provincial build `barrier_holders` and the old streams list agree, and the fix
  changes no class there.
- Read-only on the ledger: one loader row per (host, table), so `here[1]` in the cited
  comparison does not depend on row order today.

## Enumeration (43 places: 43 hold, 0 do not)

Round 3's 34 places, then 9 the round 3 fixes added.

**Readers of the export's manifest (`R/lnk_downstream.R`)**

1. `m$dependencies` NULL: refuses (`:66`). **Holds.**
2. `d$groups` NULL, or the target outside it: refuses (`:70`). **Holds.**
3. A target inside `groups` with no map row reads as no dependencies (`:86-89`). **Holds,
   at the group grain** (accepted).
4. Config missing from `m$configs`: refuses (`:76`). **Holds.**
5. The map is fetched and checked for size and md5 (`:81-83` → `R/lnk_db_load.R:156-181`).
   **Holds.**
6. `exported`: `setequal` against every per-group dataset (`:119`). **Holds.**
7. `skipped`, from `skipped[[w]]` (exact `[[` on a list) (`:142`). **Holds.**
8. `not_held` (`:146-150`): decided from `entry$barrier_holders`, i.e. groups with rows in the
   config's `barriers` or `barrier_overrides`, which is what the walk reads. **Holds now**
   (round 3's finding 1 is fixed, and its test passes).
9. Missing `scope` falls back to `"named"` → `not_exported` → refused (`:101`, `:156`).
   **Holds.**
10. `run_of(w)` NULL → `config_hash` NA → "another bundle" (`:135`). **Holds.**
11. `fwa_tmpl` empty → `data.frame()` stops on 1 against 0 rows (`:98`, `:112`). **Holds**
    (loud).
12. A run entry with no `inputs` (`:178`, `:187-208`) → the compare names the group under
    "(every input)", state `not compared` (`:490-496`). **Holds now** (round 3's finding 2).

**`lnk_downstream_load()`**

13. Required columns, one target and one config (`:293-304`). **Holds.**
14. `miss` covers `skipped` and `not_exported` (`:305`). `not_held` passing is right now
    that item 8 holds. **Holds.**
15. `ex` empty returns before touching the database (`:313`). **Holds.**
16. Rows built here, or of unknown origin, refused unless `replace` (`:331-361`). **Holds**
    (the residual for groups outside `ex` is the one round 3 accepted).
17. Columns, rows read and written, and group per part, all inside the transaction
    (`:368-431`). **Holds.**
18. A row subset made with base `[` drops `manifest`, and the NOT NULL log insert rolls back
    (`:427`). **Holds** (loud). Had it reached the compare, its NULL `inputs` would be named
    as not compared (`:488-496`). A subset made with dplyr keeps the attributes.

**`.lnk_downstream_inputs_compare()`**

19. A `not read` row (table NA) is left out (`:498`). **Holds.**
20. A table absent here: `.lnk_table_content_md5()` returns NA, reported as differs
    (`:520-528`). **Holds.**
21. No ledger table, or no loader row on this host → `here` NA → differs (`:500-507`,
    `:532-541`). **Holds.**
22. No content md5 and no version id → `not compared`, "no identity recorded at build"
    (`:510-518`). **Holds now.**

**The export (writer)**

23. `.lnk_export_dependencies()` refuses an FWA missing any of the 246 BC groups, any
    exported group or any barrier-holding group (`R/lnk_export_groups.R:236-252`). **Holds.**
24. `.lnk_wsg_deps_line()` refuses an empty map (`R/lnk_wsg_deps.R:74`). **Holds.**
25. Class source: `holders <- .lnk_export_barrier_holders(...)` (`R/lnk_scenario_export.R:932`,
    written at `:1004`; function at `R/lnk_export_groups.R:126-135`), from both per-group
    tables of the config's exported schemas, the same tables the parts are cut from. **Holds
    now.**
26. `.lnk_export_inputs()` records a missing md5 column or `log_input` row as
    `no content identity at build`, and treats a missing or NA `arg_dams` as read
    (`R/lnk_export_inputs.R:101-113`). **Holds.**
27. `.lnk_manifest_previous_groups()` checks each carried-forward part's md5
    (`R/lnk_export_groups.R:168-182`). **Holds.**
28. `.lnk_manifest_regressions()` compares group pairs; an old manifest with none loses
    none (`R/lnk_scenario_export.R:1182`). **Holds.**

**Publishing and the run driver**

29. `verify_tree` covers `parts`, `group_parts`, `files` and `dependencies`
    (`data-raw/habitat_publish.R:75`). **Holds.**
30. The pre-write regression check runs against the live manifest (`:146-160`). **Holds.**
31. The read-back compares group-part keys and md5s and the dependencies md5 (`:241-250`).
    **Holds.**
32. Stale deletion is limited to `segment/`, `barriers/` and `barrier_overrides/` (`:220`;
    accepted). **Holds.**
33. `run_export_hint` and `run_finish_report` now read one predicate, `run_complete()`
    (`data-raw/study_area_finish.sh:788`, read at `:796` and `:878`). `RECOMPUTE_RAN` is the
    hint's own extra. Every flag the INCOMPLETE branch prints a cause for (`RUN_INCOMPLETE`,
    `RECOMPUTE_FAIL`, which `RC_AUDIT` early/unread also set at `:684-686`, `KEPT_CAUSE_N`,
    `COMPARE_FAIL`) is in it. **Holds.**
34. `recompute_deps.R` calls `pkgload::load_all()` (`:71`), run from the repo root. **Holds.**

**Places the round 3 fixes added**

35. Writer, empty holders: `character(0)` → `[]`. When both tables are absent, `NULL`
    would make `I(NULL)` error, but the group-part loop stops on the missing table first.
    **Holds** (loud).
36. Reader, `barrier_holders` absent (a manifest from before the fix) under scope `held`:
    falls through to the last branch, `not_exported` → refused (`:103`, `:146`, `:151`,
    `:156`). **Holds** (fails toward refusal). The reason printed then ("the export named its
    groups") is wrong for a held-scope export. That is text, not a wrong load.
37. Reader, `barrier_holders` `[]` → `list()`, which is not NULL. Every dependency neither
    exported nor skipped is then `not_held`, which is true when nothing holds rows. **Holds.**
38. New middle branch: a holder with no exported build and no skip entry is `not_exported`
    (`:151-155`) and refused at `:305`. **Holds** (tested: "lacks the rows of 1 group").
39. `bare` is decided per group, not per group and input (`:490`). **Holds,** because the
    writer emits all four inputs for every run (`c(snap, cited)`,
    `R/lnk_export_inputs.R:101-152`), so no entry can list only some of them.
40. `none`, an input with neither identity (`:510-518`), covers a cited input with no
    `log_input` row (`url = NULL`, no `version_id`) and a ledger row with a NA version id.
    **Holds.**
41. The loader's messages separate `differs` from `not compared` (`:457-470`), and the
    attribute keeps both states. **Holds.**
42. `run_complete()` read in both places; a non-numeric `KEPT_CAUSE_N` is now incomplete
    (rc 2). **Holds** (safer than before).
43. `.lnk_downstream_inputs(character(0), NULL)`: the NULL `run_of` guard (`:189`) gives
    the typed empty frame `bare` needs. **Holds.**

Two lists that still differ, both bounded:

- The FWA guard's holder list reads `barriers` only (`R/lnk_export_groups.R:237-242`), while
  `barrier_holders` reads both tables. The guard also requires all 246 BC groups, which
  contain every group code an overrides row can carry, so the narrower list cannot let a
  group through.
- `barrier_holders` is the union over every exported schema of a config. Under a config
  spread over several schemas, a dependency holding rows only in a schema the target was not
  built in is classed `not_exported` and refused. That is over-refusal, the safe direction.

## Clean

No defect found in round 3's fixes, and none that repeats the mechanism one axis over.
All 43 places hold.

/Users/airvine/Projects/repo/link/planning/active/review-round4.md
