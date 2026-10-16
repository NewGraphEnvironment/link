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
- BT's lower percentiles on wet come from coverage, not the source (`data-raw/logs/discharge_wet_331/source_vs_coverage.*`): on the 2,999 BT locations both value, wet and fwapg agree (P10 0.075 / 0.076); the 320 only wet values in shared groups are main stems (median 185 m³/s, width 203 m); the 1,178 in nine Skeena groups fwapg does not cover sit lower (P10 0.019). 44 of 64 spawning-staged records are Skeena, and no held-out group is.
- Operator, on that: BT spawn lands on any-stage records, P10 0.043 (equal to rearing, as #302's 0.078 / 0.078 were). Asked as "0.044"; the rungs' two-significant-figure floor gives 0.043.
- `cw` unchanged on NATR under `default_tuned` (`cw_unchanged_natr.csv`): one prepare, `mad_m3s` re-joined from each source, 189,092 of 189,200 rows' `mad_m3s` differ, 0 habitat rows and 0 of 111,116 `linear_feature_id` × species rows differ.
- Build B died at 05:55Z: the DB volume filled (`habitat_score_331m_diskfull/`). Operator: drop stale scratch. Dropped 62 schemas (46 per-WSG `working_<wsg>`, `zz311_*`, Build B's partial `score331m_*` / `working_score331m_*`); 40 GB free, the 45 `score*` evidence schemas kept. Filed #343 (GR / RB / KO on wet).
- Build B (`score331m_`, base `default_tuned` at BT 0.043 / 0.043, fill on): 79.4 min at `5bd9b325`, scored `--floor=expected`. Held out, size-adjusted: wet `cw`-only rearing 3,109 km at 0.18, `mad`-only 364 km at 1.64; spawning 0.14 / 0.69; every reading "`mad` closer". fwapg at the same thresholds within a point or two (rearing 0.15 / 1.65). `mad` keeps −19.8 % BT rearing on wet, −21.3 % on fwapg (#305: −32 % at 0.078). `mad_null` in the `cw`-only rearing band: 6 km wet, 71 km fwapg.
- Full suite at `5bd9b325`: 2962 pass, 7 fail. Two were this branch's (prep_network SQL-shape tests passed a mock connection to the new preflight; fixed `deefda33`). Three need the :63333 tunnel (down; environmental). Two are the golden dams pin (8 → 7; `cabd.dams` 2,594 → 2,592 rows, an upstream refresh; the branch does not touch dams code). Left for a deliberate re-pin.
