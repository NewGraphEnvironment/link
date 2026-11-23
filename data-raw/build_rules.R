# data-raw/build_rules.R
#
# Regenerate both rules YAMLs from their dimensions CSVs.
# Run after editing either CSV, or a bundle's parameters_habitat_thresholds.csv
# (its rear_lake_ha_min is baked into the rules).
#
# Usage:
#   Rscript data-raw/build_rules.R
#
# Builds with the source tree's lnk_rules_build() (load_all), not an
# installed link, so an edit to the builder reaches the rules it writes.

pkgload::load_all(quiet = TRUE)

# Default rules: explicit FWA edge_type codes [1000, 1100, 2000, 2300]
# for spawn + rear-stream rules. Drops 1050/1150 (stream-thru-wetland)
# and 2100 (rare double-line canal). Matches bcfishpass's 20-year-
# validated convention. The dedicated wetland-rear rule still uses
# c(1050L, 1150L) hardcoded — unaffected by this setting.
#
# Authoritative source — lives at top-level inst/extdata/ for any caller
# of frs_params() with no config. ALSO mirrored into configs/default/
# so the config bundle is self-contained.
lnk_rules_build(
  csv = "inst/extdata/parameters_habitat_dimensions.csv",
  to = "inst/extdata/parameters_habitat_rules.yaml",
  edge_types = "explicit"
)
lnk_rules_build(
  csv = "inst/extdata/configs/default/dimensions.csv",
  to = "inst/extdata/configs/default/rules.yaml",
  thresholds = "inst/extdata/configs/default/parameters_habitat_thresholds.csv",
  edge_types = "explicit"
)

# bcfishpass comparison variant (same explicit codes, different dimensions)
lnk_rules_build(
  csv = "inst/extdata/configs/bcfishpass/dimensions.csv",
  to = "inst/extdata/configs/bcfishpass/rules.yaml",
  thresholds = "inst/extdata/configs/bcfishpass/parameters_habitat_thresholds.csv",
  edge_types = "explicit"
)
