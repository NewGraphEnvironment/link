# Progress — Read discharge from wet in classify and the habitat export, and re-tune BT's MAD range on it (#331)

## Session 2026-10-15

- wet's `historical` discharge loaded into local fwapg (`wet_db_load(conn, wet_catalog())`): 15.5 min, 102,790,688 rows, 20 GB
- Plan-mode exploration — phases approved by user
- Created branch `331-read-discharge-from-wet-in-classify-and` off main
- Scaffolded PWF baseline from issue #331 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) returned 3 blockers, 8 gaps: `review-plan.md`, triage in `findings.md`. Operator, on the two forks it raised: only `default_tuned` reads wet; wet's 0 reads as no value.
- Phase 1: `discharge_source` bundle setting (`fwapg` | `wet`), one relation (`.lnk_discharge_rel()`), logged per WSG, read by prepare, validator (mismatch warns), export (manifest names the source per WSG) and harness. fwapg SQL byte-identical to main for every argument shape. Tests: 969 pass / 0 fail across discharge, validate, export, log, config.
- Phase 2: the guard drops `set` cells the base carries and still stops on a rung whose own cell equals the base; per-variant `discharge_source` / `discharge_fill` written explicitly into each bundle. Scripted checks: `variants_302.csv` regenerates 18 bundles at HEAD; a no-op rung stops ("variant noop equals default: rear_mad_min is already 0.021"); a base row with a source is refused; a variant's `wet` / `TRUE` reach `lnk_config()`.
- Fill reach on wet (`data-raw/logs/discharge_wet_331/fill_reach_1250.csv`): edge 1250 km with no value, BT score WSGs 506 (fwapg) → 5 (wet); fresh_default 5,967 → 29.
