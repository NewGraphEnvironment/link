# Code-check round 2 — branch 479 (#386, #236, #341)

## Checklist read

- **code-check.md**: all 14 H3s under `## Mechanisms`, prose only (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Not read: 24 (the `## Rules that stand alone`, Security and Spreadsheets H3s).
- **code-check-r.md**: Postgres row order is never fixed unless the query fixes it...; An `information_schema` lookup by the literal table name misses what Postgres resolves; `sort()` and `order()` collate by `LC_COLLATE`...; `strsplit()` drops a trailing empty field...; `nzchar(NA)` is TRUE...; A value compared as `::text` in SQL has PostgreSQL's spelling...; `match()` treats NA as a matchable VALUE...; `paste()` with a zero-length argument returns length ONE...; `$` on a list partial-matches... Not read: 123.
- **code-check-shell.md**: psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0. Not read: 74.
- **code-check-spatial.md**: none read (the diff uses no terra/sf/GDAL); 98 not read.

## Round-1 fixes reviewed

All four hold, and none reproduces its defect one axis over:
- blank `observation_species`: overrides, the lift-floor check in `.lnk_lift_rules()` and the habitat path all read blank/NA as the row's own species now (`.lnk_presence_check()` still reads NA as no species, but every shipped NA list sits on a NA threshold, so no lift reads it).
- rule names: `.lnk_lift_rules()` refuses exactly the grammar `lnk_barrier_overrides()` refuses.
- consolidate: `xor()` refuses both directions before step 3.5; a side with no evidence table still copies nothing.
- `pscis_assessment` scope: PSCIS crossings come only from `pscis_assessment_svw` (`.lnk_pipeline_pscis_build`), so a PSCIS-scoped `is_null` row cannot match a crossing with no assessment row; the derived `slope_length` is covered by the same check.

## Findings

- **[severity: fragile]** R/lnk_barriers_unify.R:233 (`.lnk_sql_gradient_held()`), with data-raw/study_area_recompute.sh:81 — a closure (study-area) run into a schema lacking a line-rule dependency outside the closure now silently loses gradient barriers on its own downstream paths, and nothing refuses it.
  - Before 0.93.0 each scanning group held its own copy of every gradient position on its lines. Now only the owner holds it. The RUNBOOK names the hazard for a **one-group** run only (§8c, "What a one-group run needs (link#386)"). But `study_area_wsgs.R` expands focal groups through `lnk_wsg_resolve(expand = TRUE)`, which is `fresh::frs_wsg_drainage()`: the groups a focal group drains **through**. It does not include an owner sitting in the middle of the focal group's own line.
  - The branch's own evidence has cases like this. In `data-raw/logs/barrier_copies_386/before_fresh_default/onegroup_by_holder.csv`, FINA holds 3 copies owned by INGR/MESI/OSPK/UOMI, with 11,733 km of FINA segments upstream. Those are tributary groups FINA does not drain through, so FINA's closure excludes them. USTK holds 23 copies owned by SPAT, a Stikine tributary. Further holders: KHOR, CLRH, COLR, BULL, KOTR, SMAR, PCEA, UNRS, SALR.
  - Run with a FINA or USTK focus into a fresh scratch schema (as the parity and variants builds do), those positions are held by nobody. The access walk reads only persisted barriers, so FINA's segments above them come out accessible, with exit 0.
  - The early recompute scheduler states "A dependency outside the run has landed already" (study_area_recompute.sh:81). It treats an outside-run line-rule dependency as present whether or not the schema holds any of its rows. That is a guard failing toward pass, now on a much larger population than before (copies hid it until this release). `study_area_verify.sql` checks for one holder per position, not that every owner a run group depends on is present.
  - The fix belongs before dispatch: refuse (or expand the run by) any line-rule dependency of a run group that holds no `barriers` rows in the target schema, as `lnk_downstream_files()` already reasons about `barrier_holders`.
  - **Rule:** code-check.md "A guard that fails toward pass"

No other issues found. These were checked and are sound:
- Owner and holder determinism: every `ORDER BY` ends on `linear_feature_id`; `scanners` uses the same scan rule as `streams_blk` (non-6010, modelled groups); classes are bundle-wide, so every scanner finds the same positions.
- Working lifts at a non-owned position equal the owner's: habitat and observations are province-wide, and controls now are too.
- The persist override and evidence filter is identical on both tables, so verify's lift = evidence check still holds.
- The evidence migration and its key.
- The log snapshot tables.
- The barrier-rule SQL: quoting, NULL-only-by-`is_null`, the duplicate-assessment refusal, and the `ctid` UPDATE resetting every row.
- The vocabulary payload, and verify's per-rule threshold and one-holder SQL.
- Cases 6m to 6p of the negative script.
