# Code-check round 3 (#402 part 2): review by enumeration

Worktree `wt_cc3` at `f84467a6`; diff `ba5fef36...HEAD`. Database: local fwapg (session temp tables only).

## Checklist read

- `code-check.md` `## Mechanisms`, prose of every H3, table rows skipped: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree…", "A wrapper's exit is not the work", "Zero-length, empty, and unset…", "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently", "One fact derived twice". I read "One fact derived twice" and "Verification that reads its own output" in full.
- `code-check-r.md` index: "Cross-function consistency for label/string normalization", "`match()` treats NA as a matchable VALUE", "Postgres row order is never fixed unless the query fixes it", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL", "A `data-raw/` script must load the source tree", "`nzchar(NA)` is TRUE". These are the patterns the diff uses: SQL built with sprintf, R/SQL folds, distinct counts.
- `code-check-spatial.md` index: "FWA `upstream_route_measure` misses the next segment's start", "A name is not a key". These apply to the FWA joins.

## Findings

- **[severity: bug]** `R/lnk_presence_measures.R:246-249` (with `:30-32` and `:127-130`): the code reads `known_sockeye_lake` and `lake_ha` from the lake polygon of the matched **segment** (`s.waterbody_key` of `o.linear_feature_id`). The roxygen and the research table describe the record's own lake ("its lake"). They differ, and inside one function the same "record's lake" is defined two ways: `waterbody` uses the record's own `waterbody_identifier`.
  - Of 138,628 `waterbody_type = 'Lake'` records, 17,147 sit on a segment with no `fwa_lakes_poly` row. Of these, 11,293 are E matches: bcfishobs matches them to a waterbody but snaps them to the closest construction line, often a river polygon or a 1000 line. 15,848 of the 17,147 can be placed on their lake through bcfishobs's own `waterbody_identifier` = `fwa_lakes_poly.waterbody_key_group_code_50k`. In 1,036 more records the segment's lake differs from the identifier's lake.
  - Effect on the tracker: **BOWR KO** (flagged `absent_recorded`) reads "59 of 62 in lakes" with no known sockeye lake. 54 of those records carry `00947BOWR`, Bowron Lake (`waterbody_poly_id` 700036943), which is in `dfo_known_sockeye_lakes.csv`; E-matched, they sit on a Bowron River 1250 segment (`waterbody_key` 329706424). USHU KO (flagged) misses 4 such records and NASR KO (flagged) 1.
  - Province-wide, 78 SK and KO lake records in 16 cells are in a known sockeye lake by identifier and not by segment, against 909 caught by segment.
  - A fix must aggregate, because the 50k key is not unique: 213,282 lake polygons carry 185,958 distinct values.
  - The research row "Lake, known sockeye lake" leaves its Limits cell empty.
  - **Rule:** `code-check.md` "A proxy is not the property"; "One fact derived twice".

- **[severity: fragile]** `R/lnk_presence_measures.R:45-46`, `CLAUDE.md` (the #402 part 2 bullet "375,962 records…"), `research/species_presence.md` (the "Sites, waterbodies, years" row): "bcfishobs gives every stream record in a group one shared identifier (`00000<group>`)" is false as written.
  - In 120 groups, stream records carry more than one identifier.
  - 39,090 stream records carry another group's code: UPCE has 12,524 with `00000LPCE`, LARL 8,177 with `00000COLR`, REVL 3,840 with `00000COLR`, HARR 2,745 with `00000LFRA`.
  - 5,700 stream records have no identifier.
  - The conclusion stands, since the identifier is group-wide rather than a stream key, and the code does not depend on it. Only the quantifier and the `<group>` are wrong.
  - **Rule:** none (CLAUDE.md agent-operations §3, "Treat `every` … as words to check").

- **[severity: fragile]** `data-raw/wsg_species_presence_check.R:120-131` and `R/lnk_presence_measures.R:119-125`: counting is defined twice. One copy is the R in `.lnk_presence_check()` (`n_kept_own`). The other is the measure's SQL, whose text is copied into both driver SQL blocks.
  - At HEAD the two agree in all 1,573 cells that both hold: `n_counting == n_kept_own`, 0 differ (measured from `measures.csv` against `cells.csv`).
  - Nothing asserts that equality province-wide.
  - The measures recount repeats the measure's counting predicate as text, so it cannot catch a wrong definition. The R definition is tied to the SQL only through the part 1 cross-check, in three groups.
  - Known divergence: `.lnk_presence_check()` makes a year before 1850 undated, and the SQL `BETWEEN year_min AND year_now` counts it. So `--year-min` below 1850 changes `counting` but not `n_kept_own`, and the driver accepts any non-NA year.
  - One `stopifnot()` in the driver comparing `cm$n_counting` with `res$n_kept_own` over the shared cells would close this.
  - **Rule:** `code-check.md` "One fact derived twice".

- **[severity: fragile]** `data-raw/logs/presence_check_402/README.md` (the `stamp.txt` row) and `stamp.txt` ("SQL recount of PARS, ADMS, ALBN, 106 cells, all agree"): both read as a recount of the measures. It recounts 7 measure columns: `n_counting`, `n_sites`, `n_waterbodies`, `n_years`, `n_code_other_group`, `n_above_barrier`, `n_hist_zone`.
  - It does not recount lake records, known sockeye lakes (where the first finding sits), main stem, kokanee without a lake, class above (min and max), above kinds, `barriers_known`, elevation or drainages.
  - The driver's comment (lines 183-186) and `task_plan.md` line 43 name what is left out. The README and the stamp do not.
  - **Rule:** `code-check.md` "A guard's scope, escape hatches, and remedies".

- **[severity: fragile]** `planning/active/task_plan.md` describes code that does not exist at HEAD, in four lines:
  - Line 32 gives the signature `.lnk_presence_measures(conn, zones, species_barrier, lift_pools, year_min)`. It omits `sockeye_lakes`, `excl_keys`, `incl_keys` and `year_now`.
  - Line 33 names a `code_group` column. No such column is output.
  - Line 47 gives `.lnk_presence_cell_measures(measures, records)`, which takes `m` alone. Its "the most records of the class above" should read fewest and most.
  - Line 48 says "The driver joins it to every cell (`cells.csv`, `disagreements.csv`)", but `cells.csv` carries no measure column. The per-cell measures are in `measures.csv` and `disagreements.csv`.
  - The archive README is built from this file, so it will repeat these.
  - **Rule:** none (CLAUDE.md feature-workflow, "Issue bodies get edited, not appended", applied to the PWF record).

## Enumeration

### (a) Every number in the diff's additions to the docs

Sources: `M` = `measures.csv`, `D` = `disagreements.csv`, `R` = `recall.csv`, `C` = `cells.csv`, `S` = `stamp.txt`, `E` = `evidence/stamp.txt`, `DB` = local fwapg, `T` = tracker CSV. `R`'s `barrier_below` is read with `na.strings = ""`.

| Claim | Location | Reproduced | Verdict |
|---|---|---|---|
| 351 tracker rows | CLAUDE, research | T 351 rows; S flagged 351 | holds |
| 319 of 351 rows carry measures | CLAUDE, research | T: 319 stories contain "Own records:"; D: 319 with `n_counting` | holds |
| 32 carry none: 24 present, 8 BT with DV pooled only | research | D: 24 present_unsupported plus 8 BT absent_recorded with `n_kept_own` 0 and `pooled_from` DV | holds |
| 46 of 67 errors caught by two measures | CLAUDE, research | R: barrier-and-≤2 OR elevation >1400: 46 | holds |
| barrier, ≤2 class above: 36 | CLAUDE, research | R: 36 (37 have any barrier) | holds |
| elevation >1,400 m: 21 | CLAUDE, research | R: 21 (`>` and `>=` both give 21) | holds |
| 10 of those 21 not caught by the barrier | CLAUDE, research | R: 10 | holds |
| gradient ≥0.25 catches 6, all already caught | CLAUDE, research | R: 6, 6 caught | holds |
| the other 21 | CLAUDE, research | R: 21 (12 ST, 3 PK, 2 CM, 2 CO, 1 CH, 1 SK; the SETN notes as described) | holds |
| all 67 have own code in own group | CLAUDE, research | R: `code_other_group` FALSE 67 | holds |
| 67 `data_error` records, 67 in bcfishobs | README, RUNBOOK, S, task_plan 49 | R 67 rows, 67 with a group | holds |
| 49 of 67 on a zoned stream | research | R: `in_hist_zone` TRUE 49 | holds |
| 98 UTM-zone disagreements, about a degree from an edge | CLAUDE, research | DB: 98; max 1.04° from own zone's edge | holds |
| 0 of 386,025 lake polygons carry a local code | CLAUDE | DB: 386,025 rows; `local_watershed_code` and `localcode_ltree` 0 non-null | holds |
| 375,962 records | CLAUDE, research, S | DB 375,962 | holds |
| 179,815 species-locations (CT folded, blue line and metre) | CLAUDE, research | DB: distinct (folded species, blk, round(drm)) 179,815 | holds |
| 117 of 327 absent-recorded on one waterbody | CLAUDE, research | D: 117 (327 AR, 8 NA) | holds |
| 94 on one site | research | D: 94 | holds |
| 2,574 records filed under another group's code | research | DB over all records: 2,574 (8,226 not in lookup). M (counting only) sums 2,192, so it is not reproducible from committed outputs | holds (population: all records) |
| CHUK, HAYR, KCHL, SAHT, SHEK hold no barrier rows | research | M `barriers_known` FALSE exactly these 5; DB barriers in 241 groups vs 246 | holds |
| 3,374 counting KO above a blocking barrier | research, task_plan 43 | M: sum KO `n_above_barrier` 3,374 | holds |
| 42 with no lake | research, task_plan 43 | M: sum `n_ko_no_lake` 42 | holds |
| in 15 of 140 KO cells | research | M: 15 of 140 | holds |
| 168 anadromous AR cells | research | D: 168 | holds |
| 12 with every record above a barrier; 6 with ≤2 class above | research | D: 12; max_class_above ≤2: 6 | holds |
| 21 only on a main stem | research | D: 21 | holds |
| 59 with no record on a zoned stream | research | D: 59 | holds |
| 21 in Columbia (11), Mackenzie (7), Yukon (3) | research | D by records' `drainages`: 300 11, 200 7, 800 3. By the group's `region`, Yukon is 4: KUSR CH's record is drainage 960 | holds by drainage (the sentence's "lie in" reads as drainage) |
| 137 kokanee AR cells; 123 with lake records | research | D: 137; 123 | holds |
| none with every record above a barrier without a lake; 15 with some | research | D: 0; 15 | holds |
| 6,111 cells | README, S | M 6,111 rows (1,573 shared with C; 4,538 are codes the table has no column for) | holds |
| 106 cells recounted | README, S, task_plan 43 | M rows in PARS, ADMS, ALBN: 106 | holds |
| 39 cells, 5,423 records cross-check | README, S | part 1 values, not changed by this branch; S line from that run | holds (not re-derived here) |
| 4 alias cells | README | S 4 | holds |
| hist_zones rows written 16,525; species 74 | E | `hist_zones.csv` 16,525 rows, 0 duplicate keys, 74 species | holds |
| WFS rows 19,094 | E | written by `presence_evidence_load.R` (`nrow(z)`); not re-fetchable offline | producer-written, not re-derived |
| 1950, 1990, 1,400 m, 0.25, 25 to 30 % | research, CLAUDE | rule year and thresholds; "25 to 30 %" quotes the operator | parameters, not counts |
| "pre-2001 FISS" | research, roxygen, task_plan 41 | description of the source; not testable locally | not re-derived |
| falls 3,294; user-definite 226; 241 groups; match types 181,420 / 122,443 / 31,726 / 21,890 / 18,483 | task_plan 20-21 | DB: all equal | holds |
| link `e07e521e`, 0.73.1 | S | `e07e521e` is the last code commit; `f84467a6` changes outputs and docs only; DESCRIPTION 0.73.1 | holds |

38 rows, covering 61 numerals: 1 fails as worded (in the second finding, not a count), 0 numbers wrong, 3 not re-derived by construction.

### (b) Every definition applied in more than one place

| Definition | Place | Verdict |
|---|---|---|
| CT fold | records, measures SQL `:110` | `CCT, ACT, CT/RB` → CT |
| | zones, measures R `:84` | same set; holds |
| | zones, recount SQL `:236` | same set, folded from the raw CSV; holds |
| | `.lnk_presence_check()` `R/lnk_presence_check.R:76` | same set; holds |
| | driver cross-check SQL `:144`, recount record SQL `:192` | same set; holds |
| | zones loader | `toupper(trimws())`; records are not trimmed, so a record coded ` RB` stays apart in both. Consistent with the check |
| | DV→BT pooling | not applied to records or zones by design ("species' own records"). 180 BT records since 1950 sit on a DV-only zone. No flagged BT cell has own records, so no story moves. Holds as stated |
| Waterbody key | measures SQL `:127-130` | lake or wetland with an identifier → `wb:`id; else `line:`blk |
| | recount SQL `:196-199` | same, without prefixes. Cannot collide: numeric identifiers look like `waterbody_key`, and 0 equal any blk. Holds |
| | roxygen `:42-47`, research, CLAUDE | same rule; holds (the `00000<group>` wording is the second finding) |
| | `known_sockeye_lake` / `lake_ha` `:246-249` | a different "record's lake", the matched segment's: **first finding** |
| Site | measures `blk:round(drm)::bigint` vs recount `(blk, round(drm))` | blk non-null in all 375,962; same `round(double)`; holds |
| | research "a blue line and metre"; 179,815 | holds |
| Counting | measures SQL; cross-check SQL; recount SQL | identical text |
| | `.lnk_presence_check()` (R) | equal at HEAD (`n_counting == n_kept_own` in 1,573 of 1,573 shared cells); differs below `--year-min` 1850; unasserted: **third finding** |
| Release tagging | measures, cross-check and recount SQL; R `:92-98` | source head up to the first `:`; `BC RELEASE RECORDS DATABASE` / `STOCKING` in any case; `release_include` keys. Same effect (cell counts equal); holds |
| Exclusions | `.lnk_observation_exclusion_keys(loaded)` for `pm_excl`, `pc_excl` and R | one function; holds |
| `release_include` | `%in% c(TRUE, "t")` in the driver (twice) and R | holds |
| Year window | SQL `BETWEEN year_min AND year_now` vs R `[1850, year_now]` and `>= year_min` | holds for `year_min` ≥ 1850 (third finding) |
| 50k code trim | records `rtrim(replace(code,'-',''),'0')` (measures, recount); zones `sub("0+$","",gsub("-",""))` | same; zones have 0 trailing zeros and 0 non-digits; holds |
| Other-group code | measures (`pm_codegrp` from the lookup) vs recount (lookup read directly) | same predicate, separate plumbing; NULL code → NA vs not counted, consistent; holds |
| Barrier below | measures `fwa_downstream(rec, bar)` with `bar.ws @> rec.ws` vs recount `fwa_upstream(bar, rec)` with `rec.ws <@ bar.ws` | different fwapg logic (criteria read from the definitions), agree on 103 records in the three groups; prefilters implied by each function; holds |
| Lift pool | `observation_species` split on `;` in the driver; `pm_pools` | holds |
| Lake for KO rearing | `fwa_lakes_poly` via segment `waterbody_key` | reservoirs not counted; 0 of the no-lake barriers in LARL, OKAN, REVL, UARL and UPCE have a reservoir above. Holds as worded ("lake") |

### (c) Every column the recount compares

| Column | Sources | Independent of `pm_*`? | Could it disagree if the measure were wrong? |
|---|---|---|---|
| `n_counting` | bcfishobs, `pc_excl`, `pc_incl` | yes | Only on plumbing or aggregation. The predicate is a textual copy, so a wrong definition passes (third finding) |
| `n_sites` | bcfishobs | yes | yes: SQL count distinct vs R `ndist`; the definition is shared |
| `n_waterbodies` | bcfishobs | yes | yes on aggregation and the NULL-identifier fallback; the definition is shared |
| `n_years` | bcfishobs | yes | yes on aggregation |
| `n_code_other_group` | bcfishobs, `fwa_streams_20k_50k` directly | yes (not `pm_codegrp`) | yes on plumbing and NULL handling; the definition is shared (non-trivial: 2 records in the three groups) |
| `n_above_barrier` | bcfishobs, `fresh_default.barriers`, `fwa_upstream` | yes (not `pm_bar`) | yes, including the argument order: different function, 103 records |
| `n_hist_zone` | bcfishobs, `pc_zones_raw` folded in SQL | yes (not `pm_zones`); shares the one `read.csv` of the zones | yes on the fold and the trim; 2,608 records |

7 of 7 are computed without `pm_*`. Not compared: 10 measure columns (fourth finding).

### (d) Every statement about what a measure can or cannot see

| Statement | Where | True at HEAD? |
|---|---|---|
| A 50k code can span several groups; NA when it is not in the lookup | roxygen | yes (8,226 records not in the lookup) |
| Elevation is the point's Z, taken from the matched stream; 0 → NA | roxygen, research | yes: on 3,000 records, 2D distance 0 and Z equal to the line's interpolated Z (p99 0.00 m) |
| Major drainage is the first wscode segment | roxygen | yes (`split_part`) |
| Lifts are not read; they count only present species | roxygen, RUNBOOK, CLAUDE, research | yes (the code reads no lift table; the mechanism is from #349) |
| Bonnington Falls is not a falls row | CLAUDE, research | yes: Kootenay River near the Bonnington dams holds only CABD and GRADIENT rows; the 2 falls within 3 km are on Bird Creek |
| Barriers outside BC are absent | research | yes (the table is BC FWA natural barriers) |
| `n_class_above` ignores presence | roxygen, research, RUNBOOK | yes (no group or presence filter) |
| The KO lake is placed by its segments; lake polygons have no local code | roxygen, RUNBOOK, research, CLAUDE | yes |
| `lake_record`: bcfishobs matched the record to a lake | roxygen, research | yes: all `Lake` records are D or E ("matched - waterbody") |
| `lake_ha` / `known_sockeye_lake` are the record's lake | roxygen, research | **no**: the matched segment's lake (first finding) |
| Main stem: the blue line continues upstream outside the group; side channels read as tributaries | roxygen, research | yes (SQL as described) |
| The zone measure reads the 50k code, CT aliases folded; zones are not independent of FISS | roxygen, research | the fold holds; independence is a source claim |
| Waterbody: a lake's or wetland's identifier, else the blue line | roxygen, research, CLAUDE | yes; the explanation "every stream record … `00000<group>`" is wrong (second finding) |
| Comparing the record's code with the matched stream's repeats bcfishobs's A, C and D match | research, CLAUDE | consistent with the match types' wording; not further testable |
| A UTM zone test is tautological; 98 within about a degree | research, CLAUDE | yes (counted above) |
| Measures cover the species' own records, not pooled ones | roxygen (story), research | yes (no pooling in the measures) |
| The recount covers the measures | README, stamp | partly (fourth finding) |
| Not recounted: main stem, lakes, KO lakes, class above, elevation | driver comment, task_plan 43 | yes, though above kinds, `barriers_known` and drainages are also left out |

Members checked: 61 numerals in 38 rows (a), 28 definition sites (b), 7 recount columns (c), 18 statements (d). Five findings: one bug and four fragile.
