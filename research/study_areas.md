# FWCP study areas — Peace / Fraser / Skeena

The 3 FWCP regions and their watershed groups — the parity-run scope for link
(link#175). Authoritative source = the `wsg_code` / `wsg` param in each
`fish_passage_*_reporting` repo (`index.Rmd` for Peace/Fraser,
`scripts/02_reporting/0160-load-bcfishpass-data.R` for Skeena).

## Focal watershed groups

- **Peace** — `NewGraphEnvironment/fish_passage_peace_2025_reporting`
  (`index.Rmd` `wsg_code`, 16): CARP, CRKD, FINA, FINL, FIRE, FOXR, INGR, LOMI,
  MESI, NATR, OSPK, PARA, PARS, PCEA, TOOD, UOMI
- **Fraser** — `NewGraphEnvironment/fish_passage_fraser_2025_reporting`
  (`index.Rmd` `wsg_code`, 8): LCHL, NECR, FRAN, MORK, UFRA, WILL, TABR, LSAL
- **Skeena** — `NewGraphEnvironment/fish_passage_skeena_2024_reporting`
  (`0160-load-bcfishpass-data.R` `wsg <- c(...)`, 5): BULK, MORR, ZYMO, KISP, KLUM

## Drainage closure

29 focal WSGs → **~52 with downstream-closure** (every WSG each drains through —
e.g. PARS → PCEA / UPCE / LPCE / FINA / PARA / LBTN). Closure + downstream-first
order are derived from `wscode_ltree` ancestry (`@>`) via the `public.wsg_outlet`
helper table (a per-WSG outlet `wscode_ltree`; see the Database Connection section
of `CLAUDE.md` and issue #227 for its reproducible build). Major drainages by root
wscode: Fraser `100` (68 WSGs), Peace `200` (65), Columbia `300`/ELKR (17 — NOT a
study area), Skeena `400` (12).

**Why closure matters:** mapping_code `;DAM` is cross-WSG — a headwater WSG only
emits `;DAM` once its downstream dam-bearing WSGs are persisted. So a study-area
parity run must be drainage-closed downstream **and** DS-first ordered (or
two-passed). This is the crux of #175's orchestrator work; run procedure in
`research/study_area_run.md`.
