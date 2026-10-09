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


## Errors Encountered

| Error | Resolution |
|-------|------------|
