# Findings — DB hygiene: drop working schemas after persist; drop worker schemas after consolidation (#118)

## Surface area mapping (Plan-mode exploration, 2026-05-04)

### `R/lnk_pipeline_persist.R` — function shape

Signature: `lnk_pipeline_persist(conn, aoi, cfg, species, schema = paste0("working_", tolower(aoi)))`. Final operation = per-species INSERT loop, then `invisible(conn)`. The natural place to drop the working schema would be at the end of this function — but doing so breaks the compare script's rollup query (see below).

### `data-raw/compare_bcfishpass_wsg.R` — orchestrator flow

Sequence:
1. `lnk_pipeline_setup → load → prepare → break → classify → connect`
2. `lnk_persist_init` + `lnk_pipeline_persist` (writes persistent schema rows)
3. **Rollup query** — `SELECT … FROM <schema>.streams s JOIN <schema>.streams_habitat h …`
4. Return rollup tibble

The rollup query reads from the WORKING schema (`<schema>.streams_habitat` is long-format with a `species_code` column). The persistent schema is wide-per-species (`streams_habitat_<sp>` without `species_code`), so the rollup query can't trivially port to the persistent tables. Conclusion: drop the working schema AFTER the rollup query, not in `lnk_pipeline_persist`.

### `data-raw/consolidate_schema.R` — current state

Function signature: `consolidate_schema(schema, sources, backup, dest_conn, verbose)`. Per-source loop:
1. pg_dump on source via `via = "docker"` SSH-exec (or `via = "psql"`).
2. scp dump local.
3. pg_restore --data-only --no-owner onto destination.
4. Verification queries on destination tables.

No cleanup of source after restore today. Adding source-drop is straightforward — same `via = "docker"` SSH pattern used for pg_dump can run `DROP SCHEMA … CASCADE` on the source.

### `tests/testthat/test-lnk_pipeline_persist.R`

4 tests with `local_mocked_bindings` for `.lnk_db_execute`. None reference the working schema lifecycle — all focus on persist's DELETE+INSERT patterns. Phase 1's change is in `compare_bcfishpass_wsg.R`, not in `lnk_pipeline_persist`, so these tests stay unchanged.

## Approach choice — orchestrator level vs in-package

| Option | Cost | Trade-off |
|--------|------|-----------|
| Drop in `lnk_pipeline_persist` | Function gains a side-effect | Breaks compare's rollup; would force rollup into persist (large rewrite to wide-per-species query) |
| Drop in `compare_bcfishpass_wsg` after rollup | One param + one block | Keeps persist scoped; orchestrator owns lifecycle |

Issue body explicitly allows orchestrator path: "(or as the final step of `compare_bcfishpass_wsg`)". Going that way.

## Risks identified

- **Interactive debug** — default-on cleanup means a developer running `compare_bcfishpass_wsg("ADMS", config = …)` interactively loses the working schema after. Mitigation: `cleanup_working = FALSE` opt-out documented in roxygen.
- **Source-drop timing** — must guard on `pg_restore` rc == 0L, not just "ssh succeeded". Otherwise we lose the source schema for a partial restore.
- **SSH flake** — Phase 2 source-drop adds SSH calls per source. If SSH fails after a successful restore, the M4-side data is fine but source isn't cleaned. Net: partial cleanup is acceptable, partial restore would not be.

## Issue context

(full body of #118 reproduced here for archival)

`<see issue body in PR body / GitHub UI for the canonical text — same text as scaffolded in task_plan.md "Context" section above>`
