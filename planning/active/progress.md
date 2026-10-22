# Progress — #367

## Session 2026-10-22

- Step 0 (before the plan): #316 measured on `fresh_default` and left out (comment on #316); bcfishpass CSV sync confirmed running weekly with no drift since 2026-09-30
- Plan-mode exploration — phases approved by user; "go all phases to pr"
- Created branch `367-before-the-next-provincial-default-run-a` off main
- Scaffolded PWF baseline from issue #367 with approved phases
- Next: start Phase 1
- Phase 1 done: `.lnk_pscis_pick_order` ends on `modelled_xing_dist, modelled_crossing_id`; DBSCAN dedup ends on `stream_crossing_id`. Province-wide, 931 PSCIS had a tie between modelled crossings under the old order; under the new one, no output-changing tie remains. Mock and DB tests pass; the DB test fails under the old order (mutation check). Plan review spawned 23:09 UTC, background
