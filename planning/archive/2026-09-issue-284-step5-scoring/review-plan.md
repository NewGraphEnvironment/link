# Plan review — #284 step 5 (Plan agent, 2026-09-29)

Read-only agent; findings returned as reply text and transcribed here with each one's disposition.

## Blockers
- **B1 Power.** The held-out bands cannot reach n ≥ 10. Held-out locations: BT 7 / 1 / 0, CH 1 / 0 / 2 (the reviewer's FWA-gradient counts). **Confirmed**: the re-derivation gives BT 10 / 1 / 0, CH 0 / 1 / 2 (`data-raw/logs/habitat_score_284/power_windows.txt`). **Operator decision:** widen the BT held-out set (UARL, REVL, CLRH, LILL, BABL, BABR) and drop CH.
- **B2 "keep" semantics.** An underpowered first step would reset `default_tuned` to 0.1049. **Operator decision:** an underpowered step changes nothing; 0.1349 stands.
- **B3 CH spawning stage vs the UHC overlay.** The core could hold forced reaches. Moot once CH was dropped (BT has 0 UHC rows). The score script now stops if a scored species has forced reaches for the flag.

## Gaps
- **G1** Re-persisting `default` in the variant loop would overwrite the recomputed access. **Already so:** the base variant is re-classified for its digest only and never persisted.
- **G2** Pass the working schema to persist explicitly. **Done.**
- **G3** `lnk_persist_init(species = cfg$species)`. **Done.**
- **G4** Must `load_all`. **Done** (`pkgload::load_all` at the top of both scripts).
- **G5** The knowledge repo moved since the #283 baseline. **Handled:** pinned at `508bf44` through `git archive`; byte-identical.
- **G6** Thin-bundle CSV fidelity. **Done:** the round-trip is proven byte-identical on default before any variant; the one-cell diff is asserted; `equals_bundle` is compared by md5.
- **G7** Variant schemas carry no DB provenance. **Done:** each bundle's provenance checksum is verified; the bundles and the stamp are committed. No per-variant `log` row (the variants are not pipeline runs).
- **G8** Recompute provenance and timeouts. **Done:** `log_recompute` rows plus the statement and lock timeouts.

## Ordering
- **O1** The BULL pre-flight needs LARL and KOTL first (the guard). **Accepted:** the pre-flight is the first three base WSGs; the full run resumes past them.
- **O2** Recompute after all base WSGs. **Done.**
- **O3** Commit the rule after the power check. **Done:** the rule was revised with the counts before the commit.

## Assumptions (verified by the reviewer)
- A1 re-classify is clean; A2 access is threshold-free; A4 a thin bundle outside `inst` works (set `name:`, own provenance); A5 the resolve order is downstream-first; A6 the band is buildable from `$observations`.
- **A3** A band is not purely the gradient window (clustering). **Done:** `bridge_band.csv` splits the band into in-window and connectivity-admitted.

## Scope
- **S1** The closure costs about 55 % of the base run. Accepted at the gate.
- **S2** Variants classify every species. **Done:** variants classify BT only.
- **S3** Plan text drift (`tighter` → `step_from`; core = intersection). **Done:** task_plan revised; the nesting assertion is in the score script.

## Acceptance
- **AC1** The access invariant was tautological. First fixed by comparing the working-derived access with the base's before the copy; code-check round 1 showed that comparison could never pass (a variant persists only its own species' access columns) and was not a threshold test either (classify and connect never rebuild access). The BULL pre-flight hit it at run time. **Dropped:** access is threshold-free by code reading (A2) and is copied from the base.
- **AC2** Rollup rounds to 0.01 km. Noted for the Phase 5 reconciliation tolerance.
- **AC3** The digest is defined as working long `streams_habitat` against working. **Done.**
- **AC4** Launch gate. **Done:** the build refuses uncommitted R/config/data changes unless `--allow-dirty`.
