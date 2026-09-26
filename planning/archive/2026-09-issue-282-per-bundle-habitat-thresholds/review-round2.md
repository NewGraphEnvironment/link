# Review round 2 — #282 branch diff (main...HEAD)

Probed in a scratch copy of the repo (working tree untouched). All five changed
test files pass there (config 122, log 268, dictionaries 42, classify 19,
connect 10; 0 fail, 0 skip under NOT_CRAN=true). Every bundle verifies clean,
and every vendored thresholds CSV is byte-identical to fresh 0.33.0's. The
`config_hash` of `default_tuned` and of all four non-extends bundles is the same
from two different install paths.

Checked and found sound:
- `chain` ordering (leaf first)
- `.dir` stamping at depth 3, including a grandparent's `.dir` surviving
- a custom bundle outside the package extending a bundled one, and one whose
  directory basename matches the bundle it extends
- the `/` suffix on the chain-dir pattern (`default` does not match `default_tuned`)
- `$` partial matching on `chain` / `.dir` / `parameters_habitat_thresholds`
- `.dir` does not leak into `lnk_stamp()` (reads verify output only),
  `regen_provenance.R` or `sync_bcfishpass_csvs.R` (both read YAML text)
- the per-table snapshot gate on a new schema (`.lnk_log_run_start` creates the
  tables before the snapshot) and on an existing one (backfill). The gate test
  fails if the gate is reverted to the single one or removed.
- `schema_consolidate.R` and `lnk_log_read()` do not enumerate the parameter
  tables, which was already true before this branch.

## Findings

- **[severity: bug]** R/lnk_config.R:229-230 — a 3-deep `extends:` chain fails
  to load unless the middle bundle declares its own `rules:` and `dimensions:`.
  `.lnk_config_merge` builds the inherited path as
  `file.path(parent_dir, parent$rules)`. At depth 3, `parent$rules` has already
  been made absolute by the earlier merge, so the result is
  `<default_tuned>//<...>/default/rules.yaml`.
  - `.lnk_config_absolutize_files` guards against this for `files:`, but
    `rules` and `dimensions` have no such guard.
  - Measured: a bundle with only `extends: default_tuned` and a `pipeline.schema`
    fails in `lnk_config()` with "`rules:` references missing file:
    .../configs/default_tuned//.../configs/default/rules.yaml".
  - The same bundle loads, verifies and hashes correctly once it declares
    absolute `rules:` and `dimensions:`, so the provenance, chain and hash work
    in this diff holds at depth 3. Only these two keys break.
  - The lines are older than this branch. It matters now because `default_tuned`
    is the first shipped thin bundle, and extending it is the obvious next step
    (for example, a CH-only tuning variant).
  - Fix: wrap both in `.lnk_path_is_absolute()`, as the files helper does.

- **[severity: fragile]** data-raw/regen_provenance.R:32 and
  data-raw/audit_configs.R:89 — two of the three `lnk_rules_build()` callers
  did not get the change made to the third.
  - `build_rules.R` now passes the bundle's own `thresholds =`, because
    `rear_lake_ha_min` is baked into rules.yaml. `regen_provenance.R` and audit
    §2 still use the default, which is fresh's CSV.
  - No effect today, because the copies are byte-identical.
  - Once a bundle's `rear_lake_ha_min` diverges (the workflow the new
    `default_tuned/README.md` describes):
    - `regen_provenance.R` rewrites `default/rules.yaml` with fresh's lake floor,
      silently undoing the tuned value, then re-stamps its checksum so
      `lnk_config_verify()` reports clean.
    - Audit §2 compares against a build from fresh's copy, so it flags a
      correctly built rules.yaml as stale.
  - Related: audit_configs.R:39 still lists only `bcfishpass` and `default`, so
    the new §3c "fresh added a column this bundle lacks" check never looks at
    the `default_tuned`, `default_extrabreaks` or `default_rearbreaks` copies.
    `test-dictionaries.R` covers undocumented columns for every bundle, but not
    staleness against fresh.

- **[severity: fragile]** R/lnk_log.R:674-678 with R/lnk_log.R:60-67 — for a
  bundle that declares no thresholds CSV, the logged thresholds can go stale.
  - Such a bundle (any custom one; the fallback exists for them) logs fresh's
    copy into `log_parameters_habitat_thresholds`.
  - `.lnk_config_hash()` does not hash that fallback file.
  - The snapshot is first-write-wins per `config_hash`, through both the
    `already()` gate and `ON CONFLICT DO NOTHING`.
  - Result: after a fresh upgrade that changes a threshold, later runs of the
    same bundle keep the same hash and record nothing. The table then shows the
    older values for runs that used the new ones, which is exactly the drift the
    fallback message warns about.
  - Mitigation: `log.fresh_sha` lets a reader notice the mismatch by joining.
  - Fix: add the resolved fallback path to the hashed file set when the config
    declares none, e.g. `suppressMessages(.lnk_habitat_thresholds_csv(cfg))`.
    That keys the snapshot on the values actually used.
  - Shipped bundles are unaffected, because all five declare their own.
