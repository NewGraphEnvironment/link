# Code-check round 5: 33bc88fb..f3b74715 (round-4 fixes + NEWS 0.66.0)

## Mechanism

Earlier rounds found the same thing four times. A claim takes its noun or its scope from a
nearby sentence, an earlier draft, or the wider population, and is never re-derived from the
artifact for the exact set it names: rows called lines, a value called scored because the
rearing value beside it was, a rearing ratio stated for both flags, locations called records.
A second form follows from the first. When a fact is stated in several files, a fix lands in
the file the reviewer pointed at and the other copies keep the old wording. This round's
findings are both forms: a fix applied in research/README/config but not in NEWS's headline
or RUNBOOK, and a sentence extended to cover spawning that now carries a rearing-only
qualifier.

## What was checked, and holds

- 4,532,843 rows, 4,503,352 valued, so 29,491 zeros (mad_wet/stamp.txt). fwapg has
  2,716,652 rows, 2,003,189 valued, so 713,463 NULLs (mad_fwapg/stamp.txt). The relation
  holds one row per `linear_feature_id` (R/lnk_discharge.R `.lnk_discharge_sources()`).
- Of the 58 spawning-staged BT locations on wet, 41 are in the Skeena (MORR 20 + BULK 12 =
  32). Recomputed from obs_mad.csv: stream/river_poly, access 1/2, mad not NA. fwapg has 17.
  The Skeena P10 is 0.0125675, so 0.013 (quantiles.csv).
- The held-out core holds 3 spawning-staged locations (habitat_score_331/verdict.csv `n_core`).
- Build B ratios: 0.18 / 0.14 / 1.64 / 0.69, fwapg 0.15 / 0.13 / 1.65 / 0.72. Change:
  −19.8 % (13,881 → 11,136). model_reason: 6 + 3,091 + 12 km and 1 + 20 + 1 locations.
- NATR: 0 of 189,200 rows changed habitat; `mad_m3s` changed on 189,092 of them.
- Width conversions (0.043 / 0.042 / 0.023 / 0.021). The thresholds CSV values in the README.
- Code claims in NEWS. Prepare stops via the preflight in `.lnk_discharge_join`. The loader
  skips or reloads on `--expect-load`. study_area_run.sh has the dispatcher gate and the
  `CYPHER_PREP_WET_LOAD` pass. wsgs_run_pipeline.sh and wsgs_dispatch.sh refuse non-fwapg.
  `log_input.table_comment` is written, and a wet run adds wet's table (`cfg` is passed at
  R/lnk_pipeline_run.R:167). The manifest has `discharge.source`, `discharge.wet_load`.
  `wet (>= 0.4.7)` is in Suggests. The fwapg relation is unchanged. The harness writes the
  source and fill into each bundle and records them in built.csv. Both producers take
  `--discharge-source`.

## Findings

- **[claim]** NEWS.md:3. The headline says "with BT's MAD minima re-scored on it". This is
  the overclaim round 4 removed from config.yaml, the README and research. Only
  `rear_mad_min` was scored. 0.043 was never a scored spawning rung (habitat_score_331 and
  _spawn_any verdicts: the spawning rungs are 0.012 / 0.0063 / 0.0019). The bullet at
  NEWS.md:8 states this correctly, so the entry contradicts itself.

- **[claim]** RUNBOOK.md:1002 (§7, which the CLAUDE.md 2026-10-16 block names as the
  mechanics). It says wet "values about 4.5 M lines against fwapg's 2.7 M". 2.7 M is
  fwapg's row count. It values 2.00 M lines (mad_fwapg/stamp.txt: 2,003,189 with
  mad_m3s). This is the rows-as-lines claim round 4 fixed in research:1162-1163 and that
  NEWS.md:5 now states correctly, and the fix did not reach this copy.

- **[claim]** research/habitat_thresholds.md:1280-1281. "#305 … read '`cw`-only not
  habitat' with `mad`-only underpowered; at 0.043 the `mad`-only band has power for the
  first time." The fix extended this bullet to spawning (1.64 / 0.69), and the clause is
  true for rearing only. For BT spawning the `mad`-only band already had power in #300
  (expected 14.3, ratio 0.42, "not habitat") and in #305 (expected 14.6, ratio 0.41, "not
  habitat"). Sources: habitat_score_300/ and habitat_score_305/model_verdict.csv. #305's
  spawning reading was "the models differ only on little-used water", not "`cw`-only not
  habitat". Scope the clause to rearing.

- **[claim]** NEWS.md:8 and inst/extdata/configs/default_tuned/README.md:17 both say the
  held-out groups "hold too few spawning-staged **records** to score it". The evidence is
  locations, not records: the held-out core holds 3 spawning-staged locations, and the
  bands hold 0 found against 0.7 expected (habitat_score_331/verdict.csv `n_core`,
  `n_band`). The scorer counts locations. Round 4 flagged this records/locations slip in
  CLAUDE.md, and research:1228-1229 and CLAUDE.md:18 now say "locations", but these two
  copies did not change.

- **[claim]** research/habitat_thresholds.md:3 (header Status) says "MAD ranges for BT,
  GR and RB **scored** (the rule refused loosening past P10 except RB spawning)". The same
  line then gives BT's current minima as "0.043 / 0.043 (#331: rearing scored, spawning on
  any-stage records)" and never says the spawning value is unscored. Read in order, the
  status still says BT's spawning MAD value is scored. config.yaml now says "(unscored)",
  and so does the verdict table at research:1172. The header line should say the same.

- **[claim]** research/habitat_thresholds.md:1153-1155, CLAUDE.md:220-222 and
  CLAUDE.md:295. All three say #302's ladders "regenerate only at v0.58.0" and that
  `--base=default` "stops with 'variant … equals default'". This branch changes that:
  habitat_variants_build.R now drops a `set` cell the base already carries. NEWS.md:11
  says "#302's ladders build at HEAD again", and progress.md records that
  `variants_302.csv` regenerates 18 bundles at HEAD. The three passages are a "fact not
  worth re-deriving" that is now false. They contradict NEWS and the harness README
  (data-raw/habitat_score/README.md, new #331 paragraph).

- **[claim]** inst/extdata/configs/default_tuned/config.yaml:28-30. The `discharge_fill`
  comment says the fill applies to edge 1250 lines "with no value in
  fwa_stream_networks_discharge". This bundle now reads wet (`discharge_source: wet`,
  line 46), and the fill reads the bundle's source: `.lnk_discharge_sql(source =)` →
  `.lnk_discharge_candidates_sql(source =)`, whose roxygen says "The fill reads the same
  source". So on this bundle it fills lines with no value in wet's pick, wet's zeros
  included. The branch edited this file without updating the comment.

- **[claim, minor]** NEWS.md:6 says "the validator warns when the log and the bundle
  disagree". It warns only for WSGs where `cfg` reads discharge, meaning a `mad` group or
  a rule-level `mad:` (R/lnk_habitat_validate.R:480-482, `reads & logged_src != …`).
  Validating today's all-`cw` `default_tuned` against a schema logged under fwapg gives no
  warning. RUNBOOK §7 states the scope correctly ("where `cfg` reads discharge").

- **[claim, minor]** CLAUDE.md:16 says the source is "named in the export manifest
  (`discharge.wet_load`)". The per-WSG source is `discharge.source`
  (R/lnk_scenario_export.R:982). `discharge.wet_load` names which wet load the builds
  logged against the exporting database's, and it is present only when some WSG read wet.

- **[claim, minor]** default_tuned/README.md:17 says "(BT's on wet in 56)". 56 is the
  calibration set (mad_wet/stamp.txt). BT's observations are in 53 of those groups
  (mad_wet/coverage.csv `n_wsg` 53 for BT any), and the spawning-staged ones in 13. This
  is the slip round 4 named: a set's size given for a narrower population.

No code defect found in this round's diff. Its only code-adjacent change is the
config.yaml description, which is correct.
