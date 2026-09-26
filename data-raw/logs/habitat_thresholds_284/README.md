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
  Fry/Parr/Juvenile. `BT_any` has no stage, because bcfishobs gives BT none. The `*_dv`
  sets add DV records in WSGs with BT, the way the pipeline already counts them for access
  (`BT;DV`). They mix two chars and are capped at low confidence.
- **FISS**: provincial data submissions parsed by the private `knowledge` repo
  (`scripts/0200`–`0220`). Only aggregates are committed here. Site rows are written only
  when `LNK_FISS_SITES_OUT` names a path. `average_gradient_percent` holds proportions
  despite its name: every value is ≤ 0.43.
- `candidates.csv` is the decision rule in the PWF (archived with #284), applied
  mechanically to accessible-segment use (the bridge row uses all BT observations, the
  share counting those on accessible segments). That restriction was added after a first run
  had been seen, and it moved three verdicts. The research doc (Method, Change 1) lists
  the before and after values, and where the final candidate departs from the rule.
