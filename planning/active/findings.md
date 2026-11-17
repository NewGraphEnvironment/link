# Findings — Backlog move 5: The habitat export's contract, and one-group runs that read downstream (#473)

## Issue context

**If we do it:** the export carries code 2, its column contract lives in crate, publishing refuses a build it cannot trace, and a one-group run reads its downstream groups' barriers or refuses. **If we never do:** a one-group run on a partial database ignores every dam downstream, and a consumer can pin a build nobody can reproduce.

Move 5 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 6: The export contract

**Why here:** all edit `R/lnk_scenario_export.R`; one crate release and one republish.

#423 (the habitat export carries whether the species is recorded upstream, access code 2), #333 (register the export's column contract in crate as `nge/habitat/fwa/v1/segment`), #334 (gates before a floodplain item pins a build: refuse a missing `run_uid` or a dirty tree, bucket versioning, public read, a per-group streams digest) and #465 (export each group's persisted barriers and input snapshots, so a one-group run reads its downstream groups). Touches `R/lnk_scenario_export.R`, `inst/extdata/schemas/habitat_fwa_v1_segment.yaml`, `R/lnk_catalog.R`, `data-raw/habitat_publish.R`, crate. Gate: #423's column shape; #334's refusals and the bucket decision; #466 (provenance track) rewrites the same manifest, so it lands first or inside this move. One crate release and one republish. A cloud loader in the infrastructure repository waited on #465, which landed first (PR #483), so the move's PR covers #423, #333 and #334.

| issue | title |
|---|---|
| #423 | Habitat export: carry whether the species is recorded upstream (access code 2) |
| #333 | Register the habitat export's column contract in crate (nge/habitat/fwa/v1/segment) |
| #334 | Gates before a floodplain item pins a habitat build: run_uid, dirty trees, versioning, public read |
| #465 | Export persisted barriers and input snapshots per group, so a one-group run reads downstream (done ahead of the move, in PR #483, 0.80.0) |

## Batch 7: One-group runs that read downstream

**Why here:** both edit `R/lnk_wsg_downstream_check.R`.

#464 (`lnk_wsg_downstream_check()` passes when the downstream groups are not loaded; refuse and name them) and #461 (the same check takes 371 s of a 975 s one-group run; time its steps and make the dominant one fast without changing pass, fail or override). Touches `R/lnk_wsg_downstream_check.R`, `data-raw/wsg_run_one.R`, `data-raw/wsg_recompute_one.R`, tests. No gate.

| issue | title |
|---|---|
| #464 | lnk_wsg_downstream_check() passes when the downstream groups are not loaded |
| #461 | lnk_wsg_downstream_check() takes 371 s of a 975 s one-group run |



## Errors Encountered

| Error | Resolution |
|-------|------------|

## #461: where the downstream check's 371 s goes (measured 2026-11-17, m4)

- Full local fwapg (246 groups, 4.9 M segments), `fresh_default`: the whole check takes 0.20 s on BULK and PARS (probe 1.25 s cold / 0.14 s warm, closure 0.02 s, persisted lookup 0.03 s).
- A scratch database `fwapg473` built as the cloud sessions build theirs (fwapg `newgraph` `db/schema.sql` + migrations, rtj's `cloud-env_load-fwa-wsg.py BULK ADMS SKGT LFRA HARR FRCN`, 4.8 min; `cabd.dams` copied from `fwapg`): whole check 0.18 s on BULK. **#461's 371 s does not reproduce** with the same loader and groups on m4. The guard's code has not changed since 2026-11-05.
- What would produce it: the 65 m lateral KNN snap over all 2,593 CABD dams with no usable GiST index on `fwa_stream_networks_sp.geom`. On a 103,217-segment temp copy of the six groups, 100 dams took 12.2 s without the index (about 316 s for 2,593) and all 2,593 took 0.19 s with it. fwapg's `schema.sql` creates the index (`fwa_streamnetworks_geom_idx`), so a missing index is not shown to be the cloud cause; cold cache or a smaller Postgres in the container are not ruled out.
- A dam whose `cabd_blkey_xref` `blue_line_key` is not loaded scans the whole table in KNN order (20.3 s against 4.9 M rows; one xref row per bundle, its line in LNIC), a second per-dam cost.
- Decision: make the probe's cost independent of these. Snap only dams within 65 m of the downstream groups' polygons (identical result: a dam snapped to a path group's stream lies within 65 m of that group's polygon), with no prefilter when a path group's polygon is absent; time each step into the result, so the next cloud run names the slow step.
