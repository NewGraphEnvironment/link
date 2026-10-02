# Review: variants harness for MAD ladders (#302), round 3

Scope: working tree of `data-raw/habitat_variants_build.R`, `data-raw/habitat_variants_score.R`
and `data-raw/query_habitat_thresholds_fiss.R`, including the parent's mid-review
`schema_of()` zero-length fix. The planned input is `variants_302.csv` + `wsg_roles_302.csv`.
I reviewed by reading, with read-only probes:
- an R probe of zero-row `$<-`;
- psql on :5432 for discharge NULL share per focal WSG and for existing schemas.

I ran neither script. #284's regression is not duplicated here.

## Findings

- **[bug, loud]** `habitat_variants_score.R:632` `rule$floor_of_record <- floor_of_record`
  (new in #302).
  - When no held-out WSG is in scope, `rule` has 0 rows. Line 554 says "verdict.csv carries
    no rows" and the script carries on.
  - Assigning a length-1 scalar with `$<-` onto a 0-row data.frame then errors: "replacement
    has 1 row, data has 0". I reproduced this in R.
  - Every earlier `rule$...` assignment is vector-valued and survives.
  - It hits any pre-flight on in-sample WSGs only, for example `--wsgs=PARS` or `--wsgs=KOTL`
    with `wsg_roles_302.csv`. That is the natural single-WSG pre-flight, since PARS carries
    all three species.
  - The crash comes after the whole validation pass, and before taper, elevation, bridge and
    the stamp are written.
  - Fix: `rule$floor_of_record <- rep(floor_of_record, nrow(rule))`.

- **[bug, verdict disagrees with the rule fixed before the run]** `habitat_variants_score.R:593-625`
  (`walk()`, the "underpowered" branch).
  - `research/habitat_thresholds.md` ("Scoring design, fixed 2026-10-02") says: *"An
    underpowered first step lands P05, marked unscored."*
  - The walk instead writes `walked_value` / `walked_value_of_record` = NA, with status
    "underpowered at <P05 rung> - the step 1-4 verdict stands".
  - For a MAD ladder there is no step 1-4 verdict in any bundle: `default`'s
    `*_mad_min` are NA. So the status names a fallback that does not exist, and the
    verdict-of-record value is NA where the design says P05.
  - This is the likely outcome, too, because the expected floor is the floor of record and
    the held-out WSGs were sized as upper bounds. So the CSV will disagree with the doc
    exactly where #302 expects to land.
  - A second, smaller ambiguity: the design says "the walk stops at the first step not
    taken". An underpowered P02 after a taken P05 therefore reads as P05, but the code gives
    NA (#284's semantics).
  - Fix: for a ladder with an anchor, either implement both cases in `walk()` (first
    post-anchor step underpowered → that step's value plus "unscored"; a later one →
    the last taken value), or state in the doc that this is applied by hand, as the
    literature veto is.

- **[fragile, can rewrite #284's committed evidence and DB state]** `habitat_variants_build.R:81,95`
  and `habitat_variants_score.R:73-74,164`. `--prefix` and `--out` still default to #284's
  values whatever `--variants` says.
  - **Build.** `--variants=…variants_302.csv --roles=…wsg_roles_302.csv` with no `--prefix`
    and no `--out` writes into #284's schemas and log directory:
    - it re-runs the base into `score284_default` and `working_score_*` for the shared WSGs
      (ELKR, KOTL, PARS, REVL, UARL). At a new HEAD the resume gate does not hold, so they
      are rebuilt;
    - it overwrites the committed `data-raw/logs/habitat_score_284/closure.txt`;
    - it rewrites rows of the committed `base_habitat_digest.csv`, `base_recompute.csv` and
      `built.csv`;
    - it appends to the committed `stamp_build.txt`;
    - it writes 18 bundles into the committed `bundles/`.

    That is the state #284's regression re-run reads.
  - **Score.** The same invocation calls `unlink()` on #284's 11 committed outputs at line 164,
    *before* `cfg_of()` stops for missing bundles. git can recover them, but the tree is
    damaged first.
  - `query_habitat_thresholds_fiss.R` got exactly this guard in round 2 (a non-default
    species set needs an explicit `--out`). The two harness scripts did not.
  - Fix:
    - refuse a `--variants` other than `variants.csv` unless `--prefix` and `--out` are both
      given (or derive both from the variants file);
    - in the score, move the `unlink()` below the bundle and built.csv checks.

- **[fragile, guard scoped to the planned shape]** `habitat_variants_score.R:423` (`model_step`)
  and `:117-128`, `:437-441`, with `habitat_variants_build.R:150-159`.
  - The mechanism of rounds 1-2 is still open at its edges, because the guards assume the
    planned shape (a mad ladder starts at the base, and a cw variant has no `set`):
    - **(a) A mid-ladder anchor.** `model_step` means "model differs from step_from", not
      "step_from is the base". A `mad` step from a non-base `cw` rung (or a `cw` step from
      a `mad` rung) then counts as an anchor in the middle of a ladder:
      - it is force-decided `take (anchor: model change)`;
      - the set-fixed check skips it (line 121);
      - `core_of()` keeps that cw rung in the core, which brings back round 2's width-cut
        core.
    - **(b) A cw variant's `set`.** The `*_mad_*` restriction applies only to `mad` variants.
      A cw variant whose `set` names a gradient or width cell sits in an all-cw ladder, and
      `core_of()` keeps the base there. The base lacks that cell, so the core is cut at
      default's value: round 1's finding 2.
  - Neither shape is in `variants_302.csv` or `variants.csv`, so nothing is wrong today.
  - Guards:
    - assert `model_step` only where `step_from == base_variant`;
    - extend the set restriction to cw variants: no set, or only cells the cw base does not
      read.

- **[fragile, diagnostic only]** `habitat_variants_score.R:715-719` (taper).
  - For a MAD ladder the core is cut into **gradient** bins (`grad_bins`), on an axis the
    ladder does not move. The segment query (`:681`) does not fetch discharge at all.
  - So taper.csv's `core (…]` rows for the six MAD ladders are not a taper toward the
    discharge cutoff, though they are labelled as one.
  - The band rows and `ratio_to_core` are correct, and the research doc does not cite the
    taper for #302.
  - Fix: bin a MAD ladder's core on `mad_m3s` (join `fwa_stream_networks_discharge` on
    `linear_feature_id`), or write no core bins for it.

Mid-review fix checked: `schema_of()` now returns `character(0)` on empty input, in both
scripts, and the anchor `WHEN` branch is built only when `nrow(anc) > 0`.
- I audited every other `paste0` / `sprintf` / `dbQuoteString` call over a possibly-empty
  vector (rows S6, S41-S43, S45, S49, B8, B12 below). All are either scalar or produce
  `character(0)` correctly.
- `flag_of(character(0))` gives `match()` → `integer(0)` → `sprintf()` → `character(0)`.
- `w_sp` empty gives `"{}"`, but `lnk_habitat_validate_band()` stops first (`length(aoi) >= 1`):
  loud, not silent.
- The method-table `rbind` with no new WSG binds a 0-row frame: fine.

## Enumeration

83 places: 50 in the score, 29 in the build, 4 in the FISS script.
- (a) is #284's cw gradient ladders: no model or set, one cw chain, `_max` columns.
- (b) is the six MAD ladders of `variants_302.csv`: an anchor, `_min` rungs, and a `set`
  holding the other stage's MAD range.

Every entry is either ok or one of the five findings above. Nothing else in either script
derives a schema, core, band, value, direction, WSG set, species set, digest or check.

### habitat_variants_score.R

| # | line | what is derived | (a) #284 cw | (b) #302 MAD |
|---|---|---|---|---|
| S1 | 91-103 | variants read; `model` default cw; base unique and cw | ok (no model col → cw) | ok |
| S2 | 104-114 | `n_set`, `parse_set` (same parse as build) | ok (0) | ok (3 cells) |
| S3 | 117-128 | set held fixed along a ladder | ok (all empty) | ok for planned; skip rule is finding 4a |
| S4 | 132-153 | step_from listed, no branch below base, no cycle | ok | ok |
| S5 | 155-158 | focal, roles ∩ focal, species | ok | ok (BT, GR, RB) |
| S6 | 160 | `schema_of` (zero-length fix) | ok | ok |
| S7 | 164 | `unlink` of outputs | ok | **finding 3** (runs before any check) |
| S8 | 167-171 | head sha, dirty paths | ok | ok |
| S9 | 178-186 | cfg per variant (base `default`, others from `<out>/bundles`) | ok | ok |
| S10 | 201-215 | built.csv WSG set (focal ∩ species roles) and schema name | ok | ok |
| S11 | 216-220 | thresholds sha vs built | ok | ok |
| S12 | 224-245 | method sha vs built; bundle method table puts w_v on `model_of(v)` | ok (NA allowed for cw) | ok (all role WSGs mad) |
| S13 | 247-269 | n_diff = 1 + n_set vs current default; value; each set cell (num or text) | ok | ok (4 cells) |
| S14 | 275-292 | per-variant access digest = base's | ok | ok |
| S15 | 294-300 | absences and pooling over species | ok | ok |
| S16 | 306-312 | `species_of`, `aoi_of` | ok | ok |
| S17 | 314-324 | validate each variant on its own cfg (model from the cfg's method table) | ok | ok |
| S18 | 332-345 | `obs_key` same observations and segments as base | ok | ok (attachment is model-independent) |
| S19 | 347-364 | summary role, totals | ok | ok |
| S20 | 369-385 | habitat_change against the base | ok | ok as labelled: a mad rung against **cw** default, so a rearing rung's `spawning_km_added` is its `set`'s change, not the step's |
| S21 | 391-402 | absence sites attached on base | ok | ok |
| S22 | 407-415 | `thr_default`, `value_of` | ok | ok (anchor NA, later rungs their step_from's value) |
| S23 | 416-418 | `steps$value_from` | ok | ok (mixed NA/numeric simplifies to numeric) |
| S24 | 423 | `model_step` | ok (none) | ok for planned; **finding 4a** |
| S25 | 426-429 | `loosens` (`_min` ↓), `direction` | ok (unchanged for `_max`) | ok (all six ladders strictly decrease) |
| S26 | 430-433 | `ladder_of` (species × column) | ok | ok (one chain per column) |
| S27 | 437-441 | `core_of` (mad: rungs only) | ok (base + rungs, unchanged) | ok; **finding 4b** for cw-with-set |
| S28 | 444-457 | step shares species, column, flag and stage with step_from | ok | ok |
| S29 | 462-473 | UHC reaches would sit in the core | ok | ok |
| S30 | 474-504 | band per step: `w_sp`, schema, schema_ref, core | ok | ok (anchor ref = base, core = rungs) |
| S31 | 485-495 | absence band, covered WSGs | ok | ok |
| S32 | 517-530 | 1 % against-direction stop (anchors excluded) | ok | ok |
| S33 | 534-547 | pooled aggregate; `value_from` joined back after | ok | ok |
| S34 | 550-555 | rule filter: held_out, direction = step_direction, stage = obs_stage | ok | ok (RB spawn on `spawn`) |
| S35 | 556-561 | found-floor decision | ok | ok |
| S36 | 562-563 | anchor forced take | n/a | ok |
| S37 | 570-575 | expected-floor decision, anchor forced | ok | ok |
| S38 | 583-592 | `chain_to`, `tips` | ok | ok ([anchor, P05, P02]) |
| S39 | 593-625 | walk: taken / refused / underpowered values | ok | **finding 2** |
| S40 | 629-641 | floor-of-record columns | ok | **finding 1** (0 held-out rows crash) |
| S41 | 650-664 | taper ladders, `lad`, `sch_all`, `flag_of` | ok | ok |
| S42 | 668-681 | `band_case` (thr steps first, anchor split last) | ok (no anchor branch since fix) | ok |
| S43 | 689 | taper core from `core_of` | ok | ok |
| S44 | 695-697 | taper obs stage | ok | ok (single stage per ladder) |
| S45 | 715-719 | taper core gradient bins | ok | **finding 5** |
| S46 | 732-746 | elevation terciles of each WSG's core | ok | ok (core = rungs) |
| S47 | 747-759 | elevation per class vs core in same class | ok | ok |
| S48 | 764-771 | elevation_adjusted | ok | ok |
| S49 | 777-834 | bridge_band: added rearing steps, `in_window` gradient-only | ok | ok (NULL for MAD and anchor) |
| S50 | 836-871 | score stamp | ok | ok (method sha not printed; it is in built.csv) |

### habitat_variants_build.R

| # | line | what is derived | (a) | (b) |
|---|---|---|---|---|
| B1 | 81-95 | `prefix`, `working_prefix` (derived), `dir_out` | ok | **finding 3** (prefix and out default to #284's) |
| B2 | 98-105 | dirty and head | ok | ok |
| B3 | 107-130 | column set (model and set optional), base on cw | ok | ok |
| B4 | 134-146 | `parse_set` with malformation checks | ok | ok |
| B5 | 150-159 | mad `set` only `*_mad_(min\|max)` | n/a | ok; **finding 4b** for cw |
| B6 | 163-184 | ladder well-formed | ok | ok |
| B7 | 185-197 | `--only`, focal ⊂ roles | ok | ok |
| B8 | 199-200 | `schema_of` (zero-length fix), `working_of` (scalar callers only) | ok | ok |
| B9 | 206-212 | cfg_default, loaded, default thresholds and method table | ok | ok |
| B10 | 216-231 | thresholds writer reproduces default byte for byte | ok | ok |
| B11 | 234-262 | bundle cells, equals-default refusal, n_diff = cells | ok | ok (4 cells, all NA in default) |
| B12 | 275-294 | mad method table (all role WSGs for the species on mad) and provenance | n/a | ok |
| B13 | 295-321 | config.yaml, `lnk_config_verify` per declared file, method path resolves to the written one | ok | ok |
| B14 | 322-330 | `equals_bundle` | ok | ok (none) |
| B15 | 335 | `run_variants` (base always first) | ok | ok |
| B16 | 345-370 | `record_built` (method sha; pre-#302 NA column) | ok | ok |
| B17 | 373-388 | digest SQL (streams, access, working habitat) | ok | ok |
| B18 | 393-426 | base closure and resume gate | ok | ok under its own prefix; finding 3 otherwise |
| B19 | 432-445 | base habitat digest per focal WSG | ok | ok |
| B20 | 449-492 | access recompute on focal | ok | ok |
| B21 | 495-518 | `copy_access` | ok | ok |
| B22 | 520-533 | `run_variant` WSGs (base: focal; variant: focal ∩ species roles), species | ok | ok |
| B23 | 535 | `lnk_persist_init` sized to the bundle | ok | ok |
| B24 | 544-555 | mad_m3s guard (column exists, count > 0) | n/a | ok (probe: NULL discharge is 0-4 % of km in the 12 focal WSGs; partial NULL drops alike from every rung) |
| B25 | 557-561 | classify and connect, method from the cfg path | ok | ok |
| B26 | 563-575 | base re-classify digest | ok | ok |
| B27 | 576-584 | persist species, copy access | ok | ok |
| B28 | 585-590 | streams and access equal base per WSG | ok | ok |
| B29 | 598-632 | build stamp (thresholds hash only) | ok | ok (method sha is in built.csv) |

### query_habitat_thresholds_fiss.R

| # | line | what is derived | (a) | (b) |
|---|---|---|---|---|
| F1 | 39-58 | `--out` / `--species` guard | ok (default reproduces #284 rows; adds mad rows, noted in round 2) | ok |
| F2 | 98-101 | per-species presence flag by common name | ok | ok |
| F3 | 122-128 | snapped `seg_mad_m3s` by `linear_feature_id` (unique) | ok | ok |
| F4 | 180-188 | mad presence/absence metrics (shares NA where default has no range) | n/a | ok |
