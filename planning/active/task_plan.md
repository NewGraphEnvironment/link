# Task: Tighten default spawn edge_types (v0.10.0)

Default bundle currently emits `edge_types: [stream, canal]` for spawn (and
rear-stream) predicates. The `stream` category expands to FWA edge_type
codes `1000, 1050, 1100, 1150` — which **includes stream-through-wetland**
(`1050/1150`). Biologically borderline: these are streams flowing through
wetland zones, often lower-flow-energy and unlikely to retain spawning
gravel. The `canal` category similarly includes `2100` (rare double-line
canal).

`lnk_rules_build()` already supports an `edge_types = "explicit"` mode
that emits integer codes `[1000, 1100, 2000, 2300]` — bcfishpass's
20-year-validated convention. The bcfishpass config already uses it. The
default config currently does not.

Switch the default config to `edge_types = "explicit"`. After this lands,
default and bcfp bundles use the same edge_type set everywhere — which is
the right end state.

## Goal

Switch default `data-raw/build_rules.R` calls to use `edge_types = "explicit"`,
regenerate the two default YAMLs, and confirm:

- Spawn predicates no longer include `1050/1150/2100`.
- Rear-stream predicates no longer include `1050/1150/2100`. The dedicated
  wetland-rear rule still captures `1050/1150` for the `wetland_rearing`
  flag (it's emitted as a separate rule per species with `rear_wetland=yes`).

Note on user's framing ("lake and wetland edges for spawn"): the default
spawn rules do NOT actually include lake (`1500/1525`) or wetland-centerline
(`1700`) edges — those would only come from a `waterbody_type = L/W` rule
which the dimensions CSV doesn't generate for spawn. The borderline
edges are `1050/1150` (stream-thru-wetland), which DO match the categorical
`stream` set. Document this distinction in the research doc.

## Phases

- [x] Phase 1 — PWF baseline (task_plan, findings, progress)
- [x] Phase 2 — Switch `data-raw/build_rules.R` to `edge_types = "explicit"` for default
- [x] Phase 3 — Regenerate `inst/extdata/parameters_habitat_rules.yaml` and `inst/extdata/configs/default/rules.yaml`
- [x] Phase 4 — Verify YAML diff: confirm no `1050/1150/2100` in spawn or rear-stream rules; confirm `1050/1150` still present in dedicated wetland-rear rule
- [x] Phase 5 — Existing test for explicit mode covers this (`test-lnk_rules_build.R:270`); add a default-config-specific test that asserts default rules.yaml has no `1050/1150/2100` in spawn predicates
- [x] Phase 6 — Full devtools::test() suite
- [x] Phase 7 — ADMS preflight on M1 (local Docker fwapg, fresh 0.21.0): BT spawn 397→368 (-7.3%), CH 296→279 (-5.6%), CO 340→318 (-6.3%), SK 98→94 (-4.5%), RB 331→311 (-6%); rearing essentially unchanged for `rear_wetland=yes` species
- [x] Phase 8 — Full 5-WSG rerun (18m 25s, 11 targets): spawning Δ = 0 km vs bcfishpass bundle on every parity species/WSG (default and bcfishpass bundles now emit structurally identical spawn predicates)
- [x] Phase 9 — Refreshed all per-WSG tables in research doc with v0.10.0 numbers
- [x] Phase 10 — Updated §2 (wetland rearing) and §3 (intermittent streams) prose for spawn-vs-rear distinction + caveat on §6 BABL SK source-bucket analysis (pre-v0.10.0 numbers)
- [x] Phase 11 — `/code-check` on staged diff: Clean round 1, skipped remaining
- [x] Phase 12 — NEWS 0.10.0 + DESCRIPTION 0.9.0→0.10.0
- [ ] Phase 13 — PR

## Critical files

- `data-raw/build_rules.R` — switch default to `edge_types = "explicit"`
- `inst/extdata/parameters_habitat_rules.yaml` — regenerated
- `inst/extdata/configs/default/rules.yaml` — regenerated
- `tests/testthat/test-lnk_rules_build.R` — add test that default-config YAML has no `1050/1150/2100` in spawn predicates
- `research/default_vs_bcfishpass.md` — refresh tables + clarify §2/§3
- `NEWS.md` — 0.10.0 entry
- `DESCRIPTION` — version bump

## Acceptance

- Default and bcfp config bundles emit structurally aligned spawn predicates: `edge_types_explicit: [1000, 1100, 2000, 2300]`
- `1050/1150/2100` no longer in default spawn or rear-stream predicates
- Dedicated wetland-rear rule (`edge_types_explicit: [1050, 1150]`) per
  species still present and unchanged
- 5-WSG rerun shows spawning km decreases in WSGs with significant
  `1050/1150` km; rear stream km also decreases (compensated by wetland
  rear km going up — net `rearing` flag may net flat depending on
  species)

## Risks

- **Reproducibility regression** vs v6/v7 — expected (this is the whole
  point); document in NEWS.
- **Could over-tighten** if some `1050/1150` segments WERE legitimate
  spawning per known habitat. The overlay (shipping in v0.9.0) catches
  those via `user_habitat_classification` — overlay-flagged segments stay
  TRUE even if rule predicate says FALSE.
- **rearing flag mechanics**: rear-stream loses `1050/1150` but
  `wetland_rearing` flag still includes them; the `rearing` flag is the OR
  across rear/wetland_rear — so `rearing = TRUE` for a `1050/1150`
  segment as long as `rear_wetland = yes` for the species. Net `rearing`
  km should be roughly unchanged for species with `rear_wetland = yes`
  (BT, CH, CO, ST, WCT, CT, DV, RB) and decrease for GR (no wetland
  rearing).

## Not in this PR

- Per-spawn `spawn_edge_types_explicit` column on dimensions.csv —
  unnecessary complexity. The global `edge_types` switch achieves the
  same end state.
- Edge_type override table (per-`waterbody_key` exceptions) — file as
  separate issue if needed.
- Per-edge-type gradient floors — defer.
- Range-containment relaxation in `fresh::frs_habitat_overlay` — file
  fresh follow-up if user_habitat alignment gap warrants.
