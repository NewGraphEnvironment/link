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
