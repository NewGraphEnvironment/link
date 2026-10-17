# Code-check round 2 (#246) — branch diff + round-1 fixes

Reviewer: round-2 subagent, 2026-10-16. Read-only probes only (no DB writes, no
cloud spend); guard probes run with invalid args that exit at the guard.

## Findings

- **[fragile]** `data-raw/logs/provincial_246/verify_extra.sql:85-89` (5b, row_count
  agreement) — `count(DISTINCT i.row_count)` drops NULLs, so a NULL row_count never
  counts as a disagreement. NULL is real: `row_count` is `nullif(reltuples, -1)`, and the
  first group a cypher runs reads its freshly snapshot tables before autovacuum has
  analyzed them. Measured in run `20260901_234743-6628379d`: cypher-job2's first group
  (LSKE) logged `bcfishobs.observations` row_count NULL and the next five logged 373050.
  So the header's "the snapshot-loaded tables are analyzed at load" does not hold on
  cyphers. If a host's whole bucket runs before that table is analyzed, or the table is
  missing on that host, the host contributes nothing to the comparison and 5b passes.
  5a covers a missing table for bcfishobs and crossings, because the artifact join needs
  `c.oid`. Nothing covers PSCIS or CABD (`api`), although a missing table there would
  also fail the groups. Fix: also fail any (host, table) among the non-FWA tables with
  `count(i.row_count) = 0`. Coalescing NULL to a value would turn the normal NULL from
  each first group into a false failure.

- **[fragile]** `verify_extra.sql` 5a/5b against the driver — after the run, they assert
  that hosts agree on loader version ids (bcfishobs, crossings) and on api row counts
  (PSCIS via live WFS, CABD via live API). The driver never checks either before spend.
  `preflight_hosts()` judges the stamp, which holds no artifact identity
  (`.lnk_preflight_stamp_cols()`), and judges cypher vintage by age only. Cyphers run
  `snapshot_bcfp.sh` at prep, while the dispatcher's loads can be up to
  `--vintage-max-days` (7) old. A new bchamp object version, or a CABD/PSCIS change, in
  that window lets the run pass every gate and then fail verify_extra once the money is
  spent. CLAUDE.md records that `cabd.dams` just moved, 2,594 → 2,592. This is a true
  divergence, so the assertion is right. What is fragile is where the guard sits.
  Mitigation for this run: launch with `--refresh-primitives`, which puts the
  dispatcher's reload minutes before the cyphers' snapshots. The lasting fix is to
  compare `provenance.source_artifact` version_id / n_rows between hosts inside
  `preflight_hosts()`.

## Checked and clean (no action)

- **Charset guard** (`study_area_run.sh:206-210`): it sits straight after the arg loop,
  before every use of CONFIG / SCHEMA_OVERRIDE (the persist guard, resolve_schema,
  DISCHARGE, buckets, both ssh legs, host_stamp, consolidate, psql coverage).
  - Probed with `a'b`, `x'y`, `de$(id)`, `a b` and `fresh-default`: each is refused
    before anything else runs.
  - A SCHEMA resolved from YAML is reachable only when `CONFIG=bcfishpass`, because
    every other config must pass `--schema=`. It is then the trusted bundle value
    `fresh`.
  - An empty `--config=` passes the charset test, then dies at the persist guard or
    the DISCHARGE FATAL.
- **Other variables interpolated into ssh:**
  - DISCHARGE is enum-checked.
  - WET_LOAD is checked for quotes.
  - RUN_LABEL and RUN_UID are checked or generated.
  - The *_GIT_SHA values are hex.
  - B_SPACE holds WSG codes from R.
  - LINK_BRANCH is the only one not checked. Git allows `'` in a ref name, but it is
    the operator's own branch and not new in this diff.
- **cypher_prep.sh:322:** `Sys.getenv("CYPHER_PREP_CONFIG", "bcfishpass")` keeps the
  set-but-empty trap, but it fails loudly (`lnk_config("")` errors, prep is FATAL), and
  the driver always passes a value that is not empty. `--auto-install` (line 854) does
  not pass the config, but the install stage exits before persist_init. The cypher
  persist_init now builds `fresh_default` with cfg$species, which has 11 species. That
  matches the dispatcher's existing `fresh_default` tables (KO / RB / GR columns
  present), so the consolidate does not drop any columns.
- **verify_extra.sql mechanics:**
  - psql does not need to interpolate anything inside `$$`; the values go in through
    set_config.
  - `%%` → `%` inside format() is correct, and `$1` / `%1$I` / nested `$q$` all run.
  - `array_length('{}',1)` is NULL, so an empty fails list passes, as it should.
  - A missing `-v` var causes a syntax error and exit 3.
  - Column names match `cols_log` / `cols_log_input` (R/lnk_log.R).
  - The log_parameters_* tables are keyed `(config_hash, species…)`, as the script
    assumes.
  - `date_start` is NOT NULL.
  - Recompute rows sit in `log_recompute`, so they cannot affect check 2.
  - Consolidate deletes and re-copies `log` / `log_input` per bucket WSG, so a cypher
    group's newest row is this run's.
- **artifact_* on log_input:** `fresh_default.log_input` has 9 columns today and no
  artifact_*. `.lnk_log_create_tables()` aligns the columns at every log open and at
  consolidate step 0 (`schema_consolidate.R:114`), so they exist before
  verify_extra runs.
- **Dry run against `fresh` (run `20260901_234743-6628379d`, expected_n=34):** two
  environmental failures, not one.
  1. `fresh.log_parameters_habitat_thresholds` does not exist (fresh predates #282).
     It is hit first, at check 4.
  2. `log_input.artifact_version_id` does not exist.

  With both stubbed in a scratch copy, the only failure is check 2 (67 of 101 groups
  are not in this 34-group run), which is expected. Checks 1, 3, 4 (fresh /
  dimensions) and 5b pass. All 4 non-FWA tables agree across the 3 hosts. Check 1
  fires with expected_n=35, and a bogus run_uid fails checks 1–4.
- **5b's FWA exclusion is justified:** m1's `fwa_lakes_poly` reltuples is 386,429,
  while `count(*)` is 386,025 (the cyphers' value). That table is 44,000 pages, above
  ANALYZE's 30,000-page sample, so the estimate wanders. The snapshot tables sit below
  that line: bcfishobs 27,072, crossings 12,800, pscis 2,192 and cabd 214 pages. So
  their estimates are exact today. bcfishobs is at 90 % of the threshold; once it
  passes, 5b will report false disagreements.
- parity_crosssection.R: the nzchar fallback is correct. `lnk_rollup_wsg()` returns 0
  rows for a group it does not hold (probed), so the `no_link` FAIL can fire.
- study_area_buckets.R: `fresh::frs_wsg_outlets()` needs no conn (246 rows); `focal`,
  `flat` and `config` are all defined before use.
- `bash -n` is clean on study_area_run.sh and cypher_prep.sh.
