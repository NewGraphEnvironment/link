# Study areas: funders, and the two scopes that get conflated

Migrated from machine-local memory 2026-09-01 (soul#47) so every machine has it.
Assembled 2026-08-31 by reading each GIS project's own AOI layer against
`whse_basemapping.fwa_watershed_groups_poly` — "not invented" — which is why it
is worth keeping rather than re-deriving.

**Not to be confused with `research/study_areas.md`, which is GENERATED** by
`data-raw/study_area_buckets.R --write` and will be overwritten. This file is
hand-maintained.

## Only Peace is FWCP

These were called "the 3 FWCP study areas" for a long time. That is wrong, and
the error propagated into `research/`, `NEWS.md` and a planning archive before
it was caught.

**Peace is FWCP. Fraser and Skeena are HCTF** (Habitat Conservation Trust
Foundation, provincial). The repo names corroborate it:
`rtj/scripts/gis/projects/sern_peace_fwcp_2023` and
`fish_passage_hctf_skeena_fraser_2026_proposal`.

## Two different scopes — do not conflate

This cost an hour on 2026-08-31.

- **FIELD scope** — the WSGs a GIS/Mergin project's AOI covers, i.e. where crews
  collected data. Lives in `rtj/scripts/gis/projects/<name>/project.yml` as
  `watershed_groups`.
- **MODEL scope** — the WSGs a report analyses. Lives in each
  `fish_passage_*_reporting` repo as `wsg_code` (`index.Rmd`) or `wsg <- c(...)`.

They legitimately differ. *"We model the entire FWCP Peace but only put the rtj
project WSGs in the GIS"* — Peace field = 8, model = 16.

| area | funder | field (rtj `project.yml`) | model (reporting repo) |
|---|---|---|---|
| Peace | **FWCP** | 8: CARP CRKD NATR PARA PARS PCEA PINE UPCE | 16: + FINA FINL FIRE FOXR INGR LOMI MESI OSPK TOOD UOMI |
| Fraser | **HCTF** | 10: BOWR COTR FRAN LCHL LSAL MORK NECR TABR UFRA WILL | 8 (reporting repo omits BOWR, COTR — may be stale) |
| Skeena | **HCTF** | *no rtj `project.yml` yet* — `sern_skeena_2023` exists as a Mergin project | 5: BULK MORR ZYMO KISP KLUM (stable 2024 and 2025) |
| Columbia / nelson | ? | 3: KOTL LARL SLOC | — |
| hornby_2026 | ? | **not recorded** — no AOI layer to read | — |

## Scope numbers that matter

- 96 focal (93 persisted + the Columbia trio) → **125 in closure → 119
  modelable**. Six drop on species presence — LEUT, LFRT, LKEC, LNRS, MFRT,
  UFRT — and none contains a dam, so the gap is benign.
- **BC has 246 WSGs; 217 are modelable.** The "provincial" 119 is only the
  drainage closure of *current* focal areas, about half. All-BC is 4.49M source
  segments against 2.56M — **1.76×** — if "look anywhere" is the goal. Scope
  was decided at 217 in #256.

## How closure and order are derived

`lnk_wsg_resolve()` → `fresh::frs_wsg_drainage()` (fresh >= 0.33.0).

**Never hand-roll this from `wscode_ltree` ancestry.** A single ltree cannot
order two groups on one stem, and the shallowest code appearing anywhere in a
group can come from a polygon sliver — see `RUNBOOK.md` §8b and §8c.

Buckets are derived, not chosen: `data-raw/study_area_buckets.R` (union-find
over per-WSG closures, then greedy LPT by finish time) writes
`research/study_areas.md`. Whether its segment-count weight is the right one is
open in #259.
