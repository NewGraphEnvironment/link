# Findings — Score the discharge (mad) habitat model against observations (#300)

## Issue context

**If done:** we know, per species, where classifying on `mad` instead of `cw` adds or drops habitat that fish actually use, before any bundle switches a group. **If never:** switching a group to `mad` is a guess. Since #302 that guess has a measured downside: at `default_tuned`'s ranges a `mad` group keeps at least a third less BT stream rearing than `cw`, and at least four-fifths less GR, on #302's held-out groups.

## Problem

Since #286, a bundle can put a watershed group on the discharge model (`mad`). The two models classify different segments, and nothing yet says which is closer to where fish are observed. Fewer habitat segments under `mad` is not by itself a defect. It may be less conservative, or more realistic, and the evidence should decide.

## What #299 and #302 settled (2026-10-02)

- **The validator scores a `mad` group on discharge** (#299).
- **BT, GR, KO and RB have MAD ranges in `default_tuned`** (#302; `default` and `bcfishpass` still have none, so under them those species lose all stream habitat on `mad` by construction). Values and evidence: `research/habitat_thresholds.md`, "MAD (discharge)".
- **The scoring harness already does model comparison** (#302, `data-raw/habitat_variants_build.R` / `_score.R`, `data-raw/habitat_score/README.md`): a variant's `model` column puts its WSGs on `mad` through a per-bundle method table, on one shared segmentation, and an *anchor* step from the `cw` base to a `mad` variant reports both directions (what `mad` keeps that `cw` drops, and the reverse).
- **A partial answer exists for BT, GR and RB.** #302's anchor bands (`data-raw/logs/habitat_score_302/bands_pooled.csv`, held-out, `stage = any`) give the cw-only and mad-only habitat at the P10 rungs. The `removed` side (cw only) is used at 0.37–0.48 (BT), 0.50–0.73 (GR) and 1.06–1.07 (RB) of the core rate. **But their core is the `mad` rungs, not the habitat both models keep**, so they do not answer this issue's question as posed.
- **Stream size and sampling effort are confounded** in a per-km density comparison when the two sides differ in stream size, which a model swap does. #302 flagged it and did not resolve it.

## Proposed Solution

- **Harness changes the build needs** (found by reading the code, not yet built):
  - **A model-only variant.** Today only the base may leave `column` empty, and every other variant must change at least one threshold cell. A `mad` variant with no cell change is what this issue compares.
  - **A base bundle other than `default`.** Both scripts hard-code `lnk_config("default")`. Comparing on `default_tuned` (which gives BT, GR, KO and RB a range) needs `--base=default_tuned`.
  - **A core of "habitat both models keep"** for a model-only comparison (`cw` base ∩ `mad` variant), with the decision on the two exclusive bands rather than a threshold walk.
- **Classify held-out groups under both models** on one shared segmentation. Only groups with discharge in `fwa_stream_networks_discharge` can be used (123 WSGs in local fwapg; e.g. BULK has none). #302's held-out set (REVL, ELKR, KOTR, UARL, MURR, UBTN, LHAF, SIML, OKAN, KETL; 20-WSG closure) and its `score302_*` / `working_score302_*` schemas can be reused if built at a compatible HEAD.
- **Score with `lnk_habitat_validate_band()` under a rule fixed before the run**: per species and stage, observation locations per km on the segments only one model keeps against the core both keep.
- **Control for stream size** before reading the ratio as habitat: split the core by stream size (as #284's elevation classes split elevation), or report the comparison within size classes. Without it the verdict may read sampling effort.
- **Report per species and stage**, including the species `default` gives no MAD range, which lose stream habitat under `mad` by construction there.
- **Groups outside the discharge coverage cannot be scored** until per-segment discharge exists there. A province-wide per-segment discharge estimate is in progress in the `wet` package.

Depends on #299 and #302 (both closed). Relates to #284, #286; fresh#237 (`wetland_ha_min` ignored by the rear predicate) affects wetland rearing under both models alike.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## KO presence in the closure (2026-10-02)

`configs/default/overrides/wsg_species_presence.csv`: KO is present in KOTL and PARS only,
both #302 in-sample (calibration) WSGs, so KO is reported in-sample and decides nothing.

## Power from #302's P10 anchors (held-out, stage any)

`cw`-only (removed) rearing: BT 4,505 km / 240 found, GR 3,893 / 158, RB 864 / 123.
`mad`-only (added) rearing: BT 193 km / 7, GR 14 km / 0, RB 500 km / 19. The `mad`-only side
is likely underpowered for BT and GR at the landed pair.

## Self-review notes, pending fix after code-check round 1

- `model_size.csv` vs `model_bands_pooled.csv` consistency guard matches only one way
  (chk -> mp); a pooled band with km > 0 and no per-segment rows would pass. Add the reverse.

## Errors Encountered (continued)

| Error | Resolution |
|-------|------------|
| #284 regression silently never ran: `cd … && S=… && export … && (A) & (B) & wait` backgrounded the whole `&&` list with (A), so (B) ran in the parent with no `S` and no cwd | `code-check-shell.md` "`&` binds to the whole `&&` list"; relaunched (B) as its own backgrounded call |

## Results (2026-10-03)

- Build `482c075`, 68.2 min (after the colima disk grew 200 → 300 GiB; the first attempt,
  `build_20261002_full.log`, stopped at "No space left on device" after KETL). Score
  `--floor=expected`. Band identity holds per WSG within 0.01 km (23 pairs, both flags).
- Of record, size-adjusted (held-out, stage any): BT rear `cw`-only 0.71 (unadj 0.33),
  BT spawn 0.69 / `mad`-only 0.42 → `cw` closer; GR rear 0.49 (all classes merged: no
  small-water core), GR spawn 0.72; RB rear 1.49 / `mad`-only 0.54 → each misses; RB spawn
  2.33 / 0.35 → `cw` closer. BT rear `mad`-only, GR `mad`-only underpowered.
- Landed pair vs `cw`: BT rear −35.7 %, spawn −29.0 %; GR −82.5 % / −73.3 %; RB −4.5 % /
  +11.9 %.
- **Mechanism:** `cw`-only = (a) no discharge — BT rear 504 km, 433 km edge type 1250
  (river-polygon main flow), 204 of 246 locations, 40/100 km vs core 15; (b) below the
  MAD minimum — 4,459 km, 41 locations; orders 1–3 at 0.22 of the size-matched core.
  Order 4+ `cw`-only is used at ≥ the core rate for BT and RB (1.31–3.41), 0.77 for GR.
