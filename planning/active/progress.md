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

### Next

Phase 2 — implement `lnk_dams_load(conn, schema, ...)` mirroring bcfp's `load_dams.sql`. Output `<schema>.dams` with `(dam_name_en, height_m, owner, dam_use, operating_status, passability_status_code, geom)` column set. Critical: must NOT enter `streams_breaks` or `barrier_overrides` — verified via byte-identical regression in Phase 6.
