# Plan review (Plan agent, 2026-10-29) — triage

Findings and what was done with each. Full reply in the session transcript.

| ID | Finding | Action |
|---|---|---|
| B1 | acc inputs: pooling/groups not read by the pipeline; cfg$species missing from plan; observation_exclusions is a decision | Done in the draft (findings "Deviations"); exclusions asked of the operator |
| B2 | refusal breaks test-lnk_pipeline_run composition tests | Done: resolver mocked in phase tests, real-resolver refusal test added |
| G1 | whether user_barriers_definite / _control / user_habitat_classification are declared moves cuts | Add a declared-inputs term to the cut spec |
| G2 | code rules (.lnk_classes_bcfp, lnk_presence() groups) move cuts | Add both to the acc payload; RUNBOOK: other code changes need a new token |
| G3 | parameters_fresh rows outside cfg$species | Kept: lnk_barrier_overrides reads every row (habitat lifts) |
| G4 | provincial run refuses per group after spend | Add the resolve to study_area_run.sh's local pre-flight |
| G5 | variant schemas carry no tokens; a variant can change flow | Out of scope; follow-up drafted for the operator |
| G6 | custom bundle (path) refused with no way through | Asked of the operator |
| G7 | existing builds have NULL tokens | Out of scope; the next provincial run writes them (Owed) |
| G8 | no naming rule for next revisions | RUNBOOK rule |
| O1-O2 | table needs the resolver; introduced = release version | Done (built together; 0.70.0) |
| O3 | tokens default resolves inside the logger | Kept: a direct call should refuse too, not log NULL |
| O4 | refusal outside `if (log)` | Done |
| A1 | the canonical form is frozen into every acc spec | Documented: changing it re-specs every acc token |
| A2 | consolidate drops source-only columns quietly if the dispatcher is older | RUNBOOK: the dispatcher runs this link (it does, via load_all) |
| A3-A6 | export carries tokens; overrides cheap; recompute needs none; other callers use shipped bundles | Confirmed, no change |
| S1 | flow fill applies only where discharge is read | Definition text |
| S2 | a network is cut + acc together | RUNBOOK |
| X1 | append-only guard is local only (shallow CI, R CMD check) | Stated in the test and RUNBOOK |
| X2-X4 | prefix map, package_version compare, quoting fixture | Done |
| X5 | live verification needs a shared scratch schema | Done at verification |
