# Progress — Lake km: should 1450 connection lines count as lake rearing? (#317)

## Session 2026-10-08

- Plan-mode exploration — phases approved by user
- Operator calls: lake km are centrelines; connection lines kept out of km by a rollup split, not by the rule (clustering needs them)
- Created branch `317-lake-km-should-1450-connection-lines-cou` off main
- Scaffolded PWF baseline from issue #317 with approved phases
- Next: start Phase 1
- Phase 1 measured on #310's run-B snapshots (no re-classify): connection km is almost all 1450 (1400 ≤ 1.4 km). ADMS CH vs bcfp +91.1 % → +38.9 %, CO +75.0 % → +28.7 %, BT +16.4 % → +2.0 %; NATR BT +29.8 % → +24.3 %. bcfishpass also counts 1450 in BT / SK rearing, so the rule must run on both sides (SK 0.0 % both ways; link-only would read −69 %). `data-raw/logs/lake_connection_317/`
- Phase 2 + 3 (one commit, so the rollup is never asymmetric): `.lnk_sql_lake_connection()` (NULL-safe) + `connection` alias in `lnk_rollup_wsg()`; compare family (link side, bcfishpass side, long format) reports `rearing_lake_connection` and leaves it out of `rearing` / `rearing_lake` km. **Design correction from code-check round 1 + plan review:** the primitive's default `rearing_km` stays the flag total. Changing it leaked the rule into the validator's cost (capture reads the flag), `parity_crosssection.R` and `wsg_vignette_data.R` (SK −70 % against a flag-based reference).
- Live: `rollup_check.csv` matches Phase 1 to ≤ 0.008 km; bcfishpass-config parity on 9 taxonomy-pinned WSGs (`parity_bcfishpass.csv`): SK rearing 0.0 % in all seven WSGs where bcfishpass models SK (no SK reference at BBAR, no SK at MFRA), connection km equal on both sides to within 0.3 %, CH / CO / ST bands unchanged. Suite 2584 pass / 0 fail / 16 warn.
- Phase 4: RUNBOOK §7 #317 bullet, `research/habitat_thresholds.md` section "Lake connection lines", `bcfishpass_methodology.md` note, default README + `dictionary_dimensions.csv`, CLAUDE.md status; issue #317 body edited with the decision. Code-check r3 caught a RUNBOOK bullet inserted mid-list and an SK / KO drop generalised from two rows (now SK 55–95 % on seven WSGs, KO 62 %); r4 clean.
