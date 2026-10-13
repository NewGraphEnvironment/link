# #328: DUNC built into `fresh_default` (config `default`)

Local docker fwapg (:5432), 2026-10-12 15:31:35–15:33:45 UTC (2.2 min). One group, persisted. The floodplains Columbia region (KOTL, LARL, SLOC, DUNC) reads one schema, and DUNC was only in `fresh`.

## Run

```bash
LNK_LOAD=loadall LNK_SCHEMA=fresh_default LNK_RUN_LABEL=dunc_default_328 \
  LNK_GUARD_DOWNSTREAM=error Rscript data-raw/wsg_run_one.R DUNC default
```

- **config / schema:** `default`, persisted to `fresh_default`. `default`'s YAML schema is `fresh`, so `LNK_SCHEMA` is required.
- **closure:** DUNC only. The downstream guard passed: all six blocking dams below DUNC are in KOTL, already persisted. DUNC is a headwater group, so nothing needs recomputing.
- **species:** BT, WCT, RB.
- **provenance:** link 0.63.1 `8215d2d` (clean), fresh 0.39.0 `e247ca1`, `config_hash` `sha256:7e9dffa4…`, run_id `m1-20261012T153135.985-b33d3a`. `run_uid` is NULL. It is set per dispatch by `study_area_run.sh`, and this was a direct single-WSG run.
- `working_dunc` is kept (`cleanup_working = FALSE`, the script default), like the other groups' working schemas.

## Files

- `run.log`: the driver's output.
- `verify.R` → `verify.txt`: read-only checks against the issue's "Done when", with an environment stamp. Re-run with `Rscript data-raw/logs/dunc_default_328/verify.R`. Its first run stalled on a full-PK join over the new rows until `ANALYZE` on the six touched tables (stale planner statistics; see CLAUDE.md #319).

## Results

All 19 checks pass.
- **Coverage.** `fresh_default.streams` holds 63,067 DUNC segments. Each of `streams_habitat_bt` / `_wct` / `_rb`, `streams_access` and `streams_mapping_code` has one row per segment, on the full PK.
- **Network.** Order ≥ 2 is 3,493.0 km, the same as raw FWA and `fresh.streams`. `fresh` has 26,827 segments, from its pre-#223 build in the 2026-05-13 trifecta provincial run (link 0.36.0, `data-raw/logs/202605132248_trifecta_provincial_m1.txt`).
- **Log row.** `fresh_default.log` records config `default`, the config hash, link / fresh versions and SHAs, `fwapg_sha`, `schema_persist` and `date_end`.
- **FWA version.** `fwapg_sha` is the HEAD of the local fwapg checkout, not an FWA data version. It reads `f9718cb` here against `e6e1eb0` for KOTL / LARL / SLOC, on unrelated fwapg commits. In `log_input`, the six FWA tables logged for both KOTL and DUNC carry identical row counts and byte sizes (e.g. `fwa_stream_networks_sp` 4,907,804 rows, 10,287,677,440 bytes). DUNC also logs `fwa_obstructions_sp` and `fwa_stream_networks_discharge`, which KOTL's row lacks. Non-FWA inputs did move: `fresh.modelled_stream_crossings` 524,562 rows against 529,244, `bcfishobs.observations` 373,050 against 372,690.
- **Nothing written to `fresh`.** It still has no DUNC log row.

**Context, not parity.** `default` differs from bcfishpass by design. Against `fresh.streams_vw_bcfp` (`IN (1,2)`, lake connection lines out on both sides):

| species | accessible | spawning | rearing |
|---|---|---|---|
| BT | +2.0 % | +0.9 % | +2.2 % |
| WCT | +1.3 % | +0.4 % | +17.0 % |

## Vintage: DUNC is not the same build as its neighbours

KOTL, LARL and SLOC in `fresh_default` were built 2026-08-27. KOTL and SLOC came from link `322389a` with fresh v0.33.0, config_hash `3cfde7…`. LARL came from a dirty tree, hash `44e452…`. DUNC is link 0.63.1 with fresh v0.39.0, so its habitat flags can differ from theirs: the rules that changed since August are #310 (lake and wetland rearing connected to spawning) and #311 (the wetland floor), plus fresh 0.33 → 0.39's area-only buckets (fresh#240) and its floor on the wetland rule (fresh#237). #282 and #307 changed only MAD columns, which do nothing for DUNC, a `cw` group. The operator chose this on 2026-10-12, over matching the August build or rebuilding all four, because the three groups' published bt_ff04 items come from that build.

DUNC's own access is also mixed-vintage. It reads the persisted barriers and overrides of the groups downstream (KOTL, LARL), which were built at link 0.45.1. The guard checks that blocking dams are persisted, not how old the build is.

## For floodplains

`config/regions/columbia.yml` in floodplains cites link 0.45.1 as the network source for the region. That holds for KOTL, LARL and SLOC, not for DUNC (link 0.63.1).
