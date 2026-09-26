# Code-check round 1: #284 research scripts

Reviewer: subagent, 2026-09-26. Probes were read-only against docker fwapg and the staged
outputs in `data-raw/logs/habitat_thresholds_284/`. No repo file was edited except this one.

## Findings

- **[bug, flips two published candidates]** `data-raw/query_habitat_thresholds_obs.R:271-274` and `:387`
  The gradient P95 that drives `candidates.csv` is taken over every use row, **including
  observations on segments the model marks `accessible = FALSE`**. The selection ratio
  (`sel_one`, :315/:318) and the floor rule (:415) in the same script both filter
  `accessible %in% TRUE`, so one decision rule mixes two definitions of "use". A handful of
  inaccessible, steep observations move the P95 enough to change the verdict. Recomputed from
  the staged `obs_segments.csv`:

  | set | P95 all (n) | rule | P95 accessible only (n) | rule |
  |---|---|---|---|---|
  | CH_spawn | 0.0519 (232) | 0.0549, **change** | 0.0443 (226) | 0.0449 = current, **keep** |
  | CH_rear | 0.0630 (507) | 0.0649, **change** | 0.0596 (497) | 0.0549 = current, **keep** |
  | BT_any | 0.1311 (2457) | 0.1349, change | 0.1253 (2443) | 0.1249, change |
  | BT_spawn_dv | 0.1964 (76) | unchanged | 0.1964 (76) | unchanged |

  CH_spawn's six inaccessible rows include gradients of 0.224 (ZYMO) and 0.336 (LSKE). The
  width P05 does not flip (CH_spawn 6.42 vs 6.64, CH_rear 1.70 vs 1.71). Either filter the
  quantiles to accessible like the other two rule arms, or state in the research doc that the
  P95 deliberately includes inaccessible use. As written, CH spawn and CH rear read "change"
  on six and ten observations the model cannot classify anyway.

- **[bug, wrong number in bridge_bt.csv and candidates.csv]** `data-raw/query_habitat_thresholds_obs.R:241-242`, `:351`, `:429`
  `status_one()` labels every river-polygon observation that passes gradient as
  `passes_river_poly`, but the R rule in `rules.yaml` carries an explicit
  `channel_width: [0.0, 9999.0]`, which fresh renders as `s.channel_width BETWEEN 0 AND 9999`
  (`fresh/R/utils.R`, `.frs_rule_to_sql`). A NULL width fails it. 55 retained observations sit
  on river-polygon segments with NULL `channel_width`, and all 55 have `spawning = FALSE`
  and `rearing = FALSE` while `accessible = TRUE`. Consequences:
  - `bridge_bt.csv`: 30 of the 61 BT observations counted as "passes predicate, rearing FALSE,
    accessible" (the G9 "lost to cluster_rearing" cell) are these NULL-width river polygons,
    not clustering. `share_lost_to_clustering` is 0.0238. The clustering share is about
    31/2560 = 0.012, half the published value. The verdict ("keep", < 10 %) holds, but the
    number is wrong.
  - `obs_status.csv`: `passes_river_poly, final = FALSE` rows are mostly NULL-width failures
    (e.g. CH_any spawn: 21 of 23). They should read `width_null`.

  Fix: add `pred_set == "river_poly" & is.na(channel_width) ~ "width_null"` before the
  river_poly pass arm. (Side finding for the model, not the script: river-polygon segments with
  NULL width are silently excluded from both spawning and rearing, in 16 WSGs. TABR, UPCE and
  LPCE hold 31 of the 55.)

- **[fragile, ~2 % availability error per width bin]** `data-raw/query_habitat_thresholds_obs.R:298-299` vs `:320-322`
  Availability bins widths after `round(channel_width, 1)` in SQL, while use bins the raw
  width. The two sides are therefore binned on different values. Rounding pushes each avail bin
  about 0.05 m, and against a decreasing density it loses mass. Measured on CH accessible
  streams (raw km vs rounded km): (1.5,2] 3573 vs 3515, (2,3] 4775 vs 4652, (3,4] 2763 vs
  2707, (4,5] 1941 vs 1926. That is a 1-3 % shift, which inflates `ratio` by the same amount.
  Gradient is stored at 4 dp, so its `round(…, 4)` is a no-op. The width ratios feed only the
  figure and the text, not the rule, so severity is low. Fix: group by unrounded width, or bin
  in SQL with the same edges.

- **[bug, sensitivity set only]** `data-raw/query_habitat_thresholds_obs.R:190-192`, `:226`
  The dedup key `loc` uses `species_code`, where DV maps to BT, but the grouping is
  `group_by(obs_species, loc)`. A BT record and a DV record at the same `blue_line_key` ×
  metre therefore both survive. `BT_any_dv` (`species_code == "BT"`) counts 278 locations
  twice (4826 single + 278 doubled). The README says "one record per species ×
  `blue_line_key` × metre". This does not reach `candidates.csv`: the `*_dv` stage sets filter
  `obs_species == "DV"` and `BT_any` filters `obs_species == "BT"`. It does inflate
  `BT_any_dv` in `quantiles.csv`, `selection.csv` and `obs_status.csv`.

- **[fragile, provenance]** `data-raw/query_habitat_thresholds_obs.R:474-476`
  - `.lnk_pkg_git_sha("fresh") %||% "unknown"` never falls back, because the helper returns
    `NA_character_`, not `NULL`. The staged `stamp.txt` reads `fresh: 0.34.0 @ NA`. The
    installed fresh is a local build (built 2026-09-26 06:25 UTC, no `RemoteSha`) at a version
    above link's `Remotes:` pin (v0.33.0).
  - That line describes the fresh installed at analysis time. The query never calls fresh; the
    fresh that matters is the one that built `fresh_default`, which the persist `log` records
    and the stamp does not.
  - `link: 0.51.0 @ 9d1f975` is stamped with no dirty flag, and both producing scripts were
    uncommitted when the outputs were written. The SHA therefore names a tree that does not
    contain the code that made these numbers. `.lnk_pkg_git_dirty()` exists for this.

- **[fragile, reproducibility]** `data-raw/query_habitat_thresholds_obs.R:138-153`, `:193`, `:341`
  The `obs` query has no `ORDER BY`, and the dedup keeps `slice(1)` per location. The row kept
  is therefore whichever Postgres returned first. Gradient, width and flags are the same within
  a location (same segment), but `observation_key`, `match_class` and `source_ref` are not.
  `projects.csv` counts projects from the kept row's `source_ref`, so the project-dominance
  table can change between identical runs when two projects observed one location. Add
  `ORDER BY observation_key`, or arrange before `slice(1)`.

- **[fragile, interpretation]** `data-raw/query_habitat_thresholds_fiss.R:157-170` (`fiss_width_error.csv`)
  The `FIELD_MEASURMENT` row (median ratio 1.000, median |diff| 0.003 m, 93 % within 25 %)
  compares FISS-measured widths with segment widths whose source is a field measurement. That
  is very likely this same FISS measurement propagated into the channel-width layer, so the
  row is circular and says nothing about model error. Only the `MODELLED` row (n = 18) answers
  question 2 in the header. The file does not say so, and the README does not either. It needs
  one sentence before anyone quotes the 93 %.

- **[PWF integrity]** `planning/active/task_plan.md` Phase 1 boxes are ticked `[x]` for two
  things the code does not do:
  - "selection ratios by gradient and width bin, by region (top-level wscode) and width
    source": `selection.csv` is pooled, and only `quantiles.csv` splits by region and source.
  - "asserting exactly one segment per obs": the code resolves ties to the upstream segment
    and reports `n_cand`, with no assertion.

  Reword the boxes or implement them.

## Checked and fine

- PK joins: `streams` ↔ `streams_habitat_<sp>` on `(id_segment, watershed_group_code)` in
  both places. `observation_key` is unique in `bcfishobs.observations` (33,492 / 33,492 for
  CH/BT/DV), so the `t_obs*` joins do not fan out.
- NULL traps: no NULL `source`, `match_type` or `observation_key` in the exclusion set, so
  `LIKE`/`IN` cannot produce NA filter drops. The ledger totals match that.
- The obs-side `pred_set` (`waterbody_type` NA) and the avail-side (`waterbody_key IS NULL`)
  differ on exactly 1 segment province-wide.
- No WSG in fresh's `parameters_habitat_method.csv` uses the `mad` model, so the CH MAD
  columns do not act and the width decomposition holds.
- Segment pick: 9,588 of 9,763 A/B observations land on a segment starting at `round(m)`. The
  58 that pick a start above it are cases where the obs break coincided with an existing
  boundary < 1 m upstream, which matches the stated intent.
- The FISS site dedup is correct: 2,115 keys appear in exactly two files, with identical
  coordinates and `species_list`, each labelled with its file's WSG.
- `average_gradient_percent` has 469 non-NA values with a maximum of 0.43, which matches the
  comment.
- No absolute paths, host addresses or FISS site rows appear in any staged output.

planning/active/review-round1.md
