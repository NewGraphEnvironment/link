# Provincial parity — accessible + spawning + rearing (2026-07-03)

Cross-section parity proof for the combined **#221** (per-WSG accessible_km roll-up)
+ **#223** (access-segmentation-frontier fix). Extends the historical spawn/rear
parity harness with the **accessible_km** column and re-runs a species/region
cross-section to prove the fix converges `accessible_km` without regressing habitat.

## Run metadata

- **Harness:** `data-raw/parity_crosssection.R`. link side = `lnk_rollup_wsg()` (#221);
  bcfp side = tunnel-free `fresh.streams_vw_bcfp`.
- **Predicate:** `IN (1,2)` on `access_<sp>` / `spawning_<sp>` / `rearing_<sp>`. bcfp
  codes these `0/1/2/3`; `IN (1,2)` is the presence predicate — a bare `= 1`
  under-counts spawning/rearing (caught + corrected this session).
- **Reference:** `smnorris/bcfishpass@v0.7.15-41-g2917790`, `fresh.streams_vw_bcfp`.
- **Scope:** 11 WSGs re-run with the fix (`lnk_pipeline_run(mapping_code = TRUE)`),
  spanning Peace / Fraser / Skeena / Columbia, all 8 species:
  - Peace (BT-only): FINA, PARS, PCEA
  - Fraser/Skeena (BT+ST+salmon): LKEL, BULK, MORR, KISP, LFRA, USKE
  - Columbia/Kootenay (BT+WCT): ELKR, KOTR
- **Tolerance:** accessible ≤ 1%, habitat (spawn/rear) ≤ 5%.

## Headline result — the fix works, no regression

| metric | pairs | WSGs | species | max \|diff\| | within tol |
|---|---|---|---|---|---|
| **accessible** | 44 | 11 | 8 | **0.05%** | **44/44** |
| spawning | 43 | 11 | 8 | 10.99% | 42/43 |
| rearing | 35 | 11 | 6 | 35.20% | 34/35 |

**Overall: 120/122 within tolerance.** `accessible_km` is exact everywhere
(max 0.05% across all 8 species × 11 WSGs) — that is the #223 fix, before which
FINA/PCEA were +23.6% / +40.4%.

## The only two exceptions — both pre-existing, documented, parked

`BULK SK` spawning **+11.0%** (link 27.1 / bcfp 24.4) and rearing **+35.2%**
(link 64.6 / bcfp 47.8). This is **fresh#190** — the Elwin + Day Lake dual-rearing-lake
topology on `blue_line_key 360846413`, documented at
`research/bcfishpass_methodology.md:124-141` (spawning +11.0% recorded there verbatim).
Pre-existing, unrelated to #223, and exactly the "if the rollup surfaces similar SK
bumps on multi-lake topologies" case that doc predicted. **No #223 regression.**

## Excluded — species link does not model (#189 residence)

bcfp lumps all salmon into one barrier group so its `access_<sp>` is populated
everywhere; link only models a species where `wsg_species_presence` declares it. These
are one-sided (bcfp present, link 0) and excluded from the parity assertion (tracked in
#189), not silent:

- LKEL SK; BULK CM; MORR CM; USKE CM; USKE PK.

## Convergence highlight (accessible_km, BT — the #223 target)

| WSG | pre-fix | post-fix |
|---|---|---|
| FINA | +23.59% | **−0.02%** |
| PARS | +3.43% | **−0.01%** |
| PCEA | +40.36% | **−0.01%** |
| LKEL | +0.72% | **0.00%** |

## Reproduce

```
# each WSG first re-run with the fix, then:
LNK_LOAD=loadall Rscript data-raw/parity_crosssection.R \
  FINA PARS PCEA LKEL BULK MORR KISP LFRA USKE ELKR KOTR
```
