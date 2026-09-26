# habitat_thresholds_284

Evidence for the CH and BT gradient and channel-width candidates in link#284.
Read with `research/habitat_thresholds.md`, which holds the verdicts.

| Producer | Output |
|---|---|
| `data-raw/query_habitat_thresholds_obs.R` | `obs_ledger.csv`, `obs_segments.csv`, `obs_status.csv`, `quantiles.csv`, `selection.csv`, `projects.csv`, `bridge_bt.csv`, `uhc_ch.csv`, `candidates.csv`, `fig_selection_*.png`, `stamp.txt` |
| `data-raw/query_habitat_thresholds_fiss.R` | `fiss_presence.csv`, `fiss_width_error.csv`, `fiss_stamp.txt` |

Both are read-only against docker `fwapg` (:5432). Environment stamps are in
`stamp.txt` and `fiss_stamp.txt`.

## How to read them

- **Use** is CH/BT observations from `bcfishobs.observations`. Excluded records are
  `observation_exclusions` (`data_error | release_exclude`) and `Releases Database`
  rows; the remainder is restricted to WSGs persisted in `fresh_default` where
  `wsg_species_presence` marks the species, match types A/B, and one record per species
  × `blue_line_key` × metre. `obs_ledger.csv` counts every step.
- **The segment** is the one the model tests. Observations are break points, so a point
  usually sits on a boundary, and the segment *starting* within 1 m (the upstream one)
  wins. `gradient_dn` is the downstream neighbour and `gradient_w100` a 100 m FWA window
  from geometry Z, independent of link's breaks.
- **Availability** is accessible (`streams_habitat_<sp>.accessible`) length in the same
  WSGs, on stream edges outside waterbodies (plus river polygons for gradient). In
  `selection.csv`, `ratio` is use share ÷ availability share: above 1 is selected, below
  1 is avoided or under-sampled.
- **Sets**: `CH_spawn` = activity SPL/SPM/S; `CH_rear` = activity R/REA or
  Fry/Parr/Juvenile. BT has no stage in bcfishobs. **`BT_any_dv` is the primary BT
  evidence**: BT and DV records pooled in WSGs with BT, the way the pipeline already counts
  them for access (`BT;DV`). Inland, DV are bull trout recorded under the other name, and
  on the coast the two species' habitat biology is treated as equivalent. `BT_any` (BT
  records only) is kept as the comparison: `candidates.csv` and `bridge_bt.csv` carry both,
  marked by `evidence_role` / `set`. `BT_spawn_dv` and `BT_rear_dv` are the staged DV
  records, the only staged char evidence.
- **FISS**: provincial data submissions parsed by the private `knowledge` repo
  (`scripts/0200`–`0220`). Only aggregates are committed here. Site rows are written only
  when `LNK_FISS_SITES_OUT` names a path. `average_gradient_percent` holds proportions
  despite its name: every value is ≤ 0.43.
- `candidates.csv` is the decision rule in the PWF (archived with #284), applied
  mechanically, with three changes made after a first run had been seen: use restricted to
  accessible segments; the inverted "ratio above cutoff ≥ 1 → keep" clause removed; and
  BT+DV pooled as the primary BT evidence. The research doc (Method, Changes 1–3) lists
  what each moved. Each bridge row (one per BT set) is the share of all of that set's
  observations that sit on an accessible segment passing the rear predicate yet carrying
  `rearing = FALSE`.
