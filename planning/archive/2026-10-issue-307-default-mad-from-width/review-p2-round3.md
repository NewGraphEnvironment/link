# Code-check review — #307 phase 2, round 3

## Mechanism behind round 2's three findings

One fact — "which bundles carry a MAD range for BT, GR, KO and RB, and at what values" —
is restated by hand in a dozen documents. Each restatement was written from the
*intended* or *remembered* state (the #302 framing "`default` leaves them without one",
"same ranges", "keeps their stream habitat") rather than re-read from the artifact
(the CSVs, `width_mad_conversion.csv`, the `pipeline:` block) at the moment the CSV
changed. Nothing ties the prose to the CSV, so a cell edit leaves every sentence that
restates the old state reading as authoritative. Remedy is the karpathy §7 habit: grep
for the sentence repo-wide, not the file that was quoted.

## The three fixed sentences, checked against the files

1. `default_tuned/config.yaml` description: "stricter for BT, GR and KO and looser for RB".
   True: tuned BT 0.078/0.078 vs default 0.041/0.021; GR 0.96/0.97 vs 0.20/0.021;
   KO 0.57 vs 0.041; RB 0.011/0.019 vs 0.041/0.021 (both RB minima looser).
2. `default/README.md`: "this bundle sets no `discharge_fill`". True — `default/config.yaml`
   `pipeline:` block has no `discharge_fill` key (only `default_tuned` sets it).
   Values 2 m→0.041, 4 m→0.20, 1.5 m→0.021 match `width_mad_conversion.csv`
   (0.04115, 0.20103, 0.0214 floored to 2 s.f.). "fresh's copy, plus" is true: against
   installed fresh 0.36.2's CSV the only differing columns are the four MAD columns.
3. `dictionary_parameters_habitat_method.csv`: "BT, GR, KO and RB in bcfishpass; default
   and default_tuned carry ranges for them". True against all three CSVs.

## Findings

- **[low]** research/habitat_validation.md:55-57 — "`no_mad_threshold` is a `mad` miss the
  species' missing MAD range alone explains (BT, GR, KO, RB have none: ...)". Unqualified
  and now false for `default` (and `default_tuned`); only `bcfishpass` (and the two
  `default_*breaks` variants) still have none. Not in the "doc pass" file list, so it will
  be missed unless added. Same mechanism as round 2.
- **[low]** RUNBOOK.md:727-729 (working-tree edit) — "At the landed values a `mad` group
  keeps less stream rearing than `cw` (held-out: −36 % BT, −82 % GR, −4 % RB ...)". The
  preceding sentence now introduces two sets of values (`default`'s width-converted and
  `default_tuned`'s calibrated); "the landed values" reads as covering both, but these
  figures are `default_tuned`'s only. Also pre-#305: with the fill, CLAUDE.md / NEWS 0.58.0
  give −32 % BT, −76 % GR. Name the bundle (and preferably the post-fill figures).
- **[low]** inst/extdata/configs/default/README.md:26 and default_tuned/README.md:17 —
  "rearing 1.5 m → 0.021" in a sentence listing BT, GR, KO and RB reads as KO rearing
  getting 0.021; KO has no rear MAD range (`rear_mad_min` NA, lake rearing only; the test
  at test-lnk_config.R:366 says so). The `default_tuned/config.yaml` description gets this
  right ("BT, GR and RB spawning and rearing and KO spawning").
- **[low]** inst/extdata/configs/default_rearbreaks/ and default_extrabreaks/ — both are
  described as "Experimental variant of the `default` config" changing only breaks, with
  `extends: ~` and their own `parameters_habitat_thresholds.csv`, which still has NA MAD
  for BT/GR/KO/RB. They now silently differ from `default` in eight MAD cells. Inert while
  every group is on `cw`, but a default-vs-variant comparison on a `mad` group would
  attribute a MAD difference to breaks. Either sync them or say so in their description.
- **[low]** data-raw/query_habitat_thresholds_mad.R:3-4 — header "for the species with no
  MAD range (link#302)" — historical framing, now untrue of `default`; a one-word "then"
  or "in bcfishpass" fixes it. (query_width_mad_equivalent.R:6-8 already says "before #307".)
- **[low]** inst/extdata/configs/default/README.md:5-11 — "Documented departures from
  bcfishpass" does not list the new one: `default` now gives BT, GR, KO and RB MAD minima
  that `bcfishpass` leaves NA.

Verified correct, no action: data-raw/habitat_score/README.md:36-40 (the `*_mad_max=9999`
`set` cells now equal `default`'s 9999, so `write_bundle()` stops with "variant … equals
default: … is already 9999" — habitat_variants_build.R:310-312; 8cb4822 is "Release
v0.58.0"); RUNBOOK.md:710 and :721-726; dictionary_parameters_habitat_thresholds.csv
(generic NA semantics only); research/habitat_thresholds.md:452-455 and :811-813.

## For the doc pass (not defects of this diff)

- CLAUDE.md:89-92 — heading and lead "`default_tuned` now carries mean-annual-discharge
  ranges for the four species `default` leaves without one" — `default` no longer leaves
  them without one.
- CLAUDE.md:80 — "`--step=bundles` writes bundles only; #302's regenerate byte for byte."
  No longer true after #307 (the habitat_score README now says they regenerate at
  v0.58.0 and not after).
- NEWS.md — no entry yet for #307. Past entries (0.57.0 line 19 "`default` gives these four
  none"; line 32 "for the species that have none (BT, GR, KO, RB)"; line 40) are historical
  release notes and accurate for their release; leave them, but the new entry should state
  the change of `default`.
- research/habitat_thresholds.md:455 — links to
  `#defaults-mad-ranges-converted-from-its-width-minima-307`, a heading that does not yet
  exist in the file (grep finds no `#307` heading). Broken anchor unless the doc pass adds
  that section with exactly that slug.
- research/README.md:31 — index row describes the MAD ranges as #302 / `default_tuned`
  only; add #307's `default` conversion when the section lands.
