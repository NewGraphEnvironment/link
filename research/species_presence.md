# Species presence: which groups each species is modelled in

**Verified:** 2026-10-31 · **Issues:** #402 (this), #292 and #153 (the presence groups), #290 (pooling), #398 (CT aliases in code 2) · **Produced by:** `.lnk_presence_check()` (`R/lnk_presence_check.R`) through `data-raw/wsg_species_presence_check.R` on local fwapg, bcfishobs 375,962 rows (newest valid date 2026-10-10), link `feaa408c` → `data-raw/logs/presence_check_402/` · **Status:** 351 cells flagged and seeded into `configs/default/wsg_species_presence_review.csv`, every one pending the operator's review

## What a presence cell decides

`default`'s `overrides/wsg_species_presence.csv` is hand-authored: 246 groups by 13 species, and one `notes` cell per group. A cell marked `t` makes the species part of the model in that group. The pipeline reads the table two ways:

- **As written.** The observation filter keeps a record only where its own group marks its species present (`.lnk_pipeline_break_obs_species()`), and `lnk_pipeline_species()` picks the species to classify. A record of an unmarked species reaches no observation break, no code 2 and no barrier lift, in its own group or any other: the lifts count `<schema>.observations_province`, where each record is kept by its own group's row.
- **Promoted.** `lnk_presence()` makes a whole group present when one member is (salmon: CH, CM, CO, PK, SK; and CT, DV, RB). The barrier sets and the mapping code read that.

So a cell can be wrong in two ways that matter: a species modelled where nothing shows it lives there, and a species recorded in a group whose records the pipeline throws away.

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
- **114 absent cells are present through their group anyway.** All 32 PK cells, 34 SK, 17 CM, 17 CO and 12 CH are made present by another salmon member, and 2 CT cells through the CT, DV and RB group, so their barriers and mapping code are built, while the filter still drops their records.
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

The check mirrors the pipeline, so it judges what the model reads. Counted as their species, they would change 4 flags (`alias_sensitivity.csv`): FINA ST, UFRT ST and MFRA BT would become absent but recorded, and VICT DV would become supported. Whether the pipeline should read these codes is the steelhead and char counterpart of #398; it is not part of #402.

## The tracker

`configs/default/wsg_species_presence_review.csv` holds one row per flagged cell: the flag, the rule, a story drafted from the evidence, and a decision (`pending`, `keep`, `add`, `remove`), with the reviewer, date and issue. The check refreshes the story on a pending row and never touches a decided one; a row it no longer flags stays and is reported. A decision to add or remove is carried out by editing the presence table, whose `notes` cell names the rule. That edit moves the `acc` output token (the presence species columns are in its spec; `notes` is not).

The tracker is deliberately not declared under the bundle's `files:`. A declared file enters `config_hash`, so every review edit made after a run would make `recompute_readers` refuse that run's groups and stop the export publishing it. No run reads the tracker.

## Lifts are a separate threshold

A presence cell decides whether a record is seen at all. Whether a record seen above a natural barrier lifts it is `parameters_fresh.csv`'s `observation_threshold`. In `default` that is 5 records since 1990 for CH, CM, CO, PK, SK, ST, GR and KO, and 1 for BT, RB and WCT. The salmon, steelhead and WCT values are bcfishpass's (`smnorris/bcfishpass@620dbe4`). bcfishpass has no GR or KO access model, lifts RB in its CT/DV/RB model with no threshold row, and counts BT, salmon and steelhead records for a BT lift, where `default` counts BT and DV. So a single salmon above a falls makes the segment read "observed upstream" (code 2), and does not lift the falls.
