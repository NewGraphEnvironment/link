# data-raw/build_rules.R
#
# Regenerate both rules YAMLs from their dimensions CSVs.
# Run after editing either CSV.
#
# Usage:
#   source("data-raw/build_rules.R")

# newgraph defaults (categories: stream, canal, wetland)
# Authoritative source — lives at top-level inst/extdata/ for any caller
# of frs_params() with no config. ALSO mirrored into configs/default/
# so the config bundle is self-contained.
link::lnk_rules_build(
  csv = "inst/extdata/parameters_habitat_dimensions.csv",
  to = "inst/extdata/parameters_habitat_rules.yaml"
)
link::lnk_rules_build(
  csv = "inst/extdata/configs/default/dimensions.csv",
  to = "inst/extdata/configs/default/rules.yaml"
)

# bcfishpass comparison variant (explicit edge_type integers)
link::lnk_rules_build(
  csv = "inst/extdata/configs/bcfishpass/dimensions.csv",
  to = "inst/extdata/configs/bcfishpass/rules.yaml",
  edge_types = "explicit"
)
