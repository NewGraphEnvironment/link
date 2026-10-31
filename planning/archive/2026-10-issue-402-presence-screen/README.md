## Outcome

Part 2 of #402. The operator's first review of the 351 flagged presence cells set out what a fish record must survive before it counts: historic access (salmon above barriers that were never passable, kokanee with no lake to rear in), species range, transcription errors, implausible elevations and gradients, and loneliness only after the rest. The plan review showed that three of the planned location screens repeat bcfishobs's own matching, that "above an unlifted barrier" is circular for absent cells (lifts count only present species' records), that Bonnington Falls is not in the barrier table, and that ceilings taken from the records' own percentiles are circular. The operator chose **measures now, verdicts later**. `.lnk_presence_measures()` (`R/lnk_presence_measures.R`) measures every record and judges none: own 50k code outside its group, elevation, major drainage, the nearest blocking natural barrier below with counting records of the species' lift pool above it (presence ignored), a rearing lake for kokanee, lake and known-sockeye-lake records, main stem, and a historical distribution zone. `.lnk_presence_cell_measures()` rolls them up per cell with distinct sites, waterbodies and years, and each tracker story of a cell with its own records carries them. The verdict function first committed was removed. Literature, range layers and a native-range table go to a second PR.

## Measurement

- Measures over all 375,962 records in about 60 s on local fwapg; 6,111 cells with a counting record.
- 2,574 records are filed under a group their own 50k code does not run through.
- Recall on the 67 `data_error` records of `observation_exclusions.csv`: a blocking barrier below with at most 2 class records above catches 36; elevation above 1,400 m catches 21 (10 more); a gradient of 0.25 or more catches 6 (none more). 46 caught, 21 with no geometric tell (likely misidentified rainbow, misplacements within reachable water). Before round 1 this read 47 / 20.
- Absent-recorded cells (327): 117 on a single waterbody (153 when bcfishobs's group-level stream identifier counted as a waterbody, 121 when the record's own 50k code did), 94 on a single site. Anadromous (168): 12 with every record above a blocking barrier, 6 of them with at most 2 class records above; 21 recorded only on a through-flowing main stem; 59 with no record on a zoned stream; 21 in the Columbia, Mackenzie and Yukon. Kokanee (137): 123 with lake records, none with every record above a barrier with no lake.
- 375,962 records sit on 179,815 species-locations.

Wrong turns kept: `fwa_downstream()`'s argument order was reversed in the first prototype (every ADMS chinook read blocked); FWA lake polygons carry no local code, so the first lake test found none; a UTM zone screen was built and dropped (tautological); the lake behind a lake record was first read only from the matched segment, which misses 17,147 lake records snapped outside their polygon (BOWR KO's 54 Bowron Lake records).

## Evidence

`data-raw/logs/presence_check_402/` (`measures.csv`, `recall.csv`, `evidence/`, `stamp.txt`; its README indexes it). Reviews: `review-plan.md`, `review-round1.md` to `review-round3.md` in this directory.

## Owed

- The decision session: the operator sets the screen's rules from the measures and decides each class and the residue rows in the tracker.
- Second PR: literature (McPhail 2007 into Zotero, `/lit-search` store), "Provincial Fish Ranges - Watersheds" (BCGW custom download; codes 0/4/5/6/9, with 1/2/8 overwritten from records), E-Fauna probe, and a native-or-introduced table per species by major drainage.
- A separate PR applies the decisions to `wsg_species_presence.csv` (notes naming the rule on each changed cell), with a new `acc` vocabulary row, a version bump and a provenance re-stamp; the groups re-model at the next provincial run (#377).
- Whether the screen should also gate the pipeline's records (breaks, code 2, lifts): an issue, since it moves outputs.
- The pre-run gate (#372) re-runs if `R/` files on the modelling path change (this plan adds a new file only; `pretest_inputs.csv` gets a `none` row).

Closed by: PR (link#402 stays open for the decisions)
