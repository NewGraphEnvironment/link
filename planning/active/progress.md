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

### Phase 1 — 52a3723

`fresh` Suggests → Imports (the root cause: pak's `dependencies = NA` never
resolved the existing `Remotes` pin), new `lnk_preflight_fresh()` asserting
symbols with a namespace-walking drift guard, `cypher_prep.sh` rewrite
(pinned install, assertion, `~/.Renviron` provenance, `CYPHER_PREP_STAGE`),
and the prep sentinel fixed at both call sites. Drift guard verified by
restoring the bug with proof the patch took.

### Phase 2 — fb8e642

Pre-flight split into `preflight_local()` (pre-spend) and
`preflight_hosts()` (post-prep, pre-write), plus `lnk_preflight_vintage()`,
`lnk_preflight_stamp()`, `lnk_preflight_parity()` and two driver scripts.
Two post-conditions and three new flags. Every gate exercised in both
directions on m1 with no spend.

### Phase 3 — b7cb155

`data-raw/study_area_buckets.R` derives the host buckets by union-find over
drainage closures and regenerates `research/study_areas.md`. Reproduces the
issue's 22 components / 119 modelable / 39-on-dispatcher from first
principles; two `--write` runs are byte-identical.

### Phase 4 — in progress

RUNBOOK §8d, NEWS 0.47.0, version bump. Issue #246 body corrected in three
places and marked Phases 1-2 done. Follow-up #247 filed
(`fresh.snapshot_stamp`).

**Not done, deliberately:** `/code-check` was run once over the whole branch
diff rather than per commit — recorded here rather than ticking a per-commit
box that did not happen.
