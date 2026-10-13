## Clean

Reviewed commit dba635e6 (move `fresh.log_source_artifact` -> `provenance.source_artifact`), grepping the whole repo (archive excluded except its README) rather than the diff.

What was checked, and holds:

- **No remaining old-name references outside `planning/archive/`** (except the archive README's deliberate history line). `grep -rn "log_source_artifact"` over R/, data-raw/, tests/, inst/, man/, RUNBOOK.md, CLAUDE.md, research/ returns nothing.
- **Every R and data-raw consumer goes through the helpers**: `R/lnk_log.R:718-730` (`.lnk_log_inputs()`), `R/lnk_preflight_vintage.R:250,276,289` (`.lnk_vintage_stamp()` and its message), `R/lnk_artifact.R` (create / record / read), `data-raw/artifact_record.R:74,78,120` (`--clear` and the read-back). `snapshot_bcfp.sh` names the table only in a comment.
- **Existence probes:** both `information_schema.tables` probes (`R/lnk_log.R:719-723`, `R/lnk_preflight_vintage.R:276-281`) compare `table_schema` / `table_name` to `loc$schema` / `loc$table`, both lower-case unquoted identifiers, so they match. `lnk_artifact_read()` uses `to_regclass(.lnk_artifact_table())`, which also resolves.
- **Creation:** `.lnk_artifact_create()` runs `CREATE SCHEMA IF NOT EXISTS provenance` before the table, and `.lnk_log_align_columns()` takes schema and table separately, so it targets the new location.
- **Nothing drops `provenance`:** `state_clean.sh`'s heuristic drop is `working%` / `fresh_%` / `= 'fresh'` (`provenance` does not match `fresh_%`), and scoped mode drops only the named schemas. No `DROP SCHEMA` in cypher_prep.sh, schema_consolidate.R, recompute_parity.sh (its own `$BAK`), study_area_verify_negative.sh (its own scratch) or `lnk_pipeline_setup()` (the working schema) can reach it. schema_consolidate.R copies only tables with `watershed_group_code` in the persist schema and never enumerated this table.
- **Surviving `fresh` drops is safe for the gate:** `fresh.modelled_stream_crossings`'s loader row now outlives a `state_clean.sh` drop of `fresh`, but `lnk_preflight_vintage()` reports a missing table as `absent` (fail) before it looks at stamps, and only `snapshot_bcfp.sh` recreates that table, `--clear`ing first. So a stale stamp cannot pass a dropped table.
- **Live DB:** on local docker fwapg (:5432), `provenance.source_artifact` exists with `m1` rows (4 loader, 253 probe) and `fresh.log_source_artifact` no longer exists. The rows were migrated, so the archive README's Evidence line (`provenance.source_artifact WHERE host = 'm1'`) is true.
- **Tests:** the SQL-capture assertions and DB-test cleanups name the new table. The "no artifact table" test's `expect_no_match` still checks the right string.

Two notes, neither a defect:
- The tests name `provenance.source_artifact` as a literal (DDL / INSERT greps, and the `withr::defer` DELETEs at `tests/testthat/test-lnk_artifact.R:156,325` and `tests/testthat/test-lnk_preflight_vintage.R:236`), not through `.lnk_artifact_table()`. Another move would break them, but loudly.
- The "What it preserves" header list in `data-raw/state_clean.sh:14-18` does not name `provenance`. The behaviour is right.
