# Code-check review — #310 Phase 3 (bundle data), round 3

Reviewed the staged diff (17 files) against HEAD 83dfe16. The brief was one mechanism: a
fact stated in more than one place, with nothing tying the copies together. For every number
or set this diff restates, the source of truth was read directly:
`R/lnk_rules_build.R`, the staged dimensions CSVs, the staged rules.yaml files, and fresh at
**v0.39.0** (`git show v0.39.0:…`). The local fresh checkout is at v0.40.0, so its working
tree was not used.

## Findings

- **[fragile]** inst/extdata/configs/dictionary_dimensions.csv, `rear_lake_connected_distance_max`
  row — the dictionary says "fresh keeps a lake **(or reservoir)** in the lake_rearing
  bucket". That is wrong for the pinned fresh.
  - fresh v0.39.0 builds the bucket predicate from `whse_basemapping.fwa_lakes_poly` only
    (`R/frs_habitat_predicates.R` ~L205-209, `build_wb_pred(lake_rule, "whse_basemapping.fwa_lakes_poly")`).
  - `.frs_waterbody_tables("L")` (lakes + `fwa_manmade_waterbodies_poly`) feeds only the
    main `rearing` rule compiler.
  - So a reservoir's lines can rear through the L rule, but a reservoir is never
    `lake_rearing`, and this connection test never touches it.
  - This branch's own unstaged RUNBOOK text says the opposite of the dictionary: "Its
    `lake_rearing` bucket reads lakes only (fresh v0.39.0), so reservoir lines rear but are
    never `lake_rearing`."
  - The two copies already disagree before the commit lands. Fix: drop "(or reservoir)".
    Optionally add that reservoirs rear through the L rule but have no bucket.
  - Smaller point in the same sentence: "or upstream traced down mainstem lines" does not
    say that the upstream case is also capped at the distance. In fresh it is: case 3 traces
    down from each spawning cluster with `distance_max`. The README wording ("within 10 km
    up- or downstream") is the unambiguous one.

- **[fragile]** research/habitat_thresholds.md:1173 (the #311 section of the file this diff
  edits) — it still says, in the present tense, "**Floors in `default`:** 1 ha for BT, CH, RB,
  ST and WCT; 0.5 ha for CO."
  - This diff blanks CO's `rear_wetland_ha_min` (and `rear_lake_ha_min`), so CO no longer
    has a floor.
  - The new #310 paragraphs a hundred lines below do not reconcile it, so the file now holds
    two contradicting statements about CO.
  - The same staleness, outside this file:
    - `inst/extdata/configs/default/README.md:9` still says "CO 0.5 ha" in the staged
      tree. The fix exists but is **unstaged**, so this bundle-data commit would ship the
      bundle's README describing the old data.
    - `research/default_vs_bcfishpass.md:59, 268, 287` still say CO 2 ha / 0.5 ha.
    - NEWS.md:970-971 is a historical release note and is fine.
  - Fix:
    - add an "*Update 2026-10-07 (#310):* CO has no floor" note at line 1173, in the style
      already used at line 1140;
    - stage the README hunk with this commit;
    - add a one-line update note to the `default_vs_bcfishpass.md` CO lines.

- **[fragile]** research/habitat_thresholds.md, new #310 paragraph "Hectares and centreline
  km…" — "RB, CT and DV have `cluster_rearing = FALSE`, so their lake centreline km follow no
  spawning test at all."
  - The paragraph just above it says CT and DV get no rules at all: they have no thresholds
    row, which is true for all four `default*` thresholds CSVs and fresh's own.
  - So CT and DV have no lake km. The sentence implies they do.
  - The unstaged RUNBOOK hunk repeats the same three-species list.
  - Fix: say RB only, or "RB (and CT/DV, if they ever gain rules)".

## Restatements checked and found consistent

- **Dictionary `rear_lake`, lake edge set** `[1000, 1100, 1200, 1250, 1300, 1350, 1400, 1450, 1475]`:
  - matches `lake_edges` in `R/lnk_rules_build.R:225-227`;
  - matches every staged rules.yaml (default, both variants and the top-level file; 7 L
    rules each);
  - the 1250 / 1350 descriptions match `fwa_edge_type_codes` (both are "Construction line,
    double line river").
  - Round 1's finding is fixed.
- **Dictionary `rear_lake`, `thresholds: false`:** emitted on every additive L rule.
- **Dictionary `rear_lake`, "lake and reservoir polygons":** correct for the rule (fresh
  `.frs_waterbody_tables("L")`).
- **Dictionary `rear_wetland_connected_distance_max`,** "first W rule = the polygon rule, not
  the floored 1050/1150 rule after it":
  - correct for floored species, where the carve-out is a W rule emitted after the polygon
    rule;
  - correct for CO, where the carve-out is now an untyped edge rule emitted before it
    (rules.yaml CO hunk).
- **Retired rows** (`rear_requires_connected`, `rear_connected_distance_max`):
  - "ignored when empty, stops when set" matches the builder at L118-128.
  - "fresh >= 0.37.0 refuses …" matches fresh: `.frs_validate_rear_connected` landed in
    f7dd03e, first tagged v0.37.0. The per-rule check refuses non-L/W rear rules.
- **"Must be > 0"** matches `read_cdm()` (finite, > 0).
- **"Refused for … SK, KO"** matches the builder at L263-268.
- **Distance 10000:**
  - dims cells: BT, CH, CO, ST, WCT, CT, DV and RB both columns; GR lake only; CM, PK, SK
    and KO blank, in all four CSVs;
  - rules: 13 stamps (7 L, 6 W), which matches `progress.md`'s "13 connection stamps (7 L,
    6 W)";
  - research and README say "10,000 m / 10 km".
- **Research species list** "BT, CH, CO, GR (lakes only), RB, ST and WCT" matches the
  rules.yaml species carrying the stamps.
- **Research "CT and DV … no row in the bundle's thresholds CSV":** true for `default`,
  `default_extrabreaks`, `default_rearbreaks`, `default_tuned` and fresh's own CSV. The
  top-level rules.yaml has no CT/DV either.
- **Research "only the bucket is filtered"** matches fresh v0.39.0's `frs_habitat()` docs:
  "Only the bucket flag is filtered … `rearing` is unchanged".
- **Research cluster-pass wording** ("spawning anywhere upstream, no distance; downstream
  within the bridge limits") matches `.frs_cluster_both` phase 2 (`FWA_Upstream`, no cap)
  and phase 3 (downstream trace with bridge gradient and distance).
  `default/parameters_fresh.csv` has `cluster_direction = both` for the clustered species.
- **CO unfloored:**
  - the builder falls back to the thresholds CSV. CO `rear_lake_ha_min` is NA in the
    `default` thresholds CSV and in fresh's;
  - staged CO L and W rules carry no `lake_ha_min` / `wetland_ha_min` in any of the four
    rules.yaml;
  - the dims notes say "No lake or wetland size minimum".
- **Provenance:**
  - for each of default, default_extrabreaks and default_rearbreaks, the sha256 of the
    staged `rules.yaml` and `dimensions.csv` equals the `checksum:` in the staged
    `config.yaml`;
  - `generator_sha` 83dfe16 is HEAD, and `R/lnk_rules_build.R` has no uncommitted changes;
  - the rules.yaml `shape_checksum` is unchanged, which is correct because
    `.lnk_shape_fingerprint` hashes line 1 only;
  - the dims `shape_checksum` changed with the header.
- **Bundle test literals:**
  - BT/CH/CO/GR/RB/ST/WCT, GR without W, CT/DV NULL, SK/KO with no `requires_connected`, CO
    unfloored: all match the staged default rules.yaml;
  - the test's committed-vs-build comparison makes it the tie for that file. It does not
    tie the variants or the top-level rules.yaml to their builds; round 1 verified those by
    hand.
- **`task_plan.md` Phase 3 checkboxes:** the work they name is present in the diff.

---

## Triage (parent session)

All three fixed: the dictionary row drops "(or reservoir)", states the upstream cap and says the bucket reads lakes only; CO's old floors carry update notes (`habitat_thresholds.md` #311 section, `default_vs_bcfishpass.md` ×3) and the default README hunk ships with this commit; "RB, CT and DV" → "RB" in research and RUNBOOK. Round 1's finding was in the dictionary as well (the same mechanism: one fact written in two places with nothing tying them), but these are new places, not a defect inside round 1's fix. The reviewer listed every restated fact in the diff (edge set, retired rows, first-W rule, 13 stamps, species list, cluster wording, CO unfloored, provenance, test literals) and checked each against its source. With these fixes no restated fact contradicts its source, so the loop ends on that enumeration. A grep for `0.5 ha`, `CO 2 ha` and `RB, CT and DV` over the tracked docs finds only NEWS history.
