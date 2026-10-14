# Progress — lnk_scenario_export() (#308)

## Session 2026-10-14

- Plan-mode exploration; phases approved by the user (provenance gate: refuse unlogged groups, key NULL run_uid by run_id; discharge = what the run used; scope = functions + BUILD/PUBLISH script).
- Created branch `308-lnk-scenario-export-publish-habitat-per` off main
- Scaffolded PWF baseline from #308 with approved phases
- Next: Phase 1
- Phase 1: column contract YAML + `.lnk_export_rows()`; live smoke DUNC BT 63,067 rows in 0.3 s. Fixture tests 30 pass.
  - Finding: only DUNC's `config_hash` has logged thresholds in `fresh_default`; `fresh` has no `log_parameters_habitat_thresholds` table at all (built before #282). Ratios there are NA by design, not a fallback to today's bundle.
- Phase 2: `lnk_scenario_export()` + manifest + provenance tree + bundle publish. `.lnk_config_hash()` split into `.lnk_config_files()` (hashes of default/bcfishpass/default_tuned unchanged; log/config/stamp tests 520 pass). Smoke: DUNC+KOTL BT/RB → part-300; DUNC's bundle published (hash matches today's `default`), KOTL's recorded as changed. Export tests 93 pass.
  - Deviations from the plan, both small: provenance also carries `log_parameters_fresh.parquet` (the source of `access_gradient_max` for `accessible_ratio_gradient`); bundle prefix is `config/sha256-<hex>/` (no colon in keys); a latest build that did not finish (`date_end` NULL) is refused like an unlogged one.
- Plan review (Plan agent, 2026-10-14) filed as `planning/active/review-plan.md` with a disposition per finding. Folded in:
  - B2: export carries forward configs it does not re-export.
  - G1: `has_barriers_dnstr` from `streams_access` beside `accessible`, plus recompute provenance. This is a column-contract decision to confirm in the PR.
  - G2: rows only for the species each group's build modelled; a logged species with no rows is refused.
  - G3: per-run `model`.
  - G4: refuse a build logged for another `schema_persist`.
  - G8: `source_artifact` scoped as this database's record.
  - Export tests 109 pass.
- Phase 3: `lnk_catalog()` (local, https, s3:// through the `aws` CLI with the caller's credentials) and `lnk_db_load()` (one transaction, md5-checked parts, config-wide replace, PK `(config, species, blue_line_key, downstream_route_measure)`, `table =` for tests). Catalog 15, loader 19 tests pass, including mid-load rollback and cache reuse.
- Full suite at `07fb08d0`: 2,860 pass, 2 fail + 2 error. All four reproduce identically on `origin/main` in a worktree (`test-lnk_pipeline_prepare.R` dams golden 2 fail; `test-lnk_wsg_resolve.R` closure 2 error), plus `test-lnk_db_conn.R` reaching a refused tunnel port. Environmental and pre-existing, none in files this branch touches.
- `/code-check branch`: five rounds. Ended by enumeration, not by a quiet round: round 5 enumerated the mechanism's 24 places, and the one finding left (3 places) is fixed, tested and mutation-proven.

  | Round | Findings | Fixed | Accepted | Inside previous fix? |
  |---|---|---|---|---|
  | 1 | 7 | 7 | 0 | — |
  | 2 | 5 | 5 | 0 | y (2) |
  | 3 | 3 | 3 | 0 | y (3) |
  | 4 | 4 | 4 | 0 | y (2) |
  | 5 | 1 (3 places) | 1 | 0 | y |

  - The mechanism, named in round 3: what one call or one root can see (the schemas and groups passed, the local manifest, the exporting clock) was stored or compared as if it were a property of the build or the published config.
  - The terminal fix: one judgement, `.lnk_manifest_regressions()`, shared by the export and PUBLISH. It flags a lost config, a lost group:species pair, an older build, a missed recompute, and an older export whose parts differ.
  - Mutation table (findings.md) plus 6 more mutations on rounds 4–5's clauses: every guard goes red when restored.
- Pilot rebuild at `b59f61a5`: 22 parts byte-identical to the first build; 156 provenance/bundle files.
