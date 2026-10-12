## Outcome

Built watershed group DUNC (Duncan Lake, Lardeau River) into `fresh_default` under config `default`, so the floodplains Columbia region (KOTL, LARL, SLOC, DUNC) reads one schema. The operator chose a HEAD build (link 0.63.1, fresh 0.39.0) over matching KOTL / LARL / SLOC's August build (link 0.45.1, fresh 0.33.0) or rebuilding all four, because those three groups' published bt_ff04 items come from the August build. So DUNC's flags can differ from its neighbours' by #310, #311 and fresh 0.33 → 0.39; #282 and #307 changed only MAD columns, inert for a `cw` group. The run was a single `wsg_run_one.R` call with `LNK_SCHEMA=fresh_default`. The issue's "Also observed" (DUNC missing from `fresh.streams_access` / `fresh.log`) is stale vintage: its `fresh` rows come from the 2026-05-13 trifecta run, before v0.40.0 and #127.

What was learned:
- **`fresh_default` is mixed-vintage.** Only 5 groups have log rows, and 49 of 56 have pre-#223 segmentation.
- **`fwapg_sha` is the fwapg checkout's HEAD, not an FWA version.** `log_input` fingerprints are the real comparison.
- **Freshly persisted rows need `ANALYZE`** before a full-PK join.
- **Review was the measurement here.** Three code-check rounds found 9 documentation defects, every one a claim inherited from prose (the issue body, plan notes, PR titles) and not read back from the artifact that owns it. That included the issue's own build date for DUNC.

## Measurement

- 2.2 min build (15:31:35–15:33:45 UTC).
- 63,067 segments (against 26,827 in `fresh`, pre-#223). Order ≥ 2 is 3,493.0 km, the same as raw FWA.
- `verify.R`: 19 / 19 checks pass.
- Against the bcfishpass reference view, context only: BT +2.0 / +0.9 / +2.2 % (accessible / spawning / rearing), WCT +1.3 / +0.4 / +17.0 %.
- FWA fingerprints are identical to KOTL's for the six tables both log rows record.

## Evidence

`data-raw/logs/dunc_default_328/` (run log, `verify.R` → `verify.txt`, README); `review-*.md` in this directory.

Closed by: PR for #328
