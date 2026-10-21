# Findings — Through-wetland stretches: use the stream door plus a near-river test, not a free pass (#364)

## Issue context (body as of 2026-10-21T16:36Z, including the parked plan's Context at the gate)

**If done:** in `default`, a stretch that runs through a wetland is rearing only when it would be as a stream (big enough itself, or close to a large river), so wetlands neither exclude a reach nor admit it on their own. **If never:** `default` keeps every through-wetland stretch a species can reach as rearing with no size, slope or distance test; for chinook that is about 10,200 km, most of it far from where juveniles are caught.

## What we want

Being in a wetland should not throw a stream out, and should not let it in either. A through-wetland stretch (FWA edge types 1050 and 1150) goes through the same door as any stream: its slope must be in range, and **either** it is big enough on its own **or** a large river lies a short distance downstream. For chinook rearing the tuned values are a flow of at least 0.75 m³/s, or a river of at least 3 m³/s within 1 km.

## What `default` does now

`lnk_rules_build()` emits, for every species with `rear_wetland = yes` in `dimensions.csv`, a rear rule for edge types 1050 / 1150 with `thresholds: false`:

```yaml
- waterbody_type: W
  edge_types_explicit: [1050, 1150]
  thresholds: false
  wetland_ha_min: 1.0
```

Any one rear rule is enough, so these stretches are rearing whatever their size, slope or distance from a river. The species-level connection step (`cluster_rearing`, spawning within 10 km for CH) is the only check left, and 10 km keeps reaches far from use. Example: Coffin Creek in the Bulkley (segment through a 59.5 ha wetland, flow 0.23 m³/s, 5.3 km from the nearest 3 m³/s river) is kept as CH rearing under `default`.

Measured on chinook rearing across the 125 CH groups (province-wide `default` run, tuned rule applied through classification, overlay and connection):

| | km |
|---|---|
| Through-wetland CH rearing now | 10,197 |
| Kept under the stream door + near-river test (flow ≥ 0.75 m³/s, or a 3 m³/s river within 1 km) | 2,338 |
| … kept by flow | 1,627 |
| … kept by distance only | 711 |

A fitted use curve (expected chinook catch per standard electrofishing visit, 0–1) gives the kept stretches a median of 0.34 and the dropped ones 0.02.

## How bcfishpass does it, in our terms

The free pass did not come from bcfishpass for chinook. bcfishpass's habitat SQL (`load_habitat_linear_ch.sql`, `load_habitat_linear_co.sql`, main of 2026-10-01):

| | CH through a wetland | CO through a wetland |
|---|---|---|
| bcfishpass | never rearing (only river polygons and stream lines outside any waterbody) | rearing when the gradient passes, no size test |
| link `default` | rearing, no test | rearing, no test |
| wanted (`default`) | stream door + near-river test | same idea, CO's own numbers once tuned |

The `bcfishpass` bundle should express that with its own `dimensions.csv` and rules: no wetland rearing for CH, and CO's carve-out with the gradient test kept. Worth checking it does today.

## Proposed

- [ ] A `dimensions.csv` column choosing how through-wetland lines rear (name to settle): the stream door, the current free pass, or none. `default` takes the stream door; the `bcfishpass` bundle takes what bcfishpass does per species.
- [ ] Near-river parameters per species and stage in `parameters_habitat_thresholds.csv` (for example `rear_river_discharge_min`, `rear_river_distance_max`), used through fresh's near-river condition (NewGraphEnvironment/fresh#259) on stream and through-wetland lines. This is also the parameter #346 needs: the tuned CH rule's exception has no link parameter today.
- [ ] Lakes and river polygons keep their own rules; lake rearing is a separate life history and river polygons are the large rivers themselves.
- [ ] Rerun the CH and CO comparison on the new design before changing `default`.

Related: #346 (calibration from published evidence), #316 (wetland construction lines reach no rear rule).


## fresh side: shipped in fresh 0.41.0 (2026-10-21)

NewGraphEnvironment/fresh#259 closed with NewGraphEnvironment/fresh#261. What link needs to know when it wires this in:

- **Grammar:** a rule key `near_river: {discharge_min, distance_max}` on spawn and rear rules (not on `waterbody_type: L/W` rules). `lnk_rules_build()` emits it from the new thresholds columns.
- **Rule shape matters for gradient.** A `thresholds: false` rule carrying `near_river` has no gradient test unless it also carries `gradient:`. So either emit one stream rule over edge types 1000/1100/2000/2300/1050/1150 (it inherits gradient and size), or keep the 1050/1150 carve-out and add `gradient:` to it.
- **Validator:** `frs_habitat_classify()` writes `<to>_near_river` and keeps it; `.lnk_hv_stage_exprs()` must pass `near_river_table = paste0(<to>, "_near_river")`, and `lnk_preflight_fresh()`'s formal check should learn the argument. A rule matches only rows walked at its own exact `(discharge_min, distance_max)`. `.lnk_hv_mad_missing()` assumes a mad species with no MAD range qualifies nowhere; with `near_river` it can.
- **Discharge source:** the walk reads `mad_m3s` on the working table. On fwapg's discharge BULK's river-polygon rows have none (0 of 1,118), so the Bulkley is never found; wet's pick covers them.
- **Limits:** the walk sees one group's table; side channels with no local code (most 1100/1150) never get a distance, so they pass only on their own size. Coffin Creek's wetland segments measure 4.6 to 12.3 km from a 3 m³/s river on BULK, so they fail at 1 km as intended.
- **Cost:** about 16 s per (discharge, distance) pair per group at 1 km on BULK (32,472 segments).

---

*Parked 2026-10-21 after the plan gate, revised the same day after a design discussion and two reviews: the near-river rule becomes an inherited threshold in fresh, with the measure of "a river" chosen per stage (fresh#262), the scope of the test and the wetland door are each a dimension, and the variants harness learns to vary structure. The sections below are the approved plan. Resume with `/planning-init 364`.*

## Context at the gate (established 2026-10-21 from the code; a resuming session verifies, not re-derives)

- **fresh 0.41.0 (tag `v0.41.0`) shipped `near_river` as a rule key.** `frs_habitat_classify()`'s signature is unchanged: when any spawn/rear rule carries `near_river: {discharge_min, distance_max}` it runs `frs_near_river()` once per distinct pair into `<to>_near_river` — in link, `<working>.streams_habitat_near_river` — keeps it (CREATE IF NOT EXISTS + DELETE the group's rows; built only when a rule asks), and passes it to `frs_habitat_predicates(near_river_table =)`, a new formal. The key is refused on `waterbody_type: L/W`; `R` and plain edge rules take it. A rule compiles to `edge AND gradient AND (size OR EXISTS)`; the EXISTS touches only `s.id_segment` / `s.watershed_group_code`. The walk reads `mad_m3s` (link joins it on every group's working streams, `cw` included, `lnk_pipeline_prepare.R:755-762`), sees one group's table, never walks a row with a NULL local code, and writes a row only where a river is within `distance_max`, so an empty table per group is a legitimate result. fresh never compiles `channel_width_min_bypass`; link applies it after classify through `frs_order_child()`.
- **fresh#262 (open, 2026-10-21) makes the measure a choice**: discharge, channel width or stream order. fwapg has discharge on none of BULK's 1,118 river-polygon rows and width on all of them, so under width a `cw` group finds its rivers with no fill.
- **fresh has two layers and the rule belongs in the numeric one.** Structure (`rules.yaml`) is built by `lnk_rules_build()` from `dimensions.csv`; numbers come from `parameters_habitat_thresholds.csv` at classify, inherited by every rule without `thresholds: false`, overridable per rule. Thin bundles, the variants harness and the run log work on the numeric layer only. `frs_habitat_predicates()` builds the per-stage `csv_thresholds` itself (`R/frs_habitat_predicates.R:184-187, 209-211`) and `.frs_near_river_specs()` (`:284`) reads rule keys only; `ranges` is typed numeric length-2 by `frs_classify()` and `frs_habitat_species()`, so the pair lives in a sibling slot `params[[sp]]$near_river$<stage>`. `waterbody_type: R` rules inherit thresholds (`R/utils.R:267-270`) and so would inherit the pair. The fresh issue below carries all of it.
- **The free pass is one rule.** `lnk_rules_build()` (`R/lnk_rules_build.R:395-451`) emits, for every `rear_wetland = yes` species, a 1050/1150 carve-out with `thresholds: false`; in `default` it is W-typed with `wetland_ha_min: 1.0` (the #311 floor, which also drops the ~40 lines with no `waterbody_key`) and sits after the W polygon rule; unfloored it is untyped and sits before. In categories mode the carve-out is `edge_types: [wetland]` = 1700 shorelines, while `stream` already covers 1050/1150 (`frs_edge_types()`). `default` sets `rear_wetland = yes` for BT, CH, CO, ST, WCT, CT, DV, RB, all with `rear_stream_in_waterbody = yes`, polygon yes, floor 1, connection 10 000 m; every species in both bundles has `river_skip_cw_min = yes`, so the R rule carries `channel_width: [0, 9999]`. The thresholds CSV reaches `rules.yaml` only through `rear_lake_ha_min` (`:346,462`).
- **bcfishpass bundle: CH is right, CO is not.** CH has `rear_wetland = no`. CO's carve-out has no `gradient:`, but bcfishpass's `load_habitat_linear_co.sql` (main, read 2026-10-21) applies `s.gradient <= t.rear_gradient_max` to every rearing row and bypasses only the size test for 1050/1150.
- **link gaps:**
  1. The validator: `.lnk_hv_stage_exprs()` (`R/lnk_habitat_validate.R:1020-1062`) calls `frs_habitat_predicates()` twice with no `near_river_table`; it scores the **persist** schema (`.lnk_hv_predicates()`, `:1070-1129`); `.lnk_hv_check_schema()` (`:365-385`) checks `streams`, `streams_access`, `streams_habitat_<sp>` only and refuses a schema with no `streams_access` rows. Existence of a near-river table cannot tell "walked at this pair" from "walked at another": a schema walked at one pair and scored under another reads `(size OR FALSE)` silently; the `discharge_fill` log check (`:466-477`) is the precedent. `.lnk_hv_mad_missing()` needs no change. A small segment far from any river labels `fails_width`, never "no river near".
  2. `lnk_preflight_fresh()`'s formals check (`R/lnk_preflight_fresh.R:126-129`) knows `frs_habitat_predicates = "model"` only; `test-lnk_preflight_fresh.R:49-65` hard-codes the vector. 0.41.0 and the inheriting release export the same formals and `frs_params()` ignores unknown CSV columns, so only the `Imports:` floor tells them apart.
  3. **The discharge fill never applies on `cw` groups.** `.lnk_discharge_read_each()` → `.lnk_rules_read_mad()` (`R/lnk_discharge.R:305-368`) recognises a rule-level `mad:` only; every caller passes `cfg` without per-group presence (prepare `:128`, log `lnk_log.R:1028`, validator `:467,481,507`, harness `:457,672`). With a pair resolved by fresh, link must ask fresh's resolver, not re-derive it.
  4. **Nothing drops a stale working near-river table.** `lnk_pipeline_prepare.R:738-739` drops `streams`/`streams_habitat`, `lnk_pipeline_run.R:181-183` adds `streams_breaks`.
  5. **Bundle files carry byte + shape checksums** (`default/config.yaml:120-143`, `bcfishpass/config.yaml:110-133`, `default_tuned/config.yaml:56-57`, the frozen bundles too); `audit_configs.R:61-73` flags drift and exits 1. `data-raw/regen_provenance.R` rebuilds `bcfishpass` and `default` only and hard-codes `setwd(<home path>)`. Inherited provenance keeps the parent's directory (`R/lnk_config.R:220-223`), so a child without its own `rules.yaml` / `dimensions.csv` entries verifies the parent's copies.
  6. **`.lnk_hv_check_log()` (`:466-477`) stops when a schema's logged `discharge_fill` differs from what cfg applies.**
  7. **The harness varies thresholds cells only** (`data-raw/habitat_variants_build.R`): a non-base row with no `column` must be a `mad` model step (`:211-223`); `set` admits only `*_mad_(min|max)` cells (`:196-207`); a ladder is one chain with no branch below the base; the score's anchor is a cw→mad step only (`habitat_variants_score.R:858-879`); `built.csv` records thresholds and method shas only (`build:445-461`); a variant `extends:` the base and inherits its `rules.yaml` and `dimensions.csv`. It copies `streams_access` from the base (`copy_access()`, `:623-646`).
- **Logging and dictionaries are data-driven.** Log columns come from `dictionary_parameters_habitat_thresholds.csv` (`R/lnk_log.R:471-476`); `test-dictionaries.R` asserts each dictionary equals the **union** of bundle columns and `owner` ∈ {fresh, link}. `config_hash` covers `cfg$rules` and `cfg$dimensions`. `audit_configs.R` §2 rebuilds every bundle's rules (thin `default_tuned` from its own thresholds). `build_rules.R` passes each bundle's own thresholds. `dictionary_dimensions.csv:13` says `rear_wetland_polygon` defaults to `no` when absent, in two fields; the code treats absent as `yes` (`:413`). `lnk_scenario_export` reads six fixed threshold columns (`:143-145`) and publishes `mad_m3s` through `.lnk_discharge_sql(fill = logged)`.
- **The issue's measurement is not in link.** The 10,197 / 2,338 km table and the use curve come from the private evidence work (#346). The "flow ≥ 0.75 m³/s" half of the tuned rule is CH's MAD floor, which belongs to #346; every `default` group is on `cw`, where "big enough on its own" is `rear_channel_width_min` (CH 1.5 m). `data-raw/query_width_mad_equivalent.R` maps width bins to median MAD and runs the other way.

## Decisions

Settled 2026-10-21 at the plan gate (operator + agent), revised the same day after a design discussion and two reviews. A resuming session treats these as given.

1. **The near-river rule is a threshold, inherited by fresh, with its measure.** `parameters_habitat_thresholds.csv` gains, per stage, `<stage>_river_measure` (`discharge` / `channel_width` / `stream_order` / `model`; absent = `model`, width under `cw` and discharge under `mad`, as the size test), `<stage>_river_discharge_min`, `<stage>_river_channel_width_min`, `<stage>_river_stream_order_min` and `<stage>_river_distance_max`; owner `fresh`. fresh (the issue below, on fresh#262) carries them as `params[[sp]]$near_river$<stage>`, inherits them on every rule that inherits thresholds **and has a size part** (a rule with none would be tightened, not relaxed), lets a rule override with its own mapping or opt out with `near_river: false`, and collects the walk's pairs from each rule's effective pair through the same resolver. `lnk_rules_build()` writes **no numbers**: only opt-outs. A thin bundle carries its own values; the harness ladders measure, Q and D as it ladders MAD; the run log records what applied. Not chosen: baking the pair into `rules.yaml` (a number in the structural layer, where nothing can vary or score it); discharge-only with `discharge_fill: true` on `default` (blind in the nine Skeena groups with no fwapg discharge; the operator chose the measure-agnostic design, 2026-10-21).
2. **Two dimensions, both per species, rear only:**
   - `rear_wetland_flow`, how FWA edge types 1050 / 1150 (flow through a wetland) rear: `stream` (the species' gradient and size thresholds, and so the inherited pair), `gradient` (slope test only, no size test, no pair — bcfishpass's coho rule), or `free` (no test; what every bundle does today). Absent means `free`. "None" is already `rear_wetland = no`. The carve-out is emitted as `edge_types_explicit: [1050, 1150]` in both edge modes (as the W polygon rule already is), because the `wetland` category is 1700 shorelines.
   - `rear_near_river`, which rear rules take the pair: `both` (the stream-edge rule and the 1050/1150 rule), `stream`, `wetland_flow`; absent means `both`. The builder stamps `near_river: false` on the inheriting rules outside the scope, and **always on the river-polygon rule** (spawn and rear): a river polygon is the river, and `(cw BETWEEN 0 AND 9999 OR EXISTS)` would otherwise admit NULL-width river lines near a bigger river. The spawn stream rule always takes a spawn pair, so there is no spawn scope column. A dead combination stops the build: `wetland_flow` with `rear_wetland_flow ≠ stream` or `rear_wetland = no`; `stream` with `rear_stream = no` (`rear_all_edges` counts as `stream`). The stamp goes only on rules that inherit: never on a `waterbody_type: L/W` rule (fresh refuses it), and not on a `thresholds: false` rule (a no-op).
   The issue's own measurement (wetland lines only) and the published CH rule (every small stream) are then two rows of one table, scored against each other.
3. **Rule shape:** two rules, not one six-edge rule. The main stream rule keeps its edge set and `in_waterbody`; under `stream` the 1050/1150 rule drops `thresholds: false`, its W type and the #311 floor, so it inherits gradient, size and the pair exactly as the stream rule does. The wetland floor (`rear_wetland_ha_min`) stays on the W polygon rule only; the km the floor alone removed from flow lines is measured (Phase 4), not assumed. Under `gradient` the carve-out keeps `thresholds: false` and gains `gradient: [0, rear_gradient_max]` from the bundle's thresholds row (error if NA).
4. **Discharge and width for the walk.** `default` stays on fwapg with `discharge_fill` as it is: under `model` its `cw` groups find rivers by channel width, which fwapg carries on every river-polygon row, so no fill is needed and the Skeena groups are covered; the Coffin Creek example is testable on `default`. `.lnk_rules_read_mad()` becomes `.lnk_discharge_read_rules()` and answers through fresh's own scope-aware resolver (`.frs_near_river_specs()` via `getFromNamespace`, listed in `.lnk_fresh_required_internal()`): true when any effective pair of a species in `cfg$species` measures by discharge, or a rule carries `mad:`; a `near_river: false` never counts. Bundle-level, as today (every caller passes `cfg` only); the cost of a needless fill where the species is absent is nil, no flag moves. Where a `cw` group measures by width the fill is irrelevant to the walk; the export's `mad_m3s` / `*_ratio_mad` columns follow the logged fill, noted in RUNBOOK §6d.
5. **The near-river table is persisted and the effective pairs are logged.** `<schema>.streams_near_river` carries fresh's columns as #262 writes them (the measure, its threshold, `distance_max`, `dist_m`, keyed with `id_segment`, `watershed_group_code`), created by `lnk_persist_init()` for every schema, in `.lnk_validate_persist_table`'s list. `lnk_pipeline_classify()` drops `<working>.streams_habitat_near_river` before `frs_habitat_classify()`; `lnk_pipeline_persist()` always deletes the WSG and inserts only when the working table exists. `<schema>.log` gains a `near_river` text column beside `discharge_fill` holding the effective pairs per WSG (from the resolver); `.lnk_hv_check_log()` compares it with what cfg resolves, as it does `discharge_fill`, and the existence check stays for pre-#364 schemas. The validator passes the persisted table as `near_river_table` to both predicate calls. Not chosen: the validator re-walking.
6. **Values:** `default` sets `rear_wetland_flow = stream` for every `rear_wetland = yes` species and `rear_near_river = both`; CH rear gets `rear_river_measure = model`, `rear_river_distance_max = 1000`, `rear_river_discharge_min = 3`, and `rear_river_channel_width_min` at the width whose median MAD is 3 m³/s (from `query_width_mad_equivalent.R`'s bins, run the other way, floored as #307 floored), confirmed or moved by Phase 4's ladder under #302's rule; every other cell, CO included, stays NA until #346 tunes it. CH's own flow floor (0.75 m³/s) is #346's `rear_mad_min`, not this issue's; on `cw` the door is width ≥ 1.5 m or the river. `bcfishpass` sets CO to `gradient` (CH unchanged). `default` changes only in the last phase, after the comparison. Schemas built before (the 241-group `fresh_default`) carry no `near_river` log column and cannot be validated under the new `default` until re-modelled; that is the next provincial run, not this issue.
7. **The harness learns structure and the pair.** `habitat_variants_build.R` / `_score.R` gain: a `dims` row class (`k=v;k=v` like `set`, on `cw`, from the base, no `column` / `value` / `flag` / `obs_stage`, scored for capture, cost and `habitat_change.csv`, kept out of ladders as model-only is) that writes its own `dimensions.csv` and a `rules.yaml` rebuilt by `lnk_rules_build()`, with both named in its `config.yaml` and its own provenance entries that `write_bundle()`'s verify loop reads; `set` widened to `*_river_*` cells; `built.csv` and the score's on-disk check gain `rules_sha256` / `dimensions_sha256` with the NA backfill pattern; a pair anchor (a step whose base cell is NA, taken by construction like the model anchor); the equals-base guard compares dims. A ladder stays one chain, so Q × D is two chains, tightest first (Q with D fixed in `set`; D with Q fixed), walked with `--floor=expected`. The base row cannot set `discharge_fill`; each variant row does.
8. **Out of scope, measured anyway:** the W polygon rule still admits 1000 / 1100 mainlines inside wetland polygons into `rearing` with no size test (`rear_wetland_area_only = no`, #310's call). Phase 4 reports the km that rule alone admits; `area_only` is a separate operator decision. Whether a lake's flow line counts as "a river" under each measure is fresh#262's biology question, for the operator. #316 stays open. **The rule table** — one row per (species, stage, rule) replacing the column-per-scenario `dimensions.csv` and the hand-wired builder — is the right end state and its own issue, drafted for review at the end of this one, not folded in. The export does not carry the pair (a consumer contract change; noted in RUNBOOK §6d).

## Plan

### Phase 0 — fresh: the measure and the inheritance (sibling repo, branch + PR, never its main)
- [ ] NewGraphEnvironment/fresh#263 (filed 2026-10-21): `/planning-init fresh#263` there, sequenced with fresh#262 (one PR or two; link pins the release carrying both).
- [ ] #262: the size key is one of `discharge_min` / `channel_width_min` / `stream_order_min`; the walk reads the named column; `<to>_near_river` records measure and threshold; the predicate matches both; the live check gains width and order references.
- [ ] Inheritance: `frs_params()` reads the five columns per stage (`_measure` in `char_fields`), stops on a half pair (incl. `Inf`), warns on an unknown `*_river_*` column, stores `params[[sp]]$near_river$<stage>`; `.frs_rule_near_river()` resolves explicit → `false` → inherited-with-a-size-part, used by `.frs_rule_to_sql()` and `.frs_near_river_specs()`; `frs_habitat_predicates()` passes the pair in `csv_thresholds_<stage>` under both models; the loader's coercion is guarded by `is.list()`; `.frs_validate_near_river()` takes `false` (refused on L/W), refuses `true`; `frs_habitat_classify()` filters `species` by `params_fresh` before the specs.
- [ ] Tests: the list in the issue (inherit by each measure and `model`; override; opt-out; no-op on `thresholds: false`; refusals; byte identity on NA columns; specs = effective pairs; no size part → no pair; the R rule's form; half pairs; yaml round trip).
- [ ] NEWS, docs, PR, release tag.

### Phase 1 — link pins it
- [ ] Install the released fresh; `DESCRIPTION`: `Imports: fresh (>= <that version>)` **and** `Remotes: NewGraphEnvironment/fresh@v<that version>` (the floor is the only gate between 0.41.0 and the inheriting release).
- [ ] One commit: `.lnk_fresh_required_formals()` gains `frs_habitat_predicates = c("model", "near_river_table")`, `.lnk_fresh_required_internal()` gains `.frs_near_river_specs`, their comments, and `test-lnk_preflight_fresh.R`'s expected vectors.
- [ ] Suite green before any other change (baseline).

### Phase 2 — rules: dimensions, parameters, builder, bundles
- [ ] `dictionary_dimensions.csv`: rows for `rear_wetland_flow`, `rear_near_river`; correct `rear_wetland_polygon`'s `default_when_absent` and description to `yes` (code `:413`).
- [ ] `dictionary_parameters_habitat_thresholds.csv`: the ten `*_river_*` rows (owner `fresh`, `consumed_by` fresh's `frs_params()`).
- [ ] Columns: the ten thresholds columns (NA) in `default`, `default_tuned` and `bcfishpass`; the two dimension columns in `default` (`free` / `both` for now) and `bcfishpass` (CO `gradient`). Frozen bundles untouched.
- [ ] `lnk_rules_build()`: read the two columns (absent → defaults; unknown → stop; dead combinations → stop); emit per Decisions 2–3 with one `add_nr()` helper applied only at the stream / all-edges / R / `stream`-mode carve-out sites; the carve-out explicit in both edge modes; the builder reads no `*_river_*` threshold. Roxygen.
- [ ] Tests in `test-lnk_rules_build.R`, in explicit mode: `stream` emits an inheriting 1050/1150 rule, never W-typed, floor only on the polygon rule; `gradient` emits explicit gradient from the row; each scope value stamps `false` on exactly the rules outside it and always on R; no L/W rule ever carries the key; dead combinations and unknown values stop; absent columns reproduce today's YAML byte for byte; built rules load through `fresh::frs_params()`.
- [ ] `Rscript data-raw/build_rules.R`; diff: `bcfishpass/rules.yaml` changes only CO's carve-out and the `false` stamps on R; `default/rules.yaml` gains only the R stamps and the date. `regen_provenance.R`: derive the repo root from its own location and cover `default_tuned`; run it. `audit_configs.R` exits 0; `test-dictionaries.R` green. Update `.lnk_hv_stage_min()`'s comment on rule-level gradient.

### Phase 3 — the walk's inputs, the persisted table, the log, the validator
- [ ] `.lnk_rules_read_mad()` → `.lnk_discharge_read_rules()` through fresh's resolver (Decision 4); rename the call sites and `test-lnk_discharge.R`; test a pair by discharge, a pair by width (does not read discharge), an opt-out everywhere (does not), a rule-level `mad:` (does).
- [ ] `lnk_pipeline_classify()` drops `<schema>.streams_habitat_near_river` before classify. `lnk_persist_init()`: `cols_streams_near_river` + table + index + `.lnk_validate_persist_table`; `lnk_pipeline_persist()`: delete per WSG, insert when the working table exists. Statement-count tests move 8 → 9 and 7 → 8 (`test-lnk_pipeline_persist.R:74,235`); `test-lnk_persist_init.R:119-147` mocks are name-exact and safe. `schema_consolidate.R` discovers by `watershed_group_code`; `study_area_verify.sql` enumerates `streams_habitat_<sp>` only (both read 2026-10-21; re-check at resume).
- [ ] `<schema>.log.near_river` (text, the effective pairs per WSG from the resolver) written by `lnk_log` beside `discharge_fill`; `.lnk_hv_check_log()` compares; `.lnk_hv_stage_exprs(…, near_river_table = NULL)` threaded from `.lnk_hv_predicates()` to both `frs_habitat_predicates()` calls; `.lnk_hv_check_schema()` checks `streams_near_river` exists when the bundle resolves a pair, with a "rebuild with link ≥ <version>" message; roxygen says a far segment labels `fails_width`; test that `.lnk_hv_relax()` leaves a compiled EXISTS alone.
- [ ] Verify: on ADMS, force `.lnk_discharge_join(fill = TRUE)` on the working streams and classify with the no-pair `default` — the habitat digest equals the unfilled one (the fill is invisible to `cw` rules); a test bundle with CH `stream` + `model` / width-equivalent / 1000 runs end to end on one group, persists `streams_near_river`, logs the pair, and `lnk_habitat_validate()` scores it with 0 `post_predicate` disagreements.

### Phase 4 — the harness learns structure; the CH / CO comparison, before `default` moves
- [ ] `habitat_variants_build.R` / `_score.R` per Decision 7. Test on one group: a `dims`-only variant with no change equals the base digest; `rear_wetland_flow=stream` does not; a pair-anchor step is taken by construction; `built.csv` refuses a rules/dimensions change.
- [ ] `data-raw/habitat_score/variants_364.csv`, base `default`: `free` (today); `stream` with no pair; `stream` + CH `model` / W / 1000 scope `both`; the same scope `wetland_flow`; the same scope `stream`; width chain tightest first with D fixed; D chain with W fixed; one `discharge` measure variant with `discharge_fill=TRUE` on the row (the issue's own measurement, 3 m³/s); `stream_order` once #262 says what order. CO on the door only (no pair). Held-out groups per `wsg_roles_364.csv`, `--floor=expected`. Groups: ADMS, BULK (no fwapg discharge: where the measures part) and three more CH- and CO-present groups across the Fraser, Thompson and coast, chosen by presence and width coverage, named in the README.
- [ ] `data-raw/logs/wetland_door_364/summarise.R`: per species and group, rearing km on 1050/1150 per variant (kept by size, kept by river only, dropped); km the #311 floor alone removed under `free`; km moved on 1000/1100/2000/2300 by the pair (scope `both` − `wetland_flow`); km the W polygon rule alone admits (Decision 8); share of river-polygon rows with a value under each measure. `habitat_variants_score.R` gives capture and cost for CH and CO per variant.
- [ ] bcfishpass side: on ADMS and BULK, `lnk_compare_rollup()` for CO under the `bcfishpass` bundle, "before" from a temp bundle carrying main's `rules.yaml` and "after" from the branch's.
- [ ] README with every table; `research/habitat_thresholds.md` gains "Through-wetland lines and the near-river test (#364)" with the `**Verified:** · **Issues:** · **Produced by:**` header; the issue body gets the numbers (edited, not appended).

### Phase 5 — `default` takes the stream door; docs; PR
- [ ] `default/dimensions.csv`: `rear_wetland_flow = stream` for BT, CH, CO, ST, WCT, CT, DV, RB, `rear_near_river = both`; `default/parameters_habitat_thresholds.csv` and `default_tuned`'s: CH's `rear_river_*` cells per Decision 6, at the ladder's pick. Rebuild rules, regen provenance, `audit_configs.R` exits 0. A test that `frs_params()` on `default`'s CSV yields `near_river$rear` for CH.
- [ ] RUNBOOK §7: the rule table row for the wetland flow rule, the near-river columns beside gradient/width/MAD (inherited, overridable, `near_river: false`, the measure), the scope dimension, the R rule's standing opt-out; §6d the export; the persisted table and the log column where §6 lists them.
- [ ] NEWS entry; CLAUDE.md status block, including that schemas built before this (`fresh_default`) are not validatable under `default` until re-modelled; `research/habitat_thresholds.md` verdict line; `data-raw/README.md` and `data-raw/habitat_score/README.md` rows.
- [ ] Draft the rule-table issue (Decision 8) for review; `/code-check branch`; `/planning-archive`; `/gh-pr-push`.

## Owed at the end (reported, done after merge)

- [ ] Cyphers re-prepped for the new fresh pin before the next dispatch (`lnk_preflight_fresh()` hard-fails on the formal; `update_hosts.sh` installs fresh from main, which is safe before Phase 1 because link's CSVs then carry no `*_river_*` column).
- [ ] The next provincial `default` run re-models every group (the validator's `near_river` log check otherwise refuses `fresh_default`).
- [ ] bcfishpass parity record (`research/bcfishpass_parity.md`) re-scored at the next release: CO moves on the gradient fix.
- [ ] Operator decisions with Phase 4's numbers: the W polygon rule's `area_only` (Decision 8); lake flow lines as "a river" (fresh#262).
- [ ] The rule-table issue filed after body review (Decision 8).
- [ ] #346: CO's pair, and CH's `rear_mad_min` 0.75 in `default_tuned`.

## Validation

- [ ] Tests pass (`devtools::test()` on the new fresh), `lintr`, `devtools::document()`, `pkgdown::check_pkgdown()`.
- [ ] `/code-check` clean (once over the branch)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification is per phase above: Phase 0 by fresh's suite and the byte-identity test; Phase 1 by the suite; Phase 2 by the byte diffs of the regenerated and frozen `rules.yaml` files and the audit's exit status; Phase 3 by the digest equality, the one-group end-to-end run and the validator; Phase 4 by the committed log directory and the harness's digest and `built.csv` checks; Phase 5 by the audit and a `lnk_rollup_wsg()` on one scratch group matching Phase 4's chosen variant.



## Errors Encountered

| Error | Resolution |
|-------|------------|
