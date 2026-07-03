# Findings — Per-WSG habitat/access km roll-up (accessible_km) (#221)

## Premise verified live (2026-07-01, local docker fwapg localhost:5432)

- `fresh.streams_vw_bcfp` exposes `barriers_ch_cm_co_pk_sk_dnstr`,
  `barriers_bt_dnstr`, `barriers_st_dnstr`, `barriers_wct_dnstr`,
  `barriers_ct_dv_rb_dnstr`, `barriers_dams_dnstr`, `barriers_pscis_dnstr`,
  `barriers_anthropogenic_dnstr`, `length_metre`, `spawning_<sp>`, `rearing_<sp>`,
  `watershed_group_code`, `segmented_stream_id`.

## Predicate correction to the issue body

The `barriers_<group>_dnstr` columns in `fresh.streams_vw_bcfp` are stored as
`character varying` (comma-joined string), **not** `text[]`. `= array[]::text[]`
errors (`operator does not exist: character varying = text[]`). The accessible
predicate is `barriers_ch_cm_co_pk_sk_dnstr = ''` — empty string means no
barrier downstream. In MORR, the empty-string bucket holds 12,485 segments; every
other value is a barrier id / comma list.

## Coho accessible_km proof (validated)

- link side: `fresh.streams s JOIN fresh.streams_access a ON
  s.id_segment=a.id_segment AND s.watershed_group_code=a.watershed_group_code`
  (full PK, #203), `WHERE a.access_co IN (1,2)`, `sum(s.length_metre)/1000`.
- ref side: `fresh.streams_vw_bcfp WHERE barriers_ch_cm_co_pk_sk_dnstr = ''`,
  `sum(length_metre)/1000`.
- Result: **20 WSGs** present locally in both tables. **19/20 within ±5%**, most
  under 1% (COTR/LKEL/WILL 0.00; MORR 0.09; BULK 0.27; largest passing FRCN 4.30,
  LFRA 4.16). Full table in `data-raw/accessible_km_proof_co.R` header / run output.

### SETN — known divergence (excluded from hard-fail)
- SETN pct_diff **+109.75%** (link 1497.55 km vs ref 713.95 km). This is the
  **expected direction**: bcfp's `barriers_subsurfaceflow` is stale for ~95% of
  SETN segments (74,816 / 78,937), propagating into
  `barriers_ch_cm_co_pk_sk_dnstr` so bcfp UNDER-credits accessible habitat. link
  correctly applies `user_barriers_definite_control`. Documented as
  `setn-anadr-*-stale` in `research/bcfp_divergence_taxonomy.yml`
  (status INTENTIONAL) + `research/provincial_parity_2026_05_01.md`. **Not a link
  defect** — reproducing it is validation that accessible_km faithfully tracks the
  access model. The proof script allowlists SETN (`known_divergence`) so it prints
  + flags but does not hard-fail.

## Per-species vs salmon-group reconciliation

link models `access_co` per species; bcfp models CO inside the salmon group
`barriers_ch_cm_co_pk_sk_dnstr` (shared barrier table — a barrier that blocks CH
but not CO cannot exist in bcfp). The ≤0.27% agreement **empirically confirms**
they agree for CO on the tested WSGs. Watch for divergence if `blocks_species`
encoding (link#152/#200 per-species barrier views) drifts from bcfp's shared
salmon group at scale.

## Plan-agent review (sonnet) — resolved items

- B1/A1 (unverified snapshot columns) → resolved: columns confirmed present; only
  the array-vs-text predicate needed correction.
- B2 (length join) → the draft SQL already joins `streams` for `length_metre`;
  correct.
- O2 / row-count test breakage → captured as an explicit Phase 2 task.
- AC1 (single-WSG) → proof runs over all locally-available WSGs (2 today).
- AC2 (untestable ad-hoc SQL) → Phase 1 deliverable is a reproducible
  `data-raw/` script with a hard ≤5% assertion.

## Phase 3 — per-species proofs (2026-07-02, local docker fwapg)

Local persist coverage: `access_bt` populated (47 WSGs), `access_st` (14 WSGs),
`access_wct` column present but **0 rows populated**, `access_ct/dv/rb` columns
**absent**. So only BT + ST are provable locally; WCT/CT/DV/RB have no data.

### ST (`access_st` ↔ `barriers_st_dnstr`) — passes
14 WSGs; 3 over ±5%: **SETN +90.6%** (known `setn-anadr-*` salmon-stale class;
ST is in that taxonomy entry), **FRCN +6.19%**, **USKE +9.45%** (link ≥ bcfp;
same steep-reach class as BT below, smaller at ST's 0.20 threshold).

### BT (`access_bt` ↔ `barriers_bt_dnstr`) — does NOT pass ±5%
47 WSGs; **12 over ±5%, every WSG link ≥ bcfp** (systematic positive bias):
PCEA +40.4, UFRA +24.5, FINA +23.6, FIRE +13.3, UNRS +12.1, FOXR/USKE/LFRA/FRCN
~8, BBAR +7.2, HARR +5.8, MORK +5.4. LBTN/LPCE NULL-ref = **snapshot coverage
gap** (0 rows in `streams_vw_bcfp`), not a divergence.

### Root-cause investigation (PCEA + USKE)
- The link-extra (~2020 km on PCEA) is **diffuse** — spread across 1676
  blue_line_keys, top single-blk only 2 km. Not a handful of miscoded barriers.
- **Gradient histogram (PCEA link BT-accessible km):** the gap is almost
  entirely in steep reaches — link credits ~2315 km at gradient ≥20% vs bcfp
  ~577 km (measure-join). link 1293 km at ≥30% vs bcfp ~218.
- **Not a persist/recompute artifact.** Control (USKE, km above each species'
  OWN `access_gradient_max`): CO 0.1% (thr 0.15), BT 6.4% (0.25), ST 7.9%
  (0.20). link gates correctly at every threshold; the small above-threshold
  residual is a segment-averaging boundary effect that scales with the
  threshold (more steep terrain reachable → more boundary segments).
- **Divergence magnitude ranks monotonically by `access_gradient_max`:**
  CO 0.15 (clean, proven ≤0.27%) < ST 0.20 (minor) < BT 0.25 (material). link
  and bcfp share the same 0.25 BT threshold in `configs/bcfishpass/parameters_fresh.csv`,
  so the gap is in gradient-barrier **placement / access-tracing**, not the
  threshold value.

**Verdict:** BT accessible_km divergence is a genuine, systematic, BT-specific
**steep-reach gradient-barrier methodology divergence** (link credits more steep
access than bcfp; likely link-defensible but unadjudicated). It is NOT a bug,
NOT a persist artifact, NOT barrier miscoding. Adjudicating link-vs-bcfp gradient
barrier placement needs a fresh-side reconciliation — out of scope for #221.
Recommendation: keep the accessible_km ref salmon-group-only (proven) for this
PR; do not wire BT/ST past their proofs yet; file a follow-up issue for the
steep-reach reconciliation covering the higher-threshold species (BT/ST/WCT/CT/DV/RB).

## Phase 3 mechanism deep-dive (2026-07-02) — CORRECTS the verdict above

The "gradient-barrier placement methodology divergence" verdict above is
**wrong / incomplete**. This session traced the actual code on both sides and
ruled placement OUT:

### Gradient-barrier DETECTION is byte-identical link↔bcfp
- fresh `frs_break_find()` multiclass (`fresh/R/frs_break.R`,
  `.frs_break_find_multiclass`) is a faithful port of bcfp
  `gradient_barriers_load.sql` (`smnorris/bcfishpass@f4ae29d`): same 100 m
  upstream window, same per-FWA-vertex `ST_LocateAlong` elevation-delta
  method on `whse_basemapping.fwa_stream_networks_sp`, same
  `blue_line_key = watershed_key` mainstem filter, `min_length=0` default.
- **FWA input is byte-identical** between local docker fwapg (:5432) and the
  bcfp tunnel (:63333): USKE = 23458 streams / 9,436,876 m on both.
- **BT effective cutoff identical:** bcfp blocks BT on `GRADIENT_25 + GRADIENT_30`
  (`model_access_bt.sql:16`) = gradient ≥ 0.25; fresh's open-ended top class
  `[0.25,∞)` = same. Salmon: bcfp `GRADIENT_15/20/25/30` = ≥0.15 (matches
  link 0.15). CT/DV/RB: `GRADIENT_25/30` = ≥0.25.
- ⇒ Same method + same data + same cutoff ⇒ gradient barriers **land at the
  same positions**. Placement is NOT the divergence.

### The real suspect: BT barrier-SET composition + km measurement
bcfp's `barriers_bt_dnstr` (`model_access_bt.sql`) is:
`gradient(≥0.25) ∪ barriers_falls ∪ barriers_subsurfaceflow ∪ barriers_user_definite`,
**MINUS** any barrier with a BT/salmon/steelhead **observation upstream** (20 m
tol) OR confirmed **habitat upstream** (200 m tol). link ≥ bcfp (link credits
more) ⇒ link applies FEWER effective downstream barriers than bcfp. Leading
candidates (UNRESOLVED — this is the fresh-issue diagnosis):
1. Non-gradient barrier types bcfp includes that link's `access_bt` weights
   differently (falls, subsurfaceflow — note SETN subsurface-stale is already
   documented; but USKE/PCEA gap is steep-reach-concentrated, not obviously
   subsurface).
2. Per-segment km measurement on different segment definitions +
   downstream-trace: same barrier vertex, but a link segment spanning the
   barrier gets credited accessible as a unit (segment-averaging boundary
   effect) — scales with threshold because steeper terrain = more/longer
   boundary segments.
3. bcfp's obs/habitat-upstream barrier EXCLUSION differing from link's.

### Diagnostic RAN 2026-07-02 (FINA) — placement DECISIVELY ruled out
Compared raw gradient-barrier landing positions link-vs-bcfp on FINA BT:
link `working_fina.gradient_barriers_raw` (:5432) vs tunnel
`bcfishpass.gradient_barriers` (:63333). **≥0.25 set: link 23,507 vs bcfp
23,483; all 23,483 bcfp barriers present in link at identical `(blk, DRM±1m)`;
bcfp-only = 0; link +24 (0.1%).** Strict positional superset → raw gradient
placement is NOT the divergence (the 24 extra would make link *more*
restrictive, opposite to the over-credit). The +23.6% is entirely downstream of
raw detection. Full write-up + reproduce commands + narrowed hypotheses (H1
assembled-set composition / H2 segment measurement / H3 access trace) now live
in the durable **`research/accessible_km_divergence.md`** (this findings.md is
task-scoped + will be archived). Next: H1 — diff `fresh.barriers_bt_unified` vs
`bcfishpass.barriers_bt` (FINA) by `barrier_source`.

### RESOLVED 2026-07-03 — segmentation granularity, NOT access model
Per-segment confusion matrix (both DBs local on :5432, join on the same FWA
position key `(blue_line_key, round(drm,3))` that `lnk_compare_mapping_code()`
uses) settles it. Link-weighted FINA BT: 26089/26094 link segs co-locate with a
bcfp start; **count-match 99.98%, km-match 99.99%, `link_only` over-credit = 0
km**. Ref-weighted, bcfp's finer-only (no co-located link start) segments:

| WSG | agg gap link_bt−ref_bt | bcfp extra-seg km | blocked |
|---|---:|---:|---:|
| FINA | +1436 | 1438 | 1438 (100%) |
| PARS | +234 | 245 | 238 |
| PCEA | +2020 | 2021 | 2021 (100%) |

The over-credit **equals** bcfp's finer-only blocked km, 3/3. Mechanism: bcfp
sub-segments the identical FWA network finer at gradient-barrier boundaries and
blocks the steep above-barrier tail; link keeps it inside a coarser accessible
segment. link & bcfp AGREE on the access decision at 99.99% of shared positions.
99.57% mapping_code parity coexists because that metric is an INNER join
(`R/lnk_compare_mapping_code.R:229`) + count-weighted (`:276`) — it silently
drops bcfp's finer-only segments. Full evidence + reproduce + verdict in the
durable **`research/accessible_km_divergence.md` ("## RESOLVED")**. This is H2
from the earlier list; H1 (barrier-set composition) is moot — barriers are
identical and access agrees.

### Deliverable state
`/tmp/fresh_issue_access.md` drafted but **NOT filed** — and now needs a full
rewrite to the resolved framing: it is a **segmentation-granularity** finding
(link doesn't break at gradient-full boundaries where bcfp does), likely a
**link** issue not a fresh one, or an INTENTIONAL-divergence taxonomy entry.
No code committed; nothing wired in link. #221 decision unchanged + now firmly
grounded: ship salmon-group accessible_km (proven ≤0.27%), keep BT/ST deferred.

## Issue context

Issue #221 body: goal is per-WSG length roll-up emitting accessible_km +
spawning_km + rearing_km per (WSG, species), tunnel-free reference, coho-first,
abstract into a reusable function, extend to all bcfp species, then a separate
MORR vignette. Relates to #175 (parity methodology), #204 (persist shape). bcfp
ref: `smnorris/bcfishpass@2917790` (archived `wsg_linear_summary.sql`).
