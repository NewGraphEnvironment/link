# Findings — Backlog move 1: The parent gradient on the full network, and the grad tokens (#469)

## Issue context

Umbrella #469 (backlog move 1, batch 1). Issues in the batch: #460, #420, #462, #463. No comments on
any of the five (read 2026-11-09). Gate per the umbrella: #462's option, and whether #420's
older-build tokens are still wanted; both decided (task_plan.md).

## Exploration (plan mode, 2026-11-09)

- `lnk_vocabulary_resolve()` hard-codes `grad = "gradient=segment"` in `.lnk_vocabulary_specs()`
  (`R/lnk_vocabulary.R`); matching is exact on `(axis, spec)` among live rows. `grad-parent`'s row
  (0.79.0) has spec `gradient=parent;parent_cut=cut-min`, which nothing resolves to yet.
- `lnk_pipeline_classify()` calls `fresh::frs_habitat_classify(table = <schema>.streams)`, which
  reads the working `streams.gradient`; fresh's connectivity (`frs_cluster.R`) reads `gradient`
  too (bridge gradient). So swapping working `streams.gradient` between `lnk_pipeline_break()` and
  classify covers classify, the overlay, `frs_order_child()` and connect. Breaks and access do not
  read segment gradient (barriers come from fresh's gradient positions in prepare).
- fresh's near-river table is walked inside `frs_habitat_classify()` from each segment's downstream
  end (`frs_near_river()`); there is no argument to hand it a prepared table, so carrying the
  parent's distance (#462 option a) would need a fresh change. Declined at the gate.
- `streams_parent` is keyed `(id_segment, watershed_group_code)` in the full schema; ids are each
  build's own, so a new build must map its segments by position, not id.
  `.lnk_streams_parent_builds()` (R/) already reads each side's newest closed log row; the stale
  checks live in `data-raw/streams_parent.R` (`streams_parent_rows_why()`).
- `default`'s YAML schema is `fresh`; the provincial build was run with `--schema=fresh_default`,
  so the grad-parent knob names its schemas explicitly.
- `data-raw/pretest_inputs.csv` maps `R/lnk_streams_parent.R` as `none`, and `test-pretest.R`
  checks a `none` file is not reached from `wsg_run_one.R`: reading it from the run flips both.
- m4 (this machine) holds `fresh_default.streams_parent` (241 groups, 5,546,370 rows),
  `fresh_default_minimal` (241 groups) and `fresh_default.streams_near_river`.
- Under `default`'s own rules the near-river pair applies only to CH on through-wetland lines
  (`rear_near_river = wetland_flow`, #364), so #462's 1,042 km (knowledge's `Q3@D1000` on every
  line) is not what `default_parent` will show; Phase 3 measures what it does show.

## Errors Encountered

| Error | Resolution |
|-------|------------|
