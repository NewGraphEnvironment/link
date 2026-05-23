# link RUNBOOK — how the system actually works

Durable mental model of link's barrier → access → mapping_code machinery.
Written because the data flow spans ~8 R files and gets re-derived from scratch
every session (especially after context compaction). Read this first.

For *what's shipped* and *conventions*, see `CLAUDE.md`. This doc is the
*mechanics*: what feeds what, where each rule lives, and the gotchas that have
bitten us. When the mechanics change, update this file in the same commit.

---

## 1. The big picture

link reproduces bcfishpass's per-segment, per-species habitat + connectivity
classification, tunnel-free, for any watershed group (WSG) or AOI.

```
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
```

The **working schema** is per-WSG scratch. The **persist schema** is
province-wide and cross-WSG — this is what QGIS, comparisons, and the
mapping_code views read. Persisting is idempotent per WSG (DELETE-WHERE-WSG +
INSERT).

---

## 2. Barriers: the heart of it

### 2a. `blocks_species` — the per-segment blocking predicate

`lnk_barriers_unify()` consolidates four barrier families into
`<schema>.barriers`, each row carrying a **`blocks_species text[]`** column.
`lnk_pipeline_access` later asks `WHERE 'BT' = ANY(blocks_species)`.

**The blocking rule depends on the barrier family — this is the single most
important table in the system:**

| Family | Source table | `blocks_species` | Species-specific? |
|---|---|---|---|
| **Gradient** | `gradient_barriers_raw` | species where `access_gradient_max ≤ gradient_class/100` | **YES** — from `parameters_fresh.csv` |
| **Anthropogenic** (PSCIS, **CABD dams**, modelled crossings) | `crossings WHERE barrier_status IN ('BARRIER','POTENTIAL')` | **ALL species** (universal) | **NO** |
| **Falls** | `falls` | ALL species | NO |
| **Subsurface flow** | `barriers_subsurfaceflow` (opt-in) | ALL species | NO |

Gradient classes (`gradient_barriers_raw.gradient_class`, basis points) map to
fractional thresholds via `.lnk_classes_bcfp` (`lnk_pipeline_prepare.R`):
`1500→0.15, 2000→0.20, 2500→0.25, 3000→0.30`. A class blocks species `s` when
`class_value ≥ s$access_gradient_max`. BT's `access_gradient_max` is 0.25, so a
2500-class gradient blocks BT; CH/CO/SK at 0.15 are blocked from 1500 up.

**Key consequence: dams block *all* species universally.** There is no
per-species dam rule in any config file. A dam (CABD, via the anthropogenic
family) gets `blocks_species = {all species}`. **This is the #196 bug.** bcfp
does NOT put dams in the per-species *access* set at all (§5) — they're a
downstream *descriptor*, not an accessibility barrier. link conflating the two
in `blocks_species` is the root cause; see §5 for the authoritative bcfp
mechanism and the fix shape.

Remediations (PASSABLE) are **not** in `blocks_species`. They flow separately
via `<schema>.barriers_remediations` for the sequence-aware `remediated_dnstr_ind`.

### 2b. The three barrier table shapes — do not confuse them

| Shape | Example | Columns | Built for | Has feature id? |
|---|---|---|---|---|
| **break-spec** | `barriers_<sp>_min` | `blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree` | `frs_break_apply` (segmenting streams) | **NO** |
| **feature view** | `barriers_<sp>_unified` | `id_barrier AS barriers_<sp>_unified_id, barrier_source, blocks_species, geom, …` | `frs_network_features` (downstream walks) | **YES** |
| **persist table** | `<persist>.barriers` | `cols_barriers` shape | cross-WSG source of truth | YES (`id_barrier`) |

`barriers_<sp>_unified` is a **view over the persist `barriers` table**, filtered
`WHERE '<SP>' = ANY(blocks_species)`. Because it reads persist (province-wide),
it sees **cross-WSG** barriers — this is the link#152 fix (PARS drains through
dams in PCEA/UPCE; those dams are only visible via persist, never in PARS-local
tables).

`barriers_<sp>_min` (gradient + falls, minimal-reduced) is a **break-spec** — it
has NO id column, so it **cannot** feed `frs_network_features` /
`barriers_per_sp`. (Tried in #196; failed with `barriers_bt_min_id does not
exist`.) `barriers_per_sp` mechanically requires the *feature view* shape.

---

## 3. Access: `lnk_pipeline_access()`

Computes `<schema>.streams_access` — per-segment, per-species accessibility plus
downstream barrier-source flags. Two distinct inputs, two distinct roles:

- **`barriers_per_sp`** — named list `sp → barriers_<sp>_unified`. Drives
  `has_barriers_<sp>_dnstr` (is a blocking barrier downstream for this species).
  This is **accessibility** — feeds `accessible` in mapping_code. Each table's
  feature id is derived as `<table>_id` and passed to `frs_network_features`.
- **`barrier_sources`** — named list of source-typed feature tables
  (`anthropogenic`, `pscis`, `dams`, `remediations`). Drives the
  `has_barriers_<source>_dnstr` / `dam_dnstr_ind` / `remediated_dnstr_ind`
  flags. This is **classification** (what *kind* of barrier is downstream), NOT
  accessibility. Feeds token2 (DAM/MODELLED/ASSESSED/…).

The output flag columns (`has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`,
`dam_dnstr_ind`, `remediated_dnstr_ind`) MUST be persisted — see §6 gotcha.

---

## 4. mapping_code tokens: `lnk_pipeline_mapping_code()`

Token format: `{ACCESS|SPAWN|REAR|""};{NONE|DAM|MODELLED|ASSESSED|REMEDIATED}[;INTERMITTENT]`

For each species, per segment (`lnk_pipeline_mapping_code.R:~196-289`):

```
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
```

Note the asymmetry: **SPAWN/REAR fire on habitat presence regardless of
accessibility**, but **token2 (the barrier descriptor) is suppressed when the
segment is inaccessible**.

`no_data` (NA `has_barriers_<sp>_dnstr`) → emit `""`. Species absent from the WSG
(via `presence`) → emit `""` for all rows.

---

## 5. The per-species access set — how bcfp does it (and where link diverges)

This is THE thing to understand. Source of truth, read 2026-05-23 from
`smnorris/bcfishpass@v0.7.15` (read-only via `gh api`):

- `model/01_access/sql/model_access_bt.sql` — builds `bcfishpass.barriers_bt`
- `model/01_access/sql/load_streams_access.sql` — rolls per-species barriers
  downstream into `streams_access`
- `model/02_habitat_linear/sql/load_streams_mapping_code.sql` — token assembly

### bcfp's `barriers_<sp>` = natural-only, species-specific, override-filtered

`barriers_bt` (the per-species set that drives accessibility) is built as:

```
( barriers_gradient WHERE barrier_type IN ('GRADIENT_25','GRADIENT_30')   -- ≥ BT's 25% threshold
  ∪ barriers_falls
  ∪ barriers_subsurfaceflow )
  MINUS barriers with any upstream BT/salmon/steelhead OBSERVATION   -- "fish above ⟹ passable"
  MINUS barriers with any upstream confirmed HABITAT (user_habitat_classification)
  ∪ ALL barriers_user_definite                                      -- user hard barriers, never overridden
```

Salmon use the lower gradient classes; that's the per-species axis. **Dams,
PSCIS, and modelled crossings are NOT in `barriers_<sp>` at all.** They never
make a segment inaccessible.

Anthropogenic barriers live in a SEPARATE axis: `streams_access` carries both
`barriers_<sp>_dnstr` (per-species access, natural+definite) AND
`barriers_anthropogenic_dnstr` / `barriers_dams_dnstr` / `barriers_pscis_dnstr`
(descriptors). `dam_dnstr_ind = array[barriers_anthropogenic_dnstr[1]] &&
barriers_dams_dnstr` — "is the next downstream anthropogenic barrier a dam?".

### How bcfp emits `SPAWN;DAM`

mapping_code (`load_streams_mapping_code.sql`) gates the barrier token on
`barriers_bt_dnstr = array[]::text[]` (accessible) — **identical to link's
`ifelse(accessible, mc_barrier, NA)`**. So `SPAWN;DAM` happens when:
`barriers_bt_dnstr = []` (no NATURAL barrier downstream → accessible) AND
`spawning_bt > 0` (token1 SPAWN) AND `dam_dnstr_ind = true` (a dam is downstream
→ token2 DAM). The dam doesn't block access; it annotates it.

### Where link diverges (the #196 bug, fully characterized)

link's `barriers_per_sp = barriers_<sp>_unified` = **all** barriers (incl dams,
PSCIS, modelled) WHERE species ∈ `blocks_species` (§2a). Two wrongs:

1. **Wrong content.** It includes dams/anthropogenic. bcfp's `barriers_<sp>` is
   natural-only. So every PARS segment below a dam reads `has_barriers_bt_dnstr
   = TRUE` → `accessible = FALSE` → token2 `;DAM` suppressed → bare `SPAWN`.
2. **No override applied.** bcfp removes barriers with upstream observations /
   confirmed habitat. link HAS this logic — `lnk_barrier_overrides`
   (`lnk_pipeline_prepare.R:519`) — but its output `<schema>.barrier_overrides`
   feeds only `lnk_pipeline_classify` (habitat gating), NOT
   `lnk_pipeline_access` (mapping_code accessibility). So link's habitat token
   (SPAWN/REAR) is override-aware but its `accessible` flag is not.

Note: link's `access_<sp>` integer (`lnk_pipeline_access.R:364`,
`ifelse(blocked, 0, ifelse(observed, 2, 1))`) IS observation-aware and matches
bcfp's `access_bt` code — but mapping_code reads `has_barriers_<sp>_dnstr`, not
`access_<sp>`.

### The fix shape

`barriers_per_sp` must reproduce bcfp's `barriers_<sp>`: a **feature-shaped**
(has-id, §2b) per-species view of **natural barriers only** — gradient at the
species' threshold + falls + subsurface — with the observation/habitat override
applied and `user_barriers_definite` unioned in. Dams stay in `barrier_sources`
(token2 only). This is real work (a per-species access-barrier builder), not a
table swap. Confirm with `fresh.streams_vw_bcfp` once it loads (the snapshot's
streams view failed on a transient gzip error 2026-05-23; retry).

What does **NOT** work: `barriers_<sp>_min` (break-spec, no id, §2b) — though its
*content* (gradient+falls) is close to the right base.

### Does dam blocking "depend on species"? (recurring question)

Two senses, keep them apart:

- **Access (does a dam make a segment inaccessible):** NO — confirmed across both
  bcfp models (`model_access_bt.sql` uses `GRADIENT_25/30`;
  `model_access_ch_cm_co_pk_sk.sql` uses `GRADIENT_15/20/25/30`). **No species'
  access set contains dams.** Accessibility *is* species-specific, but via two
  levers that **already live in `parameters_fresh.csv`** — you do NOT add dam
  rules to match bcfp:
  - `access_gradient_max` → gradient class per species (salmon 0.15, BT 0.25).
  - `observation_threshold` / `observation_date_min` / `observation_species` →
    the override. These match bcfp exactly: BT row = threshold 1, date 1900,
    species `BT;CH;CO;SK;PK;CM;ST` (bcfp: ≥1 obs, BT+salmon+steelhead, "passable
    by salmon ⟹ passable by BT"); CH row = threshold 5, date 1990, species
    `CH;CM;CO;PK;SK` (bcfp: >5 obs since 1990). The rules exist and are
    species-specific; they're just not wired into `lnk_pipeline_access` yet.
- **Descriptor (token2):** YES, species-class-specific and already in link —
  resident (`mcbi_r`: next-downstream-dam, sequence-aware via `dam_dnstr_ind`)
  vs anadromous (`mcbi_a`: any dam downstream via `barriers_dams_dnstr`).

**Extend-vs-reproduce fork — "dam override":** many CABD dams exist on paper but
are passable (decommissioned, partial, fishway-equipped, or fish demonstrably
above). The *general* version of this — let a dam be overridden out of the
relevant set by evidence — should **reuse the existing override machinery**
(`lnk_barrier_overrides`: observations / confirmed habitat / control), NOT a
bespoke fishway-passability model. The CABD `passability_status` mapping already
drops `Passable` dams (`barrier_status='PASSABLE'`); "dam override" extends the
same evidence-based rules to the rest. Call it **dam-override** (the situation
varies — fishway is just one case; the name shouldn't bake in the mechanism).
This is a **departure from bcfp** (bcfp keeps all dams as descriptors and never
overrides them per-species) and an opt-in axis — it breaks the exact-reproduction
bar (CLAUDE.md), so decide deliberately: match bcfp first (wiring fix above),
then layer dam-override on the same rules engine.

### Validation WSGs (dam-influenced)

bcfp dams by WSG (from `fresh.crossings_vw_bcfp`): the canonical dam +
anadromous-above test is **LFRA** (Lower Fraser) — Coquitlam, Alouette, Stave
Falls, Ruskin dams, all classic sockeye-reintroduction-above-dam cases where the
observation override drives above-dam access. **PARS** (resident/BT, drains
through Bennett=PCEA / Peace Canyon=UPCE) covers the resident flavor. Validate
the access fix on **PARS + LFRA together** — resident + anadromous, two dam
systems, exercises both `mcbi_r`/`mcbi_a` paths.

### Design implication: `blocks_species` is probably the wrong abstraction

bcfp has no binary "blocks_species" predicate. It keeps two orthogonal axes:
**natural access** (per-species, gradient-typed, observation/habitat-overridden)
and **anthropogenic descriptor** (dam/pscis/modelled, passability-typed). link's
`blocks_species text[]` collapses both into one set computed once at unify time —
which (a) bakes dams into access wrongly, and (b) loses the override (computed
later). A redesign that carries barrier *ingredients* (type, gradient class,
passability, fishway) and classifies access *late and per-context* — the way
fresh's `label` / `label_block` gradation already allows — is the abstract-system
direction. Not yet scoped; candidate issue.

---

## 6. Gotchas that have cost real time

- **Persist column changes are a matched pair.** Adding a column to
  `streams_access` / `streams_mapping_code` means editing **two independently
  constructed sites**: the CREATE TABLE DDL in `lnk_persist_init.R` *and* the
  INSERT projection in `lnk_pipeline_persist.R`. The DDL having the column does
  NOT make the INSERT populate it — they don't share a projection. Missing the
  source-flag generator in the INSERT was the v0.40.3 `NONE`-token bug. Verify
  DDL + INSERT together against live data.
- **Tunnel-free build, tunnel-only diff.** The *build* (pipeline_run +
  mapping_code) needs **no tunnel** — gradient/falls are local, cross-WSG dams
  come from persist. The bcfp tunnel (`localhost:63333`) is needed ONLY for the
  parity *diff*, and it's flaky. Prefer the local snapshot
  (`fresh.streams_vw_bcfp`) over the live tunnel for comparison — it's
  tunnel-free and reproducible. The tunnel will be retired.
- **Redo the snapshot weekly.** bcfp rebuilds Tuesdays (`bcfishpass.log` →
  `model_run_id`, `model_version`). `bash data-raw/snapshot_bcfp.sh
  --with-bcfp-views --force` (PG* env → local docker fwapg) refreshes both
  link's inputs AND `fresh.*_vw_bcfp` for comparison. Tunnel-free (public
  sources: BCDC, CABD, bchamp objectstore, s3://newgraph).
- **`snapshot_bcfp.sh --with-bcfp-views` silently ships no streams.** The
  `bcfishpass.streams_vw.fgb.zip` on s3 is ~1.6 GB and won't stream through
  `ogr2ogr /vsizip//vsicurl` — the gzip read dies mid-file (`decompression
  failed z_err=-1`). Worse: **ogr2ogr exits 0** on this premature termination,
  so the snapshot's `set -euo pipefail` doesn't catch it and the script reports
  success with only `crossings_vw_bcfp` loaded (the small view streams fine).
  The parity-critical streams comparison data is just missing. Fix when touched:
  download the zip with `curl` first, `unzip`, then `ogr2ogr` from the local
  `.fgb`; and verify a row count post-load rather than trusting the exit code.
  Until then, `streams_vw_bcfp` parity needs the ~1.6 GB download or the tunnel.
- **Don't persist from a half-built working schema.** `lnk_pipeline_persist`
  DELETE-WHERE-WSGs the persist tables before INSERT — running it against an
  incomplete working schema wipes good province-wide data for that WSG.
- **Double-persist wall time.** `mapping_code = TRUE` currently pre-persists
  barriers (for cross-WSG views) *and* persists at the end → PARS ~16 min vs
  ~3.5 min normal. Pre-persisting only barriers (not streams+habitat) is the
  open optimization (#196 Phase 5).

---

## 7. Where every rule lives

| Rule | File | Drives |
|---|---|---|
| Per-species gradient access threshold | `configs/<name>/parameters_fresh.csv` → `access_gradient_max` | gradient `blocks_species` (§2a) |
| Per-species observation override | `parameters_fresh.csv` → `observation_*` | barrier-skip via observations |
| Habitat dimensions (spawn/rear by gradient, channel width, lake/stream, …) | `configs/<name>/dimensions.csv` → `lnk_rules_build()` → `rules.yaml` | `frs_habitat_classify()` (token1 habitat) |
| Species residence (resident/anadromous/spawn-only) | **hardcoded** defaults in `lnk_pipeline_mapping_code()` | which mc_barrier flavor + spawn-only token1 |
| Dam / anthropogenic blocking | **nowhere** — universal `all species` in `lnk_barriers_unify` | `blocks_species` (§2a). Not rules-driven. |

Two gaps worth knowing: **species residence** is hardcoded (data-drive is
follow-up #189), and **dam blocking is not rules-driven** at all (universal).
If dam blocking should ever become species-specific, it's a new
per-source-per-species column + `lnk_barriers_unify` change — not a tweak.

---

## 8. Fast verification recipes

```bash
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

Local docker fwapg: `host=localhost port=5432 dbname=fwapg user=postgres
password=postgres` (compose at `~/Projects/repo/fresh/docker/`).
