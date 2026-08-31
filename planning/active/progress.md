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

### code-check — 5 rounds, converged

Rounds 1-4 each found a blocker inside the previous round's fix; round 5 was
clean, verified by restore-the-bug on each round-4 change. 14 real issues
total, all fixed. Full table and the mechanism analysis in findings.md.

The recurring cause was fixing one instance of a class without sweeping the
diff for the rest — `grep` exiting 1 under `set -euo pipefail` aborted three
different code paths across three rounds. Ended by replacing the remembered
form with `csv_lines()` / `csv_count()`, which cannot be got wrong.

## Session 2026-08-31 — Phases 1-2 shipped and validated on real hardware

Merged: #251 (prep readiness guard), #252 (two gate fixes, v0.47.1), #253
(finish-time packing), #235 (internal dirs out of build), #254 (v0.47.2 +
run record), #255 (doc corrections). Upstream NewGraphEnvironment/rtj#250
(`cloud-init status` readiness) merged, rtj#248 closed.

**Four cypher pilots, ~$1.00, four defects** — two of them in the new gates
themselves. Pilot 4 clean end-to-end in 7.0 min with full provenance on the
cypher row, which is #246 Phase 5's acceptance criterion.
Record: `research/run_record_2026_08_31_cypher_pilots.md`.

Measured: dispatcher 0.0391 vs cypher 0.0872 min/1k persisted segments
(**2.23x**), recompute 0.0112, persisted/source ~3.5.

**Three beliefs corrected** (now in CLAUDE.md, #246 body, memory, generated
`research/study_areas.md`): the Phase 3 wipe is **not required** (93 ⊂ 119 and
persist replaces per-WSG); only Peace is FWCP, Fraser+Skeena are HCTF; field
scope != model scope.

Primitives refreshed on m1 2026-08-31 21:45 — the one real prerequisite, now
done. Vintage gate passes at its 7-day default.

**Open decision, not a task:** run the 119 (closure of current focal areas,
~4.3h) or all 217 modelable BC WSGs (1.76x the work). "Look anywhere" means 217.

Filed: #247, #250, soul#129. PWF is complete apart from archiving.
