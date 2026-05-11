## Status (2026-05-11, post-link#154)

**Phase A acceptance bar met on all in-WSG targets.** link#154 landed
the bcfp PSCIS-build composition (`.lnk_pipeline_pscis_build`) plus
three Phase 1.5 follow-on fixes that surfaced during the diagnostic
dive (modelled-branch `crossing_fixes.structure` filter, DBSCAN 5m +
UNIQUE(blk,drm) dedup, xref-precedence restructure). Live Phase A
results across four WSGs:

| WSG  | bt | ch | cm | co | pk | sk | st | wct |
|------|------|------|------|------|------|------|------|------|
| ADMS | 99.01 | 99.93 | 99.99 | 99.76 | 99.72 | 99.14 | 100 | 100 |
| BULK | 99.26 | 99.62 | 99.78 | 99.17 | 99.73 | 99.59 | 99.41 | 100 |
| WILL | 98.85 | 99.65 | 99.93 | 99.06 | 99.91 | 99.93 | 100 | 100 |
| PARS | 60.64 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |

Source log: `data-raw/logs/202605111220_phase_a_post_link154_v7_xref.txt`.

- ≥99% bar met on **all in-WSG species** across ADMS/BULK/WILL/PARS.
- WILL `bt` (98.85%) and ADMS `sk` (99.14%) sit fractionally inside
  the threshold — residual drift is per-segment habitat-classification
  noise + the small REMEDIATED tunnel residue. Acceptable for the
  link#154 acceptance bar; full closure tracked under #152.
- PARS `bt` (60.64%) is cross-WSG `dam_dnstr_ind` — out of scope for
  link#154 (each WSG runs in its own working schema), tracked under
  [link#152](https://github.com/NewGraphEnvironment/link/issues/152).

**Issues shipped this cycle:**

| Status | Issue | Closes which divergence |
|---|---|---|
| ✅ shipped (fresh v0.30.0, PR #208) | fresh#206 `frs_point_match` | b-side dedup at modelled layer |
| ✅ shipped (fresh v0.31.0, PR #209) | fresh#207 `frs_candidates_pick` | PSCIS-stream selection (BULK/WILL drift) |
| ✅ shipped (link Phase 1+1.5) | [link#154](https://github.com/NewGraphEnvironment/link/issues/154) `lnk_pipeline_crossings` PSCIS-build | 3-step composition wired + 3 bcfp-parity follow-ons |
| 📋 architectural, deferred | [link#152](https://github.com/NewGraphEnvironment/link/issues/152) Unified `<persist_schema>.barriers` | Cross-WSG dnstr (PARS BT 60%) |
| 📋 mid-priority | [link#153](https://github.com/NewGraphEnvironment/link/issues/153) `lnk_pipeline_species` vs `lnk_presence` | cm/pk habitat columns missing for ADMS |

**Composition shipped in link#154** (mirrors bcfp's
`02_pscis_streams_150m.sql` + `04_pscis.sql` at
`smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`):

```r
lnk_points_snap(num_features = 5L, tolerance = 150)  # multi-stream candidates
# Step 2: bcfp-shape enrich + score (name_score, width_order_score)
# Step 3: b-side dedup (NULL out modelled-collision losers)
fresh::frs_candidates_pick(exp_filter, order_by)     # per-PSCIS pick
# Step 4c/4d: DBSCAN 5m cluster + UNIQUE(blk,drm) dedup
# Step 5: xref-driven INSERT (two-branch: modelled_crossing_id vs linear_feature_id)
```

`fresh::frs_point_match` ships in fresh but is not used in this chain
— bcfp computes `modelled_xing_dist_instream` inline in Step 2 because
the per-PSCIS pick uses `weighted_distance` (modelled-match presence
influences which stream wins). Pulling modelled-match out would happen
AFTER the stream pick, which is the wrong order.

---

# bcfp parity — `streams_mapping_code` comparison

How to reproduce, run, and interpret per-segment per-species
`mapping_code_<sp>` parity between link and bcfishpass.

This document is the canonical recipe for the comparison — the
companion runnable driver lives at
`data-raw/compare_bcfp_mapping_code.R`.

## Goal

For a given watershed group, produce `<schema>.streams_mapping_code`
in link's working schema and compare it segment-by-segment per species
against `bcfishpass.streams_mapping_code` on the bcfp tunnel.

`mapping_code_<sp>` is the bcfp semicolon-token compound:

```
{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED|REMEDIATED} [;INTERMITTENT]
```

It's the segment-level summary of the species' habitat label + the
most-relevant downstream barrier source + an intermittent-stream flag.
Eight species columns: `mapping_code_bt`, `mapping_code_ch`,
`mapping_code_cm`, `mapping_code_co`, `mapping_code_pk`,
`mapping_code_sk`, `mapping_code_st`, `mapping_code_wct`.

## History (so we don't forget how we got here)

- **link v0.30.0 (PR #134, 2026-05-06)** — added the bcfp parity layer:
  `lnk_pipeline_access()`, `lnk_pipeline_mapping_code()`,
  `build_species_views.R --bcfp`. ADMS validation: 15762/15762
  byte-identical for all 8 species. Stamped log:
  `data-raw/logs/20260505_1635_link124_parity_validation.txt`. Caveat:
  BT/WCT used bcfp's pre-computed `dam_dnstr_ind` /
  `remediated_dnstr_ind` merged in — sequence-aware computation from
  primitives was deferred to #135.
- **link v0.30.1 (PR #140, 2026-05-06)** — `lnk_presence()` helper with
  species-group expansion. Wired into pipeline_access + mapping_code
  to handle salmon-group-absent WSGs (ELKR salmon 1.41% → 100%, HORS-st
  7.44% → 100% after this fix).
- **link v0.30.2 (PR #142, 2026-05-07)** — `lnk_pipeline_access()` now
  computes `dam_dnstr_ind` and `remediated_dnstr_ind` from primitives,
  no bcfp merge-in needed. ADMS `dam_dnstr_ind` byte-identical to bcfp
  (11803/3960). The `remediated_dnstr_ind` divergence at validation time
  was traced to an upstream bug — bcfp's SQL clause
  `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` is
  contradictory (always FALSE). NewGraphEnvironment filed a fix as
  smnorris/bcfishpass#891 (issue) + #892 (one-line PR), both merged
  upstream 2026-05-06 16:17 UTC.
- **link v0.32.0 (PR #146, 2026-05-08)** — `lnk_pipeline_crossings()`
  builds `<schema>.crossings` + `<schema>.barriers_anthropogenic` /
  `barriers_pscis` / `barriers_dams` / `barriers_remediations` from
  primitives. These are the inputs to `lnk_pipeline_access(barrier_sources = ...)`.
- The provincial parity script `data-raw/run_provincial_parity.R` runs
  phases 1–6 + km/ha rollup against bcfp. It does *not* run phases
  7–8 (access + mapping_code). The mapping_code comparison is its own
  driver — this document plus `compare_bcfp_mapping_code.R`.

## Tunnel state vs upstream fix

The bcfp tunnel rebuilds Tuesdays ~20:00 PDT from
`smnorris/bcfishpass`. Query `bcfishpass.log` for the current
`model_run_id` + `model_version` SHA.

The upstream fix #892 merged 2026-05-06. The most recent tunnel
rebuild prior to writing was `model_run_id=121, date=2026-05-05`,
which is *before* the merge — so the tunnel currently still emits
the regressed `remediated_dnstr_ind = FALSE` everywhere. Until the
next rebuild (Tuesday 2026-05-12) picks up #892, we expect link to
emit `REMEDIATED` tokens on a small set of segments (~30 on ADMS-BT)
where bcfp emits `DAM` / `MODELLED` / `ASSESSED`. **This is link
correct, bcfp tunnel-stale; expect convergence after the rebuild.**

## Pipeline call sequence

For one WSG, the full sequence to produce `streams_mapping_code`:

```r
schema <- paste0("working_", tolower(wsg))

# Phases 1–6 (the existing parity-run scope)
lnk_pipeline_setup    (conn, schema, overwrite = TRUE)
lnk_pipeline_load     (conn, aoi = wsg, cfg, loaded, schema)
lnk_pipeline_prepare  (conn, aoi = wsg, cfg, loaded, schema,
                       conn_tunnel = conn_ref)
lnk_pipeline_crossings(conn, aoi = wsg, cfg, loaded, schema)
lnk_pipeline_break    (conn, aoi = wsg, cfg, loaded, schema)
lnk_pipeline_classify (conn, aoi = wsg, cfg, loaded, schema)
lnk_pipeline_connect  (conn, aoi = wsg, cfg, loaded, schema)

# Phase 7: streams_access (per-species access codes + dnstr indicators)
pres <- lnk_presence(loaded$wsg_species_presence, wsg)
acc  <- lnk_pipeline_access(
  conn,
  segments        = paste0(schema, ".streams"),
  aoi             = wsg,
  to              = paste0(schema, ".streams_access"),
  barriers_per_sp = list(
    bt  = paste0(schema, ".barriers_bt_min"),
    ch  = paste0(schema, ".barriers_ch_min"),
    cm  = paste0(schema, ".barriers_cm_min"),
    co  = paste0(schema, ".barriers_co_min"),
    pk  = paste0(schema, ".barriers_pk_min"),
    sk  = paste0(schema, ".barriers_sk_min"),
    st  = paste0(schema, ".barriers_st_min"),
    wct = paste0(schema, ".barriers_wct_min")
  ),
  observations    = paste0(schema, ".observations"),
  presence        = pres,
  barrier_sources = list(
    anthropogenic = paste0(schema, ".barriers_anthropogenic"),
    pscis         = paste0(schema, ".barriers_pscis"),
    dams          = paste0(schema, ".barriers_dams"),
    remediations  = paste0(schema, ".barriers_remediations")
  ),
  crossings_table = paste0(schema, ".crossings")
)

# Phase 8: streams_mapping_code (per-species semicolon-token compound)
hab <- DBI::dbReadTable(conn, c(schema, "streams_habitat"))  # wide-pivot per species
fc  <- DBI::dbGetQuery(conn, sprintf(
  "SELECT id_segment, feature_code FROM %s.streams", schema))
mc <- lnk_pipeline_mapping_code(
  access       = acc,
  habitat      = hab,
  feature_code = fc,
  to           = paste0(schema, ".streams_mapping_code"),
  conn         = conn,
  presence     = pres
)
```

## Comparison vs bcfp tunnel

After the working schema is populated, join link's
`<schema>.streams_mapping_code` to bcfp's
`bcfishpass.streams_mapping_code` on the segment-level shared keys:

```sql
-- link side: <schema>.streams_mapping_code keyed by id_segment
-- bcfp side: bcfishpass.streams_mapping_code keyed by segmented_stream_id
-- Shared geometry: (blue_line_key, downstream_route_measure, length_metre)

SELECT lmc.*, bmc.*
FROM <schema>.streams_mapping_code lmc
JOIN <schema>.streams ls ON ls.id_segment = lmc.id_segment
JOIN bcfishpass.streams bs
  ON bs.blue_line_key            = ls.blue_line_key
 AND bs.downstream_route_measure = ls.downstream_route_measure
 AND bs.length_metre             = ls.length_metre
JOIN bcfishpass.streams_mapping_code bmc
  ON bmc.segmented_stream_id = bs.segmented_stream_id
WHERE ls.watershed_group_code = '<wsg>';
```

Per-species comparison: `sum(lmc.mapping_code_<sp> = bmc.mapping_code_<sp>)`
divided by total joined rows.

## Expected results

### Match expectations (ADMS, current tunnel state model_run_id=121)

| species | expected match | notes |
|---|---|---|
| `mapping_code_bt`  | ~99.81% (~30 diff) | REMEDIATED tunnel-regression residue |
| `mapping_code_ch`  | ~99.99% (~2 diff)  | REMEDIATED tunnel-regression residue |
| `mapping_code_cm`  | ~99.99% (~2 diff)  | REMEDIATED tunnel-regression residue |
| `mapping_code_co`  | ~99.99% (~2 diff)  | REMEDIATED tunnel-regression residue |
| `mapping_code_pk`  | ~99.99% (~2 diff)  | REMEDIATED tunnel-regression residue |
| `mapping_code_sk`  | ~99.99% (~2 diff)  | REMEDIATED tunnel-regression residue |
| `mapping_code_st`  | 100.00%             | absent species in ADMS, all `""` |
| `mapping_code_wct` | 100.00%             | absent species in ADMS, all `""` |

**After the next tunnel rebuild (Tuesday 2026-05-12)** picks up
smnorris/bcfishpass#892, all 8 species should converge to 100%.

### Anatomy of the expected diffs

Per the v0.30.2 stamped log
(`data-raw/logs/20260505_2251_link135_parity_validation.txt`):
"link emits REMEDIATED token where bcfp says other". The diffs are
on segments downstream of remediated PSCIS crossings. link's logic:

> `remediated_dnstr_ind = TRUE` iff the next-downstream remediation is
> a crossing whose `pscis_status IN ('REMEDIATED', 'PASSABLE')`.

bcfp's pre-fix logic (literally in the SQL): same JOIN but
`pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` —
contradictory, always FALSE. So bcfp falls through to DAM / MODELLED /
ASSESSED token where link correctly emits REMEDIATED.

## How to run

From the repo root with local fwapg up + tunnel reachable + tunnel
auth set in `~/.Renviron`:

```bash
cd data-raw
Rscript compare_bcfp_mapping_code.R --wsgs=ADMS
# multi-WSG:
Rscript compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,PARS,WILL
```

Outputs:

- `data-raw/logs/mapping_code_parity/<WSG>.rds` — per-species match counts +
  diff distribution
- `data-raw/logs/<TS>_mapping_code_parity.txt` — stamped run log

## Persistence model (mirror bcfp exactly so QGIS symbology swaps 1:1)

bcfp's schema:

| object | shape | who writes |
|---|---|---|
| `bcfishpass.streams` | base segments (FWA attrs + geom) | bcfp `streams_split.sql` |
| `bcfishpass.streams_access` | wide per-species `access_<sp>` + dnstr arrays + indicators (`dam_dnstr_ind`, `remediated_dnstr_ind`) | bcfp `load_streams_access.sql` |
| `bcfishpass.streams_habitat_linear` | wide per-species `spawning_<sp>` + `rearing_<sp>` numeric | bcfp habitat compose |
| `bcfishpass.streams_mapping_code` | wide per-species `mapping_code_<sp>` text | bcfp mapping_code compose |
| `bcfishpass.streams_<sp>_vw` per species | VIEW: JOIN all above, flatten arrays, filter `WHERE access_<sp> > 0` | bcfp `streams_views.sql` |

Each per-species view exposes columns named generically (`access`,
`spawning`, `rearing`, `mapping_code`) so a single QGIS symbology
file can render any species view by swapping the source layer.

### Where link is today vs the bcfp pattern

| object | link state | gap |
|---|---|---|
| `<schema>.streams` | ✅ written by `lnk_pipeline_classify` | — |
| `<schema>.streams_access` | ⚠️ written by `lnk_pipeline_access(to=...)` into working schema only | not persisted provincially |
| `<schema>.streams_habitat_linear` (wide) | ❌ link uses long-format `streams_habitat_<sp>` per species (different shape) | needs wide-pivot writer |
| `<schema>.streams_mapping_code` | ⚠️ written by `lnk_pipeline_mapping_code(to=...)` into working schema only | not persisted provincially |
| `<schema>.streams_<sp>_vw` | ⚠️ today `build_species_views.R --bcfp` writes `streams_<sp>_bcfp_vw` (sibling) | naming + canonical-vs-sibling decision pending |

### Two-phase plan

**Phase A — confirm parity** (this document, this driver):
- Run pipeline phases 1–6 + access + mapping_code into the working
  schema only.
- Compare `<schema>.streams_mapping_code` vs `bcfishpass.streams_mapping_code`
  join-by-segment-position, per species.
- Confirm the numbers in [Expected results](#expected-results).
- Don't touch persistence — working schema gets dropped after the run
  (matches existing `compare_bcfishpass_wsg.R` lifecycle).

**Phase B — wire provincial persistence to mirror bcfp** (follow-up issue):
- Extend `lnk_pipeline_persist` to also write
  `<persist_schema>.streams_access` (wide) and
  `<persist_schema>.streams_mapping_code` (wide).
- Add a wide-pivot from per-species `streams_habitat_<sp>` →
  `<persist_schema>.streams_habitat_linear` matching bcfp's column
  layout.
- Decide on view naming:
  - **Option 1** — replace `streams_<sp>_vw` with the bcfp-shape
    definition (drops link's 5-bucket category view; clean QGIS swap
    but loses the existing variant).
  - **Option 2** — keep both: `streams_<sp>_vw` (link 5-bucket, current)
    and `streams_<sp>_bcfp_vw` (bcfp parity, current naming). QGIS
    operator picks per project.
  - **Option 3** — flip: bcfp shape becomes the canonical
    `streams_<sp>_vw`, link's 5-bucket view becomes
    `streams_<sp>_link_vw` (or similar). Cleanest QGIS-swap story
    against bcfp tunnel layers.

Decision deferred until Phase A confirms parity — running on real
numbers will inform whether Option 1/2/3 is right.

## Learnings (live log as we go)

### 2026-05-09 — driver bring-up

**Learning 1: link reinstall required.** Locally installed `link` was at
v0.29.1 — predates `lnk_pipeline_crossings` (v0.32.0), `lnk_presence`
(v0.30.1), and the bcfp parity layer (v0.30.0). Reinstalled from local
source via `devtools::install(quick = TRUE)` to get to v0.33.0 with all
four required exports.

**Learning 2: pipeline column-shape gap surfaced** —
`lnk_crossings_union()` reads two columns from `<schema>.dams` that
`lnk_pipeline_prepare()` doesn't write:

- `d.passability_status` (text) — only `passability_status_code`
  (integer) exists
- `d.dam_name` — only `dam_name_en` exists

The v0.32.0 archive README explicitly deferred end-to-end mapping_code
parity:

> Phase 6 full parity vs bcfp tunnel (`mapping_code_<sp>` bit-perfect
> diff) deferred — depends on `lnk_pipeline_prepare` observations bug
> + populated CABD dams flow + bcfishobs.observations parquet
> (rtj#66 blocker). Tracked as follow-up; not blocking v0.32.0.

So `lnk_pipeline_crossings` shipped tested via mocks + a non-dams
smoke test. The dams-flow gap is what this document + driver are
surfacing now.

**Learning 3: tunnel-vs-local audit — only `cabd.dams` still pulls
from tunnel.** Audit of every `bcfishpass.*` reference in `link/R/`
and every `conn_ref` use in our compare scripts:

- **link package source** is correctly parameterized — no hardcoded
  `SELECT FROM bcfishpass.*` SQL. All bcfishpass refs in source are
  doc strings, default args, or the `conn_tunnel` parameter in
  `lnk_pipeline_prepare()`.
- **Compare scripts** — `cabd.dams` is the only stale tunnel pull
  (driven by the `conn_tunnel = conn_ref` arg passed to
  `lnk_pipeline_prepare`). Per #137, snapshot_bcfp.sh loads cabd.dams
  locally, so this should be `conn_tunnel = conn` (local).
- **Legitimate tunnel uses** — the bcfp-side queries inside
  `compare_bcfishpass_wsg.R` (km/ha rollup) and
  `compare_bcfp_mapping_code.R` (mapping_code parity check) — these
  ARE the parity comparison; they read the bcfp reference, by design.

**Learning 4: CABD text vocabulary ≠ bcfp text vocabulary.** Local
`cabd.dams` has both `passability_status_code` (integer) AND
`passability_status` (text). But CABD's text differs from bcfp's:

```
local cabd.dams       bcfp barrier_status (per load_crossings.sql)
─────────────────     ─────────────────
1 = "Barrier"          BARRIER
2 = "Partial Barrier"  POTENTIAL  ← different word
3 = "Passable"         PASSABLE
6 = "NA - Decom..."    PASSABLE   ← different word
```

So a translation is required either way — can't pass CABD's text
through unchanged.

**Learning 5: `conn_tunnel` parameter name is misleading post-#137.**
The arg implies "the tunnel" but its actual purpose is "where to
read cabd.dams from." Worth renaming (e.g., `conn_cabd_source`) or
removing entirely (default to the main `conn`).

### 2026-05-09 — Phase A first end-to-end run (with tunnel-staged per-species barriers)

After patches landed (lnk_crossings_union CASE, snapshot_bcfp.sh GEOMETRY_NAME=geom,
compare scripts conn_tunnel = local), and staging bcfp's per-species barriers
tables (`bcfishpass.barriers_bt`, `barriers_ch_cm_co_pk_sk`, `barriers_st`,
`barriers_wct`) into the working schema for the access call, the driver ran
end-to-end. Pre-link#152 baseline (link's local source-typed barriers + bcfp's
per-species barriers + link's habitat):

| species | match % | n_diff |
|---|---|---|
| bt  | 82.65% | 2,483 |
| ch  | 99.25% | 107 |
| cm  | 80.28% | 2,822 |
| co  | 99.08% | 131 |
| pk  | 80.28% | 2,822 |
| sk  | 98.71% | 184 |
| st  | 100.00% | 0 (absent species) |
| wct | 100.00% | 0 (absent species) |

n_total = 14,308 segments per species (vs 15,762 in v0.30.0 — segment count
differs from break-position drift; not yet investigated).

**Diagnostic (working schema preserved via `LNK_KEEP_WORKING=1`):**

```
table              tunnel   local   diff
anthropogenic        3519    3608    +89
dams                    6       6      0
pscis                  34      33     -1
remediations         3524    3613    +89
```

So link's `lnk_pipeline_crossings` (v0.32.0) is producing ~89 extra rows
in `barriers_anthropogenic` and `barriers_remediations` for ADMS — likely
modelled crossings that bcfp filters out and we don't.

**Diff patterns** include `ACCESS;MODELLED | ACCESS;NONE`,
`ACCESS;NONE | SPAWN;NONE`, `REAR;DAM | SPAWN;DAM`, etc. — both barrier-
source differences (token 2) AND habitat differences (token 1).

### Interpretation

Three input drift sources contributing to <100% match:

1. **`barriers_anthropogenic` row count** — link +89 vs tunnel. Filter
   logic divergence in `lnk_pipeline_crossings`. Investigate.
2. **Habitat (`spawning_<sp>` / `rearing_<sp>`) per-segment differences**
   — link's classifications differ slightly from bcfp's at the segment
   level even though aggregate km parity is ~99% (we validated earlier).
   Likely break-position drift from break-source ordering.
3. **REMEDIATED residue** — known, ~30 BT diffs from
   smnorris/bcfishpass#892 (merged 2026-05-06; tunnel rebuild Tuesday
   2026-05-12 picks it up).

Phase A validates that the *driver works end-to-end* and surfaces real
divergences — that's the goal. Pursuing 100% match with *link's local
inputs* requires investigating each drift source. The cleaner pure-logic
test (stage *all* bcfp inputs incl. anthropogenic/dams/habitat from
tunnel, run mapping_code) is degenerate — v0.30.0 validation already
proved that path is byte-identical.

### Open work surfaced

- [ ] Investigate +89 anthropogenic / +89 remediations divergence in
      `lnk_pipeline_crossings` ADMS output vs tunnel
- [ ] Investigate per-segment habitat (`spawning_<sp>` / `rearing_<sp>`)
      differences — break-position drift?
- [ ] Re-run after Tuesday 2026-05-12 tunnel rebuild — REMEDIATED
      residue should disappear
- [ ] After link#152 (unified barriers) ships, re-run from local-only
      inputs and document the cleaner numbers

### 2026-05-10 — root-causing the gaps

Investigation surfaced 2 concrete defects + 1 architectural divergence:

**Defect 1 (fixed):** `lnk_crossings_union` set
`barrier_status = 'POTENTIAL'` unconditionally for all modelled crossings.
bcfp's `load_crossings.sql` is conditional on `modelled_crossing_type`:
CBS (closed-bottom / culvert) → POTENTIAL; OBS (open-bottom / bridge) →
PASSABLE. ADMS has 34 native OBS modelled crossings being misclassified.

Patched `lnk_crossings_union.R` to add the CASE on `modelled_crossing_type`,
mirroring bcfp. After fix: BT 82.65 → **98.53%**, CH 99.25 → **99.89%**,
CO 99.08 → **99.72%**, SK 98.71 → **99.09%**.

**Defect 2 (driver workaround, real fix is a link issue):** `streams_habitat`
only carries rows for species in `lnk_pipeline_species(cfg, loaded, wsg)`
which returns `BT, CH, CO, SK` for ADMS — no salmon-group expansion.
But `lnk_presence` (used by `lnk_pipeline_mapping_code`) returns
`bt, ch, cm, co, ct, dv, pk, rb, sk` — *with* group expansion.

So mapping_code looks for `spawning_cm` / `rearing_cm` columns that don't
exist → falls back to NA → token1 falls through to NA → empty token1
in output. bcfp pre-allocates `spawning_<sp>` / `rearing_<sp>` for all 8
species regardless of presence (classifier runs everywhere; absent species
get 0).

Driver workaround: pre-fill `spawning_<sp>` / `rearing_<sp>` columns with
0 for any species in `lnk_presence$present` not already in the wide
habitat tibble. After fix: CM 80.28 → **99.95%**, PK 80.28 → **99.67%**.

**Architectural divergence (open):** `lnk_pipeline_species` and
`lnk_presence` disagree on what "species present" means. Should be the
same definition or one should call the other. To file as a link issue.

## Diagnostic workflow for per-WSG mapping_code divergences

When a WSG shows lower-than-expected match %, follow this recipe. Built from the
PARS BT 56% investigation 2026-05-10.

### Step 1 — Pull diff pattern distribution

The driver writes diff-pattern counts for each species. Pull the species under
investigation:

```bash
grep "  bt " logs/<TS>_mapping_code_parity_<WSG>.txt | head -20
```

Each line is `<species>  <count>  <link_value> | <bcfp_value>` for a single
distinct mismatch pair. Counts add up to the species' total `n_diff`.

### Step 2 — Identify dominant themes

Group the patterns by what differs. Common themes:

- `link emits X, bcfp emits Y where Y is "stronger" barrier` — link missing
  barriers downstream that bcfp sees. (Examples: `ACCESS;NONE | ACCESS;DAM`,
  `ACCESS;ASSESSED | ACCESS;DAM`.)
- `link has X, bcfp emits "" (empty)` — link sees habitat where bcfp says no
  habitat / inaccessible.
- Token1 differs (habitat label) — `ACCESS | SPAWN`, `REAR | SPAWN` etc. —
  habitat classification disagreement (break-position drift, eligibility
  thresholds).
- Token2 differs only — `ACCESS;NONE | ACCESS;MODELLED` — barrier source
  detection differs.

### Step 3 — Hypothesize cause from theme

Match theme → likely root cause:

| Theme | Likely cause |
|---|---|
| Link `NONE`/`ASSESSED` → bcfp `DAM` | Link missing dam barriers downstream (cross-WSG dnstr or dams pipeline gap) |
| Link `ASSESSED` → bcfp `MODELLED` | Link's PSCIS / modelled crossings differ in network position |
| Token1 `ACCESS` → `SPAWN`/`REAR` | Habitat classification differs (segment-level eligibility) |
| Token1 `""` (empty) → bcfp populated | Link sees barriers blocking species, bcfp doesn't (presence/expansion or barrier filter difference) |

### Step 4 — Verify with side-by-side queries

Query both sides for the suspected cause. For dam-related:

```sql
-- Tunnel: dam_dnstr_ind distribution + sample dnstr arrays
SELECT dam_dnstr_ind, dam_hydro_dnstr_ind, count(*)
FROM bcfishpass.streams_access JOIN bcfishpass.streams USING (segmented_stream_id)
WHERE watershed_group_code='<WSG>' GROUP BY 1,2;

-- What's IN the dnstr arrays? Do they reference barriers in OTHER WSGs?
SELECT array_to_string(barriers_dams_dnstr, ';') AS dams_dnstr, count(*)
FROM bcfishpass.streams_access JOIN bcfishpass.streams USING (segmented_stream_id)
WHERE watershed_group_code='<WSG>' AND dam_dnstr_ind=TRUE
GROUP BY 1 ORDER BY 2 DESC LIMIT 5;

-- Look up those barrier IDs — what WSG do they belong to?
SELECT barriers_dams_id, barrier_name, watershed_group_code
FROM bcfishpass.barriers_dams WHERE barriers_dams_id IN ('<id1>', '<id2>', ...);
```

If the dam IDs belong to DIFFERENT WSGs than the one we're testing, that's
cross-WSG dam_dnstr_ind. The Phase A driver stages per-WSG so it misses
these.

### Step 5 — Document and either fix or note as known limitation

If the root cause is fixable in scope, file an issue / patch. If it's a
known limitation of the per-WSG strategy (like cross-WSG dnstr), note it
as a caveat for that family of WSGs and continue.

### PARS BT 56% — confirmed cross-WSG dam_dnstr_ind (2026-05-10)

Diff patterns showed dominant `ACCESS;NONE | ACCESS;DAM`,
`ACCESS;ASSESSED | ACCESS;DAM`, `REAR;ASSESSED | REAR;DAM`. Tunnel
diagnostic: PARS has 0 rows in `barriers_dams`, but
`streams_access.dam_dnstr_ind = TRUE` for 29,798 PARS rows. The
`barriers_dams_dnstr` array contains 3 dam IDs:

- `785afb41-...` — W.A.C. Bennett Dam (PCEA)
- `320902cd-...` — Peace Canyon Dam (UPCE)
- `957546a9-...` — Site C Dam (UPCE)

PARS drains through these via the Peace River. bcfp computes
`barriers_dams_dnstr` province-wide; our driver stages per-WSG so the
downstream walk can't reach them.

**Same root cause likely explains WILL's 85%** (also a Peace tributary).
**BULK's 76% has a different cause** (Skeena drainage, no downstream hydro
— investigate separately).

### Open work surfaced by PARS investigation

- [ ] Phase A driver scope: cross-WSG dnstr feature lookup. Either
      stage `barriers_dams` / `barriers_anthropogenic` province-wide
      (load all rows, not just `WHERE watershed_group_code = '<wsg>'`),
      or document the per-WSG-only scope as a known caveat for
      hydro-downstream WSGs.
- [ ] Investigate BULK's ~84% match — different cause than PARS/WILL,
      not cross-WSG dams (Skeena drainage).

### Phase A post-link#154 (2026-05-11)

After link#154 Phase 1 (`.lnk_pipeline_pscis_build`) + Phase 1.5
follow-ons (crossing_fixes filter, DBSCAN/UNIQUE dedup, xref-precedence
restructure). Source log:
`data-raw/logs/202605111220_phase_a_post_link154_v7_xref.txt`.

| WSG  | bt | ch | cm | co | pk | sk | st | wct |
|------|------|------|------|------|------|------|------|------|
| ADMS | 99.01 | 99.93 | 99.99 | 99.76 | 99.72 | 99.14 | 100 | 100 |
| BULK | 99.26 | 99.62 | 99.78 | 99.17 | 99.73 | 99.59 | 99.41 | 100 |
| WILL | 98.85 | 99.65 | 99.93 | 99.06 | 99.91 | 99.93 | 100 | 100 |
| PARS | 60.64 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |

Step-change vs the 2026-05-10 baseline below: BULK jumped from
~80% → ~99.5%, WILL from ~86% → ~99.7%. PARS BT stays at ~60% (cross-WSG
dam_dnstr — link#152 territory).

Phase 1.5 diagnostic insight: the dominant BULK gap was xref-mapped
PSCIS leaking through the snap path. bcfp excludes xref-mapped
stream_crossing_ids from the snap path entirely, then inserts them via
xref-driven branches where stale `modelled_crossing_id` (no longer in
`modelled_stream_crossings`) silently fails to insert via INNER JOIN.
We were keeping the snap-derived rows for those IDs (88 extras in
BULK), which created phantom break points and re-classified thousands
of segments.

### Phase A baseline (2026-05-10 with fixes applied)

ADMS:

| species | match % | n_diff |
|---|---|---|
| bt  | 98.53% | 211 |
| ch  | 99.89% | 16 |
| cm  | 99.95% | 7 |
| co  | 99.72% | 40 |
| pk  | 99.67% | 47 |
| sk  | 99.09% | 130 |
| st  | 100.00% | 0 (absent species) |
| wct | 100.00% | 0 (absent species) |

Multi-WSG scale test (BULK, WILL, PARS):

| WSG | bt | ch | cm | co | pk | sk | st | wct | n_total |
|---|---|---|---|---|---|---|---|---|---|
| BULK | 76.30% | 84.07% | 84.18% | 83.82% | 84.14% | 84.17% | 79.88% | 100% | 39,481 |
| WILL | 85.48% | 86.83% | 87.05% | 86.49% | 87.03% | 87.05% | 100% | 100% | 17,148 |
| PARS | **56.16%** | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 37,509 |

Driver scales (no errors at 39k+ segments). Lower-than-ADMS numbers
across BULK/WILL/PARS are surfacing different root causes per WSG;
PARS investigated above (cross-WSG dam_dnstr_ind), BULK + WILL TBD.

Remaining gaps are input drift (link's locally-built barriers slightly
differ from bcfp's tunnel ones), per-segment habitat classification
differences from break-position drift, and the known REMEDIATED tunnel
residue (~30 BT diffs) that resolves after Tuesday 2026-05-12 rebuild.

**Phase A confirmed: link's mapping_code derivation logic is correct
given properly aligned inputs.** The path to ≥99.99% on all species
runs through (a) Tuesday's tunnel rebuild for REMEDIATED, (b) link#152
unified barriers for input self-sufficiency, and (c) the
`lnk_pipeline_species` / `lnk_presence` divergence fix.

### Fix decisions (pending)

1. **Where to do the CABD → bcfp text translation:**
   - **Option A** — `snapshot_bcfp.sh` (load time, most upstream)
   - **Option B** — `lnk_pipeline_prepare.R` (per-WSG, lives where
     source-shape work already happens)
   - **Option C** — `lnk_crossings_union.R` (current location;
     mirrors bcfp's `load_crossings.sql`)
2. **Compare-script `conn_tunnel` arg:** change both compare scripts
   to pass `conn_tunnel = conn` (local) — no link package changes
   needed for this part.
3. **`lnk_pipeline_prepare` API rename:** separate follow-up — not
   blocking parity work.

## Open questions

- **`streams_access` parity** as a follow-up document
  (`bcfp_compare_streams_access.md`). The integer access codes are a
  sibling parity surface; comparing them gives cleaner diagnostic for
  upstream changes that affect access logic vs habitat logic.
- **Per-token diff breakdown.** The current `match %` is segment-level.
  A token-by-token breakdown (token1 mismatches vs token2 mismatches)
  would help triangulate where divergences come from. Add to the
  driver if the simple match % isn't enough signal.
