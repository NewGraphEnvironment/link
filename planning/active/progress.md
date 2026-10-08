# Progress — Default lake and wetland rearing: connected to spawning, centrelines kept, km and ha broken out (#310)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user; four forks decided at the gate (species scope, column rename, wetland construction lines, distances)
- Created branch `310-default-lake-and-wetland-rearing-connec` off main
- Scaffolded PWF baseline from issue #310 with approved phases
- Next: start Phase 1
- Phase 1: distance 10,000 m for all species, lakes and wetlands; written to `research/habitat_thresholds.md` "Lake and wetland rearing connected to spawning (#310)". Zotero MCP lacks env vars; read the local library store read-only instead.
- Phase 2: builder stamps `requires_connected: spawning` on the first rear L / W rule from the new per-type distance columns; additive L rule takes lake centrelines (1000/1100/1200/1300/1400/1450/1475, categories: stream/construction/connector) with `thresholds: false`; SK/KO circular-connection and area_only refusals; retired columns error when set. Lake edge set kept 1000/1100 too (none in the 4 measured WSGs; harmless where a mainline sits in a lake). Existing carve-out tests identified the carve by `thresholds: false`, which the L rule now shares; fixed.
- Phase 2 code-check: round 1 two fragile (categories-mode lake edges wider than explicit; SK/KO area_only refusal in a branch that never emits it), fixed; round 2 clean; round 3 one fragile inside round 1's fix (refusal assumed the L rule is the spawning anchor; fresh anchors on the first L or W rule), fixed; ended by enumerating the 7 builder sites that restate a fresh decision (`review-p2-round3.md`). Plan review (`review-plan.md`) also folded in: lake edge set widened to 1250/1350 (reservoirs, province-wide query), stop on a distance with no rule of its type.
- Phase 3: distance columns (10,000 m) added by column name to default, default_extrabreaks, default_rearbreaks and the top-level dims; CO lake / wetland floors blanked; dictionary rows added / retired; rules built per bundle with its own thresholds (variants byte-identical to default); bcfishpass untouched; provenance (rules checksum + generator_sha 83dfe16, dims checksum + shape + synced) — all five bundles verify clean. 13 connection stamps (7 L, 6 W).
- Phase 3 code-check: round 1 dictionary edge-set text (fixed); round 2 clean (proved the bundle test fails on a changed distance); round 3 three stale restatements (reservoir in bucket, CO's old floors, CT/DV cluster wording), fixed; ended on the reviewer's enumeration of restated facts.
