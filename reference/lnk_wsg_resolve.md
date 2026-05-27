# Resolve the Set of Watershed Groups to Model

Bundle-aware WSG resolver. Given a config + loaded overrides and an
optional focal set, returns the character vector of WSG codes that
should be modelled — composing FWA drainage closure (via
[`fresh::frs_wsg_drainage()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_drainage.html))
with the bundle's species-presence filter (link#157).

## Usage

``` r
lnk_wsg_resolve(cfg, loaded, wsgs = NULL, expand = TRUE)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list of tibbles from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Must carry `wsg_species_presence`.

- wsgs:

  Character vector of focal WSG codes, or `NULL` (default) for province
  mode. Codes are upper-cased internally before use.

- expand:

  Logical. When `wsgs` is non-`NULL`, `TRUE` (default) closure-expands
  via
  [`fresh::frs_wsg_drainage()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_drainage.html);
  `FALSE` uses the input as-is (species-filter only).

## Value

Character vector of WSG codes. Province mode returns the
species-filtered set sorted alphabetically; closure mode preserves the
downstream-first order from
[`fresh::frs_wsg_drainage()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_drainage.html);
strict mode preserves the caller-provided focal order. WSGs dropped by
the species filter (closure / strict modes) are reported via
[`message()`](https://rdrr.io/r/base/message.html).

## Details

Three call patterns dispatched by `wsgs` + `expand`:

- `wsgs = NULL` — *province mode*: every WSG in
  `loaded$wsg_species_presence` that has at least one of `cfg$species`
  flagged present.

- `wsgs = c(...)` + `expand = TRUE` (default) — *closure mode*: expand
  the focal set to its drainage closure (focal + every WSG they flow
  through, ordered downstream-first), then species-filter. Opens a
  connection via
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
  and closes it on exit.

- `wsgs = c(...)` + `expand = FALSE` — *strict mode*: species-filter the
  input verbatim, no closure expansion, no DB.

Species filter: a WSG is kept if *any* of `tolower(cfg$species)` columns
in `loaded$wsg_species_presence` carries `"t"` (or `"TRUE"` / `TRUE`,
defensively). DS-first ordering from the closure is preserved.

## Examples

``` r
if (FALSE) { # \dontrun{
cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

# Province mode — all bundle-species WSGs
lnk_wsg_resolve(cfg, loaded)

# Study-area mode — focal + drainage closure (default)
lnk_wsg_resolve(cfg, loaded, wsgs = c("PARS", "BULK"))
#> [1] "KISP" "KLUM" "LKEL" "LSKE" "MSKE" "USKE" "BULK" "FINA"
#>     "LBTN" "LPCE" "MORR" "PARA" "PCEA" "UPCE" "PARS"

# Strict mode — exactly these, species-filtered, no closure
lnk_wsg_resolve(cfg, loaded, wsgs = c("BBAR", "BULK"), expand = FALSE)
} # }
```
