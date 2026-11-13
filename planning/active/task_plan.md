# Task: Backlog move 1: The parent gradient on the full network, and the grad tokens (#469)

**If we do it:** link classifies on each full segment's minimal parent's gradient under `grad-parent`, and the Freshwater Atlas segment's gradient has a token, so NewGraphEnvironment/knowledge#120's picks can be drawn and archived. **If we never do:** knowledge's minimal-network tuning stays a comparison link cannot deploy, and one of its setups stays untokened.

Batch 1: #460 (`grad-fwa`), #420 (tokens for older builds), #462 (near-river distance under `grad-parent`), #463 (classify on `streams_parent.gradient_minimal`).

## Context

#444 built `fresh_default.streams_parent` (each full segment's `cut-min` parent, 241 groups on m4)
and named the reading `grad-parent`, but no build reads it. knowledge#120 drew the parent-gradient
setup with a stand-in on scratch copies; link cannot. And the Atlas-segment gradient setup has no
token, so knowledge refuses to archive it. One PR, branched from `origin/main` at `3c0ab0bc`
(main moved from `f8a45c29` during the gate: two unrelated commits). The backlog file itself
(`planning/backlog.md`) lands with PR #482, still open at the park; merge `origin/main` on resume.

## Decided at the gate (operator, 2026-11-09; parked 2026-11-10)

- **#462: report the near-river gap as transfer cost.** The distance stays per segment; the proof
  build measures the CH rearing it costs. No fresh change. Carrying the parent's distance stays
  possible later (a fresh change: classify taking a prepared near-river table); #462 closes with
  the measurement and that note.
- **#420: close it with a doc line.** Its Atlas-line item is #460. Older builds stay filed by run
  id; `research/output_vocabulary.md` says a consumer's own flow read is its input, not a link axis.
- **Proof: the four proof groups** (BULK, SETN, MORK, COTR) on m4, not the province.

Approved with the plan (operator, 2026-11-10):

- **Parent source:** the build reads the verified `<full schema>.streams_parent` that
  `streams_parent_build.R` writes (the table knowledge reads), not a join of its own. It maps each
  working segment to the full schema's segment by `blue_line_key`, start and length (within 1 mm,
  never by `id_segment`) and refuses unless every working segment maps one-to-one. That proves the
  build cut the network the table was joined on.
- **Persisted `gradient` in a grad-parent schema is the value classify read** (the parent's), so
  the validator and any re-test agree with the habitat; `token_grad = grad-parent` says so.
- **A new bundle `default_parent`** (`extends: default`, schema `fresh_default_parent`), so
  `default`'s shipped `grad-seg` habitat is never overwritten.

## Phase 0: resume (review O3, O2)

- [x] Merge `origin/main` (PR #482's backlog, if merged) before touching `pretest_inputs.csv`,
      NEWS or CLAUDE.md. Merged 2026-11-12 (`1af2bf95`), clean: main had moved to 0.80.0 (#465),
      so this release is **0.81.0** throughout; #482 still open.

## Phase 1: grad-fwa and #420's doc line (#460, #420)

- [x] `inst/extdata/vocabulary.csv`: row `grad-fwa`, axis `grad`, spec `gradient=fwa_segment`,
      introduced `0.81.0`; definition names its source,
      `whse_basemapping.fwa_stream_networks_sp.gradient` on `linear_feature_id` (the FWA segment,
      not the whole blue line); no link segment crosses an FWA segment boundary; no link build
      writes it (S1).
- [x] `research/output_vocabulary.md`: `grad-fwa` on the gradient axis; a line that a consumer's
      own discharge read is its input, not a `q-` token; pre-0.70.0 builds are filed by run id,
      because `default` at 0.66.0 cut at every observation and gradient class before #326/#396 and
      would need a new token on every axis (#420's answer, S2).
- [x] `tests/testthat/test-lnk_vocabulary.R`: `grad-fwa` is live, its spec unique, and no shipped
      bundle resolves to it.

## Phase 2: a build setting that reads the parent's gradient (#463)

- [ ] Config key `pipeline: gradient:` with `source: segment | parent` (absent = `segment`) and,
      for `parent`, `minimal_config` and `schema_full`; `schema_minimal` derived from
      `minimal_config`'s `pipeline.schema` (or a given one refused when it differs). Validated
      when the manifest loads: unknown source or sub-key, non-identifier schema, a
      `minimal_config` whose own source is `parent` (G6).
- [ ] `R/lnk_vocabulary.R`: grad spec `gradient=segment`, or for `parent`
      `gradient=parent;parent_cut=<cut token minimal_config resolves>`, refusing unless
      `minimal_config`'s acc and flow tokens equal this config's (G6). `grad-parent`'s definition
      loses "No link build writes it", meaning unchanged (S1). Roxygen of
      `lnk_vocabulary_resolve()` updated (G8).
- [ ] New R/ file (mapped `any` in `pretest_inputs.csv`; `R/lnk_streams_parent.R` stays `none`
      with the join only, A4) holding:
  - [ ] the per-group stale check as SQL taking a schema and groups and returning the
        `verify.tsv` columns, called by `streams_parent_build.R`'s `verify_groups()` and by the
        build (G3);
  - [ ] the DB half of the pair guard per group: both builds closed, `link_dirty`/`fresh_dirty`
        FALSE, `fresh_sha` known and equal, same species, full side `grad-seg` with this build's
        cut/acc/flow, minimal `token_cut` the resolved parent cut with the same acc/flow, the
        rows' `schema_minimal` the config's (G2). The git half stays `streams_parent_build.R`'s.
- [ ] `lnk_pipeline_run()` for `source: parent`:
  - [ ] refuse a persist schema equal to `schema_full` or `schema_minimal` (it sees
        `LNK_SCHEMA`'s override), and `schema_full == schema_minimal` (G1);
  - [ ] the judgement right after `lnk_vocabulary_resolve()`, before the log opens (O1);
  - [ ] after break, whatever the active species (G7): a bijection within the group between
        working and `schema_full.streams` segments on `downstream_route_measure` and
        `upstream_route_measure` within 1 mm, each matched exactly once, equal counts (G4);
        `ALTER COLUMN gradient DROP EXPRESSION`, then set it to `gradient_minimal` (B1);
  - [ ] log the parent rows read (`run_id_full`, `run_id_minimal`, `schema_full`) as a
        `log_input` row or in `log.notes` (G5); the phase list in roxygen (G8).
- [ ] `inst/extdata/configs/default_parent/config.yaml` (thin, `extends: default`, schema
      `fresh_default_parent`). Say in RUNBOOK that `config_hash` covers the extends chain, not
      `minimal_config` (or hash its config.yaml too) (A3).
- [ ] Tests: resolver (only `default_parent` resolves `grad-parent`; it differs from `default`
      only in grad; a non-`cut-min` or different acc/flow minimal config refuses), config
      validation, the rewrite of `test-lnk_vocabulary.R:117-133` (G8), and each refusal (stale
      run id, length mismatch, a segment with no row, an unmatched or doubly matched segment, a
      persist schema equal to `schema_full`) in the live DB tests, with the swap tested on a
      GENERATED column (B1). `test-streams_parent_build.R` follows `verify_groups()` (G3).

## Phase 3: proof build on m4, and #462's transfer cost

- [ ] Bump DESCRIPTION to 0.81.0 and commit before building; build from a clean committed tree
      with `LNK_LOAD=loadall` (O2).
- [ ] Before building, compare each group's `fresh_default` `log_input` artifact ids with m4's
      `provenance.source_artifact` (A1).
- [ ] `data-raw/logs/grad_parent_463/`: BULK, SETN, MORK, COTR under `default_parent` into
      `fresh_default_parent`, and under `default` into a scratch control schema, same commit,
      order and env (`LNK_HABITAT_GATE`, `LNK_GUARD_DOWNSTREAM=warn`), on a quiet database. A
      group refused on mapping is reported as the refusal working and replaced by another (A1).
- [ ] Check from persisted tables (working tables are overwritten): segment keys and access
      identical between control and parent; segmentation identical to `fresh_default`; persisted
      gradient equals `gradient_minimal`; `log.token_grad` is `grad-parent`; each habitat
      difference classed own-gradient / connectivity (species clusters, the flag connect writes,
      within cluster distance of a changed segment) / unexplained, failing on unexplained (AC1).
- [ ] #462 from persisted tables: CH 1050/1150 segments failing width, accessible in both, whose
      parent's `fresh_default_minimal.streams_near_river.dist_m` ≤ 1000 and own > 1000 with
      rearing false in `default_parent`; km per group into the README and
      `research/minimal_network.md`, said to be not comparable to knowledge's 1,042 km (AC2).

## Phase 4: docs and release

- [ ] RUNBOOK §6b (:886, :1000-1003 and "Parent attributes"): what reads `streams_parent` now, the
      bundle, the refusals, the git half of the guard as the builder's job, that a grad-parent
      schema's `gradient` is the parent's (the segment's own sits at the same position in
      `schema_full`), that a re-model of either network voids its input, and that it runs only
      where `schema_full` and `streams_parent` exist (the dispatcher) (G2, G9, A2).
- [ ] `research/output_vocabulary.md`'s config→tokens table gets `default_parent` (G9).
- [ ] NEWS, CLAUDE.md status.

## Owed at the end (reported, done after merge)

- [ ] Close #460, #420 (doc line), #462 (measured cost, carry option noted), #463 by the PR.
- [ ] knowledge#120 can archive `grad-fwa` runs and read a link `grad-parent` build: say so there.
- [ ] A provincial `default_parent` build waits for an operator decision (not this move).
- [ ] knowledge's pick needs a bundle extending `default_parent` with its thresholds; tell
      knowledge#120 that, not that its pick is drawn (AC3).

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the resolver and config by unit tests; each refusal by a test that
restores the defect and goes red; the build by Phase 3's per-segment comparison against a control
built the same way, where any habitat difference off a changed-gradient segment fails the script.
