# Review — #302 landing diff, round 2

Scope: `diff_land2.patch`, with the rewritten prose read against
`data-raw/logs/habitat_score_302/{verdict,bands_pooled,elevation_adjusted,habitat_change}.csv`,
`planning/active/literature.md`, and read-only queries on docker fwapg `score302_*`
(+ `whse_basemapping.fwa_stream_networks_discharge`). Held-out WSGs pooled throughout,
as the doc does.

## Verified clean

- Results table: every band km, found, expected, ratio, elevation-adjusted ratio and
  decision matches `verdict.csv` / `elevation_adjusted.csv` (held-out rows).
- "The two floors agree … except RB spawning P10→P05", "Both land 0.011; they differ only
  in whether it counts as scored": matches `decision` / `decision_expected_floor` /
  `walked_value*`.
- Anchor `removed` ratios 0.36 / 0.48 / 0.50 / 1.06 (`bands_pooled.csv`; BT rear is
  0.36500, so 0.36 is correct).
- Habitat table: held-out sums reproduce exactly (BT 12,991 / 8,679 −33.2 % / 10,712
  −17.5 % / 13,235 +1.9 %; GR 4,705 / 825 −82.5 % / 2,348 −50.1 % / 5,022 +6.7 %;
  RB 8,186 / 7,821 −4.5 % / 8,853 +8.2 % / 9,849 +20.3 %).
- Lower-bound paragraph: rearing rungs' spawning km equal the `*_spawn_mad_p05` rung's
  (BT 0.027, GR 0.095); `bt_spawn_mad_p10` rearing 10,215, `gr_spawn_mad_p10` 1,558;
  `rb_rear_mad_p10` spawning equals the 0.011 rung, so RB's row is the landed pair; RB
  rearing does not respond to spawning (all `rb_spawn_*` rungs 8,853). "Lower bound" is
  stated as an inference ("So"), which is what it is.
- "Most of it is small water that P05 and P02 add back": restored share 68 % (BT rear),
  71 % (BT spawn), 80 % (GR rear), 66 % (RB rear).
- `elevation_adjusted.csv`'s `removed` class is the residual (1,444 / 791 / 794 / 296 km);
  the parenthetical says so correctly.
- Clustering bullet: 3.2 and 1.1 km held-out (`bands_pooled.csv`), against 2,037 / 2,523.
- KO bullet matches literature.md l.91–92 (0.369–0.403; ≤ 0.283 and > 0.105); 31
  locations matches the Candidates table.
- "What it costs" bullet (a third, four-fifths, −18 %, −50 %, losses vanish at P02) holds.
- RUNBOOK new bullet: `default`, `bcfishpass` (and both `default_*breaks`) carry no MAD for
  BT/GR/KO/RB; percentages correct with "at least". README / config.yaml wording holds
  (46 calibration groups, a third / four-fifths, "less than `cw` gives").
- `test-lnk_config.R` passes against the source tree (`NOT_CRAN=true`, load_all).

## Findings

- **[claim]** research/habitat_thresholds.md:666-668 — "Most of it is small water that P05
  and P02 add back, and fish use **that part** sparsely. The P10 → P05 and P05 → P02 bands
  above are used at 0.15 and 0.03 … for BT rearing, and at 0.14 and 0.24 for RB rearing."
  Same defect class as round 1: the cited ratios are for the whole ladder bands, which are
  not "that part". Each loosening band also holds habitat `cw` never had (queried, held-out,
  `score302_default` rearing vs the band):

  | band | km in `cw` rearing | km not in `cw` |
  |---|---|---|
  | BT rear P10→P05 (2,037) | 1,705 | 332 |
  | BT rear P05→P02 (2,524) | 1,357 | 1,167 |
  | RB rear P10→P05 (1,032) | 398 | 634 |
  | RB rear P05→P02 (995) | 171 | 824 |

  The part of the anchor's removed band that P05/P02 restore is derivable from committed
  files (`bands_pooled` anchor removed minus `elevation_adjusted` residual, same core):
  BT rear 3,062 km, 35 obs → **0.08**; BT spawn 1,961, 20 → 0.06; GR rear 3,099, 90 →
  0.36; **RB rear 569 km, 32 obs → 0.42**. For BT the conclusion survives (0.08); for RB
  the cited 0.14 / 0.24 understate the restored part's use 2–3x, the bands cited are ~70 %
  non-`cw` habitat, and "sparsely" for 0.42 (beside RB's whole removed band at 1.06) is a
  stretch. Either cite the restored-part rates with their derivation or drop "that part".
  Also minor: "the … P05 → P02 bands **above**" — no P05→P02 rearing row is in the table
  above (only RB spawning's); the 0.03 and 0.24 are from `verdict.csv`.

- **[claim]** research/habitat_thresholds.md:668-669 — "What no rung restores is the rest:
  lines with no discharge (mostly inside waterbodies) and water below P02." Stated as a
  measurement for all ladders; no committed file contains this decomposition (it came from
  a round-1 reviewer query for BT rear only), and for GR it is wrong by a third. Residual,
  held-out, by `mad_m3s` against the ladder's P02 and `waterbody_key`:

  | ladder | NULL MAD (in wb / out) | below P02 | **≥ P02, still dropped** |
  |---|---|---|---|
  | BT rear (1,445 km) | 455 / 45 | 799 | **146** |
  | GR rear (795 km) | 440 / 24 | 63 | **268 (34 %)** |
  | RB rear (295 km) | 138 / 40 | 117 | 0 |

  GR's 268 km sit above every rung's discharge cut and are dropped by something else
  (consistent with rearing clustering on spawning held at 0.095, not verified). "Mostly
  inside waterbodies" holds for the NULL-MAD part in all three. Name the third class, or
  scope the sentence to BT/RB, and commit the query or its output if it stays a measured
  claim.

- **[claim]** research/habitat_thresholds.md:687-689 — "**the loosening bands are not
  habitat.** Fish use the smaller streams P05 adds at 0.12–0.46 …". RB spawning P10→P05 is
  used at **0.80** and was taken as habitat (the same bullet then says RB spawning moves to
  P05). The range silently omits the one step that passed, and the bolded lead contradicts
  it. Say "except RB spawning (0.80)".

- **[claim]** research/habitat_thresholds.md:690-692 — "Elevation explains part of GR's gap,
  **not BT's or RB's** … The BT and RB steps stay at 0.12–0.16." RB spawning moves
  0.80 → 0.93 (P10→P05) and 0.20 → 0.23 (P05→P02) under elevation adjustment — a larger
  shift than GR spawning's 0.46 → 0.54. True for BT and RB *rearing* only; scope it so.

- **[claim]** research/habitat_thresholds.md:693-695 — "The core is the bigger water,
  **where sampling concentrates**" is stated as fact with no measurement behind it in this
  section or its logs (the next sentence concedes "Nothing here measures how much"). The
  doc's own Biases section (l.254) says sampling "clusters near road access and **avoids
  big rivers**". The core here is MAD ≥ P10 (BT 0.078 m³/s), which is not big-river, so
  the two may not conflict, but the concentration of sampling on the core is an inference;
  phrase it as one ("plausibly where sampling concentrates").

- **[claim, now false]** research/habitat_thresholds.md:452-454 (section intro, unchanged by
  the diff) — "BT, GR, KO and RB carry no MAD range **in any bundle** … so in a `mad` group
  fresh fails every inheriting stream rule". After this diff `default_tuned` carries them.
  Scope to `default` and `bcfishpass`, or "before #302". Same shape, milder, at
  RUNBOOK.md:705 ("species with no MAD thresholds (BT, GR, KO, RB) lose all stream
  habitat"): true of `default`/`bcfishpass`, and the next bullet now qualifies it, but read
  alone it names four species that `default_tuned` gives thresholds to.

- **[claim, minor]** research/habitat_thresholds.md:538 ("Site evidence brackets the
  candidates"), 545 ("consistent with 0.027"), 560 ("Consistent with 0.0094–0.011") — these
  assess the P05 candidates, not the landed values, and the Verdict above now lands P10.
  Not false as written, but one landed value sits where the doc flags only KO: GR spawning
  lands 0.96, while the only small-stream GR spawning site (House 2021) spawned at
  0.21–0.25 m³/s freshet flow, MAD likely lower (literature.md l.86). The Results flag "the
  literature argues lower" for KO only; the same reading applies to GR's landed value
  (weak evidence: one constructed NWT channel). RB rear lands 0.019, outside the
  "0.0094–0.011" the literature bullet calls consistent.

- **[note]** research/habitat_thresholds.md:3 and :538 call `literature.md` "archived with
  #302's PWF"; it is in `planning/active/` until `/planning-archive` runs. True only once
  the archive step lands in this PR.
