# Task Plan: ST/WCT classification gap (#31)

## Goal
Identify and close the ST -22% spawning / -25% rearing gap on BABL, WCT -4% on ELKR.

## Status
- Per-model non-minimal: tested, no effect on ST/WCT
- label_block with crossings: tested, -52% regression (crossings don't block in bcfishpass)
- Stream order exception: tested, closed 3 points on ST rearing (-28% → -25%)
- Root cause NOT confirmed. Hypotheses tested and eliminated. Need segment-level comparison.

## Phase 1: Segment-level ST comparison on BABL
- [ ] Query tunnel: all ST spawning segments in BABL with key attributes (gradient, channel_width, edge_type, waterbody_type, stream_order)
- [ ] Query local: same for our classification
- [ ] Diff: which segments does bcfishpass classify as ST spawning that we don't? And vice versa.
- [ ] For mismatches: check gradient, channel_width, edge_type, waterbody_type on each — find the predicate that differs
- [ ] Same for rearing

## Phase 2: Fix based on evidence
- [ ] TBD after Phase 1 findings

## Tested and eliminated
- Per-model non-minimal barrier removal (no effect)
- label_block with crossings (-52%, crossings don't block access in bcfishpass)
- Stream order exception (3 points, not the main cause)
- Thresholds (spawn_gradient_max, rear_gradient_max, channel_width ranges — all match exactly)
- Access gating (bcfishpass uses only natural barriers, same as us)

## Filed
- NewGraphEnvironment/bcfishpass#9 — access_st checks 'SK' instead of 'ST' (copy-paste bug)
- NewGraphEnvironment/link#33 — reference to bcfishpass#9

## Versions
- fresh: 0.13.4, bcfishpass: v0.5.0, link: 0.1.0
