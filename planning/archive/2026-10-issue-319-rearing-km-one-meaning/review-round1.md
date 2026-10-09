# Code review, round 1: branch `319-rearing-km-means-two-things-lnk-rollup-w` (#319)

## Clean

I found no bugs, security issues or wrong numbers in the branch diff.

## What was checked, and how

- **Blast radius of the new default.** I grepped `R/` and `data-raw/` for `lnk_rollup_wsg(` and for readers of `rearing_km`.
  - Only three callers use the default `metrics`: `lnk_habitat_validate()`, `data-raw/parity_crosssection.R` and `data-raw/wsg_vignette_data.R`. `lnk_compare_rollup()` passes its own metrics.
  - Every downstream reader selects columns by name:
    - `.lnk_hv_summary()` merges on the key.
    - In `habitat_validate.R`, `cols_km` sums with `na.rm` and `cols_cmp` subsets by name.
    - In `habitat_variants_score.R`, `cols_n` and `hc` use named subsets.
    - `species_pooling_evidence.R` uses `intersect(keep, names)`.
  - No caller indexes columns by position. No caller binds summaries of different shapes.
- **SQL.**
  - Both parity scripts get the `s` alias and the `{wb_join}` / `%s` placement right. The `sprintf` argument order in `wsg_vignette_data.R` is correct. glue does not re-parse the interpolated predicate.
  - The view `fresh.streams_vw_bcfp` has `edge_type`, `waterbody_key`, `length_metre` and `watershed_group_code`. No unqualified column is ambiguous against `wb`.
  - The predicate is NULL-safe under `AND NOT`.
- **Fan-out.**
  - The lake, reservoir and wetland polygon tables share no `waterbody_key` (all three intersections are 0).
  - `fwa_lakes_poly` repeats 9 keys. One is Williston, `328961697` (FINA / PARA / PCEA, 980 lines on 1450). `.lnk_sql_waterbody_join()` uses `DISTINCT`, so the rollup and parity paths are safe.
  - The log script `score_schemas_connection_km.R` joins `.lnk_sql_lake_polys()` without `DISTINCT`, so it would over-count in those lakes. None of the WSGs those 9 keys sit in (FINA, PARA, PCEA, LEUT, LNRS, UNRS, MIDR, TAKL, CANO, CLRH, ULRD, SMOK, KHOR, MFRA) is in any score schema it reports. The committed CSV and the README claims are unaffected.
- **Numbers re-derived from the DB.**
  - The roxygen and research table of in-lake bcfishobs A/B records reproduces exactly: BT 146/94/44, CO 445/124/301, KO 354/282/67, RB 1357/710/624, SK 270/128/139.
  - The parity before and after differences match the stated connection km. FINA 393.5, PCEA 367.7 / 375.9, PARS 9.75 against 9.77, all within rounding.
  - The `pars_accessible.rds` diff is rearing −9.75 / −9.76. The 0.02 km spawning move is documented as input drift.
- **Tests.**
  - The validator fixture now gives BBBB seg 2 an edge 1450 line in a real lake polygon.
  - With the old default, `b$rearing_km` would be 0.2, so the 0.1 assertion can fail. The `rearing_lake_connection_km == 0` assertion on AAAA exercises the COALESCE.
  - BBBB observations o5 and o8 are dropped because BT is absent, so the 1450 change cannot move any capture assertion.
- **Rd.** `tools::checkRd` parses both changed Rd files. The only notes are non-ASCII text that was already there.

## Non-blocking notes (not defects)

1. **`rearing_km` is still NULL, not 0, where a group's only rearing is connection lines.**
   - In that case the new roxygen claim "the two sum to the flag total" reads `NA + x`.
   - That shape existed before (the default `rearing_km` never COALESCEd), and it is deliberate: byte-identity is the reason given in `task_plan.md`.
   - I queried every species table in `fresh` and `fresh_default` and found 0 (WSG, species) cases. So it moves no current number.
2. **Two places still say the default is the flag total, the opposite of the code.**
   - The code comment at `R/lnk_compare_rollup.R:204` reads "(the primitive's default rearing_km is the flag total)".
   - The bullet at `CLAUDE.md:21` reads "`lnk_rollup_wsg()`'s default `rearing_km` stays the flag total".
   - Neither affects output. The CLAUDE.md status is planned for `/planning-archive`. The `lnk_compare_rollup.R` comment is not on the plan.
