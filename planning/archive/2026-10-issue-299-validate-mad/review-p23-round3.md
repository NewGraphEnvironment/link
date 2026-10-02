# Review — #299 phase 2-3, round 3

Diff: `p23r3.diff` (branch vs main, R/ tests/ man/). fresh 0.36.2 (installed and checkout agree).
Tests: `test-lnk_habitat_validate.R` — FAIL 0 | WARN 0 | SKIP 0 | PASS 181 (local docker fwapg).

## Mechanism

Every miss label is read off *which relaxed predicate passes*, and the label assumes the
relaxed predicate differs from the real one in exactly the dimension the label names. A
relaxation is a textual substitution of a constant for a column, and a constant has no NULL
and carries no other condition. The cw ladder (`p_g`/`p_w`/`p_gw`) already encodes the
consequences as extra arms (`width_null` = `p_w & !p_g & is.na(size)`; `p_gw` ->
`fails_gradient_and_width` whatever the NULLs). The nomad ladder (`p_nomad`/`p_nomad_g`) is a
second, hand-written copy of that ladder: `p_nomad` is the analogue of `p_w` (the missing
range plays "width fails") and `p_nomad_g` the analogue of `p_gw`. Rounds 1 and 2 were both
places where the copy had fewer arms, or a wider substitution, than the original: round 1
substituted gradient too (`p_nomad` stood in for `p_gw` while labelled like `p_w`), round 2
lacked `p_w`'s `is.na(size)` companion arm. The second list of the same shape is
`no_range` in `.lnk_hv_stage_exprs()`, which is link's restatement of fresh's own condition
for writing `FALSE` in place of a size test (`size_inherit()`: `is.null(rng) && model == "mad"`);
the two agree only because every bundled stage that has rules also has a channel-width range.

## Enumeration

Measured, not reasoned: real predicates from the `default` bundle (`.lnk_hv_stage_exprs()`),
evaluated in Postgres over a synthetic grid — gradient {NULL, -0.02, 0.01, 0.20} x channel
width {NULL, 0.5, 5} x mad {NULL, 0.01, 1, 200} x edge {1000, 1050} x waterbody {none, a real
river polygon} — for BT, KO (no MAD range), SK (spawn range, no rear range), CO, CH (ranges),
each on cw and mad, both stages, then `.lnk_habitat_miss_reason()`. The nomad labels were
compared row by row with the cw label of the same species on the same segment with width
mapped to "fails" (0.5) where discharge is present and NULL where it is NULL. Probe:
scratchpad `r3/probe.R`, `r3/cmp.R`.

| arm | cw | mad, range (CO/CH, SK spawn) | mad, no range (BT, KO spawn, SK/KO rear) |
|---|---|---|---|
| `no_segment` | unchanged | same | same |
| `not_accessible` | unchanged | same | same |
| `post_predicate` (p) | unchanged | right | right: 1050/1150 `thresholds: false` and L/W polygon branches still pass (BT keeps wetland/lake rear) |
| `gradient_below_min` (p_g & !p_w & below) | unchanged | right (size present, gradient < 0) | unreachable: p_g == p (no non-size branch carries a gradient in any bundle); below-min + missing range reads `fails_gradient_and_width`, = cw's `p_gw` for below-min + failing width |
| `fails_gradient` (p_g & !p_w) | unchanged (NULL gradient lands here, pre-existing) | right, incl. NULL gradient, as cw | unreachable (same reason) |
| `width_null` (p_w & !p_g & NA size) | unchanged | right: size = `mad_m3s`; discharge NULL + gradient ok | unreachable via this arm (p_w == p) |
| `fails_width` (p_w & !p_g) | unchanged | right (below min and above max, e.g. CO rear mad 200 > 40) | unreachable |
| `fails_gradient_or_width` (p_g & p_w) | unchanged | right (no case in grid; same SQL shape as cw) | unreachable |
| `fails_gradient_and_width` (p_gw) | unchanged (NULL width + failing gradient lands here, pre-existing) | right, incl. NULL size/NULL gradient combos, as cw | unreachable |
| `width_null` (p_nomad & NA size) | NA on cw | NA (nomad cols NULL) | right: gradient ok + discharge NULL; matches cw `width_null` analogue on every row |
| `no_mad_threshold` (p_nomad) | NA | NA | right: gradient ok, discharge present (any value 0.01-200); analogue `fails_width` on every row; river polygons with discharge also read it (the R bypass is dropped under mad, so the range is the only obstacle) — correct |
| `fails_gradient_and_width` (p_nomad_g) | NA | NA | right: gradient NULL / negative / too steep, discharge NULL or present; analogue `fails_gradient_and_width` on every non-polygon row |
| `rule_excludes` | unchanged | right | right (KO/SK rear off-lake; 1050 off-polygon spawn) |

cw unchanged: the cw exprs are byte-identical to the pre-#299 construction (pinned by test),
`size` is `channel_width` for cw rows, nomad columns are NULL on cw, and classify's
`aoi_model` moves from `NA` to `"cw"` for an unlisted group, which `identical(, "mad")` reads
the same. The only cw-visible change is that classify now errors on a duplicate or non-cw/mad
method row, which fresh's classify raises on the same table anyway.

Other reaches checked: the `s.mad_m3s` join in `.lnk_hv_predicates` and the scalar subquery in
attach read the same table on the same key, and `linear_feature_id` is its unique PK (2,716,652
rows, 0 NULL), so neither fans out nor errors; `_nomad`'s open range `[0, 0]` adds a size gate
to lake/wetland rearing that the size-0 relaxation removes again, so SK/KO rear `p_nomad == p`.

## Findings

- **[severity: fragile]** R/lnk_habitat_validate.R:893-896 — `no_range` requires
  `!is.null(rng[["channel_width"]])`, a condition fresh does not have: fresh writes `FALSE` for
  any stage with no MAD range under mad (`size_inherit()`), channel-width range or not. For a
  stage with rules and a gradient but no channel-width range, cw classifies stream habitat on
  gradient alone and mad classifies none, yet the validator gives the nomad columns NULL and the
  miss reads `rule_excludes` instead of `no_mad_threshold`. The docstring's "(a stage with no
  stream habitat at all)" is only true when the rules are empty too. **Unreachable in every
  shipped bundle**: the only stages without a channel-width range are CM and PK rear, and their
  `rear:` is `[]` in all five `rules.yaml`. Matters only for a custom bundle; dropping the
  `channel_width` clause would make it follow fresh's rule (setting a `[0, 0]` range on CM/PK
  rear is harmless — `rear: []` compiles to `FALSE` either way).

No bugs found in the mad-path labels: every arm x model x NULL/negative/present combination
reads either the intended label or the cw analogue's label.
