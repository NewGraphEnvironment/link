# Review — #302 landing diff, round 3 (enumeration)

Scope: `diff_land3.patch`. Every quantitative or causal claim in the changed prose
(RUNBOOK §7, `default_tuned/README.md`, `config.yaml`, `research/README.md`,
`research/habitat_thresholds.md` header, top Verdict and the MAD section) read against
`data-raw/logs/habitat_score_302/*.csv` (held-out rows), `data-raw/logs/habitat_thresholds_302/*`,
`data-raw/habitat_score/{variants_302,wsg_roles_302}.csv`, `planning/active/literature.md`,
`data-raw/habitat_variants_score.R`, and read-only queries on docker fwapg `score302_*` +
`whse_basemapping.fwa_stream_networks_discharge`. Read-only throughout.

## Findings

- **[claim]** research/habitat_thresholds.md:678-679 — "What no rung restores. BT 1,444 km,
  GR 794 km and RB 296 km, used **at or above** the core rate." False for BT. The residual
  (`elevation_adjusted.csv`, class `bt_rear_mad_p10 removed`: 1,443.9 km, 205 obs) against
  the core rate (`bands_pooled.csv`, 1,266 / 8,674.5 km = 0.1459) is **0.97** unadjusted and
  **0.86** elevation-adjusted (238.0 expected). GR (1.06 / 1.11) and RB (2.30 / 1.67) hold.
  Say "at or near", or give the three ratios. Same paragraph, same mechanism: the km in both
  bullets ("BT 3,062 of 4,505", "BT 1,444") are the **rearing** ladders only, while the rate
  list beside them also cites BT and GR spawning; BT spawning is 1,961 of 2,752 restored and
  791 residual (at 1.51), GR spawning 1,769 of 2,241 and 472 (at 1.70). Label them "rear".

- **[claim]** research/habitat_thresholds.md:684-686 — "A review query found lines with no
  discharge … and water below P02 **for BT and RB**. **For GR it also found** 268 km above
  P02 that the rungs still drop." BT rearing has the same third class: 146 km at
  `mad_m3s` ≥ P02 still dropped. Re-queried this round (held-out, residual = `cw` rearing,
  not P10, no threshold step differs):

  | ladder | NULL MAD in wb / out | below P02 | ≥ P02, still dropped |
  |---|---|---|---|
  | BT rear | 455 / 45 | 798 | **146** |
  | BT spawn | 453 / 33 | 305 | 0 |
  | GR rear | 440 / 24 | 64 | 267 |
  | GR spawn | 439 / 24 | 9 | 0 |
  | RB rear | 138 / 40 | 118 | 0 |

  Round 2's table already showed the 146; the rewrite kept it for GR only. Write "For BT
  (146 km) and GR (268 km) it also found water above P02 that the rungs still drop."

- **[claim]** inst/extdata/configs/default_tuned/config.yaml:11-12 — "so a group put on the
  `mad` model keeps stream habitat for them (**less than `cw` gives**; see the research
  doc)". Unscoped, it covers spawning, and RB spawning at the landed 0.011 is **more** than
  `cw`: 6,181 km vs 5,522 on the held-out WSGs, +12 % (`habitat_change.csv`, `spawning_km`
  in `rb_rear_mad_p10` / `rb_spawn_mad_p05`). KO is unmeasured. README and RUNBOOK scope
  the same claim to rearing correctly; scope this one too ("less stream rearing than `cw`").

- **[claim]** research/habitat_thresholds.md:547-549 — "Both are consistent with the
  candidate 0.027 **and with the landed 0.078**. The landed value sits well above Isaak's
  summer floor, **so it would drop small streams that juvenile BT use elsewhere**." The
  second sentence contradicts the first and is inference stated as fact:
  - Isaak's 0.0057 is mean summer flow; literature.md l.81 and l.149-150 say its MAD
    equivalent "is larger (by an amount not known)", so "well above" is a cross-metric
    comparison that is not established.
  - Isaak's trim is a parameter choice made "because trout are rare in such small
    streams" (l.81, l.113); it documents no juvenile use between 0.0057 and 0.078.
  - The same size of gap is called "consistent" for RB at l.566-567 (landed 0.019 vs
    juveniles at 0.002 summer flow), so the two bullets apply different standards.
  Mark it as inference ("may drop"), or drop "and with the landed 0.078".

- **[claim, minor]** inst/extdata/configs/default_tuned/README.md:17 — "**Each** was then
  scored on held-out groups by a rule fixed before the run, and they are what that rule
  walked to. KO could not be scored." "Each" includes KO, whose 0.57 is the Phase 1
  candidate, not a walked value. "BT, GR and RB were then scored …".

- **[claim, minor]** research/habitat_thresholds.md:555-556 — "The candidate 0.095 is below
  it." "It" is the House 2021 site, known only by freshet flow (0.21–0.25) and receding flow
  at emergence (0.10–0.12); its MAD is "likely lower" (literature.md l.158-159), not known,
  so whether 0.095 admits that site is not established. The 0.96 claim is robust (MAD ≤
  freshet flow). "Argues lower … as for KO" also rests on one constructed NWT channel
  (l.86), weaker than KO's two BC streams; worth saying.

- **[note]** research/habitat_thresholds.md:648 — "The build ran clean". The invariants were
  asserted (`habitat_variants_build.R` l.28, l.379), but `build_20261002_full.log` l.46
  records "There were 50 or more warnings" during the base recompute (beside "KETL:
  streams_access CHANGED"), and nothing records what they were. Probably benign; one look
  before calling it clean.

- **[carried from round 2, minor]** RUNBOOK.md:705 — "species with no MAD thresholds (BT, GR,
  KO, RB) lose all stream habitat". The conditional is true and l.716 now qualifies it, but
  the parenthetical still names four species `default_tuned` gives ranges to. "(in
  `default` and `bcfishpass`: BT, GR, KO, RB)" would close it.

- **[carried note]** research/habitat_thresholds.md:3, :540 — "archived with #302's PWF";
  `literature.md` is still in `planning/active/`. True once `/planning-archive` lands in this PR.

## Elsewhere (item 3)

- RUNBOOK §7: nothing else false. l.705 above is the one standing line.
- research/habitat_thresholds.md outside the diff: Method, FISS, Scoring design and the
  #284 sections read correctly; l.452-454 is now scoped ("Before #302 … still none in
  `default` and `bcfishpass`").
- research/README.md: the new row is accurate; the other rows are unaffected.
- default_tuned/README.md: the table row ("…MAD, lake-area floor…") and "When you change a
  value" stay true; `lnk_rules_build()` bakes only `rear_lake_ha_min` (l.260-282;
  `default/rules.yaml` has no `mad`), so the inherited `rules.yaml` stays valid.
- CLAUDE.md: l.168 "One cell moved" and l.62 "one cell changed" sit in dated status sections
  (2026-09-26, 2026-09-29) and are true of that moment; no CLAUDE.md line asserts the
  current cell count. No #302 status entry yet (normal before archive).
- Bundles: `default`, `bcfishpass`, `default_extrabreaks`, `default_rearbreaks` are all 188 ×
  `cw`; `default` and `bcfishpass` carry NA MAD for BT/GR/KO/RB; `R/` reads no
  `*_mad_*` column. "Inert while every group is on `cw`" holds.

## Enumeration

Status: OK = population matches and the number reproduces. Held-out rows unless stated.

| # | file:line | claim | evidence (file / column / rows or query) | population | match |
|---|---|---|---|---|---|
| 1 | RUNBOOK.md:710-713 | bucket columns gated by rear size range: width under `cw`, discharge under `mad` | fresh e3a37f0 `build_wb_pred()` (round 1); local fresh `frs_habitat_predicates.R` l.214-216 | fresh code | OK |
| 2 | RUNBOOK.md:713-714 | no rear MAD range → polygon membership alone | same | fresh code | OK |
| 3 | RUNBOOK.md:714-715 | main predicate ignores `wetland_ha_min`; only `build_wb_pred()` applies it | fresh `utils.R` l.281 (lake only); predicates l.216 | fresh code | OK |
| 4 | RUNBOOK.md:716-717 | `default_tuned` carries; `default`, `bcfishpass` do not | the three thresholds CSVs | bundles | OK |
| 5 | RUNBOOK.md:717 | inert until a group is moved to `mad` | all method CSVs 188 × `cw`; no `*_mad_*` read in `R/` | bundles | OK |
| 6 | RUNBOOK.md:718-719 | at least −33 % BT, −82 % GR, −4 % RB | `habitat_change.csv` sums: 8,679/12,991, 825/4,705, 7,821/8,186 | held-out rearing | OK |
| 7 | README.md:15 | channel-width maxima, lake area, edge types unchanged (MAD removed from list) | CSV diff | bundle | OK |
| 8 | README.md:17 | `default` gives BT/GR/KO/RB no MAD; `mad` group loses all their stream habitat | `default` CSV; RUNBOOK §7 | bundle | OK |
| 9 | README.md:17 | landed values list, maxima 9999 | `default_tuned` CSV | bundle | OK |
| 10 | README.md:17 | no output moves while every group is `cw`; every group today | #5 | bundles | OK |
| 11 | README.md:17 | calibrated in 46 groups | `habitat_thresholds_302/stamp.txt` | calibration | OK |
| 12 | README.md:17 | each scored by a pre-fixed rule; values are what it walked to | `verdict.csv` `walked_value_of_record`; KO `candidates.csv` | BT/GR/RB vs KO | **minor (KO)** |
| 13 | README.md:17 | KO could not be scored | `power_windows.txt` KO non-calibration 0 | covered WSGs | OK |
| 14 | README.md:17 | at least a third less BT, four-fifths less GR rearing | #6 | held-out rearing | OK |
| 15 | README.md:17 | size and effort not separated | design (no size-split core) | — | OK |
| 16 | config.yaml:6-8 | BT 0.1349 scored and held | #284 record | — | OK |
| 17 | config.yaml:9-10 | BT/GR/RB spawn+rear, KO spawn; maxima open | CSV | bundle | OK |
| 18 | config.yaml:11-12 | keeps stream habitat, less than `cw` | `habitat_change.csv` spawning_km RB +12 % | held-out, spawn+rear | **mismatch** |
| 19 | config.yaml:12 | no output moves under `cw` | #5 | bundles | OK |
| 20 | habitat_thresholds.md:3 | BT/GR/RB scored; loosening refused past P10 except RB spawn; KO unscored | `verdict.csv` | held-out | OK |
| 21 | habitat_thresholds.md:21 | one gradient or width value moves | CSV diff | bundle | OK |
| 22 | habitat_thresholds.md:452-454 | before #302 none in any bundle; still none in `default`, `bcfishpass` | CSVs | bundles | OK |
| 23 | habitat_thresholds.md:466-472 | Verdict table: 7 values + "How" | `verdict.csv` walked_value_of_record, decision_of_record; KO `candidates.csv` | held-out | OK |
| 24 | habitat_thresholds.md:474 | every `*_mad_max` 9999 | CSV | bundle | OK |
| 25 | habitat_thresholds.md:475-476 | at least −33 % BT, −82 % GR, −4 % RB | #6 | held-out rearing | OK |
| 26 | habitat_thresholds.md:476-477 | size and effort not separated | design | — | OK |
| 27 | habitat_thresholds.md:539-540 | site evidence set beside candidates and landed values | bullets below | — | OK |
| 28 | habitat_thresholds.md:547-548 | neither BT source is MAD; both consistent with 0.027 and 0.078 | literature.md l.77-81 | literature | OK (but see 29) |
| 29 | habitat_thresholds.md:548-549 | landed well above Isaak's floor, so drops streams juvenile BT use | literature.md l.81, l.149-150 (MAD equivalent unknown) | cross-metric | **inference as fact; contradicts 28** |
| 30 | habitat_thresholds.md:555-556 | 0.96 above the House site; literature argues lower | literature.md l.86, l.158 | one constructed channel | OK (robust: MAD ≤ freshet) |
| 31 | habitat_thresholds.md:556 | candidate 0.095 below it | site MAD unknown | literature | **minor** |
| 32 | habitat_thresholds.md:566-567 | RB consistent with 0.0094, 0.011 and landed 0.019 | literature.md synthesis l.182-188 ("range of ST 0.02") | literature | OK |
| 33 | habitat_thresholds.md:623-625 | held-out outside the 55 `fresh_default` WSGs; 46 with discharge were calibration | DB: no held-out WSG in `fresh_default.streams` (55 WSGs); stamp.txt 46 | WSG sets | OK |
| 34 | habitat_thresholds.md:648 | build ran clean at `c2fed37` in 145 min, invariants asserted | `stamp_build.txt`; build log "145.3 min"; log l.46 "50 or more warnings" | build | OK / **note** |
| 35 | habitat_thresholds.md:649 | 20-WSG closure, LHAF pre-flighted, 18 variants | `closure.txt` (20), preflight log, `variants_302.csv` (18 + default) | build | OK |
| 36 | habitat_thresholds.md:650 | score under `--floor=expected` | `verdict.csv` floor_of_record all "expected" | score | OK |
| 37 | habitat_thresholds.md:654-662 | Results table: 7 rows × band km, found, expected, ratio, elevation-adjusted, decision | `verdict.csv` band_km, n_band, n_expected, density_ratio, decision_of_record; `elevation_adjusted.csv` threshold classes | held-out | OK |
| 38 | habitat_thresholds.md:664-667 | floors agree except RB spawn P10→P05 (10.1 expected, 8 found); both land 0.011 | `verdict.csv` decision vs decision_expected_floor, walked_value* | held-out | OK |
| 39 | habitat_thresholds.md:669-671 | anchor `removed` used at 0.36, 0.48, 0.50, 1.06 | `bands_pooled.csv` p10 removed/any | held-out, whole anchor band | OK |
| 40 | habitat_thresholds.md:675-676 | restored is most by length: BT 3,062/4,505, GR 3,099/3,893, RB 569/864 | bands_pooled removed − elevation_adjusted removed class | held-out, **rear ladders only** | OK numbers; **label** (in #1 finding) |
| 41 | habitat_thresholds.md:676-677 | restored use 0.08, 0.06, 0.36, 0.47, 0.42 | (240−205)/3,061.5 ÷ 0.1459 etc. | held-out, restored part | OK |
| 42 | habitat_thresholds.md:678-679 | residual 1,444 / 794 / 296 km used at or above core | `elevation_adjusted.csv` removed class: BT 0.97 / 0.86 | held-out residual | **mismatch (BT)** |
| 43 | habitat_thresholds.md:681-683 | split = bands_pooled removed − elevation_adjusted removed; first differing step labels | `habitat_variants_score.R` l.696-711 | method | OK |
| 44 | habitat_thresholds.md:683-684 | composition not written to any file | no such file in either log dir | — | OK |
| 45 | habitat_thresholds.md:684-685 | NULL-MAD mostly inside waterbodies; below P02 for BT and RB | query above (455/500, 440/464, 138/178 in wb) | held-out residual | OK |
| 46 | habitat_thresholds.md:685-686 | ≥ P02 still dropped: GR 268 km (implied GR only) | query: BT rear 146 km, GR 267 | held-out residual | **mismatch (BT omitted)** |
| 47 | habitat_thresholds.md:690-694 | rearing table, 12 cells + % | `habitat_change.csv` held-out sums | held-out rearing | OK |
| 48 | habitat_thresholds.md:696 | rearing rungs held spawning at P05 (0.027, 0.095) | `variants_302.csv` set | variants | OK |
| 49 | habitat_thresholds.md:697 | landed spawning tighter; BT/GR rearing clusters on spawning | CSV; Method l.523 `cluster_rearing = TRUE` | — | OK |
| 50 | habitat_thresholds.md:698-699 | P10 row a lower bound on loss at the landed pair (inference, "So") | monotone in spawning; never built | held-out | OK (stated as inference) |
| 51 | habitat_thresholds.md:699-700 | spawn P10 rungs: BT 10,712→10,215, GR 2,348→1,558 | `habitat_change.csv` `*_spawn_mad_p10` rearing_km | held-out | OK |
| 52 | habitat_thresholds.md:700 | RB P10 row is the landed pair | `variants_302.csv` rb_rear_mad_p10 set spawn 0.011 | variants | OK |
| 53 | habitat_thresholds.md:703-705 | stay at P10; bands at 0.12–0.46 of core ("larger water"); RB spawn 0.80 moves | `verdict.csv`; core query: BT 90 %, GR 100 %, RB 96 % of core km at MAD ≥ P10 | held-out | OK |
| 54 | habitat_thresholds.md:706-710 | GR adjusted 0.57/0.54 ≥ 0.5 → would take; BT and RB rear 0.12–0.16; RB spawn 0.80→0.93 | `elevation_adjusted.csv`; expected 99.8 / 96.0 ≥ 10 | held-out | OK |
| 55 | habitat_thresholds.md:711-716 | size/effort (marked inference); Biases notes surveys avoid big rivers | l.254 | — | OK |
| 56 | habitat_thresholds.md:717-721 | a third / four-fifths at P10; −18 / −50 at P05; vanish at P02; nothing switches | `habitat_change.csv` (P02 with spawn at P05) | held-out rearing | OK |
| 57 | habitat_thresholds.md:722-726 | KO 0.37–0.40, ≤ 0.283 > 0.105, 31 locations one WSG; clustering 3.2 and 1.1 km vs 2,037 / 2,523 | literature.md l.91-92; Candidates table; `bands_pooled.csv` p05/p02 removed | literature; held-out | OK |
| 58 | research/README.md:31 | row scope (CH/BT gradient+width; MAD for BT/GR/KO/RB) | section headings | — | OK |

58 claims checked (tables counted once each, every cell verified). Nothing else in the
changed prose states a number, a range, a comparison or a cause outside that set: the
remaining changed lines are file and issue references, the test file (verified to match the
CSV diff in rounds 1–2) and the R reformatting in `query_habitat_thresholds_mad.R`
(behaviour-preserving: same subsets, braces only).
