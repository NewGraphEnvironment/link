# Progress — Code-identity gaps in fresh.log (#264)

## Session 2026-09-01

- Plan-mode exploration; four design decisions put to the user and approved:
  bcfishobs gate-not-column, `fresh_sha` as a parity key, one unified
  `.lnk_pkg_git_state()` resolver, plus `fresh_sha_source` and the `-1`
  sentinel fix as extras
- Re-measured the issue's premise on m1 rather than taking it from the body —
  `fresh` has `RemoteSha 7f12d99…`, `link` has none; both known answers for the
  new tier are available as real installs
- Created branch `264-code-identity-gaps-in-fresh-log-fresh-sh` off main
- Scaffolded PWF baseline with the approved phases
- Next: Phase 1 — tests first, then `.lnk_pkg_git_state()`
