# Findings: ADMS Comparison

## bcfishpass code review findings

- `break_streams('crossings', wsg)` breaks at ALL crossings — confirmed from SQL function source
- barrier_status only used in `load_streams_access.sql` for access codes (0/1/2)
- `load_dnstr()` indexes downstream features as ID arrays per segment
- Access codes: 0 = barrier downstream, 1 = no barrier but unconfirmed, 2 = confirmed by observations
- ADMS uses model = "cw" (channel width), species BT and CO

## Parameter differences
- `parameters_habitat_thresholds.csv` identical between fresh and bcfishpass
- `parameters_fresh.csv` adds `spawn_gradient_min` (0.0025) — bcfishpass doesn't use this
- For comparison: set spawn_gradient_min = 0

## Function consolidation (completed)
- 12 → 8 functions
- Key renames: lnk_break_source → lnk_source, lnk_habitat_upstream → lnk_aggregate
- lnk_match now handles xref_csv directly (no separate PSCIS/MOTI wrappers)

## Comparison results
*To be filled after running compare_adms.R*
