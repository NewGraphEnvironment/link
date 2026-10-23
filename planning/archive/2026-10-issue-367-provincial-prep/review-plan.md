# Plan review — #367 (Plan agent, delivered 2026-10-22 ~23:18 UTC)

Read-only reviewer, findings returned as reply text and recorded here. It read the working tree with Phase 1-2 edits in progress. Disposition after each.

## Blocker

- **B1. bcfp does not tie the same way; link skips a bcfp step.** bcfp `02_pscis_streams_150m.sql` (after the B-side dedup and close-enough reset) keeps one modelled crossing per PSCIS per blue line, nearest instream (`DISTINCT ON (stream_crossing_id, blue_line_key) ... ORDER BY ..., modelled_xing_dist_instream`), and nulls the rest. `.lnk_pipeline_pscis_build()` had no equivalent; that is where the #277 ties come from. — **Verified** in the local bcfp clone (`f8db4b9`). **Fixed:** ported as Step 3b with a `modelled_crossing_id` tie-break; the comments corrected.
- **B2. Phase 3's #244 diff against `fresh_default` mixes in #277.** — **Taken:** #244 is checked knob-on against knob-off at the same HEAD.
- **B3. The anadromous flavour gives `DAM` for any dam downstream unless remediated** (`R/lnk_pipeline_mapping_code.R:205-209`), so the "next anthropogenic barrier" wording holds for residents only. — **Verified, fixed** in `config.yaml` and the Phase 3 expectation.

## Gap

- **G1. Token changes land in groups upstream of the placeholders, which a recompute of the three holding groups cannot show.** — **Partly taken:** the upstream groups are predicted from placeholder positions (findings) and measured by the provincial run, not rebuilt here.
- **G2. The issue's verification named NATR and per-species km.** — **Taken:** NATR added to the main-against-branch comparison, with km per species.
- **G3. Ordering by `(blue_line_key, measure)` renumbers the placeholders even with the knob off; bcfp numbers them in table order.** — **Fixed:** numbered by CSV row (`csv_row`), stated in both the staged table and the guard's VALUES.
- **G4. The persisted-`fresh.barriers` psc-NULL test breaks once `default` (which persists to `fresh` by default) runs with the knob.** — **Fixed:** removed; the prep DB test covers both knob states.
- **G5. Anti-drift with the knob on.** — Covered by the new guard DB test (the placeholder id the guard reports equals the one prep persists).
- **G6. Unordered picks elsewhere:** the dam snap's inner `LIMIT 1`, `lnk_points_snap()`'s `LIMIT k`, and `row_number() OVER ()` for gradient / falls / user-definite / subsurface barrier ids in `lnk_barriers_unify()`. — **Fixed** all four (snap timing unchanged, 1.6-1.8 s province-wide). `fresh::frs_network_features` relying on subquery order through GROUP BY: noted, not changed here (fresh's code).
- **G7. `default_extrabreaks` / `default_rearbreaks` are `extends: ~`.** — Left off the knob; experiment bundles.

## Assumption

- **A1. What the knob moves:** not segmentation (placeholders already break streams), not access (classify blocks on `blocked` only; `_access` views exclude CABD), not observation overrides; it adds CABD barrier rows and moves the dam flags behind mapping codes. — Phase 3 asserts it.
- **A2. With the knob on, the guard fails for groups upstream of a placeholder until KETL / LARL / SKGT are re-persisted.** — Owed in RUNBOOK and #361.
- **A3. Take barrier status from `barrier_ind`.** — **Taken.**
- **A4. Source keys unique?** — **Measured:** `fresh.modelled_stream_crossings` 524,578 rows / ids; PSCIS 19,905 / 19,905. The 24 rows that still share `(stream_crossing_id, linear_feature_id, modelled_crossing_id)` are exact duplicates from the rivers-polygon join, as in bcfp.
- **A5. Placeholder ids share the `user_crossings_misc` range.** — Recorded; misc rows never reach crossings today.

## Acceptance

- **C1. A same-day two-build diff need not catch the defect.** — **Taken:** the in-process census and repeated builds: main's code gave 464 different PSCIS picks between two builds minutes apart; the branch 0; no top tie left that differs in a passed-on column.
- **C2. Record parity movement.** — The pick change moves toward bcfp; measured on ADMS / ELKR / NATR against main in Phase 3, and parity is re-scored after the provincial run.
- **C3. Rewrite the CLAUDE.md "Full-run digests are not reproducible on main" note.** — Phase 4.
