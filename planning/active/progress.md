# Progress — rearing_km means two things (#319)

## Session 2026-10-08

- Plan-mode exploration — phases approved by user ("go all phases to pr")
- Created branch `319-rearing-km-means-two-things-lnk-rollup-w` off main
- Scaffolded PWF baseline from issue #319 with approved phases
- Next: start Phase 1
- Parity baseline on unchanged code: `data-raw/logs/lake_connection_319/parity_crosssection_before.txt` (25/25 PASS, 13 s)
- Phase 1: default `rearing_km` = `rearing AND NOT connection`; new default `rearing_lake_connection_km` (COALESCE 0). Tests red first (3), then green; live test ran on fresh_default (192 pass in rollup+compare files)
