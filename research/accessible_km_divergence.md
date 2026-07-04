# accessible_km divergence — high-threshold species (BT / ST / CT-DV-RB)

**Status:** RESOLVED + ROOT-CAUSED (2026-07-03) — mechanism is **segmentation
granularity**: link's streams don't break at gradient barriers because the break source
`gradient_barriers_minimal` is the `frs_barriers_minimal()` downstream-most reduction
(correct for the access DECISION, wrong as a SEGMENTATION source). **Fixable link
defect** — break at the full per-species barrier positions + reclassify like bcfp (do
NOT clip); `barriers_<sp>_access` already holds the barrier, so no barrier-set change is
needed. See "## ROOT CAUSE" + "## RESOLVED" below. Living doc — append dated entries.
**Relates to:** link#221 (per-WSG `accessible_km` parity), `planning/active/findings.md`
(task-scoped, will be archived), and **link#223** (the tracking issue — filed 2026-07-03,
root-cause framing + embedded PNG). **Visual proof:** `research/blk359209845_bt_accessible_km.png`
(committed `1a26f7d`; generator `/tmp/blk_proof.R`) — blk 359209845 FINA BT, the
`[3835, 7998]` reach link keeps whole & accessible while bcfp blocks it.

This doc exists because this class of problem (link-vs-bcfp parity divergence) has
historically burned tens of hours in **misdiagnosis-after-misdiagnosis**. Its
primary value is: **what has been DECISIVELY ruled out (with reproducible
evidence), so no one re-chases it**, plus the exact commands to continue.

---

## TL;DR (as of 2026-07-02)

- **Symptom:** link's `accessible_km` for BT systematically **exceeds** bcfp, up to
  **+40% (PCEA)**, **+23.6% (FINA)**; **every WSG link ≥ bcfp**; magnitude scales
  **monotonically** with the species `access_gradient_max` (CO 0.15 clean ≤0.27% →
  ST 0.20 minor → BT 0.25 material). Extra km is **diffuse** (PCEA: ~2020 km over
  1676 blue_line_keys, no dominant BLK) and **concentrated in steep reaches**.
- **DECISIVELY RULED OUT this session:** raw gradient-barrier **placement**. On FINA,
  link's ≥0.25 gradient barriers are a **strict positional superset** of bcfp's —
  every bcfp barrier present in link at identical `(blue_line_key, DRM±1m)`,
  `bcfp-only = 0`, link +24 (0.1%). See §"Ruled out #4".
- **Therefore the +23.6% is 100% downstream of raw gradient detection.** Narrowed to
  three candidates (§"Narrowed hypotheses"): assembled barrier-**set composition**,
  per-segment km **measurement/segmentation**, or the access **trace/exclusion**.
- **RESOLVED 2026-07-03 (§"## RESOLVED"):** none of the three narrowed hypotheses in
  the "barrier set / access trace" family — it's **H2, segmentation granularity**.
  bcfp sub-segments the identical FWA network finer than link at gradient-barrier
  boundaries; every bcfp-only sub-segment is the **blocked** steep reach above the
  barrier. link keeps it inside a coarser accessible segment. The over-credit km
  **equals** bcfp's finer-only blocked km, 3/3 WSGs. link & bcfp agree on the access
  DECISION at 99.99% of shared segment positions.
- **ROOT-CAUSED 2026-07-03 (§"## ROOT CAUSE"):** the segmentation difference is one link
  code path — `gradient_barriers_minimal` (a stream-break source) is built by
  `fresh::frs_barriers_minimal()` (`lnk_pipeline_prepare.R:592`), the downstream-most
  per-flow-path reduction. Right for the ACCESS decision, but it strips the interior
  break points, so link's segments straddle gradient barriers. **Fixable**: break at the
  full barrier positions + reclassify (NOT clip) — `barriers_<sp>_access` already contains
  the barrier. Fix in a separate branch, then prove bcfp-equivalence in the vignette.

---

## RESOLVED (2026-07-03) — segmentation-granularity length-apportionment

**One-line:** link and bcfp agree on BT accessibility at 99.99% of co-located segment
starts; the aggregate `accessible_km` gap is **entirely** bcfp sub-segmenting the same
network finer at gradient-barrier boundaries and blocking the above-barrier tail that
link keeps whole inside a coarser accessible segment. Not a bug, not barrier placement,
not access logic, not rollup arithmetic — a **measurement granularity** difference.

### The decisive test (per-segment confusion matrix, both DBs local on :5432)

Both `fresh.streams`⋈`fresh.streams_access` (link) and `fresh.streams_vw_bcfp` (bcfp
ref) live on `:5432`, so they join directly on the FWA position key
`(blue_line_key, round(downstream_route_measure,3))` — the **same key**
`lnk_compare_mapping_code()` uses (`R/lnk_compare_mapping_code.R:229`). `access_bt IN
(1,2)` = link-accessible; `barriers_bt_dnstr = ''` = bcfp-accessible.

**Link-weighted (FINA):** 26089/26094 link segments find a co-located bcfp start
(99.98% coverage; 11731/11733 km). Of that, **count-match 99.98%, km-match 99.99%**;
`link_only` (link-acc & bcfp-blocked) = **0 km**. So at shared positions the access
decision is identical — link does NOT flag co-located segments more generously.

**Ref-weighted, all 3 WSGs** (`ref LEFT JOIN link`, bcfp segments with NO co-located
link start = bcfp's finer-only pieces):

| WSG | agg gap `link_bt−ref_bt` | bcfp extra-seg n | extra-seg km | of which **blocked** |
|---|---:|---:|---:|---:|
| FINA | 7521−6085 = **+1436** | 2589 | 1438 | **1438** (100%) |
| PARS | 7057−6823 = **+234** | 540 | 245 | 238 (97%) |
| PCEA | 7023−5003 = **+2020** | 4258 | 2021 | **2021** (100%) |

The over-credit **= bcfp's finer-only blocked km**, to rounding, 3/3. bcfp's extra
segments are ~99–100% blocked (they're the steep reach above the gradient barrier);
link has no break there so the reach stays in a larger accessible segment.

### Why 99.57% mapping_code parity coexists with +23.6% accessible_km

`lnk_compare_mapping_code()` is an **INNER** merge on position
(`R/lnk_compare_mapping_code.R:229-232`) and `match_pct = n_match/n_total` is
**segment-COUNT-weighted** (`:276`). The inner join **silently drops bcfp's finer-only
segments** — exactly the 1438 km that diverge — so parity never sees them.
accessible_km sums both full segmentations independently, so it does. Both metrics are
internally correct; they measure different populations. (Implication for #175: the
count-weighted, inner-join parity metric has a blind spot to segmentation granularity
at gradient boundaries for high-threshold species. The habitat-km rollups are unaffected
in kind but share the sensitivity.)

### Why monotonic in `access_gradient_max`

Higher threshold → species accesses steeper terrain → more accessible segments abut a
gradient barrier → more boundary sub-segments where link's coarser break over-credits
the above-barrier tail. CO 0.15 accesses little steep terrain (few boundaries → ≤0.27%);
BT 0.25 accesses more (many boundaries → material). Confirms the earlier USKE control
(only 6.4% of link BT-accessible km lies above 0.25 — link isn't leaking broadly; it's a
boundary-resolution effect, mean bcfp extra-seg length ~555 m on FINA).

### Reproduce (single query, :5432, no tunnel)

```bash
PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -P pager=off -c "
WITH link AS (
  SELECT s.watershed_group_code AS wsg, s.blue_line_key AS blk,
         round(s.downstream_route_measure::numeric,3) AS drm,
         s.length_metre AS len, (a.access_bt IN (1,2)) AS link_acc
  FROM fresh.streams s JOIN fresh.streams_access a
    ON s.id_segment=a.id_segment AND s.watershed_group_code=a.watershed_group_code
  WHERE s.watershed_group_code IN ('FINA','PARS','PCEA')),
ref AS (
  SELECT watershed_group_code AS wsg, blue_line_key AS blk,
         round(downstream_route_measure::numeric,3) AS drm,
         length_metre AS len, (barriers_bt_dnstr='') AS ref_acc
  FROM fresh.streams_vw_bcfp WHERE watershed_group_code IN ('FINA','PARS','PCEA'))
SELECT r.wsg,
  round((sum(r.len) FILTER (WHERE NOT r.ref_acc AND l.blk IS NULL)/1000.0)::numeric,0) AS unmatched_blk_km,
  count(*) FILTER (WHERE l.blk IS NULL) AS unmatched_n
FROM ref r LEFT JOIN link l ON l.wsg=r.wsg AND l.blk=r.blk AND l.drm=r.drm
GROUP BY r.wsg ORDER BY r.wsg;"
```

Gotcha: `round(<double>/1000.0, n)` fails (`round(double,int) does not exist`) — wrap the
whole expression `(expr)::numeric` INSIDE `round`, not the divisor.

### Verdict + implications

- **Not a link defect in placement or access logic.** Barriers land identically
  (§"Ruled out #4"); access agrees at 99.99% of shared positions.
- **It IS a granularity accuracy gap in the *product*:** link labels ~1438 km (FINA) /
  2021 km (PCEA) of above-gradient-barrier steep reach as BT-accessible because its
  segments span the barrier. Physically that reach is not BT-accessible; bcfp (finer
  breaks) blocks it. For salmon (0.15) the gap is negligible (≤0.27%).
- **The reconciliation is a concrete fix, not a defer** (see §"## ROOT CAUSE"): build the
  segmentation break source from the **full** per-species barrier positions instead of the
  `frs_barriers_minimal()` reduction, so link's streams break at every gradient barrier
  like bcfp; the existing access trace then reclassifies the above-barrier segment as
  blocked. **Do NOT clip** roll-up lengths and do NOT move barriers — placement is already
  identical (§"Ruled out #4") and `barriers_<sp>_access` already holds the barrier.
- **#221 decision (updated):** ship salmon-group accessible_km now (proven ≤0.27%); BT/ST
  unblock **after** the segmentation fix lands on its own branch — then demonstrate
  bcfp-equivalence in the vignette. No longer "permanently deferred / documented
  artifact"; it's a fixable defect with a known fix.
- **It's a LINK issue, not fresh.** The missing break is in link's segmentation of the
  access path (`gradient_barriers_minimal`), not in fresh gradient detection. Filed as
  **link#223** (2026-07-03) with the root-cause framing + embedded PNG.

---

## ROOT CAUSE (code-level, 2026-07-03) — `gradient_barriers_minimal` is a minimal reduction used as a segmentation source

The aggregate "segmentation granularity" difference above is produced by one specific
link code path. link **does** break-and-reclassify like bcfp (it does **not** clip) — but
the break source it feeds the access segmentation is the **downstream-most reduction** of
the barrier set, not the full set, so the interior break points are missing.

### The path

1. `lnk_pipeline_run.R:220` — the access phase runs `lnk_pipeline_access()` over the
   coarse `<schema>.streams` break segmentation, deciding each segment from
   `<schema>.barriers_<sp>_access` (`barriers_per_sp`, assembled `:216`).
2. That `streams` segmentation is built from break sources assembled in
   `lnk_pipeline_prepare.R` / `_break.R`. One source is `gradient_barriers_minimal`.
3. `lnk_pipeline_prepare.R:574-592` (`.lnk_pipeline_prep_minimal`) builds, per model,
   `barriers_<model>` = `gradient_barriers_raw WHERE gradient_class IN (class_filter)`
   `UNION ALL` falls, then runs **`fresh::frs_barriers_minimal(conn, from, to)`** on it
   (`:592`) and unions the per-model results into `gradient_barriers_minimal` (`:646`).
4. `frs_barriers_minimal.R:120-134` — the reduction `DELETE`s any barrier that has another
   barrier **downstream** of it on the same flow path (`whse_basemapping.fwa_upstream()`),
   keeping only the **downstream-most** point per path. "Once the downstream-most barrier
   is present, any barrier upstream of it is redundant **for access-blocking**" — true for
   the access DECISION, false for SEGMENTATION.

Result: a segment can span a gradient barrier. Its `downstream_route_measure` sits
**below** the barrier, so `frs_network_features(direction="downstream")` in
`lnk_pipeline_access.R:156-165` finds no barrier downstream of the segment start →
`has_barriers_<sp>_dnstr = FALSE` (`:356`) → `access_<sp> = 1` (`:364`) for the **whole**
segment, including the blocked reach above the barrier.

### The author already knew this tension — for orphans

`lnk_pipeline_prepare.R:606-611` (comment, abridged): *"Critically — DO NOT run
frs_barriers_minimal on the orphan set. Minimal reduction keeps only the downstream-most
blocking position per flow path; that's correct semantics for ACCESS barriers, but
orphans are segmentation positions only. We want every detected position to split the
network, not just the downstream-most one."* The same reasoning applies to the per-species
gradient+falls sets that feed `gradient_barriers_minimal` — they are ALSO segmentation
positions — but the minimal reduction was left in for them. **That is the bug.**

### Decisive evidence on blk 359209845 (FINA, BT) — the PNG segment

Three distinct barrier sets on this blue line:

| set | what | n on blk 359209845 |
|---|---|---:|
| `working_fina.barriers_bt` | prep, pre-minimal = gradient ≥2500 ∪ falls | **16** (incl frontier 3834.78) |
| `barriers_bt_min` (→ `gradient_barriers_minimal`) | `frs_barriers_minimal` reduction | **0** |
| `barriers_bt_access` (view) | the ACCESS-decision set | **16** (incl frontier 3834.78) |

- **Why the minimal set is empty here:** `frs_barriers_minimal` pruned all 16 — even the
  frontier at 3834.78 — because **two BT barriers on the parent mainstem blk 359572348**
  (wscode `200.948755`) at measures **1684183.02 / 1706109.93** are topologically
  downstream of the confluence per `fwa_upstream()`. So there is no break anywhere on
  359209845, and its top segment `[3391, 7998]` (4607 m) stays one accessible unit.
- **Why the fix needs no barrier-set change:** the ACCESS set `barriers_bt_access`
  **already contains** the frontier 3834.78. Break the stream at 3835 → new segment
  `[3835, 7998]` whose reference measure IS the barrier → `has_barriers_bt_dnstr = TRUE` →
  reclassified **blocked**. Nothing added to the barrier set; only the segmentation changes.

Numbers this segment asserts (matches `/tmp/blk_proof.png`):

| | segment | length | label |
|---|---|---:|---|
| **LINK** | `[3391, 7998]` | 4607 m | access_bt=1 (accessible) — whole |
| **bcfp** | `[3391, 3835]` | 444 m | accessible |
| **bcfp** | `[3835, 7998]` | **4163 m** | **blocked** |

Over-credit on this ONE blue line = **4163 m**. Aggregated over FINA that's the +1436
segment / +1438 km gap in the confusion matrix above.

### The fix (separate branch)

Feed the access segmentation the **full** per-species barrier positions (gradient FULL ∪
falls ∪ definite), not the `frs_barriers_minimal()` reduction — i.e. give the per-species
gradient+falls sets the same "don't-minimize, these are segmentation positions" treatment
`lnk_pipeline_prepare.R:606-611` already gives orphans. Then the existing access trace
reclassifies each above-barrier segment as blocked, exactly like bcfp. **No clipping in
the roll-up; no barrier moved.** Validate: rerun `accessible_km` for BT on FINA/PARS/PCEA
→ expect convergence to bcfp within salmon-group tolerance; then wire BT/ST into
`lnk_parity_annotate()` and demonstrate equivalence in the vignette.

---

## Environment / reproducibility

Two **separate** postgres instances (cannot SQL-join across them — see gotchas):

| role | conn | creds | db |
|---|---|---|---|
| link/fresh local | `localhost:5432` | `postgres` / `postgres` | `fwapg` |
| bcfp tunnel | `localhost:63333` | `newgraph` / `postgres` | `bcfishpass` |

- **Tunnel is intermittent.** Working cred is `newgraph`/`postgres` (NOT the dead
  `airvine`/`*_SHARE` path in older notes). Verify live before relying on it.
- **FWA input is byte-identical** between the two DBs (USKE 23458 streams /
  9,436,876 m on both). FINA gradient-barrier class counts match to ≤0.2% (below),
  independently reconfirming identical FWA.

### Table map (what lives where)

**link — raw gradient barriers** (per working schema; single-WSG, no `wsg` column):
`working_<wsg>.gradient_barriers_raw` — `(blue_line_key, downstream_route_measure,
gradient_class, label, source, wscode_ltree, localcode_ltree)`.
`gradient_class` encoded **×10000** (0.25 → `2500`). `label='gradient'`,
`source='attribute'`. Also `working_<wsg>.gradient_barriers_minimal` (island-reduced).
34 working schemas present locally (adms, bbar, …, pcea, …, ufra, unrs, will).

**link — assembled per-species barriers** (persist, province-wide):
`fresh.barriers_<sp>_unified` (VIEW: `barrier_source`, `barrier_subtype`,
`passability`, `blocks_species text[]`, `blue_line_key`, `watershed_key`,
`downstream_route_measure`, `watershed_group_code`, `geom`) and
`fresh.barriers_<sp>_access`. `<sp>` ∈ {bt, ch, cm, co, pk, sk, st, …}.

**link — km inputs** (persist): `fresh.streams` (`length_metre`; PK
`(id_segment, watershed_group_code)` — **#203: join on full PK**),
`fresh.streams_access` (`access_<sp>` int: −9 absent / 0 blocked / 1 modelled / 2
observed), `fresh.streams_vw_bcfp` (the tunnel-free bcfp ref; `barriers_<group>_dnstr`
stored as **comma-joined varchar**, accessible predicate `= ''`).

**bcfp tunnel — raw gradient:** `bcfishpass.gradient_barriers` — `(blue_line_key,
downstream_route_measure, wscode_ltree, localcode_ltree, watershed_group_code,
gradient_class)`. `gradient_class` encoded **×100** (0.25 → `25`), classes
{5,7,10,12,15,20,25,30}.

**bcfp tunnel — type-mapped / assembled / components:** `barriers_gradient`
(`barrier_type='GRADIENT_NN'`), `barriers_bt` / `barriers_ch_cm_co_pk_sk` /
`barriers_st` / `barriers_ct_dv_rb` / `barriers_wct`, and the component sources
`barriers_falls`, `barriers_subsurfaceflow`, `barriers_user_definite`.
`bcfishpass.streams` stores `barriers_<group>_dnstr` as **`array[]::text[]`** (note:
different type than `streams_vw_bcfp`'s varchar).

Fuller cross-reference: `research/bcfp_table_map.md`.

### Species → barrier group + gradient cutoff
`inst/extdata/configs/bcfishpass/parameters_fresh.csv` (`access_gradient_max`):
CH/CM/CO/PK/SK **0.15** → `barriers_ch_cm_co_pk_sk_dnstr`; ST **0.20** →
`barriers_st_dnstr`; WCT **0.20** → `barriers_wct_dnstr`; BT **0.25** →
`barriers_bt_dnstr`; CT/DV/RB **0.25** → `barriers_ct_dv_rb_dnstr`.
bcfp side: `model_access_bt.sql` blocks BT on `GRADIENT_25 ∪ GRADIENT_30` (≥0.25);
`model_access_ch_cm_co_pk_sk.sql` on `GRADIENT_15/20/25/30` (≥0.15);
`model_access_ct_dv_rb.sql` on `GRADIENT_25/30` (≥0.25).

---

## Ruled OUT (with evidence — do NOT re-chase)

**1. Gradient-barrier detection METHOD.** fresh `.frs_break_find_multiclass`
(`fresh/R/frs_break.R`) is a faithful port of bcfp `gradient_barriers_load.sql`
(`smnorris/bcfishpass@f4ae29d`): same 100 m upstream window, same per-FWA-vertex
`ST_LocateAlong` Z-delta on `whse_basemapping.fwa_stream_networks_sp`, same
`blue_line_key = watershed_key` mainstem filter, same island grouping, `min_length=0`.

**2. FWA input.** Byte-identical between :5432 and :63333 (USKE 23458 /
9,436,876 m).

**3. Gradient cutoff value.** BT ≥0.25 on both sides (link
`access_gradient_max=0.25`; bcfp `GRADIENT_25 ∪ GRADIENT_30`).

**4. Raw gradient-barrier PLACEMENT — decisively ruled out 2026-07-02.**
Class-by-class raw counts, FINA (link `gradient_class` ×10000 ↔ bcfp ×100):

| gradient | link n | bcfp n | Δ |
|---|---|---|---|
| 0.15 | 13110 | 13085 | +25 |
| 0.20 | 13263 | 13241 | +22 |
| 0.25 | 13117 | 13101 | +16 |
| 0.30 | 10390 | 10382 | +8 |

Positional diff of the **≥0.25** set (blk, DRM→nearest m): link **23,507**, bcfp
**23,483**, **common 23,483**, **bcfp-only 0**, **link-only 24 (0.1%)**. link's raw
gradient barriers are a **strict positional superset** of bcfp's. The 24 extra would
make link *more* restrictive — **opposite** to the observed over-credit. So raw
gradient placement cannot be the cause; the divergence is entirely downstream of it.

Reproduce (note: `comm` needs **lexically** sorted input — psql `ORDER BY` sorts
numerically, so pipe through `sort`):
```bash
PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d fwapg -At -F',' \
  -c "SELECT blue_line_key, round(downstream_route_measure::numeric)
      FROM working_fina.gradient_barriers_raw WHERE gradient_class >= 2500" \
  | sort > /tmp/fina_link_ge25.sorted
PGPASSWORD=postgres psql -h localhost -p 63333 -U newgraph -d bcfishpass -At -F',' \
  -c "SELECT blue_line_key, round(downstream_route_measure::numeric)
      FROM bcfishpass.gradient_barriers
      WHERE watershed_group_code='FINA' AND gradient_class >= 25" \
  | sort > /tmp/fina_bcfp_ge25.sorted
comm -12 /tmp/fina_link_ge25.sorted /tmp/fina_bcfp_ge25.sorted | wc -l  # common
comm -23 /tmp/fina_link_ge25.sorted /tmp/fina_bcfp_ge25.sorted | wc -l  # link-only
comm -13 /tmp/fina_link_ge25.sorted /tmp/fina_bcfp_ge25.sorted | wc -l  # bcfp-only
```

---

## Narrowed hypotheses (all downstream of raw gradient detection)

Direction constraint: **link ≥ bcfp ⇒ link applies FEWER effective downstream
barriers than bcfp** (more accessible = fewer barriers blocking upstream). Since raw
gradient barriers are identical, the missing/differing barriers or measurement is
elsewhere.

**H1 — Assembled barrier-SET composition.** bcfp BT set
(`model_access_bt.sql`) = `gradient(≥0.25) ∪ barriers_falls ∪ barriers_subsurfaceflow
∪ barriers_user_definite`, **MINUS** barriers with a fish observation upstream (20 m
tol) or confirmed habitat upstream (200 m tol). If link's BT set omits (or
down-weights) falls/subsurfaceflow that bcfp includes, and those sit **below steep
terrain**, bcfp blocks the steep upstream habitat that link credits → matches both
the direction AND the steep-reach concentration. (SETN subsurfaceflow-stale is a
known member of this class — `research/bcfp_divergence_taxonomy.yml`,
`provincial_parity_2026_05_01.md`.) **Test:** diff `fresh.barriers_bt_unified` vs
`bcfishpass.barriers_bt` on FINA, bucketed by `barrier_source`/type.

**H2 — Per-segment km MEASUREMENT / segmentation.** Identical barrier positions but
**different stream segmentation** → a segment straddling the 0.25 boundary gets
credited accessible **as a whole unit**. Scales with threshold (steeper terrain ⇒
more/longer boundary segments), which fits the monotonic CO<ST<BT signature. **Test:**
segment-level `access_bt IN (1,2)` (link) vs `barriers_bt_dnstr = ''`
(`streams_vw_bcfp`), joined on segment, bucketed by gradient + DRM; look for the extra
km at boundary segments.

**H3 — Access TRACE / obs-habitat EXCLUSION.** bcfp's `barriers_filtered` removal of
obs/habitat-upstream barriers differing from link's could shift which barriers are
effective. (Weaker fit to steep-reach concentration; check after H1/H2.)

Note on raw-vs-minimal: access only cares about the **downstream-most** barrier per
stream, so link using `gradient_barriers_raw` vs `_minimal` should not change access
outcomes — but confirm link applies the same set bcfp does.

---

## Next steps (pick up here)

1. **H1 assembled-set diff** — `fresh.barriers_bt_unified` vs `bcfishpass.barriers_bt`
   (FINA) by `barrier_source`; quantify falls/subsurfaceflow present in one but not
   the other, and whether they sit below steep reaches.
2. **H2 segment measurement diff** — per-segment access flag + gradient + DRM, link vs
   `streams_vw_bcfp`; localize the extra km (boundary segments vs whole reaches).
3. **Extend the positional check** (§Ruled-out #4) to **PCEA** (biggest divergence,
   working_pcea present) and **USKE** (FWA-verified) to confirm the superset result
   generalizes.
4. **DONE (2026-07-03):** filed as **link#223** (root-cause framing, bcfp SHA pinned,
   PNG embedded). Next: land the segmentation fix on its own branch, then return to
   link#221 Phase 3 (keep the `accessible_km` ref **salmon-group-only** — proven ≤0.27%
   — and wire BT/ST after the fix proves bcfp-equivalence).

---

## Gotchas

- **Cross-DB:** :5432 and :63333 are separate instances — no direct SQL join. Export
  CSV + `sort` + `comm`, or stage one side into the other. (`bcfishpass_ref` schema
  exists on :5432 but verify its vintage before trusting it as the reference.)
- **`comm` needs lexically sorted input.** psql `ORDER BY blk, drm` sorts numerically;
  always pipe through `sort` first or `comm` silently misreports.
- **DRM float:** round to nearest metre to absorb sub-metre float differences between
  the two DBs before comparing positions.
- **gradient_class encoding differs:** link ×10000 (`2500`), bcfp ×100 (`25`). Not a
  bug — just normalize when comparing (link `>= 2500` ↔ bcfp `gradient_class in
  (25,30)`).
- **#203 join discipline:** `id_segment` is NOT globally unique in the consolidated
  `fresh` persist; join on full PK `(id_segment, watershed_group_code)`.
- **Tunnel cred:** `newgraph`/`postgres`, intermittent availability.

---

## Session log

### 2026-07-03
- **Root-caused** the BT accessible_km over-credit to `gradient_barriers_minimal` being
  the `frs_barriers_minimal()` downstream-most reduction used as a segmentation break
  source (`lnk_pipeline_prepare.R:592`; the author already excludes orphans from this at
  `:606-611`). Proven at segment level on blk 359209845 (FINA, BT): the `[3391, 7998]`
  4607 m segment stays accessible whole because the minimal reduction pruned all 16
  barriers (parent-mainstem blk 359572348 barriers downstream of the confluence), while
  `barriers_bt_access` still holds the frontier 3834.78 → break+reclassify fixes it with
  no barrier-set change. Over-credit on this blk = 4163 m.
- Built the visual proof (generator `/tmp/blk_proof.R`): schematic linear diagram +
  geographic map, LINK vs bcfp, barrier at 3835. Committed to the repo as
  `research/blk359209845_bt_accessible_km.png` (`1a26f7d`) — gists don't reliably serve
  binary PNGs, so a committed file + pinned `raw.githubusercontent.com` URL is the
  hosting mechanism for the issue embed.
- Verdict shifted from "defer BT/ST as documented artifact" → **fixable link defect**; fix
  on a separate branch (break at full per-species barrier positions + reclassify, NOT
  clip), then demonstrate bcfp-equivalence in the vignette. No pipeline code committed yet.
- **Filed link#223** (2026-07-03) with the root-cause framing + embedded PNG. Pushed the
  `221-…` branch (was 8 commits ahead, never pushed) to host the image.
- Next: land the segmentation fix on its own branch.

### 2026-07-02
- Ruled out raw gradient-barrier placement decisively (FINA positional superset;
  §Ruled-out #4). Established the link/bcfp table map + class encodings. Narrowed to
  H1/H2/H3. No code committed; read-only DB work. Next: H1 assembled-set diff on FINA.
