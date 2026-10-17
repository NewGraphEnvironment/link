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
- Pilot `20261016_215933-663675b0` (m1 KAKC closure LSTR,STIR,MSTR,KAKC + job1 TSEA closure LPET,TSEA, into
  `fresh_pilot246`, `--refresh-primitives`): 21:59 → 22:27 UTC, exit 0, 6/6 modelled, recomputed, consolidated.
  `study_area_verify.sql` and `verify_extra.sql` both PASS (`data-raw/logs/provincial_246/pilot_verify*.log`).
  bcfp view after refresh 4,272,394 rows / 188 groups (was 4,272,365). Compare errors for KAKC, LPET, TSEA are the
  expected RB/GR-only groups (no bcfp reference)
- **Decision set for the main run** (stated before launch, from the approved plan): config `default`; schema
  `fresh_default`; 241 groups as four `--focal=` strings from `research/study_areas.md` (79 / 51 / 55 / 61 focal,
  closing to 76 / 50 / 55 / 60, the species-less HAYR KCHL SHEK SAHT CHUK dropped); species from `default` ×
  presence per group; `--refresh-primitives`; `--recompute-jobs` left at 4; `dams` and mapping code as the driver
  runs them; label `provincial-241-default-246`

## Session 2026-10-17

- Colima at 600 GiB (operator), `fresh-db` healthy, 307 G free
- Main run `20261017_004619-3f4c713b` launched 00:46 UTC; modelling 01:05–05:42; the driver counted 18 finished
  groups as missing and two failed (KITR, UPET). Driver paused by the operator before its burn; the 18 consolidated
  by hand; KITR and UPET fixed (`a17e9177`) and re-run on m1 under the same run_uid; driver resumed; recompute
  241/241; exit 09:34 UTC. Both verifiers PASS. Filed #347 (completeness from log text) and #348 (one failure skips
  the recompute)
- Parity `20261017_093603-31ab6242` (17-group closure, `fresh_parity246`): cross-section PASS 48/50; 5 UNEXPLAINED
  at the taxonomy's 2 %
- Logs committed `d08f3320`, with host addresses redacted from `pilot.log`, which the EXIT redaction misses
- Next: Phase 5 (research write-up, CLAUDE.md status, #346 note), `/code-check branch`, archive, PR
