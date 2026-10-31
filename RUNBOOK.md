# link RUNBOOK — how the system actually works

Durable mental model of link's barrier → access → mapping_code machinery.
Written because the data flow spans ~8 R files and gets re-derived from scratch
every session (especially after context compaction). Read this first.

For *what's shipped* and *conventions*, see `CLAUDE.md`. This doc is the
*mechanics*: what feeds what, where each rule lives, and the gotchas that have
bitten us. When the mechanics change, update this file in the same commit.

---

## 0. Getting going (operate on a fresh machine — e.g. M1)

The modelling runs against a local Postgres (docker `fresh-db`) holding the bcfp
inputs. DB state is **machine-local** — rebuild it from public sources, no DB
dump needed. One-time prereqs (GDAL+Parquet driver, uv, bcdata, psql) install via
kdot `install_geo.sh`.

```bash
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

Local fwapg conn: `host=localhost port=5432 dbname=fwapg user=postgres
password=postgres`. (M1's `~/.Renviron` defaults `PG_*_SHARE` to the tunnel
`:63333` — for the local build set `Sys.setenv()` to `:5432` in R; see the
m1-testing pattern in `fresh/CLAUDE.md`.) Then build:
`lnk_pipeline_run(conn, "PARS", cfg, loaded, schema, mapping_code = TRUE)`.

## 1. The big picture

link reproduces bcfishpass's per-segment, per-species habitat + connectivity
classification, tunnel-free, for any watershed group (WSG) or AOI.

```
per-WSG pipeline (lnk_pipeline_run, working schema working_<aoi>)
  setup → load → prepare → crossings → break → classify → connect
        → species → persist_init → barriers_unify → persist
        → barriers_views → pipeline_access → persist (adds streams_access)
        → habitat_gate (settles persisted habitat on access, link#349)
        → mapping_code (with mapping_code = TRUE; read from persist)
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

**Key consequence: dams block *all* species in `blocks_species`.** There is no
per-species dam rule in any config file. A dam (CABD, via the anthropogenic
family) gets `blocks_species = {all species}`. This was the #196 dam-token bug.
bcfp does NOT put dams in the per-species *access* set at all (§5) — they're a
downstream *descriptor*, not an accessibility barrier. **Fixed in #200/v0.40.4:**
accessibility no longer reads `blocks_species` over all barriers. It reads the
per-species `barriers_<sp>_access` view (§5), which filters to NATURAL sources
only (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')`)
— so dams are excluded from access and (correctly) annotate token2 only.
`blocks_species` is still computed for all families (it's how the `_access` view
gets the per-species gradient threshold for free); the access view just ignores
the anthropogenic rows.

**The dams outside BC (link#367).** `cabd_additions.csv` places Grand Coulee /
Chief Joseph (Columbia at the border, Kettle, Big and Little Sheep creeks) and
Ross (Skagit) on the BC lines they block. bcfishpass at `620dbe4` loads them
with a NULL passability code and does not make them crossings (its
`load_crossings.sql` inner-joins `cabd.dams`), so the `bcfishpass` bundle does
the same. That is an upstream regression: from July 2023 they had their own
`BARRIER` crossings insert, which stopped matching in v0.7.7 when they moved to
`cabd_additions.csv` (NewGraphEnvironment/bcfishpass#15). Flip the bundle once
upstream restores them; a restored insert must not reuse the `1200000000`
offset, which `user_crossings_misc` also uses. `default`
sets `pipeline: cabd_additions_barriers`, which gives each placeholder whose
`barrier_ind` is true code 1, so it becomes an anthropogenic barrier. They are
numbered `1200000001`-`5` in CSV order (`.lnk_dams_usa_sql()`, shared with the
guard, §8c). Like every dam they never block access; they move the `DAM` token
above them (LARL, KETL, SKGT: 19,065 segments, all `NONE` to `DAM`;
`data-raw/logs/provincial_prep_367/`) and, by the same rule, in the groups
upstream whose next anthropogenic barrier they are.

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

**Barrier ids are positional and stated.** Each source in `lnk_barriers_unify()`
numbers its rows by `(blue_line_key, downstream_route_measure)` (gradient also by
label; falls and user-definite also by the joined `linear_feature_id`, because a
point in the ~1 mm overlap of two FWA segments joins both, as one USIK falls
does), never `row_number() OVER ()`, so two builds from the same inputs give
every barrier the same id (link#367; verified on ADMS and ELKR).

**No staged gradient or subsurface row is lost to its point.** `FWA_LocateAlong()` is
set-returning and returns no row for a measure in the few-millimetre gap where an
FWA segment's upstream measure misses the next segment's start, so called in a
SELECT list it silently dropped the barrier (4 to 9 rows with a wscode per group
in the #326 cross-section, plus rows past a line's last segment). The per-species
reduction still kept such a position, so the barriers above it went unbroken while
the access view, which lacked it, blocked them. Each source now takes its point
from `.lnk_sql_locate()`, which falls back to interpolating on the line's nearest
segment and takes only alias-qualified columns (a bare `blue_line_key` binds to the
fallback's own FWA table). Falls and user-definite rows still need an FWA segment
containing their measure, to take its wscode, and the reduction joins them the same
way, so a gap point is left out of both alike (none in the 12 groups checked, #326).

**The PSCIS pick (`.lnk_pipeline_pscis_build()`).** A PSCIS x stream candidate
joins every modelled crossing within 100 m on its blue line. bcfishpass then keeps
only the nearest instream one per PSCIS per blue line, before the pick; link had
skipped that step, and the pick fell to encounter order between two modelled
crossings on one feature (link#277: two builds at main, minutes apart, picked a
different modelled crossing for 464 PSCIS). Step 3b ports it, with
`modelled_crossing_id` breaking its tie, and the pick's order
(`.lnk_pscis_pick_order`) ends on `linear_feature_id, modelled_xing_dist,
modelled_crossing_id`. Both KNN snaps (`lnk_points_snap()`, the dam snap) end on
`linear_feature_id`.

`barriers_<sp>_min` is a **break-spec**: a present species' post-lift natural barriers (gradient at its classes, falls, opt-in subsurface flow, minus its overrides, plus user-definite) reduced to the downstream-most position per flow path, as bcfishpass breaks (#326). It was reduced before the lifts until #223, then held every position until #326; the raw post-lift table `barriers_<sp>` stays in the working schema for diagnostics, and how this compares with bcfishpass is `research/bcfp_segmentation_parity.md`. It
has NO id column, so it **cannot** feed `frs_network_features` /
`barriers_per_sp`. (Tried in #196; failed with `barriers_bt_min_id does not
exist`.) `barriers_per_sp` mechanically requires the *feature view* shape.

### 2c. Observation breaks: where a fish record cuts a stream (link#396)

`observations` is the first break source (`lnk_pipeline_break()`), built by
`.lnk_pipeline_break_obs()` from the AOI's filtered `<schema>.observations` into
`<schema>.observations_breaks`. Which positions it holds is the bundle's
`pipeline: observation_breaks:`, checked when the manifest loads:

| value | positions | bundles |
|---|---|---|
| `all` (also when absent) | every observation, rounded to the metre, as bcfishpass cuts | `bcfishpass`, `default_extrabreaks`, `default_rearbreaks` |
| `top_per_species` | on each `blue_line_key`, each species' farthest-upstream observation | `default`, and `default_tuned` by inheritance |

**What reads an observation break.** Only `access_<sp>` code 2 ("accessible, and the
species is observed upstream") against code 1. The access walk
(`lnk_pipeline_access()`, `frs_network_features(direction = "upstream",
include_equivalents = FALSE, result = "distinct")`) reads every group's records itself
(`<schema>.observations_province`, since #401), not the breaks table, and its same-line
measure test counts a record as upstream of a
segment only when the record is at least 1 m above the segment's start (fwapg
`fwa_upstream`, fresh's 1 m tolerance; clause 1 below). That is bcfishpass's reading: its walk calls `FWA_Upstream(…, False, 1)`
(`load_streams_upstr_observations.sql`). Breaks are rounded to the metre, so a break at a
species' top starts its segment within 0.5 m of the record: that segment reads 1 (barring
the cases below) and the one ending there reads 2. So code 2 is a property of a segment's start. **What reads 2** is `fwa_upstream()`'s
clauses (fwapg; each first asks that the record's watershed code descend from or equal the
segment's):

1. A record on the segment's own line at least 1 m above its start. This is the only clause
   #399 changed; `TRUE` read `start − 1`.
2. A record on another line, by watershed codes alone. Where the segment's watershed and
   local codes are equal, any other line whose watershed code descends from or equals the
   segment's counts, except a distributary carrying the same two codes. Where they differ, a
   line counts when its watershed code is greater than the segment's local code and does not
   descend from it (a tributary entering above), or when it has the same watershed code and a
   larger local code (fwapg's "capture side channels"). None of this reads measure, so a
   tributary's records count for every segment of the receiving line below its mouth.
3. Where the segment's two codes differ, the side-channel test also matches the segment's
   own line, again ignoring measure, wherever local codes there do not rise with measure: on
   PARS line 359567332 the segments starting at 182477 and 183194 m read BT 2 from the line's
   top BT record at 182461 m.

**Which records count** is the bundle's `pipeline: observation_upstream:` (#401), checked
when the manifest loads and hashed into the `acc` token:

| value | a segment reads 2 when | bundles |
|---|---|---|
| `province` | a record of the species in any group is upstream | `default`, and `default_tuned` by inheritance |
| `group_gated` (also when absent) | as `province`, and a record of the segment's own group, of any species, is also upstream | `bcfishpass` |

`group_gated` is what bcfishpass computes: its `spp` CTE collects the species upstream from
every group's records, but the insert is `spp INNER JOIN ids`, and `ids` is same-group only, so
a segment with no own-group record upstream gets no row and reads 1
(`load_streams_upstr_observations.sql`, `smnorris/bcfishpass@620dbe4`; our fork's draft for
upstream is NewGraphEnvironment/bcfishpass#16). Under it a main stem reads 1 below a group
boundary until the group holds a record above it. Before #401 both bundles read the group's own
records only (`<schema>.observations`), so such a main stem read 1 up to its boundary whatever was
recorded just upstream. Breaks still read the group's own records: a record in another group cannot
cut this group's segments.

The walk asks fresh for each segment's distinct species (`result = "distinct"`, fresh#284), as
bcfishpass's `SELECT DISTINCT segment, species_code`, and under `group_gated` one existence walk
over `<schema>.observations` for the gate. The array walk it replaced returned every
segment-record pair, and over every group's records a Fraser main-stem segment in LFRA has about
79,000 above it (126,371 raw bcfishobs records under wscode `100`, 79,300 once each is kept by its
group's presence). The distinct walk over every group's records costs less than the array walk over
the group's own did (LFRA 65 to 37 s, BULK 21 to 8 s, SETN 47 to 45 s;
`data-raw/logs/obs_province_401/walk_fresh_distinct.csv`). `lnk_pipeline_run()` drops
`<schema>.observations_province` in an `on.exit()`. A kept working schema holds it after a
killed run (no `on.exit()` runs) or a failed DROP (a lost connection, inside `try()`), until the
group's next run replaces it. A direct caller of `lnk_pipeline_prepare()` owns the drop.
Built before and after on six `default` and three `bcfishpass` groups, only code 1 to 2 moved,
each piece under a record of the species from another group: 25.98 km under `default` (LNTH BT
12.25 km, 3.6 % of its observed km, the most) and 0.05 km under `bcfishpass`, whose gate holds
most of it back (`data-raw/logs/obs_province_401/`).

Each species' top is a break in both bundles (under `all` every record is), so normally the
segment starting at the top reads 1, and the boundary sits on the highest record (#399). Clauses 2 and 3 can keep 2 above it. So can a top within 1 m of an FWA
line end, which does not cut. Observations are the first break source and all go to one
`frs_break_apply()` call, which tests a break only against the ends that existed before it,
so another record's break never blocks one. The boundary is then that end if it lies above
the record or less than 1 m below it, else the next end above (ELKR: a BT record 1 m above
its line's start reads 2 to the line's first end, 112 m up). Until #399 the walk passed `TRUE`, which
counts a record at start − 1 or above, so the segment starting at a species' top still
read 2 and the species turned at the first cut more than 1 m above its top, whatever made
that cut (#396's measurements below were made under that reading). Built before and after
#399 on five `default` groups and two `bcfishpass` groups, only that code moved: 346.6 and
93.6 km of 2 to 1, at most 5.4 % of a species' observed km, every piece at a record, with
segments, barrier flags, mapping codes and habitat unchanged
(`data-raw/logs/record_at_start_399/`), and the `bcfishpass` builds' observed km now equal
bcfishpass's (steelhead excepted, whose reference codes it from sockeye records). Lifts count observations
point against point
(`lnk_barrier_overrides()`), and the mapping code and habitat gate read
`has_barriers_<sp>_dnstr` and `access = 0` against `> 0`; none needs a break.
Until #403 nothing in link told 2 from 1 (every reader tested `IN (1, 2)`, `> 0` or `= 0`;
`data-raw/logs/observation_breaks_396/readers_code2.md`). Now `lnk_rollup_wsg()`'s default
`accessible_observed_km` / `accessible_unobserved_km` do, as bcfishpass's `aw_linear_summary()`
does on its own tables (`length_naturallyaccessible_obsrvd_<sp>` / `_model_<sp>`).

**The access changes follow from one fact: a segment's codes depend only on where it
starts.** Both tests in the walk are monotone in the start: the same-line measure test
counts a record when its measure is at least start + 1 (start − 1 before #399), a barrier
as downstream when at most start + 1, the code clauses read only codes, which are constant
within an FWA feature, and a segment never spans a confluence (FWA ends cut in every build), so the tributary
tests are constant within one: a tributary's records count for every segment of the
feature below its mouth, whatever its start, and for no segment above. So when a break goes and a segment now starts lower,
its upper part can only open or gain "observed upstream"; when a segment now starts
higher, the reverse. Fewer observation breaks mostly move starts down (measured by
#396, under the reading before #399):

- **1 to 2 at a species' top**, the main change. Where a removed record's rounded
  position lay more than 1 m above X's raw top and below the next kept cut, the segment
  starting at X's top swallows it and reads X = 2 above it.
- **Blocked to open,** where a merged segment's lower start puts a barrier more than
  1 m above it.

**Some starts move up, because the 1 m rules stack near a removed break.** Breaks are
rounded to the metre while the walk compares raw measures, and a later source cuts only
more than 1 m from the current segment ends (`fresh::frs_break_apply()`), observations
being the first source. So while an observation cut stands, a barrier, crossing or other
break within 1 m of it does not cut; once the observation goes, that break cuts at its
own position, up to about 2 m higher. A start that rises can turn a 1 m sliver or a
whole segment from open to blocked (a barrier 1 to 1.5 m above the observation cut: the
metre-rounding defect of link#349, fresh#258) or from 2 to 1 (a released break about 2 m
above X's top).

The recompute (`lnk_access()`) passes no observations and keeps a prior 2, so a recompute
after a re-model keeps these. `data-raw/logs/observation_breaks_396/pre_post_diff.R`
checks the direction rule on every piece: any change against the direction its start
moved, or with the start unmoved, is a defect. Under the reading before #399, the set
that would have kept nearly every turn to 1 where `all` put it was smaller than the tops:
per species, the lowest record of any species more than 1 m above its raw top
(`exact_set.sql`). It was near-exact, not exact, and dropped: the tops stay, because
putting each species' boundary at its highest record (#399) needs exactly them; since
#399 that set no longer reproduces `all`, which now normally turns each species at its own top. `research/observation_breaks.md` has the counts.

**Omitting `observations` from `break_order`** removes its segmentation only: code 2
is still computed, at the resolution of the segments left.

**The validator** attaches an observation to the segment starting within 1 m of it,
else the one holding it, so it scores the same records whatever breaks a bundle
takes. Capture shares still move with segmentation (merged segments take a new
gradient).

---

## 3. Access: `lnk_pipeline_access()`

Computes `<schema>.streams_access` — per-segment, per-species accessibility plus
downstream barrier-source flags. Two distinct inputs, two distinct roles:

- **`barriers_per_sp`** — named list `sp → barriers_<sp>_access` (#200; was
  `_unified` pre-v0.40.4). Drives `has_barriers_<sp>_dnstr` (is a blocking
  *natural* barrier downstream for this species, override-applied). This is
  **accessibility** — feeds `accessible` in mapping_code. NATURAL-only +
  override-filtered + user_definite (§5) — dams are NOT here. Each table's
  feature id is derived as `<table>_id` and passed to `frs_network_features`.
- **`barrier_sources`** — named list of source-typed feature tables
  (`anthropogenic`, `pscis`, `dams`, `remediations`). Drives the
  `has_barriers_<source>_dnstr` / `dam_dnstr_ind` / `remediated_dnstr_ind`
  flags. This is **classification** (what *kind* of barrier is downstream), NOT
  accessibility. Feeds token2 (DAM/MODELLED/ASSESSED/…).

The output flag columns (`has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`,
`dam_dnstr_ind`, `remediated_dnstr_ind`) MUST be persisted — see §6 gotcha.

### How the walks run (link#394)

Each table is walked once by `fresh::frs_network_features()`, and the walk asks only
for what the step reads (fresh ≥ 0.47.0):

- **Arrays (`result = "ids"`)** for `anthropogenic` and `dams` when both are given
  (`dam_dnstr_ind` reads the first anthropogenic id and looks it up in the dams array),
  for `remediations` when `crossings_table` is set (`remediated_dnstr_ind`), and for the
  upstream observation walk (species codes). A table given in one of those roles is walked
  as arrays even where it also serves as a species table.
- **Existence (`result = "exists"`)** for everything else: the per-species views and
  `pscis`, which are read only as `id %in% result$id`. Same join and answer, reduced
  to distinct segments instead of arrays. The join still enumerates every pair, so an
  output-bound group gains little (SETN 1.2×).
- **One walk per distinct barrier set.** The species views over one barriers table often
  hold the same rows (CHWK's CH, CM, CO, PK and SK views). Before walking,
  `.lnk_walk_keys()` digests each existence table's rows that `fwa_downstream()` could
  admit from this group: on one of its blue lines, or with a wscode equal to an ancestor
  of a group segment's, every column the walk reads, as record text in `C` order. Tables
  with equal keys share one walk. The key assumes nothing the walks read changes during
  the group's access step, which is #374's readiness rule: those rows belong to groups
  that have landed.

Measured on SALR, CHWK, LFRA and SETN (`data-raw/logs/recompute_access_394/`): with
fresh 0.44.0's walks the access step took 27, 535, 1,146 and 764 s. With the
prefilter (fresh 0.47.0) it took 3.9, 21.5, 89.5 and 347 s. With existence walks it
took 4.0, 19.6, 74.5 and 292 s. With one walk per distinct set it took 4.0, 9.3, 35.3
and 136.5 s. Every output digest was identical.

### `accessible` is settled from `streams_access` (link#349)

Two columns answer "is this segment accessible to <sp>", and they used to disagree:
`streams_habitat_<sp>.accessible` is fresh's, computed in `frs_habitat_classify()` and gating
`spawning` / `rearing` / `lake_rearing` / `wetland_rearing` there; `streams_access.access_<sp>`
(and `has_barriers_<sp>_dnstr`) is link's, built by this section's `lnk_pipeline_access()`.
**`access_<sp>` is authoritative.** On `fresh_default` (241 groups) fresh said accessible where
link said blocked on 1.6–3.5 % of most species' accessible segments, 17 % of RB's and 90 % of
KO's, for four reasons (`data-raw/access_disagree_349.R`, `research/access_columns.md`):

| | mechanism | fixed by |
|---|---|---|
| A | fresh's breaks are rounded to the metre (`.lnk_pipeline_classify_build_breaks()`); a gradient barrier mm below a segment start lands above it, and fresh's `b.drm <= s.drm` misses it | the gate |
| A′ | a barrier 0–5 mm *above* the start: link's `fwa_downstream(…, 1)` blocks by the barrier's ltree, fresh's exact `<=` never | the gate |
| B | fresh's breaks are filtered to the group; a blocking barrier downstream in another group is invisible to it | the gate |
| C | lifts counted only the group's own observations (§5), so barriers on lines several groups share stayed un-lifted (the Peace dam faces for RB, KO, and BT above UKEC) | province-wide counting (§5), plus an RB rule in `default` |

**The gate, `lnk_habitat_gate()`**: where `access_<sp>` = 0, the five flags go FALSE on the
**persist** per-species tables; rows `user_habitat_classification` marks keep `spawning` /
`rearing` (known habitat, as `frs_habitat_overlay()` forces it), `accessible` still goes FALSE.
It runs in `lnk_pipeline_run()` after the second persist (so mapping codes are built from
persist after it), in `wsg_recompute_one.R` after `lnk_access(merge = TRUE)`, and in
`habitat_variants_build.R`'s recompute and variant persists. Counts land on `log` /
`log_recompute` (`habitat_gate_{n,km,lifted,species}`), and `study_area_verify.sql` raises if any
run group holds `accessible AND access_<sp> = 0`.

- **Never on the working tables.** `habitat_variants_build.R` digests `working_<wsg>.streams_habitat`
  after a run and asserts classify + connect reproduce it.
- **One-way.** `lnk_access(merge = TRUE)` can lift a segment (0 → 1), and the gate cannot give its
  habitat back: only a re-model of the group does. The recompute snapshots access first and counts
  such segments as `habitat_gate_lifted`; `wsg_recompute_one.R` prints "need a re-model" when it is
  non-zero.
- **On a dispatch the model leg does not gate.** `study_area_run.sh` exports
  `LNK_HABITAT_GATE=0` on both legs (`lnk_pipeline_run(habitat_gate = FALSE)`): a group modelled on
  one host reads other hosts' barriers and overrides as that host holds them, possibly a previous
  run's, and a one-way gate there would blank habitat the recompute then lifts. The recompute
  settles every group on final access, and so does the re-model command §8d prints for a run's
  missing groups. A single-group `wsg_run_one.R` gates at model time; so does the legacy
  `wsgs_dispatch.sh` path (`lnk_compare_wsg()`), which runs no recompute and settles on the access
  it ships.
- **Schemas built before it are unsettled.** A recompute settles one
  (`bash data-raw/study_area_run.sh --recompute-only --run-uid=<uid> --config=<config>
  --schema=<schema>`, §8d), but re-model first, then gate: a re-gate settles on today's access, and
  a later re-model of a barrier-holding group (the province-wide lifts, the RB rule) lifts segments
  upstream whose habitat the re-gate already blanked; only re-modelling each of those groups restores
  it. `study_area_verify.sql` fails on such a group (the newest recompute's `habitat_gate_lifted`).
- A and A′ could be fixed at classify time with a tolerance on fresh's predicate and its override
  match plus dropping link's rounding in prepare and classify together (NewGraphEnvironment/fresh#258). The gate
  stays either way: B cannot be seen at classify time on a multi-host run.

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

### Where link diverged, and how #200/v0.40.4 fixed it

The #196 bug was: `barriers_per_sp = barriers_<sp>_unified` = **all** barriers
(incl dams, PSCIS, modelled) WHERE species ∈ `blocks_species` (§2a). Two wrongs,
both now fixed:

1. **Wrong content** (FIXED). It included dams/anthropogenic; bcfp's
   `barriers_<sp>` is natural-only. Every PARS segment below a dam read
   `has_barriers_bt_dnstr = TRUE` → `accessible = FALSE` → token2 `;DAM`
   suppressed → bare `SPAWN`.
2. **No override applied** (FIXED). bcfp removes barriers with upstream
   observations / confirmed habitat. link's `lnk_barrier_overrides`
   (`lnk_pipeline_prepare.R:519`) output `<schema>.barrier_overrides` fed only
   `lnk_pipeline_classify` (habitat), NOT the access path.

**The fix (#200/v0.40.4) — all three access inputs persisted province-wide:**

- `barriers_per_sp` now points at `<schema>.barriers_<sp>_access`
  (`lnk_barriers_views`): feature-shaped (has-id, §2b), NATURAL only
  (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')` —
  gradient-at-species-threshold is already encoded in `blocks_species`), MINUS
  the override (anti-join `barrier_overrides`), with `USER_DEFINITE`
  override-exempt. Dams stay in `barrier_sources` → token2 only.
- `user_barriers_definite` is now a `USER_DEFINITE` family in `lnk_barriers_unify`
  (persist `barriers`), ltree-resolved via the same FWA join the FALLS branch
  uses (mirrors bcfp `barriers_user_definite.sql`).
- `barrier_overrides` is now persisted province-wide
  (`<persist>.barrier_overrides`, `lnk_persist_init` + `lnk_pipeline_persist`).
  Because the access view reads persist (cross-WSG) barriers, the override must
  also be province-wide so a natural barrier in *any* WSG a downstream walk
  crosses is lifted correctly. Persist PK is
  `(blue_line_key, downstream_route_measure, species_code, watershed_group_code)`
  — boundary-stream override positions are computed by two adjacent WSG runs, so
  WSG must be in the key.

**Provincial-accumulation property** (do not forget): a single-WSG run only sees
WSGs already in persist. PARS only emits `;DAM` once PCEA+UPCE (which hold the
Bennett/Peace Canyon dams PARS drains through) are persisted. This is identical
to bcfp's accumulated `barriers_<sp>` and to link's natural-barrier persistence
(link#152) — handled by the provincial orchestrator.

**Validated (v0.40.4):** PARS BT 98.95%, LFRA BT 97.77% / CO 97.90% per-segment
vs `fresh.streams_vw_bcfp`. Residual ~1-2% is token1 habitat-presence
(`ACCESS`↔`SPAWN`/`REAR`, dimensions/rules), not the dam-access fix.

What does **NOT** work (rejected during #196): `barriers_<sp>_min` (break-spec,
no id, §2b) — its *content* (gradient+falls) is close, but it cannot feed
`frs_network_features`.

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

### Observation lifts count province-wide (link#349)

bcfishpass counts a barrier's upstream observations over **every** group's records
(`bcfishpass.observations`, each kept by its own group's presence; `smnorris/bcfishpass@620dbe4`
`load_observations.sql` + `model_access_bt.sql`). link counted only the AOI's
(`<schema>.observations`), so a barrier on a line several groups share, persisted under each
(the Peace rows sit under FINA, LPCE, PCEA and UPCE), was lifted only if one holding group had
enough records *inside itself*. Since #349 `.lnk_pipeline_prep_observations()` also builds
`<schema>.observations_province` (every group's records by its own presence, minus exclusions,
GiST on the ltrees) and `lnk_barrier_overrides()` counts over it. Since #401 the access walk reads
it too, for code 2 (§2c, "Which records count"); `<schema>.observations` stays AOI-scoped for the
observation break source and `group_gated`'s gate. Cost: ~4 s per group to build
both tables, no change to the override step (DUNC, CARP). `default`'s RB row gained a rule shaped like BT's
(one RB record, only RB counting for RB, no date floor); before it RB had no rule and nothing lifted for it.

The count is of distinct records (`count(DISTINCT o.observation_key)`, link#367):
`natural_barriers` can hold one position twice (a point where two FWA segments overlap, or
a falls and a gradient barrier that round to one metre), and each copy joins the same records.

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
- **`pkill <R client>` does NOT cancel its Postgres query — the backend
  orphans.** Caught 2026-05-25 (link#205): a killed recompute left a
  `frs_network_features` SELECT running 1h45m server-side, holding a lock on
  `barriers_bt_access`; every later `lnk_barriers_views` `DROP VIEW` blocked
  behind it indefinitely (silent hangs). The R client died; the libpq backend
  did not. **Always terminate the server-side backend** (`SELECT
  pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='active' …`),
  not just the client. And **set `statement_timeout` + `lock_timeout` on any
  long-running DB op** (`SET statement_timeout = '600000'; SET lock_timeout =
  '60000'`) — a runaway cancels server-side instead of orphaning, and a
  blocked DROP VIEW fails fast instead of wedging. `data-raw/wsg_recompute_one.R`
  sets these on its conn for exactly this reason. The modelling legs of
  `study_area_run.sh` are bounded too, through `PGOPTIONS` (§8d, "A runaway
  statement fails its group").
- **AOI-scoping streams to a VIEW (not a real table) makes the planner pick
  the wrong join driver.** Caught 2026-05-25 (link#205): scoping
  `fresh.streams` to one WSG via `CREATE VIEW … WHERE wsg = 'FINA'` left
  Postgres with no small-table stats; it picked the ~800k-row
  `barriers_bt_access` as the outer driver of `frs_network_features`'s
  nested loop, blowing the cost up by ~1000× (estimated 71M result rows, >10
  min wall). Solution: materialize as a real `CREATE TABLE` with an
  `id_segment` btree + ltree GiST + blue_line_key + `ANALYZE`. Then the
  planner picks the 26k-row AOI streams as outer and the walk takes ~10s.
  Mirrors the full pipeline's working schema (also a real, indexed table).
- **Since fresh v0.45.0 a downstream walk scopes itself** (fresh#272, adopted
  in #409). Given `aoi`, `frs_network_features()` copies the group's segments
  into an indexed, analyzed session temp table and admits only features on one
  of the group's blue lines or on an ancestor-or-equal wscode, so the plan no
  longer depends on the table link hands it, and the walk no longer drives from
  every feature in the province. Two consequences: the session must be able to
  create temp tables (a read-only transaction or a hot standby stops the call;
  so can a transaction pooler), and every PSCIS and dam walk got slower, by
  about 1 s in SALR, LKEL and CHWK and up to about 4 s in SETN, 5 to 11 walk
  calls per group (`data-raw/logs/prefilter_409/`; what costs it is not measured). Every
  downstream walk link makes passes `aoi` (`test-lnk_pipeline_access.R`); one
  without it gets the old province-wide walk with the same answers.
- **`id_segment IN (…)` is cartesian against the persist schema** (link#203).
  `id_segment` is unique per WSG, not globally; a query like
  `SELECT * FROM <persist_access> WHERE id_segment IN (SELECT id_segment FROM
  <streams> WHERE wsg = aoi)` matches access rows from every WSG that
  happens to share those id_segment values → ~N(WSGs)× duplicates. Filter
  by `watershed_group_code` directly when the table has that column.
  `lnk_mapping_code` learned this the hard way.

---

## 6b. Run provenance — which config built this network? (link#127)

Every `lnk_pipeline_run()` writes five sidecar tables into the **persist**
schema, so a network in the DB is self-describing:

| table | grain | holds |
|---|---|---|
| `<persist>.log` | one row per run | `date_start` / `date_end`, `config_hash`, `config_drift`, link/fresh version + SHA + dirty flag, `fwapg_sha`, run args, `discharge_fill`, `discharge_source`, `near_river` (the pairs, #364), `species[]`, `wsg_upstream[]`, bcfp baseline |
| `<persist>.log_parameters_fresh` | `(config_hash, species_code)` | **full** `parameters_fresh.csv` rows |
| `<persist>.log_parameters_habitat_thresholds` | `(config_hash, species_code)` | **full** thresholds rows the run used — the bundle's, or fresh's copy when it has none (#282) |
| `<persist>.log_dimensions` | `(config_hash, species)` | **full** `dimensions.csv` rows |
| `<persist>.log_input` | `(run_id, table_name)` | per-primitive row count, size, last-analyze, source |

Read it with `lnk_log_read(conn, cfg, aoi = "PINE")`. Mirrors `bcfishpass.log`
+ its `log_parameters_*` children.

**Why full rows, not a pointer.** `observation_species = BT;DV` at threshold 1
with no date floor is recorded *in the database*, so two scenario runs stay
distinguishable after the config file moves on. That is the whole point — see
link#236, which runs the DV-as-BT override with and without.

**The three-state completion signal:**

| `date_end` | `notes` | meaning |
|---|---|---|
| set | — | success |
| NULL | set | R error or interrupt (`on.exit` ran) |
| NULL | NULL | SIGKILL / OOM / host reboot (nothing ran) |

**No backfill, ever.** A WSG in `<persist>.streams` with no `log` row was
modelled before provenance existed. That state is not recoverable and a
synthetic row would be fabricated provenance. Audit which:

```sql
SELECT DISTINCT watershed_group_code FROM <persist>.streams
EXCEPT SELECT watershed_group_code FROM <persist>.log;
```

**Gotchas.**

- `config_hash` hashes the **observed bytes of the resolved file set**, not the
  declared `provenance:` block — `config.yaml` is absent from its own block, so
  a declared-set hash would be blind to `pipeline$schema`, `break_order` and
  `gradient_classes`. `config_drift` is the separate "did it match what it
  claimed" axis.
- `log_input` never runs `count(*)`. Row counts are `pg_class.reltuples`
  estimates (`row_count_estimated = TRUE`); exact counts on a 4.9M-row / 9.8 GB
  table across a provincial pass would add hours.
- **`bcdata.log` covers only `bc2pg` downloads — not FWA.** The stream network
  is loaded by fwapg's own `load.sh` from bchamp objectstore parquet, and
  `pg_stat_user_tables` for it is empty (bulk-restored, never analyzed).
- **`fwapg_sha` is not FWA provenance.** It is the HEAD of the fwapg checkout
  **when the model runs** (on cyphers, the dispatcher's, exported as
  `FWAPG_GIT_SHA`), not the commit that ran `load.sh`, and it moves on any
  fwapg commit. To tell whether two runs read the same FWA data, compare
  `log_input`'s row counts and sizes, and `artifact_version_id` /
  `artifact_etag` beside them (below; for FWA these are probe rows, which are
  evidence and not proof).
- **Source-artifact identity (link#265).** `provenance.source_artifact` holds,
  per host and primitive artifact, the object store's version id, ETag and
  `Last-Modified`, and `recorded_by` says how strong the record is:
  - `loader`: written by `snapshot_bcfp.sh`, which HEADs each object and then
    reads **that version** (`?versionId=`), so the recorded version is the
    loaded one by construction. A snapshot that cannot record fails.
  - `probe`: a HEAD after the fact (`lnk_artifact_probe()`, run soft at the
    end of every snapshot), used for the FWA tables because `load.sh` records
    nothing (loader rows for those are link#270). It says "current at the
    first probe", never "what was loaded". It never overwrites a loader row.
    It keeps the earliest probe while the row count is unchanged, and it is
    **not a baseline** for change detection (link#273 must read loader rows
    only). **So an equal FWA `artifact_version_id` on two runs is evidence,
    not proof, that they read the same data.** A reload that keeps the row
    count is invisible to it. Check `row_count` / `size_bytes` beside it until
    #270 writes loader rows.
  - `kind` is `object` (versioned; a NULL identity is a gap), `api` (PSCIS,
    CABD: no version handle, NULL is permanent) or `derived` (`order_parent`).

  The bucket is versioned but cannot be listed (`?versions` is AccessDenied),
  so an id not recorded at load time is gone for good. At run open
  `.lnk_log_inputs()` copies this host's rows into `log_input.artifact_*`
  (the stream network row names the run's own `<WSG>.parquet`), which is what
  carries the identity home from a cypher before it is burned.
  `lnk_artifact_read()` lists every expected artifact, `missing` where
  nothing is recorded and `table_absent` where the record outlived its table
  (a `fresh` dropped by `state_clean.sh`). Only `snapshot_bcfp.sh --force`
  clears it: without `--force` a current ledger row exits before `--clear`.
  `log_input` never copies identity for a table the run cannot see.
  - **Restoring a schema alone (e.g. `schema_consolidate.R`'s
    `pg_dump --schema=fresh` backup) restores the table but not its record.**
    The record then names the later load. Re-run `snapshot_bcfp.sh --force`
    after any such restore.
  - **Its own schema, `provenance`, because it describes the database, not a
    run.** Run logs live beside their results (`<schema>.log*`, one set per
    persist schema). This table is what is loaded here, read by runs into
    every schema, and `state_clean.sh` drops `fresh` but not `provenance`, so
    loader rows that cannot be re-created (link#270's FWA rows) survive it.
- `log`, `log_input` and `log_recompute` carry `watershed_group_code` so
  `schema_consolidate.R` auto-discovers them. They are history, not per-group
  state: consolidate replaces their rows on the dispatcher by primary key (one
  key is one build) and never deletes them there by group (the source's copy
  is still cleared once copied), so a group copied home from a cloud host
  keeps its earlier builds' rows (link#354; before it, every cloud-built group
  kept only its newest row). The set is `.lnk_log_specs()`, read by the DDL
  and by consolidate. `log_parameters_fresh` / `log_parameters_habitat_thresholds` /
  `log_dimensions` deliberately
  do not (they key on `config_hash`), so **they do not yet travel between
  hosts** — follow-up PR.

**Guard notes (link#227).** `notes` may carry a downstream-guard record:
`link#227 guard(override): 3 unmodelled downstream dam(s) — PCEA(1), UPCE(2) — <justification>`
or `guard(warn): … at open`. Cross-check against the same row's `wsg_upstream`,
which independently records what was persisted when the run opened. See §8c.

**Env vars:** `LNK_RUN_UID` / `LNK_RUN_LABEL` (identify a dispatch — see §6c),
`LINK_GIT_DIRTY` / `FRESH_GIT_DIRTY` (dirty-tree flag for installed packages),
`FWAPG_GIT_SHA` / `FWAPG_DIR`, `LNK_BCFP_MODEL_VERSION` (bcfp reference pin),
`LNK_BCFP_BASELINE` (ledger path override), `LNK_HOST_ALIAS` (host name in
provenance rows), `LNK_LOG=0` (skip recompute logging — benchmarks only).

---

### Output vocabulary: naming what a build is (link#414)

A config name says how a bundle was made, and its contents move under that name.
The output's name is four tokens from `inst/extdata/vocabulary.csv`, one per axis.
`lnk_vocabulary_resolve(cfg)` derives them, and every `lnk_pipeline_run()` writes them
to its `log` row (`token_cut`, `token_acc`, `token_grad`, `token_flow`).

| Axis | Prefix | What it names | Spec matched |
|---|---|---|---|
| cut | `cut-` | break sources in order, `observation_breaks` (when observations cut), gradient classes, and which of the definite-barrier, control and habitat-classification files the bundle declares | canonical string |
| acc | `acc-` | the modelled species, each species' `access_gradient_max` and `observation_*` lifts, the presence table, `pipeline: observation_upstream` (resolved; #401), and the two access rules held in code (`.lnk_classes_bcfp`, `lnk_presence()`'s groups) | sha256 of the parsed values |
| grad | `grad-` | how segment gradient is measured | `gradient=segment` |
| flow | `q-` | `discharge_source` and `discharge_fill` | canonical string |

**A network is `cut` and `acc` together.** Since #326, gradient positions cut a stream
only where a modelled species' access changes, so the access rules move segments as
much as the break sources do. Two outputs with the same `cut` token and different
`acc` tokens are cut differently.

**What gets no token.** Habitat thresholds and rules, and width against flow: they
change flags, not segments, and a tuning chooses them. Data vintage: observation records,
the bcfishpass correction CSVs, `observation_exclusions.csv`, FWA and the discharge
loads. `config_hash` and `log_input` carry those. Same tokens means made the same way,
not necessarily from the same data.

**A config with no live token is refused** before the run opens. That covers a
changed break source, a new access gradient, an edited presence table, a bundle loaded
by path that differs from every named one, or `default_extrabreaks` and `default_rearbreaks`, which have no rows. The error
prints the spec. `study_area_run.sh`'s local pre-flight asks the same question once,
before any spend.

**Adding a token.** Add a row with `token`, `axis`, `definition` (prose that still makes
sense in years), `spec` (paste the one the error printed), `introduced` (the release
that ships it) and an empty `retired`. Then add a test of the config resolving to it in
`test-lnk_vocabulary.R`.

The rules:
- Tokens are lowercase, `^[a-z0-9]+(-[a-z0-9]+)*$`.
- A token is never renamed, never removed and never given a new spec: a changed
  definition is a new token, and the old row gets `retired`.
- Our own access rule sets are numbered (`acc-v1`, `acc-v2`, …), and the definition says
  what changed from the last one. A transcription of bcfishpass's rules is `acc-bcfp`,
  then `acc-bcfp-2` (#399), `acc-bcfp-3` (#401) and so on.
- `test-lnk_vocabulary.R` holds the rules against `origin/main`'s copy, in a checkout
  only. CI's shallow clone and `R CMD check` skip that test, so run it locally before
  merging an edit to the table.

**Code changes can need a token too.** The specs see the bundle, not the code. A
change to how fresh finds gradient barriers, to `frs_barriers_minimal()`, to the CT
alias expansion in observation breaks moves cuts with no
spec change, and a change to how the access walk reads a record moves codes with none
(#399 retired `acc-v1` and `acc-bcfp` for `acc-v2` and `acc-bcfp-2`; #401 retired those for
`acc-v3` and `acc-bcfp-3`, whose specs also hash `pipeline: observation_upstream`). Retire and re-add
the affected tokens in the same PR: the retired row and its successor then share a spec,
and `.lnk_vocabulary_match()` returns the live one. Changing
`.lnk_vocabulary_canonical()` or the digest inputs re-specs every `acc` token the same
way.

**The recompute is not checked.** `wsg_recompute_one.R` rewrites `streams_access` from
the config at the commit it runs, and `log_recompute` carries `config_hash` but no tokens.
A `--recompute-only` at a later commit whose presence table or lifts changed ships access
decided under rules other than the build's `token_acc`. Within one run the repo is frozen,
so this only bites a recompute run later: compare its `config_hash` with the build's.

**Rows from before.** Builds logged before link 0.70.0 have NULL tokens. The
consolidate copies the columns both sides share after bringing the destination's log
tables up to the dispatcher's link (`schema_consolidate.R`), so the dispatcher must run
this link or newer; under `load_all` it does.

## 6c. Run identity and the recompute log (link#262)

### Three identifiers, and they answer different questions

| column | scope | who mints it |
|---|---|---|
| `run_id` | **one per WSG** — the log's PK. A 217-WSG dispatch mints 217. | `.lnk_run_id()`, per `lnk_pipeline_run()` call |
| `run_uid` | **one per dispatch** — every host, every WSG of one run share it | `study_area_run.sh`, once, before anything forks |
| `run_label` | operator free text (`--run-label=`) | the operator; **never assume it is unique** |

Before this, "everything from the 2026-08-31 run" was answerable only by a time
window plus a host list — fragile at 34 WSGs on three hosts, ambiguous the
moment two runs overlap. Now:

```r
lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1")                    # modelling
lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1", phase = "recompute")
```

`run_uid` **overrides `latest`**: the question is "every row of this run", and
`DISTINCT ON` would hide a WSG re-run inside the same dispatch.

`RUN_UID` is deliberately **not** host-prefixed (unlike `run_id`) — all hosts
sharing one value is the entire point. Do not "fix" it by adding a host prefix.
The random suffix is not decoration either: two dispatches started in the same
second, which a re-run after a failure makes routine, would otherwise merge.

**Both legs or nothing.** The driver exports `LNK_RUN_UID`, `LNK_RUN_LABEL` and
`LNK_BCFP_MODEL_VERSION` to the local `Rscript` loop *and* inside the cypher ssh
command string. An export in the dispatcher's environment does not cross ssh, so
setting only the local one lands the id on the dispatcher's WSGs and NULL on
every cypher's — a half-labelled run that looks fine until someone queries it.
This is the same trap `LNK_GUARD_DOWNSTREAM` hit in §8c.

### `<schema>.log_recompute`

`data-raw/wsg_recompute_one.R` rewrites `streams_access` and
`streams_mapping_code` and settles `streams_habitat_<sp>` (link#349) — **the values that ship** — and until #262 recorded
nothing, so `log` said when a WSG was *modelled* and nothing about when its
persisted access last *changed*.

Its own table, not a `phase` column on `log`, because a recompute row in `log`
would win `lnk_log_read()`'s `DISTINCT ON` and be returned as "what produced
this network", which it did not. It carries `watershed_group_code`, so
`schema_consolidate.R` auto-discovers it with no list to maintain.

**Deliberately absent:** `log_input` rows (the recompute reads persisted tables,
not DB primitives) and the `bcfp_*` columns (it does not touch the reference).
Issue #262 asked for "the same provenance columns"; this is a considered
deviation, not an oversight.

**It never runs DDL.** The table is created by `lnk_persist_init()`, by every
modelling run, and once by `study_area_run.sh` immediately before the pool —
that last one covers the case where every dispatcher WSG species-skips and no
modelling run ever happens, which would otherwise hard-stop all N recomputes at
the end of a paid run. `.lnk_log_recompute_start()` asserts presence instead.

**`LNK_LOG=0`** suppresses the row. `recompute_sweep.sh` and
`recompute_parity.sh` set it: they re-run the same WSG set to measure the pool,
and their rows would be indistinguishable from a real post-consolidate
recompute — so the verify script's model-vs-recompute check would pass on
benchmark noise.

**A second or resumed consolidate keeps these rows.** `log_recompute` is
populated *after* consolidate, and consolidate leaves the log tables out of its
bucket DELETE: their rows are replaced by primary key, in one transaction per
table (link#354). Before #354 a re-consolidate over the same bucket wiped them.

**The recompute also settles habitat (link#349).** Between `lnk_access(merge = TRUE)` and the
mapping-code rebuild, `wsg_recompute_one.R` runs `lnk_habitat_gate()` on the group's persisted
habitat (§3), after copying the group's `access_<sp>` to `<persist>.zz_lnk_access_prior_<wsg>` so
it can count segments the recompute lifted while their habitat stays FALSE. Mapping codes are then
built by `.lnk_mapping_code_persist()`, the same helper `lnk_pipeline_run()` uses.

### The bcfp reference pin, tunnel-free

`bcfp_model_run_id` / `bcfp_model_version` were NULL on all 37 rows of the first
provenanced run. Not because nothing wrote them — `.lnk_bcfp_log_current()` has
been called at run open since #127 — but because it queries `bcfishpass.log`,
and the local docker fwapg holds **zero** `bcfishpass` tables. The run is
tunnel-free by design.

The reference is not the tunnel either: it is `fresh.streams_vw_bcfp`, a local
snapshot, and `snapshot_bcfp.sh` already records the build it loaded in
`data-raw/logs/bcfp_baselines.csv`. Querying a live `bcfishpass.log` at compare
time would name the build the tunnel is at *now* — it rebuilds weekly — not the
one the numbers were computed against. **A wrong pin, not a missing one.**

Three tiers, and `bcfp_pin_source` records which answered:

| tier | source | when |
|---|---|---|
| `env` | `LNK_BCFP_MODEL_VERSION` | every host of a driver run |
| `db` | `bcfishpass.log` | a real bcfp connection (the tunnel) |
| `ledger` | `bcfp_baselines.csv`, this host's latest row | local, hand-invoked |

Tier 0 exists because the ledger is **per host** and a cypher has no row of its
own — it git-resets the repo, so the file is present, but it never snapshots
under its own hostname. Without the export every cypher row lands unpinned: 13
of 34 last field run, the majority at 217. Same shape, same fix, as
`FWAPG_GIT_SHA`.

**`bcfp_model_run_id` stays NULL on the tunnel-free path and that is correct.**
`log.json` carries no such key. Honest absence beats a fabricated id — do not
"fix" it, and do not assert it in a verify script.

### Verifying a run

```bash
psql -h localhost -p 5432 -U postgres -d fwapg -v ON_ERROR_STOP=1 \
     -v run_uid=<uid> -v expected_n=<N> -f data-raw/study_area_verify.sql
bash data-raw/study_area_verify_negative.sh <uid>   # proves it can fail
```

`expected_n` is supplied from **outside** on purpose. Deriving the expected set
entirely from `fresh.log` is circular: a WSG that never produced a log row
vanishes from "expected", and that is precisely the failure the check exists to
catch. The old hardcoded 34-WSG `VALUES` list was the wrong externality, not
proof that none was needed.

Parameters reach the assertion block via `set_config`, not `:'run_uid'` — psql
does not interpolate its variables inside a dollar-quoted string.

---

## 6d. Publishing habitat: export, catalog, load (link#308)

`lnk_scenario_export()` → `manifest.json` → `lnk_catalog()` → `lnk_db_load()`,
on the pattern wet set for discharge (NewGraphEnvironment/wet#7). Driver:
`data-raw/habitat_publish.R` (BUILD, then `LNK_PUBLISH=1` to upload).

```
s3://fresh-bc/habitat/fwa/v1/            (private until opened; read with credentials)
  manifest.json
  segment/config=<config>/species=<sp>/part-<code>.parquet
  provenance/run_uid=<uid>/run_id=<id>/   log, log_input      one finished build
  provenance/run_id=<id>/                  log, log_input      a build outside a dispatch
  provenance/config_hash=<hex>/            log_parameters_habitat_thresholds, log_parameters_fresh
  provenance/recompute_id=<id>/log_recompute.parquet
  provenance/source_artifact/<md5>.parquet       this database's record at export, by content
  config/sha256-<hex>/<the files config_hash was computed over>
```

**The key is FWA position, `(blue_line_key, downstream_route_measure,
upstream_route_measure)`.** Break points differ by config, so `linear_feature_id`
repeats and `id_segment` is per group (#203). `(blue_line_key,
downstream_route_measure)` is unique within a persist schema across groups
(measured 2026-10-14: 0 duplicates in 1.83 M `fresh_default` and 3.80 M `fresh`
segments), so the loaded table's PK is `(config, species, blue_line_key,
downstream_route_measure)` and a duplicate fails the load. Neighbouring measures
do not abut exactly (sub-cm float slop); never join on equality of one segment's
upstream to the next one's downstream.

**What a group must have to be exported.** Its latest `<schema>.log` row (by
`date_start`) is a finished build (`date_end` set) of the config, for this
schema. Anything else — no row, another config's newer build, an open row —
leaves the group out (`wsgs = NULL`, listed in the manifest's `skipped`) or
stops (named `wsgs`; a group is taken from whichever of the config's schemas
holds its build). Provenance is keyed per finished build, never per dispatch:
a dispatch's set of rows grows as its other groups close and depends on which
schemas an export reads, while one build's log row does not change. A NULL
`run_uid` (a direct `wsg_run_one.R` run) is kept under
`provenance/run_id=<run_id>/`. Each config entry carries `exported`, which the
regressions judgement below reads.

**What each column means, and where it does not mean what it looks like:**

- **Species rows** exist only for the species the group's build logged. A
  modelled species with no habitat reads FALSE; an unmodelled one has no rows.
- **`accessible` is fresh's classification flag; `has_barriers_dnstr` is
  link's `streams_access`** (what mapping_code and `lnk_rollup_wsg()`'s
  `accessible_km` read). Since #349 the build settles the habitat flags on
  link's access (§3), so in a settled build every `accessible` row has
  `has_barriers_dnstr` FALSE; the reverse still occurs (fresh blocked a
  segment link calls accessible: at most ~1,000 segments per species
  province-wide). A build from before #349, or one whose recompute has not
  re-run since, holds the old disagreement (`research/access_columns.md`).
- **The near-river pair is not exported** (#364): a consumer sees the flags
  it produced, not the walked distances in `streams_near_river`. Carrying them
  would change the export's contract.
- **`mad_m3s`** is read at export from the table the run classified on, with
  the run's logged `discharge_fill`. It agrees with the flags while that table
  is unchanged.
- **Ratios** are against the thresholds the run *logged* at its
  `config_hash`. Builds before #282 logged none, so their spawning/rearing
  ratios are NA and `thresholds_logged` says so (2026-10-14: only DUNC in
  `fresh_default`; `fresh` has no thresholds log table at all). They compare
  with the CSV thresholds, not the rule that fired (river polygons spawn on
  any width), and no upper bound is in any ratio.

**Write-once vs replaced.** `segment/` and `manifest.json` are replaced per
config, and only once every config of the export has succeeded (parts are
staged under `.staging/`); an export carries forward the configs it does not
name from the root's manifest (after checking their md5s), so build into the
root that was published. `provenance/` and `config/` are never overwritten or
deleted. A provenance file that exists must hold the same *record*, not the
same bytes: Parquet's footer names the duckdb version, and a log column added
since (all NA) is not a change; a different record stops the export (a changed
record is a changed build). PUBLISH makes every check before its first write
(the root must not lose anything live, per the judgement below; each
write-once key absent or already these bytes), then puts new write-once keys with `--if-none-match`
and deletes only under `segment/`. A root rebuilt on another host re-serialises
provenance to other bytes, so seed it from the bucket (`aws s3 sync`) before
building; PUBLISH refuses rather than overwrite.

**An export replaces each config it names, wholesale**, so it stops when that
would drop a config's group:species pair the root holds, put an older build
of a group (earlier `date_start`, other `run_id`) in place of a newer one, drop
a recompute of the same build, or put an older export of the config (by
`exported`) whose parts differ in place of a newer one (the same builds read
at an earlier state of `streams_access`, the discharge table, or the export
code);
`replace = TRUE` (`--replace`) allows it. PUBLISH runs the same judgement,
`.lnk_manifest_regressions()`, against the live manifest
(`LNK_PUBLISH_REPLACE=1`). Each config entry records the link that exported it
(`exported_by`: version, sha, dirty, contract md5), because carried-forward
configs keep the link that computed them. Named `wsgs` and
`wsgs = NULL` both take each group from whichever of the config's schemas holds
a finished build of it, and stop only when a named group, or the config as a
whole, has none.

`provenance.source_artifact` is upserted as primitives reload, so the export
stores it as a content-addressed snapshot of this database's record at export
time; what a run actually read is its `log_input.artifact_*` (#265).

**Bundle files are published only when today's bundle hashes as the build
did.** Otherwise the manifest's `bundles[]` entry says the bundle has changed,
and the run's own `log_parameters_*` snapshots under `provenance/` are the
record.

**Not yet:** public read, versioning and PUBLISH gates on `run_uid` /
`link_dirty` (#334); discharge from wet's `discharge.fwa_v1_segment_monthly`
(#331); the desktop GeoPackage (#332); registering the column contract in crate
(#333; until then it is `inst/extdata/schemas/habitat_fwa_v1_segment.yaml`, in
crate's shape); the webmap (#335).

## 7. Where every rule lives

| Rule | File | Drives |
|---|---|---|
| Per-species gradient access threshold | `configs/<name>/parameters_fresh.csv` → `access_gradient_max` | gradient `blocks_species` (§2a) |
| Per-species observation override | `parameters_fresh.csv` → `observation_*` | barrier-skip via observations; feeds habitat (`lnk_pipeline_classify`) AND access (anti-join in `barriers_<sp>_access`, persisted as `barrier_overrides`, #200) |
| Habitat dimensions (which edge / waterbody types spawn or rear, lake/wetland rules, bypasses) | `configs/<name>/dimensions.csv` → `lnk_rules_build()` → `rules.yaml` | `frs_habitat_classify()` (token1 habitat) |
| Habitat thresholds (per-species spawn/rear gradient max, channel-width min/max, lake-area floor) | `configs/<name>/parameters_habitat_thresholds.csv` (#282) → `.lnk_habitat_thresholds_csv()` → `fresh::frs_params()` | numbers the `rules.yaml` rules inherit when they set none of their own |
| Through-wetland rearing (FWA 1050/1150) and the near-river scope | `dimensions.csv` → `rear_wetland_flow`, `rear_near_river` → `lnk_rules_build()` | the 1050/1150 rule's shape; `near_river: false` stamps (always on river-polygon rules) |
| The near-river pair (a river of at least a size within a distance downstream) | `parameters_habitat_thresholds.csv` → `<stage>_river_*` (#364, fresh#263) → `fresh::frs_params()` | inherited by every rule with a size test that is not stamped out; walked into `streams_near_river` |
| Species residence (resident/anadromous/spawn-only) | **hardcoded** defaults in `lnk_pipeline_mapping_code()` | which mc_barrier flavor + spawn-only token1 |
| Dam / anthropogenic blocking | **nowhere** — universal `all species` in `lnk_barriers_unify` | `blocks_species` (§2a). Not rules-driven. |
| What each config column means | `configs/dictionary_dimensions.csv`, `configs/dictionary_parameters_fresh.csv`, `configs/dictionary_parameters_habitat_thresholds.csv` | data dictionaries — per-column type, group, default, description, and (for `parameters_fresh`) `owner` + `consumed_by` file:line |

### Who owns which `parameters_fresh` column

**Do not re-derive this.** `parameters_fresh.csv` is co-owned, and the split is
settled:

- **fresh owns the 14 network-engine columns** — `species_code`,
  `access_gradient_max`, the two `*_gradient_min`, and the nine `cluster_*`.
  fresh ships them in its own `inst/extdata/parameters_fresh.csv`; link's
  bundles are seeded from it.
- **link owns the 5 `observation_*` columns** — fish-passage interpretation
  (counts, thresholds, date windows, species pooling, control veto).

The boundary was decided in
[fresh#129](https://github.com/NewGraphEnvironment/fresh/issues/129) (shipped
fresh 0.12.7), which *removed* `observation_*` from fresh after fresh#69 had
added them: "fish passage interpretation belongs in link, not the network
engine." Values may diverge freely per bundle — link tunes them — but the
**column set** is contractual.

Enforced in two places, both of which read `dictionary_parameters_fresh.csv`'s
`owner` column rather than hardcoding the rule:
`data-raw/audit_configs.R` §3b (pre-trifecta gate) and
`tests/testthat/test-dictionaries.R` (runs in CI, since `data-raw/` is
`.Rbuildignore`d). Direction of travel is opposite for the two shared artifacts:
`rules.yaml` flows **link → fresh** (link owns the generator, `lnk_rules_build()`);
the `parameters_fresh` column schema flows **fresh → link**.

Three gaps worth knowing: **species residence** is hardcoded (data-drive is
follow-up #189), **dam blocking is not rules-driven** at all (universal), and
`rear_gradient_min` is carried in the schema but **read by no code in either
package** — it is fresh-owned, so removing it is a fresh-side call.
If dam blocking should ever become species-specific, it's a new
per-source-per-species column + `lnk_barriers_unify` change — not a tweak.

### Where habitat thresholds live (#282)

Each bundle carries its own `parameters_habitat_thresholds.csv`, declared under
`files:` with provenance. Before #282 every bundle ran fresh's installed copy,
so a threshold change moved the parity reference too.

- **bcfishpass's copy is frozen.** It is fresh's file byte-for-byte (bcfishpass
  `parameters/example_newgraph` + fresh's edge-type columns). csv-sync ignores
  it (`source` is fresh, not bcfishpass). Tune in `default_tuned`, never here.
- **A bundle that declares none falls back to fresh's copy**, with a message, and
  its `config_hash` then covers that file as `fresh:parameters_habitat_thresholds.csv`.
- **Not every column is live on link's path.** Rules inherit gradient and channel
  width; `*_mad_*` replace channel width only for watershed groups the bundle's
  method table puts on `mad` (next section); `spawn/rear_edge_types` are read only
  on fresh's no-rules fallback. `rear_lake_ha_min` is **baked into `rules.yaml`**
  by `lnk_rules_build(thresholds =)`, so changing it needs a rules rebuild.
  The dictionary's `consumed_by` column has the file:line for each.
- **Runs record the values** in `<persist>.log_parameters_habitat_thresholds`
  (keyed on `config_hash`), beside `log_parameters_fresh`.
- **`default_tuned` is a thin bundle** (`extends: default`). Inherited provenance
  entries carry `.dir`, `cfg$chain` lists the extends directories, and
  `.lnk_config_hash()` hashes every `config.yaml` on the chain and names inherited
  files `extends:<bundle>/<rel>`, sorted in byte order (not `LC_COLLATE`), so the
  hash is the same on every host. A relative `extends:` path resolves against the
  child bundle, not the working directory. Before
  #282 no shipped bundle extended anything, and all three of those were broken.

### Channel width or discharge, per watershed group (#286)

Each bundle also declares `parameters_habitat_method.csv` (`watershed_group_code`,
`model` = `cw` | `mad`), and `lnk_pipeline_classify()` passes it to
`fresh::frs_habitat_classify(params_method =)`. That needs fresh >= 0.35.0; the
preflight asserts the argument (`required_formals`), not the version, so **a cypher
image still on an older fresh hard-fails at preflight — re-prep hosts before the
next dispatch.**

- **Every shipped bundle is all `cw`**: a frozen copy of bcfishpass
  `parameters/example_newgraph` (188 groups). Outputs did not change (ADMS and BULK
  `streams_habitat` digests identical against main on fresh 0.33.0 and 0.36.2,
  `data-raw/logs/params_method_286/`).
- **Frozen, not csv-synced.** Its provenance `source` is deliberately not the
  bcfishpass URL: `sync_bcfishpass_csvs.R` syncs and auto-merges any entry with
  that exact source, which would let an upstream `cw` → `mad` flip change
  `default` unreviewed (and miss the two `default_*breaks` bundles).
  `derived_from` carries the upstream path. Moving a group is a reviewed row edit,
  which moves `config_hash`.
- **Fallback and override** mirror the thresholds: no declaration means fresh's
  copy, hashed as `fresh:parameters_habitat_method.csv`; `method_csv =` on the call
  wins over both. A group the table does not list is `cw`.
- **`mad_m3s` is joined onto the working streams** (`working_<wsg>.streams`, from
  `whse_basemapping.fwa_stream_networks_discharge` on `linear_feature_id`) for
  every group, survives breaking, and is **never persisted** (`cols_streams` does
  not carry it). A DB without the discharge table now fails prepare for every
  group. `log_input` fingerprints it. Every reader goes through one builder,
  `.lnk_discharge_sql()` (`R/lnk_discharge.R`): prepare, the validator and the
  variants harness. The #302 calibration scripts read the raw table on purpose,
  because the ranges were set with NULLs excluded. prepare writes `mad_m3s` as
  `double precision` itself, because `frs_col_join()` types a subquery's columns
  `text`.
- **What `mad` changes** (fresh's rules, after bcfishpass): stream rules that
  inherit thresholds test `mad_m3s` against `*_mad_min/max` instead of channel
  width, so species with no MAD thresholds (BT, GR, KO and RB in `bcfishpass`)
  lose all stream habitat; the rule-level `channel_width` river-polygon bypass is ignored; SK/KO
  lake rearing is polygon membership. **Lake, wetland and `thresholds: false`
  rules inherit nothing under either model**, so BT keeps its wetland and
  1050/1150-edge rearing in a `mad` group (ADMS, measured on `default` before #307
  gave BT a range: 63.5 km, all inside waterbodies). The separate `lake_rearing` /
  `wetland_rearing` bucket columns (fresh's `build_wb_pred()`) are polygon
  membership plus the rule's area floor under either model, from fresh 0.37.0
  (fresh#240). Before that they were gated by the species' rear size range, which
  sized the line through the polygon.
- **A wetland floor bounds `rearing` as well as the bucket (fresh ≥ 0.38.0,
  fresh#237; link#311).** fresh compiles a W rule's `wetland_ha_min` into the main
  rear predicate, and `lnk_rules_build()` puts a declared `rear_wetland_ha_min`
  on both wetland rear rules: the polygon mainline rule (1000/1100) and the
  1050/1150 wetland-flow carve-out, which then becomes `waterbody_type: W`.
  - **Order is load-bearing.** fresh takes the **first** W rule in `rear:` as the
    `wetland_rearing` bucket rule and as the `requires_connected` anchor
    (`.frs_find_waterbody_rule()`), so the floored carve-out is emitted after the
    polygon rule.
  - A species with no floor keeps the unfloored carve-out in its old place, so the
    `bcfishpass` rules are byte-identical.
  - Nearly every 1050/1150 line sits in a `fwa_wetlands_poly` polygon. The W type
    drops the exceptions: 40 edge-1050 lines (about 6.6 km) province-wide with no
    `waterbody_key`, none of them in NATR, PARS, ADMS or BULK.
  - The floor bounds the two wetland rear rules, not every line in a small wetland.
    The stream rule (`[1000, 1100, 2000, 2300]`, no waterbody test) still admits
    mainlines in sub-floor wetlands (0–0.62 km per floored species on those four).
  - fresh admits a `waterbody_key` when **any** of its polygons meets the floor.
- **Lake and wetland rearing connected to spawning; lake centrelines in `rearing`
  (link#310).**
  - `rear_lake_connected_distance_max` / `rear_wetland_connected_distance_max` (m) put
    `requires_connected: spawning` + `connected_distance_max` on the species' **first**
    rear L / W rule. That is the only rule fresh reads for the bucket, and it refuses the
    keys on any other rule (`.frs_validate_rear_connected()`).
    - A polygon keeps `lake_rearing` / `wetland_rearing` when same-species spawning lies on
      it, or within the distance downstream, or upstream traced down mainstem lines.
    - `default` uses 10 km for every lake/wetland rearer except SK and KO.
  - **The distance filters only the bucket.** Lake centrelines reach `rearing` through the
    L rule, which now admits lake and reservoir lines
    (`1000/1100/1200/1250/1300/1350/1400/1450/1475`; lakes hold construction lines, not
    mainlines). They then go through the rearing cluster pass like any stream. So a lake's
    hectares and its km follow different tests. RB has `cluster_rearing = FALSE`, so
    its lake km follow none.
  - **The spawning anchor is fresh's first rear L or W rule** (`.frs_run_connectivity()`).
    In the additive branch W comes before L. `lnk_rules_build()` refuses connected rearing,
    and an `area_only` anchor, on a species with `spawn_requires_connected = rearing`.
  - **Reservoirs:** fresh's rule compiler reads `fwa_lakes_poly` + `fwa_manmade_waterbodies_poly`.
    Its `lake_rearing` bucket reads lakes only (fresh v0.39.0), so reservoir lines rear but
    are never `lake_rearing`.
  - **Rollups split `rearing` km by the polygon each line sits in, not by edge type.**
    `rearing_stream` / `rearing_lake` / `rearing_wetland` partition `rearing`.
    - The polygon is matched by `waterbody_key` against those polygon tables, not
      `fwa_waterbodies`, which has no row for ~23,000 km of lake/wetland/reservoir lines.
  - **`lnk_habitat_validate()` reads a bucket cleared by the connection test as
    `post_predicate`.** Its lake / wetland predicates come before the connection test, so a polygon
    that is too far from spawning passes the predicate and then is not habitat.
    - `lake_rearing` / `wetland_rearing` are hectares of the same water; never add a km
      to a ha.
- **Lake connection lines: in `rearing`, out of the km (link#317, #319).**
  - FWA connectors (1450, "Construction line, connection") join each tributary mouth to the lake's
    main-flow line (1200), so a lake's line km grow with its tributary count. Adams Lake
    holds 148.8 km of 1450 against 62.8 km of 1200.
  - **Construction flow lines are not connectors.** 1400 ("other flow / inferred connection") is a
    construction flow line like 1200 / 1300 and stays in the km.
  - **The flag keeps them.** The L rule still admits 1450, so `cluster_rearing`
    still joins inlet rearing to the lake. Nothing re-classifies.
  - **The compare rollups leave them out.** `lnk_compare_rollup()` / `lnk_compare_wsg()` report
    them as `rearing_lake_connection` (km), out of `rearing` and `rearing_lake` km, on the link
    side and the bcfishpass side alike. bcfishpass counts them too, in BT and SK rearing, so
    SK parity stays 0.0 %. One predicate: `.lnk_sql_lake_connection()`
    (`R/lnk_rollup_wsg.R`), which is lake-polygon lines on 1450, NULL-safe.
  - **`rearing_km` means one thing in link's WSG rollups (#319).** `lnk_rollup_wsg()`'s default
    `rearing_km` leaves them out and its default `rearing_lake_connection_km` carries them
    (0 where there are none), so the two sum to the flag total (to rounding; `rearing_km` is
    NA in a group whose only rearing is connection lines). That reaches the validator's
    cost, and `data-raw/parity_crosssection.R` / `wsg_vignette_data.R` apply the same predicate
    to `fresh.streams_vw_bcfp`, which carries `edge_type` and `waterbody_key`.
  - **Capture still reads the flag.** About half of in-lake fish records (bcfishobs A / B) sit on
    a 1450 line, because a lake fish is matched to the nearest line, so they are evidence for the
    lake. `lnk_habitat_validate()`'s roxygen carries the table.
  - **`accessible_km` splits by access code too (#403).** The default
    `accessible_observed_km` (`access = 2`) and `accessible_unobserved_km` (`access = 1`) sum over
    the rows `accessible_km` sums, so the pair sums to it (to 0.01 km a column) and all three are NA
    together where access is not built. The validator's `summary` carries all three. What code 2
    means, and where it ends relative to a species' top record, is §2c.
  - **`lnk_aggregate()` still sums the flag**, connection lines included: it is per-crossing,
    link-side SQL over boolean habitat columns, with no connection split. So do the older
    one-off scripts with their own SQL (`data-raw/compare_adms.R`,
    `data-raw/exp_gradient_extra_breaks.R`).
  - SK / KO lake rearing is mostly 1450, so their compare `rearing` km drop sharply: SK
    55–95 % on seven measured WSGs (ADMS 159.1 of 229.9 km), KO 62 % on NATR. For SK the
    drop is the same on the bcfishpass side; KO has no bcfishpass reference.
- **`default` and `default_tuned` carry MAD ranges for BT, GR, KO and RB;
  `bcfishpass` does not.** `default`'s are its own channel-width minima converted
  to discharge (#307: spawning 2 m → 0.041, GR 4 m → 0.20, rearing 1.5 m → 0.021
  m³/s, the median `mad_m3s` at that modelled width,
  `data-raw/query_width_mad_equivalent.R`); `default_tuned`'s are calibrated on
  fish observations (#302). Under fresh < 0.37.0 a rear range also gated the
  `lake_rearing` / `wetland_rearing` buckets, so they shrank under `mad`. That was
  an artifact of sizing a polygon by the line through it, and fresh#240 removed it
  (link pins fresh v0.39.0 from #311). Since #310 `default`'s buckets keep
  only polygons connected to same-species spawning, except SK's and KO's (their spawning
  is anchored on their lake rearing). All are inert until a group is moved to `mad`. At
  `default_tuned`'s values a `mad` group keeps less stream rearing than `cw`
  (held-out, with the #305 fill: −32 % BT, −76 % GR, −2.8 % RB); at `default`'s,
  the two models agree within about 5 % (NATR, ADMS; #307). Read `research/habitat_thresholds.md`
  before moving one. link also skips the stream-order rearing bypass
  (`frs_order_child`) for a `mad` group — bcfp applies it in its cw branch only.
  On a `cw` group, a bypass rule carrying `width_known_below_min: true` (written by
  `lnk_rules_build()`; the `bcfishpass` bundle sets `rear_stream_order_bypass = yes`
  for BT, CH, CO, ST and WCT since #326) also passes `channel_width_max` and
  `gradient_max`, taken from that rule's range or else the species' rearing thresholds
  (`.lnk_order_child_bounds()`, an error if either is missing). So only a known width
  at most the minimum within the rearing gradient qualifies, and a NULL width never does.
  bcfishpass tests below the minimum; a line at exactly the minimum already rears through
  the ordinary width test, so nothing moves (none in the 11 cross-section groups; `data-raw/logs/segmentation_326/order1_width_at_min.log`). Two differences remain, listed in `?fresh::frs_order_child`:
  fresh keeps its direct-child test (`stream_order = stream_order_max`, fresh#158;
  PARS BT 8.1 km), and applies no CH / CO / ST / WCT waterbody or edge filter (at most
  2.7 km per species per group, `data-raw/logs/segmentation_326/`).
  fresh does not implement bcfp's `stream_order >= 8` spawning bypass.
- **Discharge coverage is uneven.** A segment with NULL `mad_m3s` fails every mad
  test, so a `mad` group without coverage loses all of its stream habitat with no
  error. BULK has none in the local fwapg; 123 groups have any. Check
  `count(mad_m3s)` before moving a group.
- **River-polygon main stems are filled under `discharge_fill`** (#305;
  `default_tuned` only, absent means off). Inside covered groups, 22 % of edge 1250
  km has no value: rows missing from the table or rows with a NULL value, almost all
  order 4+. #300 measured that gap as `mad`'s most-used loss. An edge 1250 line with
  no value takes, in order:
  1. the nearest valued line upstream on its `blue_line_key` (a lower bound);
  2. else the nearest valued line downstream on it;
  3. else the largest value on any line upstream of it, which reaches a river with
     no value anywhere (the Beatton).

  Never the receiving river downstream. `mad_m3s_source` names the tier.
  - **Where it runs.** Only in groups the table covers (an uncovered group stays all
    NULL, so `count(mad_m3s)` still detects one). Only where something reads
    discharge: a `mad` group in `cfg`'s method table, or a rule-level `mad:`
    (`.lnk_discharge_fill_applied()`). An all-`cw` `default_tuned` run fills nothing.
  - **What stays NULL.** Other edge types are never filled. What is left is mostly
    1,862 km of NULL-valued rows in 12 northern groups whose tributaries are NULL too.
  - **Recorded state.** The applied state is logged per WSG
    (`<schema>.log.discharge_fill`). The validator refuses a WSG logged with another
    state than its `cfg` applies, and the variants harness carries the state in
    `built.csv`.

  `data-raw/logs/discharge_fill_305/`, research "`cw` against `mad`".
- **Where discharge is read from is a bundle setting, `discharge_source`** (#331).
  `fwapg` (the default, and what every run before #331 read) is
  `whse_basemapping.fwa_stream_networks_discharge`. `wet` is the annual pick of wet's
  published `discharge.fwa_v1_segment_monthly` (`scenario = 'historical'`,
  `month = 0`, `pick`), which values about 4.5 M lines against fwapg's 2.0 M (rows 4.53 M and 2.72 M)
  (PCIC's routed model where it has one, wet's water balance elsewhere). Load it into
  a database once with `wet::wet_db_load(conn, wet::wet_catalog())` before a run
  reads it.
  - **One relation.** `.lnk_discharge_rel(source)` has fwapg's shape
    (`linear_feature_id, watershed_group_code, mad_m3s`), and prepare, the fill, the
    validator, the export and the variants harness all read through it.
  - **Recorded state.** It is logged per WSG (`<schema>.log.discharge_source`; NULL
    on an older row, which read fwapg). The validator warns about a WSG whose logged
    source differs from its `cfg` where `cfg` reads discharge (a warning, because the
    MAD producer measures wet at observations on `cw` builds through the validator),
    and the export's manifest names the source per WSG.
  - **Every host that runs a wet config needs wet's table**, `cw` groups included,
    because prepare joins discharge for every group; prepare stops with the load
    command when it is missing. `lnk_preflight_discharge(conn, cfg)` checks a database.
    `data-raw/discharge_wet_load.R` loads the annual pick only (`months = 0,
    pick_only = TRUE`, about 4.5 M rows) and skips a host that already has it.
    `study_area_run.sh` gates the dispatcher on the config's source and passes it to
    `cypher_prep.sh` (`CYPHER_PREP_DISCHARGE=wet`), which installs wet at its
    DESCRIPTION pin and loads it after the snapshot.
  - **Which load a build read.** wet's loader writes its manifest URL, build time and
    commit into the table's comment; `log_input.table_comment` copies it at run open,
    and a wet run adds wet's table to its fingerprinted inputs. The export manifest's
    `discharge.wet_load` sets the logged loads beside the exporting database's and
    says whether they match (by build, ignoring wet's `; subset` suffix). wet's table
    is not a vintage-gate primitive: it is a published, versioned dataset, and a host
    running an fwapg config must not need it.
- **`lnk_habitat_validate()` scores each group on its own model** (#299), from the
  `cfg` it is handed, resolved by fresh's `.frs_habitat_models()` (one rule for classify
  and validator). A `mad` group's predicates and size relaxation read `mad_m3s`, joined
  from the discharge table on `linear_feature_id` (filled when `cfg` fills, scoped to
  the scored lines); reason labels are shared with `cw`
  and the `model` / `mad_m3s` columns split them, plus `no_mad_threshold` for a species
  with no MAD range. To score a run made with a swapped method table, swap it on the
  same `cfg` object (`cfg$files$parameters_habitat_method$path`) before validating:
  `lnk_pipeline_classify(method_csv =)` is invisible to the validator.
- **Connectivity reads no size model.** `.frs_run_connectivity` takes no
  `params_method`; its one width test (`.frs_connected_waterbody`,
  `spawn_connected_cw_min`) is 0 for SK/KO in every bundle, so it is inert.

---

### Through-wetland lines and the near-river pair (#364)

Two rule decisions moved into the data, and one number set moved into the
thresholds.

- **`rear_wetland_flow` (dimensions.csv) says how FWA 1050 / 1150 lines rear.**
  - `stream` emits a rule that inherits the species' rear gradient, size and
    near-river pair exactly as the stream rule does: no `thresholds: false`, no W
    type, no wetland floor. `default` uses it for every `rear_wetland = yes`
    species.
  - `gradient` emits `thresholds: false` plus `gradient: [0, rear_gradient_max]`
    from the bundle's thresholds row, which is bcfishpass's coho rule. The
    `bcfishpass` bundle uses it for CO.
  - `free`, or blank, emits `thresholds: false` with no test, as before #364.
  - The rule is emitted as `edge_types_explicit: [1050, 1150]` in both edge
    modes, because fresh's `wetland` category is 1700 shorelines.
  - The wetland floor (`rear_wetland_ha_min`) stays on the W polygon rule only.
- **The near-river pair is a threshold** (fresh ≥ 0.42.0, fresh#263). Ten
  columns, `<stage>_river_{measure, discharge_min, channel_width_min,
  stream_order_min, distance_max}`, in `parameters_habitat_thresholds.csv`.
  - fresh inherits the stage's pair on every rule that inherits thresholds and
    has a size test, and walks the network for it into
    `<working>.streams_habitat_near_river`.
  - `measure` is `model` when blank: channel width under `cw`, discharge under
    `mad`. Under `model` both `_channel_width_min` and `_discharge_min` must be
    set.
  - A rule opts out with `near_river: false`. `lnk_rules_build()` writes no
    numbers, only those opt-outs.
- **`rear_near_river` (dimensions.csv) is the pair's scope**: `both` (the stream
  or all-edges rule and the 1050/1150 rule), `stream`, or `wetland_flow`.
  `default` gives CH `wetland_flow`, with the pair model / 15 m / 3 m³/s within
  1,000 m: the operator's call on 2026-10-21, after `both` added 275.6 km of
  CH rearing on five held-out groups where CH are found at 5 % of the core rate
  (`data-raw/logs/wetland_door_364/`). Every other species' pair is NA.
  - The builder stamps `near_river: false` on the inheriting rear rules outside
    the scope, and always on the river-polygon rule (spawn and rear), because a
    river polygon is the river.
  - The spawn stream rule always takes the spawn pair.
  - Never on an L / W rule (fresh refuses the key there) or a `thresholds:
    false` rule (where it is a no-op).
  - A combination that can emit nothing stops the build: `wetland_flow` without
    the stream door, or `stream` with no stream rule.
- **What reads discharge.** `.lnk_discharge_read_rules()` asks fresh's resolver
  (`.frs_near_river_specs()`, through `.lnk_near_river_pairs()`) whether any pair
  measures by discharge under `cw`, or any rule carries `mad:`. Under `model` a
  `cw` group measures rivers by channel width, which fwapg carries on every
  river-polygon row, so `default` needs no discharge fill for its pairs.
- **Persisted and logged.** `<schema>.streams_near_river` keeps the walked
  distances, keyed by segment and pair. `<schema>.log.near_river` records each
  WSG's pairs as `measure:threshold:distance_max`, `;`-joined, `""` for none. The
  validator re-tests near-river predicates against the persisted table. It
  refuses a schema with no table when cfg reads a pair, and a log whose pairs
  differ. So a schema built before #364 cannot be validated under a bundle with a
  pair until it is re-modelled.
- **The frozen bundles** (`default_extrabreaks`, `default_rearbreaks`) carry no
  near-river columns. `audit_configs.R` reads that as no pair, not a stale copy,
  and compares their rules with the inert `near_river: false` removed.

## 8b. Drainage closure: never hand-roll it from ltree

**Use `lnk_wsg_resolve(cfg, loaded, wsgs, conn = conn)`.** It delegates to
`fresh::frs_wsg_drainage()` (fresh >= 0.33.0), which tests per-group outlet
**points** (`blue_line_key` + `downstream_route_measure`) with the measure-aware
`whse_basemapping.fwa_downstream()`.

**Do not** compute closure from `wscode_ltree` ancestry (`a.outlet @> b.outlet`).
That was the pre-#227 method and it silently over-includes, because **two watershed
groups on the same stream share an outlet code** — so `@>` is true in *both*
directions and calls each one downstream of the other. Closure is measure-aware,
not code-aware. This is why `c("PARS","BULK")` dropped from 15 WSGs to 9 when
#238 adopted fresh 0.33.0.

**Worked example — the Kootenay, where it bites hardest.** FWA carries the whole
river under one continuous `wscode_ltree = 300.625474`, including the stretch that
leaves BC near Newgate, runs through Montana and Idaho, and re-enters at Creston.
Measures chain with no gap:

```
LARL 0–130 → KOTL 130–431,808 → BULL 431,808–495,206 → SMAR 495,206–608,735 → KOTR 608,735–773,149
```

So KOTR/SMAR/BULL are **upstream** of Kootenay Lake, reached via the US loop — but
an ltree test sees them sharing KOTL's outlet code and reports them as downstream.
The correct closure of `c("LARL","KOTL","SLOC")` is **just those three**: LARL is
the terminal BC group (it holds the Kootenay's mouth at Castlegar and the Columbia
down to the border — hence Waneta and Seven Mile sitting in it), and below it is
the United States.

**`public.wsg_outlet` is gone as a concept** (#227). If you find the table in a
database it is a leftover from before fresh 0.33.0 — it still answers queries, and
it answers them wrongly. Outlets now ship in fresh at `inst/extdata/wsg_outlet.csv`
and reach the DB as a `VALUES` list; no table is needed anywhere.

## 8c. Downstream state: the guard, and why membership ≠ path

`lnk_pipeline_run()` computes accessibility from the **already-persisted**
barriers of the WSGs downstream. Model a WSG before them and the access query
finds no downstream dams, marks dammed-off segments accessible, and **exits 0** —
a wrong answer indistinguishable from a right one. `lnk_wsg_downstream_check()`
(link#227) verifies that precondition instead of trusting it.

**The predicate is PATH, not membership.** The question is not "does a downstream
watershed group *contain* a blocking dam" but "is there a blocking dam **on this
WSG's downstream flow path**". Measured live:

| focal | membership | path | reality |
|---|---|---|---|
| **BULK** | fires — 18 blocking dams across LSKE/KISP/KLUM | **0** | none are below BULK's outlet |
| **PARS** | fires | **3** | Peace Canyon, Site C, W.A.C. Bennett — correct |
| SLOC | fires | 1 | Brilliant Dam — correct |

A membership guard cries wolf on BULK, operators learn to reach for the override,
and the guard stops meaning anything. **Do not "simplify" it back.** The path form
is complete, not merely cheaper: access walks downstream from every segment, and
every focal segment exits through the focal outlet, so the out-of-WSG barriers
reachable from *any* focal segment are exactly those below the outlet. ~0.5 s.

**What counts as blocking** — three filters that live downstream of
`.lnk_pipeline_prep_dams`, all mirrored by the guard:
`passability_status_code IN (1,2)`; a real `linear_feature_id` join; and
`blue_line_key = watershed_key` (mainstem only). The psc filter is why the
`cabd_additions` US placeholders never appear under the `bcfishpass` bundle —
they carry NULL. Under `default` (`pipeline: cabd_additions_barriers`) they are
barriers, and the guard probes them through the same `.lnk_dams_usa_sql()` as
`.lnk_pipeline_prep_dams()` (link#367). **So under `default` a group upstream of
one (the BC Columbia above the border, the Kettle, the Skagit) fails the guard
until KETL, LARL and SKGT are persisted at link 0.68.0 or later**: a schema built
before then holds no placeholder barriers, and `wsg_recompute_one.R`'s
error-mode check refuses those groups until they are re-modelled.

**Persistence is checked per DAM, not per WSG** — `.lnk_wsg_persisted()` cannot
tell a group persisted with `dams = FALSE`, which would pass a schema holding the
streams but not the barriers.

**Modes.** `LNK_GUARD_DOWNSTREAM=error` (default) | `warn` | `ignore`.
`study_area_run.sh` exports **`warn` on both legs** (local subshell *and* inside
the ssh string) because on a multi-host run a downstream group is legitimately
mid-flight on another cypher. That is a deferral, not a hole:
`wsg_recompute_one.R` re-runs the guard in `error` mode after consolidate, when
everything must be persisted. A hard pre-flight there would be worse than the bug —
per-WSG failures soft-fail, so the WSG would be **skipped**, and
`lnk_access(merge = TRUE)` cannot repair a WSG that was never modelled.

**Override** requires a written justification (`LNK_GUARD_DOWNSTREAM_NOTE`); a
bare `TRUE` is rejected. The note lands in `<persist>.log.notes` beside
`wsg_upstream`, so `lnk_log_read()` reports that the network was built on a
stated assumption.

**Known bound:** inherits `frs_wsg_drainage()`'s one-outlet-per-group model. A
WSG draining by two independent paths would be under-covered.

---

## 8d. Pre-flight gates on a multi-host run (link#246)

**Before any provincial run, run the pre-run gate** (`data-raw/pretest_run.sh`,
link#372, below). `preflight_local()` refuses a run that no passing gate record
clears.

A study-area run spends money and writes to a shared persist, so the gates in
`study_area_run.sh` sit in **two** blocks answering two different questions.

**Why two, not one.** A cypher's software is *predictable* from the dispatcher
before the cypher exists: its link comes from `git reset --hard
origin/$LINK_BRANCH`, its fresh from link's `DESCRIPTION`. So `preflight_local()`
validates what the workers are *going to get* — free, before the spin — and
`preflight_hosts()` confirms after prep that they got it. Predict before spend;
verify before write. Framing it as one gate forces a false choice between
checking early and checking truthfully.

`preflight_hosts()` genuinely cannot run earlier, and that is fine: it runs
before any `wsg_run_one.R` touches the persist, and a failure exits 1, which
trips the EXIT trap and burns the cyphers. The loss is bounded at spin + prep
rather than a whole run of two mixed model versions landing in one schema with
no `log` table to tell them apart.

**No global bypass, on purpose.** An unconditional `--skip-preflight` is the
affordance that let this class of failure happen. `--preflight-note="<why>"`
downgrades *only* vintage and parity, and only with a written justification —
the same position `lnk_wsg_downstream_check(override=)` takes. `--auto-install`
is remediation, not a skip: it re-runs the cyphers' install stage (which re-runs
the fresh assertion) and re-checks exactly once.

**A fresh bump reaches every host only through that assertion.** Since link#394 the pin is
fresh v0.47.0, and `lnk_preflight_fresh()` asserts `frs_network_features(result)`, the
existence walk `lnk_pipeline_access()` calls. A worker or cloud host still on 0.44.0 fails
preflight rather than reaching a walk with an argument it does not take. Nothing is done by
hand: a cloud host installs fresh at prep from the `Remotes:` pin, and a persistent worker
gets it when the run is launched with `--auto-install` (`worker_prep.sh`'s `install-fresh`
stage), which re-checks its `RemoteSha` against the dispatcher's.

### The pre-run gate (link#372)

On 2026-10-23 the provincial run was the first contact between new code and
OKAN and KTSU, and the dispatcher lost about five hours to them while three
cloud hosts idled. A rule's cost is driven by an input the test groups did not
carry, so the gate models the groups at the extreme of each input that the
changed code drives, on the dispatcher, before anything is spent:

```bash
bash data-raw/pretest_run.sh --config=default --schema=fresh_default
```

(bash 5.1 or later, as the driver). It prints its decisions, then:

- **What changed.** link's files under `R/`, `inst/extdata/` (the run's bundle
  and what it `extends`; other bundles are left out), `DESCRIPTION` and the
  run's `data-raw/` entry points, between `--since` and HEAD. fresh's `R/`
  and `inst/extdata/` (link reads its `falls.csv`, the downstream guard its
  `wsg_outlet.csv`) between the two `Remotes:` pins, read from the fresh
  checkout beside link (`--fresh-repo=`). `--since` defaults to the link SHA of
  the earliest of the groups' newest finished builds under `--config` in
  `<schema>.log`: the last run, even where a group was re-modelled by hand
  after it. A range must hold every one of those builds (start at or before
  each, and each an ancestor of the range's end, so its code is in the diff);
  one that does not is refused before anything is modelled (a warning under
  `--pick-only`, which records nothing).
- **Which input each file drives.** `data-raw/pretest_inputs.csv` (repo, path
  regex, input, why). `{config}` in a pattern stands for any bundle in the
  chain. Inputs are queries, `data-raw/pretest/<input>.sql`, each returning
  `(watershed_group_code, value)` for every group: `near_river_conn` (fresh's
  walk prefilter, the longest connector run), `segments`, `gradient`
  (segments at 15 % or more), `observations`, `obs_upstream` (raw bcfishobs records
  upstream of the group's outlet, every group's: a ranking proxy for what the access walk reads
  since #401, which keeps each by its group's presence), `crossings`
  (PSCIS), `dams` (CABD). Three special values: `any` (every pick runs it; alone, the fastest
  group is picked), `none` (off the modelling path), `unexercised` (on the
  run's path but not the gate's: the recompute, the consolidate, the habitat
  gate). **A changed file the map does not name refuses the gate (exit 2):**
  add a row naming what drives its cost. `test-pretest.R` checks that every
  file in `R/`, `inst/extdata/` and the entry points has a row, and that no
  `none` row names a file the static call graph from `wsg_run_one.R` reaches
  (`pretest_reach()`, which also follows `getFromNamespace()` strings); the
  pick and the driver's check walk the same graph at the code they see, so a
  changed `none` file the path reaches is treated as on it. For fresh the pick
  walks fresh's graph at the tag the range ends on, from a temporary worktree
  of the fresh checkout, whenever the range changes a fresh file mapped `none`
  (`data-raw/pretest_reach_fresh.R <fresh dir>` prints it); a test checks it at
  the DESCRIPTION pin. A file relabelled inside the range is matched against
  the map at both ends, so a relabel to `none` cannot hide its own edit.
- **Which groups.** Each input's top `--per-input` groups (default 2) among
  groups with a finished build in `<schema>.log`, ties by code; the union is
  modelled, largest history first.
- **The bound.** k (`--k`, 3) times the group's newest finished minutes in
  `--minutes-schema` (default `--schema`), never under `--floor-min` (5). A
  group in `--minutes-exclude` (a known stall, as KTSU's 65 min on 2026-10-23)
  or with no row is bounded on the median. Each statement is bounded at
  `min(--statement-timeout, ceil(bound))`, and a wall-clock watchdog kills the
  group at its bound and terminates its backends by application name
  (`pretest_<WSG>`), so a stall fails within the bound, not after it.
- **Where.** A scratch schema, `fresh_pretest_<config>`, dropped and rebuilt
  with the persist schema's tables (columns, defaults, indexes and primary keys
  under their own names, no rows), so the run's DDL meets existing tables, not
  fresh ones. Each pick runs through `wsg_run_one.R` as the dispatcher leg would
  (`LNK_LOAD=loadall`, `LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0`). The
  gate refuses a dirty checkout, refuses while any session is active on the
  persist schema or a `working_` schema (a live run shares `working_<wsg>`),
  and, since the bound is a time, refuses to start beside any other active
  client session unless `--allow-busy` (written to the record's notes). While a
  group runs the watchdog samples the other sessions every 30 s, and the
  verdict prints the most it saw beside the group's minutes: the first real
  gate (2026-10-28) had TAKL and SAJR killed at their bounds while another
  session ran six modelling workers on the same database, and SAJR had
  modelled in 0.8 min alone an hour before.
- **The verdict and the record.** Each group is `pass`, `failed` (non-zero
  exit), `bound` (past its bound, or killed) or `no_row`. The gate passes only
  when every group passes, on one clean link SHA equal to HEAD and one fresh
  SHA, both read from the scratch log rows the picks wrote. One row goes to
  `<schema>.log_pretest`; the report is `<out>/pretest.md` (default
  `data-raw/logs/pretest/<UTC>_<config>/`). Exit 0 pass, 1 fail, 2 refused.
  `--pick-only` stops after the pick and writes nothing to the database;
  `--only=<WSG>,...` models a subset of the picks and its record is never a pass.

**How the driver reads it.** `preflight_local()` runs `data-raw/pretest_check.R`
(`pretest_record_check()`), which first refuses a checkout with uncommitted
changes outside `data-raw/logs` (a record speaks for commits, and the
dispatcher leg models the working tree). The newest `pass` or `fail` row for the config
decides, so a later fail voids an earlier pass. It clears the run when it
passed on a clean tree, its fresh SHA is the installed one (a gate that modelled
nothing records the installed fresh too), its range starts at or before every
link SHA the history was built at, DESCRIPTION pins the same fresh at its SHA
and at HEAD, the gate's own scripts and map (`PRETEST_RULES`) have not changed
since, and every file changed between the SHA it modelled and HEAD maps to
`none`. A version bump or a
CITATION commit therefore keeps the record; an edit to `R/` voids it.
`--pretest-note="<why>"` runs without a record, prints an `OVERRIDE:` line,
and writes an `override` row with the note and the run_uid
(`data-raw/pretest_override.sql`; not on `--preflight-only`, which writes
nothing). The check applies to every launch, dispatcher-only included;
`--recompute-only` runs no pre-flight.

**What it does not cover.**
- Correctness and parity: the variants harness and `habitat_validate.R`.
- The recompute and the consolidate, whose changed files it names as
  unexercised. The recompute's cost was its downstream walks (#261). Since
  fresh v0.45.0 they read only the features on the group's lines or downstream
  codes, and under v0.46.0 they are 41 to 83 % of five groups' fastest runs
  (#409); the gate's scratch `barriers` hold only its picks, so it cannot
  exercise them.
- Access cost across groups: the scratch `barriers` hold only the picks, where a
  run's hold every group's.
- An input nobody mapped. The map is a judgement per file, and inputs ignore the
  config (under `bcfishpass` no rule asks for the near-river walk, so its picks
  are spent). On 2026-10-23's groups: QUES is first on `near_river_conn` and
  OKAN first on `dams` and third on `observations`, but KTSU ranks 119th or
  lower on every input, so no input would have picked it.
- A 2x slowdown: k = 3 is for stalls (KTSU ran 50x). QUES went 4.9 to 9.3 min
  between 0.66 and 0.68 with the walk, inside its bound.
- Primitives refreshed after the gate (`--refresh-primitives` runs before
  `preflight_local()`, after the gate was taken).
- Dependencies other than fresh: crate, DBI, RPostgres and yaml are on the
  path, and their installed versions are not recorded.
- A constant (not a function) defined in a `none` file and used on the path:
  the call graph walks functions only (none today).
- The driver's own environment for a group: `study_area_run.sh` is mapped
  `unexercised`, so a change to it is named and voids a record, but the gate
  models under its own copy of that environment. The remote legs' environment
  (`study_area_remote.sh`) is outside the gate's paths.

Evidence: `data-raw/logs/pretest_372/` (its README indexes it).

### The vintage gate reads load stamps (link#265, absorbing #247)

`lnk_preflight_vintage()` (via `data-raw/host_vintage.R`) judges each snapshot
primitive on its **load stamp**: the newest `loader` row's `loaded_at` in
`provenance.source_artifact` for this host (`.lnk_host()`, so
`LNK_HOST_ALIAS` if set). A table with no stamp **fails** as `unstamped`, even
when its statistics say it is fresh. Statistics are an inference that can read
too-new, and a host that never recorded a load should say so on its first run.
The statistics age is printed beside an unstamped table as context. The
message says which source judged each table.

**Rollout.** Every host is unstamped until it snapshots with this code. The
cyphers snapshot during prep. The dispatcher only does under
`--refresh-primitives`, so the first dispatcher preflight after this lands
fails until
`bash data-raw/snapshot_bcfp.sh --with-bcfp-views --force` has run. `--force`
matters: the ledger skip guard (link#276) exits before anything is loaded or
recorded.

### Three things that look like checks and are not

| looks like | actually |
|---|---|
| a provisioning tool's `plan` proves its credential | against a zero-resource workspace it plans without contacting the provider at all. The orchestrator and the provisioner also use *separate* credentials, which expire independently. Probe each against the provider's account endpoint. Details are infrastructure — see rtj |
| comparing `link_sha` across hosts | it is a real SHA on the `load_all` dispatcher and `NA` on every pak-installed cypher, so it can only ever fail. Key on **`repo_sha`**, read on each host from the checkout it installed from. `fresh_sha` was excluded alongside it on the grounds that it was `NA` everywhere and could only ever pass — that half was measured false on 2026-09-01 and the field is a real key since link#264 |
| `max(last_analyze)` for vintage | NULL on all ten primitives, measured. Empty in bash reads as "nothing to see". Use `GREATEST(last_analyze, last_autoanalyze)`, and since link#265 only as context beside the load stamp |

### The prep sentinel

`cypher_prep.sh` ends with a bare `=== READY`, and the umbrella greps it
**anchored** (`grep -qx`). Do not revert this to `snapshot_bcfp.sh: complete`,
which was wrong in both directions: the snapshot emits it *before*
`lnk_persist_init` runs, so a persist_init FATAL passed the gate and WSGs ran
against a half-prepped cypher; and the snapshot's legitimate skip-if-current
path never emits it at all, so a skipped load read as FATAL. The `-x` anchor is
what stops `=== READY (install stage only; ...)` satisfying a full-prep check.

### Two post-conditions, and why they are not optional

`schema_consolidate` DELETEs the destination bucket from every persist table
(its step 3.5) and *then* COPYs (step 4). A host that produced nothing
therefore does not merely fail to add rows — it **removes** the rows already
there for those WSGs and returns `ok = TRUE`. (The log tables are left out of
that DELETE, so a group's log history survives it; link#354.) So:

- before consolidate, every host must account for its whole bucket, read from
  its **database**: `<schema>.log` rows for the run_uid with `date_end` set,
  plus `SKIP` markers from the log, which write no row (link#347);
- after consolidate, every run WSG must have rows in `<persist>.streams` from a
  build **this run finished**.

The second is detection rather than prevention, and it is the one that would
have caught link#246 on day one regardless of cause.

### A missing group costs only itself (link#348)

The coverage check used to `exit 1` on the first run group with no rows,
before the recompute. One failed group then left every other group's access
computed against an incomplete barrier set, with no recompute rows at all.
It also asked only whether rows existed, so a failed group holding an earlier
run's rows passed and was recomputed as this run's.

Now `run_coverage` (`data-raw/study_area_finish.sh`) splits the run's groups
(every bucket, less SKIPs) into five classes, read on the dispatcher after
consolidate:

| class | rows in `streams` | finished this run | what happens |
|---|---|---|---|
| recompute | yes | yes | recomputed and compared |
| no rows | no | no | named at the end |
| earlier or partial | yes | no | named; its rows are left as they are |
| lost at consolidate | no | yes | named |
| not consolidated | any | any | named; its host's consolidate failed (below) |

"Finished this run" means the group's **newest** `<schema>.log` row (max
`date_start`, the rule `schema_consolidate.R` uses for which build a group's
persist rows hold) is the run_uid's and has `date_end` set. Consolidate
copies a group's log rows home (link#354), and the driver adds the
dispatcher's `done` markers and each cypher's consolidated bucket. A failed
build leaves its row open (`.lnk_log_run_fail` sets only `notes`), and its
pre-persist can leave `streams` rows, so rows alone do not make a group
"this run's". "Newest" matters for a `--recompute-only` days later: a group a
later run rebuilt, or a hand re-run under the same uid that failed after its
pre-persist, has a closed row for the uid that no longer names its rows. The
classes are written to `<TS>_coverage.tsv`, beside the compare CSV, which
covers the first class only. The compare runs over the first class only, and the recompute
over it and the groups outside the run that read it and may be recomputed now ("Groups outside
a partial run", below). If that class is empty, neither runs and the report says why. Any other class
makes the run exit non-zero, and the report names the groups and the recovery:

```bash
PGOPTIONS='-c statement_timeout=<the run bound, e.g. 30min>' \
LNK_RUN_UID=<uid> [LNK_RUN_LABEL=<label>] LNK_SCHEMA=<schema> \
  LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0 LNK_LOAD=loadall \
  Rscript data-raw/wsg_run_one.R <WSG> <config>          # each missing group
bash data-raw/study_area_run.sh --recompute-only --run-uid=<uid> \
  --config=<config> --schema=<schema> [--run-label=<label>] [--wsgs=<the run's groups>]
```

`--recompute-only` runs the driver's tail and nothing else: no droplet, no
pre-flight, no consolidate. It recomputes every group of the run, not just
the re-modelled ones, because a re-modelled group's barriers change access
upstream of it, and, as a run does, the groups outside the run that read it
(link#274). Without `--wsgs=`, the expected set is the groups the run
recorded in `<TS>_run_wsgs.tsv` (`wsg`, `host`, `skip`, `run_uid`; a run_uid's
prefix is its `TS`), together with any group holding a log row for the run_uid
on the dispatcher (link#358). The driver writes that file as soon as the buckets
resolve, before any spend, and rewrites it after the per-host accounting with
each host's SKIPs, so a group that failed on a cloud host, or before its first
log row, is still named. A run from before #358 has no file and falls back to
the log alone, where such a group has no row and only `--wsgs=` gets it named.
A file that names another run_uid stops a bare `--recompute-only`. A
`--wsgs=` that leaves out the run's groups warns. It refuses a `--config` other
than the one the run's log rows name, since a forgotten `--config` would
recompute every group under `bcfishpass` and stamp the rows with the run's
uid. It skips the discharge resolution as well as the pre-flight, but still
checks for `fresh.streams_vw_bcfp`, which the compare reads.

It also cannot rescue a group whose build finished but whose `date_end`
UPDATE failed (`.lnk_log_run_finish` is soft). A full run counts that group
through its `done` marker, but `--recompute-only` has only the log, so it
reports the group as "earlier or partial" every time. Re-model it.
A missing group in a kept host's bucket is listed apart in the report, which
defers to `kept_hosts.tsv`: settle it there first (consolidate only `groups`
where `groups_measured` is `yes`, never `groups_partial`), and re-model only
what is still missing. `--recompute-only` warns when a `kept_hosts.tsv` names
the run_uid.

**A consolidate that refuses one source does not stop the run** (link#358).
`schema_consolidate` loops past a source it refuses (`dest_log_newer`, which one
group can trigger, and the other checks made before anything is deleted) or
fails on mid-copy, so the other sources' groups are on the dispatcher. The
driver writes one outcome per source to `<TS>_consolidate.tsv`, and when every
source has one, carries on: the failed host keeps its finished groups (a source
is deleted from only after all of it copied), so `host_release` keeps it, with
`consolidate failed at stage <stage>` as the reason in `kept_hosts.tsv`. Its
bucket adds no finish signal and is classed **not consolidated**, out of the
recompute whatever the dispatcher's log says, because a failure after the
DELETE can leave log rows copied and `streams` not. The other hosts' groups are
recomputed and compared, and the run exits non-zero. Only when the outcomes are
missing for some source (R died) does the driver exit right after consolidate,
as before, with the `--recompute-only` recovery printed.

Before the copy the driver writes `<TS>_consolidate_state.tsv` (`wsg`,
`workspace`, `state`, `run_uid`) with every source's bucket `in_flight`, and
rewrites it once each source has an outcome (`ok`, or `failed:<stage>`). A
consolidate that dies mid-copy leaves the `in_flight` rows, so the record never
reads as "nothing failed". A bare `--recompute-only` names every group in a
state other than `ok` and keeps it out of the recompute, because nothing on the
dispatcher says whether its kept host was settled since; `--wsgs=` naming them
is the operator's word that it was. No record means the run never reached
consolidate, so consolidate wrote nothing to the dispatcher.

Two things it does not do. It takes no lock, so do not run it while another
driver on the same schema can resume: a driver paused with `kill -STOP`, as in
#347's recovery, would run a second barrier-view build and pool on the schema.
And `study_area_verify.sql` stays red for a group whose failed attempt left an
open log row **on the dispatcher**. That row is never closed, so verify reports
the group as started and never finished, even after the re-run succeeds. In
#246 the open rows were on the cloud hosts, so it did not show.
Tests: `tests/testthat/test-study_area_finish.R`, on a scratch schema.

### A runaway statement fails its group (link#371)

On 2026-10-23 OKAN sat 4 h in one statement (fresh's near-river walk,
`CREATE TEMP TABLE pg_temp.frs_near_river_walk AS …`), and the cloud hosts
idled on it. The same statement on the same tables took 59 s afterwards, so
the stall was neither the SQL nor the data. Nothing bounded a statement, and
the operator found it in `pg_stat_activity`. Now each modelling statement is
bounded, and one that runs past the bound fails its group like any other
error, which the path above already handles.

- **The bound:** `--statement-timeout=<minutes>`, default 30, 1 to 1440, with
  no unbounded mode. The driver sets it as
  `PGOPTIONS='-c statement_timeout=<N>min'` on **both** modelling legs: the
  local leg (after any `PGOPTIONS` the operator set) and the ssh command string
  (replacing the dispatcher's, whose tuning is not the cyphers').
  `LNK_STATEMENT_TIMEOUT_MIN=<N>` goes with it, and `wsg_run_one.R` refuses to
  model on a connection whose bound (from `pg_settings`, in ms; `SHOW` reads
  60min as `1h`) is any other, so a leg that lost `PGOPTIONS` fails its first
  group rather than running unbound.
  This is the both-legs rule `LNK_GUARD_DOWNSTREAM` and `LNK_RUN_UID` follow.
  libpq reads `PGOPTIONS` at connect, so the bound reaches every connection of
  the run and nothing else. The 2026-10-23 fix, `ALTER ROLE postgres SET
  statement_timeout`, reached every session on the host and had to be reset.
- **Why 30:** the longest group that finished on 2026-10-23 took 16.3 min in
  total (SETN, then LNAR 13.8 and BULK 13.7; `fresh_default.log`), and no
  statement outlasts its group. Those are whole-group minutes from one run, and
  cyphers ran up to 2.9x the dispatcher's time, so raise the bound when a top
  group is placed on a cypher by hand. A bound too tight costs one re-model and a
  `--recompute-only`; no bound cost four hours on 2026-10-23.
- **The recompute is not given it.** `wsg_recompute_one.R` keeps its own
  `SET statement_timeout = 10 min` and `lock_timeout = 1 min` (§6). A session
  `SET` overrides `PGOPTIONS` either way, and the driver does not export it
  there.
- **What a host log shows:** each group prints
  `[wsg_run_one] <WSG> statement_timeout=30min`. A cancelled statement prints
  `[wsg_run_one] <WSG> TIMEOUT after 30min: <statement>`, the SQL taken from
  the stack in a calling handler (`.lnk_timeout_statement()`; fresh's bare
  `dbExecute` leaves it out of the error), or from `.lnk_db_execute()`'s
  `Statement:` when a transaction re-threw it. The downstream guard's queries
  run under the same handler. Then the usual
  `[WARN] … failed (continuing)`. The log row stays open with notes, as for
  any failed build.
- **What the summary shows:** the group is in the "no rows" (or "earlier or
  partial") class, and under it `statement bound hit:` lists each such group
  with its statement (`run_timeouts`, read from the run_uid's
  `<ts>_run_*.log`, matched mid-line and byte-wise). Recover as above: the
  printed re-model carries the bound the run's groups reported (read from those
  logs, so a `--recompute-only` session prints it too), then `--recompute-only`. A group still timing out on a re-model is a real
  slow statement: re-model it with a larger `PGOPTIONS` bound by hand, and look
  at `pg_stat_activity` while it runs.
- **Exercising it:** `LNK_TEST_STALL_WSG=<WSG>` makes that group's
  `wsg_run_one.R` run `SELECT pg_sleep(3600)` first. It works on the local leg
  only (it is not passed over ssh), and `wsg_run_one.R` refuses it when no
  bound is in effect. With `--statement-timeout=1` the group fails after a
  minute, and the run carries on. The banner prints a `TEST HOOK:` line
  whenever the variable is set. Evidence: `data-raw/logs/statement_timeout_371/`.

### Where a run's time went: `<TS>_phases.tsv` (link#375)

Every speed number before this was rebuilt by hand from log tables, console
logs and `date_end` columns. Now the driver writes one row per phase per host
as the phase ends (`data-raw/study_area_phases.sh`), so a speed change is
measured off a file, run after run (#377).

| column | holds |
|---|---|
| `run_uid` | the run's uid; under `--recompute-only`, the uid of the run it finishes |
| `phase` | below |
| `host` | `dispatcher`, a cypher workspace or a worker's key (`worker1`, …); blank for a run-wide phase |
| `start_utc`, `end_utc` | ISO 8601, UTC |
| `minutes` | end − start, one decimal |
| `groups` | groups the phase covered; blank where it covers none |
| `status` | `ok`, `failed` (errored, or left groups out), `skipped` (blank times) |

- **The phases, in run order:**
  - `prep`, run-wide: driver start to dispatch. It holds `refresh`, every
    cypher's prep, both pre-flights and the bucket resolve.
  - `prep`, per cypher: from the spin to the end of its own prep. `ok` needs
    exit 0 and the `=== READY` line the gate reads.
  - `refresh`: `snapshot_bcfp.sh` under `--refresh-primitives`; otherwise skipped.
  - `backup`, run-wide: the run's one `pg_dump` of the persist schema, in the
    background through spin and prep (link#369). No row on a dispatcher-only run.
  - `model`, per host: the leg, written by the leg's own subshell when its loop
    ends. The status is the session's exit, which is 0 even when every group
    failed (each group soft-fails); `account` says whether the hosts finished.
  - `account`, per host: completeness from each database, a cypher's as soon as
    its leg ends, the dispatcher's after every leg. `failed` when the host did
    not account for its bucket.
  - `consolidate`, per remote host: its copy and the release that reads it
    again, as soon as its leg ends (link#369); for a worker, also the drop of
    its partial groups (link#376). `failed` when it copied nothing or its
    consolidate failed; skipped with no remote hosts.
  - `burn`, per cypher: the burn right after its release, not the EXIT trap's.
    `failed` when the host was free to burn and is still up. A held host is the
    kept-hosts report's to name. A worker's row is always `skipped`.
  - `coverage`: `failed` when a run group has no rows from this run.
  - `views`: the log-table step and `barriers_views_build.R`.
  - `recompute`: the pool, ordering and judge included; skipped when `views` failed. Its
    group count includes the outside readers it recomputed (link#274).
  - `compare`.
  - The tail is skipped when no group has rows.
- **Rows overlap, so never sum them.** The run-wide `prep` holds `refresh`,
  `backup` and every cypher's prep, the model legs run side by side, and a
  cypher's consolidate overlaps the legs still modelling. The summary prints
  the **critical path**, which is the first start to the last end, the longest
  model leg, and the **consolidate tail**: how far the last consolidate ran past
  the last model leg's end, 0 when every copy overlapped a leg still modelling.
- **A row per tracker cell.** "Longest leg" is the longest `model` row.
  "Consolidate on the critical path" is the summary's consolidate tail (before
  link#369 it was the one `consolidate` row, which waited on every leg).
  "Recompute" is the `recompute` row. "Critical path" is the summary's line.
  The phases.tsv sits beside the run's other `<TS>_*` logs.
- **A run that dies** keeps the rows it finished. The EXIT trap closes the phase
  it died in as `failed` and prints the table once. A kill does not stop a
  running leg, so that leg later writes its own row too. For one phase, host and
  start, the later row is the leg's real end. Each leg's wrapper is a subshell of
  the driver and carries its command line, so `pkill -f study_area_run` kills the
  wrappers as well. Their legs (`wsg_run_one.R`, the ssh session) run on, but
  write no later row. A phase a leg had already closed
  is not closed again. The file has every phase only on a run that reached its
  summary: a coverage FATAL, for one, leaves no tail rows.
- **`--recompute-only` writes its own `<its TS>_phases.tsv`**, with a `prep` row
  for its preamble and then the tail. Its critical path covers that pass only.
  A path running from the original run through a hand re-model hours later
  would mean nothing.
- **`--preflight-only` writes no file.**
- **Times come from one `date -u` call each, which prints both ISO and epoch.**
  `date` is GNU on some hosts and BSD on others, so nothing parses a date with
  it, and the report parses ISO in perl. A `date` that fails costs only that
  row's times.

### Each cloud host is consolidated when its own leg ends (link#369)

Until #369 the driver waited for every leg, consolidated every cypher in one
`schema_consolidate()` call and then burned them, so a cypher that finished
early sat idle and billed, holding the only copy of its groups: about 3
host-hours on 2026-10-17 and about 20 on 2026-10-23. Now `legs_wait`
(`data-raw/study_area_legs.sh`) takes the legs in the order they end, and for
each cypher accounts it, consolidates that one source, releases it and burns
it while the other legs keep modelling. `--keep-cyphers` consolidates each host
the same way and burns none.

- **One consolidate at a time, in the main shell**, in the order the legs end:
  the hold, burn and outcome maps live there. `CONSOLIDATING` names the host
  being copied, so a driver killed mid-copy reads that host as unsettled and
  the others as their own state says. `wait -n -p` (bash ≥ 5.1, the driver's
  floor since #369) returns an already-returned job again, so each pid leaves
  the pending list once returned.
- **A bucket that overlaps the dispatcher's waits for the dispatcher leg.**
  Closure mode only warns on an overlap, and copying a group the dispatcher is
  still writing would race its delete and insert. Exact mode refuses overlaps.
- **A burn mid-run considers only hosts whose leg has ended** (`burn_cyphers
  ended`), so `<TS>_kept_hosts.tsv` and its banner never list a host still
  modelling. The EXIT trap considers every host.
- **A consolidate that ends with no outcome for its host** (R died, or failed
  after recording `ok`) keeps the host held, leaves its groups `in_flight` in
  `<TS>_consolidate_state.tsv` and out of the recompute, and the run carries on
  and exits non-zero. Before #369 that exited the run, which would now leave
  the other legs running unwatched. The host is not passed to `host_release`:
  a consolidate that died after its source cleanup leaves nothing there, and
  release would then burn it.
- **Per-host records:** `<TS>_consolidate_<ws>.log` and `.tsv` (one outcome
  row); `<TS>_consolidate_state.tsv` gains `state_utc`, the time each host's
  state was written, and a host not yet consolidated has no rows. A
  `--recompute-only` reads either header.
- **Beside a dispatcher that is writing.** Three things changed so a copy and
  the dispatcher's modelling can share the persist tables:
  - `CREATE INDEX IF NOT EXISTS` and `ALTER TABLE … ADD COLUMN IF NOT EXISTS`
    lock their table before finding the work done (both block behind a
    `COPY`'s ROW EXCLUSIVE; the `ALTER` also behind `pg_dump`'s ACCESS SHARE),
    and `lnk_persist_init()` issued them for every group. Existing indexes and
    columns are now read from the catalog first and not re-issued.
  - `schema_consolidate()` judges a copy on the bucket's rows, not whole
    tables, which move with the dispatcher's own per-group replace.
  - It refuses a source before anything is deleted when the destination lacks
    one of link's core persist tables (`streams`, `barriers`, …; a missing
    habitat table is still only a note: `dest_missing_tables`): into an uninitialised
    schema it would copy only the log tables, report success and delete the
    host's log rows. The driver initialises the dispatcher's persist before
    dispatch so this does not arise.
  - A dispatcher group can still read a cypher group mid-copy, some tables
    copied and some not. The recompute settles access, mapping code and the
    gated flags whatever it read; the downstream guard's warnings and
    `log.wsg_upstream` now depend on timing.
- **The backup is taken once, before any leg writes.** It used to be taken
  inside the one consolidate, after the dispatcher had rebuilt its groups, so
  #354 could restore only log rows from it. Now the driver initialises the
  dispatcher's persist, then dumps it (`schema_consolidate_backup()`, which
  stops when `pg_dump` fails) in the background through spin and prep, and
  dispatches no leg until it has succeeded; a failure exits before any host is
  held, so the trap burns them. A running `pg_dump` beside the dispatcher
  would stall each group's log-table `ALTER` for the whole dump (7.6 min for
  `fresh_default`'s 241 groups, 2026-10-24). Its use is the earlier builds' log
  history (#354) and a rollback of the whole schema to before the run: the
  recompute rebuilds access and mapping code, not the persisted groups.
  Dispatcher-only runs take none, as before.

### A group is recomputed once what it reads has landed (link#374)

Until #374 the recompute ran after the last leg and the last consolidate: 110
min of `-j8` on the critical path on 2026-10-23. Now `recompute_scheduler`
(`data-raw/study_area_recompute.sh`) runs in the background beside the legs and
starts each group's `wsg_recompute_one.R` as soon as the group, and every group
it reads, has **landed** on the dispatcher. `--recompute-at-end` keeps the old
behaviour; `--recompute-only` is unchanged. Both of those compute the same
dependency map too, for the groups outside the run (link#274), but wait on it
only at the end.

- **What a group reads.** Its own rows, and the `barriers` and
  `barrier_overrides` rows of every group holding one on its downstream path:
  the persist schema's views read every group's rows, by position, not by
  group. A watershed group is not one drainage, so the outlet closure
  (`frs_wsg_drainage()`) misses readers in 150 of 241 groups; and gradient
  barriers are found along the whole of every line a group touches and
  persisted under its code, so a group that owns no segment of the path can
  still hold a row on it. `data-raw/recompute_deps.R` writes the **line**
  rule, complete by construction: every group touching any line whose code
  is an ancestor of, or equal to, one of the group's codes (FWA only, about 80
  s, in the background through spin and prep; no leg is dispatched without it).
  FWA's unassigned `999…` codes are left out on both sides.
- **Landed.** A dispatcher group: its newest `log` row is the run's and closed
  (`date_end` is written last). A remote group: its host's row in
  `<TS>_consolidate_state.tsv` is `ok` (written after the copy; `in_flight`
  before, because a consolidate deletes and copies table by table, not in one
  transaction). A SKIP, or a group outside the run, has landed. A group on two
  hosts lands when both have landed it. **Readiness fails closed:** an early
  recompute that reads too little cannot be undone (the habitat gate only
  clears flags), so a failed poll, an unreadable file or a row of another run
  starts nothing.
- **Before the legs:** the persist init (every run now, not only with remote
  hosts), the log tables and the barrier views, before the backup (its
  `pg_dump` would make the view build wait). A view rebuild later would take
  an exclusive lock under running jobs, so the end of the run does not rebuild
  them. Each dispatcher group's `lnk_persist_init()` replaces
  `streams_habitat_long_vw` only when its definition changed, for the same
  reason.
- **The end.** After coverage, `run_finish` writes the final set
  (`<TS>_recompute_final`): the groups found finished. The scheduler starts
  every one not yet started, ready or not (every leg and consolidate is over,
  and a group reading a failed group is recomputed as the pool always did),
  drains, and returns; it looks for the final set every second, not every
  poll. A scheduler that died leaves the groups it did not start to the old
  pool, after waiting for any job it left running (each launch records its
  pid). `<TS>_recompute_launched.tsv` records each start, `early` or `final`.
- **The audit** (`data-raw/recompute_audit.R`): no group started before a
  group it reads had landed, each comparison on one clock. A dispatcher
  dependency's `log.date_end` is compared with the group's earliest
  `log_recompute.date_start` (both the database's). A remote dependency's
  consolidate `state_utc` is compared with the group's launch in
  `RC_DIR/launched.tsv` (both the driver's; the database runs in a VM whose
  clock can drift). `EARLY` (exit 1) fails the run with its own remedy:
  re-model those groups, then recompute them, because the gate may have
  cleared habitat for good. A start or landing it cannot prove (exit 2) fails
  the run too, never passes: a missing value is safe only where nothing ran,
  or the fallback pool ran it after every landing. So `LNK_LOG=0` (which skips
  `log_recompute`) is refused in early mode.
- **Stopping.** The EXIT trap touches `<TS>_recompute_stop`: nothing new
  starts, running jobs finish, as a killed pool's always did. A scheduler whose
  driver is gone (SIGKILL) stops the same way.
- **Width.** One width, `--recompute-jobs`, while the legs run and after. A
  full-width recompute roughly doubles the dispatcher's modelling time, and full
  width is still best: replayed on 2026-10-23 without its stalls, it ends the
  recompute 36.7 min sooner, against 22.2 at width 4 and 11.1 at none.
  Evidence: `data-raw/logs/recompute_early_374/`.

### Groups outside a partial run (link#274)

A run rebuilds its groups' barrier rows. A group the schema holds **outside** the run whose
walk reads one of them (line rule, above) keeps `streams_access`, `streams_mapping_code` and
settled habitat computed against the old rows. A full run has none: every group is in it.
After coverage, `run_finish` calls `recompute_readers` (`data-raw/study_area_recompute.sh`),
which runs `data-raw/recompute_readers_check.R` (functions in `data-raw/recompute_readers.R`)
and writes `<TS>_outside_readers.tsv` (`wsg class reason reads`):

| class | when | what happens |
|---|---|---|
| `recompute` | every test below passes | joins the recompute: the pool, the early scheduler's final set and the judge all read the union; the compare does not (`CMP_WSGS`) |
| `waiting` | it reads a run group coverage did not find finished | named; the `--recompute-only` after that group's re-model takes it up |
| `refused` | any test fails, each one named | named, with the re-model |
| `unchecked` | the check could not run, or its table is missing or malformed | the map's candidates, named; never read as "no readers" |

- **The run** for "outside": its rebuilt groups, every row of `run_wsgs.tsv` (SKIPs too) and
  every group with a `log` row of the run_uid, so a `--wsgs=` leftover is never a reader.
- **The tests**, on the reader's newest `log` row: closed; the `config_hash`, `fresh_sha`,
  `fresh_version`, `crate_version` (crate shapes the overlay the gate keeps) and `fwapg_sha`
  that `lnk_stamp()` gives now under the recompute's own environment;
  `link_dirty` and `fresh_dirty` FALSE; a `link_sha` git resolves, with no difference to the
  working tree in `R/`, `inst/extdata/`, `DESCRIPTION`, `NAMESPACE`, `wsg_recompute_one.R`,
  `barriers_views_build.R`, `study_area_run.sh` or `study_area_finish.sh` (`READERS_PATHS`);
  and the error-mode downstream check the recompute ends with would pass (asked first with
  `on_fail = "warn"`, because it fails after the group is rewritten). Every reader is refused
  when the run's own rows carry another config hash, the dispatcher tree has uncommitted
  files on that path, the fresh it would run is dirty or unknown, or its sha is a
  `FRESH_GIT_SHA` pin the installed fresh's `RemoteSha` does not confirm (`--recompute-only`
  runs no pre-flight, which tests the pin otherwise). Anything unknown refuses: a recompute that reads wrongly cannot be undone.
- **One hop.** A recompute writes its own group's access, habitat and mapping codes, never
  barrier rows, so a reader's readers read nothing that moved.
- **Not the exit status.** Named readers are a WARN in the summary; the run did what it was
  asked for its own groups. A reader whose recompute fails does fail the run, as any recompute
  failure does. A recomputed reader that lifted segments the gate had cleared is named
  (`log_recompute.habitat_gate_lifted`); `study_area_verify.sql` reports it as a WARNING where
  it raises for the run's own groups.
- **The remedy** printed for refused, unchecked and lifted readers: leave them to the next full
  run, or re-model each under the run_uid (`LNK_HABITAT_GATE=0 LNK_GUARD_DOWNSTREAM=warn`),
  which makes it a run group, then `--recompute-only`; its own readers are named on that pass.
- **What it means today.** Every local schema was built before `R/` last changed
  (`fresh_default` at 0.68.0), so every reader there is refused. After the next provincial
  run, a partial run at that run's commit recomputes its readers. Measured: a six-group North
  Thompson run has 65 readers by the line rule (every Fraser group reads LFRA), the 34-group
  field scope 78. Evidence: `data-raw/logs/partial_readers_274/`.

### Which host may be burned (link#347)

The count used to be `[wsg_run_one] … done` lines, anchored at line start. R
writes warnings into the same stream, and one flushed without a newline put the
marker mid-line (`… :[wsg_run_one] FIRE done in 4.6 min`), so run
`20261017_004619-3f4c713b` hid 18 finished groups, consolidated only what it
counted, and would have burned the hosts holding the rest. The rules now, all
in `data-raw/study_area_hosts.sh`:

- **The database counts, the log only adds.** consolidate takes database ∪ log
  `done`. The log cannot be the count (mid-line markers), and the database
  alone can undercount: `.lnk_log_run_finish()` is a soft UPDATE after persist,
  and a lost `LNK_RUN_UID` leaves every row's `run_uid` NULL. Both probes are
  framed by sentinels, because ssh can exit 0 whatever the remote command did;
  no sentinels means **unknown**, never "nothing".
- **A cypher is held from dispatch.** It is released only when its dispatch
  session exited 0 and, **after** consolidate, its database holds no
  **finished** group: one with `<persist>.streams` rows left that this run
  finished there by any signal (database, log `done`, or
  `streams_mapping_code` rows, which within a run only the final persist
  writes). `schema_consolidate` deletes what it copied from the source, so
  what is left was not consolidated: measured, not assumed. A group with
  `streams` rows and no other signal is **partial** (it failed after the
  pre-persist, `R/lnk_pipeline_run.R:240`); it does not hold the host and is
  never consolidated.
- **Provenance and settledness are checked, not assumed.** A cypher spins from
  a warm image and `lnk_persist_init` keeps rows, so before dispatch the
  driver records which of each bucket already have `streams` or
  `streams_mapping_code` rows (`host_baseline`); their mapping-code rows are
  not this run's, and such a group with no finish signal of this run is
  `groups_unknown`, never partial. With no baseline, mapping-code rows count
  as `groups_unknown` too. Unknown groups hold the host and are never
  recovered. After dispatch the driver writes to a cypher in exactly two
  ways, the dispatch ssh session and `schema_consolidate` (which copies, then
  deletes from the source). A killed driver runs its EXIT trap while either
  keeps going, so a host is **unsettled** unless its session ended 0
  (`legs_wait` and `host_wait` record the status only once `wait` returns) and
  consolidate is not in flight against it (`CONSOLIDATING` names the host
  being copied, link#369). An unsettled host's groups are "not
  finished when probed", never "partial", and the record says to re-measure. A report from the trap reads the host's log row and run log
  itself when accounting never ran.
- **A held host is kept on every exit path**, abort included, and so is a host
  whose burn did not complete. Each is a row in `<TS>_kept_hosts.tsv`
  (reason, run_uid, schema, groups, whether those groups were measured, the
  command that prints its address, the command that burns it), the banner
  prints from the EXIT trap, and the run exits non-zero. `--keep-cyphers`
  alone is not a failure; a host it keeps that is also held for cause is.
- **A host whose database did not answer is left out of consolidate**: the
  same route would fail there and take the other hosts' consolidate with it.
- **Pre-flight fails on a cypher already up in this run's workspaces**: that is
  most likely a host an earlier run kept, and `cypher_up` would adopt it.
  Others warn, except the long-lived default `cypher`.

To recover a kept host: run its `ip_command` (a worker's is the `--workers=`
target the operator gave), consolidate its `groups` with
`schema_consolidate(schema = <schema>, sources = list(list(host =
"cypher@<ip>", via = "docker", bucket = c(...))))` (a worker: `host =
"<its target>"`), then run its `burn_command` (a worker has none). **Only `groups`, never `groups_partial` or
`groups_unknown`, and only where `groups_measured` is `yes`**: `groups` is
then the finished work still on the host. `unsettled` means wait until
nothing runs there and re-measure. `schema_consolidate` deletes its bucket on the dispatcher before it
copies, so consolidating a group the host holds only in part loses the
dispatcher's copy of its persist rows (its log rows survive, link#354).
Where both sides have a `log` table, consolidate refuses a source outright
(`stage = "dest_log_newer"`, nothing deleted) when a group has a log row on
the dispatcher and the source's newest is older or absent: the persist tables
carry no run id, so that newest row is what says which build they hold. So a
group the host no longer holds at all (already consolidated, then deleted from
the source, log rows included) is refused rather than lost, and a group re-run
on the dispatcher during recovery is never overwritten by the kept host's
older build. A group with persist rows but **no** log row on the dispatcher
(built before the log tables, link#127: 59 of `fresh`'s 98 groups, 0 in
`fresh_default`, 2026-10-17) is not protected: it is deleted and, if the host
no longer holds it, not replaced. Where it says `no`, find out what is left first. If the
run's recompute ran, it ran without the kept groups: recompute each one and
each run group that reads it (`wsg_recompute_one.R`): the `wsg` of each row of
`<TS>_recompute_deps.tsv` whose `dep` is a kept group, which is wider than
"upstream of it", because a group reads every line on its path whole
(link#374); without that file, every group of the run. If it did not run (no
run group had rows from this run), recompute every group of the run; the
banner says which. A host whose consolidate recorded no outcome keeps its
groups `in_flight` and out of the recompute (link#369): check what reached the
dispatcher before consolidating them again. A missing
`<schema>.streams` or `streams_mapping_code` on a host reads as unknown, not
empty: every dispatched cypher has both. Tests: `tests/testthat/test-study_area_hosts.R` runs the lib
in bash with stubbed ssh, psql, tofu and doctl, and
`tests/testthat/test-study_area_legs.R` runs `legs_wait` over real background
legs of different lengths with a stub consolidate.

### Persistent workers (link#376)

A third kind of host: a machine that already exists and stays up, reached over
ssh, which the driver neither spins nor burns. `--workers=<ssh target>,...`,
one `--focal=` list per worker after the dispatcher's and before the cyphers'
(`study_area_buckets.R --workers=N` prints them in that order). Each is keyed
`worker1..N` in the order given, and the key is all a log, `phases.tsv` or
`kept_hosts.tsv` records: the target is the operator's infrastructure, and
`remote_redact_targets` replaces it with `<workerN>` in the run's logs.

- **What it must be.** A target of `A-Z a-z 0-9 . _ @ -`, not starting with
  `-` (an ssh option), not `local` (the hosts lib's name for the dispatcher's
  database), given once. Before any spend it must answer over ssh and hold its
  own database: `pg_control_system().system_identifier` differs from the
  dispatcher's and every other worker's. A worker on the dispatcher's own
  database would model into the dispatcher's persist, and consolidate would
  delete a bucket there and copy it back from the same, now empty, table. Once
  the buckets resolve, its schema must hold no `streams` or
  `streams_mapping_code` rows for a group of its bucket. The driver only reads
  them: they may be that machine's own builds, so remove them deliberately or
  give the run another `--schema=`. `--preflight-only --workers=` runs the
  reach and identity checks.
- **Prep** is `data-raw/worker_prep.sh`, piped over ssh, so no older copy is
  left on a machine that stays up. It owns one clone,
  `~/Projects/repo/link_worker`, cloned on first use and reset to
  `origin/<run branch>` every prep, and never touches the worker's own
  checkout. link runs from it by load_all, so the link installed there for
  every other session is never replaced. It installs nothing, reloads no
  primitives or discharge and recreates no table: fresh is asserted, the
  config's discharge (and wet load, which must be the dispatcher's) is checked,
  and `lnk_persist_init()` runs without `force_recreate`. Vintage and parity
  are the host pre-flight's, as for a cypher.
- **What the worker sets for R is refused.** R reads `~/.Renviron` after the
  environment, so a line there beats anything the driver exports (measured
  2026-10-24), and an empty export does not clear it. Prep refuses every
  variable the leg exports (`REMOTE_LEG_VARS`, held to `remote_leg_cmd`'s
  exports by a test), every `LNK_*` (all link reads; `LNK_HOST_ALIAS`, which
  only names the host, excepted), and the pins `LINK_GIT_SHA`,
  `LINK_GIT_DIRTY`, `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA` and `PGOPTIONS`. A
  `FRESH_GIT_SHA` must be the installed fresh's `RemoteSha`, and
  `FRESH_GIT_DIRTY` may only be `false` beside it. Under load_all link's sha
  comes from the clone's git. `--auto-install` on a worker installs fresh at
  DESCRIPTION's `Remotes:` pin and re-checks once; it refuses while a
  `FRESH_GIT_SHA` pin is set, which would outlive the install.
- **Primitives and fresh are the operator's to bring current, once,** because
  both are shared with the machine's other sessions. Measured on the first
  worker (2026-10-25): fresh by `--auto-install` (or `worker_prep.sh`'s
  `install-fresh` stage), and the snapshot by `bash -lc 'cd
  ~/Projects/repo/link_worker/data-raw && export PGUSER=postgres
  PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg
  LNK_LOAD=loadall && bash snapshot_bcfp.sh --with-bcfp-views --force'` over
  ssh. A login shell, because a non-interactive ssh command on macOS gets PATH
  `/usr/local/bin:/usr/bin:/bin`, without `psql`, `ogr2ogr` or `bcdata`. The leg
  itself needs only `Rscript`, `git` and `docker`, which resolve there. Evidence:
  `data-raw/logs/worker_376/`.
- **The leg** is a cypher's (`remote_leg_cmd`, the same exports), run from the
  clone with `LNK_LOAD=loadall`. Before each group it checks the clone's HEAD
  against the run's commit, and runs no group once it has moved (a second
  run's prep, a hand `git checkout`): each group loads the code afresh.
- **After its leg:** account, consolidate and release, as for a cypher
  (`host_finish_leg`). Then no burn: consolidate already deleted what it
  copied, and a released worker's partial groups (failed builds whose
  pre-persist left rows, `HOST_PARTIAL`) are dropped from its persist tables
  (`host_drop_partials`), so the next run's prior-rows check finds it clean.
  Their log rows stay, because the open row is the only record of the failure.
  The drop runs only on a settled worker whose rows before dispatch were known
  and empty, never on unknown-provenance groups. A drop that does not finish
  leaves rows, and the next run refuses the worker: it fails closed.
- **Consolidate and the drop touch link's tables only** (`consolidate_link_tables()`:
  the persist tables and the log tables). A persist schema can hold others: in
  `fresh` the snapshot primitives (`modelled_stream_crossings`) and the bcfp
  reference (`streams_vw_bcfp`, `crossings_vw_bcfp`) carry `watershed_group_code`
  too. Before link#376 consolidate copied them as well, putting a source's
  primitive rows over the dispatcher's for its bucket, and step 5 deleted them
  from the source: harmless on a cypher about to be burned, not on a worker.
- **Redaction** covers the target, the host part of `user@host`, the HostName
  ssh resolves an alias to (`ssh -G`), and the name the worker gives itself
  (`=== host` from prep, which its stamp row carries), including right after
  `<user>@` (ssh's failure line). A held worker's leg can write ssh's closing
  lines after the trap redacted its log: redact it again before committing.
- **Held, it is kept and reported** like a cypher, with no droplet, address or
  burn command, also on a run with no cyphers (`WORKERS_UP`). `--keep-cyphers`
  keeps cloud hosts only.
- **Speed.** A worker's speed is learned like any host's once it has run under
  a name passed in `--host-names` ("Learned host speeds", below); until then
  it takes the median of the learned state. To set one by hand, measure its
  minutes per group against the dispatcher's on the same mid-size groups, by
  host (read `<schema>.log` by `host`; `--minutes-schema`'s newest row per
  group mixes hosts, and small groups are dominated by per-group overhead),
  and pass `--host-speeds`.

### A remote status is what the remote shell prints (link#376)

Some ssh servers exit 0 whatever the remote command returned; Tailscale SSH to
macOS does. So no exit status the driver acts on is read from `ssh`. ssh's own
non-zero status (it could not connect, or the link dropped) still wins, and
the rule holds for cyphers too, which loses nothing.

| call | verdict from |
|---|---|
| stamp, vintage, auto-install, reachability (`remote_run`, `data-raw/study_area_remote.sh`) | `__LNK_RC__=<n>` printed after the command, run in a subshell so an `exit` still reaches it; none printed is 255 |
| the modelling leg (`remote_leg_cmd`, `remote_leg_status`) | `__LNK_LEG_END__`, printed after the loop inside the braces its `cd` guards, matched anywhere on a line; absent, the leg failed and the host is not released |
| every consolidate call (`consolidate_remote()`, `schema_consolidate.R`) | the same trailer on stderr, captured per call, so it stays out of a COPY's data on stdout |
| a persist table's copy | psql's `COPY n` must equal the lines sent, or the table is not copied and its source rows stay |
| database probes, prior rows, identity, partial drop (`.hosts_psql`) | `__LNK_BEGIN__` / `__LNK_END__` framing, as since link#347 |

Before link#376 a COPY that died part-way on such a host loaded its partial
file, and with the bucket's rows still rising, consolidate deleted the source.
The bucket total cannot see one table landing short while the others land,
which is why the per-table count exists.

### Host buckets are derived, not chosen

`data-raw/study_area_buckets.R` partitions the focal set into
drainage-independent components by union-find over per-WSG
`frs_wsg_drainage()` closures, then LPT-packs the components onto hosts and
writes `research/study_areas.md`. Overlapping closures would make consolidate
last-writer-wins on the shared WSGs, so the script **asserts** disjointness.
Never partition by `wscode_ltree` root — see §8b.

**The atom can be a single group (link#361).** The component rule was
written for access at model time. Since link#175 the post-consolidate
recompute settles access, mapping code and (link#349) the gated habitat
flags from every group's persisted barriers, and the driver models both legs
with `LNK_GUARD_DOWNSTREAM=warn` and `LNK_HABITAT_GATE=0`. The split test of
2026-10-23 modelled the Peace's 26 groups on two hosts in the worst order
and found nothing the order can reach that differs from the one-host build
(`data-raw/logs/provincial_361/split_verdict.md`: the 55 of 442 differing
digests are cross-host arithmetic of at most 3.7e-9 m and the test's own 26-group scope). So
`study_area_buckets.R --atom=group` packs single modelable groups, which lets
modelling finish before the largest component would (the Fraser: 205 of 873
host-minutes on the 2026-10-17 minutes, 231 of 1,077 on 2026-10-23's), and prints the makespan under both atoms. Its `--focal=`
strings are each host's exact list in the global downstream-first order, and
the run takes them with `study_area_run.sh --buckets-exact`
(`study_area_wsgs.R --exact`: no closure expansion, the species filter only,
order kept). In exact mode an overlap between hosts' lists is fatal, the
banner says `buckets: exact`, and `<TS>_run_wsgs.tsv` carries
`bucket_mode`. Keep component atoms when fewer guard warnings at open matter
more than minutes; at four hosts the two atoms tie on this run's minutes, and
group atoms pay from five hosts on. Two cautions from the test: a build is
byte-identical on one host and differs by up to 3.7e-9 m across architectures, so
"identical across hosts" is a digest after rounding; and a recompute over a
subset of groups differs from the full one wherever a group holds lines
coded to another basin or with barriers below it in a group outside the subset (NATR's two Fraser-coded segments; TOOD's two with barriers below them in FROG, LKEC, UKEC and ULRD).

### Learned host speeds (link#259, folding in #163)

`study_area_buckets.R` predicts each host's model leg as the sum of its
groups' weights over its speed. Measured minutes (`--minutes-schema=`) are the
weight a provincial run packs on: scored out of sample on 2026-10-23, they
set each leg's share of the mean leg within 3.6 points, segments 28.9, with
KTSU's and OKAN's stalls left out (16.4 against 28.5 as logged)
(`research/study_area_run.md`, "How hosts are packed").

**Where a host's speed comes from, in order:**

1. `--host-speeds=` on the packer, typed for this run.
2. The learned state, `data-raw/logs/host_speeds.tsv` (`--speeds-state=`;
   empty for none). A host it does not hold takes the median of the hosts it
   does, and the report labels it `median (no learned speed)`.
3. Equal.

**Speeds are keyed by name, not by the driver's role key.** `--host-names=`
gives each host's alias in the driver's order (default: this machine's short
name, `worker1..N`, `cloud` for every cloud host). The dispatcher moved from m1
to m4, so a factor keyed `dispatcher` would carry m1's speed onto m4. Every
cloud host is one class, `cloud`: one droplet size, so three legs of evidence
a run. A worker gets a learned speed only under a name passed in
`--host-names`. The names reach a committed file, so the packer and the
calibrator refuse anything with `@`, `:`, `/`, a dot or an address shape. Give
an alias, never an ssh target.

**After a run.** The summary prints the command, and the operator runs it:

```
Rscript data-raw/host_speeds_calibrate.R --plan=<the packer's --plan-out> \
  --phases=<log dir>/<TS>_phases.tsv [--skip=<name>:<reason>] [--dry-run]
```

- **What it reads.** Each leg's actual time is its `model` row, the whole leg,
  never a mean over its groups (#163's feedback loop; a simulation in
  `test-study_area_packing.R` shows per-group means running away from the true
  ratio while whole legs converge). When a killed driver leaves two rows, the
  later end is the leg's.
- **What it projects.** Each leg's projection is the sum of its plan rows'
  weight over the speed the plan packed at, less groups the host SKIPped and
  groups with no rows from this run (`<TS>_coverage.tsv` class other than
  `recompute`). A host whose `account` row is not `ok` is left out. So is a
  leg named by `--skip`, for a stall or another job on the machine: by name
  (every leg of it) or by the run's host key (`job2`, one cloud host, as the
  legs table shows it). The legs and their reasons print before anything is
  learned, so a run in which every leg is left out still says why. The
  history records why.
- **The arithmetic.** Per name, `correction = (Σ actual / Σ projected) /
  run_ratio`, where `run_ratio` is the same ratio over every leg not left out.
  Each leg is first re-projected at the stored factor `old` (the state's, its
  median for a name it lacks, 1 with no state), so `projected` above is taken
  at `old`, not at the speed the plan packed it at, from weights re-normalized
  at the calibrating state (the plan carries each group's raw minutes and the
  class that measured them, so a plan packed on an older state or another
  `--speeds-state` is projected as if packed on this one). Then `observed = old /
  correction` and `new = 0.7 · old + 0.3 · observed`, clamped to `[0.5, 2] ×
  old`; at this damping only the upper bound can bind. So the speed a run was
  packed at (`--host-speeds`, an older state) decides only which groups a host
  got, never what is learned. Dividing by `run_ratio` takes out drift every
  leg shares: the same groups on the same class took 13 to 16 % longer,
  summed per class, on 2026-10-23 than on 2026-10-17, and without the
  division that drift would be booked as host slowness. The run-wide ratio
  goes in the history beside each row.
- **Role keys are never learned.** A leg whose name is `dispatcher`,
  `workerN` or `jobN` counts toward `run_ratio` and is recorded `not learned`
  in the history; `workerN` is the packer's default name for an unnamed worker.
- **A group measured by a host the state does not know** (a worker never
  learned under its alias, say) was weighted at the state's median, which says
  nothing of its work. So a leg holding one is left out, unless the leg is that
  host itself; otherwise its error would land in the hosts that are learned.
  Name each worker in `--host-names` by the alias its log rows carry
  (`LNK_HOST_ALIAS`), and the next calibration learns it.
- **A group whose newest minutes are a stall** would weigh the plan wrong and
  then teach the calibrator a leg as fast as the stall was long (KTSU: 65.4 min
  on 2026-10-23, 1.3 the week before). Pack with `--minutes-exclude=KTSU,OKAN`
  until a run re-measures them: an excluded group takes the median weight and
  carries no minutes into the plan.
- **Cloud hosts are matched to the run's by their groups,** not their keys: the
  packer keys them `job1..N` by position, and the driver by the
  `--cy-workspaces` names, which a kept host can leave out of order. The
  dispatcher and each worker keep their key, so a run that gave one role
  another role's list is refused rather than learned under the wrong name.
  `--plan-out` needs `--host-names`, since the packer need not run on the
  dispatcher.
- **What it refuses.** A plan weighted in segments: a run must pack on
  `--minutes-schema` to be calibrated. A plan whose groups for a host differ
  from `<TS>_run_wsgs.tsv`. A phases file with no model row, which is what a
  `--recompute-only` pass writes. A run the history already holds.
- **What it writes.** It rewrites `host_speeds.tsv` and appends to
  `host_speeds_history.tsv` (`run_uid, date_utc, name, packed, old, correction,
  observed, damped, clamped, new, run_ratio, action`). Commit both with the
  run's evidence.

**Why it learns slowly, and why that is right.** A host packed on minutes it
measured itself predicts its own leg whatever its speed. Only groups that
move host between runs carry evidence. Measured minutes are normalized by the
current learned speed of the host that measured them, so a group that moves
is predicted at the estimated ratio, and the estimate's error drives the
damped correction. On 2026-10-23 only 10 of 239 groups had moved class since
2026-10-17. That is why the state was seeded equal (m1 1, cloud 1) and not
from a fit.


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
