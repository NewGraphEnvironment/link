# Progress — lnk_scenario_export() (#308)

## Session 2026-10-14

- Plan-mode exploration; phases approved by the user (provenance gate: refuse unlogged groups, key NULL run_uid by run_id; discharge = what the run used; scope = functions + BUILD/PUBLISH script).
- Created branch `308-lnk-scenario-export-publish-habitat-per` off main
- Scaffolded PWF baseline from #308 with approved phases
- Next: Phase 1
- Phase 1: column contract YAML + `.lnk_export_rows()`; live smoke DUNC BT 63,067 rows in 0.3 s. Fixture tests 30 pass.
  - Finding: only DUNC's `config_hash` has logged thresholds in `fresh_default`; `fresh` has no `log_parameters_habitat_thresholds` table at all (built before #282). Ratios there are NA by design, not a fallback to today's bundle.
