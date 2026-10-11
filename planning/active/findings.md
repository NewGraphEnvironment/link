# Findings — PCEA BT rearing segment diff (#324)

## Issue context

See `gh issue view 324`. PCEA BT rearing link 1,655.8 / bcfp 1,625.5 km (+1.87 %) after #319; connection lines 367.7 / 375.9 (−8.2 km); everything else +30.3 km. FINA, PARS, LKEL match on connection km.

## Plan-mode probes (2026-10-09) (read-only, local fwapg :5432)

- **Segmentation differs, so an exact `(blk, drm)` join is wrong.** PCEA: link `fresh.streams`
  106,079 segments vs `fresh.streams_vw_bcfp` 37,957, same 14,315.7 km. The diff must join on
  **measure-interval overlap** per `blue_line_key` (`l.dm < b.um AND b.dm < l.um`, overlap =
  `least(um) − greatest(dm)`). Coverage reconciles exactly (overlap sums to 14,315.7 km).
- **The net +22.1 km is two gross flows:** link-only 54.2 km, bcfp-only 32.1 km; 1,969.3 km agree.
- First cut of the buckets (bcfp segment's gradient / width, threshold 0.1049):
  - link-only, edge 1000, bcfp segment gradient > 0.1049: 35.9 km on 272 blks — looks like
    gradient averaged over bcfp's longer segments vs link's finer ones (hypothesis, unproven).
  - link-only, edge 1000, in range: 15.8 km / 52 blks.
  - bcfp-only, edge 1000, in range: 23.1 km / 255 blks (diffuse; cluster/connectivity?).
  - bcfp-only, edge 1450: 8.4 km, 5.5 km of it on one blk with `access_bt = 2`.


## PCEA BT rearing, attributed (2026-10-11)

Pieces from `data-raw/habitat_diff_segments.R`, attributed by
`data-raw/logs/rearing_diff_324/mechanism.R` (first match wins). km, link-only / bcfp-only:

| mechanism | link-only | bcfp-only | net |
|---|---|---|---|
| rear gradient: the two segments' gradients sit either side of 0.1049 | 35.93 | 14.21 | +21.72 |
| connectivity, blk also carries a gradient split | 15.11 | 8.07 | +7.04 |
| connectivity, other | 1.35 | 0.19 | +1.16 |
| bcfp's order-1 / parent ≥ 5 width exception | 0 | 9.59 | −9.59 |
| link classify-time access TRUE, streams_access 0 | 1.80 | 0 | +1.80 |
| total | 54.18 | 32.06 | +22.12 |

- **Segmentation:** link's PCEA breaks are a superset of bcfp's (24,392 of 24,393 bcfp breaks
  present within 1 m). The 68,101 extra link breaks are all gradient positions
  (29,959 at 25/30 % — above BT's frontier, so habitat-inert —, 19,888 at 20 %, 18,254 at
  15 %), plus 15 falls and 2 crossings.
- **Why:** `.lnk_pipeline_prep_minimal()` builds per-model break sets for every configured
  species, not filtered by WSG presence (deliberate; comment at `R/lnk_pipeline_prepare.R:541`),
  and feeds raw positions (#223). bcfishpass builds a model's barriers only where its species
  are present (`model_access_ch_cm_co_pk_sk.sql:146-150`, `model_access_bt.sql:148-152` @620dbe4)
  and deletes non-minimal barriers before `break_streams()` (`01_model_access_natural.sh`).
  PCEA is BT-only, so bcfp does not break at the 15 / 20 % positions at all.
- **Cascade, row level:** blk 359497146: link breaks at 3,050.8 m (a 15 % position); its
  2,771–3,051 piece is 4.3 % and spawns (≤ 0.0549), bcfp's 2,771–3,329 segment is 7.2 % and
  does not; link then rears 2.75 km on the blk (2.47 km downstream of that piece) through the cluster rule, bcfp rears nothing on
  the blk.
- **Spawning** disagrees too (link 925.7 / bcfp 918.5): 9.3 km link-only, 7.3 of it on the
  spawn-gradient split; 2.05 km bcfp-only, all of it on the split.
- **Connection-line gap (−8.2 km) is bcfp's width exception:** 8.38 km on two 1450 lines
  (blks 359386479, 359555604) in a lake on an order-9 stem, order 1, width < 1.5 m. The
  bcfishpass bundle sets `rear_stream_order_bypass = no` for BT (`dimensions.csv`); fresh#158
  is closed and `lnk_rules_build()` supports the bypass, so the taxonomy's
  `INTENTIONAL_FRESH_DEFERRED` status for `hors-class-stream-order-bypass` is stale.
- **Access residual:** 3 segments (1.8 km) whose downstream end is a subsurface-flow (1410) or
  falls barrier: link's classify-time `accessible` is TRUE, `streams_access` and bcfp say 0.
  Cause not established.

## Controls (Phase 3, 2026-10-11)

Net km by mechanism (link − bcfp), BT rearing, bcfishpass config:

| WSG | rear gradient | connectivity | width exception | access | net | gross (link-only + bcfp-only) |
|---|---|---|---|---|---|---|
| PCEA | +21.72 | +8.20 | −9.59 | +1.80 | +22.12 | 86.2 |
| FINA | +12.21 | −25.32 | 0 | +0.23 | −12.88 | 73.7 |
| PARS | +19.28 | −9.27 | −24.78 | +0.94 | −13.83 | 112.6 |
| LKEL | +0.08 | +1.34 | 0 | +0.24 | +1.66 | 1.7 |

- Not PCEA-specific: the same two-way gradient split and its connectivity cascade run in FINA
  and PARS, where the connectivity side wins and the net is negative. PCEA is where the
  gradient side wins.
- FINA blk 359421737 shows the cutting direction: link carves 1,036–1,267 m (13.6 %) out of
  bcfp's 393–1,267 m segment (10.2 %, rears), which splits the cluster; 5.4 km of rearing
  above loses its connection to the 0.39 km of spawning at the mouth.
- LKEL (CH / CO / ST present) nearly agrees, though link still has 1,820 extra 15 / 20 %
  breaks there: bcfp breaks at the minimal salmon / ST positions, and the extras sit mostly
  in water BT does not rear in. Consistent with the presence filter, not a clean test of it.
- Break census (`*_breaks.csv`): bcfp breaks missing from link within 1 m: PCEA 1 / 24,393,
  FINA 14 / 20,392, PARS 34 / 30,733, LKEL 5 / 2,554.
- PARS's −24.78 km width exception is on 54 blks, not connection lines (PARS connection km
  agree, 9.8 / 9.8).

## Errors Encountered

| Error | Resolution |
|-------|------------|
