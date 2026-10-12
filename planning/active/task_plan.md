# Task: Build DUNC into fresh_default (config default) for the floodplains Columbia region (#328)

Build watershed group **DUNC** (Duncan Lake, Lardeau River) into `fresh_default` under config `default`, so the floodplains Columbia region (KOTL, LARL, SLOC, DUNC) reads one schema (floodplains#104, #125).

**Decided (operator, 2026-10-12): DUNC alone at HEAD.** KOTL/LARL/SLOC stay as built 2026-08-27 (fresh v0.33.0; KOTL/SLOC link `322389a`, config_hash `3cfde7…`; LARL `8c8c29b` dirty, `44e452…`; their bt_ff04 items are published from that build). DUNC is link v0.63.1 / fresh v0.39.0, so its habitat flags can differ by #310, #311 and fresh 0.33 → 0.39 (fresh#237, #240); #282/#307 changed only MAD columns, inert for a `cw` group. The log rows record the difference. A run, not a code change: no version bump.

## Run decisions

- **config:** `default` (not `bcfishpass`, the parity build writing `fresh`)
- **persist schema:** `fresh_default` via `LNK_SCHEMA=fresh_default` (`default`'s YAML schema is `fresh`)
- **closure:** DUNC only. `lnk_wsg_downstream_check(DUNC)` passes: all six downstream dams are in KOTL, persisted. DUNC is a headwater group.
- **species:** BT, WCT, RB
- **flags:** `mapping_code = TRUE`, `dams` default, `cleanup_working = FALSE`; `LNK_GUARD_DOWNSTREAM=error`; `LNK_RUN_LABEL=dunc_default_328`; `LNK_LOAD=loadall` from a clean committed tree

## Phase 1: Run DUNC

- [x] Pre-flight: no active backends on fwapg, no `working_dunc` schema, tree clean at the baseline commit, installed fresh = 0.39.0 (`e247ca1`)
- [x] Run `wsg_run_one.R DUNC default` with the env above, in the background, output teed to the scratchpad, start time from `date -u`
- [x] Confirm the exit from DB state, not from the wrapper (Phase 2)

## Phase 2: Verify against "Done when"

- [x] `fresh_default.streams` has DUNC; order >= 2 km matches `fresh.streams` DUNC (3,493 km) to the km (segment count differs by design)
- [x] `streams_habitat_bt` / `_wct` / `_rb` row counts equal `streams` for DUNC, on the full PK
- [x] `streams_access` and `streams_mapping_code` hold DUNC
- [x] `fresh_default.log` row for DUNC carries config_name, config_hash, link_sha = build commit `8215d2d` with link_dirty f, fresh_sha, fwapg_sha, schema_persist, run_label, date_end (`run_uid` NULL by design: a direct run has no dispatch)
- [x] Context, not parity (informational): DUNC BT/WCT accessible / spawning / rearing km against `fresh.streams_vw_bcfp` (`IN (1,2)`, lake connection lines out on both sides)
- [x] `data-raw/logs/dunc_default_328/`: run log, verification output with environment stamp, README

## Phase 3: Record

- [x] Edit the #328 body: outcome, DUNC's vintage beside the other three, and the answer to "Also observed"
- [x] Short CLAUDE.md status entry: `fresh_default` is mixed-vintage; read the log per group
- [x] Final report notes that floodplains `columbia.yml`'s `network_source` header (link 0.45.1) no longer holds for DUNC

## Validation

- [x] DB checks in Phase 2 pass
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
