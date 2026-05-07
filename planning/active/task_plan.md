# Task: lnk_presence — presence helper with species-group expansion (#139)

## Plan

Small helper that builds structured WSG species-presence info, knowing about bcfp's species groups (salmon = CH/CM/CO/PK/SK; ct_dv_rb = CT/DV/RB). Replaces hand-rolled `wsg_presence` list construction repeated across test scripts + makes "absent species → skip" automatic in pipeline functions.

`lnk_pipeline_species(cfg, loaded, aoi)` already returns the intersection of (config species ∩ AOI present species) as a character vector — but it doesn't expose group expansion, an `is_present(sp)` predicate, or the raw row. The repeated open-coding of "is salmon any-present?" across test scripts is the symptom.

Ships #139 as a leaf utility; #135 picks up consumption.

## Phase 1: `R/lnk_presence.R` (~30 lines + roxygen + tests)

### Signature

```r
lnk_presence(
  wsg_species_presence,
  aoi,
  groups = list(
    salmon   = c("ch", "cm", "co", "pk", "sk"),
    ct_dv_rb = c("ct", "dv", "rb")
  )
)
```

- `wsg_species_presence`: tibble matching the `loaded$wsg_species_presence` shape. Columns: `watershed_group_code`, then per-species (`bt`, `ch`, ...). Values typically `"t"` or `""`/`NA` (CSV-loaded).
- `aoi`: character WSG code, single value.
- `groups`: named list of character vectors. Default mirrors bcfp's `wsg_salmon` + `wsg_ct_dv_rb` JOIN logic in `load_streams_access.sql`.

### Return

A list with:
- `$present` — character vector of species codes present in the AOI **after group expansion** (a species in a group is present iff any group member is present).
- `$absent` — character vector of all species columns NOT in `$present`.
- `$is_present(sp)` — function. `TRUE` if `sp %in% $present`, `FALSE` otherwise. Vectorised.
- `$row` — the raw tibble row for the AOI (1 row).
- `$aoi` — echo of input AOI.

### Behaviour

- AOI not in table: stop with informative error ("AOI 'XYZ' not in wsg_species_presence — known WSGs: ...").
- Group with all-NULL members: that group's species stay absent (no-op expansion).
- Group with any-TRUE member: ALL group members become present (matches bcfp).
- Species with multiple group memberships: present if any of its groups expand it (defensive, doesn't matter for default groups since they're disjoint).
- `groups = list()` (empty): no expansion, returns raw per-species presence only.

### Tasks

- [ ] Implement `R/lnk_presence.R` per signature above.
- [ ] Roxygen with `@examples` covering: ADMS basic, ADMS with default groups, ELKR (salmon absent → CH/CM/CO/PK/SK absent), HORS (ST absent), `is_present` vectorised call.
- [ ] Mocked unit tests in `tests/testthat/test-lnk_presence.R`:
  - basic case: ADMS row → BT/CH/CO/CT/DV/RB/SK present, ST/WCT absent (without group expansion)
  - group expansion: ELKR with salmon all-NULL → CH/CM/CO/PK/SK absent
  - group expansion: a fictional row with only CH=t → CH/CM/CO/PK/SK all present (group spreads)
  - `is_present(sp)` returns correct boolean (single + vectorised)
  - missing AOI errors with informative message
  - `groups = list()` opt-out: no expansion happens
- [ ] `devtools::document()` clean.
- [ ] `lintr::lint("R/lnk_presence.R")` clean.
- [ ] `devtools::test()` green.

## Phase 2: Release v0.30.1

- [ ] DESCRIPTION 0.30.0 → 0.30.1.
- [ ] NEWS.md 0.30.1 entry: one paragraph describing the helper + group-expansion convention. Note that `lnk_pipeline_species()` is the predecessor (returns just the intersection vector, no group awareness).
- [ ] `/code-check` clean on staged diff.
- [ ] Commit, push, open PR closing #139.
- [ ] `/gh-pr-merge` (squash + tag v0.30.1).
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
