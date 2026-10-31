# Progress — Check each group's species presence against its fish records (#402), part 2

## Session 2026-10-31

- Plan-mode exploration; operator answered the gate questions (screen records first; salmon tests; KO after historic-access homework; single records species-dependent; the 24 present cells read together); phases approved
- Created branch `402-screen-fish-records` off origin/main (`ba5fef36`)
- Scaffolded PWF baseline from issue #402 with approved phases
- Next: start Phase 1
- Plan review folded in (review-plan.md); operator chose measures now, verdicts in the decision session; verdict function removed; historical zones fetched (16,525 reaches, 74 species)
- Measures in R/lnk_presence_measures.R: province-wide in 56 s; 2,574 records filed under a group their own 50k code does not run through (the review's count); cell aggregation tested; live test of the barrier direction
- Driver extended: measures.csv (6,111 cells), recall.csv, measure sentence in every story; tracker re-seeded (351 pending refreshed, decided rows untouched); SQL recount of the measures for PARS, ADMS, ALBN agrees (106 cells)
- Recall: of the 67 data_error records, 36 sit above a blocking barrier with at most 2 class records above it, 21 above 1,400 m, 6 on a gradient of 0.25 or more; 47 caught by any of the three; 20 (steelhead likely misidentified rainbow, misplacements within reachable water) have no geometric tell. Their own 50k code is in their group for all 67; 49 of 67 sit on a stream with a historical zone of the species, so the zones do not separate errors.
- Write-up: research/species_presence.md 'Measures before a record counts'; RUNBOOK §5; CLAUDE.md status; pretest_inputs none row for R/lnk_presence_measures.R (test-pretest's reach check passes); log README
- Code-check round 1 (review-round1.md): 4 bugs, 4 fragile, all fixed. Waterbody redefined (bcfishobs shares one stream waterbody_identifier per group: single-waterbody cells 153 -> 121); zones' CT aliases folded; recount now independent of the measures' tables; stamp flags dirty code; numbers corrected from the regenerated outputs (recall 47/20 -> 46/21; KO lake 3,374 records above a barrier, 42 with no lake; 179,815 species-locations; 319 of 351 stories carry measures). Outputs regenerated at 3ef7be22.
- Code-check round 2 (review-round2.md): 1 bug, 3 fragile, fixed in e07e521e. Waterbody is now a lake's or wetland's own id, else the matched blue line (single-waterbody cells 121 -> 117); recount reads the zones CSV and adds waterbodies and years, main stem no longer claimed; dirty check sees untracked files and data inputs. Outputs regenerated at e07e521e; recount agrees (106 cells).
