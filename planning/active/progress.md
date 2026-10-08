# Progress — wetland_ha_min now gates rearing in fresh (fresh#237); default* outputs move (#311)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user (carve-out floored; pin to fresh v0.39.0 here)
- Created branch `311-wetland-ha-min-now-gates-rearing-in-fre` off main
- Scaffolded PWF baseline from issue #311 with approved phases
- Next: start Phase 1

- Plan review (Plan agent): no blocker; acted on the `rear_wetland_polygon = no` case, the 1050/1150-only acceptance, B-vs-C scoring, dictionary rows. See findings.md
- Phase 2 committed `0ca706b` (/code-check: 3 rounds, all clean)
- fresh v0.39.0 installed (`e247ca1`); every bundle loads, floored carve-out compiles for BT CH CO RB ST WCT in default*, none in bcfishpass; preflight OK
- Phase 3: A/B/C on ADMS, BULK, NATR, PARS. A→B reproduces fresh exactly; B→C −198.8 km rearing, 3 of 2,265 observation locations
- Next: full test suite on v0.39.0, commit Phase 1 (pin), Phase 4 docs + issue bodies
