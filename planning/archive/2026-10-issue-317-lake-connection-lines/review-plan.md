# Plan review (#317), 2026-10-08

A Plan agent reviewed the plan at `00235e0` alongside the uncommitted Phase 2 / 3 edits. Its reply is summarised here because Plan agents cannot write files. Each finding carries its disposition.

**Blocker**
1. The assemble loop (`lnk_compare_wsg.R` ~549) is unguarded, so link fixtures without `rearing_lake_connection_km` fail. **Fixed**: the column is added to every fixture. The loop keeps failing loud on a missing column, because real link output always carries it.

**Gap**
2. `lnk_habitat_validate()` takes its cost from the default `lnk_rollup_wsg()` while capture reads the `h.rearing` flag. **Fixed by design change**: `lnk_rollup_wsg()`'s default `rearing_km` stays the flag total. Code-check round 1 found the same thing.
3. `parity_crosssection.R` / `wsg_vignette_data.R` compare the default `rearing_km` with `streams_vw_bcfp`'s flag. **Fixed by the same design change**: both sides stay on the flag, and those scripts are flag-parity instruments.
4. `compare_rollups.R` needs a #317 guard, and the new metric added to `keep`. **Done.**
5. Taxonomy: handling for `rearing_lake_connection`, plus a re-check of the pinned `diff_range` bands (SK). **Done in Phase 3**; see progress.
6. `devtools::document()` after the `@return` edits. **Done.**
7. NEWS.md entry: `/gh-pr-merge` writes it at release.
8. Path corrections (`inst/extdata/configs/...`). **Noted for Phase 4.**

**Ordering**
9. PWF boxes. Phase 1 boxes were ticked in `00235e0`; the reviewer read an earlier state.
10. The ADMS CH / CO expectation (+14 / +3 %) was wrong; the measured values are +38.9 / +28.7 %. Phase 1 README records it, and the plan text is updated.
11. Phase 2 and Phase 3 land as one commit, so the rollup is never asymmetric.

**Assumption**
12. The live `lnk_compare_rollup()` check needs the tunnel, and `fresh_default` ADMS is pre-#310 (CH has no lake km), so include SK. Its numbers won't equal Phase 1's.
13. Phase 1's reference (`streams_vw_bcfp`) is not the shipped reference (tunnel `habitat_linear_<sp>`), so compare with a tolerance.
15. `edge_type` NULL would drop a line from both sides. **Fixed**: the predicate is wrapped in `COALESCE(..., FALSE)`.

**Scope**
16. `.lnk_compare_wsg_rollup_link` has no package caller; it is a log helper. Updated anyway, since the logs use it.
17. `research/bcfishpass_methodology.md:102` calls 1400 / 1450 "real flow representations". **Phase 4 note.**
