# Findings — Gradient classes: derive from parameters_fresh, optional override arg (#45)

## Surface area mapping (Plan-mode exploration, 2026-05-03)

### Hardcode #1: gradient class definitions

`R/lnk_pipeline_prepare.R:297-301` — passed to `fresh::frs_break_find()`:

```r
fresh::frs_break_find(conn, paste0(schema, ".streams_blk"),
  attribute = "gradient",
  classes = c("1500" = 0.15, "2000" = 0.20,
              "2500" = 0.25, "3000" = 0.30),
  to = paste0(schema, ".gradient_barriers_raw"))
```

Called from `lnk_pipeline_prepare()` at line 106. Signature today:
`.lnk_pipeline_prep_gradient(conn, aoi, loaded, schema)` — no `cfg`, no `classes`.

### Hardcode #2: per-model species filters

`R/lnk_pipeline_prepare.R:489-494`:

```r
models <- list(
  bt              = c(2500, 3000),
  ch_cm_co_pk_sk  = c(1500, 2000, 2500, 3000),
  st              = c(2000, 2500, 3000),
  wct             = c(2000, 2500, 3000)
)
```

Consumed at lines 505-521 via `WHERE gradient_class IN (...)` against `<schema>.gradient_barriers_raw`, plus UNION ALL with falls. Per-model output tables `<schema>.barriers_<model_name>` (e.g. `barriers_bt`, `barriers_ch_cm_co_pk_sk`) are passed to `fresh::frs_barriers_minimal()` at line 523, then unioned into `<schema>.gradient_barriers_minimal`.

### Downstream label coupling: safe

`R/lnk_pipeline_classify.R:203` derives labels from integer class values:

```sql
'gradient_' || lpad(g.gradient_class::text, 4, '0') AS label
```

So `1500` → `"gradient_1500"`. **No hardcoded `gradient_2500` strings exist downstream** — the labels are dynamically computed from whatever the integer class values are. Switching to a different class vector is safe at the downstream coupling point.

### Species enumeration helper exists

`R/lnk_pipeline_species.R:41-64` — `lnk_pipeline_species(cfg, loaded, aoi)`:

```r
intersect(
  cfg$species %||% unique(loaded$parameters_fresh$species_code),
  loaded$wsg_species_presence[[aoi]]
)
```

Already used in `prep_classify` and `prep_connect`. `.lnk_pipeline_prep_minimal()` does NOT currently use it (uses static groupings instead).

### `access_gradient_max` data

**`inst/extdata/configs/bcfishpass/parameters_fresh.csv`:**

| Species | access_gradient_max | bcfp model group |
|---------|---------------------|------------------|
| BT, CT, DV, RB | 0.25 | bt |
| CH, CM, CO, PK, SK | 0.15 | ch_cm_co_pk_sk |
| ST | 0.20 | st |
| WCT | 0.20 | wct |

**`inst/extdata/configs/default/parameters_fresh.csv`:**

Adds GR=0.15, KO=0.15. Not declared `extends: bcfishpass` — standalone CSV.

The hardcoded `models` list maps directly: `bt = c(2500, 3000)` ⟺ classes ≥ 0.25 (BT's threshold). The `3000` bin is bcfp convention — no species needs it (every position ≥0.30 is also ≥0.25 → already labelled "2500"). Dropping it would be functionally equivalent on bcfp config but loses bcfp-label parity.

### Existing tests

`tests/testthat/test-lnk_pipeline_prepare.R`:

- Lines 71-93: `prep_gradient` SQL shape (mocked). Doesn't assert the `classes` vector contents.
- Lines 206-237: `prep_minimal` builds 4 per-model tables and unions them. Doesn't assert the `models` list contents.

Tests use `local_mocked_bindings()` for DB mocking — no real-DB tests in this file.

### `compare_bcfishpass_wsg.R` integration point

Lines 78-80:

```r
link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = config,
  loaded = loaded, schema = schema,
  conn_tunnel = if (dams) conn_ref else NULL)
```

No `classes` argument today. After this PR: still no `classes` argument needed because the default (NULL → hardcoded bcfp vector) preserves current behaviour.

### Coupling risks summarised

1. **Per-species union ≠ per-group union** if `access_gradient_max` isn't consistent within bcfp groups. Within bcfishpass `parameters_fresh.csv` it IS consistent (CH/CM/CO/PK/SK all 0.15, ST/WCT both 0.20, BT/CT/DV/RB all 0.25), so the union is mathematically equivalent. Verified pre-implementation.
2. **Per-group intermediate tables (`barriers_bt`, `barriers_ch_cm_co_pk_sk`, etc.) cease to exist** — replaced with `barriers_<sp>`. Need to grep for downstream references before flipping.
3. **YAML coercion**: `pipeline.gradient_classes: {1500: 0.15, ...}` reads as named list; need `unlist()` to get named numeric.
4. **NA / zero `access_gradient_max`**: lake-only or non-modelled species. Skip path is explicit, no per-species barrier table. Test required.

### Issue #45 cross-references

- Companion to #44 (closed) — both touch `R/lnk_pipeline_prepare.R` but different sub-helpers, parallel-safe.
- Related: #52 (research) — channel-class breaks for habitat. Different concept.
- fresh#127 (closed), fresh#86 (closed) — already shipped the underlying `frs_break_find` capability.
- #75 — `dimensions_columns.csv` source-of-truth. Doesn't gate this PR.

## Issue context

(full issue body from `gh issue view 45` 2026-04-23, see comment thread)

`R/lnk_pipeline_prepare.R` carries two hardcoded lists that encode bcfishpass's gradient-classification scheme directly in pipeline code. Both belong at the config/derivation layer.

[See planning baseline commit for full quoted issue body.]
