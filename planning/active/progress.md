# Progress — Lake km: should 1450 connection lines count as lake rearing? (#317)

## Session 2026-10-08

- Plan-mode exploration — phases approved by user
- Operator calls: lake km are centrelines; connection lines kept out of km by a rollup split, not by the rule (clustering needs them)
- Created branch `317-lake-km-should-1450-connection-lines-cou` off main
- Scaffolded PWF baseline from issue #317 with approved phases
- Next: start Phase 1
- Phase 1 measured on #310's run-B snapshots (no re-classify): connection km is almost all 1450 (1400 ≤ 1.4 km). ADMS CH vs bcfp +91.1 % → +38.9 %, CO +75.0 % → +28.7 %, BT +16.4 % → +2.0 %; NATR BT +29.8 % → +24.3 %. bcfishpass also counts 1450 in BT / SK rearing, so the rule must run on both sides (SK 0.0 % both ways; link-only would read −69 %). `data-raw/logs/lake_connection_317/`
