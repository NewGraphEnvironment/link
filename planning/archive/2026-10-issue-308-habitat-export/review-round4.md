# Code-check round 4: #308 habitat export (round-3 fixes, and the mechanism's reach)

Reviewer: subagent, 2026-10-14, HEAD c8518bca. I read these in full: R/lnk_scenario_export.R,
R/lnk_catalog.R, R/lnk_db_load.R, data-raw/habitat_publish.R,
data-raw/logs/habitat_export_308/verify.R, tests/testthat/helper-export.R, round3_fix.patch,
review-round3.md and RUNBOOK §6d. I also read `.lnk_run_id()` and the recompute log writers in
R/lnk_log.R.

**Probes.** One throwaway test file, run from a `cp -r` copy in the scratchpad
(NOT_CRAN=true) against local fwapg. It used the fixture's `lnk_test_export_<pid>` schemas plus
an `_old` sibling. All were dropped by `defer`, and none remain. The copy was then deleted.
Nothing in the repo was edited except this file.

## Enumeration

Round 3's 13 places, re-checked against HEAD, then the places it missed (14 onward).

1. **Per-build `log` / `log_input` files** (:536-547): checked-ok.
   - Unchanged since round 3.
   - `run_id` is host + ms timestamp + random suffix (`.lnk_run_id`), so it is unique per build.
2. **Per-hash `log_parameters_*` from `got[[1]]`** (:548-562): checked-ok. Unchanged.
3. **`log_recompute` files** (:1059-1076): checked-ok. `recompute_id` is `.lnk_run_id()` and the
   table's PK, so there is one row per key.
4. **`source_artifact` snapshot**: checked-ok. It is keyed by content.
5. **Bundle files under `config/sha256-*`**: checked-ok.
6. **`configs[].skipped`** (round-3 fix a; :811-822, :870, :1016-1026):
   - With `wsgs = NULL`: checked-ok. Duplicates are joined as `schema: reason; ...`, groups that
     were exported are dropped, and the keys are uppercase codes.
   - With named `wsgs`: **defect, low** (finding 3).
7. **`thresholds_logged`** (:915-922): checked-ok.
8. **PUBLISH guard** (habitat_publish.R:141-176):
   - Set coverage (round-3 fix b): checked-ok. Pairs are compared per live config, and a missing
     config stops first.
   - Recency is still the exported-time proxy: **DEFECT** (finding 1).
9. **The stop when nothing is exported** (round-3 fix c; :774-810, :295-322): checked-ok.
   - `strict = FALSE` everywhere, and the config-level stop counts rows across the config's schemas.
   - The per-schema message "N of M groups not exported" (:298) is still per schema, and can name
     a group another schema exports. It is only a message.
10. **"Held by more than one schema"** (:828-836): checked-ok.
11. **Carry-forward of other configs' parts, entries and files** (`.lnk_manifest_previous`):
    checked-ok. Each part is md5-checked and `exported` rides along.
    - What is not carried per config is place 15.
12. **`exported` text comparison**: checked-ok. Both sides use one fixed-width UTC format.
13. **verify.R, schema per run**: checked-ok for the pilot.
    - It also summarises the whole `habitat.fwa_v1_segment` table, not this catalog.
    - A config loaded earlier from another root has no `schema_of` row, so
      `lnk_rollup_wsg(schema = character(0))` errors. That is loud, in a pilot script only.
14. **BUILD-side narrow check** (round-3 fix b; :975-993): checked-ok for set coverage.
    - `parts[-1]` holds only this call's parts, and filtering on config isolates each one.
    - It fires before the staging swap, so the manifest and `segment/` are untouched (as the test
      asserts).
    - Provenance and bundle files written before it are orphans. They are harmless: write-once,
      unlisted, and PUBLISH uploads by manifest.
    - Recency: same defect as 8 (finding 1).
15. **Manifest-level `provenance` (link version, sha, dirty) and `datasets[].schema.cols`**
    (:636-650): **DEFECT** (finding 2). Round 3 did not list it.
16. **`.lnk_manifest_pairs` on parts with no `wsgs`** (an older manifest gives `":BT"` locally and
    `"NA:BT"` through `lnk_catalog`): checked-ok. Every manifest from this branch carries `wsgs`,
    and the mismatch would refuse rather than pass.
17. **"run_uid shared across configs"** (:837-845): checked-ok. It is call-scoped, but provenance
    is keyed per build, and nothing in the root depends on a uid belonging to one config.
18. **lnk_db_load's config replace and table COMMENT**: checked-ok. The replace is an accepted
    tradeoff, and the COMMENT says "last load".
19. **The miss check for named groups** (:783-799): checked-ok. Reasons are reported per schema.
20. **BUILD driver flags against the new refusal** (habitat_publish.R:9-11, :256-257): **defect,
    low** (finding 4). Round 3 did not list it.

## Findings

- **[severity: fragile, silent regression in the bucket] INSIDE ROUND-3 FIX (b)**
  habitat_publish.R:151-175 and R/lnk_scenario_export.R:975-993.
  - **What the fix covers:** whether the root has each published group:species pair.
  - **What it leaves on the proxy:** whether it holds that group's *current* build. That is still
    judged by the export time, which is the exporting clock, not the build.
  - **The case:** an export from a database whose latest finished build of a group is older than
    the one published. For example, host B's fwapg before a rebuild was consolidated. Root
    seeded from the bucket, which is exactly the remedy the refusals prescribe.
  - **What happens:** the export takes that older build. The pairs are the same and `exported` is
    newer, so BUILD and PUBLISH both pass.
    - The older build's provenance is either already in the bucket with the same content, or a new
      key put with `--if-none-match`.
    - PUBLISH then overwrites the live part with the older build's rows.
  - **Reproduced:** fixture schema S, ADMS built r1 on 2026-10-01. Sibling schema S_old, identical
    except that ADMS's latest build is r1sep from 2026-09-15. Export S into the root (the "live"
    manifest), then export S_old into the same root.
    ```
    LIVE runs:  ADMS r1 2026-10-01...   BULK r2 ...  LFRA r3 ...
    LOCAL runs: ADMS r1sep 2026-09-15... BULK r2 ...  LFRA r3 ...
    lost: 0   older: FALSE      (no narrow refusal; both PUBLISH predicates pass)
    ```
  - **Same host:** this also happens wherever a config is exported from a schema that holds older
    builds of it than the schema the bucket came from.
  - **Fix:** compare per group, not per config.
    - For each group in the root's or the live config entry's `runs`, refuse unless the new
      entry's build is the same `run_id` or has a later `date_start`, unless a flag is set.
    - BUILD has both `runs` lists, at :975.
    - PUBLISH can do the same from `live_cfg[[i]]$runs` against `m$configs`. The data is already
      in both manifests.

- **[severity: fragile, provenance misattribution] NOT IN ROUND 3's ENUMERATION**
  R/lnk_scenario_export.R:636-650 with :1086-1117.
  - **What is wrong:** `provenance.link_version`, `link_sha` and `link_dirty`, and
    `datasets[].schema.cols`, are computed from the link doing *this* call. They are written
    once for the whole manifest.
  - **Why it matters:** the carried-forward configs' parts were exported by whatever link ran then.
    The export code computes values: ratios, `mad_m3s` with the logged fill, the flag coalesce. So
    a reader attributes config B's parts to export code that never touched them.
  - **No per-config record:** the per-config entry records `exported` but no exporting link.
  - **Same mechanism:** a value from one call, stored as a property of everything in the root.
  - **Fix:** record `link_version`, `link_sha` and `link_dirty`, and the contract or its hash, in
    each config entry beside `exported`. Optionally refuse to carry a config forward under a
    different contract.

- **[severity: fragile, low] INSIDE ROUND-3 FIX (a)** R/lnk_scenario_export.R:325 with :870.
  - **What is wrong:** in named mode, `why` is computed over every group the schema holds. So
    `skipped` lists the held groups that cannot be exported, but omits groups that could be
    exported and were not named. It is not "groups no schema of the config exported", which is
    what the helper's doc says.
  - **Reproduced:** with BABL unlogged, `wsgs = "ADMS"` gives `wsgs = [ADMS]` and
    `skipped = {BABL}`. BULK and LFRA, which were not exported, are absent.
  - **Fix:** in named mode, limit `skip` to the named groups (or the held set). Alternatively,
    document `skipped` as "held groups with no exportable build".

- **[severity: fragile, low] NOT IN ROUND 3's ENUMERATION** data-raw/habitat_publish.R:9-11 and
  :256-257.
  - **What is wrong:** BUILD passes no `narrow`, and there is no `--narrow` flag.
  - **What follows:**
    - The header's own example (`--wsgs=DUNC,KOTL --species=BT,RB`) now always refuses on a root
      seeded from the bucket.
    - The refusal says "pass narrow = TRUE", which the driver cannot do.
    - PUBLISH offers `LNK_PUBLISH_NARROW=1`, but a narrowed root can be built only from R
      directly.
  - **Severity:** loud, not data loss.
  - **Fix:** add `--narrow` to the driver, and correct the header example.
