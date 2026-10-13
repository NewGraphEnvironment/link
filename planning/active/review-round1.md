# Code review — round 1 (branch 265-record-source-artifact-identity-for-the vs main)

Scope read in full: R/lnk_artifact.R, R/lnk_log.R (primitives, cols_log_input,
.lnk_log_inputs), R/lnk_preflight_vintage.R, R/lnk_stamp.R, R/lnk_pipeline_break.R,
data-raw/snapshot_bcfp.sh, data-raw/artifact_record.R, tests (artifact, vintage,
setup, log), RUNBOOK/CLAUDE diffs; callers host_vintage.R, cypher_prep.sh,
study_area_run.sh, schema_consolidate.R, state_clean.sh, R/utils.R (.lnk_host).
Live DB checked read-only: 4 loader rows (2 with version ids, 2 api) and 253 probe
rows for host m1, so the pinned fetch path and the HTTP-date fix work end to end.

Deferred items from the brief (table in `fresh`, `host` in the PK) not re-reported.

## Findings

- **[fragile]** R/lnk_artifact.R:279-290 (probe-over-probe update) together with
  RUNBOOK.md §6b ("To tell whether two runs read the same FWA data, compare
  `log_input`'s `artifact_version_id` / `artifact_etag`") — every snapshot re-probes
  the FWA artifacts and the `ON CONFLICT … WHERE existing.recorded_by = 'probe'`
  branch overwrites the earlier probe's version_id / etag / last_modified with
  whatever the store holds *now*, although nothing reloaded the FWA tables. The test
  "probe replaces probe" pins this. Consequence for the documented use: fwapg loads
  V1; bchamp publishes V2; the next snapshot probe records V2; run A (reads V1) logs
  `artifact_version_id = V2`; `load.sh` later reloads V2; run B logs V2. Comparing
  the two runs' `artifact_version_id` says "same FWA data" when they read different
  data — a false pass in exactly the comparison the RUNBOOK tells operators to make
  (and the earlier probe, taken closest to the real load, is gone for good, which is
  the loss this table exists to prevent). The `probe` label is honest about
  strength, but the RUNBOOK guidance does not restrict the comparison to `loader`
  rows. Either keep the first probe (no update of a probe row whose identity
  differs unless n_rows also changed / or DO NOTHING probe-over-probe), or change
  the RUNBOOK sentence to say probe-row identities cannot answer "same data" and
  fall back to row_count / size_bytes for FWA until link#270.

- **[fragile]** data-raw/artifact_record.R:69-70 — `snapshot_tables` is a second
  hard-coded copy of the set `.lnk_vintage_primitives()` derives from the dictionary
  (non-`fwapg/` sources). The gate judges `.lnk_vintage_primitives()`; the record
  script's `--clear`, its `setequal()` manifest check and its read-back all judge the
  literal list. Adding a non-fwapg primitive to `.lnk_input_primitives()` makes the
  gate fail `unstamped` on every host forever while the snapshot's own checks still
  pass (one fact derived twice). Use `link:::.lnk_vintage_primitives()` here.

- **[fragile]** R/lnk_artifact.R:414-421 — `lnk_artifact_read()` returns a different
  column set depending on whether the host has any rows: the all-missing branch has
  no `last_modified`, `n_rows`, `loaded_at`, `recorded_at` (and a different column
  order). An exported reader whose shape depends on the data means a caller doing
  `a$loaded_at` gets `NULL` (not NA) on an unrecorded host, and `rbind()` of reads
  from two hosts fails. Build the empty branch with the same columns (typed NA) as
  the merge branch.

No security issues found. No other real defects: URL validation regex (escape then
fixed `\{wsg\}` swap) is correct; bigint/ETag/HTTP-date serialization is canonical;
the vintage gate fails toward fail on every absence path (no stamp table, no rows for
host, absent table, stamp lookup error); log_input column order matches the SELECT;
consolidation copies log_input by shared column name so the new columns are safe;
the single EXIT trap and `${A_*}` resets in snapshot_bcfp.sh are sound.
