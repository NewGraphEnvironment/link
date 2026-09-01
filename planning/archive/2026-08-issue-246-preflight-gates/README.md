# 2026-08 — issue #246: pre-flight gates for a provenanced multi-host run

**Outcome: shipped as v0.47.0–v0.47.2 (Phases 1–2). Phases 3–5 remain open on #246.**

`fresh` held 93 WSGs accumulated over three months with no `log` / `log_input`
tables — not one row traceable to a run, a config hash, or a date. A run started
against that state would have **silently skipped 80 of 119 WSGs and exited 0**.
This branch built the gates that make a provenanced rebuild possible.

**Root cause of the silent skip was narrower than the issue stated.** `fresh` was
declared in **Suggests**, and `pak::local_install()` resolves hard dependencies
only — so the `Remotes:` pin in DESCRIPTION was never applied and cyphers ran the
image's fresh 0.31.0. Moving it to Imports fixes it with no change to the pak
call. New `lnk_preflight_fresh()` asserts **symbols, not a version string**, with a
drift guard that walks link's own namespace (not `R/`, which does not exist in an
installed package).

Also landed: `cypher_prep.sh` hardening (`CYPHER_PREP_FRESH_REF` override,
`CYPHER_PREP_STAGE=install|all` cutting `--auto-install` from ~20 min to ~3, a
`~/.Renviron` carrying the cypher's *own* observed SHAs), and the sentinel fix at
`study_area_run.sh:203` / `wsgs_run_pipeline.sh:267`.

**Proven on real hardware.** Run `20260831_232553`: 34 field WSGs across three
hosts — 19 on m1 (Fraser), 9 + 6 on two cyphers (Peace, Skeena). 158 min, ~$0.83.
Every post-condition passed, verified against the DB rather than an exit code:
per-host completeness 19/19 + 9/9 + 6/6, consolidate 2/2, burn clean, coverage
verified, 116 compare rows across 34/34. `fresh` grew 93 → 95 (BOWR and PINE
modelled for the first time). Cypher rows carry `fresh_sha` — #246's acceptance
criterion, `NA` on every cypher before this work. Reusable checker:
`data-raw/study_area_verify.sql`.

**Five review rounds** are preserved here (`review-round1.md` … `review-round5.md`)
because `study_area_run.sh` is the most heavily reviewed file in the repo and the
rounds record why several guards are shaped the way they are.

## Three corrections to earlier beliefs, recorded so they are not re-derived

1. **A wipe is NOT required for a provenanced rebuild.** `lnk_pipeline_persist`
   replaces per WSG, and the 93 WSGs in `fresh` were a strict subset of the run —
   zero orphans, no destructive step, no empty window.
2. **Only Peace is FWCP.** Fraser and Skeena are HCTF. "The 3 FWCP study areas"
   was wrong and had propagated into several docs.
3. **Field scope != model scope.** A GIS project's `watershed_groups` is where
   crews collected; the reporting repo's `wsg_code` is what is modelled.

## Measured, and now driving planning

Modelling 83 min, recompute + compare 55 min. The recompute runs over **every WSG
in the schema**, not the run's own set, so it does not scale with scope the way
modelling does — which is what makes **#250** (parallelise it) worth more than more
machines. That issue is the direct successor to this work.

## Follow-ups left open

- **#246** Phases 3–5
- **#247** `snapshot_stamp`
- **#250** parallel recompute — picked up immediately after this archive
- **#257** `link_dirty` is `t` on every dispatcher row and is false: the run's own
  logs dirty the tree

Closing commits: `7b83578`, `7701ffc`, `826cc72`, `2da6dd3`.
