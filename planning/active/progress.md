# Progress — Provenance gaps before the 217-WSG run (#262)

## Session 2026-09-01

- Plan-mode exploration; verified all four gap counts against `fresh.log` rather than
  reading the schema
- Found three corrections to the issue body: `run_label` is plumbed and unfed;
  `.lnk_bcfp_log_current()` exists and its source is unreachable by design; the
  deterministic bcfp ref is the local ledger, not the tunnel
- Four design decisions approved by the user (own `log_recompute` table; keep untracked
  in the dirty predicate; ledger fallback at run open; `run_uid`)
- Created branch `262-provenance-gaps-before-217-wsg-run` off main
- Scaffolded PWF baseline with the approved phases
- Next: Phase 1 — `run_uid` + `run_label` end to end
