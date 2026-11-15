# Plan review — #469 (Plan agent, 2026-11-10, at 3c0ab0bc, fresh 0.52.0 / 245c8d8d)

Verified by hand before folding in: B1 (working `streams.gradient` is `GENERATED ALWAYS` in every
`working_*` schema on m4; `fresh_default.streams.gradient` is a plain column) and G8
(`test-lnk_vocabulary.R:119-133` asserts every shipped bundle resolves `grad-seg`).

## Blocker
- **B1.** Working `streams.gradient` is `GENERATED ALWAYS ... STORED` (`lnk_pipeline_prepare.R:875`
  → fresh `frs_col_generate.R:88-93`), so an UPDATE fails. Fix: `ALTER TABLE … ALTER COLUMN gradient
  DROP EXPRESSION` after break, then update; nothing after break splits geometry. Test on a
  generated column, not a plain one.

## Gaps
- **G1.** A persist schema equal to `schema_full`/`schema_minimal` (e.g. `LNK_SCHEMA=fresh_default`)
  is not refused; refuse in `lnk_pipeline_run()`, and `schema_full == schema_minimal`.
- **G2.** Build-time judgement skips the DB half of the pair guard (`data-raw/streams_parent.R:61-117`:
  both closed, dirty flags FALSE, fresh_sha equal, same species, minimal `token_cut` = parent_cut,
  rows' `schema_minimal` = config's). Move it to R/; the git half stays the builder's job (RUNBOOK).
- **G3.** `--verify` is in `streams_parent_build.R` (`verify_groups()`, :189), not `streams_parent.R`.
  Put the per-group SQL in R/ taking a schema and groups; both callers use it; update its test.
- **G4.** Mapping must be a bijection within the group: each working segment matches exactly one
  full segment on `downstream_route_measure` and `upstream_route_measure` within 1 mm, each full
  segment matched once, equal counts. (0 duplicate starts province-wide today.)
- **G5.** Log which parent rows the build read (`log_input` row for `<schema_full>.streams_parent`,
  or `log.notes`).
- **G6.** Resolver: require `minimal_config`'s acc/flow = this config's; refuse a `minimal_config`
  whose own source is `parent`; refuse unknown sub-keys; derive `schema_minimal` from
  `minimal_config` or refuse a mismatch.
- **G7.** The swap runs whatever the active species (paused-only groups too).
- **G8.** `test-lnk_vocabulary.R:117-133` turns red; rewrite (only `default_parent` resolves
  `grad-parent`; it differs from `default` only in grad). Roxygen of `lnk_vocabulary_resolve` and
  `lnk_pipeline_run`'s phase list.
- **G9.** Docs: `research/output_vocabulary.md:60-65` config→tokens table; RUNBOOK :886, :1000-1003;
  a `default_parent` build runs only where `schema_full` and `streams_parent` exist (the dispatcher).

## Ordering
- **O1.** Judge right after `lnk_vocabulary_resolve()` (`lnk_pipeline_run.R:170`), before the log
  opens; only the mapping waits for break.
- **O2.** Bump DESCRIPTION to 0.80.0 before the proof; build from a committed clean tree.
- **O3.** Merge `origin/main` (PR #482 still open) before touching `pretest_inputs.csv`, NEWS, CLAUDE.md.

## Assumptions
- **A1.** Reproduction likely: since 4dfbfa49 only `R/lnk_streams_parent.R` and DESCRIPTION changed
  on the path; fresh unchanged. MORK, SETN built on m1; BULK, COTR on cypher job1. Compare each
  group's `log_input` artifact ids with m4's `provenance.source_artifact` before building; if a group
  refuses on mapping, report it as the refusal working and substitute another group.
- **A2.** Persisting the parent's gradient is right: `lnk_habitat_validate` (:879) and the export's
  `*_ratio_gradient` (`lnk_scenario_export.R:183-212`) read persisted `gradient`; nothing in access,
  gate, mapping_code, recompute or verify does. Say in RUNBOOK the column is not the geometry's.
- **A3.** `config_hash` covers the extends chain, not `default_minimal`; say so or hash
  `minimal_config`'s config.yaml too.
- **A4.** Put the build-time helper in a new R/ file mapped `any`; keep `lnk_streams_parent.R`
  `none` (join only) so later join edits do not void gate records.

## Acceptance
- **AC1.** "Differences only on changed-gradient segments" fails on correct output: clustering
  (`cluster_rearing`, bridge 0.05, 10 km) moves nearby segments; 44,426 of 203,399 segments change
  gradient in the four groups. Classify each difference as own-gradient / connectivity (within
  cluster distance of a changed segment, species clusters, flag connect writes) / unexplained; fail
  on unexplained only. Assert identical access and segment keys. Same env both builds; working
  tables are overwritten (`wsg_run_one.R:139`), so compare persisted.
- **AC2.** Define #462's number from persisted tables: CH 1050/1150 segments failing width,
  accessible in both, parent's minimal `dist_m` ≤ 1000, parent build's > 1000, rearing false. Say
  it is not comparable to knowledge's 1,042 km (different rule).
- **AC3.** `default_parent` draws `default`'s rules; knowledge's pick needs a bundle extending it
  with its thresholds. Owed, and don't tell knowledge#120 its pick is drawn.

## Scope
- **S1.** `grad-fwa` names its source (`whse_basemapping.fwa_stream_networks_sp.gradient` on
  `linear_feature_id`). Editing `grad-parent`'s prose is allowed but keeps its meaning.
- **S2.** No over-scope. #420's doc line gives the reason for declining (0.66.0 would need a new
  token on every axis).
