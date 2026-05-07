# Findings — Stream-crossing accessibility labels: bcfishpass parity layer (#124)

## Issue context

link can't reproduce bcfishpass's stream-crossing accessibility labels. We currently produce:

- `severity` ∈ {high, moderate, low} on crossings (link's own scoring of culvert geometry)
- boolean `accessible` per segment in `<schema>.streams_habitat_<sp>`
- 5-bucket `mapping_code` ∈ {INACCESSIBLE, SPAWN, SPAWN_NO_REAR, REAR, ACCESSIBLE} in `streams_<sp>_vw`

bcfishpass produces a richer vocabulary that downstream tooling expects:

- `barrier_status` ∈ {PASSABLE, POTENTIAL, BARRIER, UNKNOWN} per crossing (PSCIS field result + override CSV)
- `access_<sp>` ∈ {-9, 0, 1, 2} per segment (species-absent / blocked / modelled-accessible / observed-upstream), with per-source downstream-barrier arrays
- `mapping_code_<sp>` semicolon-token compounds per segment (e.g. `ACCESS;MODELLED;INTERMITTENT`, `SPAWN;DAM`, `REAR;ASSESSED`)

We need parity for shared comparison + collaboration with bcfishpass, while keeping link's own severity scoring as a separate flexibility layer for project-specific metrics.

## bcfishpass DB inspection (2026-05-04 via db-newgraph MCP)

### `bcfishpass.crossings.barrier_status` — distribution

| barrier_status | count |
|---|---|
| POTENTIAL | 501,224 |
| PASSABLE | 19,925 |
| BARRIER | 11,219 |
| UNKNOWN | 816 |
| NULL | 29 |

Column comment (verbatim): *"The evaluation of the crossing as a barrier to the fish passage. From PSCIS, this is based on the FINAL SCORE value. For other data sources this varies. Acceptable Values are: PASSABLE - Passable, POTENTIAL - Potential or partial barrier, BARRIER - Barrier, UNKNOWN - Other"*

### `crossing_source × barrier_status` crosstab

- **MODELLED CROSSINGS** (513,739 rows): POTENTIAL 499,827 + PASSABLE 13,912. Modelled defaults to POTENTIAL until field-assessed.
- **PSCIS** (16,894 rows): BARRIER 8,761 / PASSABLE 5,932 / POTENTIAL 1,356 / UNKNOWN 816 / NULL 29.
- **CABD** (2,554 rows): BARRIER 2,441 / PASSABLE 81 / POTENTIAL 32 — mostly dams.
- **USER_CROSSINGS_MISC** (26 rows): BARRIER 17 / POTENTIAL 9.

### `bcfishpass.user_pscis_barrier_status.user_barrier_status` (override CSV → table)

| user_barrier_status | count |
|---|---|
| PASSABLE | 1,022 |
| BARRIER | 329 |
| POTENTIAL | 26 |

### `bcfishpass.streams_access.access_bt` — distribution

| access_bt | meaning | count |
|---|---|---|
| 0 | barriers downstream / blocked | 1,573,495 |
| 1 | modelled accessible | 1,296,503 |
| -9 | species not present in WSG | 1,236,905 |
| 2 | observed upstream | 123,378 |

### `bcfishpass.streams_access` columns

- **per-source dnstr arrays**: `barriers_anthropogenic_dnstr`, `barriers_pscis_dnstr`, `barriers_dams_dnstr`, `barriers_dams_hydro_dnstr`
- **per-species dnstr arrays**: `barriers_bt_dnstr`, `barriers_ch_cm_co_pk_sk_dnstr`, `barriers_ct_dv_rb_dnstr`, `barriers_st_dnstr`, `barriers_wct_dnstr`
- **per-species access codes**: `access_bt`, `access_ch`, `access_cm`, `access_co`, `access_pk`, `access_sk`, `access_salmon`, `access_ct_dv_rb`, `access_st`, `access_wct`
- **observation arrays**: `observation_key_upstr`, `obsrvtn_species_codes_upstr`, `species_codes_dnstr`
- **indicators**: `dam_dnstr_ind`, `dam_hydro_dnstr_ind`, `remediated_dnstr_ind`
- **all crossings dnstr**: `crossings_dnstr`

### `bcfishpass.streams_mapping_code` — schema + sample distribution

Wide per-species columns: `mapping_code_bt`, `mapping_code_ch`, `mapping_code_cm`, `mapping_code_co`, `mapping_code_pk`, `mapping_code_sk`, `mapping_code_st`, `mapping_code_wct`, `mapping_code_salmon`.

`mapping_code_bt` distinct values (top 25, excluding empty):

| mapping_code_bt | count | meaning |
|---|---|---|
| (empty `""`) | 2,810,400 | inaccessible (access_bt = 0 or -9) |
| ACCESS;MODELLED;INTERMITTENT | 213,372 | accessible (no PSCIS), dnstr modelled crossing, intermittent stream |
| SPAWN;NONE | 153,612 | spawn habitat, clean access |
| ACCESS;MODELLED | 139,622 | accessible, dnstr modelled crossing |
| ACCESS;NONE | 137,043 | accessible, no dnstr barriers |
| ACCESS;NONE;INTERMITTENT | 136,170 | accessible, no dnstr barriers, intermittent |
| ACCESS;DAM | 86,139 | accessible, dnstr of a dam |
| SPAWN;DAM | 84,429 | spawn habitat, dnstr of a dam |
| ACCESS;DAM;INTERMITTENT | 74,681 | accessible, dnstr of dam, intermittent |
| REAR;NONE | 73,563 | rearing habitat, clean access |
| REAR;MODELLED | 68,586 | rearing habitat, dnstr modelled crossing |
| SPAWN;MODELLED | 53,415 | spawn habitat, dnstr modelled crossing |
| REAR;DAM | 52,210 | rearing habitat, dnstr of a dam |
| ACCESS;ASSESSED;INTERMITTENT | 46,635 | accessible, dnstr PSCIS-assessed crossing, intermittent |
| ACCESS;ASSESSED | 31,856 | accessible, dnstr PSCIS-assessed crossing |
| REAR;ASSESSED | 17,319 | rearing habitat, dnstr PSCIS-assessed crossing |
| SPAWN;ASSESSED | 12,577 | spawn habitat, dnstr PSCIS-assessed crossing |
| (other intermittent variants) | < 12,000 each | combinations of above + INTERMITTENT |

Vocabulary: `{ACCESS | SPAWN | REAR | ""} ; {NONE | DAM | MODELLED | ASSESSED} [;INTERMITTENT]`.

### `bcfishpass.streams_bt_vw` — definition (verbatim from `pg_get_viewdef`)

```sql
SELECT s.segmented_stream_id,
    s.linear_feature_id,
    s.edge_type,
    s.blue_line_key,
    s.watershed_key,
    s.watershed_group_code,
    s.downstream_route_measure,
    s.length_metre,
    s.waterbody_key,
    s.wscode_ltree AS wscode,
    ...
    array_to_string(a.barriers_anthropogenic_dnstr, ';'::text) AS barriers_anthropogenic_dnstr,
    array_to_string(a.barriers_pscis_dnstr, ';'::text) AS barriers_pscis_dnstr,
    ...
    a.access_bt AS access,
    CASE WHEN a.access_bt = '-9'::integer THEN '-9'::integer ELSE h.spawning_bt END AS spawning,
    CASE WHEN a.access_bt = '-9'::integer THEN '-9'::integer ELSE h.rearing_bt END AS rearing,
    m.mapping_code_bt AS mapping_code,
    s.geom
FROM bcfishpass.streams s
LEFT JOIN bcfishpass.streams_access a ON s.segmented_stream_id = a.segmented_stream_id
LEFT JOIN bcfishpass.streams_habitat_linear h ON s.segmented_stream_id = h.segmented_stream_id
LEFT JOIN bcfishpass.streams_mapping_code m ON s.segmented_stream_id = m.segmented_stream_id
WHERE a.access_bt > 0;
```

Note `WHERE a.access_bt > 0` — bcfp's `streams_<sp>_vw` excludes inaccessible segments (access_bt ∈ {-9, 0}) entirely.

## bcfishpass SQL source — key files

- `bcfishpass/model/01_access/sql/load_crossings.sql:66-69` — `barrier_status` CASE: user_barrier_status overrides current_barrier_result_code from PSCIS.
- `bcfishpass/model/01_access/sql/load_streams_access.sql:42-129` — per-species access integer code derivation; tests `barriers_<sp>_dnstr is null` for accessibility.
- `bcfishpass/model/01_access/sql/barriers_user_definite.sql:28-32` — loads `user_barriers_definite` table from CSV.
- `bcfishpass/db/schema.sql:16538-16545` — `user_pscis_barrier_status` table definition (columns: stream_crossing_id, user_barrier_status, watershed_group_code, reviewer_name, reviewer_date, notes).

## link-side current state (relevant exports + gaps)

- `R/lnk_score.R` — `lnk_score(conn, crossings, method)` produces severity {high, moderate, low}.
- `R/lnk_source.R` — `lnk_source(conn, crossings, label_col="severity", label_map=c(high="blocked", moderate="potential"))` translates severity → fresh break-source labels.
- `R/lnk_load.R` / `R/lnk_override.R` — load + apply user_pscis_barrier_status.csv etc., but do NOT surface `barrier_status` directly on the crossings tibble.
- `R/lnk_pipeline_classify.R` — fresh's habitat classify produces boolean `accessible` per segment per species. NO integer code, NO dnstr-barrier arrays retained.
- `data-raw/build_species_views.R` — collapses boolean accessible + spawning + rearing into 5-bucket mapping_code via CASE: `INACCESSIBLE / SPAWN / SPAWN_NO_REAR / REAR / ACCESSIBLE`.
- After `lnk_pipeline_persist`: `<schema>.streams_habitat_<sp>` has only `(id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing)`. NO accessibility code per segment, NO downstream-barrier arrays.

## Implementation strategy

The plan adds three NEW per-segment outputs (additive, not replacement):

1. **`lnk_barrier_status()`** at crossing level — passthrough.
2. **`lnk_pipeline_access()`** at segment level — array_agg of dnstr barriers per source/species + integer access codes per species.
3. **`lnk_pipeline_mapping_code()`** at segment level — semicolon-token compound per species using bcfp's CASE expression.

Existing 5-bucket `mapping_code` view stays. Sibling `streams_<sp>_bcfp_vw` view added in Phase 4 for the bcfp-shape `mapping_code`. Replacement decision deferred until parity is verified.
