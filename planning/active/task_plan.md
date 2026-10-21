# Task: Through-wetland stretches: use the stream door plus a near-river test, not a free pass (#364)

**If done:** in `default`, a stretch that runs through a wetland is rearing only when it would be as a stream (big enough itself, or close to a large river), so wetlands neither exclude a reach nor admit it on their own. **If never:** `default` keeps every through-wetland stretch a species can reach as rearing with no size, slope or distance test; for chinook that is about 10,200 km, most of it far from where juveniles are caught.

## Decided at the gate (operator + agent, 2026-10-21; settled, not re-asked)

1. **Near-river is a threshold, inherited by fresh, with its measure.** Five columns per stage in
   `parameters_habitat_thresholds.csv`: `<stage>_river_measure` (discharge / channel_width /
   stream_order / model; absent = model), `_discharge_min`, `_channel_width_min`,
   `_stream_order_min`, `_distance_max`; owner fresh. fresh stores `params[[sp]]$near_river$<stage>`.
   It inherits on rules that inherit thresholds and have a size part. A rule can override with a
   mapping or opt out with `near_river: false`, and the walk's pairs come from the same resolver.
   `lnk_rules_build()` writes no numbers, only opt-outs.
2. **Two rear-only dimensions.** `rear_wetland_flow` ∈ {stream, gradient, free; absent = free}.
   `rear_near_river` ∈ {both, stream, wetland_flow; absent = both}. `near_river: false` is always
   stamped on the river-polygon rule (spawn and rear) and never on L/W or `thresholds: false` rules.
   Dead combinations stop the build. The carve-out is `edge_types_explicit: [1050, 1150]` in both
   edge modes.
3. **Two rules, not one six-edge rule.** Under `stream` the 1050/1150 rule drops `thresholds: false`,
   the W type and the #311 floor, and the floor stays on the W polygon rule. Under `gradient` it keeps
   `thresholds: false` and gains `gradient: [0, rear_gradient_max]`, with an error if that is NA.
4. **Discharge/width for the walk.** `default` stays on fwapg + current `discharge_fill`. Under
   `model`, cw groups measure by width. `.lnk_rules_read_mad()` becomes `.lnk_discharge_read_rules()`
   and answers through fresh's `.frs_near_river_specs()` (`getFromNamespace`, listed in
   `.lnk_fresh_required_internal()`).
5. **Persist + log.** `<schema>.streams_near_river` is created by `lnk_persist_init()`. Classify drops
   the stale working table. Persist deletes per WSG and inserts when the table exists.
   `<schema>.log.near_river` holds the effective pairs per WSG, `.lnk_hv_check_log()` compares them,
   and the validator passes the persisted table as `near_river_table`.
6. **Values.** `default`: `rear_wetland_flow = stream` for every rear_wetland=yes species,
   `rear_near_river = both`. CH rear: measure `model`, distance 1000, discharge_min 3, width_min at
   the width whose median MAD is 3 m³/s (floored as #307), confirmed or moved by Phase 4's ladder.
   Every other cell, CO included, is NA until #346. `bcfishpass`: CO → `gradient`. `default` moves
   only in the last phase.
7. **The harness learns structure.** It gets a `dims` row class, `set` widened to `*_river_*`,
   `rules_sha256` / `dimensions_sha256` in `built.csv`, a pair anchor, and an equals-base guard on
   dims. Q × D is two chains, tightest first, `--floor=expected`.
8. **Out of scope, measured anyway:** the W polygon rule's mainline admission (`area_only`), lake
   lines as "a river" (fresh#262), #316, the rule-table issue (drafted at end for review), and the
   export carrying the pair.

## Plan

### Phase 0 — fresh: the measure and the inheritance (sibling repo; branch + PR, never its main)
- [ ] `/planning-init fresh#263` in fresh, sequenced with fresh#262 (one PR or two; link pins the release carrying both)
- [ ] #262: the size key is one of `discharge_min` / `channel_width_min` / `stream_order_min`; the walk reads the named column; `<to>_near_river` records measure + threshold; the predicate matches both; live check gains width and order references
- [ ] Inheritance: `frs_params()` reads five columns per stage (`_measure` in `char_fields`), stops on a half pair (incl. `Inf`), warns on unknown `*_river_*`, stores `params[[sp]]$near_river$<stage>`; `.frs_rule_near_river()` resolves explicit → `false` → inherited-with-a-size-part for both `.frs_rule_to_sql()` and `.frs_near_river_specs()`; `frs_habitat_predicates()` passes the pair in `csv_thresholds_<stage>` under both models; loader coercion guarded by `is.list()`; `.frs_validate_near_river()` takes `false` (refused on L/W), refuses `true`; `frs_habitat_classify()` filters species by `params_fresh` before specs
- [ ] Tests: the fresh#263 list (each measure + `model`; override; opt-out; no-op on `thresholds: false`; refusals; byte identity on NA columns; specs = effective pairs; no size part → no pair; R rule form; half pairs; yaml round trip)
- [ ] NEWS, docs, PR, release tag

### Phase 1 — link pins it
- [x] Install released fresh; `Imports: fresh (>= <ver>)` and `Remotes: NewGraphEnvironment/fresh@v<ver>`
- [x] One commit: `.lnk_fresh_required_formals()` gains `frs_habitat_predicates = c("model", "near_river_table")`; `.lnk_fresh_required_internal()` gains `.frs_near_river_specs`; comments; `test-lnk_preflight_fresh.R` vectors
- [x] Suite on the new fresh before any other change: 3,415 expectations; the only failures (2) are the known stale golden dams pin

### Phase 2 — rules: dimensions, parameters, builder, bundles
- [x] `dictionary_dimensions.csv`: rows for `rear_wetland_flow`, `rear_near_river`; fix `rear_wetland_polygon` default_when_absent/description to `yes`
- [x] `dictionary_parameters_habitat_thresholds.csv`: ten `*_river_*` rows (owner fresh)
- [x] Columns: ten thresholds columns (NA) in `default`, `default_tuned`, `bcfishpass`; two dimension columns in `default` (`free` / `both` for now) and `bcfishpass` (CO `gradient`); frozen bundles untouched
- [x] `lnk_rules_build()`: read the two columns (absent → defaults; unknown → stop; dead combos → stop); emit per Decisions 2–3 via one `add_nr()` helper; carve-out explicit in both edge modes; no `*_river_*` read; roxygen
- [x] Tests in `test-lnk_rules_build.R` (explicit mode): `stream`, `gradient`, each scope value, R always stamped, no L/W ever carries the key, stops, absent columns byte-identical, built rules load through `fresh::frs_params()`
- [x] `build_rules.R`; diff (`bcfishpass` changes only CO's carve-out + R stamps; `default` only R stamps + date); `regen_provenance.R` derives repo root from its own location and covers `default_tuned`, run it; `audit_configs.R` exit 0; `test-dictionaries.R` green; update `.lnk_hv_stage_min()` comment

### Phase 3 — the walk's inputs, the persisted table, the log, the validator
- [ ] `.lnk_rules_read_mad()` → `.lnk_discharge_read_rules()` via fresh's resolver; rename call sites + `test-lnk_discharge.R`; tests: pair by discharge (reads), by width (does not), opt-out everywhere (does not), rule-level `mad:` (does)
- [ ] `lnk_pipeline_classify()` drops `<schema>.streams_habitat_near_river` before classify; `lnk_persist_init()`: `cols_streams_near_river` + table + index + `.lnk_validate_persist_table`; `lnk_pipeline_persist()` delete per WSG, insert when present; statement-count tests 8→9, 7→8; re-check `schema_consolidate.R` and `study_area_verify.sql`
- [ ] `<schema>.log.near_river` written beside `discharge_fill`; `.lnk_hv_check_log()` compares; `near_river_table` threaded to both `frs_habitat_predicates()` calls; `.lnk_hv_check_schema()` checks `streams_near_river` when a pair resolves ("rebuild with link ≥ <ver>"); roxygen: far segment labels `fails_width`; test `.lnk_hv_relax()` leaves EXISTS alone
- [ ] Verify: ADMS forced-fill digest equals unfilled under no-pair `default`; test bundle (CH `stream` + `model` / width-equivalent / 1000) runs end to end on one group, persists, logs, validates with 0 `post_predicate` disagreements

### Phase 4 — the harness learns structure; the CH / CO comparison, before `default` moves
- [ ] `habitat_variants_build.R` / `_score.R` per Decision 7; one-group tests (dims no-op equals base digest; `stream` does not; pair anchor taken by construction; `built.csv` refuses a rules/dimensions change)
- [ ] `data-raw/habitat_score/variants_364.csv` (base `default`): `free`; `stream` no pair; `stream` + CH pair scopes `both` / `wetland_flow` / `stream`; width chain with D fixed; D chain with W fixed; one discharge variant with `discharge_fill=TRUE`; `stream_order` once #262 says what order; CO door only. Held-out per `wsg_roles_364.csv`, `--floor=expected`. Groups: ADMS, BULK + three CH/CO-present groups across Fraser, Thompson, coast, named in the README
- [ ] `data-raw/logs/wetland_door_364/summarise.R`: 1050/1150 km per variant (kept by size / by river / dropped); km the #311 floor alone removed under `free`; km moved on stream edges by the pair; km the W polygon rule admits; river-polygon coverage per measure; capture + cost for CH and CO
- [ ] bcfishpass side: ADMS + BULK `lnk_compare_rollup()` for CO, before (main's `rules.yaml`) vs after
- [ ] README with every table; `research/habitat_thresholds.md` section with `**Verified:** · **Issues:** · **Produced by:**`; issue body edited with the numbers

### Phase 5 — `default` takes the stream door; docs; PR
- [ ] `default/dimensions.csv`: `rear_wetland_flow = stream` for BT, CH, CO, ST, WCT, CT, DV, RB, `rear_near_river = both`; CH `rear_river_*` in `default` and `default_tuned` at the ladder's pick; rebuild rules, regen provenance, audit exit 0; test `frs_params()` on `default` yields `near_river$rear` for CH
- [ ] RUNBOOK §7 (wetland-flow rule row, near-river columns, scope dimension, R opt-out), §6d (export), §6 (persisted table, log column)
- [ ] NEWS; CLAUDE.md status (incl. `fresh_default` not validatable until re-modelled); research verdict line; `data-raw/README.md` + `data-raw/habitat_score/README.md` rows
- [ ] Draft the rule-table issue for review; `/code-check branch`; `/planning-archive`; `/gh-pr-push`

## Owed at the end (reported, done after merge)

- [ ] Cyphers re-prepped for the new fresh pin before the next dispatch
- [ ] Next provincial `default` run re-models every group (validator's log check otherwise refuses `fresh_default`)
- [ ] bcfishpass parity record re-scored at next release (CO moves on the gradient fix)
- [ ] Operator decisions with Phase 4's numbers: W polygon `area_only`; lake flow lines as "a river" (fresh#262)
- [ ] Rule-table issue filed after body review
- [ ] #346: CO's pair, and CH's `rear_mad_min` 0.75 in `default_tuned`

## Validation

- [ ] Tests pass (`devtools::test()` on the new fresh), `lintr`, `devtools::document()`, `pkgdown::check_pkgdown()`
- [ ] `/code-check` clean (once over the branch)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification per phase. Phase 0 uses fresh's suite and the byte-identity test, and Phase 1 the
suite. Phase 2 uses byte diffs of the regenerated and frozen `rules.yaml` files plus the audit's exit
status. Phase 3 uses digest equality, the one-group end-to-end run and the validator. Phase 4 uses the
committed log directory plus the harness's digest and `built.csv` checks. Phase 5 uses the audit and a
`lnk_rollup_wsg()` on one scratch group that matches Phase 4's chosen variant.

## Execution notes

- Link branch `364-<slug>` off main. Both PRs are opened, and neither is merged without the user's word.
- Phase 4 runs model builds on the local fwapg DB. The run decisions are stated up front in the
  progress log: config `default`, scratch schema `score364_*`, the closure and the species.
  Long runs go in the background with a measured clock.
