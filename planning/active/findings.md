# Findings — A vocabulary for link's outputs (#414)

## Issue context

**If we do it:** every link output is named by what it is (how its streams were cut, how its attributes were measured, where its flow came from), from one table both link and its consumers read, so a name still decodes years later and two repos never name one network differently. **If we never do:** outputs keep their working config names, whose meaning moves with every config edit, and each consumer (a tuning archive, a report, a comparison) invents its own names for the same thing.

## Problem

Configs are named for how they were made: `default`, `default_tuned`, `default_extrabreaks`, `default_rearbreaks`, `bcfishpass`. A config's contents change over time while its name stays, and a provincial run renames its schema `fresh_default_<date>`, so neither a config name nor a schema name says what an output holds. Downstream, habitat-threshold tuning is starting to store runs on several of link's outputs side by side (the same species tuned on differently cut networks, with differently measured gradients), and it needs names that say what each one is and stay true. Only `bcfishpass` is defined by something outside us; every other name here is early and can still be chosen well.

## Proposed

- [ ] **One tracked table:** `token`, `axis`, `definition`, `introduced`, `retired`.
- [ ] **Three axes to start,** each a measurement choice of an input, not a result:
  - break set: what streams are cut at, defined by its full `break_order` and `observation_breaks`;
  - gradient measure: over the segment, over the whole Atlas line, over a fixed window once fresh provides one;
  - flow source: where a stream's size comes from.
  Anything a tuning chooses (a threshold, width against flow) is a result and gets no token; anything that only identifies one build (date, commit, run) goes in the build's record.
- [ ] **Rules:** tokens are lowercase (macOS treats `A` and `a` as one name where S3 and Linux treat them as two); a token is never renamed and never reused for a new meaning; a changed definition is a new token; a retired token stays in the table so old names still decode.
- [ ] **First test:** describe today's outputs (`default`, `bcfishpass`, `default_extrabreaks`, `default_rearbreaks`) in tokens. If that needs a new token per config rather than a few per axis, the axes are wrong; fix them before anything is named.
- [ ] **Each build records its tokens** in its build record, and a check refuses a build whose tokens are missing from the table or retired.
- [ ] Consumers read the table rather than copying it.

Tokens to argue over, not settled: `cut-access` (barriers and access gradients only), `cut-full-top` (every break source, the top observation per species), `grad-seg`, `grad-line`, `q-wet`, `q-fwapg`.

## Not proposed

No renaming of configs or schemas; the tokens describe outputs, and config names stay link's working names.


## First test (plan-mode exploration, 2026-10-29)

Describing today's configs per the issue's three axes fails on the cut axis:

- `gradient_classes` moves cuts: `default_extrabreaks` (10 classes at spawn/rear ceilings) and `default_rearbreaks` (7) differ from `default` there, and also in `observation_breaks` (absent, so `all`: they predate #396).
- Access inputs move cuts (#326 breaks only at each present species' downstream-most barrier after lifts). `parameters_fresh.csv` differs between bcfishpass and default in the lift columns (BT lifts on `BT;CH;CO;SK;PK;CM;ST` from 1900 in bcfishpass, on `BT;DV` any date in default; RB has a lift rule in default only; default adds GR and KO). `wsg_species_presence.csv` differs too. extrabreaks/rearbreaks carry older copies of both (no RB lift rule, the bcfishpass presence table).
- `cabd_additions_barriers` (default true, bcfishpass false) moved only DAM mapping-code tokens in #367; segments identical. Not a cut input.
- bcfishpass alone has `subsurfaceflow` in `break_order`.

Effective defaults: `break_order` default at `R/lnk_pipeline_break.R:105`; `gradient_classes` falls back to `.lnk_classes_bcfp` (1500/2000/2500/3000) via `.lnk_resolve_classes()` (`R/lnk_pipeline_prepare.R`); `observation_breaks` defaults to `all` (`.lnk_observation_breaks()`).

Where the build record is written: `.lnk_log_run_start()` (`R/lnk_log.R`), called from `R/lnk_pipeline_run.R:163`; `cols_log` gains columns via `ADD COLUMN IF NOT EXISTS`. The habitat export copies whole `log` rows into `provenance/.../log.parquet`.

The pretest map refuses an unmapped changed file (`data-raw/pretest_inputs.csv`), so new files need rows.

## Errors Encountered

| Error | Resolution |
|-------|------------|
