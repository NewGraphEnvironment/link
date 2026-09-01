# link RUNBOOK — how the system actually works

Durable mental model of link’s barrier → access → mapping_code
machinery. Written because the data flow spans ~8 R files and gets
re-derived from scratch every session (especially after context
compaction). Read this first.

For *what’s shipped* and *conventions*, see `CLAUDE.md`. This doc is the
*mechanics*: what feeds what, where each rule lives, and the gotchas
that have bitten us. When the mechanics change, update this file in the
same commit.

------------------------------------------------------------------------

## 0. Getting going (operate on a fresh machine — e.g. M1)

The modelling runs against a local Postgres (docker `fresh-db`) holding
the bcfp inputs. DB state is **machine-local** — rebuild it from public
sources, no DB dump needed. One-time prereqs (GDAL+Parquet driver, uv,
bcdata, psql) install via kdot `install_geo.sh`.

``` bash
# 1. Docker daemon + local fwapg
open -a Docker                                    # if daemon down; wait ~30s
cd ~/Projects/repo/fresh/docker && docker compose up -d db

# 2. Install link
cd ~/Projects/repo/link && Rscript -e 'pak::local_install(upgrade = FALSE, ask = FALSE)'

# 3. Snapshot bcfp inputs into local fwapg (tunnel-free, public sources, ~5-8 min)
PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg \
  bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force
#   loads whse_fish.pscis_*, cabd.dams, fresh.modelled_stream_crossings,
#   bcfishobs.observations (+ bcfp crossings_vw). streams_vw silently fails
#   (1.6 GB, see §6) — use the tunnel for bcfp streams parity instead.

# 4. bcfp comparison tunnel (parity diffs ONLY — the build itself is tunnel-free)
#    Forward the reference DB to :63333 however your environment reaches it.
#    Host aliases and credentials are infrastructure — see rtj, not here.
psql "host=localhost port=63333 dbname=bcfishpass user=newgraph" \
  -c "SELECT model_run_id, model_version FROM bcfishpass.log ORDER BY 1 DESC LIMIT 1;"
```

Local fwapg conn:
`host=localhost port=5432 dbname=fwapg user=postgres password=postgres`.
(M1’s `~/.Renviron` defaults `PG_*_SHARE` to the tunnel `:63333` — for
the local build set
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) to `:5432` in
R; see the m1-testing pattern in `fresh/CLAUDE.md`.) Then build:
`lnk_pipeline_run(conn, "PARS", cfg, loaded, schema, mapping_code = TRUE)`.

## 1. The big picture

link reproduces bcfishpass’s per-segment, per-species habitat +
connectivity classification, tunnel-free, for any watershed group (WSG)
or AOI.

    per-WSG pipeline (lnk_pipeline_run, working schema working_<aoi>)
      setup → load → prepare → crossings → barriers_unify → break → classify
            → connect → species → persist_init → persist
                                                      │
       with mapping_code = TRUE, an extra phase runs before persist:
            barriers_views → pipeline_access → mapping_code
                                                      │
                                                      ▼
       persist (province-wide <persist_schema>, e.g. fresh_default)
         streams, streams_habitat_<sp>, barriers,
         streams_access, streams_mapping_code, streams_habitat_long_vw (view)

The **working schema** is per-WSG scratch. The **persist schema** is
province-wide and cross-WSG — this is what QGIS, comparisons, and the
mapping_code views read. Persisting is idempotent per WSG
(DELETE-WHERE-WSG + INSERT).

------------------------------------------------------------------------

## 2. Barriers: the heart of it

### 2a. `blocks_species` — the per-segment blocking predicate

[`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md)
consolidates four barrier families into `<schema>.barriers`, each row
carrying a **`blocks_species text[]`** column. `lnk_pipeline_access`
later asks `WHERE 'BT' = ANY(blocks_species)`.

**The blocking rule depends on the barrier family — this is the single
most important table in the system:**

| Family | Source table | `blocks_species` | Species-specific? |
|----|----|----|----|
| **Gradient** | `gradient_barriers_raw` | species where `access_gradient_max ≤ gradient_class/100` | **YES** — from `parameters_fresh.csv` |
| **Anthropogenic** (PSCIS, **CABD dams**, modelled crossings) | `crossings WHERE barrier_status IN ('BARRIER','POTENTIAL')` | **ALL species** (universal) | **NO** |
| **Falls** | `falls` | ALL species | NO |
| **Subsurface flow** | `barriers_subsurfaceflow` (opt-in) | ALL species | NO |

Gradient classes (`gradient_barriers_raw.gradient_class`, basis points)
map to fractional thresholds via `.lnk_classes_bcfp`
(`lnk_pipeline_prepare.R`):
`1500→0.15, 2000→0.20, 2500→0.25, 3000→0.30`. A class blocks species `s`
when `class_value ≥ s$access_gradient_max`. BT’s `access_gradient_max`
is 0.25, so a 2500-class gradient blocks BT; CH/CO/SK at 0.15 are
blocked from 1500 up.

**Key consequence: dams block *all* species in `blocks_species`.** There
is no per-species dam rule in any config file. A dam (CABD, via the
anthropogenic family) gets `blocks_species = {all species}`. This was
the \#196 dam-token bug. bcfp does NOT put dams in the per-species
*access* set at all (§5) — they’re a downstream *descriptor*, not an
accessibility barrier. **Fixed in \#200/v0.40.4:** accessibility no
longer reads `blocks_species` over all barriers. It reads the
per-species `barriers_<sp>_access` view (§5), which filters to NATURAL
sources only
(`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')`)
— so dams are excluded from access and (correctly) annotate token2 only.
`blocks_species` is still computed for all families (it’s how the
`_access` view gets the per-species gradient threshold for free); the
access view just ignores the anthropogenic rows.

Remediations (PASSABLE) are **not** in `blocks_species`. They flow
separately via `<schema>.barriers_remediations` for the sequence-aware
`remediated_dnstr_ind`.

### 2b. The three barrier table shapes — do not confuse them

| Shape | Example | Columns | Built for | Has feature id? |
|----|----|----|----|----|
| **break-spec** | `barriers_<sp>_min` | `blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree` | `frs_break_apply` (segmenting streams) | **NO** |
| **feature view** | `barriers_<sp>_unified` | `id_barrier AS barriers_<sp>_unified_id, barrier_source, blocks_species, geom, …` | `frs_network_features` (downstream walks) | **YES** |
| **persist table** | `<persist>.barriers` | `cols_barriers` shape | cross-WSG source of truth | YES (`id_barrier`) |

`barriers_<sp>_unified` is a **view over the persist `barriers` table**,
filtered `WHERE '<SP>' = ANY(blocks_species)`. Because it reads persist
(province-wide), it sees **cross-WSG** barriers — this is the link#152
fix (PARS drains through dams in PCEA/UPCE; those dams are only visible
via persist, never in PARS-local tables).

`barriers_<sp>_min` (gradient + falls, minimal-reduced) is a
**break-spec** — it has NO id column, so it **cannot** feed
`frs_network_features` / `barriers_per_sp`. (Tried in \#196; failed with
`barriers_bt_min_id does not exist`.) `barriers_per_sp` mechanically
requires the *feature view* shape.

------------------------------------------------------------------------

## 3. Access: `lnk_pipeline_access()`

Computes `<schema>.streams_access` — per-segment, per-species
accessibility plus downstream barrier-source flags. Two distinct inputs,
two distinct roles:

- **`barriers_per_sp`** — named list `sp → barriers_<sp>_access` (#200;
  was `_unified` pre-v0.40.4). Drives `has_barriers_<sp>_dnstr` (is a
  blocking *natural* barrier downstream for this species,
  override-applied). This is **accessibility** — feeds `accessible` in
  mapping_code. NATURAL-only + override-filtered + user_definite (§5) —
  dams are NOT here. Each table’s feature id is derived as `<table>_id`
  and passed to `frs_network_features`.
- **`barrier_sources`** — named list of source-typed feature tables
  (`anthropogenic`, `pscis`, `dams`, `remediations`). Drives the
  `has_barriers_<source>_dnstr` / `dam_dnstr_ind` /
  `remediated_dnstr_ind` flags. This is **classification** (what *kind*
  of barrier is downstream), NOT accessibility. Feeds token2
  (DAM/MODELLED/ASSESSED/…).

The output flag columns
(`has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`,
`dam_dnstr_ind`, `remediated_dnstr_ind`) MUST be persisted — see §6
gotcha.

------------------------------------------------------------------------

## 4. mapping_code tokens: `lnk_pipeline_mapping_code()`

Token format:
`{ACCESS|SPAWN|REAR|""};{NONE|DAM|MODELLED|ASSESSED|REMEDIATED}[;INTERMITTENT]`

For each species, per segment (`lnk_pipeline_mapping_code.R:~196-289`):

    accessible = !has_barriers_<sp>_dnstr  &  has_data        # from barriers_per_sp

    token1 (non-spawn-only):
      ACCESS  if accessible AND spawning==0 AND rearing==0     # accessible, no habitat
      SPAWN   elif spawning > 0                                # ← fires regardless of access
      REAR    elif spawning==0 AND rearing > 0                 # ← fires regardless of access
      else NA

    token2 = ifelse(accessible, mc_barrier, NA)                # ← GATED on accessible
    token3 = ifelse(accessible & intermittent, "INTERMITTENT", NA)

    mc_barrier (from barrier_sources flags, resident vs anadromous differ slightly):
      REMEDIATED if remediated_dnstr
      DAM        elif dam_dnstr
      ASSESSED   elif anthropogenic & pscis        (resident) / elif pscis (anadr)
      MODELLED   elif anthropogenic                (no pscis)
      NONE       elif no anthropogenic

Note the asymmetry: **SPAWN/REAR fire on habitat presence regardless of
accessibility**, but **token2 (the barrier descriptor) is suppressed
when the segment is inaccessible**.

`no_data` (NA `has_barriers_<sp>_dnstr`) → emit `""`. Species absent
from the WSG (via `presence`) → emit `""` for all rows.

------------------------------------------------------------------------

## 5. The per-species access set — how bcfp does it (and where link diverges)

This is THE thing to understand. Source of truth, read 2026-05-23 from
`smnorris/bcfishpass@v0.7.15` (read-only via `gh api`):

- `model/01_access/sql/model_access_bt.sql` — builds
  `bcfishpass.barriers_bt`
- `model/01_access/sql/load_streams_access.sql` — rolls per-species
  barriers downstream into `streams_access`
- `model/02_habitat_linear/sql/load_streams_mapping_code.sql` — token
  assembly

### bcfp’s `barriers_<sp>` = natural-only, species-specific, override-filtered

`barriers_bt` (the per-species set that drives accessibility) is built
as:

    ( barriers_gradient WHERE barrier_type IN ('GRADIENT_25','GRADIENT_30')   -- ≥ BT's 25% threshold
      ∪ barriers_falls
      ∪ barriers_subsurfaceflow )
      MINUS barriers with any upstream BT/salmon/steelhead OBSERVATION   -- "fish above ⟹ passable"
      MINUS barriers with any upstream confirmed HABITAT (user_habitat_classification)
      ∪ ALL barriers_user_definite                                      -- user hard barriers, never overridden

Salmon use the lower gradient classes; that’s the per-species axis.
**Dams, PSCIS, and modelled crossings are NOT in `barriers_<sp>` at
all.** They never make a segment inaccessible.

Anthropogenic barriers live in a SEPARATE axis: `streams_access` carries
both `barriers_<sp>_dnstr` (per-species access, natural+definite) AND
`barriers_anthropogenic_dnstr` / `barriers_dams_dnstr` /
`barriers_pscis_dnstr` (descriptors).
`dam_dnstr_ind = array[barriers_anthropogenic_dnstr[1]] && barriers_dams_dnstr`
— “is the next downstream anthropogenic barrier a dam?”.

### How bcfp emits `SPAWN;DAM`

mapping_code (`load_streams_mapping_code.sql`) gates the barrier token
on `barriers_bt_dnstr = array[]::text[]` (accessible) — **identical to
link’s `ifelse(accessible, mc_barrier, NA)`**. So `SPAWN;DAM` happens
when: `barriers_bt_dnstr = []` (no NATURAL barrier downstream →
accessible) AND `spawning_bt > 0` (token1 SPAWN) AND
`dam_dnstr_ind = true` (a dam is downstream → token2 DAM). The dam
doesn’t block access; it annotates it.

### Where link diverged, and how \#200/v0.40.4 fixed it

The \#196 bug was: `barriers_per_sp = barriers_<sp>_unified` = **all**
barriers (incl dams, PSCIS, modelled) WHERE species ∈ `blocks_species`
(§2a). Two wrongs, both now fixed:

1.  **Wrong content** (FIXED). It included dams/anthropogenic; bcfp’s
    `barriers_<sp>` is natural-only. Every PARS segment below a dam read
    `has_barriers_bt_dnstr = TRUE` → `accessible = FALSE` → token2
    `;DAM` suppressed → bare `SPAWN`.
2.  **No override applied** (FIXED). bcfp removes barriers with upstream
    observations / confirmed habitat. link’s `lnk_barrier_overrides`
    (`lnk_pipeline_prepare.R:519`) output `<schema>.barrier_overrides`
    fed only `lnk_pipeline_classify` (habitat), NOT the access path.

**The fix (#200/v0.40.4) — all three access inputs persisted
province-wide:**

- `barriers_per_sp` now points at `<schema>.barriers_<sp>_access`
  (`lnk_barriers_views`): feature-shaped (has-id, §2b), NATURAL only
  (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')`
  — gradient-at-species-threshold is already encoded in
  `blocks_species`), MINUS the override (anti-join `barrier_overrides`),
  with `USER_DEFINITE` override-exempt. Dams stay in `barrier_sources` →
  token2 only.
- `user_barriers_definite` is now a `USER_DEFINITE` family in
  `lnk_barriers_unify` (persist `barriers`), ltree-resolved via the same
  FWA join the FALLS branch uses (mirrors bcfp
  `barriers_user_definite.sql`).
- `barrier_overrides` is now persisted province-wide
  (`<persist>.barrier_overrides`, `lnk_persist_init` +
  `lnk_pipeline_persist`). Because the access view reads persist
  (cross-WSG) barriers, the override must also be province-wide so a
  natural barrier in *any* WSG a downstream walk crosses is lifted
  correctly. Persist PK is
  `(blue_line_key, downstream_route_measure, species_code, watershed_group_code)`
  — boundary-stream override positions are computed by two adjacent WSG
  runs, so WSG must be in the key.

**Provincial-accumulation property** (do not forget): a single-WSG run
only sees WSGs already in persist. PARS only emits `;DAM` once PCEA+UPCE
(which hold the Bennett/Peace Canyon dams PARS drains through) are
persisted. This is identical to bcfp’s accumulated `barriers_<sp>` and
to link’s natural-barrier persistence (link#152) — handled by the
provincial orchestrator.

**Validated (v0.40.4):** PARS BT 98.95%, LFRA BT 97.77% / CO 97.90%
per-segment vs `fresh.streams_vw_bcfp`. Residual ~1-2% is token1
habitat-presence (`ACCESS`↔︎`SPAWN`/`REAR`, dimensions/rules), not the
dam-access fix.

What does **NOT** work (rejected during \#196): `barriers_<sp>_min`
(break-spec, no id, §2b) — its *content* (gradient+falls) is close, but
it cannot feed `frs_network_features`.

### Does dam blocking “depend on species”? (recurring question)

Two senses, keep them apart:

- **Access (does a dam make a segment inaccessible):** NO — confirmed
  across both bcfp models (`model_access_bt.sql` uses `GRADIENT_25/30`;
  `model_access_ch_cm_co_pk_sk.sql` uses `GRADIENT_15/20/25/30`). **No
  species’ access set contains dams.** Accessibility *is*
  species-specific, but via two levers that **already live in
  `parameters_fresh.csv`** — you do NOT add dam rules to match bcfp:
  - `access_gradient_max` → gradient class per species (salmon 0.15, BT
    0.25).
  - `observation_threshold` / `observation_date_min` /
    `observation_species` → the override. These match bcfp exactly: BT
    row = threshold 1, date 1900, species `BT;CH;CO;SK;PK;CM;ST` (bcfp:
    ≥1 obs, BT+salmon+steelhead, “passable by salmon ⟹ passable by BT”);
    CH row = threshold 5, date 1990, species `CH;CM;CO;PK;SK` (bcfp: \>5
    obs since 1990). The rules exist and are species-specific; they’re
    just not wired into `lnk_pipeline_access` yet.
- **Descriptor (token2):** YES, species-class-specific and already in
  link — resident (`mcbi_r`: next-downstream-dam, sequence-aware via
  `dam_dnstr_ind`) vs anadromous (`mcbi_a`: any dam downstream via
  `barriers_dams_dnstr`).

**Extend-vs-reproduce fork — “dam override”:** many CABD dams exist on
paper but are passable (decommissioned, partial, fishway-equipped, or
fish demonstrably above). The *general* version of this — let a dam be
overridden out of the relevant set by evidence — should **reuse the
existing override machinery** (`lnk_barrier_overrides`: observations /
confirmed habitat / control), NOT a bespoke fishway-passability model.
The CABD `passability_status` mapping already drops `Passable` dams
(`barrier_status='PASSABLE'`); “dam override” extends the same
evidence-based rules to the rest. Call it **dam-override** (the
situation varies — fishway is just one case; the name shouldn’t bake in
the mechanism). This is a **departure from bcfp** (bcfp keeps all dams
as descriptors and never overrides them per-species) and an opt-in axis
— it breaks the exact-reproduction bar (CLAUDE.md), so decide
deliberately: match bcfp first (wiring fix above), then layer
dam-override on the same rules engine.

### Validation WSGs (dam-influenced)

bcfp dams by WSG (from `fresh.crossings_vw_bcfp`): the canonical dam +
anadromous-above test is **LFRA** (Lower Fraser) — Coquitlam, Alouette,
Stave Falls, Ruskin dams, all classic sockeye-reintroduction-above-dam
cases where the observation override drives above-dam access. **PARS**
(resident/BT, drains through Bennett=PCEA / Peace Canyon=UPCE) covers
the resident flavor. Validate the access fix on **PARS + LFRA together**
— resident + anadromous, two dam systems, exercises both
`mcbi_r`/`mcbi_a` paths.

### Design implication: `blocks_species` is probably the wrong abstraction

bcfp has no binary “blocks_species” predicate. It keeps two orthogonal
axes: **natural access** (per-species, gradient-typed,
observation/habitat-overridden) and **anthropogenic descriptor**
(dam/pscis/modelled, passability-typed). link’s `blocks_species text[]`
collapses both into one set computed once at unify time — which (a)
bakes dams into access wrongly, and (b) loses the override (computed
later). A redesign that carries barrier *ingredients* (type, gradient
class, passability, fishway) and classifies access *late and
per-context* — the way fresh’s `label` / `label_block` gradation already
allows — is the abstract-system direction. Not yet scoped; candidate
issue.

------------------------------------------------------------------------

## 6. Gotchas that have cost real time

- **Persist column changes are a matched pair.** Adding a column to
  `streams_access` / `streams_mapping_code` means editing **two
  independently constructed sites**: the CREATE TABLE DDL in
  `lnk_persist_init.R` *and* the INSERT projection in
  `lnk_pipeline_persist.R`. The DDL having the column does NOT make the
  INSERT populate it — they don’t share a projection. Missing the
  source-flag generator in the INSERT was the v0.40.3 `NONE`-token bug.
  Verify DDL + INSERT together against live data.
- **Tunnel-free build, tunnel-only diff.** The *build* (pipeline_run +
  mapping_code) needs **no tunnel** — gradient/falls are local,
  cross-WSG dams come from persist. The bcfp tunnel (`localhost:63333`)
  is needed ONLY for the parity *diff*, and it’s flaky. Prefer the local
  snapshot (`fresh.streams_vw_bcfp`) over the live tunnel for comparison
  — it’s tunnel-free and reproducible. The tunnel will be retired.
- **Redo the snapshot weekly.** bcfp rebuilds Tuesdays (`bcfishpass.log`
  → `model_run_id`, `model_version`).
  `bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force` (PG\* env →
  local docker fwapg) refreshes both link’s inputs AND `fresh.*_vw_bcfp`
  for comparison. Tunnel-free (public sources: BCDC, CABD, bchamp
  objectstore, s3://newgraph).
- **`snapshot_bcfp.sh --with-bcfp-views` silently ships no streams.**
  The `bcfishpass.streams_vw.fgb.zip` on s3 is ~1.6 GB and won’t stream
  through `ogr2ogr /vsizip//vsicurl` — the gzip read dies mid-file
  (`decompression failed z_err=-1`). Worse: **ogr2ogr exits 0** on this
  premature termination, so the snapshot’s `set -euo pipefail` doesn’t
  catch it and the script reports success with only `crossings_vw_bcfp`
  loaded (the small view streams fine). The parity-critical streams
  comparison data is just missing. Fix when touched: download the zip
  with `curl` first, `unzip`, then `ogr2ogr` from the local `.fgb`; and
  verify a row count post-load rather than trusting the exit code. Until
  then, `streams_vw_bcfp` parity needs the ~1.6 GB download or the
  tunnel.
- **Don’t persist from a half-built working schema.**
  `lnk_pipeline_persist` DELETE-WHERE-WSGs the persist tables before
  INSERT — running it against an incomplete working schema wipes good
  province-wide data for that WSG.
- **Double-persist wall time.** `mapping_code = TRUE` currently
  pre-persists barriers (for cross-WSG views) *and* persists at the end
  → PARS ~16 min vs ~3.5 min normal. Pre-persisting only barriers (not
  streams+habitat) is the open optimization (#196 Phase 5).
- **`pkill <R client>` does NOT cancel its Postgres query — the backend
  orphans.** Caught 2026-05-25 (link#205): a killed recompute left a
  `frs_network_features` SELECT running 1h45m server-side, holding a
  lock on `barriers_bt_access`; every later `lnk_barriers_views`
  `DROP VIEW` blocked behind it indefinitely (silent hangs). The R
  client died; the libpq backend did not. **Always terminate the
  server-side backend**
  (`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='active' …`),
  not just the client. And **set `statement_timeout` + `lock_timeout` on
  any long-running DB op**
  (`SET statement_timeout = '600000'; SET lock_timeout = '60000'`) — a
  runaway cancels server-side instead of orphaning, and a blocked DROP
  VIEW fails fast instead of wedging. `data-raw/wsg_recompute_one.R`
  sets these on its conn for exactly this reason.
- **AOI-scoping streams to a VIEW (not a real table) makes the planner
  pick the wrong join driver.** Caught 2026-05-25 (link#205): scoping
  `fresh.streams` to one WSG via `CREATE VIEW … WHERE wsg = 'FINA'` left
  Postgres with no small-table stats; it picked the ~800k-row
  `barriers_bt_access` as the outer driver of `frs_network_features`’s
  nested loop, blowing the cost up by ~1000× (estimated 71M result rows,
  \>10 min wall). Solution: materialize as a real `CREATE TABLE` with an
  `id_segment` btree + ltree GiST + blue_line_key + `ANALYZE`. Then the
  planner picks the 26k-row AOI streams as outer and the walk takes
  ~10s. Mirrors the full pipeline’s working schema (also a real, indexed
  table).
- **`id_segment IN (…)` is cartesian against the persist schema**
  (link#203). `id_segment` is unique per WSG, not globally; a query like
  `SELECT * FROM <persist_access> WHERE id_segment IN (SELECT id_segment FROM <streams> WHERE wsg = aoi)`
  matches access rows from every WSG that happens to share those
  id_segment values → ~N(WSGs)× duplicates. Filter by
  `watershed_group_code` directly when the table has that column.
  `lnk_mapping_code` learned this the hard way.

------------------------------------------------------------------------

## 6b. Run provenance — which config built this network? (link#127)

Every
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
writes four sidecar tables into the **persist** schema, so a network in
the DB is self-describing:

| table | grain | holds |
|----|----|----|
| `<persist>.log` | one row per run | `date_start` / `date_end`, `config_hash`, `config_drift`, link/fresh version + SHA + dirty flag, `fwapg_sha`, run args, `species[]`, `wsg_upstream[]`, bcfp baseline |
| `<persist>.log_parameters_fresh` | `(config_hash, species_code)` | **full** `parameters_fresh.csv` rows |
| `<persist>.log_dimensions` | `(config_hash, species)` | **full** `dimensions.csv` rows |
| `<persist>.log_input` | `(run_id, table_name)` | per-primitive row count, size, last-analyze, source |

Read it with `lnk_log_read(conn, cfg, aoi = "PINE")`. Mirrors
`bcfishpass.log` + its `log_parameters_*` children.

**Why full rows, not a pointer.** `observation_species = BT;DV` at
threshold 1 with no date floor is recorded *in the database*, so two
scenario runs stay distinguishable after the config file moves on. That
is the whole point — see link#236, which runs the DV-as-BT override with
and without.

**The three-state completion signal:**

| `date_end` | `notes` | meaning                                   |
|------------|---------|-------------------------------------------|
| set        | —       | success                                   |
| NULL       | set     | R error or interrupt (`on.exit` ran)      |
| NULL       | NULL    | SIGKILL / OOM / host reboot (nothing ran) |

**No backfill, ever.** A WSG in `<persist>.streams` with no `log` row
was modelled before provenance existed. That state is not recoverable
and a synthetic row would be fabricated provenance. Audit which:

``` sql
SELECT DISTINCT watershed_group_code FROM <persist>.streams
EXCEPT SELECT watershed_group_code FROM <persist>.log;
```

**Gotchas.**

- `config_hash` hashes the **observed bytes of the resolved file set**,
  not the declared `provenance:` block — `config.yaml` is absent from
  its own block, so a declared-set hash would be blind to
  `pipeline$schema`, `break_order` and `gradient_classes`.
  `config_drift` is the separate “did it match what it claimed” axis.
- `log_input` never runs `count(*)`. Row counts are `pg_class.reltuples`
  estimates (`row_count_estimated = TRUE`); exact counts on a 4.9M-row /
  9.8 GB table across a provincial pass would add hours.
- **`bcdata.log` covers only `bc2pg` downloads — not FWA.** The stream
  network is loaded by fwapg’s own `load.sh` from bchamp objectstore
  parquet, and `pg_stat_user_tables` for it is empty (bulk-restored,
  never analyzed). Its only real provenance is `fwapg_sha`, resolved
  from `FWAPG_GIT_SHA` or a `.git` walk of `FWAPG_DIR`. Teaching
  `snapshot_bcfp.sh` to stamp load events is the open follow-up that
  fills `log_input.source_at`.
- `log` and `log_input` carry `watershed_group_code` so
  `schema_consolidate.R` auto-discovers them; `log_parameters_fresh` /
  `log_dimensions` deliberately do not (they key on `config_hash`), so
  **they do not yet travel between hosts** — follow-up PR.

**Guard notes (link#227).** `notes` may carry a downstream-guard record:
`link#227 guard(override): 3 unmodelled downstream dam(s) — PCEA(1), UPCE(2) — <justification>`
or `guard(warn): … at open`. Cross-check against the same row’s
`wsg_upstream`, which independently records what was persisted when the
run opened. See §8c.

**Env vars:** `LNK_RUN_UID` / `LNK_RUN_LABEL` (identify a dispatch — see
§6c), `LINK_GIT_DIRTY` / `FRESH_GIT_DIRTY` (dirty-tree flag for
installed packages), `FWAPG_GIT_SHA` / `FWAPG_DIR`,
`LNK_BCFP_MODEL_VERSION` (bcfp reference pin), `LNK_BCFP_BASELINE`
(ledger path override), `LNK_HOST_ALIAS` (host name in provenance rows),
`LNK_LOG=0` (skip recompute logging — benchmarks only).

------------------------------------------------------------------------

## 6c. Run identity and the recompute log (link#262)

### Three identifiers, and they answer different questions

| column | scope | who mints it |
|----|----|----|
| `run_id` | **one per WSG** — the log’s PK. A 217-WSG dispatch mints 217. | `.lnk_run_id()`, per [`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md) call |
| `run_uid` | **one per dispatch** — every host, every WSG of one run share it | `study_area_run.sh`, once, before anything forks |
| `run_label` | operator free text (`--run-label=`) | the operator; **never assume it is unique** |

Before this, “everything from the 2026-08-31 run” was answerable only by
a time window plus a host list — fragile at 34 WSGs on three hosts,
ambiguous the moment two runs overlap. Now:

``` r

lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1")                    # modelling
lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1", phase = "recompute")
```

`run_uid` **overrides `latest`**: the question is “every row of this
run”, and `DISTINCT ON` would hide a WSG re-run inside the same
dispatch.

`RUN_UID` is deliberately **not** host-prefixed (unlike `run_id`) — all
hosts sharing one value is the entire point. Do not “fix” it by adding a
host prefix. The random suffix is not decoration either: two dispatches
started in the same second, which a re-run after a failure makes
routine, would otherwise merge.

**Both legs or nothing.** The driver exports `LNK_RUN_UID`,
`LNK_RUN_LABEL` and `LNK_BCFP_MODEL_VERSION` to the local `Rscript` loop
*and* inside the cypher ssh command string. An export in the
dispatcher’s environment does not cross ssh, so setting only the local
one lands the id on the dispatcher’s WSGs and NULL on every cypher’s — a
half-labelled run that looks fine until someone queries it. This is the
same trap `LNK_GUARD_DOWNSTREAM` hit in §8c.

### `<schema>.log_recompute`

`data-raw/wsg_recompute_one.R` rewrites `streams_access` and
`streams_mapping_code` — **the values that ship** — and until \#262
recorded nothing, so `log` said when a WSG was *modelled* and nothing
about when its persisted access last *changed*.

Its own table, not a `phase` column on `log`, because a recompute row in
`log` would win
[`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md)’s
`DISTINCT ON` and be returned as “what produced this network”, which it
did not. It carries `watershed_group_code`, so `schema_consolidate.R`
auto-discovers it with no list to maintain.

**Deliberately absent:** `log_input` rows (the recompute reads persisted
tables, not DB primitives) and the `bcfp_*` columns (it does not touch
the reference). Issue \#262 asked for “the same provenance columns”;
this is a considered deviation, not an oversight.

**It never runs DDL.** The table is created by
[`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md),
by every modelling run, and once by `study_area_run.sh` immediately
before the pool — that last one covers the case where every dispatcher
WSG species-skips and no modelling run ever happens, which would
otherwise hard-stop all N recomputes at the end of a paid run.
`.lnk_log_recompute_start()` asserts presence instead.

**`LNK_LOG=0`** suppresses the row. `recompute_sweep.sh` and
`recompute_parity.sh` set it: they re-run the same WSG set to measure
the pool, and their rows would be indistinguishable from a real
post-consolidate recompute — so the verify script’s model-vs-recompute
check would pass on benchmark noise.

**Known exposure:** `schema_consolidate.R` DELETEs its bucket from every
discovered table before COPYing. `log_recompute` is populated *after*
consolidate, so a second or resumed consolidate over the same bucket
will wipe those rows. Re-run the recompute if that happens.

### The bcfp reference pin, tunnel-free

`bcfp_model_run_id` / `bcfp_model_version` were NULL on all 37 rows of
the first provenanced run. Not because nothing wrote them —
`.lnk_bcfp_log_current()` has been called at run open since \#127 — but
because it queries `bcfishpass.log`, and the local docker fwapg holds
**zero** `bcfishpass` tables. The run is tunnel-free by design.

The reference is not the tunnel either: it is `fresh.streams_vw_bcfp`, a
local snapshot, and `snapshot_bcfp.sh` already records the build it
loaded in `data-raw/logs/bcfp_baselines.csv`. Querying a live
`bcfishpass.log` at compare time would name the build the tunnel is at
*now* — it rebuilds weekly — not the one the numbers were computed
against. **A wrong pin, not a missing one.**

Three tiers, and `bcfp_pin_source` records which answered:

| tier | source | when |
|----|----|----|
| `env` | `LNK_BCFP_MODEL_VERSION` | every host of a driver run |
| `db` | `bcfishpass.log` | a real bcfp connection (the tunnel) |
| `ledger` | `bcfp_baselines.csv`, this host’s latest row | local, hand-invoked |

Tier 0 exists because the ledger is **per host** and a cypher has no row
of its own — it git-resets the repo, so the file is present, but it
never snapshots under its own hostname. Without the export every cypher
row lands unpinned: 13 of 34 last field run, the majority at 217. Same
shape, same fix, as `FWAPG_GIT_SHA`.

**`bcfp_model_run_id` stays NULL on the tunnel-free path and that is
correct.** `log.json` carries no such key. Honest absence beats a
fabricated id — do not “fix” it, and do not assert it in a verify
script.

### Verifying a run

``` bash
psql -h localhost -p 5432 -U postgres -d fwapg -v ON_ERROR_STOP=1 \
     -v run_uid=<uid> -v expected_n=<N> -f data-raw/study_area_verify.sql
bash data-raw/study_area_verify_negative.sh <uid>   # proves it can fail
```

`expected_n` is supplied from **outside** on purpose. Deriving the
expected set entirely from `fresh.log` is circular: a WSG that never
produced a log row vanishes from “expected”, and that is precisely the
failure the check exists to catch. The old hardcoded 34-WSG `VALUES`
list was the wrong externality, not proof that none was needed.

Parameters reach the assertion block via `set_config`, not `:'run_uid'`
— psql does not interpolate its variables inside a dollar-quoted string.

------------------------------------------------------------------------

## 7. Where every rule lives

| Rule | File | Drives |
|----|----|----|
| Per-species gradient access threshold | `configs/<name>/parameters_fresh.csv` → `access_gradient_max` | gradient `blocks_species` (§2a) |
| Per-species observation override | `parameters_fresh.csv` → `observation_*` | barrier-skip via observations; feeds habitat (`lnk_pipeline_classify`) AND access (anti-join in `barriers_<sp>_access`, persisted as `barrier_overrides`, \#200) |
| Habitat dimensions (spawn/rear by gradient, channel width, lake/stream, …) | `configs/<name>/dimensions.csv` → [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md) → `rules.yaml` | `frs_habitat_classify()` (token1 habitat) |
| Species residence (resident/anadromous/spawn-only) | **hardcoded** defaults in [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md) | which mc_barrier flavor + spawn-only token1 |
| Dam / anthropogenic blocking | **nowhere** — universal `all species` in `lnk_barriers_unify` | `blocks_species` (§2a). Not rules-driven. |
| What each config column means | `configs/dictionary_dimensions.csv`, `configs/dictionary_parameters_fresh.csv` | data dictionaries — per-column type, group, default, description, and (for `parameters_fresh`) `owner` + `consumed_by` <file:line> |

### Who owns which `parameters_fresh` column

**Do not re-derive this.** `parameters_fresh.csv` is co-owned, and the
split is settled:

- **fresh owns the 14 network-engine columns** — `species_code`,
  `access_gradient_max`, the two `*_gradient_min`, and the nine
  `cluster_*`. fresh ships them in its own
  `inst/extdata/parameters_fresh.csv`; link’s bundles are seeded from
  it.
- **link owns the 5 `observation_*` columns** — fish-passage
  interpretation (counts, thresholds, date windows, species pooling,
  control veto).

The boundary was decided in
[fresh#129](https://github.com/NewGraphEnvironment/fresh/issues/129)
(shipped fresh 0.12.7), which *removed* `observation_*` from fresh after
fresh#69 had added them: “fish passage interpretation belongs in link,
not the network engine.” Values may diverge freely per bundle — link
tunes them — but the **column set** is contractual.

Enforced in two places, both of which read
`dictionary_parameters_fresh.csv`’s `owner` column rather than
hardcoding the rule: `data-raw/audit_configs.R` §3b (pre-trifecta gate)
and `tests/testthat/test-dictionaries.R` (runs in CI, since `data-raw/`
is `.Rbuildignore`d). Direction of travel is opposite for the two shared
artifacts: `rules.yaml` flows **link → fresh** (link owns the generator,
[`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md));
the `parameters_fresh` column schema flows **fresh → link**.

Three gaps worth knowing: **species residence** is hardcoded (data-drive
is follow-up \#189), **dam blocking is not rules-driven** at all
(universal), and `rear_gradient_min` is carried in the schema but **read
by no code in either package** — it is fresh-owned, so removing it is a
fresh-side call. If dam blocking should ever become species-specific,
it’s a new per-source-per-species column + `lnk_barriers_unify` change —
not a tweak.

------------------------------------------------------------------------

## 8b. Drainage closure: never hand-roll it from ltree

**Use `lnk_wsg_resolve(cfg, loaded, wsgs, conn = conn)`.** It delegates
to
[`fresh::frs_wsg_drainage()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_drainage.html)
(fresh \>= 0.33.0), which tests per-group outlet **points**
(`blue_line_key` + `downstream_route_measure`) with the measure-aware
`whse_basemapping.fwa_downstream()`.

**Do not** compute closure from `wscode_ltree` ancestry
(`a.outlet @> b.outlet`). That was the pre-#227 method and it silently
over-includes, because **two watershed groups on the same stream share
an outlet code** — so `@>` is true in *both* directions and calls each
one downstream of the other. Closure is measure-aware, not code-aware.
This is why `c("PARS","BULK")` dropped from 15 WSGs to 9 when \#238
adopted fresh 0.33.0.

**Worked example — the Kootenay, where it bites hardest.** FWA carries
the whole river under one continuous `wscode_ltree = 300.625474`,
including the stretch that leaves BC near Newgate, runs through Montana
and Idaho, and re-enters at Creston. Measures chain with no gap:

    LARL 0–130 → KOTL 130–431,808 → BULL 431,808–495,206 → SMAR 495,206–608,735 → KOTR 608,735–773,149

So KOTR/SMAR/BULL are **upstream** of Kootenay Lake, reached via the US
loop — but an ltree test sees them sharing KOTL’s outlet code and
reports them as downstream. The correct closure of
`c("LARL","KOTL","SLOC")` is **just those three**: LARL is the terminal
BC group (it holds the Kootenay’s mouth at Castlegar and the Columbia
down to the border — hence Waneta and Seven Mile sitting in it), and
below it is the United States.

**`public.wsg_outlet` is gone as a concept** (#227). If you find the
table in a database it is a leftover from before fresh 0.33.0 — it still
answers queries, and it answers them wrongly. Outlets now ship in fresh
at `inst/extdata/wsg_outlet.csv` and reach the DB as a `VALUES` list; no
table is needed anywhere.

## 8c. Downstream state: the guard, and why membership ≠ path

[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
computes accessibility from the **already-persisted** barriers of the
WSGs downstream. Model a WSG before them and the access query finds no
downstream dams, marks dammed-off segments accessible, and **exits 0** —
a wrong answer indistinguishable from a right one.
[`lnk_wsg_downstream_check()`](https://newgraphenvironment.github.io/link/reference/lnk_wsg_downstream_check.md)
(link#227) verifies that precondition instead of trusting it.

**The predicate is PATH, not membership.** The question is not “does a
downstream watershed group *contain* a blocking dam” but “is there a
blocking dam **on this WSG’s downstream flow path**”. Measured live:

| focal | membership | path | reality |
|----|----|----|----|
| **BULK** | fires — 18 blocking dams across LSKE/KISP/KLUM | **0** | none are below BULK’s outlet |
| **PARS** | fires | **3** | Peace Canyon, Site C, W.A.C. Bennett — correct |
| SLOC | fires | 1 | Brilliant Dam — correct |

A membership guard cries wolf on BULK, operators learn to reach for the
override, and the guard stops meaning anything. **Do not “simplify” it
back.** The path form is complete, not merely cheaper: access walks
downstream from every segment, and every focal segment exits through the
focal outlet, so the out-of-WSG barriers reachable from *any* focal
segment are exactly those below the outlet. ~0.5 s.

**What counts as blocking** — three filters that live downstream of
`.lnk_pipeline_prep_dams`, all mirrored by the guard:
`passability_status_code IN (1,2)`; a real `linear_feature_id` join; and
`blue_line_key = watershed_key` (mainstem only). The psc filter is why
the `cabd_additions` US placeholders never appear — they carry NULL.

**Persistence is checked per DAM, not per WSG** — `.lnk_wsg_persisted()`
cannot tell a group persisted with `dams = FALSE`, which would pass a
schema holding the streams but not the barriers.

**Modes.** `LNK_GUARD_DOWNSTREAM=error` (default) \| `warn` \| `ignore`.
`study_area_run.sh` exports **`warn` on both legs** (local subshell
*and* inside the ssh string) because on a multi-host run a downstream
group is legitimately mid-flight on another cypher. That is a deferral,
not a hole: `wsg_recompute_one.R` re-runs the guard in `error` mode
after consolidate, when everything must be persisted. A hard pre-flight
there would be worse than the bug — per-WSG failures soft-fail, so the
WSG would be **skipped**, and `lnk_access(merge = TRUE)` cannot repair a
WSG that was never modelled.

**Override** requires a written justification
(`LNK_GUARD_DOWNSTREAM_NOTE`); a bare `TRUE` is rejected. The note lands
in `<persist>.log.notes` beside `wsg_upstream`, so
[`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md)
reports that the network was built on a stated assumption.

**Known bound:** inherits `frs_wsg_drainage()`’s one-outlet-per-group
model. A WSG draining by two independent paths would be under-covered.

------------------------------------------------------------------------

## 8d. Pre-flight gates on a multi-host run (link#246)

A study-area run spends money and writes to a shared persist, so the
gates in `study_area_run.sh` sit in **two** blocks answering two
different questions.

**Why two, not one.** A cypher’s software is *predictable* from the
dispatcher before the cypher exists: its link comes from
`git reset --hard origin/$LINK_BRANCH`, its fresh from link’s
`DESCRIPTION`. So `preflight_local()` validates what the workers are
*going to get* — free, before the spin — and `preflight_hosts()`
confirms after prep that they got it. Predict before spend; verify
before write. Framing it as one gate forces a false choice between
checking early and checking truthfully.

`preflight_hosts()` genuinely cannot run earlier, and that is fine: it
runs before any `wsg_run_one.R` touches the persist, and a failure exits
1, which trips the EXIT trap and burns the cyphers. The loss is bounded
at spin + prep rather than a whole run of two mixed model versions
landing in one schema with no `log` table to tell them apart.

**No global bypass, on purpose.** An unconditional `--skip-preflight` is
the affordance that let this class of failure happen.
`--preflight-note="<why>"` downgrades *only* vintage and parity, and
only with a written justification — the same position
`lnk_wsg_downstream_check(override=)` takes. `--auto-install` is
remediation, not a skip: it re-runs the cyphers’ install stage (which
re-runs the fresh assertion) and re-checks exactly once.

### Three things that look like checks and are not

| looks like | actually |
|----|----|
| a provisioning tool’s `plan` proves its credential | against a zero-resource workspace it plans without contacting the provider at all. The orchestrator and the provisioner also use *separate* credentials, which expire independently. Probe each against the provider’s account endpoint. Details are infrastructure — see rtj |
| comparing `link_sha` across hosts | it is a real SHA on the `load_all` dispatcher and `NA` on every pak-installed cypher, so it can only ever fail. Key on **`repo_sha`**, read on each host from the checkout it installed from. `fresh_sha` was excluded alongside it on the grounds that it was `NA` everywhere and could only ever pass — that half was measured false on 2026-09-01 and the field is a real key since link#264 |
| `max(last_analyze)` for vintage | NULL on all ten primitives, measured. Empty in bash reads as “nothing to see”. Use `GREATEST(last_analyze, last_autoanalyze)` |

### The prep sentinel

`cypher_prep.sh` ends with a bare `=== READY`, and the umbrella greps it
**anchored** (`grep -qx`). Do not revert this to
`snapshot_bcfp.sh: complete`, which was wrong in both directions: the
snapshot emits it *before* `lnk_persist_init` runs, so a persist_init
FATAL passed the gate and WSGs ran against a half-prepped cypher; and
the snapshot’s legitimate skip-if-current path never emits it at all, so
a skipped load read as FATAL. The `-x` anchor is what stops
`=== READY (install stage only; ...)` satisfying a full-prep check.

### Two post-conditions, and why they are not optional

`schema_consolidate` DELETEs the destination bucket
(`schema_consolidate.R:272-276`) and *then* COPYs (`:313-316`). A host
that produced nothing therefore does not merely fail to add rows — it
**removes** the rows already there for those WSGs and returns
`ok = TRUE`. So:

- before consolidate, every host must account for its whole bucket
  (`[wsg_run_one] … done|SKIP` lines counted against the bucket size);
- after consolidate, every run WSG must have rows in
  `<persist>.streams`.

The second is detection rather than prevention, and it is the one that
would have caught link#246 on day one regardless of cause.

### Host buckets are derived, not chosen

`data-raw/study_area_buckets.R` partitions the focal set into
drainage-independent components by union-find over per-WSG
`frs_wsg_drainage()` closures, then LPT-packs the components onto hosts
and writes `research/study_areas.md`. Overlapping closures would make
consolidate last-writer-wins on the shared WSGs, so the script
**asserts** disjointness. Never partition by `wscode_ltree` root — see
§8b.

------------------------------------------------------------------------

## 8. Fast verification recipes

``` bash
# What does bcfp emit for a WSG's mapping_code (local snapshot, no tunnel)?
docker exec fresh-db psql -U postgres -d fwapg -c \
  "SELECT mapping_code_bt, count(*) FROM fresh.streams_vw_bcfp
   WHERE watershed_group_code='PARS' GROUP BY 1 ORDER BY 2 DESC;"

# What does link emit (after a mapping_code=TRUE run)?
docker exec fresh-db psql -U postgres -d fwapg -c \
  "SELECT mapping_code_bt, count(*) FROM fresh_default.streams_mapping_code
   WHERE watershed_group_code='PARS' GROUP BY 1 ORDER BY 2 DESC;"

# Inspect a barrier view's shape / blocks_species
docker exec fresh-db psql -U postgres -d fwapg -c \
  "SELECT pg_get_viewdef('fresh_default.barriers_bt_unified', true);"

# Single-WSG tunnel-free build (the headline path)
bash data-raw/wsgs_run_m4_offline.sh --wsgs=PARS --config=default \
  --schema=fresh_default --force --mapping-code
```

Local docker fwapg:
`host=localhost port=5432 dbname=fwapg user=postgres password=postgres`
(compose at `~/Projects/repo/fresh/docker/`).
