# Progress — Build DUNC into fresh_default (config default) for the floodplains Columbia region (#328)

## Session 2026-10-12

- Plan-mode exploration; operator chose "DUNC alone at HEAD" over matching the Aug vintage or rebuilding all four
- Created branch `328-build-dunc-into-fresh-default` off main
- Scaffolded PWF baseline from issue #328 with approved phases
- Next: Phase 1
- Plan review (Plan agent) folded in: `review-plan.md`. No blockers, no LNK_SCHEMA leakage, no recompute needed.
- Phase 1: pre-flight clean; ran DUNC 15:31:35–15:33:45 UTC (2.2 min), exit 0
- Phase 2: `verify.R` 19/19 pass, after `ANALYZE` on the six touched tables (the first full-PK join stalled on stale statistics). FWA fingerprints identical to KOTL's; `fwapg_sha` differs only because the fwapg checkout moved.
- Phase 3: #328 body edited (outcome, vintage, FWA fingerprint, Also-observed answer); CLAUDE.md status entry with the measured segments-per-FWA-line split (49 of 56 under 1.5, CHWK 1.54, six dense at 2.6+)
- code-check round 1: 3 doc findings fixed (CHWK missing from the CLAUDE.md density split; Phase 2 box overstated link_sha/run_uid; LARL's build commit). My own first fix misquoted the dense floor (2.9; PARS is 2.62), corrected before commit.
- code-check round 2: 4 doc findings fixed (README/task_plan/issue cited #282/#307 as moving DUNC's flags: enumerated, they changed only MAD columns, inert under cw, and the compiled BT/WCT/RB rules differ only by #310/#311; issue body still had LARL on 322389a; progress.md density count; README 'data is the same' limited to the six logged FWA tables). Two were round-1 defects one file over.
