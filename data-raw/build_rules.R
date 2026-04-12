# data-raw/build_rules.R
#
# Regenerate both rules YAMLs from their dimensions CSVs.
# Run after editing either CSV.
#
# Usage:
#   source("data-raw/build_rules.R")

# NGE defaults (categories: stream, canal, wetland)
link::lnk_rules_build(
  csv = "inst/extdata/parameters_habitat_dimensions.csv",
  to = "inst/extdata/parameters_habitat_rules.yaml"
)

# bcfishpass v0.5.0 comparison (explicit edge_type integers)
link::lnk_rules_build(
  csv = "inst/extdata/parameters_habitat_dimensions_bcfishpass.csv",
  to = "inst/extdata/parameters_habitat_rules_bcfishpass.yaml",
  edge_types = "explicit"
)
