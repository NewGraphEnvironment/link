# Task Plan: ST/WCT classification gap (#31)

## Goal
Identify and close the ST -22% spawning / -25% rearing gap on BABL, WCT -4% on ELKR.

## Status
- Per-model non-minimal: tested, no effect on ST/WCT
- label_block with crossings: tested, -52% regression (crossings don't block in bcfishpass)
- Stream order exception: tested, closed 3 points on ST rearing (-28% → -25%)
- Root cause NOT confirmed. Hypotheses tested and eliminated. Need segment-level comparison.

## Phase 1: Segment-level ST comparison on BABL
- [x] Query tunnel: bcfishpass ST segments → bcfishpass_ref.st_babl (2,334 rows with geometry)
- [x] Query local: our ST classification → bcfishpass_ref.st_babl_ours (31,580 rows)
- [x] Diff: 223 bcfishpass-only spawning segments (87.9 km), 688 bcfishpass-only rearing (277.7 km)
- [x] For mismatches: 382/383 are inaccessible in our system. Falls at BLK 360886207 blocks them.
- [x] Root cause: observation_species for ST was "ST" only. bcfishpass counts all salmon+steelhead.
- [x] Fix: one CSV cell. ST spawning -22% → +3.8%, ST rearing -25% → +2.4%.

## Phase 2: WCT + ELKR verification
- [ ] Run ELKR with WCT observation override fix
- [ ] Run BULK with ST fix

## Phase 3: SK spawning segment-level comparison
- [ ] Same approach: dump bcfishpass SK spawning segments for BULK/BABL
- [ ] Diff against ours
- [ ] Identify whether it's access, classification, or cluster algorithm

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
