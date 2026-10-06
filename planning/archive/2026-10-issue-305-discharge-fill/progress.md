# Progress — Main stems with no discharge drop out of mad habitat (#305)

## Session 2026-10-06

- Plan-mode exploration, with a read-only discharge count (findings.md). The operator chose the network fill in link. Phases approved.
- Created branch `305-main-stems-with-no-discharge-drop-out-of` off main (`7ac73ad`)
- Scaffolded PWF baseline from issue #305 with approved phases
- Next: start Phase 1

- Plan review (Plan agent) → `review-plan.md`; plan revised (typed join, recorded fill state,
  validator line scoping, Phase 4 reuses #300's working schemas, knob in default_tuned only).
- Phase 1 run (dirty tree, pre-review): tiers 1–2 left 330 km of #300's BT band (the Beatton,
  UBTN, no rows anywhere). Tier 3 changed from "downstream line" (would take the Peace) to the
  upstream tributary max. Logs regenerate at a clean HEAD after this commit.
- Phase 2/3 code: prepare, log column, validator, default_tuned knob, RUNBOOK, harness.
- /code-check: 4 rounds (R1 2 fixed; R2 2 fixed, one inside R1's fix; R3 1 fixed, inside R1's
  fix; R4 enumeration of 22 places, clean). Files `review-round{1..4}.md`.
- Code commit `312e195`. Phase 1 re-run at that clean HEAD (`discharge_fill_305/stamp.txt`).
- Phase 3 regression: #300 re-scored with the new code → byte-identical summary/totals/
  habitat_change/model_bands*, model_reason/size/verdict ≤ 7.4e-15 rel
  (`discharge_fill_305/rescore300/`).
- Phase 4: `--step=variants` on `working_score300_*` (31.5 min, every base digest matched
  #300's), score exit 0. BT rearing cw-only 0.71 → 0.19; #300's cw-favouring verdicts were
  the discharge gap. Issue body edited (Decided section; "most" corrected).
