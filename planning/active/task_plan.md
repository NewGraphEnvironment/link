# Task: default MAD ranges for BT, GR, KO and RB, from its own width minima (#307)

**If done:** `default` on `mad` maps stream habitat for BT, GR, KO and RB, and comparing `cw` with `mad` inside `default` compares two measures of the same biological stream size. That is what the scenario projects need. **If never:** `default` + `mad` is empty for those species (lake and wetland only). Every comparison then has to go through `default_tuned`, and the contrast between biology and observation is lost.


## Phase 1 — Producer for the width-to-MAD medians
- [x] `data-raw/query_width_mad_equivalent.R`:
  - reproduces #302's query: `fresh_default` stream segments on edges
    1000/1100/2000/2300 outside waterbodies, modelled `channel_width` within ±0.1 m of each
    width minimum, `mad_m3s` joined from `fwa_stream_networks_discharge` on
    `linear_feature_id`;
  - takes the bins from `default`'s CSV (the distinct spawn/rear width minima of BT, GR,
    KO and RB), not hard-coded;
  - writes n, q25, median and q75 plus the converted minimum (floored to 2 significant
    figures, #302's rule) to `data-raw/logs/habitat_thresholds_307/`:
    `width_mad_equivalent.csv` (per bin), `width_mad_conversion.csv` (per species x
    stage), and `stamp.txt`.
- [x] Run it on local docker fwapg. Compare with #302's 0.0214 / 0.0412 / 0.2010. If any
  converted value differs from 0.021 / 0.041 / 0.20, the script's value wins, and the
  research section says why.

## Phase 2 — The cells, provenance, tests
- [x] Set the 7 minima (BT 0.041 / 0.021, GR 0.20 / 0.021, KO 0.041, RB 0.041 / 0.021)
  and their 7 maxima (9999) in `inst/extdata/configs/default/parameters_habitat_thresholds.csv`.
  Keep the file's quoting and NA style byte-compatible.
- [x] Update `default/config.yaml` provenance:
  - `source: link (fresh's copy plus MAD ranges converted from width minima, link#307)`;
  - keep fresh's `upstream_sha`/`version` in `derived_from`;
  - recompute `checksum` with the `lnk_config_verify` algorithm. The shape is unchanged.
- [x] Build `default`'s rules to a tempfile from the old and the new CSV and compare
  them. Do not regenerate in place: the `# Generated:` date line would move the
  provenance checksum.
- [x] Tests:
  - rewrite `test-lnk_config.R:331` for the new default/tuned difference set (7 minima
    plus BT `rear_gradient_max`);
  - add a test pinning `default`'s 14 MAD cells and asserting that every `*_mad_min` set
    by #307 has its `*_mad_max` set (no half-open range);
  - repoint `test-lnk_habitat_validate.R:215` at `bcfishpass`;
  - give `run_validate_mad()` a `mad_none` option so the #299 end-to-end test keeps a
    species with no range;
  - add a #307 case on `default`'s own BT range (plan review, finding 1).
- [x] Full `devtools::test()` and fix any other fallout (each fix stated, none papered over).
  FAIL 0 | WARN 16 | SKIP 0 | PASS 2449. The fallout was the #299 fixture test, fixed with `mad_none`.

## Phase 3 — Rebuild NATR (and ADMS as the CH/CO/SK control) and diff
Scratch schema `zz307_natr` on local docker fwapg; nothing persisted. Main runs from a
worktree at `origin/main`, the branch from a frozen copy. Logs and copied scripts go in
`data-raw/logs/habitat_thresholds_307/`.
- [x] `verify_classify.R` setup → connect NATR and ADMS under `default` (prepares
  segmentation once). NATR holds only BT, GR, KO and RB; ADMS adds CH, CO and SK, which
  must not move.
- [x] `cw`: run `reclassify.R` on main and on the branch, and compare per-species digests.
  **Expect identical for every species.**
- [x] `mad`, with `method_natr_mad.csv` (NATR on `mad`):
  - run `reclassify.R` on main and on the branch;
  - **expect** BT/GR/KO/RB stream spawning and rearing km to go 0 → non-zero, and every
    other species' digest to be unchanged.
- [x] `mad_check.R` on **main and on the branch**:
  - stream km off waterbodies (`*_nowb`) is the measure of 0 → non-zero;
  - the invariant holds on stream segments (`*_out_nowb` and `null_nowb` = 0);
  - predict, then measure, the shrink in `lake_rearing` and `wetland_rearing` for BT,
    GR and RB: fresh gates the bucket columns on the rear range once one exists (plan
    review, finding 6).
- [x] Note that `default` has no `discharge_fill`, so NATR's edge-1250 main stems with no
  value still drop under `mad`. Report the NULL-discharge km rather than fix it (out of
  scope).
- [x] `README.md` in the log directory: method, stamp, results table.

## Phase 4 — Research, docs, NEWS
- [ ] New section in `research/habitat_thresholds.md`, "`default`'s MAD ranges, converted
  from width (#307)":
  - the rule;
  - the values table (with `default_tuned`'s beside them);
  - the literature check against #302's table: BT redds 0.25–0.30, GR 0.21–0.25 freshet,
    KO 0.28–0.40, RB ~0.1, and Woll 2017 at 0.021 / 0.040 / 0.17;
  - the NATR before/after;
  - the out-of-scope note on CH/CO/SK/ST (CO spawn 0.164 vs a converted 0.041).

  Also update the header line (Verified / Issues / Produced by) and fix the stale l.453
  and l.810 claims.
- [ ] Update the `default_tuned` `config.yaml` description and `README.md`, RUNBOOK §7
  (~l.721), and the CLAUDE.md status (new #307 block; correct the #302 block's "the four
  species `default` leaves without one").
- [ ] Correct the remaining stale prose: `default/README.md:26` ("identical to fresh's
  copy"), RUNBOOK l.710-711, `data-raw/habitat_score/README.md:36` (pin #302's ladders to
  v0.58.0 `8cb4822`: `--base=default` now stops with "variant equals default").
- [ ] State a literature decision rule before the check. These are width-equivalence
  floors, and literature values describe typical use, so a mismatch reports but does not
  move a value. Note that RB is now stricter in `default` than in `default_tuned`.
- [ ] State that `default_extrabreaks` and `default_rearbreaks` stay frozen on the old
  CSV: they are cw-only segmentation experiments.
- [ ] NEWS.md entry, including that `config_hash` moves for `default` and
  `default_tuned` (the version bump is left to `/gh-pr-merge`).
- [ ] `lnk_config_verify(lnk_config("default"))` and `("default_tuned")` are clean;
  `audit_configs.R` §3c is clean.

## Validation
- [ ] Tests pass (`devtools::test()`), and `lintr::lint_package()` is clean on touched files.
- [ ] `/code-check` clean on each commit.
- [ ] PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion, with a Measurement + Evidence archive README.


## Verification (end to end)
1. `width_mad_equivalent.csv` reproduces 0.021 / 0.041 / 0.20, or explains the shift.
2. NATR `cw` digests are identical main vs branch, for all species.
3. NATR `mad`: BT/GR/KO/RB stream km go from 0 to non-zero; other species unchanged; the
   `mad_check` invariants hold.
4. `rules.yaml` has no diff, and provenance verifies for both bundles.
5. The full test suite is green.
