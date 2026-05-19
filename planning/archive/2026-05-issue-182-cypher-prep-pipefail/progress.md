# Progress — cypher_prep.sh masks snapshot_bcfp.sh failures via | tail -5 pipeline (pipefail) (#182)

## Session 2026-05-15

- Plan-mode exploration: read `data-raw/cypher_prep.sh`, `data-raw/snapshot_bcfp.sh:270-285`, `data-raw/wsgs_run_pipeline.sh:255-275`. Confirmed two bug sites (lines 58 and 67-77) and the umbrella's marker-grep at line 264. Cross-referenced rtj#163 (`a0aef66`, 2026-05-18) which already swept rtj's cypher orchestration scripts for the same bug class.
- Phase breakdown approved by user.
- Created branch `182-cypher-prep-sh-masks-snapshot-bcfp-sh-fa` off main (current at `9a83978`).
- Scaffolded PWF baseline.
- Next: Phase 1 — patch `cypher_prep.sh`.
