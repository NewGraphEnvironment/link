# Findings — Lake km: should 1450 connection lines count as lake rearing? (#317)

## Issue context

**If done:** `default`'s lake km count only lines that trace a lake's flow, so rearing km stop scaling with how many tributaries a lake has. **If never:** a big lake's km stay dominated by FWA connection lines. Adams Lake alone puts ADMS CH at +91 % rearing against bcfishpass.

## Problem (link@4580717, v0.61.0)

- #310 admits lake and reservoir lines to the `default` lake rear rule: `1000/1100/1200/1250/1300/1350/1400/1450/1475`.
- Edge type 1450 ("Construction line, connection") joins each tributary mouth to the main-flow line (1200) across the lake. It is not a flow path through the lake.
- Measured (`data-raw/logs/lake_connected_310/`):
  - Adams Lake (13,229 ha) holds 211.6 km of ADMS CH / CO rearing lines: 62.8 km of 1200 and 148.8 km of 1450.
  - On NATR, BT's lake km are 275.0 km of 1450 and 227.6 km of 1200.
  - Province-wide, lakes hold 54,402 km of 1200 and 44,528 km of 1450.
- Against bcfishpass, ADMS CH rearing goes from +14 % to +91 %, and CO from +3 % to +75 %. Without Adams Lake those would be about +22 % / +15 %.

The issue named 1450 among the lake edge types, so #310 kept it.

## Proposal

Decide whether lake km are "centrelines" (1200 / 1250 / 1300 / 1350 / 1475, the lines that trace flow) or "every line in the polygon".

If centrelines, drop 1400 / 1450 from the lake edge set in `R/lnk_rules_build.R`. That set is one list, used in both edge-type modes. Then rebuild the rules and re-measure with `data-raw/logs/lake_connected_310/run.R`.

1450 lines may still matter for connectivity: they join inlet clusters to the lake. Dropping them from `rearing` could disconnect inlet rearing from outlet spawning. Measure that before deciding.

Relates to #310.


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 1 measurement (2026-10-08)

See `data-raw/logs/lake_connection_317/README.md`. Key points:
- Connection km ≈ all edge 1450; 1400 contributes ≤ 1.4 km on these WSGs.
- bcfishpass reference rearing (`fresh.streams_vw_bcfp`) also contains 1450 lake lines: BT 65.9 km ADMS / 88.1 km NATR, SK 159.1 km ADMS. The rule therefore applies symmetrically, or SK parity reads −69 %.
- ADMS CH / CO remain +38.9 % / +28.7 %: bcfp has zero CH / CO lake rearing on ADMS; the residual is lake flow lines (#310's call that lakes rear CH / CO), not a line-type artifact.
