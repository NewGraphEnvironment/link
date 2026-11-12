# Progress — Export persisted barriers and input snapshots per group, so a one-group run reads downstream (#465)

## Session 2026-11-11

- Plan-mode exploration — phases approved by user, with four gate decisions (line rule; all four snapshots when unchanged; list, fetch, load barriers; summary prints commands)
- Created branch `465-export-persisted-barriers-and-input-snap` off origin/main (`3c0ab0bc`)
- Scaffolded PWF baseline from issue #465 with approved phases
- Next: start Phase 1
- Phase 1: line rule moved to `R/lnk_wsg_deps.R` (`.lnk_wsg_deps_line(conn, fwa)`); `recompute_deps.R` calls it; province output byte-identical (2,211 pairs, `data-raw/logs/downstream_export_465/line_rule_identity.md`); fixture tests (4 pass; red with the 999 filter removed); gate map row added, `test-pretest.R` passes. Ordering moved to R (radix): `ORDER BY 1 COLLATE "C"` is an integer literal to Postgres.
