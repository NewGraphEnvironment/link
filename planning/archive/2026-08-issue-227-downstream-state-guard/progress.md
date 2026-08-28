# Progress — Single-WSG downstream-state guard (#227)

## Session 2026-08-28

- Plan-mode exploration: 2 Explore agents + 1 Plan agent.
- Plan agent found the issue's tier-1 check is a membership test that over-fires;
  independently verified the path predicate on PARS (3 Peace dams, matching RUNBOOK
  section 5) and BULK.
- Caught myself using the deprecated `nlevel(wscode_ltree) ASC` outlet heuristic in the
  first verification attempt — the very thing RUNBOOK section 8b warns about, added
  earlier today. Redone with `fresh::frs_wsg_outlets()`.
- User approved: warn mode + post-condition for multi-host; extract shared SQL builder
  for anti-drift.
- Created branch `227-single-wsg-downstream-state-guard` off main (9fc7303, v0.45.3).
- Next: Phase 0 regression net.
