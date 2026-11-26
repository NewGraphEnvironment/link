# discharge_wet_331

Outputs of `data-raw/query_habitat_thresholds_mad.R` (#331, the `mad_*` directories).

## Since #356 (2026-11-23)

The scripts that wrote these files now sum `length_metre` exactly (`::numeric`) and read the sums in a fixed row order, so two reruns on an unchanged database give byte-identical files (measured in #478). The CSVs here are kept as the records of the runs that produced them: a rerun may change the last digits of their `km` and share columns, which means nothing about the method.
