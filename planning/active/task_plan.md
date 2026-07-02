# Task: Per-WSG habitat/access km roll-up + parity compare (accessible_km) (#221)

We report per-segment habitat parity today but not per-WSG km totals. link already
rolls up + compares `spawning_km` / `rearing_km` per `(WSG, species)` at ~99.66%
median parity, but **`accessible_km` is never rolled up or compared** — link
persists `streams_access.access_<sp>` yet never sums it to km. Goal: a clean,
abstracted per-WSG length roll-up emitting `accessible_km` + `spawning_km` +
`rearing_km` per `(WSG, species)`, compared against a tunnel-free bcfp reference
(`fresh.streams_vw_bcfp`). Prove coho first, then generalize. WSG-level first;
per-crossing roll-up is a later phase. Morice vignette is separate/later.

## Phase 1 — Coho `accessible_km` proof (reproducible, no new abstraction)
- [x] Add `data-raw/accessible_km_proof_co.R` that runs the validated two-sided
  query for every WSG present in both `fresh.streams_access` and
  `fresh.streams_vw_bcfp` and asserts `abs(pct_diff) <= 5` per WSG (allowlisting
  documented divergences), printing the table. Uses `lnk_db_conn()` local-docker
  args. Run: 19/20 WSGs within ±5%; SETN flagged as known bcfp-side stale.
- [x] Record predicate correction (`= ''` not `= array[]::text[]`) + per-species-
  vs-salmon-group reconciliation + SETN known-divergence in `findings.md`.

## Phase 2 — Abstract the roll-up into one reusable, predicate-driven function
- [x] Introduce a single roll-up primitive emitting `accessible_km` +
  `spawning_km` + `rearing_km` per `(WSG, species)`, data-driven over species.
  Shipped `lnk_rollup_wsg` (mirrors `frs_aggregate`'s `metrics`/`where` shape,
  species-agnostic via generic `access`/`spawning`/`rearing` aliases). Live-
  verified MORR coho `accessible_km` = 3330.25 (matches Phase-1 proof). 27 unit
  tests. `accessible_km` sources `streams_access.access_<sp> IN (1,2)`, NOT the
  divergent `streams_habitat_<sp>.accessible` bool (MORR 3330 vs 3424 km).
- [x] Fold `.lnk_compare_rollup_link` habitat km sums into that single
  path. `.lnk_compare_rollup_link`'s `km` block now delegates to
  `lnk_rollup_wsg` via a 5-metric `metrics` vector (COALESCE→0 to
  preserve the historical CASE-WHEN measured-zero semantics), renaming
  `species`→`species_code` to keep the `list(km, lake_ha, wetland_ha)`
  contract. `lnk_rollup_wsg`'s `streams_access` join changed
  `JOIN`→`LEFT JOIN` so habitat length is never dropped when access is
  unbuilt. Byte-identical vs the old form on MORR (BT/CO, all 5
  metrics). lake_ha / wetland_ha (DISTINCT-waterbody polygon joins)
  stay as-is — different shape, not a per-segment length sum.
- [x] Emit `accessible_km` as an 8th habitat_type in
  `.lnk_compare_wsg_assemble_rollup`; update row-count assertions in
  `tests/testthat/test-lnk_compare_wsg.R`. Added `accessible_km` to
  `.lnk_compare_rollup_link`'s `km_metrics` (COALESCE'd `access IN (1,2)`
  via lnk_rollup_wsg's LEFT-joined `access` alias); appended `accessible`
  (km) to habitat_types/units/col_suffix/link_sources in
  `.lnk_compare_wsg_assemble_rollup`. `ref_value`/`diff_pct` are NA for
  `accessible` until the tunnel-free ref lands (4/4). Row-count
  assertions 7→8 / 14→16 updated in both test-lnk_compare_wsg.R and
  test-lnk_compare_rollup.R (7→8). Live MORR coho accessible_km 3330.25
  (= Phase-1 proof). 108 tests across the 3 files pass; docs regenerated.
- [ ] Keep habitat ref tunnel-based; add tunnel-free `accessible_km` ref path. Do
  NOT force-unify the two reference sources this phase.

## Phase 3 — All bcfp-modelled species into the parity compare
- [ ] Extend `accessible_km` to salmon (`barriers_ch_cm_co_pk_sk_dnstr`), BT
  (`barriers_bt_dnstr`), ST (`barriers_st_dnstr`) — data-driven link `access_<sp>`
  ↔ bcfp `barriers_<group>_dnstr` mapping.
- [ ] Wire `accessible_km` into the parity compare + `lnk_parity_annotate()`.

## Phase 4 — Morice (MORR) vignette (separate, later)
- [ ] New MORR vignette reporting these totals; leave the existing vignette in
  place. Gated on phases 1–3. Likely its own follow-up issue, not this PR.

## Validation
- [ ] `Rscript data-raw/accessible_km_proof_co.R` prints per-WSG
  link_km/ref_km/pct_diff, exits non-zero if any `|pct_diff| > 5` (confirmed live:
  MORR 0.09%, BULK 0.27%).
- [ ] `devtools::test()` green incl. updated `test-lnk_compare_wsg.R`;
  `lintr::lint_package()` clean; `devtools::document()` re-run.
- [ ] `/code-check` clean on each commit; PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion; SRED ref in PR body only.

## Out of scope
- Per-crossing roll-up (`lnk_aggregate()`).
- `accessible_a` / `accessible_b` anthropogenic sub-variants.
- Observed (`obsrvd_`) habitat variant.
- Full tunnel-free rebuild of the habitat km reference.
