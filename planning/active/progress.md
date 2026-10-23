# Progress — #367

## Session 2026-10-22

- Step 0 (before the plan): #316 measured on `fresh_default` and left out (comment on #316); bcfishpass CSV sync confirmed running weekly with no drift since 2026-09-30
- Plan-mode exploration — phases approved by user; "go all phases to pr"
- Created branch `367-before-the-next-provincial-default-run-a` off main
- Scaffolded PWF baseline from issue #367 with approved phases
- Next: start Phase 1
- Phase 1 done: `.lnk_pscis_pick_order` ends on `modelled_xing_dist, modelled_crossing_id`; DBSCAN dedup ends on `stream_crossing_id`. Province-wide, 931 PSCIS had a tie between modelled crossings under the old order; under the new one, no output-changing tie remains. Mock and DB tests pass; the DB test fails under the old order (mutation check). Plan review spawned 23:09 UTC, background
- Phase 2 done: `pipeline: cabd_additions_barriers` (set in `default`, validated at load); `.lnk_dams_usa_sql()` shared by prep and guard, numbered by position; guard probes the placeholders under the knob. #345 re-pinned on 7 ids (the eighth left CABD upstream; the reference DB agrees). Tests pass; both DB tests fail with the knob forced off
- Plan review delivered (~23:18 UTC): bcfp's per-stream nearest step was missing (B1), plus ordering gaps and Phase 3 isolation. Folded in: Step 3b ported, barrier ids and snaps ordered, placeholders in CSV order with `barrier_ind`, flavour-correct comment, Phase 3 redesigned. Repeat builds: main 464 differing picks between two builds, branch 0
- Phase 3 done (builds 23:23-00:13 UTC, LARL re-run after a harness race): branch builds reproducible; the knob moves only dam flags and 19,065 mapping codes NONE->DAM; main vs branch moves at most 0.094 km per species. Evidence `data-raw/logs/provincial_prep_367/`
