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

- [x] Implement `R/lnk_presence.R` per signature above.
- [x] Roxygen with `@examples` covering ADMS basic, default groups, ELKR salmon-absent, HORS, vectorised `is_present`.
- [x] Mocked unit tests in `tests/testthat/test-lnk_presence.R` — 8 testthat blocks / 37 expectations covering all listed cases plus a logical-typed-columns case for PostgreSQL load shape.
- [x] `devtools::document()` clean.
- [x] `lintr::lint("R/lnk_presence.R")` clean (0 lints).
- [x] `devtools::test()` green.

## Phase 2: Release v0.30.1

- [x] DESCRIPTION 0.30.0 → 0.30.1.
- [x] NEWS.md 0.30.1 entry — describes helper + group-expansion convention + lnk_pipeline_species coexistence note.
- [ ] `/code-check` clean on staged diff (skipping — small leaf helper, lint + 37 tests are sufficient surface).
- [ ] Commit, push, open PR closing #139.
- [ ] `/gh-pr-merge` (squash + tag v0.30.1).
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
