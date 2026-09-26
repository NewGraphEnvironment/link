# Task: Research: calibrate CH and BT gradient and channel-width thresholds from observations (#284)

Current values (fresh `parameters_habitat_thresholds.csv`; link `default/parameters_fresh.csv`):

| | spawn gradient max | spawn cw min | rear gradient max | rear cw min | MAD | access gradient max |
|---|---|---|---|---|---|---|
| CH | 0.0449 | 4 | 0.0549 | 1.5 | spawn ≥ 0.46, rear 0.28–100 (**unused**: no WSG uses the `mad` method and streams carry no `mad_m3s` — fresh#114) | 0.15 |
| BT | 0.0549 | 2 | 0.1049 | 1.5 | — | 0.25 |

Rearing-to-spawning connection is identical for both (`cluster_rearing = TRUE`, direction `both`, `cluster_bridge_gradient 0.05`, `cluster_bridge_distance 10000`). For BT the 5 % bridge is shorter than its 10.49 % rearing cutoff, so steep rearing only survives with spawning upstream of it. Whether that is right is untested.

## Scope (re-decided at plan gate, 2026-09-26 — supersedes the 2026-09-25 gate)

#282 has since merged (v0.51.0), so step 4 is now in scope. #283 has not been built.

- **Evidence now, score later.** This branch covers steps 1, 2, 3, 4 and 6. Verdicts are
  *candidate, unscored*. Step 5 waits on #283; the PR relates to #284 and does not close it.
- **`default_tuned` owns a copy of `parameters_fresh.csv`**, so CH/BT `spawn_gradient_min`
  and BT `cluster_bridge_gradient` can be tuned. Everything else stays inherited.
  *Superseded:* the evidence keeps both values, so no copy was made (see findings).
- Analysis lives in `data-raw/query_*` scripts writing to `data-raw/logs/habitat_thresholds_284/`,
  feeding `research/habitat_thresholds.md`. No new exports.
- The plan review (`review-plan.md`, 3 blockers) is folded in below. B1 and B3 were re-probed
  2026-09-26: 4840/4870 BT and 3532/3550 CH observations in `fresh_default` sit within 1 m of a
  segment break, and the FDIS key is in `source`, not `source_ref`.

## Decision rule and confidence (fixed before looking at distributions)

Use = CH/BT observations, deduplicated to one per species × `blue_line_key` × rounded measure,
match types A/B (stream, within 100 m), within WSGs persisted in `fresh_default`. Availability =
length of accessible (`streams_habitat_<sp>.accessible`) stream-edge segments not in a waterbody,
in the same WSGs. The selection ratio per bin is use share ÷ availability share.

- **Gradient max** (per stage): candidate = the use P95 of the tested (upstream-segment)
  gradient, snapped to the `x.xx49` grid. It is kept at the current value when
  |candidate − current| < 0.5 percentage points, or when the selection ratio in the bin
  just above the current cutoff is ≥ 1 (the cutoff is not binding).
- **Channel width min**: candidate = the use P5 of non-NULL width, excluding river polygons
  (which bypass the width test), checked against the field-measured subset. It is kept when
  |candidate − current| < 0.5 m.
- **`spawn_gradient_min`**: a floor only if the spawn-stage selection ratio in [0, floor) is
  < 0.5 **and** fewer than 5 % of spawn-stage observations fall below it. Otherwise 0.
- **BT `cluster_bridge_gradient`**: raise it only if more than 10 % of BT observations sit on
  segments that pass the rear predicate but have `rearing = FALSE`.
- **Confidence**: *high* = n ≥ 100 stage observations and the literature agrees; *medium* =
  n ≥ 30, or the literature alone; *low* = otherwise. A value changes only at medium or above.
- FISS site presence/absence (Phase 2) and the literature (Phase 3) can veto a candidate that
  contradicts them. They cannot create one on their own.

## Phase 1: Observation use vs availability (step 1)
- [x] `data-raw/query_habitat_thresholds_obs.R`: CH + BT obs; drop `observation_exclusions`
  (`data_error | release_exclude`, read from the default bundle's declared CSV) and
  `Releases Database` rows; keep a count ledger at each step. DV rows are sensitivity-only.
  *As built:* DV is used where the WSG has BT, since "bt and not dv" selected nothing.
- [x] Stage: CH spawn = activity SPL/SPM/S; CH rear = activity R/REA or life stage
  Fry/Parr/Juvenile (never Adult, holding, migrating or OBL); BT = unknown (DV stage as
  sensitivity).
- [x] Join on the upstream segment at the break (`abs(s.downstream_route_measure − m) < 1`, else
  containing), on the full PK in `fresh_default.streams`. *As built:* no assertion; ties
  (2+ candidate segments, 45 retained obs) resolve to the upstream one and are counted in
  `n_cand` / `stamp.txt`.
  Add a 100 m FWA window gradient from geometry Z. Decompose each obs into passes / fails-gradient
  / fails-width / width-NULL / river-poly-bypass / lake-wetland, and read the final flags from
  `streams_habitat_ch/_bt`.
- [x] Availability from accessible segments in the same WSGs; selection ratios by gradient and
  width bin; project dominance reported. *As built:* selection is pooled across regions and
  width sources; the region and width-source splits are in `quantiles.csv` only.
  CSVs + PNGs in `data-raw/logs/habitat_thresholds_284/`, with a README; the stamp is in
  `stamp.txt` / `fiss_stamp.txt` (link SHA + dirty flag, the fresh versions that built the
  schema from its `log` — `fresh_default.log` carries no `fresh_sha` and the installed fresh
  has none, while `fresh.log` (FISS snap target) records 0.33.0@7f12d99 — plus the bcfishobs
  row count).
- [x] G9 metric for the BT bridge; G7 CH `user_habitat_classification` known-spawning overlap.

## Phase 2: FISS site-level evidence (step 2)
- [x] `data-raw/query_habitat_thresholds_fiss.R`: read the `knowledge` FISS data-submission
  snapshots (`LNK_KNOWLEDGE_DIR`, default `~/Projects/repo/knowledge`; SHA recorded):
  `fiss_sites_<wsg>_all.csv` for UNTH, LNTH, COTR, PINE and UPCE. Per site: measured width
  and gradient (percent → proportion), effort, and CH/BT caught vs sampled-without (NFC
  included) as true absences.
- [x] Presence vs absence distributions against the current cutoffs; snap sites to
  `fresh.streams` to size modelled-vs-measured width error. *As built:* width only; there is
  no gradient-error table, because site gradients are too few and unit-ambiguous. Output goes to the
  campaign dir.
- [x] Draft (not file) a `knowledge` issue for parsing the individual-fish sheets (fish
  length, for the adult/juvenile split) into `planning/active/`.

## Phase 3: Literature (step 3)
- [x] Zotero (MCP + SQLite) and the web: CH stream- vs ocean-type, and BT resident / fluvial /
  adfluvial, spawning and rearing gradient and width. One cited value or range per threshold
  in `findings.md`, with page references. Gaps are flagged; new references are listed for
  approval, not added.

## Phase 4: Candidates in `default_tuned` (step 4)
- [x] Apply the decision rule; write the candidate CH/BT values into
  `configs/default_tuned/parameters_habitat_thresholds.csv`.
- [ ] ~~`configs/default_tuned/parameters_fresh.csv`~~ — not done: the rule keeps both
  `spawn_gradient_min` and `cluster_bridge_gradient`, so a copy would be identical to
  default's (see findings). Was: copy of default's; CH/BT
  `spawn_gradient_min` and BT `cluster_bridge_gradient` per the rule. Declare it in
  `config.yaml` `files:` + `provenance:`; update the README.
- [x] Update `test-lnk_config.R`: assert that only the intended cell differs from `default`,
  and start the `frs_params` fixture from default's CSV. (It does not own `parameters_fresh`;
  see the struck item above.) `audit_configs.R` §2 and `lnk_config_verify()`
  must be clean.

## Phase 5: Verdict (step 6)
- [x] `research/habitat_thresholds.md`, a topic file with a provenance line: one section per
  species. *As built:* one verdict table (current / candidate / confidence) plus per-threshold
  prose carrying the use-vs-availability, FISS and literature evidence; status is doc-wide
  ("unscored"). It states the biases (points at site downstream ends,
  road access, crews avoiding big and steep water, segment-average gradient, observations
  creating breaks) and the step-5 scoring plan with the run decisions it will need.
- [ ] Create `research/README.md` (index; none exists). Link it from `default_tuned/README.md`.
  Edit the #284 body to show what has landed and what waits on #283.

## Validation
- [x] Scripts run clean end to end from a fresh session against docker fwapg (rerun after
  every fix; outputs byte-identical between reruns)
- [x] Tests pass: `lnk_config` 171/171; full suite 1951 pass, 3 errors, all `Connection
  refused` on the bcfp tunnel `:63333` (down during the run; untouched by this branch).
  lintr: no new lint classes; the scripts carry the repo's existing hanging-indent and
  NSE-binding style lints.
- [x] `/code-check` — four rounds over the combined Phase 1–5 diff (not per commit: the
  phases were reviewed as one pass). R1 and R2 found real defects, two of which flipped
  candidates; R3 and R4 were enumerations (88 and 97 claims). R4 ended the loop: 96/97
  matched, and the one miss was a section pointer, fixed.
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, then `/gh-pr-push` (PR "Relates to #284")
