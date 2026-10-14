# Code-check round 5: #308 habitat export (round-4 fixes, and the enumeration)

Reviewer: subagent, 2026-10-14, HEAD b59f61a5. I read these in full: R/lnk_scenario_export.R,
R/lnk_catalog.R, R/lnk_db_load.R, data-raw/habitat_publish.R, verify.R (head),
tests/testthat/helper-export.R, round4_fix.patch, review-round4.md and RUNBOOK §6d.

**Probes.** All ran from a `cp -r` copy in the scratchpad (NOT_CRAN=true) against local fwapg,
using only the fixture's `lnk_test_export_<pid>` schema, which `defer` dropped. Afterwards no
`lnk_test_export_*` or `lnk_review_*` schema remained, and the copy was deleted.
- At HEAD, test-lnk_scenario_export, test-lnk_catalog and test-lnk_db_load gave 159, 16 and 19
  expectations, with 0 failed, 0 error and 0 skipped.
- One probe (below) reproduces finding 1.
- Nothing in the repo was edited except this file.

## Enumeration

Round 4's 20 places, re-checked against HEAD, then the places it missed (21 onward).

1. **Per-build `log` / `log_input` files** (:536-547): checked-ok. Unchanged.
2. **Per-hash `log_parameters_*` from `got[[1]]`** (:548-562): checked-ok. Unchanged, and an
   accepted tradeoff.
3. **`log_recompute` files** (:1146-1163): checked-ok. Unchanged.
4. **`source_artifact` snapshot** (:462-484): checked-ok. Keyed by content.
5. **Bundle files under `config/sha256-*`**: checked-ok.
6. **`configs[].skipped`** (round-4 fix; :877-878, :1025-1036): checked-ok.
   - With `wsgs = NULL`: unchanged.
   - With named `wsgs`: the result is filtered to the named groups. Every named group must be
     exported somewhere, or :784-799 stops, so `skipped` is always `{}` in named mode. That is
     consistent with the new doc ("asked for and not exported").
7. **`thresholds_logged`** (:923-930): checked-ok.
8. **The PUBLISH guard** (habitat_publish.R:145-160):
   - Configs, pairs and build recency (round-4 fix): checked-ok as far as they go.
   - The stale-root guard: **DEFECT** (finding 1). The round-4 fix removed the `exported`
     comparison, and nothing replaced what it covered.
9. **The stop when nothing is exported** (:801-811): checked-ok.
10. **"Held by more than one schema"** (:828-837): checked-ok.
11. **Carry-forward** (`.lnk_manifest_previous`): checked-ok. Whole entries are carried,
    including `exported_by`.
12. **The `exported` field**: **DEFECT**, part of finding 1. It is still written, and the code
    comment at :959-960 and RUNBOOK :682-683 say PUBLISH refuses an older export. Nothing reads
    the field any more.
13. **verify.R**: checked-ok for the pilot. It is unchanged and has no `narrow` reference left.
14. **The BUILD-side check** (:986-1000, round-4 fix):
    - Checked-ok for pairs, for dropped configs, and for an older build under another `run_id`.
      `new_m` holds only this call's parts and entries, and the check runs before the staging
      swap.
    - The same-`run_id` gap of finding 1 also applies here, in the rarer case where the
      database holds fewer recomputes than the root's export.
15. **Manifest-level provenance and `datasets[].schema.cols`**: checked-ok.
    - `exported_by` is now per config (:856-861, :964), carried forward with the entry.
    - The whole-root `cols` remains. A carried config under another contract fails
      `lnk_db_load()`'s column check loudly.
16. **`.lnk_manifest_pairs` on parts with no `wsgs`**: checked-ok.
17. **`run_uid` shared across configs**: checked-ok.
18. **lnk_db_load's replace and COMMENT**: checked-ok. Unchanged.
19. **The miss check for named groups**: checked-ok.
20. **BUILD driver flags**: checked-ok. `--replace` is wired (habitat_publish.R:242) and the
    header documents it (:11-14). The refusal text names `replace = TRUE`, not `--replace`,
    which is cosmetic.
21. **`.lnk_manifest_regressions()` itself** (new in round 4; :1088-1123): **DEFECT** (finding 1).
    - It keys a group's content on `run_id` alone.
    - Checked-ok in the details:
      - `date_start` comes through `.lnk_json_rows()` on both sides (timestamptz, UTC,
        `%OS3Z`), so it is fixed width.
      - The text `<` is order-safe under locale collation, because the punctuation sits at the
        same positions.
      - The list and data-frame branches of `.lnk_entry_builds()` agree.
      - `$` partial matching cannot hit (`run_uid` does not prefix-match `run_id`).
      - An NA `date_start` is skipped.
22. **PUBLISH reads the live manifest twice** (`lnk_catalog` then `.lnk_fetch_text`, :147-150):
    checked-ok. A race between the two reads is covered by the accepted single-operator
    tradeoff.
23. **`LNK_PUBLISH_REPLACE=1` now also overrides a dropped config**, after which the stale
    deletion removes its segment keys: checked-ok. That is the intended override and is
    documented in the header (:28-30).
24. **`exported_by` computed once per call** (:856-861): checked-ok. Every config re-exported in
    the call shares one link. `contract_md5` resolves through `system.file`, which pkgload shims.

## Findings

- **[severity: fragile, silent regression in the bucket] INSIDE ROUND-4 FIX**
  data-raw/habitat_publish.R:145-160, R/lnk_scenario_export.R:1088-1123.
  - **What the round-4 fix did:** it removed PUBLISH's `local exported < live exported` refusal
    as a proxy for build recency. It replaced it with `.lnk_manifest_regressions()`, which
    judges builds by `run_id` and `date_start`.
  - **What the removed check also covered:** a root that is not seeded from the bucket, holding
    an older export of the *same builds*. That refusal said "Seed the root from the bucket".
  - **Why the same builds can export different parts:** the parts are not a function of
    `run_id` alone.
    - `has_barriers_dnstr` reads `streams_access`, which every cross-group recompute rewrites
      (`recompute_keys` grows).
    - `mad_m3s` and `*_ratio_mad` read the discharge table at export time.
    - The derived columns depend on the exporting link (`exported_by`).
    - So a stale root's carried-forward config now passes PUBLISH. `put-object` then overwrites
      the live parts, and the config entry's `recompute_keys` / `exported_by`, with the older
      state. There is no refusal and no message.
  - **Reproduced** in a scratch copy, with the fixture schema:
    1. Export to `stale`.
    2. Add recompute `rc2` for ADMS, rewrite `streams_access`, and double `discharge`.
    3. Export to `live`.
    4. Call the judgement PUBLISH calls, `.lnk_manifest_regressions(live, stale, "testcfg")`.
    ```
    stale exported: 2026-10-14T18:37:32.285Z  live exported: 2026-10-14T18:37:34.623Z
    stale ADMS recompute_keys: provenance/recompute_id=rc1
    live  ADMS recompute_keys: provenance/recompute_id=rc1 provenance/recompute_id=rc2
    stale md5: 632bd74c... 3c7ee1b1...    live md5: 6812efa9... fa4ff495...
    PUBLISH regressions (stale root over live): 0
    ```
    Before round 4, `local_at < live exported` refused this case.
  - **BUILD has the same gap**, from the other direction: an export from a database holding
    fewer recomputes of the same `run_id` than the root's export (another host's copy of the
    schema). It is rarer, but it is the same judgement.
  - **Stale text claiming the removed guard:**
    - R/lnk_scenario_export.R:959-960: "PUBLISH refuses to replace a published config with an
      older export of it".
    - RUNBOOK.md:682-683, the same sentence.
    - habitat_publish.R:142-144 and RUNBOOK:722 still say the live configs "must all be in"
      the root. That is now overridable by `LNK_PUBLISH_REPLACE=1`.
  - **Fix**, two checks in `.lnk_manifest_regressions()`, so BUILD and PUBLISH still share one
    judgement:
    1. **Recomputes.** For a group whose `run_id` is the same on both sides, flag it when
       `new`'s `recompute_keys` do not include all of `old`'s.
    2. **Export time.** For each config, flag it when `new`'s `exported` is earlier than
       `old`'s and the config's part md5s differ.
       - This restores the stale-root guard. It is the only signal that catches a discharge
         reload or a change in the export code.
       - In BUILD it never fires, because the new `exported` is always now.
    - Then correct the three stale passages.
