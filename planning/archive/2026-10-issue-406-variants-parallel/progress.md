# Progress — Variants harness: run a variant's groups in parallel (#406)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user
- Created branch `406-variants-harness-run-a-variant-s-groups` off main
- Scaffolded PWF baseline from issue #406 with approved phases
- Next: start Phase 1
- Phase 1 done: `--jobs` in `habitat_variants_build.R` (PSOCK workers, master-only writes,
  `pass_wall` and `jobs` in `variant_timing.csv`). Smoke at `--jobs=2` and a corrupted-digest
  mutation at both widths passed (findings.md). Plan review folded in.
- Code-check rounds 1 to 4 (four reviewers): two fragile spots, two more (one inside round 1's
  fix), a remedy gap, and one bug (an empty variant at `--jobs` above 1). All were fixed.
  Round 3 enumerated the mechanism (resources a pass holds, sentinels it decides on, 21 rows),
  and round 4 walked every row; that enumeration ended the loop.
- Phase 2 done: widths 1, 2, 4 and 8 on #331's nine groups (21:57 to 22:29 UTC), 45 of 45
  digests identical. Four jobs: variant 6.23 to 2.10 min, `default` 8.06 to 3.02. Eight
  jobs add 10 to 13 %. The final code was smoke-tested after the run, with the pid log line,
  the empty variant, and persisted digests unchanged.
- Tests: `devtools::test()` 4518 pass, 0 fail, 0 warn, 0 skip (22:34 UTC, after the run).
- Phase 3: README measurement, CLAUDE.md status, NEWS, 0.69.4. The #377 line is filled once
  the PR exists.
- #377's #406 line filled with the measurement (box left for the merge). #406's body still
  reads correctly against the measurement, so it was not edited. Archived.
