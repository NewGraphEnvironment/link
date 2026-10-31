# Plan review — #402 part 2 (Plan agent, 2026-10-31)

Findings as delivered (condensed; numbers are the reviewer's, read-only against local fwapg):

- B1: the 50k-code comparison repeats match_type (A 181,326 / 181,420 agree, C 31,674 / 31,726, B 0 / 21,890 by construction); D/E are waterbody matches. Replacement: the record's own 50k code lies in another group (`fwa_streams_20k_50k.watershed_group_code_20k`): 2,574 records.
- B2: the 44 location-typed `data_error` rows in observation_exclusions.csv pass every location/transcription screen (31 A, 11 D, 2 E; code in group 44/44; UTM consistent 44/44). Use the 67 data_error rows as a recall set.
- B3: "weak match C/D/E" would doubt 46 % of records, 63 % of KO; distance limits differ per class.
- B4: "unlifted barrier below" is circular for absent cells (lifts count only present species' records; KO overrides in 10 groups). blocks_species lists all 13 species on every falls. Compute records of the species class above the barrier directly, presence ignored; fail only anadromous.
- B5: Bonnington Falls is not a FALLS row (lower Kootenay holds only CABD dams and salmon-class gradient rows); barriers outside BC absent. Add major drainage x native-range table (McPhail).
- G1: isolation degenerate (375,962 records on 180,221 species-locations); use distinct sites, waterbodies, years per cell (109 cells lone by waterbody vs 82 by record).
- G2: dfo_known_sockeye_lakes.csv and user_barriers_definite_control.csv notes are unused evidence.
- G3: KO rearing-lake test ambiguous; KO in the salmon gradient class; 254 KO lake records on through-flowing rivers.
- G4: the substance is SQL; keep builders in R/ with a golden check and the recall set.
- G5: Provincial Fish Ranges is custom-download only and partly derived from the records (codes 1, 2, 8); Historical Zones is pre-2001 FISS, same source as bcfishobs FISS records.
- A1: bcfishobs geom is PointZ and Z equals stream Z at the measure (mean |diff| 0.00 m over 15,275 records).
- A2: segment gradient P99.5 above access gradients (CO 0.378, ST 0.513); not a usable ceiling.
- A3: percentile ceilings are circular; set per drainage from literature or the operator.
- A4: name screen is noise (lake vs river names, accents, renames, side channels).
- A5: UTM zone test tautological (98 mismatches, 94 within 0.23 deg of a zone edge). Dropped.
- A6: barrier EXISTS/LATERAL with ltree prefilter is tractable; 5 groups (CHUK, HAYR, KCHL, SAHT, SHEK) hold no barrier rows: read NA.
- A7: main stem = blue_line_key continues upstream outside the group (7 s province-wide).
- A8: the operator's two examples (ELKR CCT, KOTL DV) are not among the 351 flags.
- O1: thresholds need the DB fields first.
- AC1: say whether doubt counts; a screened re-run can raise new flags outside the 351; rule column must name the screen.
- AC2: a new bundle file must stay undeclared (config_hash).
- S1: two PRs: measures and a cell table now; literature and range layers after.

Disposition (operator, 2026-10-31): measures now, no verdicts; verdict rules set in the decision session; literature, range layers and the native-range table in a second PR.
