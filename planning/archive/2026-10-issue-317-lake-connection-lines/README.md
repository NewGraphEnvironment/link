# #317 — Lake connection lines kept out of rearing km

## Outcome

#310 let every line in a lake polygon rear for `default`, including the FWA connectors (1450) that join each tributary mouth to a lake's main-flow line. So lake km grew with tributary count, and Adams Lake alone put ADMS CH at +91 % against bcfishpass.

The operator chose **centrelines for the km, but kept the lines in fresh's `rearing` flag**, because `cluster_rearing` needs them to join inlet rearing to the lake. So nothing re-classifies. The compare rollups (`lnk_compare_rollup()` / `lnk_compare_wsg()`) now report `rearing_lake_connection` km apart and leave those lines out of `rearing` and `rearing_lake` km, on the link side and the bcfishpass side alike. One NULL-safe predicate serves every site: `.lnk_sql_lake_connection()`.

**The wrong turn:** the approved plan also changed `lnk_rollup_wsg()`'s default `rearing_km`. Code-check round 1 and the plan review both found that this leaked into tools that compare the flag itself: the validator's cost (whose capture reads the flag), `parity_crosssection.R` and `wsg_vignette_data.R`, where SK would have read −70 % against a flag-based reference. So the primitive's default stays the flag total. bcfishpass turned out to count connection lines too (BT, SK), which is why the rule had to be symmetric.

Write-up: `research/habitat_thresholds.md`, "Lake connection lines: in `rearing`, out of the km (#317)".

## Measurement

All on #310's run-B snapshots (ADMS, NATR); no re-classify.
- **Connection km per species:** ADMS 159–164 km, NATR 213–275 km.
- **Narrowed after the PR opened.** The first cut also excluded 1400. The operator's ruling: "construction and connector are totally different". 1400 is "other flow / inferred connection", a construction flow line, while 1450 is "connection", so the predicate became 1450 only. Lake 1400 is at most 1.4 km of rearing, so only NATR BT and RB moved (the figures here are after the change).
- **ADMS against bcfishpass, old → new:**
  - CH +91.1 % → +38.9 %
  - CO +75.0 % → +28.7 %
  - BT +16.4 % → +2.0 %
- **NATR BT:** +29.8 % → +24.4 %.
- **CH / CO stay high** because bcfishpass has no CH / CO lake rearing on ADMS. The residual is lake flow lines (#310's call), not the line type. The issue's expectation that CH would come back near +14 % was wrong.
- **SK / KO:**
  - SK rearing km fall 55–95 % on seven WSGs, and identically on the bcfishpass side, so SK parity is 0.0 % on BULK, CHWK, NASR, NECR, QUES and THOM.
  - KO falls 62 % on NATR.
- **Pinned bands:** the CH / CO / ST taxonomy bands (BBAR, THOM, MFRA) do not move.
- **Rollup check:** the link-side rollup matches a flag-level measure to within 0.008 km.
- Suite: 2585 pass / 0 fail / 16 warnings (the baseline count).

## Evidence

`data-raw/logs/lake_connection_317/`

Closed by: PR (this branch, `317-lake-km-should-1450-connection-lines-cou`)
