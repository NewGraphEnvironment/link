# Progress — Break streams only where a present species' access changes (both configs); bcfishpass config takes the order-1 exception (#326)

## Session 2026-10-26

- Plan-mode exploration — phases approved by user, **parked** (baseline only)
- Created branch `326-break-streams-only-where-a-present-speci` off main (v0.68.6, `a34d5357`)
- Scaffolded PWF baseline from issue #326 with approved phases; gate decisions recorded in `task_plan.md`
- Plan-agent review folded in before the baseline commit (`review-plan.md`)
- Next: parked 2026-10-26; resume with the command below, then "start Phase 0"

### Resume

```bash
cd /Users/airvine/Projects/repo/link && git fetch -q origin && git checkout 326-break-streams-only-where-a-present-speci && git pull --ff-only && git merge origin/main
```

Approval on 2026-10-26 covered the baseline only. The run-to-PR mandate starts when the operator says to resume. Phase 0 is in the sibling repo `fresh` (pull first — the local checkout was 142 commits behind on 2026-10-26), and Phase 4 needs `data-raw/snapshot_bcfp.sh` run on this machine before any group is re-modelled.

## Session 2026-10-26 (resumed, evening PDT)

- fresh pulled to v0.42.0; branch `order-child-width-gradient` (no issue number yet: the fresh issue body waits on review). `frs_order_child(channel_width_lt, gradient_max)` + validator key `width_known_below_min`, with the names the plan proposed; commit `25dca92` in fresh. Live test on five synthetic order-1 lines; removing either clause turns it red.
- fresh `/code-check` round 1 (`review-fresh-round1.md`): roxygen overclaimed "in full": bcfishpass's exception sits only in its `cw` branch and only on rows passing its spawning/connectivity test. Fix pending (the fresh sweep was reading the tree).
- link Phase 1 (prepare tests) and Phase 2 (post-lift per-species reduction) written; 8 new tests red on the old body, green on the new; planted lowercase literal and no-presence-filter mutants each go red. Classify / rules-build tests moved to Phase 3 with their code.
- RUNBOOK §1 diagram corrected (unify runs after persist_init, not before break), §2b `barriers_<sp>_min` row rewritten.
- FINA pre-flight (`54c350ac`): 28,650 segments = bcfishpass, 20,394 / 20,394 breaks both ways, 0 link-only; #223 frontier holds; BT accessible −0.02 %.
- Phase 3 committed (`1b69ad7c`); fresh branch `25dca92` installed from a git archive (reports 0.42.0, no RemoteSha). PARS pre-flight launched from the worktree at `1b69ad7c`.
- link `/code-check` round 1 (`review-link-round1.md`): (1) bcfishpass `config.yaml` provenance checksums stale → regenerated (default's date-only churn reverted); (2) `breaks_diff.R` could read the other config's `working_<wsg>` → fingerprint guard, negative-checked on `fresh_default`; (3) reduction lifted by the group's overrides only while the view lifts by every group's → also anti-joins `<persist>.barrier_overrides` when it exists (mutant goes red); (4) classify gate's AOI scope → named residual, a Phase 4 count. The PARS pre-flight at `1b69ad7c` predates (1) and (3), so its log row reads `config_drift`.
- link `/code-check` round 2 (`review-link-round2.md`): defect inside round 1's fix. Lifting by the persisted overrides also lifted by the group's own stale rows (a lift removes a position, so it can remove a real minimal break), and made segmentation depend on host / run order (breaks the byte-identical bar). Reverted to the plan's design (own overrides only); round 1's cross-group case is a named residual counted in Phase 4. Test pins "no persisted table read"; round 1's body fails it.
- fresh `/code-check` round 2 (`review-fresh-round2.md`): docs still incomplete (CH/CO/ST/WCT edge/waterbody filter; the old "reproduce bcfishpass exactly" example). Fixed in fresh `0810289`; the edge/waterbody gap is a real link parity divergence too, logged as an open decision in Phase 3.
- fresh `/code-check` round 3 (`review-fresh-round3.md`): enumerated all 15 bcfishpass blocks carrying the exception; one false statement (the waterbody bullet generalised CH's form) fixed from the verified SQL in fresh `b81dc21`. Fresh review ends by enumeration. The plan's open decision restated with the three forms.
- link `/code-check` round 3 (`review-link-round3.md`, the enumeration): mechanism "one barrier set built at three scopes (break-time / classify / access view), with no check that the break set covers every effective view frontier". Every barrier kind × lift kind placed: equal, harmless (adds breaks), or the two named residuals. End-to-end on FINA: 3,879 effective BT frontiers, 0 more than 2 m from a break (1 within 1 m left unbroken by `frs_break_apply`'s 1 m skip, pre-#326). One new latent defect: unify maps classes from `.lnk_classes_bcfp` alone, so a bundle access-level class outside it would prune view frontiers → prepare refuses it (all five shipped bundles pass; mutant red), config comments corrected. Link review ends by enumeration. Note for Phase 4: the cross-group-lift count reads 0 by construction on m4 (local `fresh.barrier_overrides` holds FINA + PARS only).
