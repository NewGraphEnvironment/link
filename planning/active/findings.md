# Findings — default MAD ranges for BT, GR, KO and RB, from its own width minima (#307)

## Issue context

**If done:** `default` on `mad` maps stream habitat for BT, GR, KO and RB, and comparing `cw` with `mad` inside `default` compares two measures of the same biological stream size. That is what the scenario projects need. **If never:** `default` + `mad` is empty for those species (lake and wetland only). Every comparison then has to go through `default_tuned`, and the contrast between biology and observation is lost.

## Approach

Convert `default`'s channel-width minima to MAD through the BC width-to-discharge relation #302 measured: median modelled MAD at a given width of 1.5 m → 0.021, 2 m → 0.041, 4 m → 0.20 m³/s. Woll et al. 2017's Alaskan relation gives nearly the same. The width minima are spawning 2 m (GR 4 m) and rearing 1.5 m. Maxima stay open (9999), as #302 decided.

| Species | Spawn min (m³/s) | Rear min (m³/s) | `default_tuned` (observed, #302) |
|---|---|---|---|
| BT | 0.041 | 0.021 | 0.078 / 0.078 |
| GR | 0.20 | 0.021 | 0.96 / 0.97 |
| KO | 0.041 | — (lake rearing only) | 0.57 |
| RB | 0.041 | 0.021 | 0.011 / 0.019 |

Check each value against #302's literature table (`research/habitat_thresholds.md`, "MAD (discharge) ranges", Literature):
- BT redds at 0.25–0.30;
- GR spawning at 0.21–0.25 freshet flow;
- KO spawning at 0.28–0.40;
- RB at ~0.1.

## Deliverables

- `inst/extdata/configs/default/parameters_habitat_thresholds.csv`: the eight cells.
- Re-derive the width-to-MAD medians with a script, so the numbers have a producer.
- A research section stating the rule, the values and the literature check.
- Rebuild one WSG and diff it: `cw` outputs unchanged; `mad` now non-empty for the four species.

## Not in scope

`default`'s existing MAD minima for CH, CO, SK and ST come from bcfishpass, and #302 could not trace most of them. CO spawning is 0.164, where this conversion gives 0.041. Changing them would move existing `default` outputs, so that is a separate decision.

Relates to #20, #302, NewGraphEnvironment/knowledge#29.


## Plan-mode exploration (2026-10-06)

- **The values.** `default/parameters_habitat_thresholds.csv` is byte-identical to fresh's copy.
  The width minima are spawn 2 m (GR 4 m) and rear 1.5 m. The #302 medians are in
  `data-raw/logs/habitat_thresholds_302/width_mad_equivalent.txt`: 1.5 m → 0.0214, 2 m →
  0.0412, 4 m → 0.2010. They came from an ad-hoc psql query that has **no producer
  script**.
- **The cells.** There are seven minima: BT ×2, GR ×2, KO spawn and RB ×2. KO rearing is
  lake-only, so it stays NA. Each minimum gets an open maximum of 9999, as in
  `default_tuned`. That makes **14 cells**, not the issue's "eight".
- **No rules rebuild.** `rules.yaml` embeds no MAD values; `lnk_rules_build()` reads only
  `rear_lake_ha_min` from thresholds. Regenerating it and confirming no diff is enough.
- **`default_tuned` is unaffected.** It ships its own full thresholds CSV.
- **Provenance.** `default/config.yaml` records this CSV as `source:
  https://github.com/NewGraphEnvironment/fresh` with fresh's checksum. After this change it
  is a link-edited copy, so `source`, `derived_from` and the checksums need updating. The
  test "inherited provenance verifies against the parent's files" catches a stale checksum.
  `audit_configs.R` §3c checks columns only, not values.
- **Two tests will break by design:**
  - `test-lnk_config.R:331`: "default_tuned differs from default only in the #284/#302
    cells". The maxima stop differing, and `default`'s column takes the new minima.
  - `test-lnk_habitat_validate.R:215`: "a species with no MAD range…" uses `default`'s BT.
    It moves to `bcfishpass`'s BT, which still has no range.
- **Evidence harness to reuse:** `data-raw/logs/params_method_286/`
  - `verify_classify.R`: setup → connect for one WSG;
  - `reclassify.R`: classify + connect with segmentation held fixed, optional
    `method_csv`;
  - `mad_check.R`: classify only, with fresh's MAD invariants.

  Full runs are not digest-reproducible (the PSCIS tie), so the diff has to be a
  reclassify on one prepared schema.
- **The WSG.** Only NATR and PARS carry all four species. NATR is 29k segments with 95 %
  discharge coverage; PARS is 37k segments. **NATR** it is.
- **Stale prose that names `default` as having no range:**
  - `default_tuned/config.yaml` description and `default_tuned/README.md`;
  - RUNBOOK §7 (~l.721);
  - `research/habitat_thresholds.md` l.453 and l.810;
  - CLAUDE.md status (#302 block).
- **#302 bundle regeneration.** `--step=bundles` with `--base=default` builds from
  `default`'s CSV, so a regenerated #302 bundle would now carry the new cells for
  non-focal species. Scores read only the focal species, so verdicts cannot move. Record
  it rather than engineer around it.


## Errors Encountered

| Error | Resolution |
|-------|------------|
