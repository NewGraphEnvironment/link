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

## Phase 1: A per-record screen

- [ ] `.lnk_obs_screen()` in a new `R/lnk_obs_screen.R`: given records (the check's columns plus geometry-derived fields from the driver), returns one row per record with a flag per screen and a single `screen` verdict (`pass` | `doubt` | `fail`) with its reasons. Pure R over a data frame, so it is tested without a database. The screens:
  - **Location:** weak match (`match_type` C/D/E, `distance_to_stream` above a set distance); the record's own `new_watershed_code` disagrees with the matched stream's 50k code; `gazetted_name` disagrees with the matched stream's `gnis_name` (normalised).
  - **Transcription:** UTM zone inconsistent with the point's longitude; isolation (distance to the nearest other record of the species) beyond a set distance, reported, not failed, on its own.
  - **Reachability:** a natural barrier blocking the species lies downstream, with no lift (`barrier_overrides`), counted by kind (falls, gradient, user-definite). For KO, also whether a lake of at least a set area lies at or upstream of that barrier and downstream of the record's catchment (rearing lake).
  - **Place:** record elevation (stream Z at the measure) and segment gradient against per-species ceilings.
  - **Living there or passing through:** on a line that flows into the group from another group (through-flowing main stem) or on a tributary.
- [ ] The thresholds live in a bundle CSV, `configs/default/obs_screen_parameters.csv` (species, elevation ceiling, gradient ceiling, isolation distance, KO lake minimum ha, match distance), each row with its source. First values derived from the records' own distribution (for example the 99.5th percentile of elevation for records that pass every other screen) and flagged `provisional`, for the operator to set.
- [ ] Tests on fixtures: each screen in both directions, verdict combination, NA handling (no geometry, no 50k code), a known DV-in-pooled-region record reading as BT evidence; then restore each defect and watch its test fail.

## Phase 2: Evidence beyond bcfishobs

- [ ] `data-raw/presence_evidence_load.R`: load "Provincial Fish Ranges - Watersheds" and "BC Historical Fish Distribution - Zones (50,000)" into a local schema with `bcdata`, recording dataset id, retrieval date and row count; summarise per group and species (in range, not in range, no data). If the layers prove too coarse or empty for some species, say so in the research file rather than force them.
- [ ] Per group and species: user habitat classification rows and FISS sites (where `LNK_KNOWLEDGE_DIR` covers the group).
- [ ] Probe E-Fauna BC for a downloadable fish atlas; record what is and is not obtainable.
- [ ] Literature through the Zotero skills, not the MCP (`/zotero-api` Web API with `~/.zotero-api-key`; `/lit-search` for a ragnar store over the PDFs). The group library already holds McPhail & Baxter 1996 (`SUENJEU8`, bull trout), McPhail & Carveth 1993 (`44PTFGQ3`, field key), Roberge et al. 2002 (`B3TYJ9I9`, life history of BC and Yukon fishes) and Ericksen et al. 2009 (`XBVCXFAG`, Kootenay kokanee; two duplicates `BCBNSQ7B`, `WZJXVVJL`). Add McPhail 2007 *The Freshwater Fishes of British Columbia* (absent) and the zoogeography literature on post-glacial access, build a store over them, and record per species the native range limits and known historic-access cases (Kootenay above Bonnington Falls) in `research/species_presence.md`, each with its citation key.

## Phase 3: The cell table for the discussion

- [ ] Extend the driver: screen every record, then run `.lnk_presence_check()` on records that pass, and write per cell the counts by verdict and reason, the reachability and main-stem split, and the evidence columns. Extend the story with the screen's reasons ("2 records, both above Bonnington-type falls with no rearing lake"; "1 record, its 50k code is another stream").
- [ ] Re-seed the tracker's pending stories (decided rows untouched); report how many of the 351 flags change once failed records are dropped.
- [ ] `research/species_presence.md`: the screen, its thresholds, what each evidence source covers, and the per-class picture for the discussion (KO, salmon and steelhead, single records, the 24 present cells).
- [ ] RUNBOOK §5 subsection extended; CLAUDE.md status entry; NEWS line.

## Decided at the gate (operator, 2026-10-31)

- Screen records before deciding cells: historic access, species range, transcription, elevation and gradient, then loneliness as a reason only after the others.
- Measure for salmon and steelhead: reachability, main stem against tributary, independent evidence (UHC, FISS, range layers, E-Fauna if possible, literature).
- KO: decided after the historic-access homework, not added wholesale.
- Single pre-1990 records: species-dependent; likely absent with a note, decided after the screen.
- The 24 present-but-unsupported cells: read together in the decision session.

## Owed at the end (reported, done after merge)

- [ ] The decision session: the operator decides each class and the residue rows in the tracker, with the screened table in hand.
- [ ] A separate PR applies the decisions to `wsg_species_presence.csv` (notes naming the rule on each changed cell), with a new `acc` vocabulary row, a version bump and a provenance re-stamp; the groups re-model at the next provincial run (#377).
- [ ] Whether the screen should also gate the pipeline's records (breaks, code 2, lifts): an issue, since it moves outputs.
- [ ] The pre-run gate (#372) re-runs if `R/` files on the modelling path change (this plan adds a new file only; `pretest_inputs.csv` gets a `none` row).

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()`, `devtools::document()`
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: unit tests with mutation checks on every screen; an SQL recount of three groups' screened counts (as the first PR did); hand-checked samples per reason (ten records each for watershed-code disagreement, UTM zone, above-barrier, elevation) read against their source records to confirm the screen catches errors and not real fish; rerun reproducibility of every count.

Branch: `402-screen-fish-records` (the first PR's branch name is taken by its merged history).

Approve runs every phase to the PR. To park, reject with `park`: the baseline is written and pushed, nothing more.
