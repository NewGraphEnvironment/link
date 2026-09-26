# Progress — Validate modelled habitat against fish observations (#283)

## Session 2026-09-26

- Plan-mode exploration — phases approved by user; decisions: read-only baseline
  (no model runs; default_tuned scoring stays #284 step 5), access = `streams_access`
- Created branch `283-validate-modelled-habitat-against-fish` off origin/main
- Scaffolded PWF baseline from issue #283 with approved phases
- Next: Phase 1
- Phase 1: #283 body corrected (fresh#218 join artifact, circularity, scope); commit fc856d8
- Plan review (Plan agent) returned 1 blocker + 4 gaps + 6 assumptions; verified B1 (default's
  pipeline.schema is `fresh`, 65 bcfishpass log rows), G1 (fresh exports frs_params /
  frs_habitat_predicates), folded in — see task_plan "Design changes"; review saved to
  review-plan.md
- Phases 2-3: lnk_habitat_validate() + 71 tests incl. DB fixture; mutation check — bare
  id_segment habitat join fails 6 tests; lint clean. MORR/BULK smoke run in ~3 s.
- /code-check: 4 rounds (review-round1..4.md). R1 4 findings (UHC indicator, integer64,
  absence rearing definition, negative gradient label); R2 6 (FISS "caught fish, no species"
  counted as absences — 63% of BT absences in the probe; zero-row crash; `any`-stage reason;
  spawn gradient floor derived twice — inside an R1 fix; unbuffered absences; stale outputs);
  R3 named 3 mechanisms and enumerated 59 rows, 6 inconsistent; R4 re-walked the
  enumeration, 2 left (absence silent-zero on the WSG axis; stamp wording) — fixed.
  Found by running the driver, not by review: `toupper(NULL)` is character(0), so an absent
  --wsgs selected zero WSGs.
- Reconciliation (AC1): `fresh_default` retains BT+DV 5,104 and CH 1,745 locations, exactly
  #284's pooled counts.
- Outside-UHC capture added after the baseline showed 237/245 spawn-staged CH in UHC
  reaches (9a4c191); R5 found the UHC test read the point while buffered capture read a
  window — fixed (0c19e0a).
- Final baseline at 0c19e0a → data-raw/logs/habitat_validate_283/; research/habitat_validation.md
- Full suite: preflight drift guard failed on the undeclared fresh symbol -> declared; and
  fresh@v0.33.0 (pinned minimum) has no `model` arg on frs_habitat_predicates -> dropped,
  guarded by a test that fails with it restored (fb5a27a). Remaining 3 failures are the
  :63333 tunnel being down.
