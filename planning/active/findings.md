# Findings — Main stems with no discharge drop out of mad habitat (#305)

## Issue context

**If done:** a group moved to the `mad` model keeps its river-polygon main stems, which are the most-used water in #300's comparison, and the `cw` against `mad` verdict then reads the MAD thresholds instead of a gap in the data. **If never:** every `mad` group silently loses those reaches. For BT rearing on #300's held-out groups that is 504 km holding 204 of 246 observation locations, at 2.7× the rate of habitat both models keep.

## Problem

`fwa_stream_networks_discharge` has no value on most edge type 1250 segments (main flow through double-line river polygons). Under `mad` a NULL `mad_m3s` fails every size test, so these reaches drop out of stream habitat. #300 measured this as `mad`'s largest loss of used water. Below the MAD minimum, `mad` drops only small water that is little used (BT 0.22 of the size-matched core rate). See `research/habitat_thresholds.md`, "`cw` against `mad`", and `data-raw/logs/habitat_score_300/model_reason.csv`.

## Options to weigh (not decided)

- **A `cw` fallback where `mad_m3s` is NULL.** This is a fresh rule change, which bcfishpass's mad branch does not do.
- **Fill discharge on main stems**, for example from the per-segment estimate in the `wet` package.
- **Count first.** Measure how much NULL discharge sits on edge type 1250 province-wide against the 123 covered WSGs, before choosing.

Then re-score with #300's harness (`--base=default_tuned`, `variants_300.csv`) to see whether the `cw`-only verdicts change.

Relates to #300, #286, #302.


## Pre-plan count (2026-10-06, read-only, local docker fwapg :5432)

Edge types of the stream network, joined to `whse_basemapping.fwa_stream_networks_discharge`
on `linear_feature_id`. "Covered" = a WSG with any non-NULL `mad_m3s` (123 WSGs).

| edge_type | km (covered WSGs) | km NULL | % NULL |
|---|---|---|---|
| 1000 | 834,020 | 79,176 | 9.5 |
| 1250 | 28,122 | 6,243 | 22.2 |
| 1100 | 9,469 | 6,224 | 65.7 |
| 1350 | 3,706 | 2,646 | 71.4 |
| 1050 | 32,339 | 2,451 | 7.6 |
| 1450 | 30,080 | 2,437 | 8.1 |

- The issue says "most" 1250 segments: true province-wide (34,074 of 55,953 km), because
  the uncovered WSGs count. Inside covered WSGs it is 22 %.
- 1250 by order (covered): order 4+ is 22.3 % NULL. Of it, 4,152 km is **absent rows** and
  2,025 km is rows with a NULL value. Orders 1–3 are tiny (65 km).
- Edge 1000 NULL is rows with a NULL value (~9 % in every order), not absent rows.
- 3,023 of the 6,243 km of NULL 1250 sit on a `blue_line_key` that has discharge somewhere.
  For non-1250 NULL it is 2,349 of 95,099 km: whole lines are uncovered.
- wet (`~/Projects/repo/wet`, v0.1.1): its per-segment province output exists locally for
  basins 100 and 400 only (`data/wb/962a9cc2c4/output/`). It is keyed on
  `watershed_feature_id` (monthly `discharge_m3s`), not on `linear_feature_id`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `round(double precision, integer) does not exist` | cast to `::numeric` before `round(, n)` |
| candidates query counted 2.4M "1250" lines | the builder returns every line (the fill coalesces over all); filter `edge_type = 1250` in the measurement |
| `operator does not exist: bigint %% integer` | a `%%` written for sprintf reached SQL as an argument, not a template: single `%` |
| `aggregate()` dropped the tributary tier from reach.csv | NA group value; set `gap_class` "" (code-check R1) |
| `frs_col_join()` with a subquery `from` types columns `text` | prepare adds `mad_m3s double precision` itself (plan review B1) |
