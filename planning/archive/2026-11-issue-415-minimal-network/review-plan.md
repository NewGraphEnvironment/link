# Plan review — #415 baseline (Plan agent, 2026-11-02, synchronous, before the baseline commit)

Reviewer read: the task plan, the issue, the config merge and resolver, every bundle-enumerating
test, `audit_configs.R`, `pretest_inputs.csv`, the 396 proof scripts, `wsg_run_one.R`, the
downstream guard, and knowledge's placement and archive code. Each claim below was re-checked
against the file before it was folded in (the `obs_tbl` read, the sliver flag, the guard
default, 396's `run.sh` and README, the issue's subsurface clause).

## Blocker
- None for Phases 1 and 2.

## Gap (all folded into task_plan.md)
- `pre_post_diff.R`'s `tops` CTE reads `zz396_cuts.obs_<wsg>`, built by 396's `build_obs.R`; an
  adapted copy errors on any new group. Folded: `proof.R` drops the `at_top` measures.
- "Species 0/1 access identical on every piece" fails by construction on sub-metre pieces where
  the full build skipped a minimal cut under the 1 m rule; 396 counts them as violations.
  Folded: the assertion excludes slivers (`len < 1.01`).
- The smoke run needs `LNK_GUARD_DOWNSTREAM=warn` (`wsg_run_one.R` defaults to `error`) and the
  recompute's pass rule written first ("failed only on the downstream-dam post-condition").
  Folded.
- Phase 3 depends on Phase 2: a config with no live token is refused before any write. Folded
  into Phase 3's heading.

## Ordering
- The token's `introduced` and the DESCRIPTION bump must agree and no test checks it. Folded:
  both name `0.76.0`; Validation adds the one-line check.

## Assumption (verified by the reviewer)
- The thin bundle loads and verifies clean with no own `provenance:` (`test-lnk_config.R`'s
  depth-3 leaf proves it); every enumerating test resolves files through `lnk_config()`, so
  inherited entries satisfy them; no test requires a README; `audit_configs.R` §1 is fixed to
  two bundles and §2/§3c go through `lnk_config()`.
- The predicted cut spec matches `.lnk_vocabulary_spec_cut()`; `acc-v4` holds because
  `cfg$species` comes from the inherited `rules.yaml`; append-only and live-uniqueness rules are
  unaffected.
- The three source tables are always built whatever `break_order` says (harmless cost;
  contradicts the "zero-cost opt-out" comment at `lnk_pipeline_break.R:111`).
- knowledge archives by all four tokens from link's `log_recompute`, so it cannot mint a `grad`
  token itself; its grade record already carries `curve_grad`. Folded as a note.
- Not probed by the reviewer: "nothing in prepare/access/classify/persist reads the three break
  tables" (the exploration agent grepped `R/` for it).

## Scope
- Dropped silently, now stated: the issue's optional `subsurfaceflow` (stays off, inherited from
  `default`); "crossing-based fields absent or flagged rather than wrong" (the proof states what
  each field means; flag or drop is the follow-up's question); checkbox 3 "access on the minimal
  network" (the proof reports `access_<sp>` km by code per species).
- Added beyond the issue, kept: the placement census, the `grad` token design, the RUNBOOK keying
  pattern, the issue-body edit, the research table row.

## Acceptance
- The smoke run's pass line is now zero violations outside slivers and every minimal cut matched
  within 1 m, not "runs end to end".
