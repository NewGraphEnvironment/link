# Code-check review — #307 phase 2, round 4

Verdict: **no code bugs, no false number in the new #307 text.** Four low findings, all
outside the new #307 text: three are the round-3 mechanism showing up where earlier rounds
did not look, and one is a provenance gap.

## (1) Numbers, recomputed against the raw logs and CSVs

Every one of these matched.

- **Conversion: README table, research, RUNBOOK, CLAUDE.md, `default/README`,
  `default_tuned/README`.**
  - n 36,601 / 24,509 / 5,977. Medians 0.0214 / 0.04115 / 0.2010. q25 and q75 match after
    4-dp rounding.
  - Minima 0.021 / 0.041 / 0.20, matching `stamp.txt`, `20261006_width_mad_equivalent.txt`
    and `width_mad_conversion.csv`.
  - #302's file shows the 2 m median as 0.0412 (4 dp), which is consistent with 0.04115.
- **The CSV cells and the config.**
  - The CSV cells equal `width_mad_conversion.csv`.
  - `sha256(parameters_habitat_thresholds.csv)` = `b397dda1…`, matching `config.yaml`.
  - Against installed fresh 0.36.2, only the four MAD columns differ, so "fresh's copy,
    plus" is true.
  - `default_extrabreaks` and `default_rearbreaks` CSVs are byte-identical to `default`'s
    at `8cb4822`, so "as of v0.58.0" is true.
- **`cw` digests.** Main = branch for every species in NATR and ADMS.
- **`mad`, CH/CO/SK on ADMS.** The digests are unchanged (`1cd57b7b`, `7178003d`,
  `9616d0b5`).
- **madcheck stream-off-waterbody table.** All 12 numbers match.
- **Lake/wetland table.** All 20 numbers match, and KO stays at 345.4.
- **`*_out_nowb` and `null_nowb`.** Both are 0 in all 4 madcheck runs.
- **The `cw` → `mad` percentages, recomputed.** All match the docs:

  | WSG | BT spawn | BT rear | GR spawn | GR rear | KO spawn | RB spawn | RB rear |
  |---|---|---|---|---|---|---|---|
  | NATR | −4.47 | +1.45 | −5.40 | −4.80 | −0.83 | −4.68 | +3.28 |
  | ADMS | +1.67 | +5.00 | — | — | — | +0.75 | +3.57 |

- **KO after connect.** 120.2 km.
- **Main under `mad` after connect.** BT, GR and KO have 0. RB has 1,163.3 km (NATR) and
  52.9 km (ADMS).
- **"Only NATR and PARS hold all four species."** True per `wsg_species_presence.csv`.
- **RUNBOOK's −32 % / −76 % / −2.8 % RB.** Matches research l.1033-1035.
- **`8cb4822`.** It is "Release v0.58.0".
- **`--base=default` stops with "variant … equals default".**
  - `write_bundle()` compares character cells. Each #302 rung's `set` carries
    `*_mad_max=9999`, which is now `default`'s value.
  - It therefore stops at `habitat_variants_build.R:310-312`.
- **The literature bullets.** They match #302's Literature section (l.539-577). Woll's
  0.021 / 0.040 / 0.17 is correct.
- **NATR discharge gaps (README l.93-94).** I measured them on `fresh_default.streams`
  (docker fwapg):

  | edge | km | absent or NULL `mad_m3s` |
  |---|---|---|
  | 1000 | 9,389.8 | 0 |
  | 1100 | 9.5 | 0 |
  | 1250 | 235.9 | 0 |

  There are no 2000/2300 rows. The claim is true, but see finding 3.

## (2) Anchors

All four in-doc links resolve under GitHub slug rules:

- `#defaults-mad-ranges-converted-from-its-width-minima-307` → l.1059 heading.
- `#mad-discharge-ranges-for-bt-gr-ko-and-rb-302` (×2) → l.449.
- `#literature` → l.539. It is the file's only "Literature" heading, so there is no `-1`
  suffix.

None was added in CLAUDE.md, RUNBOOK, research/README or the log README.

## (3) Remaining instances of the round-3 mechanism

- **[low] research/habitat_thresholds.md:466-472, #302's "Verdict" table.**
  - The `default` column reads `NA` for all seven BT/GR/KO/RB cells. The present-tense
    header contradicts the current `default` CSV (0.041 / 0.021 / 0.20 / 0.041 / 0.041 /
    0.041 / 0.021).
  - The "Candidates (Phase 1)" table at l.484-490 has the same `default = NA` column. It is
    a dated Phase-1 snapshot, but it is labelled the same way.
  - Fix: qualify it as "`default` (v0.57)", or add "(0.041 since #307)".
- **[low] Superseded rearing-loss figures in two places.**
  - inst/extdata/configs/default_tuned/README.md:17, a line rewritten in this diff, says
    "At these values a `mad` group keeps … at least a third less for BT and four-fifths
    less for GR".
    - With the #305 fill (research l.1033-1034, which RUNBOOK and CLAUDE.md now quote) it
      is −32.0 % BT and −76.5 % GR.
    - So "at least a third" and "four-fifths" are both false now.
  - research/habitat_thresholds.md:475-477 (#302 Verdict prose) still gives "−36 % for BT,
    −82 % for GR and −4 % for RB" in present tense, with no pointer to the #305 figures.
  - Round 3 fixed the same staleness in RUNBOOK only.
- **[low, optional] RUNBOOK.md:713-714.**
  - The text: "BT keeps its wetland and 1050/1150-edge rearing in a `mad` group (ADMS:
    63.5 km, all inside waterbodies)".
  - 63.5 km is BT's `mad` rearing with no MAD range. It equals `20261006_adms_madcheck_main.txt`,
    BT `rear_km` 63.5.
  - Under today's `default`, ADMS BT `mad` rearing is 589.0 km (`*_madcheck_branch.txt`).
  - The sentence now hangs off "(BT, GR, KO and RB in `bcfishpass`)", but the figure was
    measured on `default` (#286). Say "measured on `default` before #307" or drop the
    figure.

## (4) Code

- **Tests.** I ran them in a copy of the tree with `NOT_CRAN=true` against the local DB.
  - `test-lnk_config.R` and `test-lnk_habitat_validate.R`: every test passes, none skipped.
  - That includes the new #307 tests and the bcfishpass-based #299 test.
- **Types.**
  - `expect_equal` on `rear_mad_max` compares an integer column (`read.csv`) against a
    double. testthat 3e tolerates that.
  - `run_validate_mad(mad_none =)` round-trips the CSV with `""` edge-type cells and `NA`
    intact.
- **mad_check.R.**
  - The added `*_out_nowb` and `null_nowb` columns are correct: a NULL `mad` or NULL
    threshold makes `NOT BETWEEN` NULL, so the row is not counted, and `null_nowb` /
    `*_no_th` cover those cases.
  - `zz_mad_th` is dropped only on success. That is acceptable in a scratch schema.

## Provenance gap (not a false claim)

- **[low] data-raw/logs/habitat_thresholds_307/README.md:93-94.**
  - The "9,390, 9 and 236 km" figures have no committed producer or log. Only the 1250
    figure is backed, by `discharge_fill_305/coverage_1250.csv` (NATR valued 235.9 km, no
    absent or null row).
  - The figures hold for the modelled network (`fresh_default.streams`), not the raw FWA
    table. `fwa_stream_networks_sp` has 50.4 km of NATR edge 1100, 40.9 km of it with
    NULL `mad_m3s`.
  - So a reader who re-derives the claim from the raw table gets the opposite answer.
  - Name the population (the modelled `streams`) and the query, or commit its output.
