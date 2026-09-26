# Task: Validate modelled habitat against fish observations per species and watershed group (#283)

link compares its output with bcfishpass but never with fish observations. The only
observation-vs-model comparison is the Babine SK work (by hand, one species). #284 set
calibrated CH/BT thresholds in `default_tuned` and left them unscored pending this validator.

## Context
link scores itself only against bcfishpass (a model), never against fish. #284 just set
calibrated CH/BT thresholds in `default_tuned` and left them **unscored** — its step 5
waits on this validator. #284 also already wrote the hard SQL, one-off, in
`data-raw/query_habitat_thresholds_obs.R` (observation → segment the model tests, exclusion /
release / presence / match-type ledger, DV pooled with BT, stage from activity/life_stage).
#283 turns that into a package function plus a driver that emit a tidy
bundle × species × WSG table, so two bundles can be diffed.

**Measured during exploration (changes the issue body):**
- **fresh#218 is a join artifact, not duplication.** `fresh.streams_habitat_ch` is
  2,329,201 rows = 2,329,201 distinct `(id_segment, watershed_group_code)`; Naver Creek
  joins 187 rows on the full PK and 4,301 on bare `id_segment` (#203). The issue's
  "use the per-WSG schemas" guidance is unnecessary — the persist schemas are correct
  when joined on the full PK. Issue body gets corrected in Phase 1; fresh#218 gets a
  comment/edit offered separately (not in this PR).
- **Accessible capture is partly circular.** Observations are pipeline inputs: they lift
  barriers (`observation_threshold` BT 1, CH 5), are break points, and
  `user_habitat_classification` forces habitat. Report that, don't hide it: capture on
  spawning/rearing is the meaningful score; accessible capture is a sanity check, and
  observations on *inaccessible* segments are reported as access misses.
- `fresh_default` (55 WSGs) and `fresh` (bcfishpass config, 59 WSGs with access) share
  51 WSGs, both with `streams_access`. `fresh_default_tuned` does not exist yet.
  FISS snapshot WSGs in `fresh_default`: COTR, PINE, UPCE.

## Design
- **`lnk_habitat_validate(conn, aoi, cfg, loaded, species, schema = cfg$pipeline$schema,
  observations = "bcfishobs.observations", species_obs = list(BT = c("BT", "DV")),
  match_types = c("A", "B"), buffer_m = 0, absences = NULL)`** — noun_verb, issue's
  working name, `@family compare`. `aoi` is a vector of WSG codes.
- Returns `list(summary, observations)`:
  - `summary`: one row per `wsg × species × stage` (`any`, `spawn`, `rear`) with
    `n_obs`, `n_accessible`, `n_spawning`, `n_rearing`, `n_habitat` (spawn|rear),
    `share_*`, `n_inaccessible`, `n_in_uhc`, cost `accessible_km`, `spawning_km`,
    `rearing_km` (via existing `lnk_rollup_wsg()`), plus absence columns
    (`n_absence`, `n_absence_spawning`, `n_absence_rearing`) when `absences` is given,
    and `schema`, `config_name`, `buffer_m` so bundles stack.
  - `observations`: one row per retained location with segment `gradient`,
    `channel_width`, `channel_width_source`, `edge_type`, `waterbody_type`, flags, and a
    diagnostic `miss_reason` (`not_accessible`, `fails_gradient`, `fails_width`,
    `width_null`, `waterbody`, `connectivity` = passes predicate but not habitat) computed
    against the bundle's `parameters_habitat_thresholds.csv`. Labelled diagnostic: it
    approximates `rules.yaml`, it is not the rules.
- **Access = `streams_access.access_<sp> IN (1, 2)`**, same definition as
  `lnk_rollup_wsg()`'s `accessible_km`, so capture and cost agree. Fail loud when a WSG
  has no `streams_access` rows. (#284 used `streams_habitat.accessible`; the difference is
  noted in research.)
- **Segment attach = #284's rule** (segment starting within 1 m, i.e. upstream; else the
  containing one), all joins on the full PK. **`buffer_m`** extends capture upstream along
  the same `blue_line_key` (observation points sit at the downstream end of sites);
  default 0, the driver reports 0 and 100 as the sensitivity for that bias.
- Filters reuse the pipeline's logic: exclusions as `.lnk_pipeline_prep_observations()`,
  presence via `.lnk_wsg_species_present()`; `species_obs` admits DV only where BT is
  present (operator decision in #284). Stage regex moves from the #284 script into
  `.lnk_obs_stage()`.
- `absences`: generic frame `(watershed_group_code, blue_line_key,
  downstream_route_measure, species_code)`; the caller locates them. FISS parsing stays in
  the driver because `knowledge` is private — only aggregates are committed.

## Design changes from the plan review (review-plan.md, 2026-09-26)

- `schema` is **required** (B1): `default` declares `pipeline.schema: fresh`, which the
  bcfishpass bundle writes. Where `<schema>.log` records a WSG, its `config_name` must
  equal `cfg$name`; unlogged WSGs pass and are flagged `run_logged = FALSE`.
- Miss reasons re-evaluate the bundle's own predicates (`fresh::frs_habitat_predicates()`
  over `cfg$rules` + thresholds) with gradient / width relaxed (G1), instead of
  re-implementing the rules from the thresholds CSV.
- Unattached locations counted as `n_unattached`, not as inaccessible (G2).
- `rearing_any` (stream + lake + wetland) reported beside stream `rearing` (G3).
- `pg_temp.` on temp-table drops.

## Phases
### Phase 1: Correct the frame
- [x] Edit #283 body: fresh#218 finding (full-PK join is correct), circularity of
      accessible capture, the decided output shape
- [x] Record the fresh#218 measurement in `findings.md`

### Phase 2: Tests first
- [x] `tests/testthat/test-lnk_habitat_validate.R`: arg validation; `.lnk_obs_stage()`
      on activity/life_stage fixtures; `miss_reason` classification; summary shares
- [x] DB integration test (`skip_if_no_db()`) on a fixture schema `zz_lnk_validate_probe`
      with `streams`, `streams_habitat_bt`, `streams_access`, and a fixture observations
      table: two WSGs sharing `id_segment` values (full-PK guard — restore a bare join and
      watch it fail), an excluded key, a release, a DV record in a no-BT WSG, a buffer case,
      one absence

### Phase 3: `lnk_habitat_validate()`
- [x] `R/lnk_habitat_validate.R`: exported function + internal SQL builders / helpers
      (temp tables, parameterised; species alpha-validated as in `lnk_rollup_wsg()`)
- [x] Runnable-by-design `@examples` (`\dontrun{}`, DB required — same as siblings)
- [x] `devtools::document()`, tests green, `lintr::lint_package()` clean

### Phase 4: Driver + baseline run
- [ ] `data-raw/habitat_validate.R` (`--schemas=`, `--wsgs=`, `--species=`,
      `--buffers=0,100`, optional `LNK_KNOWLEDGE_DIR` for FISS absences via
      `lnk_points_snap()`), writes `data-raw/logs/habitat_validate_283/`: `summary.csv`,
      `misses_binned.csv` (gradient / width / edge-type bins, aggregates only),
      `diff.csv` (bundle A vs B per species × WSG × stage), `stamp.txt`
- [ ] Run read-only: `fresh_default` vs `fresh` on their 51 shared WSGs, CH + BT
- [ ] Sanity: summary obs counts reconcile with #284's ledger for `fresh_default`

### Phase 5: Record
- [ ] `research/habitat_validation.md` (method, biases incl. circularity, baseline
      numbers); index in `research/README.md`; point `research/habitat_thresholds.md`
      step 5 at it
- [ ] CLAUDE.md status above the marker; NEWS entry

## Out of scope
Running `default_tuned` / candidate thresholds — that is #284 step 5 and needs its own
run decisions (config, schema, closure, `dams`, `mapping_code`) stated at launch.

## Validation
- [ ] Tests pass (incl. DB fixture test), `devtools::check()` / lintr clean
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Verification
`Rscript -e 'devtools::test(filter = "habitat_validate")'`; then
`Rscript data-raw/habitat_validate.R --schemas=fresh_default,fresh --species=CH,BT`
and check `summary.csv` n_obs for `fresh_default` against
`data-raw/logs/habitat_thresholds_284/obs_ledger.csv` step 7 (same filters, access
definition aside).
