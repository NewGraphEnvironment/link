# link

Experimental package — breaking all the time and loving the learning
curve. Stream-network habitat-classification tooling layered over
`fresh`. Under active development; APIs and outputs change without
notice.

> **Read
> [`RUNBOOK.md`](https://newgraphenvironment.github.io/link/RUNBOOK.md)
> first.** It is the durable mental model of the barrier → access →
> mapping_code machinery (what feeds what, where each rule lives, the
> gotchas). This `CLAUDE.md` carries conventions + status; the RUNBOOK
> carries the *mechanics*. Don’t re-derive the system from source each
> session — read the runbook, and update it in-commit when the mechanics
> change.

## Repository Context

**Repository:** NewGraphEnvironment/link **Primary Language:** R
**Prefix:** `lnk_` **Branch:** `main` (v0.40.2 as of 2026-05-19)

## Status (2026-05-23) — ACTIVE HANDOFF

**Picking up this repo? Read
[`planning/active/HANDOFF.md`](https://newgraphenvironment.github.io/link/planning/active/HANDOFF.md)
first, then
[`RUNBOOK.md`](https://newgraphenvironment.github.io/link/RUNBOOK.md).**
Work on branch `196-streams-access-source-flags` is mid-stream and
handing off to M1. The mapping_code/access mechanism is solved and the
next fix (Phase 4d) is scoped — do not start over. v0.40.3 (persist
per-source flags) is ready to ship; the dam/access divergence is
characterized with a drafted fix + issue.

## Status (2026-05-19)

Tour-prep complete. Pipeline + comparison are decoupled (#168), the
orchestrator runs autonomously (#172), and the QGIS bcfp-shape symbology
path is tunnel-free (#187). M1 takes over cypher dispatch during the
user’s Europe trip.

Recent shipped work (v0.36 → v0.40):

- **v0.36.0** (#162) — `lnk_compare_wsg` + provincial parity annotated
  CSV (single-source-of-truth taxonomy). 5-host orchestrator.
  Methodology audited on ADMS/SETN/HORS/BULK/THOM (0 UNEXPLAINED at
  \|diff_pct\|≥2%).
- **v0.37.0** (#168) — Decoupled bcfp compare from link modelling
  pipeline. New
  [`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
  (modelling umbrella) +
  [`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md)
  (reference-agnostic comparison reader). PG-state resume gate via
  `link:::.lnk_wsg_persisted()` replaces brittle RDS-existence check.
  Species auto-discovered from PG.
- **v0.38.0** (#172) — Provincial-run autonomy + 8-script noun_verb
  rename. `wsgs_run_pipeline.sh` / `wsgs_dispatch.sh` /
  `wsgs_run_host.R` accept `--wsgs=`, `--config=`, `--schema=`,
  `--no-cyphers`, `--force`. Single-command provincial dispatch.
- **v0.38.1** (#178 Tier 1) — Single-cypher integration test for the
  autonomous wrapper. Validated cypher spin → prep → dispatch →
  consolidate → burn cycle. Row-level verification proved consolidate is
  byte-exact.
- **v0.39.0** (#180, \#185) — Additive multi-host runs + bucket-filtered
  COPY-streaming in `schema_consolidate.R`. `--reset-schema` opt-in;
  default is additive. Per-source `wgc_tables` enumeration (#185 fix to
  silent partial-copy bug when source’s table set is a subset of
  destination’s).
- **v0.39.1** (#182) — Fail loud on transient cypher prep failures.
  `data-raw/cypher_prep.sh` replace `set -e` with `set -euo pipefail`;
  wrap three `| tail -N` pipelines with tempfile + exit-check pattern.
  Sibling fix to rtj#163 covering cypher orchestration scripts.
- **v0.40.0** (#187) — Mapping_code tunnel decouple + portable
  [`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md)
  build + `<type>_<role>` rename sweep. Persist `streams_access` +
  `streams_mapping_code` + `streams_habitat_long_vw` view.
  `lnk_pipeline_run(mapping_code = TRUE)` builds tunnel-free; access
  semantics now use link’s own per-species barriers (via
  `blocks_species` predicate from \#152). BC: param rename
  `with_mapping_code` → `mapping_code`, `<role>_species` →
  `species_<role>`; CLI `--with-mapping-code` → `--mapping-code`.
  Deprecation shims for one release; removal v0.41.0.

Open follow-ups: \#189 (data-drive species residence from
`dimensions.csv` — sea-run cutthroat, Dolly Varden); \#175
(`lnk_compare_mapping_code` as own family member — unblocked by \#187);
\#176 (`lnk_compare_wsg` → `lnk_compare_run` rename); \#177 (persist
family reshape); \#183 (sibling-host parity hook).

## Architecture

    bcfishpass CSVs (overrides)  ─┐
    fresh CSV (crossings)        ─┤→ link (interpret, score) → break_source spec → fresh
    bcdata (PSCIS assessments)   ─┘

link is connectivity-system agnostic. Column names are configurable
parameters with BC/PSCIS defaults. The same functions work for any
jurisdiction’s crossing data.

## Data Sources (no DB required for core pipeline)

| Data | Source | How |
|----|----|----|
| Crossings (province-wide) | `fresh::system.file("extdata", "crossings.csv")` | 533k rows, all WSGs |
| Override CSVs | `bcfishpass/data/` directory | Filter by `watershed_group_code` |
| PSCIS assessments | `bcdata::bcdc_get_data("7ecfafa6-...")` | BC Data Catalogue API |
| Habitat thresholds | `fresh::system.file("extdata", "parameters_habitat_thresholds.csv")` | Species-specific |

### Override CSVs from bcfishpass

| File | Purpose | Key columns |
|----|----|----|
| `user_modelled_crossing_fixes.csv` | Imagery/field corrections (21k rows) | `modelled_crossing_id`, `structure`, `watershed_group_code` |
| `user_pscis_barrier_status.csv` | Expert barrier status overrides (1.3k rows) | `stream_crossing_id`, `user_barrier_status` |
| `pscis_modelledcrossings_streams_xref.csv` | GPS error corrections (3.6k rows) | `stream_crossing_id`, `modelled_crossing_id` |
| `user_barriers_definite.csv` | User-identified barriers (227 rows) | `blue_line_key`, `downstream_route_measure` |

## Database Connection

Uses `PG_*_SHARE` env vars (Docker fwapg, same as `frs_db_conn()`) with
fallback to standard `PG*` vars. DB is needed for match/score/habitat
functions that operate via SQL. The override loading and validation can
work with any PostgreSQL.

``` r

conn <- lnk_db_conn()  # reads PG_DB_SHARE, PG_HOST_SHARE, etc.
```

## bcfishpass tunnel rebuild cadence

The tunnel-side `bcfishpass.*` schema (used as the comparison reference
in `compare_bcfishpass_wsg.R`) **rebuilds weekly on Tuesdays around
19:00–23:00 PDT**, fired by `smnorris/db_newgraph`’s scheduled GHA
workflow. Query the cadence + version with:

``` sql
-- localhost:63333 / dbname=bcfishpass / user=newgraph
SELECT model_run_id, date_completed, model_version
FROM bcfishpass.log
ORDER BY model_run_id DESC LIMIT 5;
```

`model_version` format `<tag>-<commits>-g<short-sha>`
(e.g. `v0.7.14-113-ga7373af`) — the trailing SHA is the exact
`smnorris/bcfishpass` commit Simon’s rebuild used. That SHA is the
deterministic ref for matching link’s bundle CSVs to the tunnel’s input
state — required for apples-to-apples comparison.

CSV-sync workflow goal: bundle CSVs in
`inst/extdata/configs/bcfishpass/overrides/` should match the tunnel’s
last-rebuild SHA. Drift between the two means comparison numbers shift
for input reasons, not methodology reasons. See the [csv-sync rewrite
plan in
memory](https://newgraphenvironment.github.io/link/project_csv_sync_rewrite.md).

### Pin upstream versions in issue/PR bodies

When an issue or PR body describes upstream behaviour (bcfp SQL, fresh
primitives, fwapg, etc.) as the rationale or reference, **pin the
upstream version**. Use `<owner>/<repo>@<version-or-sha>` format:

- bcfp: the deterministic ref is `bcfishpass.log.model_version`
  (e.g. `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`). Cite
  `model_run_id` + date alongside for human readability.
- fresh / link / other NGE: tag refs (`fresh@v0.29.0`) or short SHAs
  (`fresh@f42e86a`).
- fwapg / db_newgraph: same — tag or short SHA.

Without a version pin, “this behaviour exists upstream” claims rot —
six-month-old issues end up describing code that no longer exists, and
no one knows what was being compared against. Version-pinning makes the
issue self-contained and reproducible.

Note: `<owner>/<repo>@<sha>` references a commit; this does **not**
trigger GitHub notifications to the referenced repo’s participants
(unlike `<owner>/<repo>#<n>` issue/PR references — see
`feedback_no_cross_ref_external_issues.md` in memory).

## Exported Functions (43)

### Core

- `lnk_thresholds(csv, high, moderate, low)` — configurable severity
  thresholds. Ships BC defaults. CSV or inline override. Feeds into
  [`lnk_score()`](https://newgraphenvironment.github.io/link/reference/lnk_score.md).
- [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
  — PostgreSQL connection factory. `PG_*_SHARE` then `PG*` env vars.
- `lnk_config(name_or_path)` — load a config **manifest**: paths
  (`cfg$rules`, `cfg$dimensions`), file declarations (`cfg$files`),
  pipeline knobs (`cfg$pipeline`), provenance metadata. **Manifest-only
  — no parsed CSVs.** Cheap to call. Configs may declare `extends:` to
  inherit from another config. Ships with `"bcfishpass"` and `"default"`
  variants under `inst/extdata/configs/<name>/`.
- `lnk_load_overrides(cfg)` — materialize the data files declared in
  `cfg$files`. Returns named list of canonical-shape tibbles. Entries
  with `source` + `canonical_schema` dispatch through
  [`crate::crt_ingest()`](https://newgraphenvironment.github.io/crate/reference/crt_ingest.html);
  others fall through to local reads dispatched on path extension.
  Adding a new source family is a config edit + crate registration — no
  link R code change.

### Override family: load → validate → apply

- `lnk_load(conn, csv, to)` — read correction CSVs into DB. Two-phase:
  validate all CSVs before writing any. Multi-file load. Provenance
  tracking.
- `lnk_override(conn, crossings, overrides)` — find orphans (IDs not in
  crossings) and duplicates. Non-blocking.

### Match family

- `lnk_match(conn, sources, distance)` — generic N-way matcher on
  `blue_line_key` + `downstream_route_measure`. Bidirectional 1:1 dedup
  (closest match wins both directions). Where filters isolated in
  subqueries. Optional `xref_csv` for hand-curated GPS corrections.

### Score family

- `lnk_score(conn, crossings, method)` — `method = "severity"` for
  biological impact classification (high/moderate/low).
  `method = "rank"` for weighted multi-criteria prioritization.
  Threshold-driven, NULL-safe, column-agnostic.

### Rules family

- `lnk_rules_build(csv, to, edge_types)` — transforms a species habitat
  dimensions CSV into the rules YAML format consumed by `frs_habitat()`.
  Two CSVs: newgraph defaults
  (`inst/extdata/parameters_habitat_dimensions.csv`) and bcfishpass
  comparison variant (`inst/extdata/configs/bcfishpass/dimensions.csv`).

### Barrier overrides

- `lnk_barrier_overrides(conn, barriers, observations, habitat, exclusions, control, params, to)`
  — processes fish observations and habitat confirmations into a barrier
  skip list for fresh. Counts observations upstream of each barrier via
  `fwa_upstream()` SQL, applies per-species thresholds, unions with
  habitat confirmations. Control table (`barriers_definite_control` with
  `barrier_ind = TRUE` rows) blocks override of flagged positions —
  gated per-species by `params$observation_control_apply` so residents
  (BT, WCT) can still override anadromous-blocking falls. Habitat path
  bypasses control entirely (expert-confirmed habitat is higher-trust
  than observations). Output:
  `(blue_line_key, downstream_route_measure, species_code)` table that
  fresh skips during access gating.

### Pipeline helpers

Six-phase bcfishpass-reproducing pipeline, driven by
[`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md) +
[`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
Every phase that reads a data table takes both `cfg` (manifest) and
`loaded` (the named list from
[`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md)).
Callers materialize once and thread `loaded` through. -
`lnk_pipeline_run(conn, aoi, cfg, loaded, schema, dams, cleanup_working, mapping_code)`
— modelling umbrella; chains all phases below plus `lnk_persist_init` +
`lnk_barriers_unify` + `lnk_pipeline_persist` into one per-WSG call.
Writes `<persist_schema>.streams`, `streams_habitat_<sp>`, `barriers`.
With `mapping_code = TRUE` additionally writes `streams_access` +
`streams_mapping_code` (tunnel-free; v0.40.0). This is the modelling
boundary — comparison is separate (`lnk_compare_rollup`,
`lnk_compare_wsg`). - `lnk_pipeline_setup(conn, schema, overwrite)` —
create per-run working schema. -
`lnk_pipeline_load(conn, aoi, cfg, loaded, schema)` — crossings +
modelled fixes + PSCIS status overrides. Reads
`loaded$user_modelled_crossing_fixes`,
`loaded$user_pscis_barrier_status`, `loaded$user_crossings_misc`. -
`lnk_pipeline_prepare(conn, aoi, cfg, loaded, schema)` — falls,
definite + control, habitat confirms, gradient barriers,
`natural_barriers`, barrier overrides, per-model minimal reduction, base
segments. Manifest-key gating via
`loaded$user_barriers_definite_control` and
`loaded$user_habitat_classification` (no DB probes). -
`lnk_pipeline_break(conn, aoi, cfg, loaded, schema)` — sequential
`frs_break_apply` in config-defined order: observations → gradient
minimal → **barriers_definite (separate break source)** → habitat
endpoints → crossings. -
`lnk_pipeline_classify(conn, aoi, cfg, loaded, schema)` — assembles
`fresh.streams_breaks` (gradient FULL + falls + **barriers_definite** +
crossings, WSG-filtered) and runs `frs_habitat_classify()`.
`barriers_definite` enters here directly because bcfishpass appends
user-definite post-filter (not via observation override). -
`lnk_pipeline_connect(conn, aoi, cfg, loaded, schema)` — per-species
cluster + connected_waterbody. -
`lnk_pipeline_species(cfg, loaded, aoi)` — canonical helper for “species
this config classifies in this AOI” (intersects `cfg$species` with
`loaded$wsg_species_presence` presence; falls back to
`loaded$parameters_fresh$species_code` when `cfg$species` is missing).

### Compare family

- `lnk_compare_rollup(conn, aoi, cfg, reference, conn_ref, species)` —
  reads `<persist_schema>` (no working schema) + reference DB, returns
  long-format diff tibble. Species auto-discovered from PG.
  Reference-agnostic via `reference` arg (`"bcfishpass"` only today).
  Use for compare-only re-runs against existing PG state.
- `lnk_compare_wsg(conn, aoi, cfg, loaded, reference, mapping_code, conn_ref, ...)`
  — bundled convenience wrapper that calls
  `lnk_pipeline_run() + lnk_compare_rollup()`. For `mapping_code = TRUE`
  delegates the build to `lnk_pipeline_run`’s mapping_code phase (writes
  to persist) and then runs the diff against the reference’s
  `streams_mapping_code`. Old `with_mapping_code` param accepted with
  deprecation warning until v0.41.0.
- `lnk_mapping_code(conn, table_access, table_habitat, table_streams, aoi, table_to, presence, species_resident, species_anadromous, species_spawn_only)`
  — portable schema-aware build wrapping
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md).
  Explicit `table_<role>` args (NGE convention) — works against working
  schema (mid-pipeline) or persist schema (ad-hoc rebuild). Tunnel-free.
  The QGIS bcfp-shape view consumer entry point (#187).
- `lnk_parity_annotate(rollup, taxonomy, to, tolerance)` — annotates a
  parity rollup against `research/bcfp_divergence_taxonomy.yml`. Tags
  each row with `taxonomy_id, class, mechanism, status, refs`. Unmatched
  rows: `UNEXPLAINED | WITHIN_TOLERANCE | NOT_APPLICABLE`.

### Bridge to fresh

- `lnk_source(conn, crossings, label_col, label_map)` — returns
  `list(table, label_col, label_map)` that plugs directly into
  `frs_habitat(break_sources = list(...))`. `label_map` translates link
  severity → fresh access labels (`high → blocked`,
  `moderate → potential`).
- `lnk_aggregate(conn, crossings, habitat, cols_sum)` — per-crossing
  upstream habitat rollup from fresh output. Sums spawning_km,
  rearing_km (or custom metrics).

## Integration with fresh

``` r

# link scores crossings
lnk_load(conn, csv = "overrides.csv", to = "working.fixes")
lnk_override(conn, "working.crossings", "working.fixes")
lnk_score(conn, "working.crossings")

# link produces break source spec
src <- lnk_source(conn, "working.crossings")

# fresh consumes it — zero translation
frs_habitat(conn, "MORR", break_sources = list(src))

# link reads fresh output for per-crossing rollup
lnk_aggregate(conn, "working.crossings", "fresh.streams_habitat")
```

The data flows both directions: link → fresh (scored crossings as break
sources) and fresh → link (habitat classification for upstream rollup).

## fresh Break Source Label Convention

When link produces a break source via
[`lnk_source()`](https://newgraphenvironment.github.io/link/reference/lnk_source.md),
the label values control how fresh treats each point:

| Label | What fresh does |
|----|----|
| `"blocked"` | Always blocks access (all species) |
| `"gradient_15"` | Blocks species with access threshold ≤ 15% (CO, CH, SK) but not BT (25%) |
| `"potential"` | Does NOT block by default. Only blocks if user passes `label_block = c("blocked", "potential")` |
| Anything else (`"passable"`, `"bridge"`, custom) | Never blocks |

### `label_block` parameter

`frs_habitat()` and `frs_habitat_classify()` accept `label_block`
(default `"blocked"`). This controls which break labels restrict access:

``` r

# link scores crossings with severity labels
src <- lnk_source(conn, "working.crossings",
  label_col = "severity",
  label_map = c("high" = "blocked", "moderate" = "potential"))

# Conservative: both high and moderate block
frs_habitat(conn, "BULK",
  break_sources = list(src),
  label_block = c("blocked", "potential"))

# Aggressive: only high blocks
frs_habitat(conn, "BULK",
  break_sources = list(src),
  label_block = "blocked")
```

### `gate` parameter

`gate = FALSE` skips accessibility entirely — classifies all segments by
gradient/channel width alone. Useful for total habitat potential before
considering barriers.
[`lnk_aggregate()`](https://newgraphenvironment.github.io/link/reference/lnk_aggregate.md)
can compare gated vs ungated to show how much habitat each crossing
blocks.

### Any AOI

`frs_habitat()` accepts any spatial extent — not just WSG codes:

``` r

frs_habitat(conn,
  aoi = "wscode_ltree <@ '100.190442'::ltree",
  species = c("BT", "CO"),
  label = "richfield",
  break_sources = list(src))
```

## Pipeline for any watershed group

The same steps replicate what bcfishpass does, for any
`watershed_group_code`:

1.  Load crossings from
    `fresh::system.file("extdata", "crossings.csv")`, filter to WSG
2.  Load overrides from `bcfishpass/data/` CSVs, filter to WSG
3.  [`lnk_load()`](https://newgraphenvironment.github.io/link/reference/lnk_load.md)
    →
    [`lnk_override()`](https://newgraphenvironment.github.io/link/reference/lnk_override.md)
    (validate + apply)
4.  Get PSCIS via
    [`bcdata::bcdc_get_data()`](https://bcgov.github.io/bcdata/reference/bcdc_get_data.html),
    match with
    [`lnk_match()`](https://newgraphenvironment.github.io/link/reference/lnk_match.md)
    (+ xref CSV)
5.  [`lnk_score()`](https://newgraphenvironment.github.io/link/reference/lnk_score.md)
    →
    [`lnk_source()`](https://newgraphenvironment.github.io/link/reference/lnk_source.md)
    → `frs_habitat()`
6.  Falls as `list(table = "working.falls", label = "blocked")`

To run the entire province: loop over watershed groups. Or pass any AOI
with `species` for sub-basin work.

## Open Issues

- \#18 — Configurable rearing-spawning connectivity
- \#19 — Habitat eligibility override CSV (edge_types + feature_codes)
- \#20 — Literature/observation evidence for habitat departures
- \#21 — GSDD and thermal energy as intrinsic potential variables
- \#24 — lnk_stamp (model params for report appendix)
- \#29 — SK spawning cluster divergence (blocked on fresh#133)
- \#33 — Cross-ref note: bcfishpass access_st checks SK instead of ST
  (bcfishpass#9)
- \#34 — Update doc version references (bcfishpass current, not v0.5.0)
- \#45 — Gradient classes cleanup (derive from
  `loaded$parameters_fresh$access_gradient_max`)
- \#52 — Channel-class break positions vs gradient thresholds (research)
- \#53 — Distribute tar_make across M4 + M1 + db_newgraph
- \#75 — `dimensions_columns.csv` as source-of-truth: auto-gen README +
  [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  validation (CSV seeded in v0.17.0)

## Recently closed

- README refresh (PR \#81) — rewrote around manifest configs +
  methodology-as-data narrative. Five-line demo, real BT-row comparison
  from `dimensions.csv`, `extends:` example, single pkgdown ref link, no
  per-section function lists. Acknowledgements + License kept verbatim.
- `_pkgdown.yml` cleanup (post-v0.18.1) — dropped manual `reference:`
  index. With `lnk_*` naming convention doing thematic grouping
  naturally, the index was duplicate work that broke CI on v0.18.1
  release. Now auto-generated; per-function `@title`/`@description`
  carry the card view.
- \#78 → v0.18.1 — Attribution for redistributed upstream data +
  Title/Description refresh. NOTICE.md, LICENSE-bcfishpass, per-bundle
  `overrides/README.md` pointers, README Acknowledgements,
  `Authors@R [ctb]` for Simon Norris. New Title: “Habitat and
  Connectivity Interpretation for Stream Networks”. Description mirrors
  README’s “fresh answers / link answers” framing.
- \#76 — Enabled `allow_auto_merge` on the repo so the daily csv-sync
  workflow’s byte-drift PRs auto-merge cleanly. Validated by PR \#77
  landing unattended.
- \#65 → v0.18.0 — `lnk_load_overrides(config)` + manifest/data split.
  Decomposed
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  into manifest-only loader and new
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md)
  ingest with crate dispatch. Single PR, single bump. Config schema
  flattened into one `files:` map keyed by filename stem; `rules:` and
  `dimensions:` paths moved top-level (no format suffix). Pipeline
  phases take `loaded` alongside `cfg`. Bit-identical rollup vs v0.17.0
  baseline. Companion crate v0.0.2 release added Convention C `crt_*`
  prefix family + schema-driven type enforcement (`crt_schema_apply`,
  `crt_schema_validate`, `crt_schema_read`).
- \#1 — Original v0.6-era scope issue closed as superseded by the
  package’s evolution.

## Older closed

- \#69 — Dimensions-driven `in_waterbody` + `area_only` emission → PRs
  \#71/#72/#73 (v0.14.0–v0.16.0).
- \#68 — Vignette ship — superseded by \#74 (v0.17.0). Vignette removed
  2026-04-29 once parity claim was retracted.
- \#23 — CH spawning stream order exception QA — closed as not-a-bug
  (premise was a misread of bcfishpass spawning bypass: it uses
  `waterbody_key IS NOT NULL`, NOT `stream_order_parent`. Stream-order
  bypass exists in CH **rearing** only, tracked in fresh#158).
- \#16 — ADMS comparison (tagged via PRs \#41/#42/#43 for targets-driven
  reproducibility). Note: the “within 5%” framing was on a small set of
  pre-selected WSGs and missed barrier-class gaps surfaced in
  2026-04-29.
- \#38 — `_targets.R` pipeline → PRs \#41/#42/#43 (v0.3.0/v0.4.0/v0.5.0)
- \#44 — `barriers_definite_control` override wiring → PR \#47 (v0.6.0)
- \#46 — Manifest-driven pipeline probes → PR \#50 (v0.7.0 refactor, no
  bump)
- \#48 — `user_barriers_definite` not eligible for observation override
  → PR \#49 (v0.7.0)

## Correctness bar: exact reproduction

The habitat classification pipeline is validated by **exact reproduction
of runs**, not by “within 5% of bcfishpass.” Same fwapg DB state + same
bcfishobs DB state + same config bundle → byte-identical rollup tibble,
every time. Any variation between two runs with identical inputs is a
defect to root-cause, not to rationalize as “ordering variance.”

Comparisons to bcfishpass (including the per-WSG `diff_pct` column in
the rollup) are parity diagnostics — informative, not pass/fail. A
bit-identical run that drifts from bcfishpass reference is acceptable; a
reproducibility failure with the same inputs is not.

When inputs change (fwapg refresh, bcfishobs update, channel_width
sync), outputs will correctly differ. That’s what the stamp/lineage work
(#40) makes explainable — so any observed drift can be traced back to
which input moved.

## Config change workflow

When changing a `configs/<name>/dimensions.csv` or any file that feeds
[`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md):

1.  **Regenerate + diff rules.yaml before running anything.**
    `Rscript data-raw/build_rules.R` then
    `git diff inst/extdata/configs/<name>/rules.yaml`. Confirm the diff
    matches intent — e.g., toggling `spawn_lake=no` for SK should remove
    the `waterbody_type: L` rule under `SK.spawn`. Catching an
    unintended rule here costs seconds; catching it after a 20-min
    tar_make costs 20 min.
2.  **Pre-flight on one WSG, not five.** After reinstalling the package
    (`pak::local_install(upgrade = FALSE, ask = FALSE)` or equivalent),
    run the single-WSG workload (`link-tarmake-single <WSG>`) on the
    smallest WSG impacted by the change before the full
    `link-tarmake-5wsg`. ADMS is smallest, BULK largest per
    `workloads.csv` — pick whichever is small AND exercises the affected
    species. **Always report the pre-flight result framed as departures
    from bcfishpass reference, not just raw link numbers.** Small config
    changes (new threshold, edge-type tweak) should land within ~±20% of
    bcfp values; \>50% departure is a flag; \>100% or a 10× swing is
    “investigate before rerun” — bcfishpass is mature and its numbers
    are a reasonable sanity baseline. The four `sources` buckets from
    `§6` of the research doc are better signal than the scalar rollup
    delta — run them on the pre-flight WSG too.
3.  **DB-side sanity as shortcut.** When the fix’s effect is measurable
    (e.g., “SK spawning km should drop because lake shoreline edges no
    longer count”), a direct query on `fresh.streams_habitat` grouped by
    `edge_type` can confirm direction of change in ~30s without any
    tar_make.

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#24 — crossing connectivity
interpretation package.

# CI Monitoring

When this repo has GitHub Actions workflows, scan recent runs on session
start. Catches failed pkgdown deploys, broken vignette builds, and stale
citation regenerations that would otherwise linger until the user
manually checks.

## On Session Start

``` bash
gh run list --limit 5 --json status,conclusion,name,createdAt,databaseId \
  --jq '.[] | select(.conclusion == "failure")'
```

If any failures since the last visit, surface to the user before
starting other work:

> Workflow `<name>` failed `<time>` ago (run `<id>`). Investigate with
> `gh run view <id> --log-failed`. Fix or proceed with current task?

User decides; do not auto-fix.

## Particular Failures Worth Naming

- **pkgdown** — docs site on GitHub Pages broken
- **R-CMD-check** — package may not install
- **Vignette / build-vignettes** — vignette docs incomplete
- **update-citation-cff** — CITATION.cff stale

## Why This Matters

Without this scan, post-merge workflow failures linger until someone
(often the user) notices a stale docs site or a missing vignette. The
session-start sweep catches them on the first re-entry into the repo.

## Pairs with `/gh-pr-merge`

The skill watches workflows triggered by a fresh merge in real time —
that’s the targeted catch. This convention is the backstop for failures
that landed when no one was watching (merges via web UI, scheduled
triggers, manually-triggered workflows).

# Code Check Conventions

Structured checklist for reviewing diffs before commit. Used by
`/code-check`. Add new checks here when a bug class is discovered — they
compound over time.

## Shell Scripts

### Quoting

- Variables in double-quoted strings containing single quotes break if
  value has `'`
- `"echo '${VAR}'"` — if VAR contains `'`, shell syntax breaks
- Use `printf '%s\n' "$VAR" | command` to pipe values safely
- Heredocs: unquoted `<<EOF` expands variables locally, `<<'EOF'` does
  not — know which you need
- Pass-through-ssh args: `printf '%q'` escapes per-arg so workload paths
  with spaces / quotes / metacharacters survive the local-shell →
  ssh-argv → remote-shell round-trip. Without it,
  `ssh host 'cmd' "$path"` joins args with spaces on remote and
  re-parses, losing argument boundaries.

### Heredoc precedence in pipelines

- `cmd1 | cmd2 <<EOF` — the heredoc binds to `cmd2` (the rightmost
  simple command). If you intended `cmd1` to receive it, put `<<EOF` on
  cmd1 explicitly: `cmd1 <<EOF | cmd2`.
- Symptom when wrong: ssh body silently echoed by tee/cat/etc, ssh side
  gets empty stdin, exits 0 (or near-0) without doing anything. Caught
  the hard way 2026-05-01 in cypher_restore-fwapg.sh.

### pipefail with ssh+tee

- `set -eu` does NOT propagate exit codes through pipelines.
  `ssh ... | tee log` returns tee’s exit (always 0 for healthy tee),
  masking ssh failure.
- Use `set -euo pipefail` for any script that pipes a meaningful command
  into tee/cat/grep/etc. Or check `${PIPESTATUS[0]}` explicitly.
- Symptom when wrong: task notifications report “exit 0 / completed”
  while remote work was actually skipped or errored.

### Paths

- Hardcoded absolute paths (`/Users/airvine/...`) break for other users
- Use `REPO_ROOT="$(cd "$(dirname "$0")/<relative>" && pwd)"`
- After moving scripts, verify `../` depth still resolves correctly
- Usage comments should match actual script location

### Silent Failures

- `|| true` hides real errors — is the failure actually safe to ignore?
- Empty variable before destructive operation (rm, destroy) — add guard:
  `[ -n "$VAR" ] || exit 1`
- `grep` returning empty silently — downstream commands get empty input

### Process Visibility

- Secrets passed as command-line args are visible in `ps aux`
- Use env files, stdin pipes, or temp files with `chmod 600` instead

## Cloud-Init (YAML)

### ASCII

- Must be pure ASCII — em dashes, curly quotes, arrows cause silent
  parse failure
- Check with: `perl -ne 'print "$.: $_" if /[^\x00-\x7F]/' file.yaml`

### YAML flow-mapping in runcmd

- Any runcmd item containing both `{` and `:` is at risk of being parsed
  as a YAML flow-mapping (dict), not a literal string. Cloud-init’s
  shellify hits a non-string and throws TypeError, **aborting all
  subsequent runcmd steps silently** while `final_message` still fires.

- Don’t write: `- test -s /file || { echo "FATAL: ..." }` — the `:`
  inside braces makes YAML see a dict.

- Do write: use `- |` block scalar with explicit `if/then/fi`:

  ``` yaml
  - |
    if [ ! -s /file ]; then
      echo "FATAL: ..." >&2
      exit 1
    fi
  ```

- Validate post-edit:
  `python3 -c "import yaml; runcmd=yaml.safe_load(open('cloud-init.yaml').read().split(chr(10),1)[1])['runcmd']; print([type(x).__name__ for x in runcmd if not isinstance(x,str)] or 'all strings')"`.
  If the output is anything other than `all strings`, the runcmd will
  fail.

### State

- `cloud-init clean` causes full re-provisioning on next boot — almost
  never what you want before snapshot
- Use `tailscale logout` not `tailscale down` before snapshot
  (deregister vs disconnect)
- Wipe `/var/lib/tailscale/*` before snapshot too — `tailscale logout`
  deauthorizes server-side but local node identity blob persists in
  tailscaled.state. Snapshot restored elsewhere inherits prior key
  material until `tailscale up` runs again.
- Wipe `/etc/ssh/ssh_host_*` before snapshot — otherwise droplets
  spawned from the same image share host identity.

### Template Variables

- Secrets rendered via `templatefile()` are readable at
  `169.254.169.254` metadata endpoint
- Acceptable for ephemeral machines, document the tradeoff
- Heredocs in runcmd that write secrets: `<<'EOF'` (quoted) prevents
  bash from re-expanding `$X` sequences in already-substituted
  credential strings. AWS keys rarely contain `$` but base64-padded
  secrets might.

### Repo + key install ordering

- `apt-key adv --keyserver` is deprecated on Ubuntu 24.04 noble —
  silently fails AND APT ignores resulting keyring. Use
  `gpg --dearmor` + `signed-by=` keyring file pattern.
- Repo .list files in `write_files:` trigger the implicit
  `package_update` BEFORE runcmd installs the keyring → first apt-get
  update fails with NO_PUBKEY. Put the repo line in runcmd alongside the
  key install, not in write_files.

### Cloud-init users vs DO SSH key injection

- DO injects `ssh_key_ids` only into `/root/.ssh/authorized_keys`
  (cloud-init’s `cc_ssh` module). Cloud-init `users:` block with
  `ssh_authorized_keys: []` does NOT pick those up.

- Non-root users that need SSH access must copy from root’s keys in
  runcmd:

  ``` yaml
  - mkdir -p /home/<user>/.ssh
  - cp /root/.ssh/authorized_keys /home/<user>/.ssh/authorized_keys
  - chown -R <user>:<user> /home/<user>/.ssh
  ```

- Guard with `test -s /root/.ssh/authorized_keys` to fail loudly if
  `cc_ssh` hasn’t run before runcmd (rare race).

## OpenTofu / Terraform

### State

- Parsing `tofu state show` text output is fragile — use `tofu output`
  instead
- Missing outputs that scripts need — add them to main.tf
- Snapshot/image IDs in tfvars after deleting the snapshot — stale
  reference

### Destructive Operations

- Validate resource IDs before destroy: `[ -n "$ID" ] || exit 1`
- `tofu destroy` without `-target` destroys everything including
  reserved IPs
- Snapshot ID extraction by name: use
  `awk -v n="$NAME" '$2 == n {print $1}'` (exact match on column 2).
  `grep -F "$NAME"` is substring-match and can grab a stale snapshot
  whose name contains the new name as a substring.

## DigitalOcean

### Snapshot disk-size constraint

- DO snapshots include the source droplet’s disk size. New droplets from
  a snapshot must have disk **\>=** snapshot disk. Resize **up** is
  fine; resize **down** below the snapshot disk is impossible without
  rebuilding.
- Build the snapshot at the smallest droplet size you’d ever want to
  spin from it. Sizes vs disks at writing: `g-4vcpu-16gb` = 50 GB,
  `g-8vcpu-32gb` / `m-4vcpu-32gb` = 100 GB, `m-8vcpu-64gb` = 200 GB.
- If your workload requires X GB RAM minimum, your snapshot floor is
  whatever droplet has X GB AND the smallest disk class.

### Reserved IP detach behavior

- Targeted destroy
  (`tofu destroy -target=module.droplet -target=...assignment...`)
  preserves the reserved IP at \$4/mo. Full `tofu destroy` releases it
  (next apply gets a NEW IP).

### Reserved IP assignment race (rtj#55, rtj#85)

- DO returns 422 “Droplet already has a pending event” when reserved IP
  assignment fires immediately after droplet+firewall creation. The
  droplet’s internal event queue takes time to drain.
- **Every DO droplet module that uses a reserved IP MUST have:**
  1.  `time_sleep` resource between droplet creation and IP assignment,
      with `create_duration ≥ 60s` (10s and 30s have both been observed
      to race; 60s has more headroom)
  2.  `depends_on = [time_sleep.<name>]` on the
      `digitalocean_reserved_ip_assignment` resource
  3.  A retry fallback in the wrapping shell script (`up.sh` style) that
      detects the 422 in tofu output and uses
      `doctl compute reserved-ip-action assign <ip> <droplet-id>` to
      recover. Tofu doesn’t retry; it leaves state half-applied
      (assignment recorded but DO didn’t actually attach).
- **Snapshot-based spins are MORE prone to the race** than first-boot
  from blank Ubuntu (more startup events compete for the droplet’s event
  queue).
- **Audit existing modules:**
  `grep -L 'time_sleep' env/do/*/<host>/main.tf` finds modules missing
  the gate. As of 2026-05-02, openclaw and geoserv have no `time_sleep`
  — they will race eventually.

## Docker / Postgres

### Postgis init time

- `imresamu/postgis` (and similar postgis images) on first cold start
  (empty data volume) take **5-12 min** to install all extensions —
  varies with disk IO and noisy-neighbor lottery on cloud hosts.
  Health-wait scripts must allow 15 min minimum, ideally with
  hard-fail + log dump on timeout.

### Tuning vs host RAM

- fresh’s `docker/docker-compose.yml` defaults are tuned for a 128 GB
  host (`shared_buffers=32GB`, `shm_size=36gb`). On smaller hosts,
  postgres OOMs at startup with “could not map anonymous shared memory”.
- 32 GB host floor: use the M1/cypher 32 GB-host preset
  (`scripts/fwapg/compose.override.m1.yml`) which sets
  `shared_buffers=8GB, shm_size=12gb`.
- Below 32 GB: postgres can technically start with smaller
  `shared_buffers` but fwapg work becomes painful. Don’t run fwapg
  pipelines on \<32 GB hosts.

### `search_path` is data, not config

- `ALTER DATABASE <db> SET search_path TO ...` is a database-level
  setting **stored in the postgres data dir**. Wiped with
  `docker compose down -v`. Must be re-applied on every restore.
- Codify in your restore script, not in cloud-init or compose env (those
  don’t apply to db-level settings).

## Tailscale

### ACL “users” semantics

- Tailscale SSH ACL `"users": ["autogroup:nonroot"]` for `tag:compute`
  blocks `ssh root@<node>` over the tailnet. Use `ssh <user>@<node>` +
  sudo for root operations.
- For SSH-as-root from off-tailnet (regular OpenSSH on the public IP),
  the ACL doesn’t apply — but you need the SSH key registered on the
  node.

### Reusable + ephemeral auth keys

- Cypher-style ephemeral compute droplets need both flags on the auth
  key: **Reusable** (same key works across destroy/recreate) +
  **Ephemeral** (tailnet entries auto-clean when offline \>5 min).
- Tag the key (e.g. `tag:compute`) at creation time. Nodes joining with
  that key inherit the tag automatically — no `--advertise-tags` needed
  at `tailscale up` time.

## Security

### Secrets in Committed Files

- `.tfvars` must be gitignored (contains tokens, passwords)
- `.tfvars.example` should have all variables with empty/placeholder
  values
- Sensitive variables need `sensitive = true` in variables.tf

### Firewall Defaults

- `0.0.0.0/0` for SSH is world-open — document if intentional
- If access is gated by Tailscale, say so explicitly

### Credentials

- Passwords with special chars (`'`, `"`, `$`, `!`) break naive shell
  quoting
- `printf '%q'` escapes values for shell safety
- Temp files for secrets: create with `chmod 600`, delete after use

## R / Package Installation

### pak Behavior

- pak stops on first unresolvable package — all subsequent packages are
  skipped
- Removed CRAN packages (like `leaflet.extras`) must move to GitHub
  source
- PPPM binaries may lag a few hours behind new CRAN releases

### Reproducibility

- Branch pins (`pkg@branch`) are not reproducible — document why used
- Pinned download URLs (RStudio .deb) go stale — document where to
  update

## General

### Adopting Existing Config

When importing config from one location into a canonical one (legacy
`~/.bash_profile` → dotfiles repo, old script’s env → repo, another
project’s `settings.json` → soul):

- **Verify every referenced path/binary exists.** Dead PATH exports,
  missing interpreters, stale env vars should be cut, not codified.
  Shell paths:
  `for p in $(echo "$PATH" | tr ':' ' '); do [ -d "$p" ] || echo "DEAD: $p"; done`
- **Ask before dropping a reference** — it may be something the user
  forgot to reinstall on this machine, not something to delete.
- **Curated subset, not verbatim copy.** The diff should reflect what
  you verified, not the whole source.

### Documentation Staleness

- Moving/renaming scripts: update CLAUDE.md, READMEs, usage comments
- New variables: update .tfvars.example
- New workflows: update relevant README

# Comms Conventions

This repo has a `comms/` directory — you’re in the cross-repo
Claude-to-Claude messaging system. Full protocol in `comms/README.md`.
Peer list (who to scan) in `soul/conventions/comms_peers.md`
(internal-only). Load-bearing behaviors below.

## On Session Start

1.  **Inbound scan.** `<this-repo>/comms/*/` — files with `status: open`
    and mtime newer than your last `comms/` commit are mail for you.
2.  **Outbound scan.** For each peer in `comms_peers.md`, check
    `<peer>/comms/<this-repo>/*.md` — files with
    `from: <this-repo>, status: open` are your un-answered sent mail.

If either surfaces open threads, raise to the user before starting other
work.

## Commit Prefix

- `comms(→peer):` — you committed a file in peer’s repo (outbound)
- `comms(←peer):` — you committed a file in your own repo (inbound
  reply)
- `comms:` — meta (close, reopen, rename, README update)

Arrow points to the repo whose `comms/` contains the file you committed.

## Non-negotiables

- One commit per appended message.
- **Push immediately.** Un-pushed comms is invisible to the other
  Claude.
- Code + comms = separate commits.
- Status flips bundle with the triggering message.
- **Use `git commit --only <file>`** for any commit in a peer’s repo
  (thread files). Immune to index races from parallel sessions.

## Propagation: soul publishes, peers pull

Soul is the source of truth for `comms/README.md`. Peers sync by running
`/comms-init` in their own repo, from their own Claude session. **Do not
push README updates into a peer’s repo from another session** —
cross-session index races can bundle unrelated staged files into
misleading commits.

Within your own session, the only things you commit into a peer’s repo
are **thread files** (hosted in the receiver’s repo per the
receiver-hosts rule). Everything else — README syncs, infra — the
peer-Claude pulls itself.

### Cross-repo thread commits: which branch?

Commit on peer’s **current branch** — whatever they’ve got checked out.
Don’t stash, switch, or force main.

If peer isn’t on main, surface to the user: *“thread landing on
`<peer>`:`<branch>`, won’t hit main until PR merges. Continue or hold?”*
If peer has complicated local state (mid-rebase, partial merge), defer
to the user.

# NGE Feature Workflow

For non-trivial issue-driven work, follow this checklist. Each step
exists for a reason — skipping leads to rework, broken builds, and
avoidable bugs that we’ve hit repeatedly.

## The Sequence

1.  **Start with `/planning-init <N>`** — given an issue number, enters
    plan mode for codebase exploration, presents a phase breakdown for
    user approval, then scaffolds branch + PWF baseline with the
    approved phases. One command replaces the manual issue → explore →
    plan → branch → scaffold dance.
2.  **Write robust tests first** — failing tests that reproduce the
    issue or document the new behavior. Tests are the contract; they
    fail until the work makes them pass.
3.  **Name with intent** — functions, parameters, internal helpers carry
    the naming style of the package they live in. Look at existing
    exports as the guide; consistency over cleverness. (Per-package
    naming convention TBD — see soul issue tracking.)
4.  **Examples that run** — every exported function gets a runnable
    `@examples` block. Pkgdown renders them; CI executes them. An
    example that doesn’t run is documentation rot.
5.  **Code-check before each commit** — `/code-check` on staged diff.
    Catches what tests miss: edge cases, hard-coded paths, unguarded
    variables, security issues.
6.  **Atomic commits** — each commit bundles code change + checkbox flip
    in `task_plan.md`. The diff and the progress live in the same
    commit; `git log -- planning/` tells the full story.
7.  **`/planning-archive` when complete** — moves PWF to
    `archive/YYYY-MM-issue-N-slug/`, creates a fresh `active/`. Then
    `/gh-pr-push` opens the PR; `/gh-pr-merge` handles the release
    bookkeeping.

## When to Skip

For one-line typo fixes, version-bump-only PRs, or trivial documentation
edits, the full workflow is overhead. Use judgment. The threshold is
roughly: **multi-step issue, multi-file change, or anything that
requires scoping** → use the workflow.

## Skills That Slot In

- `/planning-init <N>` — start
- `/planning-update` — sync checkboxes mid-session
- `/code-check` — before every commit
- `/planning-archive` — when issue closes
- `/gh-pr-push` — open the PR
- `/gh-pr-merge` — merge with release bookkeeping

## Why This Exists

We’ve hit snags repeatedly when half-doing this — branches that mix
concerns, tests bolted on after, code-check skipped (and then a bug
ships in the diff), examples that fail in pkgdown. Each step is small;
the cumulative reliability gain is real. The convention is here so it
becomes the default expectation, not a thing the user has to remind
every session about.

# LLM Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with
project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For
trivial tasks, use judgment.

## 1. Think Before Coding

**Don’t assume. Don’t hide confusion. Surface tradeoffs.**

Before implementing: - State your assumptions explicitly. If uncertain,
ask. - If multiple interpretations exist, present them - don’t pick
silently. - If a simpler approach exists, say so. Push back when
warranted. - If something is unclear, stop. Name what’s confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No “flexibility” or “configurability” that wasn’t requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: “Would a senior engineer say this is overcomplicated?” If
yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code: - Don’t “improve” adjacent code, comments,
or formatting. - Don’t refactor things that aren’t broken. - Match
existing style, even if you’d do it differently. - If you notice
unrelated dead code, mention it - don’t delete it.

When your changes create orphans: - Remove imports/variables/functions
that YOUR changes made unused. - Don’t remove pre-existing dead code
unless asked.

The test: Every changed line should trace directly to the user’s
request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals: - “Add validation” → “Write tests
for invalid inputs, then make them pass” - “Fix the bug” → “Write a test
that reproduces it, then make it pass” - “Refactor X” → “Ensure tests
pass before and after”

For multi-step tasks, state a brief plan:

    1. [Step] → verify: [check]
    2. [Step] → verify: [check]
    3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria (“make
it work”) require constant clarification.

**These guidelines are working if:** fewer unnecessary changes in diffs,
fewer rewrites due to overcomplication, and clarifying questions come
before implementation rather than after mistakes.

# Planning Conventions

How Claude manages structured planning for complex tasks using
planning-with-files (PWF).

## When to Plan

Use PWF when a task has multiple phases, requires research, or involves
more than ~5 tool calls. Triggers: - User says “let’s plan this”, “plan
mode”, “use planning”, or invokes `/planning-init` - Complex issue work
begins (multi-step, uncertain approach) - Claude judges the task
warrants structured tracking

Skip planning for single-file edits, quick fixes, or tasks with obvious
next steps.

## The Workflow

1.  **Explore first** — Enter plan mode (read-only). Read code, trace
    paths, understand the problem before proposing anything.
2.  **Plan to files** — Write the plan into 3 files in
    `planning/active/`:
    - `task_plan.md` — Phases with checkbox tasks
    - `findings.md` — Research, discoveries, technical analysis
    - `progress.md` — Session log with timestamps and commit refs
3.  **Plan-review with the Plan agent before committing the plan** —
    After scaffolding `task_plan.md` but BEFORE the baseline commit,
    spawn the Plan subagent
    (`Agent({subagent_type: "Plan", prompt: "..."}`) and ask it to
    critically review the task_plan against the issue body + actual
    codebase. Categorize findings as Blocker / Gap / Ordering /
    Assumption / Scope / Acceptance. Address each before committing. The
    agent reads files fresh — it catches what you miss when you’ve been
    thinking about the design too long. Real example: caught 21 issues
    including hardcoded literals across 4 files not listed in the plan,
    untested DB column mismatches, unfixable test-literal-string
    assertions, and a baseline-cache-shadow that would have produced a
    6-second no-op run. Cost: ~5 min agent. Saves: hours of
    mid-implementation rework.
4.  **Commit the plan** — After Plan-agent review + fixes. This is the
    baseline.
5.  **Work in atomic commits** — Each commit bundles code changes WITH
    checkbox updates in the planning files. The diff shows both what was
    done and the checkbox marking it done.
6.  **Code check before commit** — Run `/code-check` on staged diffs
    before committing. Don’t mark a task done until the diff passes
    review.
7.  **Archive when complete** — Move `planning/active/` to
    `planning/archive/` via `/planning-archive`. Write a README.md in
    the archive directory with a one-paragraph outcome summary and
    closing commit/PR ref — future sessions scan these to catch up fast.

## Atomic Commits (Critical)

Every commit that completes a planned task MUST include: - The
code/script changes - The checkbox update in `task_plan.md` (`- [ ]` -\>
`- [x]`) - A progress entry in `progress.md` if meaningful

This creates a git audit trail where `git log -- planning/` tells the
full story. Each commit is self-documenting — you can backtrack with git
and understand everything that happened.

## File Formats

### task_plan.md

Phases with checkboxes. This is the core tracking file.

``` markdown
# Task Plan

## Phase 1: [Name]
- [ ] Task description
- [ ] Another task

## Phase 2: [Name]
- [ ] Task description
```

Mark tasks done as they’re completed: `- [x] Task description`

### findings.md

Append-only research log. Discoveries, technical analysis, things
learned.

``` markdown
# Findings

## [Topic]
[What was found, with source/date]
```

### progress.md

Session entries with commit references.

``` markdown
# Progress

## Session YYYY-MM-DD
- Completed: [items]
- Commits: [refs]
- Next: [items]
```

## Directory Structure

    planning/
      active/          <- Current work (3 PWF files)
      archive/         <- Completed issues
        YYYY-MM-issue-N-slug/

If `planning/` doesn’t exist in the repo, run `/planning-init` first.

## Skills

| Skill               | When to use                                        |
|---------------------|----------------------------------------------------|
| `/planning-init`    | First time in a repo — creates directory structure |
| `/planning-update`  | Mid-session — sync checkboxes and progress         |
| `/planning-archive` | Issue complete — archive and create fresh active/  |

# R Package Development Conventions

Standards for R package development across New Graph Environment
repositories. Based on [R Packages (2e)](https://r-pkgs.org/) by Hadley
Wickham and Jenny Bryan.

**Reference packages:** When starting a new package, study these
existing packages for patterns: `flooded`, `gq`. They demonstrate the
conventions below in practice (DESCRIPTION fields, README layout,
NEWS.md style, pkgdown setup, test structure, hex sticker, etc.).

## Style

- tidyverse style guide: snake_case, pipe operators (`|>` or `%>%`)

- Match existing patterns in each codebase

- Use `pak` for package installation (not `install.packages`)

- Prefix column name vectors with `cols_` for discoverability in the
  environment pane: `cols_all`, `cols_carry`, `cols_split`,
  `cols_writable`. Same principle for other grouped vectors (`params_`,
  `tbl_`, etc.)

- **Function parameters that name a database table use `table_<role>`**:
  `table_in`, `table_out`, `table_to`, `table_pscis`, `table_modelled`,
  `table_target`. Picked over `<role>_table` (e.g. `pscis_table`) for
  consistency and to group table args together in autocomplete /
  signature views. Also picked over bare `to` for destination tables —
  `table_to` is explicit about what’s being passed. Single-noun args
  stay when the role IS the name (e.g. `segments`, `observations`,
  `crossings`). Existing functions using `<role>_table` or bare `to`
  migrate opportunistically when touched; no big-bang rename.

- **Same convention for column-name parameters: `col_<role>`**:
  `col_a_id`, `col_b_id`, `col_segment_id`, `col_blue_line_key`,
  `col_key`. Picked over `<role>_col` (e.g. `segment_id_col`) for the
  same autocomplete-grouping reason. fresh’s existing `segment_id_col` /
  `feature_id_col` precede this convention and migrate
  opportunistically.

- **Same convention for SQL-expression parameters: `exp_<role>`**:
  `exp_score`, `exp_filter`, `exp_where`, `exp_select`. SQL fragments
  the caller writes that get embedded into a generated query. Like
  `table_*` and `col_*`, the `exp_` prefix groups expression args
  together in autocomplete / signature views.

- For SQL DDL+INSERT pairs that share a schema, use a single named
  vector as the source of truth. Both `CREATE TABLE` and
  `INSERT (cols) SELECT cols` derive their column lists from the same
  `cols_*` vector. Avoids drift between table shape and write projection
  — when columns change, you edit one place. Example:

  ``` r

  cols_streams <- c(
    id_segment           = "integer NOT NULL",
    watershed_group_code = "varchar(4) NOT NULL",
    geom                 = "geometry(MultiLineStringZM, 3005)"
    # …
  )
  # CREATE TABLE consumes both names + types
  ddl_body <- paste(names(cols_streams), unname(cols_streams), sep = " ",
                    collapse = ", ")
  # INSERT consumes names only
  proj <- paste(names(cols_streams), collapse = ", ")
  ```

## Package Structure

Follow R Packages (2e) conventions: - `R/` for functions,
`tests/testthat/` for tests, `man/` for docs - `DESCRIPTION` with proper
fields (Title, Description, <Authors@R>) - `DESCRIPTION` URL field:
include both the GitHub repo and the pkgdown site so pkgdown links
correctly (e.g.,
`URL: https://github.com/OWNER/PKG, https://owner.github.io/PKG/`) -
`NAMESPACE` managed by roxygen2 (`#' @export`, `#' @import`,
`#' @importFrom`) - Never edit `NAMESPACE` or `man/` by hand

## One Function, One File

Each exported function gets its own R file and its own test file: -
`R/fl_mask.R` → `tests/testthat/test-fl_mask.R` - Commit the function
and its tests together - Use `Fixes #N` in the commit message to close
the corresponding issue

## GitHub Issues and SRED Tracking

### Issue-per-function workflow

File a GitHub issue for each function before building it. This creates a
traceable record of what was planned, built, and verified.

### Branching for SRED

For new packages or major features, work on a branch and merge via PR:

    main ← scaffold-branch (PR closes with "Relates to NewGraphEnvironment/sred-2025-2026#N")

This gives one PR that contains all commits — a single SRED
cross-reference covers the entire body of work. Individual commits
within the branch close their respective function issues with
`Fixes #N`.

### Closing issues

Close function issues via commit messages — see Closing Issues in
newgraph conventions.

## Testing

- Use testthat 3e (`Config/testthat/edition: 3` in DESCRIPTION)

- Run `devtools::test()` before committing

- Test files mirror source: `R/utils.R` -\>
  `tests/testthat/test-utils.R`

- Test for edge cases and potential failures, not just happy paths

- Tests must pass before closing the function’s issue

- Always grep for errors in the same command as the test run to avoid
  running twice:

  ``` bash
  Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
  ```

  For error context: `grep -E "(ERROR:|FAIL )" -A 10 | head -25`

## Examples and Vignettes

### Runnable examples on every exported function

Examples are how users discover what a function does. They must: -
**Actually run** — no `\dontrun{}` unless external resources are
required - **Use bundled test data** via
[`system.file()`](https://rdrr.io/r/base/system.file.html) so they work
for anyone - **Show why the function is useful** — not just that it
runs, but what it produces and why you’d use it - **Use qualified
names** for non-exported dependencies
([`terra::rast()`](https://rspatial.github.io/terra/reference/rast.html),
[`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html))
since examples run in the user’s environment

### Vignettes

At least one vignette showing the full pipeline on real data: -
Demonstrates the package solving an actual problem end-to-end - Uses
bundled test data (committed to `inst/testdata/`) - Hosted on pkgdown so
users can read it without installing

**Output format:** Use `bookdown::html_vignette2` (not
[`rmarkdown::html_vignette`](https://pkgs.rstudio.com/rmarkdown/reference/html_vignette.html))
for figure numbering and cross-references. Requires `bookdown` in
Suggests and chunks must have `fig.cap` for numbered figures.
Cross-reference with `Figure \@ref(fig:chunk-name)`.

**Vignettes that need external resources (DB, API, STAC):** Do NOT use
the `.Rmd.orig` pre-knit pattern — it breaks `bookdown` figure numbering
because knitr evaluates chunks during pre-knit and emits `![](path)`
markdown that bookdown can’t number.

Instead, separate data generation from presentation: 1.
`data-raw/vignette_data.R` — runs the queries, saves results as `.rds`
to `inst/testdata/` (or `inst/vignette-data/`) 2. Vignette loads `.rds`
files, all chunks run live during pkgdown build 3. Note at top of
vignette: “Data generated by `data-raw/script.R`” 4. bookdown controls
all chunks — figure numbers, cross-refs work

This is the same pattern as test data: `data-raw/` documents how the
data was produced, committed artifacts make vignettes reproducible
without the external resource.

### Test data

- Created via a script in `data-raw/` that documents exactly how the
  data was produced (database queries, spatial crops, etc.)
- Committed to `inst/testdata/` — small enough to ship with the package
- Used by tests, examples, and vignettes — one dataset, three purposes

## Documentation

- roxygen2 for all exported functions
- `@import` or `@importFrom` in the package-level doc
  (`R/<pkg>-package.R`) to populate NAMESPACE — don’t rely on `::`
  everywhere in function bodies
- pkgdown site for public packages with `_pkgdown.yml` (bootstrap 5)
- GitHub Action for pkgdown (`usethis::use_github_action("pkgdown")`)

## lintr

Run
[`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html)
before committing R package code. Fix all warnings — every lint should
be worth fixing.

### Recommended .lintr config

``` r

linters: linters_with_defaults(
    line_length_linter(120),
    object_name_linter(styles = c("snake_case", "dotted.case")),
    commented_code_linter = NULL
  )
exclusions: list(
    "renv" = list(linters = "all")
  )
```

- 120 char line length (default 80 is too strict for data pipelines)
- Allow dotted.case (common in base R and legacy code)
- Suppress commented code lints (exploratory R scripts often have
  commented alternatives)
- Exclude renv directory entirely

## Dependencies

- Minimize Imports — use `Suggests` for packages only needed in
  tests/vignettes
- Pin versions only when breaking changes are known
- Prefer packages already in the tidyverse ecosystem

## Releasing

1.  Update `NEWS.md` — keep it concise:
    - First release: one line (e.g., “Initial release. Brief
      description.”)
    - Later releases: describe what changed and why, not
      function-by-function. Link to the pkgdown reference page for
      details — don’t duplicate it.
    - Don’t list every function; the pkgdown reference page is the
      single source of truth for what’s in the package.
2.  Bump version in `DESCRIPTION` (e.g., `0.0.0.9000` → `0.1.0`) — as
    the **final** commit of the branch, after verification numbers/tests
    are final. Mid-branch bumps are premature and churn: additional code
    changes end up bundled inside a “release” that already claimed the
    version.
3.  Commit as “Release vX.Y.Z”
4.  Tag: `git tag vX.Y.Z && git push && git push --tags`

## Repository Setup

### Branch protection

Protect main from deletion and force pushes:

``` bash
gh api repos/OWNER/REPO/rulesets --method POST --input - <<'EOF'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
EOF
```

### Scaffold checklist

- `usethis::create_package(".")`
- `usethis::use_mit_license("New Graph Environment Ltd.")`
- `usethis::use_testthat(edition = 3)`
- `usethis::use_pkgdown()`
- `usethis::use_github_action("pkgdown")`
- `usethis::use_directory("dev")` — reproducible setup script
- `usethis::use_directory("data-raw")` — data generation scripts
- Hex sticker via `hexSticker` (see `data-raw/make_hexsticker.R`)
- Set GitHub Pages to serve from `gh-pages` branch

### dev/dev.R

Keep a `dev/dev.R` file that documents every setup step. Not idempotent
— run interactively. This is the reproducible recipe for the package
scaffold.

## README

Keep the README lean: - Hex sticker, one-line description, install,
example showing *why* it’s useful - Link to pkgdown vignette and
function reference — don’t duplicate them - Don’t maintain a function
table — it’s just another thing to keep updated and pkgdown’s reference
page is the single source of truth

## LLM Workflow

When an LLM assistant modifies R package code: 1. Run
[`lintr::lint_package()`](https://lintr.r-lib.org/reference/lint.html) —
fix issues before committing 2. Run `devtools::test()` with error grep —
ensure tests pass in one call:
`bash Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
3. Run `devtools::document()` and grep for results:
`bash Rscript -e 'devtools::document()' 2>&1 | grep -E "(Writing|Updating|warning)" | tail -10`
4. Check `devtools::check()` passes for releases — capture results in
one call:
`bash Rscript -e 'devtools::check()' 2>&1 | grep -E "(ERROR|WARNING|NOTE|errors|warnings|notes)" | tail -10`
