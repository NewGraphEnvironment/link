# Plan review 1 — #246 (Plan agent, 2026-10-16)

Read-only reviewer. Findings were reported as reply text and written here by the parent session. Each one has a
verdict from a probe by the parent; "confirmed" means it was reproduced against the code or the DB.

## Blocker
- **B1. The driver's bucket resolve drops `default`'s 24 extra groups.**
  - `study_area_run.sh:913,919` call `study_area_wsgs.R "<focal>"` with no config, so it defaults to `bcfishpass`
    (`study_area_wsgs.R:20`), and without `LNK_LOAD=loadall`, so it loads the installed link 0.50.0.
  - Every in-driver completeness check is computed against those shrunken buckets.
  - **Confirmed** (installed link is 0.50.0, and lines 913 and 919 pass neither).
- **B2. The run label is rejected.** `--run-label=` allows only `A-Za-z0-9._-` (`study_area_run.sh:185-190`).
  **Confirmed.**
- **B3. The parity step has no tunnel-free code path.**
  - `lnk_parity_annotate()` needs a rollup (`wsg, species, habitat_type, link_value, ref_value, diff_pct`).
  - `lnk_compare_rollup()` requires a `:63333` connection, and the tunnel is closed.
  - **Confirmed.** Resolution: `data-raw/parity_crosssection.R` is the tunnel-free accessible / spawning / rearing
    validator against `fresh.streams_vw_bcfp`. Its rows map onto the rollup columns, and its metric names
    (`accessible`, `spawning`, `rearing`) are the taxonomy's vocabulary. Its link side is hardcoded to `fresh`.

## Acceptance
- **A-1.** `study_area_verify.sql` defaults `schema=fresh`; pass `-v schema=fresh_default`.
- **A-2.** Verify does not check:
  - `config_hash` / `config_drift`;
  - `log_input` counts / `source_at`;
  - `log_parameters_fresh` / `log_dimensions`;
  - "newest row is this run".

  Phase 4 needs its own SQL for these.
- **A-3.** `--preflight-only` without `--cy-workspaces` skips the doctl, tofu, s3 and branch gates. Pass the
  workspaces.
- **A-4.** "Artifact ids identical across hosts" proves little:
  - `api` sources are NULL by design, and FWA rows are probes;
  - cloud hosts' FWA comes from the May image;
  - September's `log_input` shows m1 and the cyphers differing on `fwa_lakes_poly` / `fwa_wetlands_poly` row-count
    estimates.

  Assert loader ids for bcfishobs and crossings, compare `row_count` per table across hosts, and state the FWA
  limitation in the record.

## Gap
- **G1.** The cypher path has not run at 0.66. The newest cypher rows are 0.50.0. The paid run would be the first test
  of each of these:
  - `cypher_prep` at 0.66;
  - `fresh_default` creation on a cypher (`cypher_prep.sh:319` force-recreates only the bcfishpass schema);
  - consolidating 11-species columns.

  Add a one-cypher pilot.
- **G2.** A consolidate failure exits 1 and the EXIT trap burns every cypher, losing their unconsolidated work. Consider
  `--keep-cyphers`.
- **G3.** The cypher ssh sessions (~4–5 h each) have no keepalive (`study_area_run.sh:1066`). Keep the laptop awake.
- **G4.** The generated `research/study_areas.md` launch command hardcodes `--config=bcfishpass` with no `--schema`. A
  paste would overwrite `fresh`.

## Assumption
- **A1. Host speeds.** 0.45 comes from one 7-min pilot. The 34-group run `20260901_234743` contradicts it.
  **Confirmed** from `fresh.log`:

  | host | groups | min | min per 1k source segments | min per 1k persisted |
  |---|---|---|---|---|
  | m1 | 19 | 88.1 | 0.219 | 0.093 |
  | job1 | 9 | 24.5 | 0.113 | 0.048 |
  | job2 | 6 | 35.4 | 0.220 | 0.082 |

  `default` on m1 at 0.63.1 (DUNC): 0.096 min per 1k source.
- **A2.** `/bin/bash` 3.2 is first on PATH, and the driver uses `declare -A`. Launch with `/opt/homebrew/bin/bash`.
- **A3.** Any edit to a tracked file mid-run sets `link_dirty`, and verify fails. A `nohup.out` at the root dirties
  the tree. Redirect output under `data-raw/logs/`.
- **A4.** `--refresh-primitives` reloads `fresh.streams_vw_bcfp`, and preflight checks only that it exists. Record its
  row count before (4,272,365 / 188 groups) and after.
- **A5.** Cypher disk headroom is unknown: about 32 GB of `working_*` per cypher at about 35 KB per segment
  (`cleanup_working = FALSE`, `wsg_run_one.R:86`).
  - The dispatcher would hold about 70 GB of `working_*` and about 30 GB of persist. So working schemas, not the
    persist, are the growth, which revises the plan's +120 GB.
  - Read free space inside the container, not on the host.
- **A6.** The vintage note in findings is stale: the m1 snapshot ran 2026-10-12/13.

## Ordering
- **O1.** Pin `--refresh-primitives` in the launch, or state that the pilot's same-day refresh stands in for it.
- **O2.** Pilot on a `default`-only group, so it exercises the B1 fix.
- **O3.** The parity run reuses the `working_<wsg>` names; never overlap it with the main run.
- **O4.** Re-running consolidate deletes `log_recompute` rows; re-run the recompute after it.

## Scope
- **S1.** Make the parity acceptance tunnel-free (B3).
