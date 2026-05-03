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

## Phase 2: Consume bcfp's pre-built `bcfishpass.dams` via tunnel

Re-evaluating the source-pull design: bcfp's tunnel DB already has `bcfishpass.dams` post-CABD-pull and post-4-edit-CSVs (refreshed weekly via db_newgraph cron). Replicating bcfp's `load_dams.sql` locally is unnecessary work for the SRED-reporting use case — the data is the same either way. Trade-off: bcfp owns refresh cadence (weekly is fine for reporting; if we ever need bit-identical control, escalate to the load_dams.sql replication path).

Consequences of consume-path:

- No bundle redistribution of the 4 CABD edit CSVs (they're applied bcfp-side, we're downstream)
- No `cabd.dams` source-pull SQL in link
- `lnk_pipeline_prepare` accepts an optional `conn_tunnel` arg; helper short-circuits when NULL

Tasks:

- [x] Add optional `conn_tunnel = NULL` arg to `lnk_pipeline_prepare(conn, aoi, cfg, loaded, schema, ...)`
- [x] Add `.lnk_pipeline_prep_dams(conn, conn_tunnel, aoi, schema, loaded)` private helper in `R/lnk_pipeline_prepare.R`. Implementation pivoted to **replicate `load_dams.sql` against `cabd.dams`** rather than consume bcfp's processed `bcfishpass.dams` (architectural parallelism: link sibling-of-bcfp under CABD, not downstream-of-bcfp).
- [x] Output: `<schema>.dams` mirroring bcfp's table column set
- [x] Helper docstring is explicit: **NOT used in habitat classification** — data lives in the parallel reporting layer
- [x] Wire `conn_tunnel` through `compare_bcfishpass_wsg` — pass it down to `lnk_pipeline_prepare`

## Phase 3: Edit CSV ingestion via lnk_load_overrides

- [x] Copy the four CSVs from `bcfishpass/data/cabd_*.csv` into `inst/extdata/configs/{bcfishpass,default}/overrides/`
- [x] Add entries to both bundles' `config.yaml::files` block (same redistribution pattern as `user_barriers_definite_control.csv`)
- [x] `lnk_load_overrides()` reads them; bundle-config-driven

## Phase 4: Pipeline wiring

- [x] Wire `.lnk_pipeline_prep_dams` into `lnk_pipeline_prepare.R` as the last phase
- [x] Both `bcfishpass` and `default` bundles ingest — the data is methodology-agnostic at the data layer
- [x] **Crucially: the dams data does NOT enter `streams_breaks` and does NOT enter the per-species barrier_overrides path**. Verified via grep + dams-ON/OFF byte-identical regression.

## Phase 5: Tests

- [x] Unit tests in `tests/testthat/test-lnk_pipeline_prepare.R` — `prep_dams` short-circuit on NULL conn_tunnel + load_dams.sql SQL shape (mocked DBI)
- [x] `devtools::test(filter = "lnk_pipeline_prepare")` clean — 78 PASS, 0 FAIL

## Phase 6: Verification — prove the data lands without affecting habitat

- [x] LFRA preflight — `<schema>.dams` rowcount = 65 (matches bcfp 65), 59 barriers (matches), 15 named (matches)
- [x] Stave Falls / Alouette / Ruskin / Coquitlam spot-checks — all 15 named LFRA dams match bcfp tunnel byte-for-byte on `(blue_line_key, downstream_route_measure)` within fp precision (Coquitlam DRM differs by ~0.2mm — lateral-snap fp, not content drift)
- [x] HARR dams-ON / dams-OFF byte-identical rollup — same HEAD, only `conn_tunnel` differs, byte-identical to fp precision. Confirms parallel-data invariant.
- [x] Architectural isolation proven via `grep -rn "\.dams\b\|\.cabd_"` — only match is a docstring example in `lnk_source.R`. No break/classify/connect phase reads dam-side tables.

The 4-WSG vs cached-baseline regression initially looked like a fail but was contaminated by #96/#97/31b9 drift relative to a May 1 06:48 cache; HARR dams-ON/OFF on current HEAD is the clean #103-only test.

## Phase 7: Research doc + ship

- [x] Update `research/bcfishpass_comparison.md` § "Dams design" — replaced the early "fresh-crossings path" framing with the actual landed implementation
- [x] NEWS.md 0.24.0 entry
- [x] DESCRIPTION version bump 0.23.0 → 0.24.0
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
