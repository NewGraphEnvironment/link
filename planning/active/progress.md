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
