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
