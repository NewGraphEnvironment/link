# Task: Lake km: should 1450 connection lines count as lake rearing? (#317)

## Problem (link@4580717, v0.61.0)

- #310 admits lake and reservoir lines to the `default` lake rear rule: `1000/1100/1200/1250/1300/1350/1400/1450/1475`.
- Edge type 1450 ("Construction line, connection") joins each tributary mouth to the main-flow line (1200) across the lake. It is not a flow path through the lake.
- Measured (`data-raw/logs/lake_connected_310/`):
  - Adams Lake (13,229 ha) holds 211.6 km of ADMS CH / CO rearing lines: 62.8 km of 1200 and 148.8 km of 1450.
  - On NATR, BT's lake km are 275.0 km of 1450 and 227.6 km of 1200.
  - Province-wide, lakes hold 54,402 km of 1200 and 44,528 km of 1450.
- Against bcfishpass, ADMS CH rearing goes from +14 % to +91 %, and CO from +3 % to +75 %. Without Adams Lake those would be about +22 % / +15 %.

The issue named 1450 among the lake edge types, so #310 kept it.


## Context

#310 (v0.61.0) admitted every line inside a lake / reservoir polygon to `default`'s rear L
rule, connection lines 1400 / 1450 included. Those lines join each tributary mouth to the 1200
main-flow line across the lake. So lake km scale with a lake's tributary count: Adams Lake's
148.8 km of 1450 takes ADMS CH to +91 % rearing against bcfishpass.

One flag does two jobs. fresh's `rearing` boolean drives `cluster_rearing` (adjacent rearing
segments form a cluster, and 1450 joins inlet rearing to the lake), and the rollups sum the
same flag. Today the rollup splits `rearing_km` only by polygon (stream / lake / wetland,
`.lnk_sql_waterbody_class()`, `R/lnk_rollup_wsg.R:196-232`), so 1450 sits in
`rearing_lake_km` and in the headline total.

**Operator decision (2026-10-08): split it in the rollup, keep the lines in `rearing`.** No rules
change and no re-classify, so clustering is unchanged.
- `rearing_lake_km` becomes lake flow lines only.
- New `rearing_lake_connection_km` holds lake-polygon lines on edge 1400 / 1450.
- Headline `rearing_km` excludes connection lines, so `stream + lake + wetland = rearing_km`
  still holds, and `rearing_km + rearing_lake_connection_km` equals the segments flagged `rearing`.

Defaults I'm taking (stated, not asked):
- **One rule for every species, bundle and side.** The rule is a km definition, not a habitat
  rule, so it applies to SK / KO too: their `rear_lake_only` L rule has no edge filter, so it
  admits 1450 (`lnk_rules_build.R:342`). It applies to the `bcfishpass` bundle, and
  symmetrically to the bcfishpass reference side (`.lnk_compare_wsg_rollup_bcfishpass`), so
  `diff_pct` stays like-for-like. Phase 1 measures what moves.
- **Connection = `waterbody = 'lake' AND edge_type IN (1400, 1450)`.** Scoped to lake polygons:
  no rule admits construction lines in wetlands today, and the stream rule never admits them.
- **Shipped `streams_habitat` still flags 1450 `rearing`.** Anything summing the flag directly
  (`lnk_aggregate()` per-crossing, which goes through `fresh::frs_aggregate`) keeps the old
  number. This is documented, not changed here.

## Where `rearing` km are summed (all four SQL sites)
- `R/lnk_rollup_wsg.R:105` — the default `rearing_km` metric, plus the per-species aliases (`:150-160`)
- `R/lnk_compare_rollup.R:211-224` — `km_metrics` passed to `lnk_rollup_wsg()`
- `R/lnk_compare_wsg.R:239-262` — `.lnk_compare_wsg_rollup_link()` (working schema)
- `R/lnk_compare_wsg.R:383-420` — `.lnk_compare_wsg_rollup_bcfishpass()` (reference side)
- Long-format metric map at `R/lnk_compare_wsg.R:495-515`; taxonomy metrics in `research/bcfp_divergence_taxonomy.yml`

## Phase 1: Measure before code
- [ ] `data-raw/logs/lake_connection_317/measure.R` over the existing #310 run-B snapshots (`zz310_snap.{adms,natr}_b` against `zz311_{adms,natr}.streams`, edge_type on the streams table). Per WSG × species, from the flag:
  - `rearing_km` old and new;
  - `rearing_lake_km` old and new;
  - `rearing_lake_connection_km`, split 1400 / 1450;
  - check that stream + lake + wetland equals the new total.
- [ ] Same rule on the reference (local `fresh.streams_vw_bcfp`, `rearing_<sp> IN (1,2)`): bcfp's own connection km per species, and `diff_pct` old → new per cell (ADMS CH / CO expected back near +14 % / +3 %; SK / KO movement on both sides named)
- [ ] Log README with stamp, results table, and the Adams Lake line

## Phase 2: One predicate, tests first
- [ ] Tests (fail first) in `test-lnk_rollup_wsg.R`:
  - the SQL carries a `connection` alias;
  - the default `rearing_km` excludes it;
  - the connection predicate names lake + 1400 / 1450.
- [ ] Add `.lnk_sql_lake_connection()` beside `.lnk_sql_waterbody_class()` in `R/lnk_rollup_wsg.R`, so one rule serves every site. Expose it as a `connection` alias in `.lnk_rollup_wsg_sql()`. The default `rearing_km` becomes `rearing AND NOT connection`.
- [ ] Roxygen for `lnk_rollup_wsg()`: the `connection` alias, the new partition sentence, and an example with `rearing_lake_connection_km`; `devtools::document()`

## Phase 3: Thread through the compare family
- [ ] Tests first in `test-lnk_compare_rollup.R` / `test-lnk_compare_wsg.R`: the new column / metric row exists; `rearing_km` and `rearing_lake_km` exclude connection lines; the parts still sum
- [ ] `lnk_compare_rollup.R` `km_metrics`: `rearing_km` and `rearing_lake_km` exclude connections; add `rearing_lake_connection_km`
- [ ] `lnk_compare_wsg.R`: the link side and the bcfishpass side get the same predicate; add the `rearing_lake_connection` metric (km) to the long-format map; update `@return` docs
- [ ] `research/bcfp_divergence_taxonomy.yml`: header comment + any `metric:` list that needs the new slice
- [ ] Live check on `zz311_adms` / `zz311_natr` via `.lnk_compare_wsg_rollup_link()`: parts minus total ≤ 0.01; `rearing_km + connection` equals Phase 1's flag total; numbers equal Phase 1's measure. One persisted WSG through `lnk_compare_rollup()` (`fresh_default`, ADMS) as well.
- [ ] `devtools::test()`, `lintr::lint_package()`

## Phase 4: Docs
- [ ] RUNBOOK §7 (:738-750): the rollup partition, the connection column, and the fact that `streams_habitat` still flags them
- [ ] `research/habitat_thresholds.md`: new section "Lake connection lines kept out of km", with header line, Phase 1 numbers and log prefix; `research/default_vs_bcfishpass.md` if its ADMS figures move
- [ ] `configs/default/README.md:10` + `dictionary_dimensions.csv` `rear_lake` row: lines in `rearing`, connection km reported apart
- [ ] CLAUDE.md Status entry; issue #317 body edited with the decision and result

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (no merge)
