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

## Session 2026-10-11 (Phases 2–3)

- Script renamed `habitat_diff_segments.R`, `flag` arg (rearing | spawning).
- `data-raw/logs/rearing_diff_324/mechanism.R` attributes each disagreeing piece; `breaks.R`
  censuses segment breaks. PCEA's +22.12 km closes: rear-gradient split +21.72, connectivity
  +8.20, bcfp's order-1 width exception −9.59 (the whole connection-line gap), access +1.80.
- Controls FINA / PARS / LKEL run; same mechanism, different net sign (findings.md).
- Plan-review agent from the first session never returned (session ended); not re-run, since
  phases 1–3 are done and the branch gets `/code-check`.
- Decision under the approved plan: the segmentation is #223's deliberate design and changing it
  re-segments every WSG, so it is a larger change: annotate here, draft an issue for review.
