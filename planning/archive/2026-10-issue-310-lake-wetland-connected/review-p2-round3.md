# Review — #310 Phase 2, round 3 (staged diff: R/lnk_rules_build.R, tests/testthat/test-lnk_rules_build.R)

## Mechanism behind rounds 1 and 2

Both earlier defects came from **one fact stated twice, with nothing tying the two
statements together**: the builder re-describes something that is decided somewhere
else, instead of reading the thing that decides it.

- Round 1: the lake edge set was stated twice, once as a code list (explicit mode) and
  once as fresh category names (categories mode). The two only agreed because nobody had
  compared them.
- Round 2: the SK/KO area_only refusal re-derived *where* `area_only` is emitted, apart
  from `add_ao()`. Its copy of the branch precedence (no_fw > lake_only > additive) left
  out the lake-only branch.

The general form: a guard or a representation in `lnk_rules_build()` encodes a model of
(a) another branch of the builder, or (b) fresh's reader. It is right only while that
model matches the real producer or consumer.

## Every place the mechanism reaches in lnk_rules_build.R, checked

| # | Where | Duplicated fact | Source of truth | Verdict |
|---|---|---|---|---|
| 1 | `lake_edges` (l.225) used in both modes | lake edge set | single list, both modes | Fixed by round 1; one list now |
| 2 | `additive_lake` (l.271) | branch precedence + which branch calls `add_ao()` | l.348/350/357/460/472 | Agrees: no_fw emits nothing, lake_only no `add_ao`, `rear_lake` block sits outside the all_edges/stream if-else, so all_edges species get it too |
| 3 | Stamp loop (l.480-494): "first rule with `identical(waterbody_type, wt)`" | which rule fresh reads | fresh `.frs_find_waterbody_rule()` (utils.R:406) and `.frs_validate_rear_connected()` (frs_params.R:186) | Agrees exactly: same predicate, same first-match order. The floored carve-out comes after the polygon W rule, so the stamp lands on the polygon rule |
| 4 | Comment l.450-453: fresh takes the first W rule as the bucket rule | fresh's lookup | same as #3 | Agrees |
| 5 | `thresholds: false` + explicit codes on the L rule | fresh skips inheritance on L/W | `.frs_rule_to_sql()` auto-skip for L/W | Agrees (redundant, accepted) |
| 6 | The circular / area_only refusals (l.262-277): "the spawning anchor is the lake rule" | which rear rule anchors `requires_connected: rearing` spawning | fresh `.frs_run_connectivity()` (frs_habitat.R ~1260): the **first rear rule with waterbody_type L or W** | **Disagrees for an additive species with a W rule** (below) |
| 7 | Emitted YAML against fresh's loader | what fresh accepts | `fresh::frs_params()` | Every working-tree bundle (default, default_extrabreaks, default_rearbreaks, bcfishpass) built to a tempfile in both edge modes and loaded with `fresh::frs_params()` v0.39.0: all OK. Stamps land on W then L for BT/CH/CO/ST/WCT/RB and on L only for GR, all at 10000 m. bcfishpass carries no stamps |

Test file: `NOT_CRAN=true testthat::test_file(...)` under `load_all()` passes with 0 failures.

## Findings

- **[severity: fragile]** R/lnk_rules_build.R:269-276. The area_only refusal hard-codes
  "the anchor is the L rule". fresh anchors waterbody-connected spawning on the **first
  rear rule with type L or W**. In the additive branch, the W polygon rule is emitted
  before the L rule (l.434-449 come before l.460). So for an additive species with
  `spawn_requires_connected = rearing` and `rear_wetland_polygon` emitted, the anchor is
  the W rule, and two things go wrong:
  (a) `rear_lake_area_only = yes` is refused even though it does not touch the anchor;
  (b) `rear_wetland_area_only = yes`, which does take the anchor's polygon rule out of
  `rearing` (`.frs_connected_waterbody` reads `hr.rearing IS TRUE`), passes unrefused.
  This is the round-2 shape again: the guard models which rule matters instead of
  reading it from the emitted rules.
  **No shipped bundle reaches it**, because SK and KO are lake-only, where neither column
  is emitted. A guard that ran after the rules were built would follow fresh's lookup and
  could not drift: find the first rear rule with `waterbody_type %in% c("L","W")`, then
  refuse if it carries `area_only`. That also makes the separate `additive_lake`
  re-derivation unnecessary.

Nothing else. Items 1-5 and 7 agree with their sources of truth.

---

## Triage (parent session)

**Fixed:** the area_only refusal now reads the anchor the way fresh does: the first rear rule
with `waterbody_type` L or W (fresh `R/frs_habitat.R:1252-1262`, `.frs_run_connectivity()`).
It refuses only if that rule carries `area_only`. Tests cover lake-only-additive (L anchor
refused), W-first (lake area_only allowed, wetland area_only refused) and the lake-only branch
(column ignored).

**This was a defect inside round 1's fix, so an enumeration ends the loop.**
The mechanism is that `lnk_rules_build()` restates a decision fresh makes. Every site where the
builder restates one:

| # | site | fresh's decision | state |
|---|---|---|---|
| 1 | `lake_edges` | which lines the L rule admits (`.frs_rule_to_sql`) | one explicit list in both modes |
| 2 | stamp loop | the bucket / validator read the first rule of each type (`.frs_find_waterbody_rule`, `.frs_validate_rear_connected`) | same `identical(waterbody_type, wt)` first-match |
| 3 | area_only anchor refusal | the spawning anchor is the first rear L or W rule | same first-L-or-W lookup, after the rules exist |
| 4 | circular refusal | n/a: any rear connection on a `spawn_requires_connected = rearing` species | independent of rule order |
| 5 | `thresholds: false` on L | L/W rules never inherit thresholds (`utils.R:252`) | redundant, consistent (accepted) |
| 6 | `spawn_connected$waterbody_type` | first rear rule with a waterbody_type, R included | pre-existing, not in this diff; no additive species sets `spawn_connected_direction` (accepted) |
| 7 | legacy-column guard | n/a | restates nothing |

Nothing in the set sits above its source of truth. Loop ended by enumeration (7 sites).
