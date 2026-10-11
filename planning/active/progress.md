# Progress — PCEA BT rearing segment diff (#324)

## Session 2026-10-09

- Plan-mode exploration — phases approved by user ("Go all phases to PR")
- Created branch `324-pcea-link-bcfishpass-config-flags-differ` off main
- Scaffolded PWF baseline from issue #324 with approved phases
- Next: start Phase 1

## Session 2026-10-09 / 2026-10-11 (Phase 1)

- `data-raw/rearing_diff_segments.R`: interval-overlap pieces per blue_line_key; asserts coverage
  (PCEA gap 14.8 m against 106 m tolerance) and that link-only − bcfp-only equals the flag-total
  difference (gap 0.0 m). PCEA BT: link-only 54.18 km, bcfp-only 32.06 km, both 1,969.31 km.
- Outputs in `data-raw/logs/rearing_diff_324/` (`pcea_bt_{summary,pieces,stamp}`).
- Previous session ended mid-query (a NOT EXISTS boundary match over 106k rows); no backend left running.
