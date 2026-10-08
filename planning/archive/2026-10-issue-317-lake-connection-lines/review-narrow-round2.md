# Review: narrow `.lnk_sql_lake_connection()` to 1450 (round 2)

## Findings

- **data-raw/logs/lake_connection_317/README.md:3**: the round-1 fix adds a new false claim. "`measure.R` needs `.lnk_sql_lake_connection()`, so it runs only from that commit on" is wrong.
  - The function exists from `c1760d1` on (`git grep 'lnk_sql_lake_connection <- function'` finds it at `c1760d1` but not at `1161b59` or `00235e0`).
  - So `measure.R` runs without error at `c1760d1`, `118ca33` and `c3ea9d7`. There it applies the old `IN (1400, 1450)` predicate and gives the pre-narrowing numbers, which is a quieter failure than an error.
  - The other half of the fix is accurate. `measure.csv` is staged with the predicate change, so once committed `git log -1 -- data-raw/logs/lake_connection_317/measure.csv` names the narrowing commit.
  - Suggested wording: "`measure.R` calls `.lnk_sql_lake_connection()`, so it errors before `c1760d1` and reproduces these numbers only from the narrowing commit on."

- **RUNBOOK.md:772** and **research/habitat_thresholds.md:1309**: the bold claim "**Construction lines are not connectors.**" is false against the FWA code table, and in RUNBOOK it contradicts the bullet right above it.
  - `whse_basemapping.fwa_edge_type_codes`: 1450 = "Construction line, connection" and 1410 = "Construction line, network connector". Both connector codes are construction lines.
  - RUNBOOK.md:770 itself says "FWA connectors (1450, "Construction line, connection")".
  - The intended rule is the one the logs README states correctly: 1400 is a construction **flow** line, not a connector.
  - Suggested wording: "**Construction flow lines are not connectors.**"
  - The archive README:17 reports this as the operator's ruling, so its wording is a quotation and can stay.

- **R/lnk_rollup_wsg.R:241-243** (roxygen of `.lnk_sql_lake_connection()`, in context and not changed by this diff): "no rule admits construction lines in a wetland" has the same defect as the 1410 claim round 1 fixed. It holds for `default` only.
  - The `bcfishpass` bundle's BT rear rule has no edge filter.
  - `fresh.streams_habitat_bt` (the bcfishpass-config persist) has rearing on construction lines inside wetland polygons: 1200 is 339 segments, 266.6 km; 1410 is 29 segments, 0.9 km; there is one 1425 segment.
  - The predicate is unaffected. Province-wide, `fwa_stream_networks_sp` has no 1450 line in a wetland polygon (construction lines there are 1200, 1300, 1400, 1410 and 1425 only), so the lake-only scope loses no connector.
  - Suggested wording: "no 1450 line lies in a wetland polygon."

- **Mechanism**: definitions and scope claims are written from memory or paraphrase rather than derived.
  - "Runs only from that commit on" was not checked against where the function first appears.
  - "Construction lines are not connectors" restates the operator's shorthand as an FWA fact.
  - "No rule admits …" carries a `default`-only truth into a general sentence. Round 1's 1410 fix was the same shape, and the sentence next to it went unchecked.
  - Each one is settled by a single `git grep` or `psql` query.

## Checked and clean

- **"1410 (network connector) does not occur in lake polygons" is true.** In local fwapg, `fwa_stream_networks_sp` joined to `fwa_lakes_poly` and `fwa_manmade_waterbodies_poly` on `waterbody_key` has no 1410 or 1425 line. The connector-family edges found there are 1400 (lake 85,414 rows / 6,226 km; manmade 1,493 rows / 126 km) and 1450 (lake 124,365 rows / 52,363 km; manmade 129 rows / 30 km).
- **The edge-type labels quoted in the docs match `fwa_edge_type_codes`:** 1400 "Construction line, other flow/inferred connection", 1450 "Construction line, connection" and 1410 "Construction line, network connector". 1475 is "Construction line, lake arm". Calling it a flow line in "like 1200 / 1300 / 1475" is an interpretation, not a contradiction.
- **Suite 2585.** This diff adds exactly one expectation (`expect_false(grepl("1400", p))`) to round 1's 2584, so 2585 is consistent with the parent's measurement. The full suite was not re-run here.
- **Numbers are consistent across measure.csv, summary.csv, rollup_check.csv, the logs README table, habitat_thresholds.md, CLAUDE.md and the archive README.**
  - NATR BT +24.4 % (3,710.422 / 2,983.281).
  - NATR RB 3,737.7 / 267.1 / 233.0.
  - Connection ranges 159–164 and 213–275 km.
  - The rollup check's maximum absolute deviation is 0.007 km, within the stated 0.008.
- **#320** resolves to "Wetland construction flow lines get no km, so many wetlands are hectares-only", which is on topic.
- **No stale wording remains.** Outside `planning/archive/` and the #310 log, no live file still names 1400 as a connector or as left out of the km. The remaining `1400/1450` strings are the L-rule edge list (RUNBOOK.md:749, NEWS.md:7, CLAUDE.md:37), which is correct.
- **Nothing is unstaged.** `git status` shows no unstaged changes beside the staged set.

## Disposition (parent, 2026-10-08)

- All three findings fixed.
- **One figure here was wrong.** "266.6 km of 1200 inside wetland polygons" (bcfishpass BT) re-derives to **28.3 km** on the full key `(id_segment, watershed_group_code)`. A bare `id_segment` join gives 26,690 km, the #203 fan-out. It was copied into #320 before being checked, then corrected there. The 1410 figure (49.7 km) re-derives exactly.
- **Terminated by enumeration, not by another round.** Every claim-bearing sentence (edge-type definitions, scope, commits, figures) in the live files the branch touches was checked against `fwa_edge_type_codes`, local fwapg (full-key joins) or `git grep`:
  - `R/lnk_rollup_wsg.R`, `R/lnk_compare_*.R`;
  - RUNBOOK §7, CLAUDE.md status, `research/habitat_thresholds.md` §317, `bcfishpass_methodology.md` note;
  - taxonomy header, default README, dictionary, logs README, archive README;
  - the #317 / #319 / #320 bodies.

  Two more were corrected on the way:
  - "like 1200 / 1300 / 1475": 1475 is "lake arm", so the analogy is now 1200 / 1300;
  - the archive README now quotes the operator rather than restating the ruling as an FWA fact.
