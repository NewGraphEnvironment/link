# Code-check round 2: branch 402-presence-map (8496bccf...213125a2)

## Checklist read

- code-check.md: read the whole index; the full prose of all 14 H3s under `## Mechanisms` (table rows skipped); from "Rules that stand alone", Documentation Staleness. Not read in full: the other 30 headings (security, spreadsheets/PDFs, YAML, URLs, and the rest of the stand-alone rules), since nothing in the diff uses them.
- code-check-r.md: read the whole index. Full sections read: `$` partial matching, `match()` treats NA as a value, `ifelse()` with an all-NA test, `paste()` with a zero-length argument, `data.frame()` recycling, `tempfile()` lives in the session tempdir, Rscript reads a script as it runs, the `data-raw/` script loading the source tree, the `information_schema` lookup, and Postgres row order. About 160 headings not read in full (none bear on this diff's tools).
- code-check-spatial.md: read the whole index. Full sections read: "Give a web map hex colours" (cartography, in CLAUDE.md), "A name is not a key: GNIS_NAME", "`summarise()` on a grouped sf", "GDAL failure partway through st_read". About 135 not read in full.
- code-check-shell.md: read the index headings. None read in full: the diff has no shell.

## Round 1 fixes, re-checked

1. **Barrier de-duplication on `barrier_source` + lon + lat is right.** The `bars` query's `DISTINCT ON (observation_key) … ORDER BY observation_key, watershed_group_code, id_barrier` joins on position and source only. So every record behind one position gets the same row (the first group alphabetically, then the lowest id), with the same coordinates. Checked on local fwapg: `fresh_default.barriers` (FALLS, GRADIENT, USER_DEFINITE) holds 7,240,866 distinct (source, blue_line_key, measure) positions. That equals both the number of distinct (source, position, x, y) rows and the number of distinct (source, x, y). So copies of a barrier never differ in geometry, and no two distinct positions of one kind share a coordinate.
2. **The ring layer is populated.** `pm_rec` is built over every bcfishobs record, excluded ones included, so the `meas` merge in `err` keeps the data_error keys. The header now says rings are never rule hits, which is correct.
3. **The two files are committed:** `easy_wins.csv` and `above_1400m.csv` are under `decision_session/`.
4. **The NEWS single-site line** now names the 10 recent single sites that were rejected.

## Tracker and docs, checked against the data

- **The tracker agrees with `easy_wins.csv`:** 1 strong 39/39 add; 2 some 55/55 add; one site 17 add and 33 keep (all 17 adds have a record since 1990; the 10 rejected and the 23 with none since 1990 are keep); literature 20/20 keep; none left 3 keep and 1 pending (TURN ST). The strong rows meet every stated criterion. Totals are 111 add, 76 keep, 154 pending (138 KO and 3 RB on #432; 8 BT, 4 CT and 1 ST on #402) and 10 remove, in 80 groups. Every decided story carries the prefix and no pending one does.
- **Reproduced on local fwapg:** 216 records under the real-barrier rule; 1,004 gradient-nearest records with at most 2 above (613 of them coho); 1,220 hits under the all-barrier rule; 5 of 37 and 36 of 37 known errors (`recall.csv`); 19 salmon and steelhead counting records above 1,400 m (SUST 16, GUIC, KOTL, MESI 1 each).
- **Vocabulary, dictionary and config tests pass** on a `git archive` copy (49, 118 and 176 pass). The append-only rule allows setting `retired` on acc-v3.
- **No private repository is named** in any added line.

## Findings

- **[severity: fragile]** research/species_presence.md "The first review", Record rules; NEWS.md:5; CLAUDE.md:16; decisions.md Decision 1 — the docs state the barrier rule differently from how it was applied.
  - **What the docs say:** "does not count above a blocking mapped falls or hand-entered barrier with at most one other record of its lift pool above it", and "Records above a modelled gradient barrier still count (1,004)".
  - **What was applied:** `.lnk_presence_measures()` measures only the *nearest* blocking barrier below a record, so the rule was applied as "nearest barrier is FALLS or USER_DEFINITE". A record whose nearest barrier is a gradient but that also sits above a falls was treated as "above a gradient" and counted.
  - **Measured on local fwapg:** 113 counting salmon and steelhead records have a gradient as nearest barrier and also a FALLS or USER_DEFINITE barrier below them. For 50 of those, the real barrier has at most 2 pool records above it, in 37 cells (CLAY ST, SANJ CO, LFRA CO, TSAY CH, MCGR CH, KLUM CH, …). The rule as written drops those 50; as applied, they count.
  - **Effect today:** none of the 37 cells is a tracker row, so no decision moves. But a rule text that a later check or re-run implements literally will differ from the review it claims to record.
  - **The 1,004 figure:** 1,837 counting records have a gradient as nearest barrier. 1,004 is only the subset with at most 2 records above.
  - **Fix:** state the rule as applied ("whose nearest blocking barrier is a falls or hand-entered barrier"), or re-measure the real barrier below.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** research/species_presence.md "The first review", Elevation ("10 surveys from 1975 to 2001"); decisions.md Decision 2 record calls ("10 surveys 1975-2001") — the survey count is wrong. The 16 SUST records in the committed `above_1400m.csv` carry 13 distinct sources (survey ids 3244, 3248, 133579, 133580, 151491, 64212, 64214, 64216, 74213, 7501825, 88725, 89735, 89736). The years 1975 to 2001 are right.
  - **Rule:** none

- **[severity: fragile]** research/output_vocabulary.md:60-61 — the table of shipped-config tokens still gives `acc-v3` for `default` and `default_tuned`. acc-v3 is retired at 0.75.0 on this branch. The `bcfishpass` row had already been stale (`acc-bcfp-3`, live is `acc-bcfp-4`) since #429.
  - **Rule:** code-check.md "Documentation Staleness"

- **[severity: fragile]** NEWS.md:6 — the "Added where … stay unmarked" sentence leaves out the cells held for the literature.
  - **What it says:** cells are added where records sit at several sites, or at one site with a record since 1990, and its exceptions list "salmon in the Kootenay, upper Columbia and Mackenzie, and species outside their native range".
  - **What it misses:** the Yukon cells and Okanagan and Similkameen steelhead. These meet the "added" criteria but were left unmarked for the literature: TESR CM (2 sites, a record since 1990), TUTR ST (one site since 1990) and OKAN ST (3 sites since 1990). NEWS does not mention them anywhere; CLAUDE.md and the research file do.
  - **Rule:** none

- **[severity: fragile]** decisions.md GUIC entry ("GUIC CH stays marked present (7 other records)"); guic_ch_misplaced.md ("8 CH records in GUIC, 1991-2012") — the counts include the misplaced record's twin, which is already a known error.
  - **The twin:** 056266487d (FDIS fshclctn_id 146375, the same permit KA12-81148, the same site 356111950:89, 2012-08-14) is already a `data_error` row in `observation_exclusions.csv`, with the same reading: 1,580 m, 85 km from the Nicola.
  - **Effect:** 6 other counting records remain at 5 sites, not 7. The cell does not move, and the existing exclusion corroborates the write-up.
  - **Rule:** none

- **[severity: fragile]** data-raw/wsg_species_presence_map.R:56 — the header promises the script writes nothing in the repo, but `--out` defaults to `file.path(Sys.getenv("TMPDIR", "."), …)`. With TMPDIR unset (cron, a non-login ssh, Linux), the default is the working directory, which is the repo root when run as documented, so the HTML lands in the tree. `tempdir()` keeps the promise.
  - **Rule:** none

/Users/airvine/Projects/repo/link/planning/active/review-round2.md
