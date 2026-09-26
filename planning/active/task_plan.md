# Task: Research: calibrate CH and BT gradient and channel-width thresholds from observations (#284)

Current values (fresh `parameters_habitat_thresholds.csv`; link `default/parameters_fresh.csv`):

| | spawn gradient max | spawn cw min | rear gradient max | rear cw min | MAD | access gradient max |
|---|---|---|---|---|---|---|
| CH | 0.0449 | 4 | 0.0549 | 1.5 | spawn ≥ 0.46, rear 0.28–100 (**unused**: no WSG uses the `mad` method and streams carry no `mad_m3s` — fresh#114) | 0.15 |
| BT | 0.0549 | 2 | 0.1049 | 1.5 | — | 0.25 |

Rearing-to-spawning connection is identical for both (`cluster_rearing = TRUE`, direction `both`, `cluster_bridge_gradient 0.05`, `cluster_bridge_distance 10000`). For BT the 5 % bridge is shorter than its 10.49 % rearing cutoff, so steep rearing only survives with spawning upstream of it. Whether that is right is untested.

Channel width is mostly modelled: on the local `fresh.streams`, 1.38 M segments modelled, 98.5 k field-measured, 90 k river polygons and 2.19 M NULL. NULL fails every width test, and order-1 streams are NULL (fresh#28), which likely removes BT headwater rearing wholesale.

## Scope (decided at plan gate, 2026-09-25)

**Decided at the gate:** this branch covers steps 1, 2, 3 and 6. Steps 4 and 5 (the
`default_tuned` bundle and scoring it) wait on #282 (per-bundle thresholds) and #283
(observation validation), both still open. The PR relates to #284 but does not close it.
The analysis code goes in a `data-raw/` script feeding a research doc, with no new
exports.

**Measured during exploration (local docker fwapg :5432):**
- `bcfishobs.observations`: BT 11,375 (life stage **100 % NULL**); CH 9,023, of which
  ~3.2k have a coded life stage and ~1k have a spawning or rearing `activity`.
- Hatchery releases: `source LIKE 'Releases Database%'` (142 CH/BT rows).
- bcfishobs carries **no** length, width or effort. Per the user, bcfishobs is built from
  FISS; step 2 therefore goes to the FISS *site* layer, not to our crews' sheets, which
  hold little CH or BT.
- `fresh_default.streams` (55 WSGs): width source is 66k field, 49k river polygon,
  673k modelled and 977k NULL. UNTH and LNTH exist only in `fresh` (the bcfishpass
  config); BULK and MORR are in both.
- Current cutoffs: CH spawn gradient ≤ 0.0449 / width ≥ 4, rear gradient ≤ 0.0549 /
  width ≥ 1.5, access 0.15. BT spawn ≤ 0.0549 / 2, rear ≤ 0.1049 / 1.5, access 0.25.
  The bridge gradient is 0.05 for both species.

## Phase 1: Observation distributions (step 1)
- [ ] `data-raw/habitat_thresholds_observations.R`:
  - Pull CH and BT from `bcfishobs.observations`. Drop `observation_exclusions`
    (default bundle, read through `lnk_config()` / `lnk_load_overrides()`) and
    `Releases Database` rows. Record the counts dropped at each step.
  - Life-stage class: CH from `life_stage` plus `activity`
    (spawning / rearing / adult / juvenile / unknown). BT is all unknown.
  - Join each observation to (a) the province-wide FWA line
    (`fwa_stream_networks_sp` gradient + `fwa_stream_networks_channel_width` with its
    source) and (b) the link `fresh_default.streams` segment within the 55 persisted
    WSGs, matched on `blue_line_key` and measure within the segment range, joined on the
    full PK. (b) is the gradient the model actually tests. Report (a) and (b) side by side.
  - Split by region (derive a region/WSG grouping) and by width source
    (measured / river polygon / modelled / NULL), kept separate.
  - Write `research/habitat_thresholds_obs.rds` and figures: ECDF/histograms of gradient
    and width at observations, by stage and region, with the current cutoffs drawn in.
- [ ] Summary numbers per species and stage: the share of observations each current
  cutoff excludes, and the share sitting on NULL-width or order-1 segments (fresh#28).
- [ ] Record the known biases next to the numbers: points sit at the downstream end of a
  site; sampling clusters by road access; the access cutoff truncates observed gradients.

## Phase 2: FISS site-level evidence (step 2)
- [ ] Probe the FISS stream sample sites layer (bcdata `WHSE_FISH.FISS_STREAM_SAMPLE_SITES_SP`,
  or whatever fwapg/bcfishobs already loads) for measured channel width, gradient and
  site identifiers. Check whether FDIS `source_ref` (`fshclctn_id`) links CH/BT
  observations to a site record.
- [ ] If it links: add site-measured width and gradient per observation to the Phase 1
  table, and derive sampled-without-CH/BT sites as pseudo-absences.
- [ ] Record what FISS cannot give us (fish size, effort, BT life stage) as a gap. If a
  source exists but is out of reach here, file a follow-up issue rather than build it.

## Phase 3: Literature (step 3)
- [ ] Search Zotero (MCP `zotero_*`, `/zotero-lookup`) and the web for CH (stream- vs
  ocean-type) and BT (resident / fluvial / adfluvial) spawning and rearing gradient and
  channel width. One cited value or range per threshold. Flag new references for adding
  to Zotero; add none without approval of the collection.

## Phase 4: Verdict (step 6)
- [ ] `research/habitat_thresholds.md`, a topic file revised in place, with the provenance
  line (Verified / Issues / Produced by). One section per species with, for each
  threshold: current value, observation evidence, literature, candidate value (or "keep"),
  and confidence. Include `spawn_gradient_min` (with the reverted 0.0025 floor from
  `research/default_vs_bcfishpass.md:443`) and the BT `cluster_bridge_gradient`.
- [ ] Record the candidates as the input for #282's `default_tuned` bundle, and list the
  pilot-WSG scoring plan for step 5: which WSGs have both species and good sampling,
  checked against `wsg_species_presence`, and the config/schema decisions that run
  will need.
- [ ] Update `research/README.md` if one exists (otherwise note the missing index), and
  edit the #284 body to show what has landed and what waits on #282/#283.

## Validation
- [ ] Script runs clean end to end from a fresh session against docker fwapg
- [ ] `/code-check` clean on each commit
- [ ] `.Rbuildignore` still excludes `research/` and `data-raw/`
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (PR "Relates to #284")
