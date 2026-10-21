# Progress — Through-wetland stretches: use the stream door plus a near-river test, not a free pass (#364)

## Session 2026-10-21

- Plan gate: the parked v3 plan in the issue body was presented as the draft and approved. It was verified against both repos first: no R/inst/tests commit on link or fresh main since the body was written.
- Created branch `364-through-wetland-stretches-use-the-stream` off main.
- Scaffolded the PWF baseline with the approved phases.
- Next: Phase 0 in fresh (`/planning-init fresh#263`, sequenced with fresh#262).
- Phase 0 in fresh: branch `263-inherit-near-river-from-the-thresholds-c`, three phases committed, `/code-check branch` in progress. fresh 0.42.0 is installed locally from a copy with only the version bumped; the fresh release commit comes after the review.
- Phase 1: `Imports: fresh (>= 0.42.0)`, `Remotes: NewGraphEnvironment/fresh@v0.42.0`. The tag does not exist until the fresh PR merges, so CI cannot install it before then. Preflight gains `frs_habitat_predicates(near_river_table)` and `.frs_near_river_specs`. Suite on the Phase 1 tree alone, in a worktree: 3,415 expectations, 2 failures, 0 errors, 6 skips. Both failures are the known stale golden dams pin (8 ADMS dams; `cabd.dams` gives 7; CLAUDE.md 2026-10-16), not this change.
- Phase 2: `rear_wetland_flow` and `rear_near_river` in `lnk_rules_build()`, both dictionaries, and the bundle columns. The bundles get NA thresholds columns; `default` takes `free` / `both`, and `bcfishpass` gives CO `gradient`. The rules diff is as intended. Every river-polygon rule gains `near_river: false`. bcfishpass CO's 1050/1150 rule gains `gradient: [0, 0.0549]`; `default` changes only by the stamps. The 1050/1150 rule is emitted as codes in categories mode too, and no shipped bundle builds in categories mode. A fixture frozen from the 0.66.7 builder (`tests/testthat/fixtures/rules_build_0667/`) checks that the new builder differs only by those changes. `regen_provenance.R` resolves its root from its own location, covers `default_tuned` and the thresholds CSV, and leaves 0 drifted entries in all three bundles. `audit_configs.R` exits 0, with two narrow rules for the frozen bundles. Near-river columns absent altogether are not "stale", because fresh reads them as NA; a partial set still flags. Rules that differ only by `near_river: false` match when the bundle's thresholds carry no near-river column, where the stamp is inert. Builder tests: 323 expectations; dictionaries 99.
- Phase 3, code:
  - The discharge reader is renamed `.lnk_discharge_read_rules()` and answers through fresh's `.frs_near_river_specs()` (`.lnk_near_river_pairs()`).
  - `<schema>.streams_near_river` is created by persist init and copied by persist; a WSG's rows are always deleted. Classify drops a stale working near-river table first.
  - `log.near_river` holds the pair text.
  - The validator refuses a schema without the table when cfg reads a pair, and a log whose pairs differ. It passes the persisted table to both predicate calls.
  - Statement counts move 8 to 9 and 7 to 8.
  - Consolidate discovers tables by `watershed_group_code`, so the new table travels. `study_area_verify.sql` enumerates habitat tables only, so nothing there changes.
- Phase 3, verification on ADMS (`data-raw/logs/wetland_door_364/verify_phase3_adms.txt`): the test bundle (CH stream door, pair model / 15 m / 3 m3/s / 1000 m) runs end to end in 2.3 min.
  - 5,849 near-river rows are persisted, and the log reads `channel_width:15:1000`.
  - The validator scores CH: 11 locations, 0 post_predicate.
  - `default` filled and unfilled give the same habitat digest.
- Width for 3 m3/s: 15 m (`data-raw/query_mad_width_equivalent.R`; the 15 m bin, n 600, median 3.29). The narrowest bin with n >= 100 whose median reaches 3 m3/s; a "stays above" rule read noise in the sparse bins over 20 m and gave 44 m.
- Phase 4, harness. `habitat_variants_build.R` and `_score.R` learn three things.
  - A `dims` column holds cells of the variant species' row in the base's `dimensions.csv`. The variant writes its own `dimensions.csv` and a rebuilt `rules.yaml`, both with provenance entries the verify loop reads.
  - A structure row class: no column, on `cw`, from the base, with `dims` and/or `set`. It is scored against the base in `structure_bands*.csv` and kept out of ladders.
  - `set` may name `*_river_*` cells. `built.csv` gains `rules_sha256` and `dimensions_sha256`, NA for older rows, which only a variant without dims may have. Ladders hold `dims` fixed like `set`. A near-river ladder's first step (base cell NA) is an anchor like a model change, and its core leaves the base out.
  - The score's known-habitat guard now looks only at the scored groups: per flag for a structure row (a biased flag is skipped and named), per step for a ladder (still a stop). CH's reaches in the five groups are all spawning.
- Pre-flight on SQAM, build 8.3 min:
  - An inert `dims` change (`notes`) persists CH habitat identical to the base (md5 c8abbeb5…).
  - The stream door moves 2.7 km out of CH rearing and 0.2 km in.
  - `ch_w30` is taken as the pair anchor.
  - The score refuses a bundle whose `rules.yaml` changed after the build.
