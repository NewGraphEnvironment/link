# Progress — Variants harness: run a variant's groups in parallel (#406)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user
- Created branch `406-variants-harness-run-a-variant-s-groups` off main
- Scaffolded PWF baseline from issue #406 with approved phases
- Next: start Phase 1
- Phase 1 done: `--jobs` in `habitat_variants_build.R` (PSOCK workers, master-only writes,
  `pass_wall` and `jobs` in `variant_timing.csv`). Smoke at `--jobs=2` and a corrupted-digest
  mutation at both widths passed (findings.md). Plan review folded in.
