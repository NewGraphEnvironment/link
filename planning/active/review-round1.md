# Code-check round 1: #401 branch (47bb3dfa...fe6060d2)

## Checklist read

- **code-check.md:** the prose of all 14 H3s under `## Mechanisms` (table rows skipped). Not read: 24 (Rules that stand alone 15, Security 6, Spreadsheets and PDFs 3; none names a tool or shape this diff uses).
- **code-check-r.md:** read in full: "`on.exit()` at a script's top level never fires"; "A `data-raw/` script must load the source tree, not the installed package"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "`$` on a list partial-matches, so a longer sibling key answers for a missing one"; "Tests that silently do not run". Not read: 108.
- **code-check-shell.md:** read in full: "A failed `cd` lets every later command run in the directory you were already in"; "`a && b || c` runs `c` when any step before the `||` fails"; "psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0". Not read: 67.
- **code-check-spatial.md:** read in full: "FWA `upstream_route_measure` misses the next segment's start". Not read: 92.

## What I checked (no finding)

- `lnk_pipeline_access()`: the distinct walk, the gate (`exists` over `<schema>.observations`), the empty-result paths (`obs_upstr[ids]` on an empty named list gives NULLs, replaced by `character(0)`), id matching as `as.character()` on both sides (both from RPostgres int4, so no `1e+05` mismatch), `observed & has_observation_key_upstr` under the gate. `has_observation_key_upstr` reaches the working `streams_access` but `lnk_pipeline_persist()` copies an explicit column list, so it is not persisted.
- The gate against bcfishpass's SQL at `620dbe4` (`ids` joins on `a.watershed_group_code = b.watershed_group_code`; `<schema>.observations` is the province table's own-group slice, which `build_obs.R` checked row for row). `distinct` mode in fresh v0.48.0: same `walk_from` as `ids`, `FILTER (WHERE id IS NOT NULL)`, upstream direction makes no temp table, so no temp object blocks the `on.exit()` drop.
- `lnk_pipeline_run()`: on.exit order (log-fail first, then the drop, both `add = TRUE`); `DROP TABLE IF EXISTS` after `DROP SCHEMA ... CASCADE` is a notice, and is inside `try()`. `observations_gate = if (...) {...}` yields NULL under `province`.
- Other callers of `lnk_pipeline_access()` (`lnk_access()`, recompute, variants) pass `observations = NULL`; no other reader of `<schema>.observations_province` outside prepare and access.
- Config: key validated at load and through `extends:`; `default_tuned` inherits `province`. Vocabulary: resolved in a worktree at HEAD: `default` and `default_tuned` give `acc-v3`, `bcfishpass` `acc-bcfp-3`; `default_extrabreaks` / `default_rearbreaks` still refuse on cut. Preflight's `min_version` is the DESCRIPTION floor (0.48.0), so a 0.47.0 worker fails pre-flight, not mid-run.
- fresh `1b2d4bc` vs `v0.48.0`: `R/` identical; link `ff6e7ea2` vs HEAD in `R/`, `inst/`, `DESCRIPTION`: the pin and one comment only. So the builds describe HEAD's code.
- Published numbers re-derived from `pre_post_diff.csv`, `parity_bcfp.csv`, `walk_*.csv`: 25.98 km, 114 pieces, 14 of 31 moved, LNTH BT 12.25 km / 3.6 %, UPCE at most 0.7 %, bcfishpass UPCE BT 0.05 km and −0.05 → 0.00, accessible diffs −0.10 / −1.30 / −0.36, LFRA 37–39 s, SETN 44–46 s, BULK 8 s: all match.
- Measurement scripts: `run.sh` guards its `cd`; `parity_pieces.sql` placeholder substitution order (`:schema`, `:wsg`, `:sp`) cannot collide with `::numeric`; `pre_post_diff.R`'s 1 cm piece floor absorbs the FWA `upstream_route_measure` miss.

## Findings

- **[severity: fragile]** `data-raw/pretest_inputs.csv` (unchanged by the branch; row `link,^R/lnk_pipeline_access\.R$,segments`) — after #401 the access step's observation walk joins the group's segments against every group's records upstream, so its cost is driven by records upstream of the group (LFRA's main stem: ~126,000), not only by the group's segment count. The pre-run gate (#372) maps `R/lnk_pipeline_access.R` to `segments` alone, so a later change touching only that file picks the largest-network group and never the group at the extreme of the input that now drives the walk. This branch's own gate is covered by coincidence: `R/lnk_pipeline_prepare.R` also changed and maps to `observations` (a group's own records), whose top group is LFRA (29,180), which is also the group with the most records upstream. Either map `lnk_pipeline_access.R` to `observations` as well, or add an input query for records upstream of a group.
  - **Rule:** code-check.md "A proxy is not the property"

## Notes (not findings)

- RUNBOOK §2c ("`lnk_pipeline_run()` drops `<schema>.observations_province` in an `on.exit()`, so no kept working schema holds it") and the `lnk_pipeline_run()` comment ("however it ends") overstate: `on.exit()` does not run when the R process is killed (the pre-run gate's wall-clock kill, an operator `kill`). Before #401 the table was dropped right after the lifts in prepare; now it lives through break, classify and connect, the long phases, so a killed run keeps one ~200 MB copy in that working schema until the group's next run replaces it. No data effect.
