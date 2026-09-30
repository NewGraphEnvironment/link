# Progress — #284 step 5 (scoring)

## Session 2026-09-29

- Plan-mode exploration — phases approved by user; four gate decisions taken (adjacent-step bands, calibration-stage observations, exported `lnk_habitat_validate_band()`, full 20-WSG closure).
- Created branch `284-research-calibrate-ch-and-bt-gradient-an` off main (097419f).
- Scaffolded PWF baseline with approved phases. User: "go all phases" — run to PR.
- Next: Phase 1.
- Phase 1: absence taxa to `data-raw/fiss_absence_taxa.csv`; loaders to `habitat_validate_inputs.R`; #283 outputs byte-identical (knowledge pinned at 508bf44).
- Phase 2: `lnk_habitat_validate_band()` + 36 tests; mutation-tested in a scratch copy.
- Plan review (Plan agent): 3 blockers. Power check confirmed B1; operator chose BT only with a widened held-out set, and an underpowered step changes nothing. Rule revised with its counts before commit.
- Phase 3 code written (`habitat_variants_build.R`, `habitat_variants_score.R`), review gaps G1–G8, AC1, AC4 folded in.
- Code-check: 5 rounds plus an enumeration. Rounds 3, 4 and 5 each found a defect inside the previous fix (the per-row walk, bundle provenance, the resume key). All fixed and probed. Summary in `review-enumeration.md`.
- BULL pre-flight: invariants hold, bands reconcile, and the pipeline runs end to end. Next: commit, drop the pre-flight scratch schemas, launch the full build detached.
