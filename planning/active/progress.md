# Progress — Turn species off in a bundle's runs with a dated tracker (#432)

## Session 2026-11-01

- Plan-mode exploration — phases approved by user; #433 decided at the gate (off means off; groups with no modelled species still modelled)
- Created branch `432-turn-species-off-in-a-bundle-s-runs-with` off origin/main
- Scaffolded PWF baseline from issue #432 with approved phases
- Next: start Phase 1
- Phase 1 (unit tests) and Phase 2 (the switch): `species_modelled.csv` in `default` (KO, RB `f`), `.lnk_species_modelled()` in `lnk_config()` with its refusals, `cfg$species_paused`, dictionary, provenance checksum, pre-run gate rows (segments, gradient), bundle README. `acc-v5` added and `acc-v4` retired at 0.76.0 (default and default_tuned share spec `sha256:85dcafad…`). Tests: config 203, dictionaries 130, prepare 233, config_verify 40, vocabulary 51, pretest 90 pass.
