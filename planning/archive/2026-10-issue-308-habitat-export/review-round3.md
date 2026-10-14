# Code-check round 3: #308 habitat export (branch diff main...HEAD, round-2 fixes)

Reviewer: subagent, 2026-10-14. I read these in full: R/lnk_scenario_export.R, R/lnk_catalog.R,
R/lnk_db_load.R, data-raw/habitat_publish.R, data-raw/logs/habitat_export_308/verify.R,
tests/testthat/helper-export.R, the round-2 fix patch, RUNBOOK §6d, and the log writers in
R/lnk_log.R and R/lnk_pipeline_run.R that the provenance keys depend on.

Probes:
- One throwaway test file, run from a `cp -r` copy of the repo in the scratchpad against local
  fwapg. It used the fixture's `lnk_test_export_<pid>` schemas plus a `_p` sibling, both dropped
  by `defer`. I confirmed that none remain.
- Read-only queries on `fresh.log` and `fresh_default.log`.

Nothing in the repo was edited except this file.

## Mechanism

Each piece the export writes or checks is computed from what one call, or one root, can see:
the schemas and groups passed, the local manifest, and the exporting clock. It is then stored or
compared as if it were a property of the build, or of the published config, which another call
or root would reproduce. Each time, two lists happen to agree in the case that was tested:

- what this export read, against what exists for the build or config;
- what this root holds, against what is live.

Round 2 moved provenance onto keys that do not depend on scope (per build, per config hash). That
closes the first pair for evidence files. Three places still rest on it:

- the per-config entries that union per-schema answers by group name;
- the "nothing to export" stop, which still judges a schema as if it were the config;
- the PUBLISH guard, which compares a proxy (the export time) for the property (the local config
  covers the live one).

Places the mechanism reaches, each checked:

1. **Per-build `log` / `log_input` files** (`.lnk_export_provenance`, :536-547): **checked-ok.**
   - A finished log row does not change: `lnk_pipeline_run` sets `completed <- TRUE` before
     `.lnk_log_run_finish`, and `.lnk_log_run_fail` runs only when `!completed`.
   - `log_input` is `ON CONFLICT DO NOTHING`, and nothing else updates either table.
   - The duplicate-group check holds one schema per group.
2. **Per-hash `log_parameters_*` files from `got[[1]]`** (:548-562): **checked-ok in practice.**
   - The snapshot is the full bundle table, written once per hash per schema
     (`.lnk_log_config_snapshot`) and independent of presence. Any schema holding the hash
     therefore holds the same rows.
   - The file still comes from whichever schema is first in `configs`. It can differ only when
     two schemas snapshotted one hash under different link dictionaries; that is low and noted.
3. **`log_recompute` files** (:990-1007): **checked-ok.** Both recompute drivers mark failure only
   on error and finish last.
4. **The `source_artifact` snapshot**: **checked-ok.** It is keyed by content.
5. **Bundle files under `config/sha256-*`**: **checked-ok.** They are byte copies under the hash.
6. **`configs[].skipped`, merged across schemas** (:842-845): **DEFECT** (finding 1).
7. **`thresholds_logged`, `any` across schemas, against ratios read per schema** (:890-897 against
   `.lnk_export_rows`): **checked-ok in practice.** A schema that holds a build at hash h ran that
   build's snapshot of h itself, so the two agree.
8. **PUBLISH's `exported` guard** (habitat_publish.R:144-160): **DEFECT** (finding 2).
9. **The `strict = is.null(wsgs)` stop on a schema with nothing to export** (:773, :319):
   **DEFECT, low** (finding 3).
10. **The "held by more than one schema" check** (:800-808): **checked-ok.** It is loud and gives
    the same answer in both modes.
11. **The carry-forward of other configs' entries and files** (`.lnk_manifest_previous`):
    **checked-ok.** `exported` rides along unchanged.
12. **The `exported` text comparison**: **checked-ok.** Both sides use one fixed-width format
    (`%Y-%m-%dT%H:%M:%OS3Z`), so collation cannot reorder them.
13. **verify.R's schema per run, from the log's `schema_persist`**: **checked-ok today.** The
    column is non-NULL on all 65 `fresh` and 5 `fresh_default` rows. The export accepts an NA
    `schema_persist` (:289), so on such a row `data.frame(schema = NULL)` would error. That is
    harmless for the pilot.

## Findings

- **[severity: fragile] INSIDE ROUND-2 FIX (skipped as object)** R/lnk_scenario_export.R:842-845.
  `skipped` is `unlist()` of every schema's skipped list, keyed by group name. Two things follow.
  - **A group held by two schemas appears twice.** jsonlite then writes a made-up key.
    **Reproduced** (wsgs = NULL; BABL held in both schemas with no log row; ADMS exported from s1,
    and in s2 as another config's build):
    ```
    "wsgs": ["ADMS", "BULK", "LFRA", "KOTL"],
    "skipped": {
      "BABL": "no log row",
      "BABL.1": "no log row",
      "ADMS": "latest build is config 'othercfg'"
    }
    ```
    `BABL.1` is not a group code, and it is published.
  - **A group the config did export is listed as skipped** (ADMS above). A reader that takes
    `skipped` as "not exported" for the config is wrong.

  Named mode hides both effects only by accident: a schema that exports nothing is dropped by
  `keep_schema` before the merge, and its `skipped` goes with it. Build the config's `skipped`
  from groups that **no** schema of the config exported, with one reason per group (for example
  `"<schema>: <why>"` joined across schemas), and drop names that are in `r_cf$watershed_group_code`.

- **[severity: fragile, data loss in the bucket] INSIDE ROUND-2 FIX (PUBLISH `exported` guard)**
  data-raw/habitat_publish.R:144-160, with R/lnk_scenario_export.R:835-837 and :924-947. The guard
  refuses only an *older* export, but a *narrower* one is always newer.
  - **Why:** an export replaces the named config wholesale. `.lnk_manifest_previous` drops all of
    its parts, and only the groups and species of this call are written.
  - **Reproduced:** a full export (ADMS, BULK, LFRA; 2 parts), then
    `lnk_scenario_export(..., wsgs = "ADMS")` into the same root. The manifest drops to 1 part,
    `wsgs` becomes `["ADMS"]`, the BULK CO part is gone from `segment/`, and `exported` is newer.
  - **What PUBLISH then does:** the live config is in the root, and the local entry is newer.
    Both checks pass, and every live part of the other groups or species is deleted as stale.
  - **Who hits it:** an operator re-exporting one rebuilt group (`--wsgs=DUNC`) or a species
    subset (`--species=BT,RB`, as the header's own example does). On the 217-group publish, that
    one command would empty the bucket's `default` of every other group, with every md5 check
    green. The round-2 test calls this case "a narrower export of the same builds writes nothing
    new and stops nowhere".
  - **Where this sits in the series:** round 1 guarded configs absent from the root, and round 2
    guarded older configs. This is the same loss on the next axis, groups and species within a
    config.
  - **Fix:** refuse unless the local entry covers the live one. Compare the live `wsgs` and
    `species` (or the live part keys of that config) against the local entry, and require an
    explicit flag such as `--drop` to shrink a published config. Alternatively, have BUILD refuse a
    named `wsgs` or `species` export into a root whose manifest already holds that config with
    more.

- **[severity: fragile, low] INSIDE ROUND-2 FIX (skip-mode per schema, named mode only)**
  R/lnk_scenario_export.R:773 (`strict = is.null(wsgs)`) with :319-322. Round 2 made a schema
  that cannot export a group a skip rather than a stop, but only for named `wsgs`.
  - **With `wsgs = NULL`:** a config's schema that holds no finished build of it stops the whole
    export with "<schema>: no group has a finished build of config".
  - **Reproduced:** a second schema holding only another config's ADMS stopped the NULL export.
    The same two schemas succeed with `wsgs = "ADMS"`, which is the round-2 test.
  - **Real shape:** `c(default = "fresh_default", default = "fresh")` (`fresh`'s latest rows are
    39 `bcfishpass`, 0 `default`) stops whenever `wsgs` is NULL.
  - **It fails loud.** The workaround is to drop the schema from the call.
  - **Fix:** use skip mode per schema in both modes, and stop only when the config as a whole
    exports nothing.
