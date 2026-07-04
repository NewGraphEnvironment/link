## Outcome

Combined **#221** (per-WSG `accessible_km` roll-up) + **#223** (access-segmentation-frontier fix), shipped as one PR.

**#223 root cause:** `gradient_barriers_minimal` was fed the `fresh::frs_barriers_minimal()` downstream-most reduction as a *segmentation* source, so a stream segment straddled the accessibility frontier and its whole reach — including the blocked part above the barrier — was credited accessible. BT/ST `accessible_km` over-credited up to +40% (PCEA), +23.6% (FINA). **Fix** (one file, `lnk_pipeline_prepare.R`): union the RAW per-model gradient + falls positions into `gradient_barriers_minimal` so streams break at every frontier — mirroring the orphan path and matching bcfishpass. `frs_barriers_minimal` is now unused in link.

**#221** added the `accessible_km` column to `lnk_compare_rollup` + a reusable `lnk_rollup_wsg()`.

**Proof** (`research/parity_accessible_habitat_2026_07_03.md`, `data-raw/parity_crosssection.R`): across **11 WSGs × 8 species** (Peace/Fraser/Skeena/Columbia), `accessible_km` converges **44/44 within 0.05%**; spawning/rearing hold, the only 2 over-tolerance being the documented parked **BULK SK** (fresh#190 dual-rearing-lake topology). Zero regressions. Consolidated 3 accessible-km scripts into one.

**Key learnings:** bcfp `spawning_<sp>`/`rearing_<sp>`/`access_<sp>` are coded **0/1/2/3** — use `IN (1,2)`, a bare `= 1` under-counts (cost me a false "+42% spawning divergence" scare). The fix is **habitat-neutral** (byte-identical spawn/rear pre/post). Segment count grows **2–3.5×** (inherent to bcfp-matching; intersects perf #205).

**Follow-ups filed:** #224 (bcfp `dam_dnstr_ind` reservoir-inflow propagation), #225 (rename `gradient_barriers_minimal` → `gradient_barriers_break`), #226 (extend PARS vignette for `accessible_km`), #227 (`wsg_outlet` builder + single-WSG downstream-state guard).

Closed by: branch `223-access-segmentation-frontier` — PR closes #221 + #223.
