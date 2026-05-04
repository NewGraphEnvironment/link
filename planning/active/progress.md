# Progress — DB hygiene: drop working schemas after persist; drop worker schemas after consolidation (#118)

## Session 2026-05-04

- Plan-mode exploration of `R/lnk_pipeline_persist.R`, `data-raw/compare_bcfishpass_wsg.R`, `data-raw/consolidate_schema.R`, and existing persist tests. Phases approved by user.
- Decision: orchestrator-level cleanup (compare_bcfishpass_wsg + consolidate_schema), not in-package. Keeps `lnk_pipeline_persist` scoped to one job; rollup query continues to read working schema in long-form.
- Created branch `118-db-hygiene-drop-working-schemas-after-pe` off main (post v0.28.0).
- Scaffolded PWF baseline.
- Phase 1 done — `cleanup_working = TRUE` param added to `compare_bcfishpass_wsg()`; drops `working_<aoi>` after rollup. ADMS smoke: rollup `identical()` to pre-cleanup baseline, working_adms confirmed dropped.
- Phase 2 done — `keep_source = FALSE` param added to `consolidate_schema()`; drops source schema on each remote host after successful pg_restore (rc-guarded; warn-but-don't-fail on drop failure).
- Phase 3 done — `data-raw/README.md` "Disk capacity per worker host" section: per-bundle footprint, extras 2.8× multiplier, 60 GB safe floor, cypher incident reference.
- Phase 4: smoke verification done (Phase 1 byte-identical). Multi-WSG + cross-host rehearsal deferred to next real provincial (cypher's fwapg needs reload first). Suite 736 PASS / 0 FAIL.
- Phase 5 ready — NEWS.md + DESCRIPTION bumped to 0.29.0. PR open + SRED cross-ref next.
