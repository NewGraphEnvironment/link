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
- Preflight-only (`--cy-workspaces=job1,job2,job3 --config=default --schema=fresh_default`) at `0ae73a79`: every
  local gate green, cloud-host gates NOT CHECKED (no hosts). bcfp pin `v0.7.15-50-g620dbe4`, fwapg `f9718cb`,
  bcfishobs `08630cf`, fresh `e247ca1`. Log: `data-raw/logs/provincial_246/preflight_1.log`
- `/code-check branch` round 1 spawned 21:29 UTC
- `/code-check branch`: 4 rounds (1 clean + 2 hardening; 2: 2 findings; 3: 2 real defects; 4: clean, by enumeration
  of every skip / aggregate in the changed files). No round found a defect inside a previous fix. Fixes in the three
  "Code-check round N fixes" commits; mutation tests proved the parity presence guard and the all-NULL host checks fire
