# Findings

## fresh 0.19.0 API to use

```r
fresh::frs_habitat_classify(conn, table, to,
  species = ..., params = ..., params_fresh = ...,
  gate = TRUE, label_block = "blocked",
  barrier_overrides = "<schema>.barrier_overrides",
  known = "<schema>.user_habitat_classification",   # NEW
  overwrite = TRUE, verbose = TRUE)
```

When `known` is non-NULL, classify calls `frs_habitat_overlay(conn, table = to, known = known, species = species, verbose = verbose)` after the rule-based classification finishes.

## user_habitat_classification table shape

From `R/lnk_pipeline_prepare.R` (line 170+):

```sql
CREATE TABLE <schema>.user_habitat_classification (
  -- exactly the bcfishpass user_habitat_classification.csv schema
  -- has linear_feature_id, blue_line_key, downstream_route_measure,
  -- upstream_route_measure, plus per-species spawning_<sp> and
  -- rearing_<sp> columns
)
```

Loaded from `inst/extdata/configs/<bundle>/overrides/user_habitat_classification.csv` by `.lnk_pipeline_prep_load_aux()`.

The default join key in `frs_habitat_overlay` is `c("blue_line_key", "downstream_route_measure")` — matches the loaded columns directly. No custom `by =` needed.

## Gating: table presence check

`lnk_pipeline_prepare` only loads `user_habitat_classification` when `cfg$overrides` declares it. Same pattern in `lnk_pipeline_classify`: gate on `cfg$overrides$user_habitat_classification` being non-NULL before passing `known =`.
