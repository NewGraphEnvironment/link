# Progress: Recompute: test existence instead of building natural-barrier arrays, and walk each barrier set once (#394)

## Session 2026-10-28

- Plan-mode exploration; phases approved by user (fold #409 in; lever 2 measured before it is built)
- Created branch `394-recompute-test-existence-instead-of-buil` off main
- Scaffolded PWF baseline from issue #394 with approved phases
- Next: start Phase 1
- Phase 1: pinned fresh v0.47.0, preflight asserts `frs_network_features(result)`, wrote measure.R
- Phase 2: lever 1 in `lnk_pipeline_access()`, four mocked tests; mutating the mode to all-`ids` fails three of them and to all-`exists` fails three (one shared). Tests run on fresh 0.47.0 from a scratch library.
- Plan review delivered (`review-plan.md`); round 1 stopped at 03:12 for the collision it found, measure.R moved to its own scoped table, model_digest.R written for #409's per-table check. Round 1 relaunched 03:15 UTC.
- Lever-2 gate, 2026-10-29 04:08 UTC (SALR, CHWK, LFRA at `exists`; SETN still running): repeated species walks are 55.0 % of walk seconds (CHWK 0.575, LFRA 0.571, SALR 0). Gate passed, lever 2 committed. Mutations of it (keys ignored, one key for all, `concat_ws` instead of record text, no admissibility scope, no `watershed_group_code`) each turn a named test red.
- Round 1 done 05:31 UTC, round 2 timings 05:51 UTC. Access step SALR / CHWK / LFRA / SETN: base044 26.9 / 535.0 / 1,145.7 / 763.6 s; prefilter 3.9 / 21.5 / 89.5 / 347.3; exists 4.0 / 19.6 / 74.5 / 292.0; dedup 4.0 / 9.3 / 35.3 / 136.5. All digests equal base044. Scratch models m044 = m047 = b047 (20 of 20 digests).
- Plan correction: the review's keep criterion (per group, dedup below exists) misses in SALR by 0.06 s, inside its four-run spread (3.84 to 4.15 s); the key query is its only cost there (0.16 s). Kept: the user's gate was the 10 % ceiling, and the three groups with repeats halve.
- /code-check branch, three rounds. R1: 3 code fixes (empty-wscode subpath error, untested blue-line arm, a keyed view given as a source walked twice) + 3 doc fixes; each code fix's reversal turns its test red. R2: contract gap (watershed_group_code) + 2 README figures. R3: no code defect; mechanism named (the key restates what fresh's walk reads) and enumerated over 12 places, all holding; one doc figure (57 → 58 %). No round found a defect inside a previous fix.
- Full suite with fresh 0.47.0 in the shared library: 4,654 pass, 2 errors (test-lnk_wsg_resolve closure tests, `lnk_db_conn()` defaults reach a tunnel port that is down). devtools::check(): the same plus test-lnk_db_conn; its 3 warnings and 3 notes are all on main too (non-ASCII, missing Rd links, `presence` undocumented, bare `setNames`). lintr: the branch's R/ file 0 lints, its test files no new lints; the three measurement scripts keep 25 indentation lints as they ran.
