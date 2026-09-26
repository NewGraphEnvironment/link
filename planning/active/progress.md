# Progress — Region-scoped DV→BT observation pooling (#290)

## Session 2026-09-26

- Plan-mode exploration; phases approved by the operator
  - `wsg_regions.csv` is package-level; the resolver is `lnk_species_pooling()`
  - Mid-plan refinement: pooling is abstract (species or group on either side of a row)
- Created branch `290-region-scoped-dv-bt-observation-pooling` off `origin/main` (`aa02738`, v0.52.0). Local `main` still carries the unpushed `997b876` (MCGR run logs), which is left untouched.
- Scaffolded the PWF baseline
- Next: Phase 1
- Phase 1: `data-raw/wsg_regions.R` builds `inst/extdata/wsg_regions.csv`. It covers 246 groups in 17 regions (Haida Gwaii spans codes 940 and 950), and Kootenay (7 WSGs: BULL, DUNC, ELKR, KOTL, KOTR, SLOC, SMAR) is the one sub-region. The rebuild is idempotent (`cmp`).
  - The guards were proven in a scratch copy: an unmatched prefix, a comma in a name and a missing region row each exit 1 with the named cause.
  - Review: self-review and the mutation test. The `/code-check` skill runs on the resolver diff (Phase 2), which carries the logic.
  - #290's body was edited: regions are package-level, and pooling is abstract (species or group on either side).
