# Progress — Export persisted barriers and input snapshots per group, so a one-group run reads downstream (#465)

## Session 2026-11-11

- Plan-mode exploration — phases approved by user, with four gate decisions (line rule; all four snapshots when unchanged; list, fetch, load barriers; summary prints commands)
- Created branch `465-export-persisted-barriers-and-input-snap` off origin/main (`3c0ab0bc`)
- Scaffolded PWF baseline from issue #465 with approved phases
- Next: start Phase 1
- Phase 1: line rule moved to `R/lnk_wsg_deps.R` (`.lnk_wsg_deps_line(conn, fwa)`); `recompute_deps.R` calls it; province output byte-identical (2,211 pairs, `data-raw/logs/downstream_export_465/line_rule_identity.md`); fixture tests (4 pass; red with the 999 filter removed); gate map row added, `test-pretest.R` passes. Ordering moved to R (radix): `ORDER BY 1 COLLATE "C"` is an integer literal to Postgres.
- Plan review folded in (`review-plan.md`); operator revised decision 2 (content md5 at load for CABD/PSCIS, province-wide content-keyed snapshots, observations/crossings cited by version id) and set decision 5 (round trip on m1, partial database a follow-up). Phase 4 moved last.
- Phase 1 extra: `all` identical before and after (`d4a9fdda…`).
- Phase 2: `R/lnk_export_groups.R` writes `barriers/` and `barrier_overrides/` parts per exported group (columns from `cols_*`; ltree and `text[]` as text, geometry as hex WKB), a manifest `group_parts` array and dataset specs, carry-forward with md5 check, regressions on dropped per-group parts, staged swap; PUBLISH puts them (skipping unchanged ETags), deletes stale keys under their prefixes and reads back. Tests: `test-lnk_export_groups.R` 40 pass; export 176, catalog 16, db_load 19 pass; mutations (no parts, no regression check, no carry-forward) each red. PUBLISH not run.
- Phase 3: the export writes `dependencies/rule=line.parquet` (province-wide line rule) as a manifest `dependencies` entry with the FWA table identity and the link that computed it, swapped in with the parts; PUBLISH puts it each time and reads its md5 back. Superset check on m1's `fresh_default`: 0 of 7,749,648 barrier rows and 0 of 44,069 override rows off their own group's lines (`data-raw/logs/downstream_export_465/superset_fresh_default.log`). Tests 52 pass; swap removed → 3 red.
