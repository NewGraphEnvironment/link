# Progress — Backlog move 4: default's presence table as bcfishpass's copy plus an overlay (#472)

## Session 2026-11-18

- Plan-mode exploration — phases approved by user
- Created branch `472-backlog-move-4-default-s-presence-table` off origin/main
- Claimed move #472 (in-flight label)
- Scaffolded PWF baseline from issue #472 with approved phases
- Next: start Phase 1
- Phase 1 (#292): `presence_groups.csv` in `default` and `bcfishpass`, `.lnk_presence_groups()`, every `lnk_presence()` caller passes it; all five live bundles still resolve to their tokens (acc-v6, acc-bcfp-5); tests in test-lnk_presence.R and test-dictionaries.R; the caller guard fails when one call drops `groups =` (mutation checked)
