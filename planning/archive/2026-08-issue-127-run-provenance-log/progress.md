# Progress — Run provenance log on persist schema (#127)

## Session 2026-08-06

- Rewrote #127 from the original `persist_log` sketch into a four-table design
  (`log` / `log_parameters_fresh` / `log_dimensions` / `log_input`) after inventorying
  everything that can change between two runs.
- Plan-mode exploration (2 Explore agents + 1 Plan agent). Plan agent found three
  blockers in the naive design: `run_id bigserial` breaks multi-host consolidation;
  `CREATE TABLE IF NOT EXISTS` cannot ship a new config column; `config_hash` must hash
  the resolved file set because `config.yaml` is absent from the `provenance:` block.
- Investigated input provenance against live fwapg — established that `bcdata.log`
  covers only `bc2pg` downloads and **not FWA**, and that the stream network's only
  real provenance is the fwapg repo SHA.
- Created branch `127-run-provenance-log-on-persist-schema` off main.
- Pull at branch time brought in #233 / v0.44.3 (config dictionaries renamed + new
  `dictionary_parameters_fresh.csv`) — folded into Phase 2 as dictionary-driven column
  lists.
- Scaffolded PWF baseline with approved phases.
- Next: Phase 1.
