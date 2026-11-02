# Progress — Turn species off in a bundle's runs with a dated tracker (#432)

## Session 2026-11-01

- Plan-mode exploration — phases approved by user; #433 decided at the gate (off means off; groups with no modelled species still modelled)
- Created branch `432-turn-species-off-in-a-bundle-s-runs-with` off origin/main
- Scaffolded PWF baseline from issue #432 with approved phases
- Next: start Phase 1
- Phase 1 (unit tests) and Phase 2 (the switch): `species_modelled.csv` in `default` (KO, RB `f`), `.lnk_species_modelled()` in `lnk_config()` with its refusals, `cfg$species_paused`, dictionary, provenance checksum, pre-run gate rows (segments, gradient), bundle README. `acc-v5` added and `acc-v4` retired at 0.76.0 (default and default_tuned share spec `sha256:85dcafad…`). Tests: config 203, dictionaries 130, prepare 233, config_verify 40, vocabulary 51, pretest 90 pass.
- Plan review landed (`review-plan.md`, 25 findings) and was folded in: `lnk_persist_init()` keeps paused species' tables and columns so consolidate clears them (the blocker), clearing moved after the first persist and extended to near-river pairs, verifier assertion on stale habitat rows, compare/validator/variants handle paused species.
- Phase 3: a group with only paused species is built for segments, barriers, access and mapping-code rows, with no habitat (`lnk_pipeline_run()`, persist, views, `lnk_access()`, mapping code, `wsg_run_one.R`, `wsg_recompute_one.R`). Live: MURT into `zz432_dev` in 1.2 min, 14,403 segments, 25,765 barrier rows, no habitat. `lnk_wsg_resolve()` counts paused species (241 groups; 234 without; CHUK has only DV and was never in the 241).
- Phase 4: six groups built before (07203cde) and after (a6942b5d) into `zz432_pre` / `zz432_post` (fresh 0.52.0 both). Segments −0.2 % (BULK) to −6.0 % (KETL); barriers and overrides identical; accessible km unchanged; habitat moved only in KOTL (BT rearing 20.9 km flips, +5.4 net) and KETL (0.4 km); 33/1,473 KOTL records on a changed segment (median Δgradient 0.012). Live clearing: SALR re-modelled into the before schema, RB rows 10,676 → 0. New verifier assertion passes both arms, fails on planted rows. KOTL's recompute fails the downstream post-condition in both arms (scratch schema lacks the group below). Write-up `research/species_paused.md`; evidence `data-raw/logs/species_paused_432/`.
