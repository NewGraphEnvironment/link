# Progress — Extend PARS vignette to demonstrate accessible_km bcfp-equivalence (#226)

## Session 2026-07-04

- Cleared leftover memory-migration + run-logs onto `main` (commits `3846a3d`, `16b41aa`; pushed). Left
  `.claude/settings.local.json` uncommitted — it carries a live bcfp-tunnel password (flagged to user).
- Plan-mode exploration: 3 Explore agents (vignette / data-gen+build / API+numbers) + 1 Plan-agent review.
- Live-verified the PARS·BT roll-up numbers and the `fresh_default` pre-#223 blocker (see findings.md).
- User chose **full faithful regeneration** (re-model the stale grayling schema, not accessible-only).
- Created branch `226-vignette-accessible-km` off main; scaffolded PWF baseline with approved phases.
- **Phase 1 done:** re-modelled PARS default → `fresh_default` (`wsg_run_one.R`, 5.1 min) + `merge=TRUE`
  recompute (`wsg_recompute_one.R`, 1.6 min). Gate: `fresh_default` PARS = 97,537 segs / 142.2 m (matches
  `fresh` 97,538). Join nuance surfaced + reassessed: 94.49% exact-length but **99.93% aggregate-length +
  exact GR count** (19,232 = native); residual is local habitat-break redistribution, sub-pixel at basin
  scale → single-layer gpkg design retained (user informed).
- **Phase 2 done:** `data-raw/wsg_vignette_data.R` — added accessible/spawning/rearing km cache
  (`pars_accessible.rds`, mirrors `parity_crosssection.R` link+bcfp `IN (1,2)`) + segmentation-parity guard
  (refuses mixed-segmentation gpkg).
- **Phase 3 done:** regenerated all artifacts. accessible **6822.47 | 6822.88 | −0.01%** (exact),
  spawning +0.93%, rearing −0.53%; mapping_code parity 98.91%; gpkg 11.9 MB (no balloon), all 8 layers,
  tunnel context included.
- Next: Phase 4 — vignette accessible_km subsection + inline-compute the stale map captions, then
  DB-stopped knit (Phase 5).
