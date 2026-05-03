# Progress — Ingest CABD dams as parallel reporting dimension (#103)

## Session 2026-05-02

- Created branch `103-ingest-cabd-dams` off main
- Scaffolded PWF baseline from issue body — 7 phases (detective → source pull → edit CSVs → pipeline wiring → tests → byte-identical verification → research doc + ship)
- Sibling work today: link#102 (CABD waterfalls) closed as not-a-bug after detective work showed fresh's static falls.csv was already complete; link#104 (CABD download path) closed as obsolete with #102. The same 4 CABD edit CSVs that #102 was going to redistribute now come in via this issue.
### Phase 1 detective findings

| Source | Total rows | Barrier rows | Notes |
|---|---:|---:|---|
| `cabd.dams` (raw upstream) | 2,594 | 2,478 | most dams are flagged as barriers |
| `bcfishpass.dams` (post-edits) | 2,559 | 2,441 | edit layer net delta ≈ 35 (drops + 4 additions) |

**Famous named dams confirmed in bcfp output** (all `passability_status_code=1`, heights 1.6–243 m):

- CAMB: John Hart (33.5 m), Ladore Falls (37.5 m), Strathcona (53.3 m)
- CLRH: Mica (243 m)
- LARL: Hugh Keenleyside (52 m)
- LFRA: Stave Falls (26 m), Ruskin (59.4 m), Alouette (22.5 m), Coquitlam (30.5 m)
- REVL: Revelstoke (175 m)
- SANJ: Jordan Diversion (40 m)
- Plus Seymour, Campbell Mountain, Campbell Lake, Upper Stave variants

**Top 10 WSGs by dam count:** OKAN (233), SAJR (109), VICT (105), STHM (95), MFRA (74), THOM (68), NICL (65), LFRA (65), LNIC (65), SIML (60). Heavy in southern interior + south coast.

**Decision:** source via tunnel-DB join (consistent with link#102 resolution). cypher / M4 / M1 all have tunnel access per rtj#82.

### Phase 2 → 7 implementation

- Pivoted Phase 2 design: replicate `load_dams.sql` against `cabd.dams` source rather than consume bcfp's processed `bcfishpass.dams`. Architectural parallelism — link sibling-of-bcfp under CABD, not downstream of bcfp.
- `.lnk_pipeline_prep_dams(conn, conn_tunnel, aoi, schema, loaded)` runs as final phase in `lnk_pipeline_prepare`. NULL `conn_tunnel` short-circuits to drop. Wired through `compare_bcfishpass_wsg` (default behavior unchanged).
- 4 CABD edit CSVs redistributed to both bundles' `overrides/`, declared in `config.yaml::files`, ingested via `lnk_load_overrides()`.
- Tests: 2 new tests in `test-lnk_pipeline_prepare.R` (NULL short-circuit + load_dams.sql SQL shape), 78 PASS / 0 FAIL.

### Verification (Phase 6) — clean #103-only test

- **LFRA preflight** (`logs/20260502_05_preflight_lfra_dams.txt`): 65 dams / 59 barriers / 15 named in `working_lfra.dams`, all 15 named (Stave Falls, Alouette, Ruskin, Coquitlam, Northwest Stave + Upper Stave variants, Cariboo, Sam Hill, Sparrow, Sharpe, Lamont, Cannell, Alam) match `bcfishpass.dams` on tunnel byte-for-byte within fp precision.
- **HARR dams-ON / dams-OFF** (`logs/20260502_07_dams_isolation_harr.txt`): same HEAD, same code, only `conn_tunnel` differs → rollup byte-identical to fp precision. Proves architectural isolation: prep_dams cannot affect habitat classification.
- The 4-WSG regression vs cached baseline (`logs/20260502_06_regress_4wsg_dams_post.txt`) surfaced -1km drift across many rows but the cache was from May 1 06:48 — pre-#96/#97/31b9. Drift was unrelated to #103. The HARR ON/OFF test is the clean replacement.

### Phase 7 docs + version

- `research/bcfishpass_comparison.md` § "Dams design — parallel reporting dimension (link#103)" replaces the early fresh-crossings framing with the landed implementation + verification + out-of-scope list.
- `NEWS.md` 0.24.0 entry; `DESCRIPTION` 0.23.0 → 0.24.0.

### Next

`/code-check` on staged diff → atomic commits with PWF checkboxes → PR with `Fixes #103`.
