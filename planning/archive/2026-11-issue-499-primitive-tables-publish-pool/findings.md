# Findings — Backlog move 14: Primitive tables in one shape, and a parallel publish (#499)

## Issue context

**If we do it:** every host's database holds `cabd.dams` in one column layout, so a fresh cloud host passes the host-parity pre-flight, and a province-wide publish takes minutes rather than about 53. **If we never do:** a run with a newly built cloud host is refused before any write ("hosts hold different snapshot primitives"), and each full publish spends most of an hour putting objects one at a time.

Move 14 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge. When the plan finds that a batch, or one of its members, is more than one PR's work, it carries the first piece and files each other piece as its own issue naming move 14, and leaves it out of the backlog file.

## Batch 21: Primitive tables load in one shape

**Why here:** the next provincial run with a new cloud host is refused until it lands; a cloud image swap in the infrastructure repository waits on it.

**Touches:** `data-raw/snapshot_bcfp.sh`, `R/lnk_artifact.R` (the content md5), RUNBOOK §8d.

**Decided at the gate:** which `cabd.dams` layout becomes the standard (the reload layout keeps the recorded md5s valid; dropping before each load gives the first-load layout everywhere and reads `cabd.dams` as changed once against published records); whether the PSCIS tables have the same create-versus-reload difference.

| issue | title |
|---|---|
| #494 | cabd.dams content md5 depends on whether the table existed before the load |

## Batch 22: Publish in parallel, and the public read

**Why here:** both are the publish step of `data-raw/habitat_publish.R`; one full publish measures the first and is the first the second would serve.

**Touches:** `data-raw/habitat_publish.R`, `R/lnk_scenario_export.R` (the version-id reads), RUNBOOK §6d.

**Decided at the gate:** a worker pool in R or the AWS CLI's own parallel transfer; whether #334's public read (an infrastructure change after budget and anomaly alerts) is ready, or #334 stays open on it.

| issue | title |
|---|---|
| #488 | Publish puts objects one at a time: about 2.4 s each, 53 min for a province |
| #334 | Gates before a floodplain item pins a habitat build: run_uid, dirty trees, versioning, public read |

## Exploration at park (2026-11-22)

- `cabd.dams` is the only primitive loaded on ogr2ogr's truncate path (`snapshot_bcfp.sh:240-248`, `-overwrite --config OGR_TRUNCATE YES`). PSCIS views are dropped before every bc2pg attempt and before the WFS fallback (`snapshot_bcfp_lib.sh:126`, `:144`); `modelled_stream_crossings` is `-overwrite` without truncate; `observations` is DROP + CREATE + `-append`.
- The content md5 is compared in three places: the host-parity pre-flight (`.lnk_inputs_agree()`, `R/lnk_artifact.R:602`, through `data-raw/host_inputs.R`), `lnk_downstream_load()` against a build's `log_input` (`R/lnk_downstream.R:525`), and an export's snapshot keys (`R/lnk_export_inputs.R:89`).
- PUBLISH (`data-raw/habitat_publish.R:103-300`) runs one `aws` process per call: a `head-object` ETag check per provenance file (753) and per per-group part (482), a `put-object` per object, then a `head-object` per part, per-group part and dependency map for its VersionId (about 590). `put-object` already returns `VersionId` and `ETag` in its JSON reply, so the version reads after the puts can come from the puts themselves.
- Neither paws nor processx is declared in `DESCRIPTION`. `parallel` ships with R but is not in `Imports`, so a `parallel::` call in `R/` needs it added there (Plan review).

## Phase 1 (2026-11-22, m1, GDAL 3.13.0): what moves `geom`

- **#494's reading was wrong in its cause:** the layout does not depend on whether `cabd.dams` existed. The first ogr2ogr load into a database (the one that creates `ogr_system_tables`) lays its table out `geom` last; every later load puts it second, `OGR_TRUNCATE` or not. A new host's first ogr2ogr load is CABD. Evidence: `data-raw/logs/cabd_shape_494/`.
- So `-overwrite` alone (first tried, simpler) does **not** fix it: in a new database it also gives `geom` last. The plan's staging table plus rebuild is kept. Found only by loading into a brand-new database; in the scratch database every load after the first came out `geom` second.
- ogr2ogr's drop under `-overwrite` takes a dependent view with it silently; `cabd_load()` drops without `CASCADE` first.
- Today's CABD response gives `6f7f44c0…` under the reload layout, equal to this host's recorded md5 (loaded 2026-11-13).
- PSCIS: two bc2pg loads and one into a new database, one md5 (bcdata never creates `ogr_system_tables`). Unmeasured residual: a WFS-fallback PSCIS load is an ogr2ogr load and could take either layout on a new host; its md5 already differs from bc2pg's.
- The "three starting states" live test cannot fail against the old call in a database GDAL has already loaded into; the stub test with a geom-last staging table is the one that discriminates (4 tests fail on the old call, 2 with `CASCADE`).

## Phase 2 (2026-11-22, m1)

- One `aws` call on m1: `aws --version` 0.32 to 0.34 s, a `head-object` on the published manifest 0.55 to 0.63 s (five each, aws-cli 2.34.34). So start-up is about 60 % of a call here; #488's 2.4 s was a cloud host.
- No built root on m1. The published tree (`s3://fresh-bc/habitat/fwa/v1/`, 108 parts 724 MB, 482 per-group parts 212 MB, 753 files 10 MB, the dependency map) was synced down as the seed root for the scratch measurement: a full built root by construction.
- The test stub's first version raced on `versions.json` (concurrent puts, no lock) and failed one run in two; fixed in the stub with `flock`, not in the code under test.
- Mutants: the manifest put sent on the pool with the parts fails 3 tests; the pool's result check removed fails 2.
