# data-raw/build_rules.R
#
# Regenerate both rules YAMLs from their dimensions CSVs.
# Run after editing either CSV.
#
# Usage:
#   source("data-raw/build_rules.R")

# newgraph defaults (categories: stream, canal, wetland)
link::lnk_rules_build(
  csv = "inst/extdata/parameters_habitat_dimensions.csv",
  to = "inst/extdata/parameters_habitat_rules.yaml"
)

# bcfishpass comparison variant (explicit edge_type integers)
link::lnk_rules_build(
  csv = "inst/extdata/configs/bcfishpass/dimensions.csv",
  to = "inst/extdata/configs/bcfishpass/rules.yaml",
  edge_types = "explicit"
)
