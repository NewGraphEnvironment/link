# Findings — Partial runs: recompute the groups outside the run that read its barriers (#274)

## Issue context

## What changes if we do it

A **partial** run (a field-scope pass, a one-area re-run, a recovery over a few
groups into a schema that holds more) also recomputes the groups outside the run
whose walks read the run's barrier rows. Today it recomputes only the run's own
groups, so those readers keep access computed against barriers that have since
been rebuilt.

## What happens if we never do

Nothing changes for a full provincial run: every group is in it. After a
partial run, groups outside it that read its barriers can hold stale
`streams_access` / `streams_mapping_code` and habitat until the next full run.
Whether that is common enough to matter is the measurement below.

## Revised 2026-10-28: the question was inverted

This issue asked whether the recompute could be **narrowed** from every run
group to `run ∪ upstream(run)` taken from `fresh::frs_wsg_drainage()`, to save
time. Three things measured since make that wrong:

1. **The recompute can never be smaller than the run.** `study_area_run.sh`
   models with `LNK_HABITAT_GATE=0` on both legs (#349), so a re-modelled
   group's habitat is settled only by its recompute. Every run group needs one,
   whatever drainage it is in. So there is no saving to measure, on a partial
   run or a full one. (`run ∪ upstream(run)` was always a superset of the run,
   which the original framing missed.)
2. **The outlet closure misses readers.** #374 found `frs_wsg_drainage()`
   misses readers in 150 of 241 groups. A watershed group is not one drainage
   (coastal groups hold many rivers, inland groups hold tributaries entering
   another group's main stem), and gradient barriers are found along the whole
   of every line a group touches and persisted under its own code (1,224
   positions co-held, up to 13 groups). The set complete by construction is
   `data-raw/recompute_deps.R`'s **line** rule: group G reads group D when D
   touches any line whose code is an ancestor of, or equal to, one of G's codes
   (median 9 readers per group).
3. **The scheduler reads that rule but only over the run.** Since #374,
   `data-raw/study_area_recompute.sh` recomputes "the run's groups" once their
   dependencies have landed, and treats a dependency outside the run as already
   landed. It never asks the reverse question: which groups outside the run
   read a group the run rebuilt.

So the live question is correctness on partial runs, not speed:

```
recompute set  =  run  ∪  { G outside the run : some dep of G under the line rule is in the run }
```

The cost figures in the old body are gone too: the 2026-10-23 recompute took
110 min at `-j8` over 240 groups; #261 found the cost is each walk's
province-wide probe, and fresh#272's prefilter (#409) is the speed lever.

## Measure before building

Run `Rscript data-raw/recompute_deps.R <out.tsv> line` over every group, then
for (a) a field-scope set and (b) a plausible one-area re-run, count the readers
outside the run and how many of them the target schema holds. If partial runs
into a shared schema are rare, or their outside readers few, the remedy may be
a printed warning naming them rather than more recompute.

## Conditions on any fix

- **The set comes from the line rule,** never from `frs_wsg_drainage()`, a
  parity score or a size threshold. Threshold-filtering the recompute by parity
  is what produced FINA at 75 % in May 2026.
- **An outside reader is recomputed at the code it was last modelled at, or
  refused.** Its segments and model-time output come from its last run. If a
  file on the recompute's path changed since (the pre-run gate's map,
  `data-raw/pretest_inputs.csv`, #372, names which changed files the recompute
  reaches as `unexercised`), recomputing it mixes two versions; refuse and name
  it instead.
- **The habitat gate is one-way.** Recomputing an outside reader cannot restore
  habitat an earlier recompute blanked; that needs a re-model of the reader.

## Ordering

After the next provincial run (#377's runs row). That run models and recomputes
every group, so nothing is stale until a partial run follows it.

## Acceptance

- [ ] Measured first, on a field-scope set and a one-area re-run: the readers
      outside each run, under the line rule
- [ ] If built: a partial run recomputes, or names and refuses, every group
      outside it that reads a group it rebuilt; a full run is unchanged
      (no outside readers), proven rather than assumed
- [ ] Negative test: a group outside the run that holds no segment of the
      rebuilt path, only a co-held barrier row, is still found

Relates to #374 (the line rule; the closure's miss measured), #349 (the gate is
one-way; models run with it off), #261 (where recompute cost goes), #372 (the
pre-run gate's map).


## Exploration (2026-10-29, plan mode)

- Committed line-rule map `data-raw/logs/recompute_early_374/deps.tsv` (2,211 line pairs over
  208 groups with any). Outside readers by the line rule, before asking what a schema holds:
  - field scope 2026-08-31 (34 groups, into `fresh`) → 78
  - North Thompson 2026-09-03 (FRCN HARR LFRA LNTH THOM UNTH, into `fresh`) → 65
  - parity closure 2026-10-23 (17 groups, `20261023_215312_run_wsgs.tsv`) → 85
  - DUNC alone (#328, into `fresh_default`) → 1 (KOTL)
  LFRA in a run makes every Fraser group a reader.
- `run_finish` (`data-raw/study_area_finish.sh`) sets `ALL_WSGS="$COV_RECOMPUTE"` and uses it for
  both the recompute and the compare. Early mode hands it to the scheduler through
  `recompute_final_write`.
- `RC_DEPS` is computed only in early mode (`study_area_run.sh` ~L1708); `--recompute-at-end` and
  `--recompute-only` have no map today.
- `recompute_audit.R` iterates over `union(log_recompute groups, launched groups)` and skips deps
  outside the run, so a reader launched from the final set audits as `ok`/`after_final`.
- `study_area_verify.sql`'s report table labels a group with `log_recompute` and no `log` row of
  the run as "model started, never finished"; its RAISEs only check modelled-but-not-recomputed.
- Log columns available per row: `config_hash`, `link_sha`, `link_dirty`, `fresh_sha`.
- `data-raw/` R libraries are tested by `sys.source()` from `tests/testthat` (`test-pretest.R`).

## Errors Encountered

| Error | Resolution |
|-------|------------|
