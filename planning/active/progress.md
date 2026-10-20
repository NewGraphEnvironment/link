# Progress — Re-score bcfishpass parity at v0.66.6 (#362)

## Session 2026-10-20

- Plan-mode exploration — phases approved by user ("go all phases to pr")
- Created branch `362-re-score-bcfishpass-parity-at-v0-66-6-an` off main
- Scaffolded PWF baseline from issue #362 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) returned no blockers; findings and dispositions in `review-plan.md`
- Phase 1: preflight clean (needs Homebrew bash); run `20261020_171738-477072be` launched 17:17 UTC,
  closure identical to 2026-10-17 (same 17 groups, same order), exit 0 at 18:15 UTC; verify PASS at
  `expected_n=17`. Stamp in `data-raw/logs/parity_0.66.6/README.md`.
- Phase 2: scored 48/50 PASS; every move explained (gate settle, or #277 for ADMS CH); #277's
  body gained the measurement. Logs and `moves.R` in `data-raw/logs/parity_0.66.6/`.
- Phase 3: TURN BT not scorable (bcfishpass has no TURN / UKEC streams); evidence in `turn_bt.txt`.
- Phase 4: `research/bcfishpass_parity.md` created; README, access_columns, study_area_run and CLAUDE.md point at it.
