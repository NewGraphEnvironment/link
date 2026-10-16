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
- Phase 6 built in a worktree while Phase 3 ran (each producer loads the package at start), then fast-forwarded: `lnk_preflight_discharge()`, prepare stops with the load command, `discharge_wet_load.R`, dispatcher gate and cypher load, `log_input.table_comment` and wet's table in a wet run's inputs, `discharge.wet_load` in the export manifest (matched by build, ignoring wet's `; subset` suffix). 646 + 173 tests pass. Filed NewGraphEnvironment/wet#88 (per-part load record).
- Phase 3 ran: width conversion barely moves; BT percentiles on wet in findings. The validator's source warning fired on the five logged `fresh_default` groups, as designed.

## Session 2026-10-15, evening

- Build A (`score331_`, base `default`, 17 groups, 12 BT rungs): 199.5 min, exit 0. Scored with `--floor=expected`, #302's floor of record (a first pass used the script's default `found`; only the wet spawning reading differed).
- Held-out verdicts: rearing on wet P10 0.043, P10 → P05 refused (21 found / 241 expected, ratio 0.09); fwapg controls 0.083 / 0.083. Spawning on wet was scored on spawn-staged records, and the held-out core holds 3, so every step is underpowered (rule: P05 0.0063, unscored). Re-scored on any-stage records (`data-raw/logs/habitat_score_331_spawn_any/`, same build): P10 → P05 refused (4 found / 195 expected, ratio 0.02).
- Operator: BT spawn lands 0.012 (any-stage, a stated departure from the stage rule); Build B launches as stated.
- Anchor bands, what `cw` keeps that `mad` drops (BT rearing, held out): fwapg 4,597 km holding 243 locations at 0.39 of the core; wet 2,815 km holding 19 at 0.05.
