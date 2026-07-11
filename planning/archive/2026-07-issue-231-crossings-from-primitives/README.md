# #231 — "Consume weekly crossings.csv; repoint pipeline off fresh" — CLOSED AS MISDIRECTED

## Outcome

Closed without implementing. The premise was wrong: **the pipeline does not consume
`crossings.csv` at all.** Superseded by **link#232** (parity confirmation).

## The lesson (so we never re-derive this)

link's pipeline **builds the crossings table from primitives itself** and does **not**
read fresh's (or newgraph's) pre-built `crossings.csv`:

- `lnk_pipeline_run` order: load → prepare → **crossings** → break → classify
  (`R/lnk_pipeline_run.R:126-137`).
- The **crossings** phase (`lnk_pipeline_crossings` → `.lnk_crossings_union`,
  `R/lnk_crossings_union.R:120`) runs `DROP TABLE <schema>.crossings; CREATE TABLE … AS
  <UNION of PSCIS snap/score/xref + fresh.modelled_stream_crossings + CABD>`.
- So `lnk_pipeline_load`'s CSV read (`R/lnk_pipeline_load.R:100`) is **vestigial** — it
  writes a `<schema>.crossings` table that the union immediately **drops + rebuilds**
  before break/classify/mapping_code ever touch it. The mapping_codes / accessible_km in
  the PARS vignette came from the **union** (DB primitives), never the CSV.

This is the deliberate tunnel-free decoupling (#137/#152/#158): **link is a peer of
bcfp** — both pull `modelled_stream_crossings` (bchamp objectstore) + PSCIS (BCDC) +
CABD and each build their own crossings. link re-implements bcfp's
`02_pscis_streams_150m.sql` + `04_pscis.sql`.

## What the newgraph crossings.csv IS good for

Not a model input — but bcfp's **complete** crossings table (`bcfishpass.crossings` /
`crossings_vw`) is the natural **parity reference** for validating link's
primitives-build. That's link#232.

## Freshness lever (the real thing)

The pipeline's crossings are as fresh as `fresh.modelled_stream_crossings` (+ PSCIS +
CABD), loaded manually by `data-raw/snapshot_bcfp.sh`. As of 2026-07-11 it was last
loaded ~2026-05-26 (529,244 rows, on the **`fwapg`** DB — note `lnk_db_conn()` defaults
to a `bcfishpass` DB that LACKS it). Automating that reload weekly is the real
"stay current" task (follow-up; noted in link#232).

## How we got here (the rabbit hole, so we don't repeat it)

We published `crossings.csv` to `s3://newgraph` (db_newgraph#15, smnorris PR #57)
believing the models needed a fresh crossings snapshot. A pre-commit **Plan-agent
review** of the #231 plan caught that the union already replaced the CSV — verified in
code before writing any implementation. **db_newgraph#16** tracks reconsidering that
(now model-unneeded) dump.

## Pointers

- **link#232** — parity: confirm link `<schema>.crossings` ≈ bcfp `crossings_vw`.
- **db_newgraph#16** — reconsider the newgraph `crossings.csv` dump.
- Key code: `R/lnk_pipeline_crossings.R`, `R/lnk_crossings_union.R`,
  `R/lnk_pipeline_load.R:100` (the vestigial CSV read).
- `findings.md` here = the (still-useful) machinery exploration. `task_plan.md` =
  the **superseded** fetch-cache plan (kept for history; do not implement).

Closed by: this archive commit; #231 closed on GitHub.
