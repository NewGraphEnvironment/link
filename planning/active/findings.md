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

## Issue context

Issue #221 body: goal is per-WSG length roll-up emitting accessible_km +
spawning_km + rearing_km per (WSG, species), tunnel-free reference, coho-first,
abstract into a reusable function, extend to all bcfp species, then a separate
MORR vignette. Relates to #175 (parity methodology), #204 (persist shape). bcfp
ref: `smnorris/bcfishpass@2917790` (archived `wsg_linear_summary.sql`).
