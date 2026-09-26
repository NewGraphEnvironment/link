# Plan review — #284 task_plan (Plan agent, 2026-09-25)

Read-only review against docker fwapg :5432 + link/fresh/fwapg/bcfishpass source. Arrived
after #284 was parked for #282. Not yet folded into task_plan.md — do that on resume.
Numbers are the reviewer's; re-probe before acting on any of them.

**Verdict: not valid evidence as written.** Three blockers.

## BLOCKER

**B1 — the obs→segment join is ill-defined: observations ARE break points.**
`.lnk_pipeline_break_obs` (R/lnk_pipeline_break.R ~141-152) breaks at
`round(downstream_route_measure)` for every retained observation; `frs_break_apply`
re-computes gradient per piece. In `fresh_default`, 4866/4870 BT and 3545/3550 CH obs sit
within 1 m of a boundary; closed `BETWEEN` double-matches 95 %, half-open picks up- or
downstream by rounding accident. Upstream segment median 84 m (CH) / 92 m (BT); 37 % < 50 m.
Pass/fail flips between neighbours for 3.2 % CH spawn-gradient, 6.4 % BT spawn, 3.7 % BT rear.
**Fix:** pick the upstream segment explicitly (`abs(s.downstream_route_measure - o.m) < 1`),
report the downstream neighbour too, add a fixed-window gradient from FWA geometry Z
(e.g. 100 m upstream like `frs_break_find`, or 200–300 m), assert exactly one segment/obs.

**B2 — recall-only cannot calibrate a threshold.** "Share of obs each cutoff excludes"
only ever argues for looser. Need use-vs-availability: length-weighted gradient/width of
accessible segments in the same WSGs (`fresh_default.streams` ⋈ `streams_habitat_<sp>.accessible`).
Pseudo-absences exist today in bcfishobs: 74,922 FDIS collection events (`fshclctn_id`);
7,887 include BT, 4,571 CH. Events catching other species but not CH/BT, in WSGs where the
species is present, are the pool (no-catch events are not in bcfishobs).

**B3 — Phase 2's link key is wrong.** `fshclctn_id` lives in `source`
(`"FDIS Database: fshclctn_id 29644"`), not `source_ref` (`"Project ID/Name: 28421/...; SU11-72376"`).
`WHSE_FISH.FISS_STREAM_SAMPLE_SITES_SP` (68,842 sites) is keyed by `site_survey_id`, has no
`fshclctn_id`; only feasible link is project ID + date + proximity. Not in local DB.
Its `GRADIENT` is **percent**; no effort/catch/absence fields.

## GAP

- **G1 — what the model tests** (default `rules.yaml` 7-78; fresh `R/utils.R:216-322`
  `.frs_rule_to_sql`): spawn = stream edges {1000,1100,2000,2300}, `waterbody_key IS NULL`,
  gradient BETWEEN 0 AND max, width BETWEEN min AND 9999, OR river polygon (width bypassed,
  gradient still tested). Rear adds wetland edges 1050/1150 `thresholds:false`, wetland ≥1 ha,
  lakes (≥100 ha CH, ≥10 ha BT) — lake/wetland rules test neither gradient nor width. Then
  cluster_rearing, access, `user_habitat_classification` overlay. Order-1 bypass OFF for CH/BT
  in default (bcfp has it, `load_habitat_linear_bt.sql:95-96`). BETWEEN is inclusive vs bcfp's
  strict `>` on spawn width min. 55 % CH / 38 % BT obs segments are river polygons.
  Decompose each obs into fails-gradient / fails-width / width-NULL / bypassed; read final
  flags from `fresh_default.streams_habitat_ch/_bt` (CH spawn 87 % / rear 90 %; BT 70 % / 78 %).
- **G2** — (a) FWA vs (b) `fresh_default` matters for gradient only; width inherits by
  `linear_feature_id` (0/71,920 differ in BULK+MORR). Gradient: 42 % of BULK segments split.
- **G3** — NULL width ≡ order-1 (modelled width only for order > 1, fwapg `channel_width.sql`).
  Only 265 BT / 116 CH obs on NULL width — headwater-loss claim needs B2's availability.
- **G4** — 42 % CH / 33 % BT obs segments have gradient exactly 0; 122/279 CH spawning-activity
  obs < 0.0025. Stratify by segment length + edge type; use window gradient.
- **G5** — match quality: CH C 795, D/E 283, lake 257; BT C 1519, D/E 1268, lake 1241.
  Primary on A/B, sensitivity on C/D/E; lake points against lake rules.
- **G6** — repeats + project dominance: CH 9,023 records / 5,246 locations; BT 11,375 / 7,887.
  Nechako Fry Emergence 551 CH; Peace large-fish indexing >1000 BT (adult mainstem boat EF);
  traps/salvage aren't habitat use. De-dup, cap per project, drop-top-projects sensitivity.
- **G7** — `user_habitat_classification`: 1,892 CH known-spawning reaches (+19 `-1`, 23 rear)
  in 126 WSGs, none BT. Best CH spawning evidence; also forces flags + breaks — flag obs inside.
- **G8** — CH stage counts: spawning activity 1,049, rearing 895, either 1,939, coded stage 3,485.
  Don't treat Adult (291), holding/staging, migrating, "Fish observed at this point or zone"
  (1,755) as a stage. BT 100 % NULL; `source_ref` "BULL TROUT REDDS" is a weak spawn proxy.
- **G9** — no metric for BT `cluster_bridge_gradient`: count BT obs whose segment passes the rear
  predicate but `rearing = FALSE` (from `streams_habitat_bt`, no new run).
- **G10** — DV: 13,094 records / 194 WSGs; BT `observation_species` is `BT;DV`. Decide + document.
- **G11** — Phase 2 "measured width" is already Phase 1: fwapg
  `extras/channel_width/sql/channel_width_measured.sql` averages FISS sample-site + PSCIS widths
  per reach = `FIELD_MEASURMENT`. 22 % of BT obs segments vs 3.7 % of network — circular.

## ASSUMPTION

- **A1** — exclusions: key `observation_key`; predicate `data_error | release_exclude`
  (R/lnk_pipeline_prepare.R:306-319); lives inside AOI-scoped `.lnk_pipeline_prep_observations`
  — copy predicate or factor a small internal helper. Pipeline also filters by
  `wsg_species_presence`. Impact tiny: 11 CH (7 data_error; 4 release_include-only, not excluded),
  0 BT. Releases DB rows (128 BT, 14 CH) NOT covered by `release_exclude` — keep the source filter.
- **A2** — `fresh_default.log` has 4 rows (PINE link 0.44.3/fresh 0.32.0; LARL/KOTL/SLOC
  0.45.1/0.33.0); 51 WSGs have no run record. State it in provenance.
- **A3** — `fresh_default.streams` PK `(id_segment, watershed_group_code)`; join on both.
  habitat tables 1:1, no fresh#218 duplication here (that is `fresh.streams_habitat_*` — avoid).
  Coverage: CH 3,550/9,023 obs in 32/142 WSGs; BT 4,870/11,375 in 51/157. Interior/north only —
  no coastal/VI ocean-type CH.
- **A4** — "access truncates observed gradients" is misstated: observations lift barriers
  (CH threshold 5 since 1990, BT 1), so ~99 % of obs segments are accessible. Real biases: crews
  avoid wading big rivers and steep reaches; segment gradient is an average; obs create the breaks.
- **A5** — default breaks only at 15/20/25/30 % (`.lnk_classes_bcfp`, prepare.R:142-147), not at
  4.49/5.49/10.49 %; segments average across cutoffs. `default_rearbreaks` not persisted locally.

## ORDERING / SCOPE / ACCEPTANCE

- Settle G11 before width strata; fix B1 join + a decision rule before any figures.
- FISS sites via bcdata in memory is read-only; loading to DB is a write — decide.
- `data-raw/README.md` 250-276 wants a verb prefix → `query_habitat_thresholds_obs.R`;
  run outputs under `data-raw/logs/<topic>/`, not `research/*.rds`.
- `research/README.md` does not exist (26 files).
- **No rule turns evidence into a candidate value** (use quantile, use/availability crossing 1,
  recall at fixed available length) and no confidence rubric — define both before looking.
  Add to validation: count ledger, one-segment-per-obs assertion, units check, named
  `fresh_default` vintage.
