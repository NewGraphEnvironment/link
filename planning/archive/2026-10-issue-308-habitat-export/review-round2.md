# Code-check round 2: #308 habitat export (branch diff main...HEAD, round-1 fixes)

Reviewer: subagent, 2026-10-14. Read in full: R/lnk_scenario_export.R, R/lnk_catalog.R,
R/lnk_db_load.R, the .lnk_config_files split in R/lnk_log.R, data-raw/habitat_publish.R,
data-raw/logs/habitat_export_308/verify.R, tests/testthat/helper-export.R, the round-1 fix
patch, RUNBOOK §6d. Probes: jsonlite snippets in the scratchpad, and one throwaway test run
from a `cp -r` copy of the repo against local fwapg (it used the fixture's own
`lnk_test_export_<pid>` schemas, dropped by its `defer`; confirmed none remain). Nothing in
the repo was edited except this file.

## Findings

- **[severity: bug] INSIDE ROUND-1 FIX (1 + 2)** R/lnk_scenario_export.R:771-783 with
  :864-865 and :506-570. The provenance record of a dispatch now depends on the **scope of
  the export**, so a later, wider export of the same unchanged build stops for good.
  `.lnk_export_provenance()` gathers `log` / `log_input` / `log_parameters_*` only from
  `unique(r_cf$schema_export)`, and `keep_schema` drops every schema of the config that holds
  none of the named `wsgs`. So with a `run_uid` spanning two schemas of one config:
  1. `lnk_scenario_export(conn, c(cfg = s1, cfg = s2), root, wsgs = "ADMS")` writes
     `provenance/run_uid=U1/log.parquet` from s1 only;
  2. `lnk_scenario_export(conn, c(cfg = s1, cfg = s2), root, wsgs = c("ADMS", "BULK"))`
     (or `wsgs = NULL`) gathers s1 and s2, `.lnk_parquet_same()` sees more rows, and the
     export stops: "already written with different content".

  **Reproduced** with the round-1 test's own two-schema fixture: the first export wrote
  `run_id` r1, r2; the second stopped with exactly that message. Because provenance is never
  deleted, the config cannot be exported at the wider scope without a manual delete. The same
  happens when the caller passes only some of the schemas a dispatch wrote, then all of them
  later. The other columns follow the same rule: a column present in only one schema is
  NA-filled as logical in the narrow export and typed from the other schema in the wide one.

  This is round 1's finding 1 (the record changes for reasons that are not the build), now on
  the axis the finding-2 fix opened. Two fixes would make the record independent of scope:
  key provenance per schema as well as per run (`provenance/run_uid=<u>/schema=<s>/...`), or
  write one record per `run_id`. Either way, the file then holds what one schema logged, which
  the export's arguments cannot change.
  - Still open from round 1, and lower-likelihood: rows of the dispatch's *other* groups are
    in the record too. `.lnk_log_run_finish` sets `date_end` and `species`, and
    `.lnk_log_run_fail` appends `notes` (R/lnk_log.R:975, :999). So an export taken while any
    group of the dispatch is still open stops once that group closes.

- **[severity: bug] INSIDE ROUND-1 FIX (2)** R/lnk_scenario_export.R:774-777 with
  :302-311. Named groups are passed to **every** schema of the config that holds them
  (`intersect(wsgs, held[[i]])`). `.lnk_export_runs()` then stops on any group whose copy in
  that schema is not a finished build of the config. With `wsgs = NULL` the same copy is
  skipped, and the good copy in the other schema is exported.
  - So named `wsgs` cannot be used whenever a group sits in two schemas of a config and one
    copy is another config's build.
  - That case is ordinary here. `default`'s YAML schema is `fresh` (CLAUDE.md, 2026-10-12), so
    `fresh` holds `bcfishpass` and `default` builds side by side, and it holds nearly every
    group. With `c(default = "fresh_default", default = "fresh")`, naming any group whose
    `fresh` copy is a `bcfishpass` build stops with "latest build is config 'bcfishpass'",
    while the `NULL` path exports it from `fresh_default`.
  - This is the round-1 defect one axis over: groups *held* by some schema were fixed, groups
    *held by several* were not.
  - The fix matches the stated rule ("each must be held by one of them"): ask each schema in
    skip mode, and stop only for a named group that no schema exports. The existing duplicate
    check still catches a group exportable from two schemas.

- **[severity: fragile] INSIDE ROUND-1 FIX (5)** data-raw/habitat_publish.R:137-152, with
  :173-195. The new guard compares config **names** only, but PUBLISH also puts every local
  part and deletes every live `segment/` key the local manifest does not list. So a root
  carrying an **older** copy of a config overwrites the newer published one, and nothing
  refuses.
  - The sequence: root R1 publishes `default`. Root R2 is seeded from the bucket, as the
    refusal message at :149-150 and RUNBOOK §6d recommend, then re-exports `default` and
    publishes it. Back on R1, an export of `bcfishpass` carries R1's stale `default` forward.
  - On publish, `live_cfg` is a subset of `local_cfg`, so the guard passes. R1's old `default`
    parts are put over R2's, and any part key R2 added (a new drainage code, a species) is
    deleted as stale. The manifest then describes R1's old `default`.
  - The md5 checks all agree, so nothing downstream notices; the published data silently goes
    back to an older build.
  - It is not the accepted simultaneous-publisher race: the two publishes can be days apart,
    and the workflow the fix recommends creates the second root.
  - A guard that closes it: record when each config was exported in its `configs[]` entry. For
    each live config, refuse unless the local entry for it is the same export (same time and
    part md5s) or a newer one.

- **[severity: fragile] same class as round-1 finding 3, not covered by its fix**
  R/lnk_scenario_export.R:826 and :908 (`skipped`). `configs[].skipped` changes JSON type
  with its length. When some group was skipped it is an object (`{"LFRA":"latest build is
  ..."}`). When none was, it is an array (`[]`), because `do.call(c, <named empty lists>)`
  drops the names. Measured with jsonlite:
  - `do.call(c, list(named_empty, named_empty))` writes `[]`;
  - `do.call(c, list(named_empty, list(A = "why")))` writes `{"A":"why"}`;
  - a named empty list on its own writes `{}`.

  A non-R reader that does `skipped.items()` / `Object.entries(skipped)` fails on the
  empty case, which is the common one for a fully-built config. The round-1 test checks the
  array fields only. Build it as `stats::setNames(as.list(<chr>), <names>)` from a
  character vector (`unlist()` the per-schema attributes first), so that an empty value is a
  named list and serialises as `{}`.

- **[severity: fragile, low]** data-raw/logs/habitat_export_308/verify.R:38-46 (untracked
  pilot check). `schema_of` takes `schema_persist[[1]]`, so after the round-1 change that
  lets a config span several schemas, every group from the second schema is compared with
  `lnk_rollup_wsg()` on the first, which does not hold it. The verify output would then report
  spurious differences, or match on zeros. It is harmless for the current single-schema
  pilot. Resolve the schema per group from `configs[].runs[].schema_persist`.

Checked and not flagged (with the reason):
- `I()` inside data-frame list columns survives `dataframe = "rows"` + `auto_unbox`:
  `I("BT")` writes `["BT"]` and `I(character(0))` writes `[]` (measured).
- Carry-forward round trip (`fromJSON(simplifyVector = FALSE)`, then rewrite with
  `auto_unbox`): one-element arrays come back as `list("A")` and stay arrays, and `null`
  stays `null` under `null = "null"` (measured).
- `thresholds_logged` and `discharge.fill` are always non-empty named lists (one hash and
  one group at least), so they are always objects.
- Staging swap: every config left after `keep_schema` writes at least one part (`sp_cf` is
  non-empty and every species in it belongs to some exported group), so `file.rename(src,
  dest)` always has a source. Provenance written before a later config fails is left
  unlisted, and that is harmless: it is write-once and the next export rewrites the same key.
- `.lnk_write_once` keeps the old bytes when `same`, and its entry is read from disk, so the
  local md5 stays equal to the S3 ETag of a key published earlier.
- The source_artifact snapshot is keyed by the md5 of its bytes, so its ETag equals its
  key by construction. A new duckdb version gives a new key, which is never a conflict.
- PUBLISH ordering: every head check runs before the first put, and an interrupted put of
  new write-once files re-runs cleanly (those keys now match).
- `lnk_catalog()` on a bare filename: `dirname()` gives `"."`, so the href is
  `./segment/...`, which resolves.
- `.lnk_parquet_same`: `all.equal` on data frames is per column and ignores attributes.
  Integer and double compare equal, and both sides are read back through duckdb in one
  session, so timestamp tz attributes agree.
