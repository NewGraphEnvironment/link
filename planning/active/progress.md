# Progress — #246 pre-flight gates

## Session 2026-08-30

- Plan-mode exploration on m1; every locally-checkable issue claim verified
  against the live DB, the fresh tags, and the cypher tfvars (findings.md).
- Two Plan-agent reviews. The second, arriving post-approval, found the
  sentinel bug fails toward **pass** (not merely toward stop) and that a
  `link_sha` parity key can never work — both folded into the baseline.
- Scope: Phases 1–2 of the issue plus the bucketing derivation. The wipe, the
  paid run and the provenance audit are a separate session.
- Created branch `246-preflight-gates-provenanced-rerun` off main.
- Next: Phase 1.

### Note on the branch point

`main` was **1 commit ahead of origin** when this branch was cut (`c9e2ddb`,
a CLAUDE.md version-header sync unrelated to #246), so this branch carries it
and the PR will include it. That unpushed commit is also a free real failing
case for the branch-pushed gate — test the failing answer before pushing.
