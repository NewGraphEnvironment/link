# Findings — lnk_wsg_resolve (#207)

## Issue context

### Problem

`data-raw/study_area_wsgs.R` does three things inline:
1. Read `public.wsg_outlet`, compute drainage closure (DS-first)
2. Species-filter via the bundle's `wsg_species_presence` (#157)
3. Print a comma list to stdout

It's callable only from bash. Not testable. Not reusable from R sessions, vignettes, or other drivers. The "what WSGs should we model?" decision is captured in a script when it should be a function.

### Proposed

```r
lnk_wsg_resolve(cfg, loaded, wsgs = NULL, expand = TRUE)
```

| Param | Role |
|---|---|
| `cfg` | `lnk_config()` manifest |
| `loaded` | `lnk_load_overrides(cfg)` — carries `wsg_species_presence` for the #157 filter (consistent with the rest of link's API) |
| `wsgs` | character vector of seed WSGs; `NULL` = all bundle-species WSGs (province mode) |
| `expand` | when `wsgs` is non-NULL: `TRUE` (default) = closure-expand via `fresh::frs_wsg_drainage`; `FALSE` = use as-is (species-filter only) |

Returns: character vector of WSG codes, DS-first ordered when expanded.

### Three call patterns

```r
lnk_wsg_resolve(cfg, loaded)                                    # province (all bundle-species WSGs)
lnk_wsg_resolve(cfg, loaded, wsgs = c("PARS","BULK"))           # study-area + drainage closure (default)
lnk_wsg_resolve(cfg, loaded, wsgs = c("BBAR","BULK"),
                expand = FALSE)                                  # exactly these, species-filtered, no closure
```

### Acceptance

- [ ] `lnk_wsg_resolve(cfg, loaded, wsgs = c("PARS","BULK"))` reproduces the current `study_area_wsgs.R` output: `KISP,KLUM,LKEL,LSKE,MSKE,USKE,BULK,FINA,LBTN,LPCE,MORR,PARA,PCEA,UPCE,PARS` (15 WSGs)
- [ ] `lnk_wsg_resolve(cfg, loaded)` returns the full bundle-species province list
- [ ] `expand = FALSE` returns input verbatim (after species-filter)
- [ ] Tests for all three call patterns
- [ ] Runnable `@example`
- [ ] `data-raw/study_area_wsgs.R` rewritten as CLI shim; `study_area_run.sh` adapted, interface unchanged

### Blocked on / Composes with

- NewGraphEnvironment/fresh#211 (`frs_wsg_drainage`) — **SHIPPED v0.32.0** (now unblocked)
- #157 (species-presence filter — the rule this function applies)

## Codebase exploration

### `lnk_config()` shape (`R/lnk_config.R`)

Returns manifest with `cfg$species` (UPPERCASE character vector from rules.yaml keys, line 121: `rules_species <- names(yaml::read_yaml(rules_path))`), `cfg$rules`, `cfg$dimensions`, `cfg$files`, `cfg$pipeline`, `cfg$provenance`, `cfg$extends`. Class: `c("lnk_config", "list")`.

### `loaded$wsg_species_presence` shape

Tibble columns:
- `watershed_group_code` — UPPERCASE WSG identifier (e.g. "BULK")
- Per-species columns LOWERCASE: `bt, ch, cm, co, ct, dv, pk, rb, sk, st, wct`
- Optional `notes`
- Values: `"t"` (present) / `"f"` (absent) as STRINGS

### Species filter idiom (`study_area_wsgs.R:60-64` and `wsgs_run_host.R:91-96` — two callers)

```r
spp_cols <- tolower(cfg$species)
wp       <- loaded$wsg_species_presence
has_spp  <- apply(wp[, spp_cols, drop = FALSE], 1,
                  function(r) any(r %in% c("t", "TRUE", TRUE)))
modelable <- wp$watershed_group_code[has_spp]
```

Defensive against format drift (matches `"t"`, `"TRUE"` string, or `TRUE` boolean).

### Closest sibling: `lnk_pipeline_species(cfg, loaded, aoi)` (`R/lnk_pipeline_species.R:41`)

Same `cfg` + `loaded` validation pattern. Uses helper `.lnk_wsg_species_present(row)` from `R/utils.R:135` which works on ONE row (one WSG). The new function needs the vectorized form (all rows), which matches the `apply()` idiom in the inline scripts above.

### Tests

`tests/testthat/test-lnk_pipeline_species.R` uses both inline live `lnk_config("bcfishpass")` + `lnk_load_overrides(cfg)` AND stub fixtures:

```r
cfg_stub <- structure(list(
  species = c("BT", "CH", "CO", "SK", "ST", "WCT")
), class = c("lnk_config", "list"))
loaded_stub <- list(
  wsg_species_presence = data.frame(
    watershed_group_code = "ELKR",
    bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
    pk = "f", rb = "f", sk = "f", st = "f", wct = "t",
    stringsAsFactors = FALSE
  )
)
```

`skip_if_no_db()` helper (in `tests/testthat/setup.R`) gates live tests.

### fresh dep + import idiom

DESCRIPTION line 33: `Remotes: NewGraphEnvironment/fresh@v0.31.0` → needs bump to `@v0.32.0`. Convention: qualified calls (`fresh::frs_wsg_drainage()`) rather than `@importFrom`.

### CLI shim (`study_area_wsgs.R`)

Args parsing (lines 23-29): `args <- commandArgs(trailingOnly = TRUE)`; focal WSGs from `args[1]` (comma-separated, uppercased); config from `args[2]` (default `"bcfishpass"`). LNK_LOAD env idiom (lines 31-35): `loadall` → `pkgload::load_all`, else `library(link)`. Lines 39-41 open conn directly to `localhost:5432/fwapg postgres/postgres`. Lines 43-74 = inline closure + filter (the part being replaced).

### `study_area_run.sh` interface

`DISP_BUCKET=$(Rscript data-raw/study_area_wsgs.R "${FOCAL_ARR[0]}")` — captures stdout; bash `set -euo pipefail` means non-zero exit aborts. Stderr (warnings, messages) goes to logs but doesn't break the script. Implication: fresh#211's `warning()` on unmatched focals will appear in logs but not break anything; stdout must remain a single comma-separated WSG line.

### Naming / family

No existing `lnk_wsg_*` exports (only `lnk_compare_wsg` which is `@family compare`). New `@family wsg` recommended — pre-stages the family per issue body.
