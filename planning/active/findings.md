# Findings — Backlog move 2: Which fish records count, and what each lift rests on (#470)

## Issue context

**If we do it:** one written rule says which records make code 2 and which lift a barrier, alias codes count as their species, and each lifted barrier is published with the records behind it. **If we never do:** code 2 and the lifts follow defaults nobody chose, and knowledge's access tuning re-implements the overrides.

Move 2 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 2: Which records count

**Why here:** one species-code rule read by the filter, the walk and the checks; one `acc` row.

#400 (one written rule for which records make code 2 and the observation breaks: date cut and pooling; the count is decided, one record), #398 (cutthroat alias records reach the observation tables but never make CT read "observed upstream", because the walk tests exact codes) and #425 (count the steelhead and char alias codes SST, WST, ADV, ABT and the two-way codes as their species). Touches one species-code helper read by `R/lnk_pipeline_break.R`, `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_presence_check.R`, `R/lnk_presence_measures.R` and `R/lnk_habitat_validate.R`. Gate: #400's date and pooling rule; #425's two-way codes (BT/DV, DV/BT, RB/CT). One `acc` row and a release; outputs move at the next provincial re-model.

knowledge waits on it: #400 decides which records lift a barrier and make code 2, which NewGraphEnvironment/knowledge#178 (move 9, tuning on link's access with leave-one-out, NewGraphEnvironment/knowledge#131) reads.

| issue | title |
|---|---|
| #400 | Decide what counts as a known fish record for "observed upstream" |
| #398 | Cutthroat alias records never make CT read "observed upstream" |
| #425 | Count steelhead and char alias codes (SST, WST, ADV, ABT, BT/DV) as their species |

## Batch 3: What each lift rests on

**Why here:** all edit `R/lnk_barrier_overrides.R`; the same `acc` row as batch 2.

#434 (each build publishes the barriers each observation override lifted, with the records and the rule behind each, checked against `access_<sp>`), #426 (lifts count records dated exactly 1990-01-01, which bcfishpass leaves out; RUNBOOK's "no date floor" line is wrong), #427 (lift a natural barrier on fewer than five salmon records in `default`, or a distance or date rule) and #236 (DV as BT access evidence: what remains is multi-rule and group-scoped overrides; the dictionary and region-scoped pooling shipped). Touches `R/lnk_barrier_overrides.R`, `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `inst/extdata/configs/default/parameters_fresh.csv`, `data-raw/study_area_verify.sql`, RUNBOOK §5. Gate: `>=` or `>` per bundle; #427's threshold for salmon, GR and KO; #236 cut to the overrides or closed. The same `acc` row as batch 2.

knowledge waits on it: #434 is what NewGraphEnvironment/knowledge#178 (move 9) reads so that NewGraphEnvironment/knowledge#131's leave-one-out gates on link's own lifts rather than re-implementing `lnk_barrier_overrides()`.

| issue | title |
|---|---|
| #434 | Publish the barriers each observation override lifted, with the records behind each |
| #426 | Lifts count records dated exactly 1990-01-01, which bcfishpass leaves out |
| #427 | Lift a natural barrier on fewer than 5 salmon records in default |
| #236 | Research: DV as BT access evidence — regional scope + multi-rule observation overrides |

## Found at plan time (2026-11-16)

- **bcfishpass drops CT alias records at its filter** (`model/01_access/sql/load_observations.sql`,
  `smnorris/bcfishpass@620dbe4`, unchanged at `3bd2824`): `array[o.species_code]::text[] && wsg_spp.species_codes`
  tests the raw code, and `wsg_spp` holds only `CT`, so the `species_code_remap` CTE that maps
  `CCT`, `ACT`, `CT/RB` to `CT` renames only records already coded `CT`. link's
  `.lnk_pipeline_break_obs_species()` adds the three aliases for every bundle. To confirm on the
  reference DB (Phase 1).
- **Lifts and code 2 already read different species lists.** Lifts read `observation_species`
  (raw codes, e.g. default BT `BT;DV`, CH `CH;CM;CO;PK;SK`); the walk tests `toupper(sp) %in%`
  each segment's distinct upstream codes (`R/lnk_pipeline_access.R:480`).
- **`top_per_species` groups by raw `species_code`** (`R/lnk_pipeline_break.R:177`), so folding
  aliases also merges their tops into the species' top on each line.
- **The acc spec** (`R/lnk_vocabulary.R`, `.lnk_vocabulary_spec_acc()`) hashes `cfg$species`,
  `observation_upstream`, the access classes, presence groups, the parameters_fresh access
  columns and the presence table. The pooling tracker and any date key are not in it yet.
- **The `bcfishpass` bundle declares no `species_pooling.csv`;** only `default` does.
- **`barrier_overrides` is persisted** (`R/lnk_persist_init.R:171`, `R/lnk_pipeline_persist.R:108`)
  and copied by consolidate (`data-raw/schema_consolidate.R:237`); nothing records the records
  behind a lift.
- **An undated record never counts toward a lift:** NA `observation_date_min` becomes
  `1900-01-01` and `observation_date >= '1900-01-01'` is NULL for a NULL date
  (`R/lnk_barrier_overrides.R:144`), against RUNBOOK §5's "no date floor" (line 628).

## Errors Encountered

| Error | Resolution |
|-------|------------|
