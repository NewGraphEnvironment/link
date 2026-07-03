# Progress — accessible_km segmentation-frontier fix (#223)

## Session 2026-07-03

- Root-caused the BT/ST `accessible_km` over-credit to `gradient_barriers_minimal`
  being fed the `frs_barriers_minimal()` downstream-most reduction as a segmentation
  source (`lnk_pipeline_prepare.R:592`). Verified `frs_barriers_minimal` is single-use,
  `gradient_barriers_minimal` is segmentation-only, and `barriers_<sp>_access` is built
  independently — so the fix is isolated.
- Filed **#223** with root-cause framing + embedded PNG (`research/blk359209845_bt_accessible_km.png`,
  committed `1a26f7d` on the 221 branch; raw URL pinned for the issue embed).
- Committed the research doc + 221 findings to the 221 branch (`4549713`), pushed 221.
- Created branch `223-access-segmentation-frontier` off `origin/main`; unset its
  main-tracking upstream (safety).
- User decisions: fix branch off main (own PR, closes #223); keep table name now +
  file a separate rename issue once confirmed.
- Scaffolded PWF baseline (`43866a8`).
- **Confirmed the pre-fix fingerprint live** (see findings.md "Live pre-fix fingerprint"):
  `working_fina.gradient_barriers_minimal` empty on blk 359209845; `fresh.streams`
  id_segment 4218 = `[3391,7998]` 4607 m one segment; BT accessible_km FINA link 7520.7
  / bcfp 6085.2 = +23.59%. FINA/PARS/PCEA all persisted + in `fresh.streams_vw_bcfp`.
- Enriched issue #223 with the full code-trace, the exact fix, and the live fingerprint.

## Handoff → new session

Session is being handed off (context-heavy). Pick up here:
1. Read issue #223 (now comprehensive) + this PWF + `research/accessible_km_divergence.md`
   (on the 221 branch).
2. Phase 1: write `data-raw/accessible_km_fix_validate.R` (segment 3835 blocked + BT
   accessible_km FINA/PARS/PCEA vs bcfp + salmon clean). It should FAIL pre-fix.
3. Phase 2: the one-file fix — `lnk_pipeline_prepare.R:592-593`, union raw `model_tbl`
   into `gradient_barriers_minimal` (drop `frs_barriers_minimal` for segmentation);
   keep the name, update stale doc comments.
4. Phase 3: re-run FINA/PARS/PCEA (`lnk_pipeline_run(..., mapping_code = TRUE)`),
   validate no-regression; `devtools::test()` + `lintr` clean.
5. Phase 4: `/code-check`, atomic commit, file the rename follow-up issue, `/gh-pr-push`.

Tasks #16–#19 track the remaining phases.

## Session 2026-07-03 (cont.) — Phase 1 complete

- Reproduced the full pre-fix fingerprint live on `:5432` fwapg (`working_fina.barriers_bt`
  = 16 barriers incl. frontier 3834.78; `barriers_bt_min` = 0 rows on the blk = the
  `frs_barriers_minimal` smoking gun; `gradient_barriers_minimal` empty; segment 4218
  `[3390.6, 7998.1]` 4607.5 m straddling, `access_bt = 1`).
- **Discovered FINA/PARS/PCEA carry no salmon/ST** (Peace, above Bennett dam) — the plan's
  item (d) "salmon (CO) ≤ tolerance" would be vacuous there. Swept all persisted WSGs and
  picked **LKEL** (smallest with ST + salmon: BT 401 / ST 365 / CO 328 km; pre-fix already
  clean) as the no-regression sentinel.
- Wrote `data-raw/accessible_km_fix_validate.R` (read-only, exits non-zero on any breach):
  parity sweep over {FINA,PARS,PCEA,LKEL} × 8 species with a `both-present` assert gate,
  plus 4 structural checks on the canonical blk 359209845. Matches `wsg_run_one.R` conn
  recipe + `LNK_LOAD=loadall` guard.
- **Confirmed FAILS pre-fix** (exit 1, 7 checks): FINA/PARS/PCEA BT parity + all 4 FINA
  structural; LKEL sentinel passes; bcfp-only SK correctly excluded.
- `lintr`: only house-style hanging-indent nits (siblings in `data-raw/` share them;
  `lint_package()` doesn't scan `data-raw/`). No line-length breaches.
- Next: Phase 2 — the one-file fix at `lnk_pipeline_prepare.R:592-593` (union raw `model_tbl`
  instead of `frs_barriers_minimal`-reduced `_min`), then re-run + re-validate.
