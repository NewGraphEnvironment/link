# Task: Ingest CABD dams as parallel reporting dimension (#103)

link does not ingest dam locations from CABD. bcfp pulls them from `cabd.dams` + applies four edit CSVs (`cabd_exclusions`, `cabd_blkey_xref`, `cabd_passability_status_updates`, `cabd_additions` filtered to `feature_type='dams'`).

**Important framing:** bcfp's per-species access models AND habitat_linear models are **dam-blind** — verified across all 5 `model_access_*.sql` and 8 `load_habitat_linear_*.sql` files: zero references to `barriers_dams`, `barriers_anthropogenic`, or `barriers_pscis`. Dams in bcfp live as a **parallel reporting dimension** (the `bcfishpass.dams` table) that downstream consumers compose with habitat output for reports, WCRP tracking, and dam-impact analyses.

So this issue is **not a habitat-parity gap** — fixing it will not close any rollup deltas. It's a **reporting-data gap**: real-world habitat above Stave / Alouette / Strathcona / John Hart dams is materially blocked, but bcfp's habitat output is dam-blind and link's would be too. SRED-relevant report consumers will ask "what's above each dam?" and we need data to answer.

The per-species methodology question — "should default-bundle make some dam classes block which species?" — is **separate** and tracked at link#83. This issue is purely about getting the data in. link#83 is the consumer-side question.

## Phase 1: Detective work — confirm the data shape on the bcfp side ✓

- [x] Query `cabd.dams` over the tunnel — **2,594 raw rows, 2,478 as barrier (passability_status_code=1)**
- [x] Compare to `bcfishpass.dams` (post-edits) — **2,559 rows, 2,441 as barrier**. Net delta ≈ 35 (12 exclusions + snap-failures, partially offset by 4 US additions). Edit layer applies cleanly.
- [x] Verify named dams present in bcfp output — confirmed: John Hart, Ladore Falls, Strathcona (CAMB), Mica (CLRH), Hugh Keenleyside (LARL), Alouette, Coquitlam, Stave Falls, Ruskin (LFRA), Revelstoke (REVL), Jordan Diversion (SANJ), and others. Heights 1.6–243 m, mostly Hydroelectricity. All `passability_status_code=1` (treated as barriers in CABD).
- [x] Source path decision: **DB join via tunnel** (consistent with link#102's resolution; cypher / M4 / M1 all have tunnel access per rtj#82)
- [x] Verify clean separation — fresh's bundled `falls.csv` has no dam-named rows; CABD's `feature_type` column cleanly partitions waterfalls vs dams

## Phase 2: Source pull as a private helper in `lnk_pipeline_prepare.R`

Follows the precedent set by `prep_subsurfaceflow` in link 0.19.0 — inline SQL helper, NOT a new exported function. The batch-point-snap-to-FWA pattern exists in bcfp 5+ places (load_dams, load_falls, load_subsurfaceflow, crossings, etc.), but a fresh-side primitive is speculative until a second link consumer materializes. Promote to `frs_point_load_snapped()` later if pattern recurs.

- [ ] Add `.lnk_pipeline_prep_dams(conn, cfg, schema, loaded)` private helper in `R/lnk_pipeline_prepare.R`:
  - CTE 1: `from cabd.dams left outer join cabd_exclusions on cabd_id where exclusions.cabd_id is null`
  - CTE 2: lateral snap to `fwa_stream_networks_sp` within 65 m, two paths (with-blkey via xref, without-blkey via spatial nearest)
  - CTE 3: passability override via `coalesce(updates.passability_status_code, cabd.passability_status_code)`; carry `(dam_name_en, height_m, owner, dam_use, operating_status)`
  - UNION ALL with `cabd_additions where feature_type = 'dams'` (the 4 US placeholders)
- [ ] Output: `<schema>.dams` with column set `(dam_id, linear_feature_id, blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree, distance_to_stream, watershed_group_code, dam_name_en, height_m, owner, dam_use, operating_status, passability_status_code, geom)` — mirrors bcfp's table
- [ ] Helper docstring is explicit: **NOT used in habitat classification** — data lives in the parallel reporting layer

## Phase 3: Edit CSV ingestion via lnk_load_overrides

- [ ] Copy the four CSVs from `bcfishpass/data/cabd_*.csv` into `inst/extdata/configs/{bcfishpass,default}/overrides/`
- [ ] Add entries to both bundles' `config.yaml::files` block (same redistribution pattern as `user_barriers_definite_control.csv`)
- [ ] `lnk_load_overrides()` reads them; bundle-config-driven
- [ ] **Note: same 4 CSVs apply to both falls and dams** — they key on `cabd_id` which spans both tables. Falls are already complete (link#102 closed), so this ingestion exists primarily for dams. If a future re-extract of `falls.csv` from CABD is needed, the same edits apply for free.

## Phase 4: Pipeline wiring

- [ ] Wire `lnk_dams_load` into `lnk_pipeline_prepare.R::.lnk_pipeline_prep_load_aux()` (or a sibling helper) — gated on the bundle config declaring CABD dams ingestion
- [ ] Both `bcfishpass` and `default` bundles ingest — the data is methodology-agnostic at the data layer
- [ ] **Crucially: the dams data does NOT enter `streams_breaks` and does NOT enter the per-species barrier_overrides path**. This is the load-bearing design choice — habitat classification stays dam-blind, matching bcfp.

## Phase 5: Tests

- [ ] Unit test in `tests/testthat/test-lnk_dams_load.R` — SQL emission shape (mocked DB, similar pattern to `test-lnk_pipeline_break.R`)
- [ ] Confirm `devtools::test()` clean

## Phase 6: Verification — prove the data lands without affecting habitat

This is the most important phase. The verification gates closing the issue.

- [ ] Run a single WSG (LFRA — Stave / Alouette / Ruskin live there) post-fix
- [ ] Query `<schema>.dams` post-pipeline; confirm rowcount > 0
- [ ] Spot-check named dams appear with correct `(blue_line_key, downstream_route_measure)` against bcfp tunnel — Stave / Alouette / Ruskin / Coquitlam at minimum
- [ ] Run the 4-WSG regression (HARR / HORS / LFRA / BABL) — both bundle rollups must be **byte-identical to pre-fix baseline**. If they shift even by one row, the dams data is leaking into habitat classification — fix that before closing.

The byte-identical regression is the load-bearing test: dams data in, habitat output unchanged, parallel data layer ready for the consumer side.

## Phase 7: Research doc + ship

- [ ] Update `research/bcfishpass_comparison.md` § "Dams design — much smaller than expected" — note the data is now wired, link's habitat output remains dam-blind by design (matches bcfp), reporting consumers can compose dam awareness on top
- [ ] `/code-check` on staged diff
- [ ] Atomic commits with PWF checkboxes
- [ ] PR with `Fixes #103`
- [ ] `/planning-archive` after merge

## Out of scope

- **Per-species access gating on dams** — link#83 (methodology decision, separate issue). This issue lands the data; #83 decides who, when, why dams block which species
- **WCRP / dam-impact report composition** — downstream consumer work, not a link-package concern
- **CABD release version pin / refresh cadence** — open question; can be filed as a follow-up if it becomes operational pain

## Reference

- bcfp `model/01_access/sql/load_dams.sql` — implementation reference (full SQL in issue body)
- bcfp `model/01_access/sql/barriers_dams.sql`, `barriers_dams_hydro.sql`, `barriers_anthropogenic.sql` — downstream consumers we don't replicate (reporting-layer, not link's territory)
- `research/bcfishpass_comparison.md` § "Dams design — much smaller than expected" — bcfp's dam-blindness verification
- link#83 — per-species dam-class methodology (consumer side; depends on this issue)
- link#102 (closed) — sibling falls work; the 4 CABD edit CSVs were initially scoped here, but #102's detective work proved the falls side already complete. The CSVs come in via this issue instead.
