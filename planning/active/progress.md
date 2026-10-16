# Progress — Provenanced province-wide `default` run (#246)

## Session 2026-10-16

- Plan-mode exploration; phases approved by user (scope 241 under `default`, colima to 600 GiB)
- Created branch `246-provenanced-province-wide-default-run` off main
- Scaffolded PWF baseline from issue #246 with approved phases
- Next: Phase 1
- Phase 1: #246 and #346 bodies corrected to 241 (the 24 `default`-only groups named). Colima resize handed to the
  operator (still 300 GiB at last check)
- Phase 2: 241-group split generated (`bfe13ee7`). Plan review 1 returned three blockers, all confirmed by probe and
  fixed before any spend (B1 bucket config, B2 label charset, B3 tunnel-free parity). Host speeds measured from
  `fresh.log` (`20260901_234743`): m1 0.219, job1 0.113, job2 0.220 min per 1k source segments, so re-packed at equal
  speeds: 76 / 50 / 55 / 60 groups, about 1.21 M source segments per host
