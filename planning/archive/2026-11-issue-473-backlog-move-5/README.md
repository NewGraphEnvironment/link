## Outcome

Backlog move 5 (#473) landed as release 0.85.0, with one phase per batch.

Batch 7 changed `lnk_wsg_downstream_check()`:
- It computes its own drainage closure from the outlets it is given.
- It refuses, warns on, or records an override for a downstream group with no FWA streams (#464).
- A closure that errors now refuses instead of passing.
- It snaps only CABD dams within 65 m of the downstream groups' polygons (#461), and records each step's seconds.

Batch 6 changed the habitat export:
- The export carries the species' `access` code, added to v1 additively, with each config's tokens in the manifest (#423).
- The column contract moved to crate as `nge/habitat/fwa/v1/segment` (crate 0.19.0, crate PR #72) (#333).
- PUBLISH refuses builds a consumer could not name or rebuild unless `LNK_PUBLISH_ALLOW` gives a reason (#334).
- PUBLISH asserts bucket versioning and records each part's S3 VersionId, which `lnk_db_load()` and the one-group loader fetch.
- Each run logs a digest of its persisted streams, which the export checks.

The operator settled four questions at the gate: both batches in one PR, the raw integer code, #466 left to its track, and #334 taken whole apart from public read. The plan review's blocker B1 (link's own loader refused a changed v1) settled "additive v1".

The plan review and four code-check rounds found 10 defects between them. Every one was the same mechanism: a contract change written for the author's environment reaching a consumer in another state. The cases were:
- a table that gained the column out of order;
- a gate map missing the removed file;
- an unrecorded dirty flag;
- a crate floor that would have stopped modelling;
- a missing polygon table;
- a loader that ignored versions;
- readers without `s3:GetObjectVersion`.

## Measurement

**#461: where the downstream check's 371 s went.** It did not reproduce on m4:
- The full province (246 groups) took 0.20 s a group.
- A six-group database built with the cloud sessions' own loader (rtj `cloud-env/cloud-env_load-fwa-wsg.py`, groups BULK ADMS SKGT LFRA HARR FRCN) took 0.18 s.

Dropping the stream geometry index reproduces the magnitude. The probe snaps every one of 2,593 CABD dams with a lateral nearest-stream search, and without the index each search is a sequential scan:

| group | before | after (snap narrowed to the downstream polygons) |
|---|---:|---:|
| HARR | 272.8 s | 8.1 s |
| FRCN | 270.9 s | 9.6 s |

Two further measurements:
- A copy of the six groups (103,217 segments) took 12.2 s for 100 dams without the index, and 0.19 s for all 2,593 with it.
- One dam whose cross-referenced blue line is not loaded walks the whole table in nearest-first order: 20 s on 4.9 M rows.

The cloud database's actual cause is not identified. fwapg's `schema.sql` creates the index, so a missing index is shown to produce the cost but not shown to be what happened there. The check's `steps_s` will name the slow step next time.

**Equality:** a sweep of all 246 groups on m4 gave identical status, dams, `wsgs_missing` and note before and after. It covered `fresh_default` and a schema with no barriers (210 pass, 36 warn), plus 3 overrides.

**#464 live:** on the six-group database, BULK, ADMS and UFRA passed before the change and now name their unloaded downstream groups.

**Export round trip:** ADMS and BULK were built from `fresh_default` in 1.5 min.
- A published 2026-11-14 part (CO, Skeena, 338,708 rows) loads with `access` NULL.
- A table without the column gains it.
- On ADMS, `access` equals `streams_access` row for row for BT, CO and CH, with no differences.

## Evidence

The working measurements are in `findings.md` and `progress.md` here. The sweep files and the scratch database `fwapg473` were session-local and are gone. The commands are in `progress.md`.

## Owed

- crate PR #72 merges and is tagged `v0.19.0` before this PR merges (link's CI reads the contract from crate's main; the manifest cites the tag); hosts that export then install crate 0.19.0.
- PUBLISH of the new export (operator's word); the next provincial run re-models to `acc-v6`, and its republish carries the new values and the first `streams_md5`.
- #334's public read: infrastructure-repo tofu after budget and anomaly alerts (operator).
- The pre-run gate runs again before the next provincial run (`R/` changed).

Closed by: PR for branch `473-backlog-move-5-the-habitat-export-s-cont`
