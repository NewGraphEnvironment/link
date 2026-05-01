# Changelog

## link 0.20.1

Closes [\#92](https://github.com/NewGraphEnvironment/link/pull/93).
Per-AOI observations filter mirrors bcfp’s `wsg_species_presence` +
`observation_key` exclusions.

- New `.lnk_pipeline_prep_observations()` builds `<schema>.observations`
  per AOI, mirroring bcfp’s `model/01_access/sql/load_observations.sql`.
  Filters `bcfishobs.observations` by the WSG’s species set (only
  species marked present count) and applies QA exclusions (`data_error`
  / `release_exclude` rows removed, keyed on `observation_key` — was
  `fish_observation_point_id`, never present in the CSV; the empty
  intersect silently dropped all 1,182 exclusions).
- Downstream consumers updated: `prep_overrides` reads
  `<schema>.observations` (no longer takes `observations` param);
  `lnk_pipeline_break_obs` simplified to a thin reader;
  `lnk_barrier_overrides` uses `observation_key`.
- TWAC pre-flight: BT spawning/rearing/rearing_stream collapsed from
  +21–30% over-credit to 0.0% across the board. 15-WSG `tar_make`:
  HARR + LFRA BT tightened toward parity (LFRA BT rearing_stream -3.75%
  → -0.93%; HARR BT rearing_stream -4.19% → -1.29%); other 13 WSGs
  unchanged. HORS BT stays -7.68% (fresh#158 stream-order bypass —
  distinct mechanism).
- Default bundle also tightens (6 rows on HARR/LFRA BT) — methodology
  correctness improvement, not a regression.

## link 0.20.0

Closes [\#88](https://github.com/NewGraphEnvironment/link/pull/89).
Subsurfaceflow folded into the natural-barrier set so per-species
observation/habitat upstream lift fires on it.

- `.lnk_pipeline_prep_natural()` now builds the full bcfishpass
  natural-barrier union (gradient + falls + opt-in subsurfaceflow).
  Subsurfaceflow positions land in `<schema>.natural_barriers`, which
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  consumes — so per-species observation/habitat upstream lift applies to
  subsurfaceflow exactly as it does to falls and gradient.
- `.lnk_pipeline_prep_subsurfaceflow()` deleted; its body absorbed into
  `prep_natural`. Six prep helpers → five.
- Default-bundle off-switch unchanged: omit `subsurfaceflow` from
  `cfg$pipeline$break_order` and the entire code path skips. Verified
  bit-identical default rollup (0 of 581 rows changed).
- bcfishpass-bundle parity: HARR CH/CO/ST rearing_stream gaps closed
  from -14.8/-13.3/-11.6% to within ±0.32%. LFRA CH/CO/ST closed to
  within ±0.6%. HARR blkey 356286055 BT credits 6.509 km (was 0).
- Reproducibility: two consecutive 15-WSG `tar_make` runs produced
  byte-identical rollup (`digest::digest(link_value)` matches across
  runs).
- HORS rearing_stream gap (~7% on BT/CH/CO) is unchanged by this fix —
  separate mechanism, follow-up.

## link 0.19.0

Closes [\#82](https://github.com/NewGraphEnvironment/link/pull/82).
Subsurface-flow access barriers + parity claim retraction.

**Subsurface-flow as opt-in access barrier**. Closes the largest single
gap surfaced when expanding the bcfishpass-config rollup from 5 to 10
watershed groups: NATR BT spawning +15.2% → +1.5%, NATR BT rearing
+13.0% → -0.6% (10-WSG `tar_make` log:
`data-raw/logs/20260429_02_tar_make_subsurf.txt`).

- New `.lnk_pipeline_prep_subsurfaceflow()` materialises
  `<schema>.barriers_subsurfaceflow` from
  `whse_basemapping.fwa_stream_networks_sp` filtered to
  `edge_type IN (1410, 1425)`. Honours `user_barriers_definite_control`.
  Mirrors bcfishpass `model/01_access/sql/barriers_subsurfaceflow.sql`
  exactly.
- New `subsurfaceflow` entry in `lnk_pipeline_break.R` `source_tables`
  map; conditional UNION ALL in `lnk_pipeline_classify_build_breaks` so
  the new break source emits `'blocked'` into `fresh.streams_breaks`
  when the config opts in.
- Inclusion is gated on `cfg$pipeline$break_order` containing
  `'subsurfaceflow'` at every site (prepare, break, classify). Configs
  control the toggle, not code.
- `inst/extdata/configs/bcfishpass/config.yaml` opts in (parity with
  bcfishpass). `inst/extdata/configs/default/config.yaml` does not opt
  in (NewGraph methodology decision pending).
- [`?lnk_pipeline_break`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  gains a `## Break sources` table covering every valid `break_order`
  entry — source table, role, classify-phase label. Both bundled
  `config.yaml` files carry an inline comment listing the available
  entries with one-line semantics so future-readers see the toggle
  without leaving the config file.

**Parity claim retraction**. Earlier framing (“all species within 5%”,
“exact reproduction”) held only on a small set of pre-selected WSGs. The
10-WSG rollup surfaced systematic gaps. Vignette pulled, README and
DESCRIPTION reframed as experimental.

- `vignettes/habitat-bcfishpass.Rmd` removed; bundled vignette data in
  `inst/extdata/vignette-data/` removed.
- `README.md` rewritten as one-liner (“Experimental package — breaking
  all the time and loving the learning curve”) plus install + license.
- `DESCRIPTION` Title and Description reframed; `bookdown`, `knitr`,
  `mapgl`, `rmarkdown` dropped from Suggests; `VignetteBuilder` removed.
- `data-raw/_targets.R` extended to 10 WSGs (PARS, MORR, KISP, KOTL,
  NATR added).
- `research/bcfishpass_comparison.md` retraction at top with the
  diagnosis tables and the natural-vs-anthropogenic two-tier
  classification reference; historical content preserved below.
- `CLAUDE.md` Status block flags remaining gaps.

**Remaining departures** (per `research/bcfishpass_comparison.md`): 7 of
210 spawning/rearing/rearing_stream rows \>5%, six of seven
`link < bcfishpass`. Concentrated on MORR ST (cluster connectivity),
MORR SK and KISP SK (new geographies for the existing fresh#147 SK
lake-proximity logic). Tracked separately; not in this release.

## link 0.18.1

Closes [\#78](https://github.com/NewGraphEnvironment/link/issues/78).
Adds attribution for redistributed upstream data and refreshes the
package Title + Description to reflect the package’s current scope.

- `LICENSE-bcfishpass` at root — verbatim copy of upstream
  `smnorris/bcfishpass` LICENSE governing the redistributed override
  CSVs
- `NOTICE.md` at root — source/license table, names redistributed files
- `inst/extdata/configs/{bcfishpass,default}/overrides/README.md` —
  pointer files reachable via
  [`system.file()`](https://rdrr.io/r/base/system.file.html)
- `README.md` “Acknowledgements” section above License
- `Authors@R` — Simon Norris added as `[ctb]`
- `Title` —
  `Habitat and Connectivity Interpretation for Stream Networks` (was the
  v0.6-era `Crossing Connectivity Interpretation`)
- `Description` — refactored to mirror the README’s “fresh answers what
  the habitat is, link answers what the features mean for the network”
  framing; names the three habitat axes (intrinsic potential,
  accessibility under connectivity, per-feature rollups)

CITATION file and mirror to NewGraphEnvironment/crate (which also ships
bcfishpass fixtures via crt_ingest examples) deferred — to be filed as
their own work.

## link 0.18.0

Closes [\#65](https://github.com/NewGraphEnvironment/link/issues/65).
Decompose the config bundle into a manifest layer and a data-ingest
layer, and route registered files through
[crate](https://github.com/NewGraphEnvironment/crate) for
source-agnostic canonicalization.

**[`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
is now manifest-only.** It reads `config.yaml` and returns paths, file
declarations, pipeline knobs, and provenance — no parsed CSVs. Cheap to
call.
[`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
and
[`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
no longer pay for CSV parsing they don’t need.

**New: `lnk_load_overrides(cfg)`** materializes the data files declared
in `cfg$files` and returns a named list of canonical-shape tibbles.
Entries with `source` + `canonical_schema` declarations dispatch through
[`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html)
(currently `bcfp/user_habitat_classification`); others fall through to
local reads dispatched on path extension. New source families plug in by
config edit alone — no link R code change.

**New `config.yaml` schema.** Top-level `rules:` and `dimensions:` paths
replace `files.rules_yaml` / `files.dimensions_csv` (format follows from
the path’s extension, not the key name). The previous `files:` and
`overrides:` maps merge into one flat `files:` map keyed by filename
stem (e.g. `user_barriers_definite`,
`pscis_modelledcrossings_streams_xref`). Each entry carries `path:` and
optionally `source:` and `canonical_schema:`. Configs may declare
`extends:` to inherit from another config; child entries override
same-key parent entries.

**Pipeline phase signatures gain `loaded`.** Every `lnk_pipeline_*`
phase that reads a data table now takes `cfg` and `loaded` together.
Callers (the bundled targets pipeline, project scripts) call
`lnk_load_overrides(cfg)` once and thread the result through phases.
`cfg$overrides$X` and `cfg$habitat_classification` access points become
`loaded$X`. See `data-raw/_targets.R` and
`data-raw/compare_bcfishpass_wsg.R` for the pattern.

**Verification.** `tar_make()` on 5 WSGs × 2 configs reproduces the
v0.17.0 baseline rollup bit-identically (sha256
`a82de9928809b9751213e08916c476b4ee3f99286bc9ea2dc53f9659eeb92097`).
Refactor introduces no behaviour change.

**Migration**

| Old | New |
|----|----|
| `cfg$rules_yaml` | `cfg$rules` |
| `cfg$dimensions_csv` | `cfg$dimensions` |
| `cfg$parameters_fresh` (data frame) | `loaded$parameters_fresh` |
| `cfg$habitat_classification` | `loaded$user_habitat_classification` |
| `cfg$observation_exclusions` | `loaded$observation_exclusions` |
| `cfg$wsg_species` | `loaded$wsg_species_presence` |
| `cfg$overrides$X` | `loaded$X` (e.g. `loaded$user_barriers_definite`) |

**Out of scope (follow-up issues):**

- crate schemas for the other 9 bcfp-sourced files (one issue per file
  as canonical-shape decisions concretize). Today they fall through to
  plain CSV read.
- `nge` / `local` source families (when project-experimental configs
  need them).
- Type-aware variant matching in crate (planned crate v0.1.x roadmap).

## link 0.17.0

Ship the
`Modelling spawning and rearing habitat using bcfishpass defaults`
vignette
([`vignettes/habitat-bcfishpass.Rmd`](https://github.com/NewGraphEnvironment/link/blob/main/vignettes/habitat-bcfishpass.Rmd))
on top of the post-phase-3 codebase. Regenerated bundled artifacts
(`inst/extdata/vignette-data/{rollup, sub_ch, sub_ch_bcfp}.rds`) reflect
the corrected emit semantics and tighter parity.

**bcfishpass-bundle parity (5 WSGs × 5 species, spawn + rear):**

- 42 of 42 non-NA rows within ±5%
- 35 of 42 within ±2%
- median 1.1%; max 5.0%

Tighter than v0.13.1’s 100% within ±5% / median 1.5% claim because phase
1’s emit-semantics fix landed in main, and the regenerated rollup
reflects it. Spawning rows that previously sat at +3-5% (BT/CH/CO/ST
across multiple WSGs) are now at +0-2%.

The vignette text claim updated to match the new numbers. Cuts the
v0.13.1 vignette’s residual-deltas paragraph that mentioned
overlay-range-containment and stream-order-bypass — those were
pre-phase-3 artifacts; with rule emission corrected, residual deltas are
mostly segmentation-boundary rounding plus the documented stream-order
bypass.

## link 0.16.0

Phase 3 of [\#69](https://github.com/NewGraphEnvironment/link/issues/69)
— proof artifact + emit-semantics fix.

**Proof artifact:** new `research/rule_flexibility.md` runs BABL × CO
under three configs (use case 1, use case 2, bcfishpass) by swapping
only `dimensions.csv` cells, with `rules.yaml` diffs side-by-side.
Reproducible via `data-raw/rule_flexibility_demo.R` +
`data-raw/rule_flexibility_render.R`. Demonstrates that every
methodology dial is a CSV cell, no buried emission rules. The numbers
prove the matrix:

- Use case 1 (default bundle): rearing 1388.90 km, lake_rearing 54507.85
  ha, wetland_rearing 5786.74 ha. Counts polygon-mainlines as linear AND
  rolls up polygon area.
- Use case 2: rearing 1271.02 km, same area rollups. Excludes
  polygon-mainlines from linear via `in_waterbody: false` +
  `area_only: true` on L/W; areas still bucket via the polygon rules.
- bcfishpass bundle: rearing 1271.02 km, no area rollup (no L/W polygon
  rules at all). Functionally identical rear predicate to use case 2
  because `area_only: true` makes the L/W rules contribute to bucket
  flags only.

**Emit-semantics fix in
[`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)**
(under [\#69](https://github.com/NewGraphEnvironment/link/issues/69)
phase 1 banner — corrects a bug introduced in 0.14.0):

Previous behaviour: `rear_stream_in_waterbody: yes` emitted
`in_waterbody: true` on the stream rule. fresh interprets that as “match
segments inside polygons ONLY,” the opposite of the column’s intent
(“include polygon-mainlines too”). The default bundle’s permissive rear
was effectively only matching in-polygon segments — broken since 0.14.0
but never visible because the bcfishpass bundle (which set `no` for all
species) was the only side tested for parity.

Corrected emit:

- `yes` (or absent): omit the `in_waterbody` field. Rule matches
  segments inside AND outside polygons (today’s permissive default —
  polygon-mainlines count too).
- `no`: emit `in_waterbody: false`. Rule matches outside polygons only
  (strict partition).

The third grammar state (`in_waterbody: true` = inside polygons only)
has no biological use case for stream rules and is no longer emitted by
[`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md).

**bcfishpass bundle output unchanged:** the bundle ships
`rear_stream_in_waterbody: no` for all species, so the fixed emit
produces byte-identical rules.yaml to 0.15.0. Default bundle output
changes (now actually permissive — pass-through stream rule).

Tests updated (3 cases): `yes` (or absent) omits the field; `no` emits
`in_waterbody: false`; default bundle smoke tests assert the rear stream
rule has no `in_waterbody` field.

## link 0.15.0

Phase 2 of
[\#69](https://github.com/NewGraphEnvironment/link/issues/69). Adds
dimensions-driven `area_only` emission + polygon-rule mainlines edge
filter. Default bundle now ships use case 1 (linear includes mainlines
through L/W polygons; area rolls up via bucket flags) with the new edge
filter restricting polygon-rule contributions to mainlines only
(1000/1100). bcfishpass bundle output unchanged.

**New per-species columns** in `dimensions.csv`:

- `rear_lake_area_only` — yes/no — emit `area_only: true` on the L
  polygon rule. When `yes`, fresh derives the `lake_rearing` bucket flag
  from the rule but excludes it from the main `rear` predicate (linear).
  When `no` or absent, the rule contributes to both (today’s behaviour).
  Both bundles ship `no` for all species — default ships use case 1;
  bcfishpass ships parity-with-bcfp.
- `rear_wetland_area_only` — yes/no — same shape on the W polygon rule.
  Both bundles ship `no` for all species.

**Polygon-rule edge filter** (`edge_types_explicit: [1000, 1100]` on L/W
rules in the additive rear branch):

- Restricts the L/W polygon rule’s match to mainlines (single-line main
  flow + secondary flow) when emitted under `rear_lake: yes` or
  `rear_wetland: yes` + `rear_wetland_polygon: yes`. Without the filter,
  polygon rules matched every segment in the polygon (shorelines 1700,
  banks 1800, island edges, construction lines), all crediting linear
  `rearing`. The bucket pred (`lake_rearing` / `wetland_rearing`) is
  unaffected — area still rolls up the polygon’s full area as long as
  any tagged segment exists in it.
- The `rear_lake_only` branch (SK / KO) is intentionally **not**
  filtered — the L rule there IS the rear classification, must continue
  matching the whole lake polygon.

**Default bundle methodology shift** — use case 1: linear km includes
mainlines through wetlands and lakes, with area rollups
(`lake_rearing_ha`, `wetland_rearing_ha`) populating from the polygon
footprint. `rear_wetland_polygon` flipped from `no` (v0.14.0) back to
`yes` for rear_wetland=yes species. The 2026-04-27 cut to `no` was the
right call given the v0.14.0 grammar (no edge filter; W rule would
over-emit), but with the mainlines edge filter shipped here,
polygon-mainlines are the right thing to count for linear AND area.

**Required:** fresh ≥ 0.24.0
([\#182](https://github.com/NewGraphEnvironment/fresh/issues/182),
[fresh#184](https://github.com/NewGraphEnvironment/fresh/pull/184)) —
`area_only` predicate decouples bucket-flag derivation from the main
rear predicate.

**Tests** — `test-lnk_rules_build.R` 130 PASS (was 124 in 0.14.0): 6 new
tests covering area_only emission per the columns + polygon-edge-types
filter present on L/W rules (additive branch only) + rear_lake_only
branch left untouched. Full suite 554 PASS / 0 FAIL.

**BABL parity (bcfishpass bundle):** unchanged from 0.14.0 — 8 of 10
rows within ±2%, 10 of 10 within ±5%. The new knobs are inert when set
to today’s defaults, so bcfp bundle output is byte-identical to v0.14.0.

**Coordinates with** [\#69 phase
3](https://github.com/NewGraphEnvironment/link/issues/69) —
`research/rule_flexibility.md` proof artifact runs BABL × CO under three
configs (use case 1, use case 2, bcfishpass) by swapping only
`dimensions.csv` cells, with `rules.yaml` diffs side-by-side.

## link 0.14.0

Dimensions-driven `in_waterbody` + bcfishpass-bundle methodology fixes
that bring 5-species BABL parity to ±5% (8 of 10 rows within ±2%) on the
bcfishpass bundle. The methodology dials are now visible in
`dimensions.csv` cells per species — no buried emission rules.

**New per-species columns** ([\#69 phase
1](https://github.com/NewGraphEnvironment/link/issues/69)):

- `spawn_stream_in_waterbody` — yes/no — emit `in_waterbody: <bool>` on
  the stream-spawn rule. `no` excludes polygon-mainlines from spawn
  classification (the partition that pairs with `waterbody_type: R/L/W`
  polygon rules); `yes` is permissive and matches polygon-mainlines too.
  Both bundles ship with `no` for all species (biology — spawning
  happens in stream channels).
- `rear_stream_in_waterbody` — yes/no — same shape on the stream-rear
  rule. bcfishpass bundle ships `no` (strict partition matches
  bcfishpass’s per-species access SQL); default bundle ships `yes`
  (NewGraph permissive — counts polygon-mainlines as `rearing` for
  species with `rear_lake: yes` etc., orthogonal to area rollups).
- `rear_wetland_polygon` — yes/no — gate emission of the
  `waterbody_type: W` polygon rule. When `no`, only the 1050/1150
  wetland-flow carve-out emits; when `yes` (or absent), the W polygon
  rule emits too (sets the `wetland_rearing` flag for area rollups).
  Both bundles ship `no` for all species — segments inside an FWA
  wetland polygon are wider than the fish-bearing channel and shouldn’t
  count as rearing habitat.

**Methodology fixes carried in from earlier branch work** (previously
held in `vignette-ship`):

- **`apply_habitat_overlay: false` flag in `pipeline:` block of
  bcfishpass `config.yaml`.** Comparison-scope choice, not a behavioural
  claim about bcfishpass. bcfishpass ships both layers:
  `habitat_linear_<sp>` (per-species rule output) and
  `streams_habitat_linear` (rule + known-habitat overlay blended). The
  bcfishpass bundle disables `frs_habitat_overlay()` so its output is
  rule-only and compares apples-to-apples against bcfishpass’s own rule
  layer (`habitat_linear_<sp>`). Comparing the rule slices in isolation
  keeps rule-emission drift from hiding behind known-habitat overlay
  drift; overlay parity is a separate question to revisit once rule
  parity is locked. Default bundle keeps overlay enabled (NewGraph
  methodology produces the blended output by default).
- **[`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  habitat-confirmation SQL** updated for bcfishpass’s authoritative CSV
  shape (post-2026-04-26: `species_code` + `spawning` + `rearing`
  integer columns instead of the dropped `habitat_ind` column).
- **[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)**
  empty-table fallback `CREATE TABLE` matches the new CSV shape.

**Required:** fresh ≥ 0.23.1
([\#180](https://github.com/NewGraphEnvironment/fresh/issues/180),
[fresh#181](https://github.com/NewGraphEnvironment/fresh/pull/181),
[fresh#183](https://github.com/NewGraphEnvironment/fresh/pull/183)) —
adds the `in_waterbody` predicate to the rule grammar plus the validator
hotfix.

**Tests** — `test-lnk_rules_build.R` 124 PASS (was 86): 6 new tests for
`in_waterbody` emission across permutations + bundle-level smoke tests;
4 new tests for `rear_wetland_polygon` (yes/no/absent backward-compat).
Full suite 516 PASS / 0 FAIL.

**BABL parity (bcfishpass bundle):** 8 of 10 spawning+rearing rows
within ±2%; max 5.0%; max spawning drift 1.5% (was 4.8%). The remaining
±2-5% drift is a follow-up — phase 2 will add the `area_only` predicate
([fresh#182](https://github.com/NewGraphEnvironment/fresh/issues/182))
and `edge_types_explicit: [1000, 1100]` filter on polygon rules to
support the use case 2 pattern (mainlines excluded from linear, area
still rolls up).

**Coordinates with** [\#69 phase
2](https://github.com/NewGraphEnvironment/link/issues/69) — adds
`rear_lake_area_only` / `rear_wetland_area_only` columns once fresh#182
lands. Phase 3 ships the proof artifact (`research/rule_flexibility.md`)
running BABL × CO under three configs (use case 1, use case 2,
bcfishpass) by swapping only `dimensions.csv` cells.

## link 0.13.0

Shape fingerprint + halt auto-merge on shape drift
([\#64](https://github.com/NewGraphEnvironment/link/issues/64)).

`data-raw/sync_bcfishpass_csvs.R` and the daily
`sync-bcfishpass-csvs.yml` cron previously compared each
bcfishpass-sourced CSV against a recorded sha256 byte checksum and
auto-merged any drift. That worked for value drift (rows added/edited)
but was blind to shape drift — bcfishpass’s 2026-04-26 long→wide reshape
(with column type change) passed straight through and broke link’s
pipeline downstream. This release adds a separate **shape fingerprint**
alongside the byte checksum; the workflow auto-merges byte-only drift as
before but halts shape drift for coordinated review.

- New `shape_checksum` field in the `provenance:` block of each bundle’s
  `config.yaml`. Computed as sha256 of the file’s first line
  (whitespace-normalized). Catches column rename / add / remove /
  reshape — the dominant failure mode. Type changes within stable
  columns are out of scope (rarer; can extend later if needed).
- `data-raw/sync_bcfishpass_csvs.R` computes shape fingerprint at sync
  time, classifies each file’s drift as `byte` or `shape`, writes the
  overall drift kind to `/tmp/sync_drift_kind` for the workflow to
  consume.
- `.github/workflows/sync-bcfishpass-csvs.yml` reads the drift kind.
  Byte-only drift → auto-PR + auto-merge as today. Shape drift → auto-PR
  opens with `schema-drift` label, NOT auto-merged, workflow exits
  non-zero (red on Actions tab) so the change is visible. Coordinated
  review across link / fresh / crate is required before merging.
- [`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
  extended with `shape_drift` column. **Breaking** (pre-1.0): old single
  `drift` column renamed to `byte_drift`; existing tibble shape now
  `(file, byte_expected, byte_observed, byte_drift, shape_expected, shape_observed, shape_drift, missing)`.
- [`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
  markdown rendering surfaces both byte and shape drift counts in the
  provenance summary.
- 15 new tests (468 total, was 453) — `.lnk_shape_fingerprint()`
  helper + shape-drift detection + missing-file handling +
  backward-compat path for bundles without `shape_checksum:` field.

Coordinates with crate’s adapter pattern (link#65, crate#2) — when shape
drift fires, crate’s normalize handler is the right place to absorb the
upstream change before link’s pipeline sees it.

## link 0.12.0

Pick up `fresh 0.22.0` overlay simplification — caller-side update for
the canonical-shape contract.

- [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  now calls `frs_habitat_overlay()` with
  `species_col = "species_code"` +
  `habitat_types = c("spawning", "rearing")` instead of
  `format = "long"` + `long_value_col = "habitat_ind"`. Matches the
  shape bcfishpass’s `user_habitat_classification.csv` adopted on
  2026-04-26 (row-per-(segment × species), per-habitat indicator
  columns). Three-line caller-side diff; no link API change.
- `Suggests: fresh (>= 0.22.0)`. Coordinates with
  [fresh#177](https://github.com/NewGraphEnvironment/fresh/issues/177).
- Pipeline runs again. The vignette stays in `dev/` until link#64 (sync
  workflow shape fingerprint) and link#65
  ([`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md)
  via
  [`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html))
  land.

## link 0.11.2

bcfishpass vignette pulled out of pkgdown until tighter.

- `vignettes/reproducing-bcfishpass.Rmd` →
  `dev/habitat-bcfishpass.Rmd.draft`. Same pattern as scoring-crossings
  — out of build path, preserved for resumption when content lands
  clean.
- Content updates applied before move: title now “Modelling spawning and
  rearing habitat using bcfishpass defaults”; new scope paragraph
  describing what bcfishpass covers beyond linear classification;
  entrypoint replaced with explicit `lnk_pipeline_*` calls (was
  `tar_make()`); map section clarifies linear classification covers
  spawning/rearing/lake_rearing/wetland_rearing per species.
- `README.md`: “Full pipeline (reproducing bcfishpass)” → “Full pipeline
  (linear habitat classification)”; broken pkgdown vignette link
  removed.
- Open follow-ups: rollup-query retarget to `streams_habitat_linear` for
  apples-to-apples post-overlay comparison; range-containment relaxation
  in
  [`fresh::frs_habitat_overlay`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.html).

## link 0.11.1

Vignette cleanup.

- `vignettes/scoring-crossings.Rmd` moved to
  `dev/scoring-crossings.Rmd.draft` — out of build path until the
  scoring methodology lands.
- `vignettes/reproducing-bcfishpass.Rmd` updated for the v0.9.0 overlay:
  added overlay step to the pipeline DAG, new “Known-habitat overlay”
  subsection, clarified rollup vs. map comparison.
- `data-raw/vignette_reproducing_bcfishpass.R`: bcfishpass-side map
  query reads `streams_habitat_linear` (model + known) instead of
  `habitat_linear_ch` (model-only) for apples-to-apples comparison with
  link’s post-overlay output.
- Regenerated bundled snapshots
  (`inst/extdata/vignette-data/{rollup,sub_ch,sub_ch_bcfp}.rds`) from
  v0.10.0 + overlay state.

## link 0.11.0

Config-bundle provenance + run stamps — closes the drift attribution
loop. Pipeline outputs that shift between runs on the same DB state can
now be traced back to which input changed. Closes
[\#40](https://github.com/NewGraphEnvironment/link/issues/40);
supersedes the narrower scope of
[\#24](https://github.com/NewGraphEnvironment/link/issues/24).

- `inst/extdata/configs/{bcfishpass,default}/config.yaml` carry
  `provenance:` blocks with sha256 checksums for every tracked file.
  Externally sourced files (bcfishpass overrides) record `source` URL +
  `upstream_sha` (`ea3c5d8`, synced 2026-04-13) + `path` within source
  repo. Generated files (`rules.yaml`) record `generated_from` +
  `generated_by` + `generator_sha`. Hand-authored files record link’s
  git sha at edit time.
- [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  exposes parsed provenance as `cfg$provenance` (named list, one entry
  per tracked file). `print(cfg)` shows the count of tracked files.
- New `lnk_config_verify(cfg, strict)` recomputes sha256 for every
  provenanced file and returns a tibble
  `(file, expected, observed, drift, missing)`. Default warns on drift;
  `strict = TRUE` errors. `digest` added to Suggests.
- New `lnk_stamp(cfg, conn, aoi, db_snapshot)` returns an `lnk_stamp` S3
  list capturing the full set of inputs at run time: cfg provenance with
  current observed checksums, software versions and git SHAs (link,
  fresh, R), DB snapshot row counts (`bcfishobs.observations`,
  `whse_basemapping.fwa_stream_networks_sp`) when conn is provided,
  AOI + start_time. `lnk_stamp_finish(stamp, result, end_time)`
  finalizes; `format(stamp, "markdown")` renders for report appendix or
  run-log dump.
- `data-raw/compare_bcfishpass_wsg.R` now emits a stamp markdown at the
  head of every WSG run, captured into `data-raw/logs/*.txt` via the
  standard stderr redirect.
- Tests: 93 new — provenance parsing, drift detection (clean / mutated /
  missing / strict), bundled-config drift = 0 invariants, stamp shape +
  markdown rendering + finalization + db-snapshot opt-out.

## link 0.10.0

Default config bundle now uses explicit FWA `edge_type` codes for spawn
and rear-stream predicates, matching bcfishpass’s 20-year-validated
convention.

- `data-raw/build_rules.R`: switched both default rule-builder calls
  (`inst/extdata/parameters_habitat_rules.yaml` and
  `inst/extdata/configs/default/rules.yaml`) from
  `edge_types = "categories"` to `edge_types = "explicit"`. Predicates
  now emit `edge_types_explicit: [1000, 1100, 2000, 2300]` in place of
  `edge_types: [stream, canal]` (which expanded to
  `1000/1050/1100/1150` + `2000/2100/2300`).
- Drops `1050/1150` (stream-thru-wetland) and `2100` (rare double-line
  canal) from spawn AND rear-stream rules. The dedicated wetland-rearing
  rule (`edge_types_explicit: [1050, 1150]` with `thresholds: false`) is
  unchanged — `wetland_rearing` flag still captures stream-thru-wetland
  segments for species with `rear_wetland = yes`. Net `rearing` flag (=
  `rear_stream OR wetland_rearing OR rear_lake`) is preserved for those
  species; species with `rear_wetland = no` (GR, KO) lose `1050/1150`
  from both spawn AND rearing.
- ADMS preflight (M1, fresh 0.21.0): default-bundle spawning km drops
  4-7% across all spawning species (BT 397→368, CH 296→279, CO 340→318,
  SK 98→94, RB 331→311). Rearing km essentially unchanged for
  `rear_wetland = yes` species. Full per-WSG numbers in
  `research/default_vs_bcfishpass.md`.
- Default and bcfishpass bundles now emit structurally aligned spawn
  predicates — confirms bcfishpass’s edge-type convention is what link
  ships by default.
- `tests/testthat/test-lnk_rules_build.R`: regression tests added —
  default rules.yaml has no `1050/1150/2100` in spawn or rear-stream
  predicates; the dedicated wetland-rear rule still carries
  `[1050, 1150]`.

## link 0.9.0

[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
now overlays known habitat from `user_habitat_classification.csv` onto
`fresh.streams_habitat` after rule-based classification. Closes
[\#55](https://github.com/NewGraphEnvironment/link/issues/55).

- After `frs_habitat_classify()` finishes, calls `frs_habitat_overlay()`
  (fresh ≥ 0.21.0) when the manifest declares `habitat_classification`.
  Loaded long-format table is overlaid via a 3-way bridge join through
  `fresh.streams` (range containment on `[drm, urm]`).
- Closes the gap surfaced in research doc §5/§7: bcfishpass’s published
  `streams_habitat_linear.spawning_sk > 0` blends model +
  observation-curated knowns; link’s pipeline previously only emitted
  the model side.
- 5-WSG rerun (digest `0f00c713`) shows BABL SK spawning under
  bcfishpass bundle rises from 57.6 → 85.2 km (+27.6 km from overlay).
  ADMS SK +5.14 km, BULK SK +0.8 km. Default bundle similar magnitudes.
- Requires fresh ≥ 0.21.0 (overlay rename + bridge support; see
  fresh#175).

## link 0.8.0

Default NewGraph habitat-classification config bundle ships alongside
the bcfishpass reproduction bundle
([\#51](https://github.com/NewGraphEnvironment/link/issues/51)).

- New `inst/extdata/configs/default/` bundle — intentional
  methodological departures from bcfishpass: intermittent streams
  included in rearing, wetland rearing added for resident species, lake
  rearing extended to species beyond SK/KO with per-species
  `rear_lake_ha_min` thresholds, `river_skip_cw_min = yes`. Loadable via
  `link::lnk_config("default")`.
- Per-species `rear_lake_ha_min` via a new column in
  `configs/default/dimensions.csv`.
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  prefers that value over the shared
  `fresh::parameters_habitat_thresholds` default when present, keeping
  bcfishpass bundle at its 200 ha threshold for SK/KO while letting
  default express species-specific biology (CO 2 ha, BT/WCT/RB/CT/DV 10
  ha, GR 40 ha, ST 60 ha, CH 100 ha, SK/KO 200 ha). Non-numeric entries
  in the dimensions CSV fall through to the fresh fallback rather than
  silently disabling it.
- Per-species `rear_wetland_ha_min` via a new column in
  `configs/default/dimensions.csv`.
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  now emits both `edge_types: wetland` (for rearing km) AND
  `waterbody_type: W` (drives `wetland_rearing_ha` rollup) rules when
  `rear_wetland = yes`. Thresholds: CO 0.5 ha (beaver complexes),
  BT/CH/CT/DV/RB/ST/WCT 1 ha.
- SK + KO spawn_connected block — added five columns to
  `configs/default/dimensions.csv` (`rear_stream_order_bypass`,
  `spawn_connected_direction`, `spawn_connected_gradient_max`,
  `spawn_connected_cw_min`, `spawn_connected_edge_types`) so
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  emits the `spawn_connected:` block with `direction: downstream` for
  lake-obligate species. `spawn_lake = no` for SK/KO to prevent
  lake-centerline inflation (Babine Lake alone is 177 km).
- `data-raw/compare_bcfishpass_wsg()` emits a compound rollup with 7
  rows per species × WSG × config: `spawning`/`rearing` km,
  `lake_rearing`/`wetland_rearing` ha, plus three edge-type slice rows
  (`rearing_stream`, `rearing_lake_centerline`,
  `rearing_wetland_centerline`) for decomposing the rearing total.
  Reference side uses the same `habitat_linear_<sp>` +
  `fwa_{lakes,wetlands}_poly` methodology as link, so both sides are
  apples-to-apples.
- `data-raw/_targets.R` runs both bundles side-by-side across all 5
  validation WSGs (ADMS, BULK, BABL, ELKR, DEAD) — 10 comparison
  targets, unified rollup with a `config` identity column. Rollup digest
  `e3eaf5f62df44d6713bfed32cd08fc5d` (357 rows) on M1 with fresh 0.17.1.
- New research doc `research/default_vs_bcfishpass.md` — methodology
  comparison, per-WSG per-species results, 9 observations covering the
  debugging journey (SK spawning over-inflation root causes, bcfishpass
  known-habitat overlay via `streams_habitat_known`, gradient-floor
  calibration, segment-averaging risk).
- Three companion maps (`data-raw/maps/sk_spawning_BABL*.R`) — mapgl
  overlays of SK spawning BABL comparing bundle-vs-bundle and
  default-vs-bcfishpass-published (model + known); per-layer toggle,
  popups with `id_segment` / `segmented_stream_id` / plain-language
  edge_type / gradient / length.
- Requires `fresh >= 0.17.1` for `waterbody_type: L/W` rear-rule
  honouring + `lake_ha_min` / `wetland_ha_min` thresholds.
- `tests/testthat/test-lnk_rules_build.R` — new suite with 56 tests
  covering lake + wetland rule emission (per-config ha_min, fresh
  fallback, rear_lake=no / rear_wetland=no), spawn rules (stream+canal
  vs explicit codes, spawn_lake, spawn_requires_connected,
  spawn_connected block), rear precedence (no_fw, lake_only, all_edges),
  river polygon + river_skip_cw_min, species skipping,
  rear_stream_order_bypass, non-numeric ha_min fallthrough.

## link 0.7.0

`user_barriers_definite` no longer eligible for observation-based
override
([\#48](https://github.com/NewGraphEnvironment/link/issues/48)).

- `.lnk_pipeline_prep_natural()` previously unioned `barriers_definite`
  into `natural_barriers`, which
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  iterates over. Net effect: the 227 reviewer-added user-definite
  positions (EXCLUSION zones, MISC detections the model misses) could be
  re-opened by observations clearing the species threshold. Confirmed
  active on ELKR pre-fix — 4 override rows at Erickson Creek exclusion
  and Spillway MISC positions that bcfishpass keeps as permanent
  barriers.
- bcfishpass’s `model_access_*.sql` builds the barriers CTE from
  gradient + falls + subsurfaceflow only and appends
  `barriers_user_definite` post-filter via `UNION ALL`. Observations and
  habitat filters never see user-definite rows, so they’re never
  overridable. link now matches this shape: `natural_barriers` is
  gradient + falls only; `barriers_definite` stays consumed separately
  as a break source in
  [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  and as a direct `UNION ALL` entry into `fresh.streams_breaks` via
  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md).
- ELKR rollup shifts toward bcfishpass: BT spawning +3.4% → +2.8%, WCT
  spawning +4.0% → +2.6%, WCT rearing +1.6% → +0.3%. Other four WSGs
  unchanged (ADMS/BABL/DEAD have empty `barriers_definite`; BULK has 87
  rows but no observation-threshold matches to any of them).

## link 0.6.0

Honour `user_barriers_definite_control.csv` at the observation-override
step.

- [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  now excludes observations upstream of control-flagged positions from
  counting toward the override threshold, matching bcfishpass’s access
  SQL. Previously controlled positions (concrete dams, long impassable
  falls, diversions) could be re-opened by upstream historical
  observations
  ([\#44](https://github.com/NewGraphEnvironment/link/issues/44)).
- Gated per-species by a new `observation_control_apply` column in
  `parameters_fresh.csv` — TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT;
  NA for CT/DV/RB. Residents routinely inhabit reaches upstream of
  anadromous-blocking falls (post-glacial headwater connectivity, no
  ocean-return requirement), so their observations still override.
  Matches bcfishpass’s per-model application.
- Habitat-confirmation override path intentionally bypasses the control
  table — expert-confirmed habitat is higher-trust than observations,
  and bcfishpass’s `hab_upstr` CTE has no control join either.
- `.lnk_pipeline_prep_overrides` now passes the control table to
  [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  when the config manifest declares `barriers_definite_control`.
  Manifest key is the contract; no DB probe.
- `.lnk_pipeline_prep_load_aux` now always creates a schema-valid
  (possibly empty) `barriers_definite_control` table when the manifest
  declares the key — fixes an asymmetric gating bug that would have
  raised “relation does not exist” on AOIs with zero control rows.
- End-to-end validation WSG: DEAD (Deadman River) added to
  `data-raw/_targets.R`. It has a single `barrier_ind = TRUE` control
  row at FALLS (356361749, 45743) with six anadromous observations
  upstream and zero habitat coverage — the unique combination that
  actively exercises the filter. All four prior WSGs
  (ADMS/BULK/BABL/ELKR) were rescued by either the observation threshold
  or habitat path, making them parity checks rather than filter tests.

## link 0.5.0

Documentation and narrative for the targets pipeline.

- New vignette: “Reproducing bcfishpass with link + fresh” — three-line
  entrypoint, rollup interpretation, BULK chinook habitat map (mapgl),
  reproducibility framing. Data-prep script at
  `data-raw/vignette_reproducing_bcfishpass.R` generates
  `inst/extdata/vignette-data/{rollup,bulk_ch}.rds` from a real run;
  vignette loads the `.rds` so pkgdown builds don’t need fwapg access.
  Follows the CLAUDE.md convention for vignettes that need external
  resources
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Research doc (`research/bcfishpass_comparison.md`) updated with
  bit-identical rollup numbers from 2026-04-22 and a new “Targets
  orchestration” section showing how `_targets.R` composes the per-WSG
  runs.
- `mapgl`, `sf` added to DESCRIPTION Suggests.
- Retired `data-raw/compare_bcfishpass.R` — `data-raw/_targets.R` +
  `data-raw/compare_bcfishpass_wsg.R` supersede it. Git history
  preserves the prior form.

## link 0.4.0

Targets-driven comparison pipeline for all four validated watershed
groups.

- Add `data-raw/_targets.R` —
  `tar_map(wsg = c("ADMS", "BULK", "BABL", "ELKR"))` over a per-AOI
  target function, synchronous execution,
  [`dplyr::bind_rows`](https://dplyr.tidyverse.org/reference/bind_rows.html)
  rollup. `fresh.streams` is a shared schema so single-host parallelism
  would collide — runs serially today; distributed runs (M4 + M1) are a
  follow-up alongside a fresh upstream change for per-AOI output paths
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add `data-raw/compare_bcfishpass_wsg(wsg, config)` — per-AOI target
  function. Wraps the six `lnk_pipeline_*` phases, diffs the output
  against `bcfishpass.habitat_linear_*` reference on the tunnel DB,
  returns a ~10-row tibble
  (`wsg × species × habitat_type × link_km × bcfishpass_km × diff_pct`).
  KB-scale — safe to ship over SSH.
- Promote `.lnk_pipeline_classify_species` to an exported
  `lnk_pipeline_species(cfg, aoi)` — canonical public API for “species
  this config classifies in this AOI.” Used by `lnk_pipeline_classify`
  and `lnk_pipeline_connect` internally and by the targets per-AOI
  function externally. Removes the duplicate private helper that was
  briefly inlined in `data-raw/`.
- End-to-end verification
  (`data-raw/logs/20260422_11_tar_make_final.txt`) — 4 WSGs / 34 rows
  produced over 8.5 minutes wall clock (serial). **Reproducibility:**
  consecutive `tar_make()` invocations on the same DB state produce
  bit-identical rollup tibbles. **Parity to bcfishpass
  (informational):** all 34 `diff_pct` values within 5% of reference;
  research-doc drift (BT rearing: -0.7 → -1.1 pp) traces to env state
  between 2026-04-15 and today, not to pipeline non-determinism.

## link 0.3.0

Pipeline phase helpers extract the bcfishpass comparison orchestration
into composable building blocks. The 635-line
`data-raw/compare_bcfishpass.R` is now 136 lines of sequenced helper
calls.

- Add
  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  — create the per-run working schema
  ([\#38](https://github.com/NewGraphEnvironment/link/issues/38))
- Add
  [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
  — load crossings and apply modelled-fix and PSCIS overrides
- Add
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  — load falls / definite / control / habitat CSVs, detect gradient
  barriers, compute per-species barrier skip list, reduce to minimal set
  via
  [`fresh::frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.html),
  load base segments
- Add
  [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  — sequential `frs_break_apply` over observations / gradient / definite
  / habitat / crossings in config-defined order
- Add
  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  — assemble access-gating breaks table and run
  [`fresh::frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.html)
- Add
  [`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
  — per-species rearing-spawning clustering and connected-waterbody
  rules
- Canonical signature `(conn, aoi, cfg, schema)` — `aoi` follows fresh
  convention (WSG code today; extends to ltree / sf polygons / mapsheets
  later), `schema` is the caller’s per-run namespace (`working_<aoi>` by
  convention) so parallel runs do not collide
- `cfg$species` parsed from the rules YAML at
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  load — intersects with `cfg$wsg_species` presence to pick per-AOI
  classify targets
- Requires fresh 0.14.0 (for `frs_barriers_minimal`)

## link 0.2.0

Config bundles for pipeline variants.

- Add `lnk_config(name_or_path)` — load a config bundle (rules YAML,
  dimensions CSV, parameters_fresh, overrides, pipeline knobs) as one
  list object. Bundles live at `inst/extdata/configs/<name>/` with a
  `config.yaml` manifest, or any directory containing `config.yaml` for
  custom variants
  ([\#37](https://github.com/NewGraphEnvironment/link/issues/37))
- Relocate bcfishpass config files into
  `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv,
  parameters_fresh.csv, overrides/). All R scripts and data-raw/
  references updated.

## link 0.0.0.9000

Initial release. Crossing connectivity interpretation layer — scores,
overrides, and prioritizes crossings for fish passage using configurable
severity thresholds and multi-source data integration.
