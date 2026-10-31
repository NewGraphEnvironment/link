# Task: Check each group's species presence against its fish records (#402), part 2: screen the records before deciding cells

## Context

PR #424 (v0.73.1) flagged 351 presence cells on a count rule: one record since 1950. The operator's review (2026-10-31) says a count is not enough to decide them. A record has to be screened before it counts as evidence:

- **Historic access.** Salmon above a barrier that was never passable, with no lake big enough for rearing (KO), are errors. Kootenay Lake is the counter-example: fish reached above Bonnington Falls before the end of the last ice age. So "above a falls" needs history, not just geometry.
- **Species range.** A lone CCT in the Elk is an error; a lone DV in KOTL is a bull trout. Single records are judged against species and place.
- **Transcription errors.** Many UTMs were typed wrong. Screen for records whose point disagrees with their own waterbody (50k watershed code, gazetted name), and for typos.
- **Implausible places.** Fish above an elevation a species does not reach, or on 25–30 % gradients, are likely wrong.
- **"Lone record" is a reason only after the other screens,** and most such cells likely stay absent with a note.
- **Evidence beyond bcfishobs:** user habitat classification, FISS, Provincial Fish Ranges and historical distribution layers (BC Data Catalogue), E-Fauna BC if obtainable, McPhail (2007) and other respected literature.

This branch builds the screen and the evidence table. Deciding cells happens after, in a discussion with those numbers, then a separate PR applies them.

## What exists to reuse

- `R/lnk_presence_check.R`: `.lnk_presence_check()` (counts, releases, exclusions, CT aliases, pooling, story), `.lnk_presence_story()`, `.lnk_presence_review_merge()`. The screen feeds it per-record flags; the counting stays.
- `data-raw/wsg_species_presence_check.R`: the driver, its SQL cross-check and the log directory `data-raw/logs/presence_check_402/`.
- `bcfishobs.observations` (local fwapg) carries `utm_zone/easting/northing`, `new_watershed_code` (the record's own 50k code), `gazetted_name`, `waterbody_identifier`, `match_type` (A–E; 181,420 A, 122,443 D, 31,726 C, 21,890 B, 18,483 E), `distance_to_stream`, `wscode/localcode`, `blue_line_key`, `downstream_route_measure`.
- `fresh_default.barriers` (241 groups): every natural barrier with `blocks_species` (falls 3,294; gradient classes per species; user-definite 226), so "a natural barrier that blocks this species lies downstream" is one `fwa_downstream()` join, province-wide.
- `fresh_default.barrier_overrides`: existing lifts (only for species the group models).
- FWA: `fwa_stream_networks_sp` (Z in geometry, gradient, `gnis_name`, `stream_order`), `fwa_lakes_poly` / `fwa_manmade_waterbodies_poly` (lake area for KO rearing).
- BC Data Catalogue: "Provincial Fish Ranges - Watersheds" (`4e66ac86-aec6-4d79-8462-9e8daf0c0339`), "BC Historical Fish Distribution - Zones (50,000)" (`b665c14f-3d29-414b-b232-cba2a9c3cc55`), via `bcdata`.

## Revised after the plan review (operator, 2026-10-31)

The review (`review-plan.md`) showed three of the location screens repeat what bcfishobs's matching already did, that "above an unlifted barrier" is circular for absent cells, that Bonnington Falls is not in the barrier table, and that percentile ceilings are circular. The operator chose: **measures now, verdicts later.** This PR adds per-record measures and a per-cell table, with no pass/fail rules. The rules are set in the decision session from these numbers. Literature, range layers and a native-range table by major drainage go in a second PR. The verdict function first committed (`53ae5cd7`) is removed.

## Phase 1: Per-record measures (SQL in R/)

- [x] `R/lnk_presence_measures.R`: `.lnk_presence_measures(conn, zones, species_barrier, lift_pools, sockeye_lakes, excl_keys, incl_keys, year_min, year_now)` builds session temp tables and returns one row per bcfishobs record with:
  - `code_other_group`, from the groups the record's own 50k code runs through (`fwa_streams_20k_50k.watershed_group_code_20k`): TRUE where it is not the group the record is filed under; NA where the code is not in the lookup);
  - `elevation_m`: `ST_Z(geom)` (the stream's Z at the match; 0 read as NA);
  - `major_drainage`: the first segment of the record's watershed code;
  - `barrier_below`: kind of the nearest natural barrier below (FALLS, GRADIENT, USER_DEFINITE) that blocks the species, for anadromous species and KO; NA where none, and NA too in groups holding no barrier rows (flagged `barriers_known` FALSE);
  - `n_class_above`: records since `year_min` of the species' lift pool (`parameters_fresh.csv` `observation_species`), presence ignored, exclusions and releases out, above that barrier;
  - `rearing_lake_ha` (KO): the largest lake above that barrier, lakes placed by their stream segments;
  - `lake_record` (record matched to a lake, `waterbody_type`), `known_sockeye_lake` (its lake is in `dfo_known_sockeye_lakes.csv`);
  - `through_main_stem`: the record's blue line continues upstream outside its group;
  - `in_hist_zone`: its 50k code lies in a historical distribution zone of the species (`presence_evidence_load.R`; pre-2001 FISS, so not independent of FISS records, stated as such);
  - `gradient`: the segment's, reported only.
- [x] Live test (skips without the database): the barrier test's argument order (a point above a falls reads it, one below does not). The golden values became the driver's SQL recount of the measures for PARS, ADMS and ALBN (106 cells, all agree, every run), and the KO lake placement is checked by its counts (of 3,374 counting KO records above a blocking barrier, 42 have no lake above it; every one read no lake before the fix that places lakes by their segments). After code-check rounds 1 and 2 the recount reads bcfishobs, FWA and the zones CSV directly (not the measures' tables), writes the barrier test from the barrier's side, and covers counting records, sites, waterbodies, years, own code in another group, barrier below and historical zone; main stem, lakes, kokanee lakes, class above and elevation are not recounted.

## Phase 2: The per-cell table

- [x] `.lnk_presence_cell_measures(m)` (pure R, tested on fixtures): per group and species, distinct sites, waterbodies and years among counting records; records whose code lies in another group; records above a blocking barrier and the most records of the class above any one of them; KO records with and without a rearing lake; lake and main-stem records; records in a historical zone; elevation range.
- [x] The driver joins it to the flagged cells (`disagreements.csv`) and writes every cell with a counting record (`measures.csv`), extends the story ("1 waterbody", "2 records, both filed under another group's code", "above a falls with 1 record of its class above it"), and re-seeds pending tracker stories (decided rows untouched).
- [x] Recall set: the 67 `data_error` rows in `observation_exclusions.csv` with their measures (`recall.csv`): which measures would have caught each, so the session sets rules knowing what they catch.
- [x] SQL recount of three groups' measures, independent of the R aggregation: seven measures, from bcfishobs, FWA and the zones CSV (after code-check rounds 1 to 3).

## Phase 3: Write-up

- [x] `research/species_presence.md`: each measure, what it can and cannot see (the review's findings), the per-class picture for the decision session (KO, salmon and steelhead, single waterbodies, the 24 present cells). RUNBOOK §5 extended; CLAUDE.md status entry; the NEWS line and version are `/gh-pr-merge`'s, as in part 1.

## Decided at the gate (operator, 2026-10-31)

- Screen records before deciding cells: historic access, species range, transcription, elevation and gradient, then loneliness as a reason only after the others.
- After the plan review: measures now, verdict rules set in the decision session; literature, range layers and the native-range table in a second PR.
- Measure for salmon and steelhead: reachability, main stem against tributary, independent evidence (UHC, FISS, range layers, E-Fauna if possible, literature).
- KO: decided after the historic-access homework, not added wholesale.
- Single pre-1990 records: species-dependent; likely absent with a note, decided after the screen.
- The 24 present-but-unsupported cells: read together in the decision session.

## Owed at the end (reported, done after merge)

- [ ] The decision session: the operator sets the screen's rules from the measures and decides each class and the residue rows in the tracker.
- [ ] Second PR: literature (McPhail 2007 into Zotero, `/lit-search` store), "Provincial Fish Ranges - Watersheds" (BCGW custom download; codes 0/4/5/6/9, with 1/2/8 overwritten from records), E-Fauna probe, and a native-or-introduced table per species by major drainage.
- [ ] A separate PR applies the decisions to `wsg_species_presence.csv` (notes naming the rule on each changed cell), with a new `acc` vocabulary row, a version bump and a provenance re-stamp; the groups re-model at the next provincial run (#377).
- [ ] Whether the screen should also gate the pipeline's records (breaks, code 2, lifts): an issue, since it moves outputs.
- [ ] The pre-run gate (#372) re-runs if `R/` files on the modelling path change (this plan adds a new file only; `pretest_inputs.csv` gets a `none` row).
- [x] The evidence and any later parameter file stay undeclared under `files:` (config_hash; review AC2).

## Validation

- [x] Tests pass (`devtools::test()` at `2e531774` and again at `ba81dc33`: 79 files, 0 failed, 0 errors), new files lint clean, `devtools::document()` writes nothing
- [x] `/code-check branch`: three rounds (review-round1.md to review-round3.md), ended by round 3's enumeration; its five findings fixed in 0041fd12 and verified by direct reads, not by a fourth round
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

Verification: unit tests on the cell aggregation with defects restored; live golden tests on one group for the SQL; the 67-row recall set; an SQL recount of three groups; rerun reproducibility.

Branch: `402-screen-fish-records` (the first PR's branch name is taken by its merged history).

Approve runs every phase to the PR. To park, reject with `park`: the baseline is written and pushed, nothing more.
