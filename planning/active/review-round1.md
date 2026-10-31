# Code check, round 1: branch 402-screen-fish-records (ba5fef36...2e531774)

## Checklist read
- code-check.md: every H3 under `## Mechanisms` read as prose, tables skipped (all fourteen). Not read: the 21 H3s under "Rules that stand alone", Security and Spreadsheets/PDFs.
- code-check-r.md: read "Postgres row order is never fixed unless the query fixes it…", "A database driver's value is not a base R type…", "A value compared as `::text`…", "`sprintf(\"%g\", x)` writes `Inf`…", "`nzchar(NA)` is TRUE…", "`match()` treats NA as a matchable VALUE…", "CSV whitespace…", "A `data-raw/` script must load the source tree…". About 150 other headings not read.
- code-check-spatial.md: read "The BC WFS caps an un-paged `GetFeature` at 10,000 features…", "bcdata returns a column whose values are all missing as character…", "A name is not a key…". The rest not read.
- code-check-shell.md: none read. The diff has no shell code.

## How it was checked
I re-ran `.lnk_presence_measures()` from the worktree against local fwapg, read-only with temp tables only (54 to 76 s). It reproduces the committed `measures.csv`: same 6,111 cells, and every column equal except elevations, which differ by at most 5e-12 from CSV precision. `n_counting` equals the check's `n_kept_own` in every cell `cells.csv` holds (0 mismatches). `fwa_downstream` and `fwa_upstream` take their arguments in the right order (I read the fwapg function bodies). The nearest-barrier pick never landed on a barrier with a NULL `localcode_ltree`, and never on a position that holds two barrier sources (0 of 9,385 picks). No join fans out (`pm_out` has 375,962 rows, 375,962 distinct keys). The new test file passes 42/42 with `NOT_CRAN=true`.

These claims reproduced: 2,574 records under another group's code; 36 / 21 / 6 in recall; all 67 recall records filed under their own group's code; 49 of 67 on a zoned stream; 153 cells on one waterbody and 94 on one site; 168 / 12 / 6 / 21 / 59 and 11 / 7 / 3 for the anadromous cells; 137 / 123 / 0 for KO; the five groups with no barrier rows; 0 of 386,025 lake polygons with a local code; the 106 recount cells; the 98 UTM-zone disagreements (the farthest is 1.04° from its zone's edge).

## Findings

- **[severity: bug]** R/lnk_presence_measures.R:284 (`n_waterbodies = ndist(d$waterbody_identifier)`), and the story at :333-336. In bcfishobs, every stream record in a group shares one `waterbody_identifier`, `00000<WSG>`: 229,336 stream records carry only 245 distinct ids, and 5,700 carry none. So `n_waterbodies` counts every stream in a group as one waterbody. Only lake and wetland records have their own ids. The headline claim "153 of the 327 absent-recorded cells rest on one waterbody" (CLAUDE.md:26, research/species_presence.md:96) and the tracker stories ("on 1 waterbody") understate the spread. 41 of those 153 cells have records on 2 to 14 distinct blue lines. For example, KTSU CM has 17 records on 16 sites across 14 streams, and its story reads "16 sites on 1 waterbody". LPCE WCT has 50 records on 14 blue lines and also reads 1 waterbody. This number feeds the operator's "lone record" decision directly. Count distinct streams for stream records (by blue line or 50k code) and keep the id for lakes and wetlands.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: bug]** R/lnk_presence_measures.R:101-102 and :224-227 (`in_hist_zone`). Each record's species is folded first (`CCT`, `ACT`, `CT/RB` become `CT`), then matched against `pm_zones.species_code`. The zone codes are not folded, and `hist_zones.csv` holds 111 `ACT` rows and 7 `CCT` rows. A cutthroat record on a stream zoned only under `ACT` or `CCT` therefore reads `in_hist_zone = FALSE`. That is 383 counting CT records in 16 groups, so `n_hist_zone` in `measures.csv` is too low for those CT cells. None of the flagged CT cells is affected today, so no tracker story moves. I checked the other pairs: ST against SST/WST, BT against ABT and RB against STC are 0 records, and DV against ADV is 15. Fold the zone codes the same way in `presence_evidence_load.R`, or before writing `pm_zones`.
  - **Rule:** code-check-r.md "Cross-function consistency for label/string normalization"

- **[severity: bug]** CLAUDE.md:21 and research/species_presence.md:94 say "47 are caught by any of the three … the other 20". The committed `recall.csv` gives 46 and 21. Barrier with at most 2 above: 36. Elevation above 1,400 m: 21, of which 10 are not already caught by the barrier test (the count is also 21 at `>= 1400`). Gradient 0.25 or more: 6, all already caught. 36 + 10 = 46, so 21 have no geometric tell. These are the numbers the decision session will choose rules from.
  - **Rule:** code-check.md "The probe is broken before the world is" (write the numbers last, against the final tree)

- **[severity: bug]** research/species_presence.md:88 and planning/active/task_plan.md:43 say "235 of the 269 barriers below KO records have one [a lake]". I could not reproduce this from HEAD on the same database. There are 276 distinct barrier positions below KO records and 242 of them have a lake (`pm_lake` has 242 rows). Over counting KO records only, it is 243 and 211. Neither pair matches the claim. The task plan also cites this count as the check on the KO lake placement.
  - **Rule:** code-check.md "The probe is broken before the world is"

- **[severity: fragile]** data-raw/wsg_species_presence_check.R:167-188. The "SQL recount of the measures" reads `pg_temp.pm_out`, the same per-record table the R rollup reads. It only re-adds the per-record flags, so it cannot disagree with any measure's definition. It would pass with the barrier direction reversed, with the waterbody defect above, and with the CT zone defect above. The task plan (:43) says "the golden values became the driver's SQL recount", and the README and stamp report "all agree" as if that verified the measures. In fact it only checks `.lnk_presence_cell_measures()`'s arithmetic. Either derive the expected side from `bcfishobs.observations` and FWA directly, or describe the recount as a check of the rollup only.
  - **Rule:** code-check.md "Verification that reads its own output"

- **[severity: fragile]** data-raw/logs/presence_check_402/stamp.txt line 2 reads `link: 0.73.1 @ 6fafc696`. At 6fafc696 the driver does not call the measures, and neither the `n_class_above` coalesce nor `.lnk_presence_measure_story()` exists yet. Those arrived uncommitted and landed in ab12550e. So the stamp names a commit that cannot regenerate `measures.csv`, `recall.csv` or the new story text. The driver stamps `git rev-parse HEAD` with no dirty flag, which is pre-existing. This branch is the first to commit outputs produced on a dirty tree.
  - **Rule:** code-check.md "A guard that fails toward pass" (provenance: stamp what actually ran)

- **[severity: fragile]** CLAUDE.md:16 ("every tracker story carries them"), RUNBOOK.md:660 ("each tracker story carries them") and research/species_presence.md:96 ("Each cell's story in the tracker carries its measures") all overstate. 32 of the 351 tracker rows carry no measure sentence. 24 are present_unsupported cells, which have no counting record. The other 8 are absent_recorded BT cells: CHIL, CLWR, EUCH, LKEC, LSAL, MUSK, SALR and STUL. Their only evidence is pooled DV, and the measures cover own records only. For those 8 the reviewer gets no measure of the records the flag rests on.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (a universal quantifier is a claim to execute)

- **[severity: fragile]** CLAUDE.md:26 and research/species_presence.md:92 give "180,221 species-locations". That is the count over raw species codes. The code's own `site` with CT aliases folded gives 179,815. Small, but the number cannot be derived from anything the branch commits.
  - **Rule:** code-check.md "One fact derived twice"

/Users/airvine/Projects/repo/link/planning/active/review-round1.md
