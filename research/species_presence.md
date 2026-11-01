# Species presence: which groups each species is modelled in

**Verified:** 2026-11-01 · **Issues:** #402 (this), #292 and #153 (the presence groups), #290 (pooling), #398 (CT aliases in code 2), #425 to #427 (follow-ups) · **Produced by:** `.lnk_presence_check()` (`R/lnk_presence_check.R`) and `.lnk_presence_measures()` (`R/lnk_presence_measures.R`) through `data-raw/wsg_species_presence_check.R` on local fwapg, bcfishobs 375,962 rows (newest valid date 2026-10-10) → `data-raw/logs/presence_check_402/`; historical zones from `data-raw/presence_evidence_load.R` (retrieved 2026-10-31) · **Status:** first review done 2026-11-01, provisional: 111 cells added, 10 removed, 76 kept, 154 pending (141 of them kokanee and rainbow, waiting on #432); see "The first review"

## What a presence cell decides

`default`'s `overrides/wsg_species_presence.csv` is hand-authored: 246 groups by 13 species, and one `notes` cell per group. A cell marked `t` makes a species the bundle models (`default`: BT, CH, CM, CO, PK, SK, ST, WCT, KO, RB, GR) part of the model in that group. A mark for CT or DV, which `default` does not model, keeps that species' records (DV records feed the BT lifts; CT records feed nothing) and promotes the CT, DV and RB group, so RB breaks the streams where its own cell is unmarked. The pipeline reads the table two ways:

- **As written.** The observation filter keeps a record only where its own group marks its species present (`.lnk_pipeline_break_obs_species()`), and `lnk_pipeline_species()` picks the species to classify. A record of an unmarked species reaches no observation break, no code 2 and no barrier lift, in its own group or any other: the lifts count `<schema>.observations_province`, where each record is kept by its own group's row.
- **Promoted, for breaks only.** `lnk_presence()` makes a whole group present when one member is (salmon: CH, CM, CO, PK, SK; and CT, DV, RB). Only `.lnk_pipeline_prep_minimal()` reads that, and only for species the bundle models (`default`: BT, CH, CM, CO, PK, SK, ST, WCT, KO, RB, GR): a promoted species' barrier positions break the streams. Classification, access and mapping code follow the cell as written (`lnk_pipeline_species()`); in `fresh_default`, ADMS PK is promoted by its salmon and has no `access_pk` or `mapping_code_pk` on any of its 39,425 segments.

So a cell can be wrong in two ways that matter: a species modelled, or its records kept, where nothing shows it lives there, and a species recorded in a group whose records the pipeline throws away.

## The rule

A cell is supported by **at least one record dated 1950 or later** (operator, 2026-10-30). The first answer was five records; it was revised before any code, because a single fish caught above where the species had been recorded is real evidence, and it is often the only one. The count is reported, never judged: each flag carries the number of records, the years and the sources, so one 1962 stray reads differently from a run of forty.

A record counts when it:

- is of the species, with `CCT`, `ACT` and `CT/RB` read as `CT`, as in link's pipeline (bcfishpass's own filter tests the raw code and so does not admit them);
- is not excluded by `observation_exclusions.csv` (`data_error` or `release_exclude`), the one helper the pipeline and the validator also use (`.lnk_observation_exclusion_keys()`);
- is not a release, tagged as bcfishpass tags one (`smnorris/bcfishpass@620dbe4`, `load_observations.sql`): its `source` up to the first colon is `Releases Database:`, its `source_ref` names the BC release records database or stocking, or its exclusions row sets `release_include`. A stocking record shows fish were put there, not that a population lives there. The source test alone marks 74,495 of the 375,962 records, and the `source_ref` tests bring it to 75,739 before the `release_include` rows; bcfishpass tags them without dropping them;
- is dated 1950 or later; a year before 1850 or after the current year (the source holds 1007 and 9999) is undated, and an undated record does not count;
- or is a record of another species that `species_pooling.csv` pools into it in that group (DV into BT in the Fraser, Mackenzie, Columbia and the Skeena above Hazelton), with the row's year limit. The pipeline does not apply `species_pooling.csv`: its observation filter keeps a DV record only where DV is marked, and counts it toward no BT cell (the BT barrier lifts do count DV records, through `parameters_fresh.csv`'s `observation_species`). So a BT flag resting on DV records alone would, if accepted, model BT in a group with no BT record; its story says so.

The check judges each cell as written and reports, beside it, whether promotion makes the species present and through which members.

## What it found

351 of 3,198 cells are flagged (`summary.csv`):

| species | cells present | present, no record | absent, recorded | of those, one record | of those, present through their group |
|---|---|---|---|---|---|
| BT | 158 | 1 | 8 | 2 | 0 |
| CH | 125 | 3 | 20 | 9 | 12 |
| CM | 55 | 1 | 22 | 12 | 17 |
| CO | 100 | 1 | 21 | 7 | 17 |
| CT | 112 | 5 | 2 | 2 | 2 |
| DV | 194 | 3 | 0 | 0 | 0 |
| GR | 82 | 1 | 1 | 1 | 0 |
| KO | 4 | 1 | 137 | 11 | 0 |
| PK | 60 | 1 | 32 | 5 | 32 |
| RB | 210 | 2 | 1 | 1 | 0 |
| SK | 84 | 2 | 39 | 9 | 34 |
| ST | 79 | 3 | 34 | 17 | 0 |
| WCT | 16 | 0 | 10 | 6 | 0 |

**Present with no record (24).**
- 12 cells have no record of the species at all. Six are UDEN's salmon and steelhead, whose note reads "salmon/steelhead added as test for Ulkatcho". KTSU's CH and ST note "updated based on PSE spawning data": presence known from outside bcfishobs, which the check cannot see.
- The other 12 rest only on releases (8) or undated records (4). LPRO's RB has 90 records, every one a release. UEUT's BT, CT and DV each have two undated records.

**Absent with records (327).**
- **The count runs from one to hundreds.** 82 cells have one record, 89 have two to four, and 156 have five or more. 238 have a record since 1990.
- **Kokanee are most of the large cells.** KO is marked in four groups and recorded in 137 more (median 11 records), and they are 92 of the 156 cells with five records or more. 52 of the 137 also hold release records, which do not count, so each flag rests on fish caught or seen; whether a lake holds a population is the review's call.
- **114 absent cells are promoted by their group, which models none of them.** All 32 PK cells, 34 SK, 17 CM, 17 CO and 12 CH are made present by another salmon member: their barrier positions break the streams, but the species is not classified and gets no access or mapping code, and the filter drops its records. The other 2 are CT cells, promoted through the CT, DV and RB group, which changes nothing, since `default` does not model CT.
- **Steelhead's 34 are not made present by any group.** In 17 of them a single record is all there is.
- **The Mackenzie keeps its notes' story.** Of its 29 flags (26 absent with records), 7 are salmon or steelhead, every one from one or two records dated 1969 to 1998 (CM in BEAV, LIAR, LMUS and ULRD; SK in MESI; ST in TURN; CH in ULRD). These are rows the "Mackenzie basin" note leaves absent on purpose; the review decides whether a record stands.
- BT's 8 flags all rest on pooled DV records alone.

## What the check does not count

132,502 records sit under codes the table has no column for (157 codes, per group in `groups.csv`), most of them other fish. Eight name a table species, and the pipeline drops those records today, because its filter matches codes exactly:

| code | name | records | would count as |
|---|---|---|---|
| SST | Steelhead (Summer-run) | 404 | ST |
| WST | Steelhead (Winter-run) | 358 | ST |
| ADV | Dolly Varden (Anadromous) | 79 | DV |
| BT/DV | either, suspected BT | 57 | BT |
| DV/BT | either, suspected DV | 52 | DV |
| RB/CT | either, suspected RB | 23 | RB |
| ABT | Anadromous Bull Trout | 12 | BT |
| ` RB` | (leading space) | 1 | RB |

The check mirrors the pipeline, so it judges what the model reads. Counted as their species, they would change 4 flags (`alias_sensitivity.csv`): FINA ST, UFRT ST and MFRA BT would become absent but recorded, and VICT DV would become supported. Whether the pipeline should read these codes is the steelhead and char counterpart of #398, filed as #425; it is not part of #402.

## Measures before a record counts

The operator's first review of the flags (2026-10-31) set out what a record must survive before it counts: a salmon above a barrier that was never passable, with no lake to rear in, is an error; Kootenay Lake is the counter-example (fish reached above Bonnington Falls before the end of the last ice age); a lone record means different things by species and place (a lone cutthroat in the Elk is an error, a lone DV in KOTL is a bull trout); many UTMs were typed wrong; fish rarely live above certain elevations or on 25 to 30 % gradients; and loneliness is a reason only after the rest. A plan review showed which of those the data can test and which it cannot, so the check now **measures** each record and **judges** none. The rules are set in a decision session from these numbers.

What each measure is, per record (`.lnk_presence_measures()`), and what it cannot see:

| Measure | What it is | Limits |
|---|---|---|
| Filed under another group's code | The record's own 50k watershed code runs through no part of the group it is filed under (`fwa_streams_20k_50k`). 2,574 records. | Comparing the record's code with the matched stream's repeats bcfishobs's own matching (A, C and D are matched by that code), so this is the location test left. A UTM typo large enough to move a record off its stream leaves it unmatched, outside bcfishobs; a UTM zone test is tautological (bcfishobs builds the point from the record's own zone; the 98 records whose zone disagrees with their longitude all sit within about a degree of a zone edge). |
| Elevation | The point's Z, the matched stream's elevation (0 read as NA). | A lake record carries the lake surface; a misplaced record carries the wrong stream's. One ceiling for the province ignores geography, and a ceiling from the records' own percentiles flags a fixed share whether or not any are errors. |
| Natural barrier below | For CH, CM, CO, PK, SK, ST and KO: the kind of the nearest falls, gradient or user-definite barrier below that blocks the species, and the counting records of the species' lift pool above it, presence ignored. | Lifts are not read: they count only records of species a group marks present, so they cannot judge an absent cell. Bonnington Falls is not a falls row (the lower Kootenay holds dams and salmon-class gradient rows), and barriers outside BC (Kootenai Falls, Grand Coulee) are absent, so historic access needs a native-range table, not geometry. CHUK, HAYR, KCHL, SAHT and SHEK hold no barrier rows (`barriers_known`). |
| Rearing lake (KO) | The largest lake above that barrier, a lake placed by the stream segments through it (FWA lake polygons carry no local code). Of the 3,374 counting KO records above a blocking barrier, 42 have no lake above it, in 15 of 140 KO cells. | The minimum lake size is the operator's, not the data's. |
| Lake, known sockeye lake | bcfishobs matched the record to a lake; its lake is in `dfo_known_sockeye_lakes.csv`. | |
| Main stem | The record's blue line continues upstream outside its group: a fish possibly passing through. | Side channels carry their own blue line and read as tributaries. |
| Historical zone | The record's 50k code carries a "BC Historical Fish Distribution - Zones (50,000)" reach of the species. | Pre-2001 FISS, the same source as bcfishobs's FISS records, so not independent; 49 of the 67 known errors sit on a zoned stream. |
| Sites, waterbodies, years | Distinct per cell. A waterbody is a lake's or wetland's own identifier, else the blue line the record is matched to: bcfishobs gives stream records a group-level `waterbody_identifier`, not one per stream, and a record's own 50k code can name the main river it was filed under rather than the stream it is on. | Repeat surveys put many records on one site: 375,962 records sit on 179,815 species-locations (cutthroat aliases folded; a site is a blue line and metre), so a count of records overstates the evidence. |

**What the measures see of known errors.** `recall.csv` holds the 67 `data_error` records of `observation_exclusions.csv`. 36 sit above a blocking natural barrier with at most 2 records of their class above it; 21 sit above 1,400 m, 10 of them not caught by the barrier; 6 sit on a segment gradient of 0.25 or more, all already caught by one of the other two. So 46 are caught by the barrier or elevation measure. The other 21 have no geometric tell: steelhead that were likely misidentified rainbow, and points the source places elsewhere within reachable water (SETN records that belong in the Yalakom or the Fraser delta). Every one of the 67 has its own code in its own group. So these three measures are the candidates for rules; the rest are context.

**What the flagged cells look like.** Of the 327 absent-recorded cells, 117 rest on a single waterbody and 94 on a single site. Of the 168 anadromous ones, 12 have every record above a blocking barrier (6 of them with at most 2 records of the class above), 21 are recorded only on a main stem flowing through the group, 59 have no record on a zoned stream, and 21 lie in the Columbia (11), Mackenzie (7) and Yukon (3), where native range decides. Of the 137 kokanee cells, 123 have lake records and none has every record above a barrier with no lake (15 have some). The story of each cell with records of its own species carries its measures: 319 of the 351 rows. The other 32 carry none: the 24 present cells with no counting record, and 8 BT cells whose only evidence is DV pooled into them.

**Still to come** (a second PR): McPhail (2007) and the zoogeography literature through the Zotero skills, "Provincial Fish Ranges - Watersheds" (a BC Geographic Warehouse custom download whose codes 1, 2 and 8 were overwritten from the records), the E-Fauna probe, and a native-or-introduced table per species by major drainage.

## The first review (2026-11-01)

The operator set the record rules from `measures.csv` and `recall.csv`, then decided the cells in batches. Every call is provisional, and each decided tracker row's story opens with its reason. The session's log is `data-raw/logs/presence_check_402/decision_session/decisions.md`.

**Record rules.**
- **Barriers:** a salmon or steelhead record does not count above a blocking mapped falls or hand-entered barrier with at most one other record of its lift pool above it: 216 records, catching 5 of the 37 known errors that have a count. Records above a modelled gradient barrier still count (1,004, 613 of them coho). Dropping them would assume the 15 and 20 % access gradients, and those records are the evidence that could test them. They are evidence for a review of where the access gradients come from. Applying the rule to every barrier would have caught 36 of the 37, by assuming the gradients were right.
- **Elevation:** no rule. 1,400 m was chosen from where the known errors sit, not from biology. The 19 records above it that were not known errors were judged one by one: 16 Sustut records count (one lake at about 1,450 m and its streams, four species, 10 surveys from 1975 to 2001, no barrier below). KOTL steelhead is likely a rainbow. The MESI sockeye record is a Sustut survey placed across the divide. The GUIC chinook record is placed in the headwaters by its permit's own coordinates, for a salvage near the mouth (`decision_session/guic_ch_misplaced.md`).

**Cells.** The 168 salmon and steelhead cells marked absent but recorded were sorted by the evidence left after the rules:
- **Strong** (3 or more sites, 2 or more waterbodies, a record since 1990, none above a modelled barrier): 39, all added.
- **Some** (2 or more sites): 55, all added. Six are flagged to recheck: pinks in ADMS and DOGC, sockeye in MCGR, MORK and UFRA, and chinook in MUSK.
- **One site:** 50. 17 with a record since 1990 were added. 10 recent ones were not, because the species is unusual that far inland (chum in HORS and STHM, pinks in LSAL and WILL, coho in FRAN, STUR and CHES, sockeye in BONP, LNIC and COTR). 23 with nothing since 1990 stay unmarked.
- **Columbia, Mackenzie and Yukon:** 20, all left unmarked. Salmon are cut off from the Kootenay and upper Columbia by dams and falls, and do not run into the Mackenzie. Okanagan and Similkameen steelhead and the four Yukon cells wait for the literature, which may add them.
- **No records left after the rules:** 4. BRID ST, STUL CO and MESI SK stay unmarked, and TURN ST waits for the Mackenzie literature.

The record count was shown, not used: a five-record bar was picked by eye and dropped.

Of the 21 resident cells, GR in LARL and all ten WCT cells stay unmarked as outside the native range. Eight BT cells resting on DV records, and two CT cells, wait for a look at their records.

Of the 24 cells marked present without a counting record:
- removed: the six Upper Dean salmon and steelhead cells added as a test, and four resting only on stocked fish (CT in THOM and LNTH, DV in VICT, GR in BULL);
- kept: the PSE-backed Kitasu Bay cells, undated-only BT and DV, and three with no records and no evidence of absence;
- held: CT in CLRH and DUNC, for the Columbia literature;
- deferred: the kokanee and rainbow cells, to #432.

**Not carried out.** The three misplaced or misidentified records (KOTL ST, MESI SK, GUIC CH) belong in `observation_exclusions.csv` as data errors. In `default` that file is a byte-for-byte bcfishpass copy, and an overlay can change only rows the copy holds. None of the three changes a presence cell.

## The tracker

`configs/default/wsg_species_presence_review.csv` holds one row per flagged cell: the flag, the rule, a story drafted from the evidence, and a decision (`pending`, `keep`, `add`, `remove`), with the reviewer, date and issue. The check refreshes the story on a pending row and never touches a decided one; a row it no longer flags stays and is reported. A decision to add or remove is carried out by editing the presence table, whose `notes` cell names the rule. That edit moves the `acc` output token (the presence species columns are in its spec; `notes` is not).

The tracker is deliberately not declared under the bundle's `files:`. A d declared file enters `config_hash`, so after a review edit link reads every earlier build as another bundle: `recompute_readers_check.R` refuses to recompute the groups outside a partial run that read it (`config_changed_since_run`; the run's own groups still recompute), and an export of an earlier build ships its habitat without the bundle files ("bundle has changed since the build"). No run reads the tracker.

## Lifts are a separate threshold

A presence cell decides whether a record is seen at all. Whether a record seen above a natural barrier lifts it is `parameters_fresh.csv`'s `observation_threshold`. In `default` that is 5 records on or after 1990-01-01 for CH, CM, CO, PK, SK, ST, GR and KO, and 1 for BT, RB and WCT. The salmon and steelhead counts are bcfishpass's (`smnorris/bcfishpass@620dbe4`), but its date test is strict (`obs_dt > date('1990-01-01')`) where link's is not (`observation_date >= ...`, `lnk_barrier_overrides()`), so salmon and steelhead records dated exactly 1990-01-01 count toward a lift in link and not in bcfishpass: 561 of them, of 569 in bcfishobs (the other 8 sit in groups whose cell for the species is unmarked). WCT counts one record in both. bcfishpass has no GR or KO access model, lifts RB in its CT/DV/RB model with no threshold row, and counts BT, salmon and steelhead records for a BT lift, where `default` counts BT and DV. So a single salmon above a falls makes the segment read "observed upstream" (code 2), and does not lift the falls. Both are filed: the date test as #426, the threshold as #427.
