# Validate modelled habitat against fish observations

Scores a persisted run against fish observations rather than against
another model. For each watershed group and species it reports how many
observations land on modelled accessible, spawning and rearing segments
(**capture**), how much habitat the run models to achieve that
(**cost**, so capture cannot be bought by calling everything habitat),
and, for each observation outside modelled habitat, what excluded its
segment (**misses** — the direct evidence for which threshold is
binding). Sites sampled with the species not caught can be supplied as
**absences**, a false-positive check.

## Usage

``` r
lnk_habitat_validate(
  conn,
  aoi,
  cfg,
  loaded,
  species,
  schema,
  observations = "bcfishobs.observations",
  species_obs = list(BT = c("BT", "DV")),
  match_types = c("A", "B"),
  source_exclude = "Releases Database",
  buffer_m = 0,
  absences = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)).

- aoi:

  Character vector of watershed group codes. Each must be persisted in
  `schema`, with `streams_access` built (fails loud otherwise).

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md):
  the bundle that produced `schema`. Supplies the rules and thresholds
  for the miss reasons. Where `<schema>.log` records a WSG's run, its
  `config_name` must be `cfg$name`.

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Uses `observation_exclusions`, `wsg_species_presence`,
  `parameters_fresh` and (when present) `user_habitat_classification`.

- species:

  Character vector of model species codes (e.g. `c("CH", "BT")`). Each
  must name `<schema>.streams_habitat_<sp>` and
  `<schema>.streams_access.access_<sp>`.

- schema:

  Persist schema to score. Required: a bundle's `pipeline.schema` is not
  a reliable guide to which schema it built (`default` declares `fresh`,
  which the `bcfishpass` bundle writes).

- observations:

  Fish records: a schema-qualified table name (default
  `"bcfishobs.observations"`) or a data frame. Required columns:
  `species_code`, `watershed_group_code`, `blue_line_key`,
  `downstream_route_measure`, and for a table `observation_key`. A data
  frame without `observation_key` gets its own row numbers as keys, and
  then `loaded$observation_exclusions` must be `NULL` (the exclusions
  are matched on that key). Species and WSG codes are compared
  upper-cased and trimmed. Optional: `match_type`, `source`, `is_spawn`,
  `is_rear` (logical, 0/1 or t/true/yes), `activity_code`, `activity`,
  `life_stage`, and `observation_date`, which is required when
  `species_obs` carries a year limit (`obs_year_max`).

- species_obs:

  Which observation species count as each model species. Either a named
  list mapping a model species to observation species codes, applied in
  every WSG (default `list(BT = c("BT", "DV"))`, which pools DV records
  with BT), or a per-WSG data frame with `watershed_group_code`,
  `species_code` and `obs_species`, such as
  [`lnk_species_pooling()`](https://newgraphenvironment.github.io/link/reference/lnk_species_pooling.md)
  returns, optionally with `obs_year_max` (a pooled record counts only
  if dated in or before that year; an undated one does not). In the list
  form a species not named maps to itself; in the data frame form a
  species always counts as itself, and a WSG and species pair it does
  not list maps to itself only. Either way a species is scored only
  where `loaded$wsg_species_presence` marks it present.

- match_types:

  Character vector of `match_type` classes (first letter) to keep, or
  `NULL` for no match-type filter. Default `c("A", "B")`.

- source_exclude:

  Character vector of `source` prefixes to drop, or `NULL` for none.
  Default `"Releases Database"`.

- buffer_m:

  Numeric scalar \>= 0. Upstream distance within which modelled habitat
  still captures an observation. Default 0.

- absences:

  Optional data frame of sites sampled with the species not caught:
  `watershed_group_code`, `blue_line_key`, `downstream_route_measure`,
  `species_code` (model species). The caller locates them on the
  network. Rows for a species not present in the WSG are dropped.
  Absences are captured the same way observations are, `buffer_m`
  included, so the two rates stay comparable. A WSG x species with no
  rows in `absences` reports `NA` (not assessed), so pass only sites
  from the areas that were surveyed. Default `NULL`.

## Value

A list of two data frames:

- `summary`: one row per `watershed_group_code` x `species_code` x
  `stage` (`any`, `spawn`, `rear`), with `schema`, `config_name`,
  `buffer_m`, `overlay_applied`, `run_logged` (whether `<schema>.log`
  records the WSG), `n_obs` (locations on a segment), `n_unattached`,
  `n_accessible`, `n_inaccessible`, `n_spawning`, `n_rearing`,
  `n_rearing_any`, `n_habitat` (spawning or any rearing), the matching
  `share_*` (of `n_obs`; `NA` when `n_obs` is 0), `n_in_uhc_spawn`,
  `n_in_uhc_rear`, the `*_outside_uhc` counts and shares, and cost
  `accessible_km`, `spawning_km`, `rearing_km` from
  [`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md).
  With `absences`, also `n_absence`, `n_absence_accessible`,
  `n_absence_spawning`, `n_absence_rearing` (stream) and
  `n_absence_rearing_any` (the same on every stage). `model` is the
  WSG's habitat model (`cw` or `mad`).

- `observations`: one row per retained location, with its segment's
  `gradient`, `channel_width`, `channel_width_source`, `mad_m3s` and
  `mad_m3s_source` (`modelled` or the fill tier; on `mad` groups only,
  else `NA`), `edge_type`, `stream_order`, `waterbody_type`, `access`,
  `model`, the capture flags, `in_uhc_spawn`, `in_uhc_rear`, the
  predicate results (`pred_<stage>`, relaxed `_g`, `_w`, `_gw`, and on
  `mad` groups for a species with no MAD range `_nomad`, `_nomad_g`),
  and the two miss reasons.

## Details

Runs over two persist schemas (two config bundles) stack row-wise, so
bundles can be diffed on the same observations.

## Which observations count

`observations` is any source of fish records located on the FWA network:
`bcfishobs.observations` by default, or another table, or a data frame
of your own. From it, keeping:

- records not flagged `data_error` or `release_exclude` in
  `loaded$observation_exclusions` (matched on `observation_key`), and
  not from a `source` starting with any of `source_exclude` (by default
  the `Releases Database`: stocked fish are not evidence of habitat
  use);

- observation species admitted for the model species by `species_obs`,
  and only in WSGs where `loaded$wsg_species_presence` marks the model
  species present (so DV records count as BT only where BT is present);

- `match_type` classes in `match_types` (default A/B, bcfishobs's
  matches to a stream within 100 m; C, 100-500 m from a stream, and the
  D/E waterbody matches are left out);

- one per species x `blue_line_key` x metre (repeat visits are one
  location; a location is spawn- or rear-staged if any record there is).

Stage comes from `is_spawn` / `is_rear` where the source carries them,
and otherwise from bcfishobs's `activity_code`, `activity` and
`life_stage` wording; a record with neither counts in the `any` stage
only.

A filter whose column the source does not have is an error, not a silent
pass: set `match_types = NULL` or `source_exclude = NULL` for a source
without `match_type` or `source`. Pass a subset to score held-out
records (by project, date or WSG).

## Which segment an observation is on

The pipeline breaks streams at observations, so most points sit on a
segment boundary. The segment **starting** within 1 m of the point (the
upstream one) is used, else the one containing it. A location with no
segment is counted in `n_unattached` and nowhere else. All joins between
`streams`, `streams_access` and `streams_habitat_<sp>` are on the full
key `(id_segment, watershed_group_code)`: `id_segment` repeats across
groups.

`buffer_m > 0` also counts an observation as captured when modelled
habitat starts within `buffer_m` metres **upstream** along the same
`blue_line_key` and WSG, because observation points often mark the
downstream end of a sampled site. It follows the mainstem only (never a
tributary), stops at the WSG boundary, and is measured along the stream,
so it does not depend on segmentation. Accessibility is always the
point's own segment. Near lakes the buffer reaches connector flow lines,
which are rearing without any threshold test, so buffered rearing
capture there says nothing about thresholds.

## Reading the numbers

- **Accessible** is `streams_access.access_<sp> IN (1, 2)`, the
  definition
  [`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)'s
  `accessible_km` uses, so capture and cost agree. The spawning and
  rearing flags are gated by the pipeline's own
  `streams_habitat.accessible`, which differs slightly, so
  `share_spawning` is not strictly a subset of `share_accessible`.

- **Accessible capture is partly circular.** Observations are pipeline
  inputs: they lift barriers (`observation_threshold` in
  `parameters_fresh.csv`), they are break points, and where
  `apply_habitat_overlay` is on, `user_habitat_classification` forces
  habitat. Spawning and rearing capture is the score. `n_in_uhc_spawn` /
  `n_in_uhc_rear` count locations inside a `user_habitat_classification`
  reach confirming that habitat type for the species (indicator 1)
  anywhere in the window capture reads (the point's segment up to
  `buffer_m` upstream); with `overlay_applied` TRUE the segments wholly
  inside such a reach are forced to habitat, so most of those locations
  are captured by construction. `share_spawning_outside_uhc` and
  `share_rearing_any_outside_uhc` repeat the capture without them, which
  is the part of the score the observations did not decide.

- **Thresholds set from these observations score in-sample.** A cutoff
  calibrated on the same records (e.g. a use quantile) is partly
  guaranteed its capture; hold records out to score it fairly.

- `rearing` is stream rearing, the flag thresholds govern and that
  `rearing_km` costs. `rearing_any` adds lake and wetland rearing.

- Known biases, reported rather than corrected: observation points often
  sit at the downstream end of a site (see `buffer_m`); sampling
  clusters near road access; and fish are only observed where they have
  access, so observed gradients are cut off at the access limit.

## Miss reasons

`miss_reason_spawn` keys on `spawning` and `miss_reason_rear` on
`rearing_any`, so a location on lake or wetland rearing is captured for
the rear reason (compare them with `n_rearing_any`, not `n_rearing`).
Both re-evaluate the bundle's own habitat predicates
([`fresh::frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.html)
over `cfg$rules` and its thresholds CSV) on the segment, then again with
the gradient and the size each moved to the stage's minimum. The size is
the one the group classified on: the model `cfg`'s
`parameters_habitat_method.csv` gives the WSG, resolved as
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
resolves it (an unlisted group is `cw`). On `cw` it is the channel
width; on `mad` it is the mean annual discharge `mad_m3s`, joined from
`whse_basemapping.fwa_stream_networks_discharge` on `linear_feature_id`
because the persist does not carry it. When `cfg` fills discharge
(`cfg$pipeline$discharge_fill`), it is filled as prepare filled it: edge
1250 lines with no value take one along the network (`mad_m3s_source`
says which), and a `mad` group logged with the other fill state is an
error. The `width` labels below mean that size on either model; `model`
and `mad_m3s` split them:

- `NA` — captured; `no_segment` — the location attaches to no segment;

- `not_accessible` — the segment's `access_<sp>` is not 1 or 2;

- `fails_gradient` / `fails_width` / `width_null` — passes once that one
  value is relaxed (`width_null` when the width is NULL);
  `gradient_below_min` when the gradient fails by sitting below the
  window (a negative gradient), not above it;

- `fails_gradient_or_width` — either relaxation alone passes (through
  different branches of the rule);

- `fails_gradient_and_width` — passes only with both relaxed;

- `no_mad_threshold` — a `mad` group where the species has no MAD range
  for the stage (fresh then fails every inheriting stream rule outright)
  and supplying one would admit the segment; a segment with no discharge
  reads `width_null` instead, and one whose gradient also fails reads
  `fails_gradient_and_width`;

- `rule_excludes` — fails even then: edge type, waterbody or lake size;

- `post_predicate` — passes the predicate but is not habitat: removed by
  clustering (connectivity to spawning), access gating, or a lake /
  wetland bucket's `requires_connected: spawning` test (link#310), which
  runs after the predicate the validator re-tests.

The method table is the one in `cfg`. A run classified with another (a
swapped bundle file, or `lnk_pipeline_classify(method_csv =)`) is not
detected, so swap it on the `cfg` passed here too. A rule-level size
window in `rules.yaml` with a floor above the stage minimum would turn
size misses into `rule_excludes`; no bundled rules set one.

## See also

[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_habitat_validate_band()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate_band.md),
[`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

# How many CH and BT observations in Morice sit on modelled habitat in
# the `default` bundle's schema, and at what cost in km?
v <- lnk_habitat_validate(conn, aoi = "MORR", cfg = cfg, loaded = loaded,
                          species = c("CH", "BT"),
                          schema = "fresh_default")
v$summary[v$summary$stage == "rear",
          c("species_code", "n_obs", "share_rearing_any", "rearing_km")]

# What keeps the rearing misses out of habitat?
table(v$observations$miss_reason_rear, useNA = "ifany")
} # }
```
