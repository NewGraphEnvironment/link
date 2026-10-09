# Code review, round 2: branch `319-rearing-km-means-two-things-lnk-rollup-w` (#319)

## Findings

- **[severity: bug (doc claim)]** `R/lnk_habitat_validate.R:83-85` (and `man/lnk_habitat_validate.Rd`):
  the new bullet says "`rearing` is fresh's `rearing` flag: stream lines, and since `default`'s lake
  rule (link#310) lake and reservoir lines too." That leaves out wetland lines, which are a large
  share of the flag in both bundles. Both rule sets admit the 1050/1150 wetland-flow lines
  (`lnk_rules_build.R:404`, and `bcfishpass/rules.yaml` lists 1050), and 1000/1100 mainlines in
  wetland polygons rear through the stream rule. I measured `fresh_default` BT `rearing` on lines
  inside `fwa_wetlands_poly` (read-only):
  - NATR: 1,211 km on 1050, 606 km on 1000 and 5 km on 1100.
  - ADMS: 42 km on 1050 and 29 km on 1000.

  The "since #310" framing is also `default`-only. The bcfishpass bundle's BT `rear: []` tests any
  edge, so its `rearing` has always carried lake lines, connection lines included (65.9 km on
  ADMS, per the #317 section).
  - **Why it matters:** this sentence defines what `share_rearing` / `n_rearing` capture count. A
    reader would take wetland-line hits as "not rearing".
  - **Fix:** say the flag covers stream, wetland-flow and lake/reservoir lines.
  - **The same stale wording, not on this branch:** `research/habitat_validation.md:11` still calls
    capture "stream rearing", one line above the cost bullet the branch edited. It now contradicts
    the added text ("capture still reads the `rearing` flag").

- **[severity: bug (wrong number)]** `data-raw/logs/lake_connection_319/README.md:49-50`: "re-scored
  now, KOTL KO base `rearing_km` would read 568.63 − 309.58 = 259.05 km, and `ko_mad`'s change
  −7.09 km becomes −4.38 km." Those figures subtract two values that were each rounded already. The
  new default rounds each column by itself, so a re-score does not give them. I ran
  `lnk_rollup_wsg(conn, "KOTL", "KO", schema = ...)` at HEAD (read-only):
  - `score300_default_tuned`: `rearing_km` **259.06**, connection 309.58.
  - `score300_ko_mad`: 254.67, connection 306.87. The change is **−4.39**, not −4.38.

  The error is 0.01 km. It is still a number the README says a re-score "would read", and that
  re-score does not produce it. The same 259.05 is in `planning/active/findings.md` and
  `task_plan.md` (not shipped).

- **[severity: fragile (doc claim wider than the code)]** `RUNBOOK.md:781` ("**`rearing_km` means one
  thing everywhere (#319)**") and `research/habitat_thresholds.md:1351` ("Decision ...: one meaning
  everywhere"). `lnk_aggregate()` is exported, and its **default** `cols_sum` is
  `c(spawning_km = "spawning", rearing_km = "rearing")` (`R/lnk_aggregate.R:79-80`). So it still
  writes a column named `rearing_km` that is the flag total, connection lines included. That is the
  two-meanings state #319 set out to end.
  - The RUNBOOK admits the exception in a sub-bullet two lines below its own headline.
  - The new research subsection does not mention the exception at all. It appears only in the #317
    section's "What does not move" paragraph.
  - Neither `lnk_aggregate()`'s roxygen nor anything a caller reads says its `rearing_km` differs
    from `lnk_rollup_wsg()`'s.
  - **Fix:** make the headline "every WSG rollup" rather than "everywhere", or name the
    `lnk_aggregate()` exception in the research subsection.

- **[severity: fragile (doc claim)]** `data-raw/logs/lake_connection_319/README.md:35-36`: "In that
  script only `totals.csv` and `habitat_change.csv` read `rearing_km`."
  - `habitat_variants_score.R:411-413` also writes the validator's full summary to `summary.csv`.
    That file carries `rearing_km` per WSG (KO rows in #300 / #305: 84 each).
  - It now also carries a new `rearing_lake_connection_km` column. So a re-score at this HEAD
    changes the shape of every `summary.csv`, #284's included, even where every value is the same.
  - The "reproduces exactly" framing holds for `habitat_change.csv` (I re-ran
    `habitat_change_284_check.R`: 36 rows checked, 0 differ). It would not hold byte for byte for
    `summary.csv` / `totals.csv`.

## Checked and clean

- **Lake fish table:** reproduced exactly with `left(match_type,1) IN ('A','B')`, a join to
  `fwa_stream_networks_sp` on `linear_feature_id`, and lake + reservoir polygons. It counts
  records, BT without DV.
- **Parity cross-section:**
  - The before/after tables in the README and the research doc match the committed `.txt` files.
  - 25/25 both times. Accessible and spawning are identical. LKEL ST/CO/CH rearing do not move.
  - The PCEA widening equals 375.9 − 367.7 = 8.2 km.
- **Score schemas:**
  - No `score305_*` schemas exist. #305's variants live in `score300_*_fill` (`built.csv`), so the
    script did cover them.
  - Only #300 / #305 carry KO cost rows, and no committed output has SK cost rows.
  - The KO verdict rows in `model_verdict.csv` read band km from flags, not `rearing_km`.
- **`fresh.streams_vw_bcfp`:** has `edge_type` and `waterbody_key`.
- **`pars_accessible.rds`:** rearing 2575.06/2588.91 → 2565.31/2579.15, and spawning
  1683.38 → 1683.36, as stated.
- **Validator test fixture:**
  - The lake key `328961687` appears once in `fwa_lakes_poly` and in no wetland or reservoir table.
  - No other test depends on BBBB seg 2 being edge 1000 with no waterbody:
    - BBBB observations (o5, o8) and the BBBB absence are dropped because BT is absent there.
    - The mad fixture's CO is absent from BBBB.
    - The discharge fill test points only AAAA seg 1 at an edge 1250 line, and nothing filters
      fixture streams on edge type.
- **Round-1 fixes** (the `lnk_compare_rollup.R` comment, the NA clause, the test restructure) are
  correct. `lnk_compare_rollup()`'s metrics do COALESCE and split by polygon.
