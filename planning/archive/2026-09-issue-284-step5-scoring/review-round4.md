# Code review, round 4 (enumeration): staged diff for #284 step 5

Mechanism under test: **a partial producer read by a whole-population reader.**
Probes ran in the scratchpad (`r4/gap.R`) and read-only against docker fwapg; no repo
file other than this one was touched.

## Enumeration

| # | place | verdict | evidence |
|---|---|---|---|
| 1 | `lnk_habitat_validate_band()` reading `streams_habitat_<sp>` in every schema | **HOLDS** | `.lnk_hvb_check_habitat()` (R/lnk_habitat_validate_band.R:117, 226-247). Round 3's probe re-run on the pre-flight schemas (`species = c("BT","RB")`, `score284_bt_rear_0p1249` vs `score284_default`, BULL) now stops: `no habitat rows for: score284_bt_rear_0p1249.streams_habitat_rb:BULL`. The new test (test file :163-172) deletes BBBB rows and expects that error; without the check the call returns rows, so the test would go red. |
| 2 | score, validation scoped per variant species (`species_of` / `aoi_of`) | **HOLDS** | score.R:135-141, 146-148, 168-169. |
| 3 | score, the walk per ladder | **HOLDS for a complete, linear `--variants`; FAILS otherwise** | Pre-flight `verdict.csv`: both rows carry `ladder_tip = bt_rear_0p1349`, `underpowered at bt_rear_0p1249`, NA, so the rows agree. It fails when a `step_from` names a variant missing from `--variants`: `chain_to()` loops forever (Finding 1). A ladder that branches below `default` is overwritten by its last tip (Finding 5). |
| 4 | score, the stamp's dirty pathspec vs the files it reads | **Partly FAILS** | The taxa CSV was added and HEAD/dirty are now taken at launch (score.R:88-93), so both of those hold. It still omits `inst/extdata/wsg_regions.csv`, which decides pooling (Finding 3). |
| 5 | build stamp and bundles vs schemas built | **FAILS** | The round-3 fix narrowed the bundle writes to `run_variants`. It did not tie them to a built schema (Finding 2). |
| 6 | build stamp `run_uid` line and the `%slog` typo | **HOLDS** | The typo is fixed: build.R:444 reads `"%s.log"`. `run_uid` is an accepted tradeoff. |
| 7 | plan vs research doc scope | **HOLDS** | task_plan.md:45 names 4 schemas, :105 drops Question 3 with CH, and :126 reads "all 4 schemas". |
| 8 | research-doc rule vs code | **HOLDS** | Both use n ≥ 10, ratio ≥ 0.5, held-out and pooled. In both, an underpowered step means "no value, the step 1-4 verdict stands" (doc "Rule"; score.R:314-363). |
| 9 | `ladder_of()` / core | **HOLDS for a complete `--variants`** | With a trimmed file the core covers only the listed schemas. For this loosening ladder that makes no numeric difference, because the core is `default`'s rearing either way. The same trimmed-file case is behind Finding 1. |
| 10 | "neither script names a species" | **HOLDS** | A grep for quoted species codes in the build, score and inputs scripts finds nothing. |
| 11 | absence `covered` set | **HOLDS** | score.R:268-270 uses `attr(absences, "covered")`, the snapshot WSGs. |
| 12 | build `wsgs_v` vs score `aoi_of` | **HOLDS** | Both come from `intersect(focal, roles for sp)`. A score run with a different `--wsgs` than the build stops in `.lnk_hvb_check_segmentation()` ("no streams for"). |
| 13 | `habitat_validate.R` → `habitat_validate_inputs.R` move | **Behaviour HOLDS, provenance FAILS** | The regexes match the CSV one for one (`read.csv` keeps `\(`). But `habitat_validate.R`'s own dirty pathspec was not widened (Finding 4). |
| 14 | the rule on a subset with no held-out WSG | **HOLDS** | Probed: every assignment at score.R:314-338 succeeds on 0 rows, `tips` is empty, and `verdict.csv` and the stamp are written. |
| 15 (new) | `habitat_validate.R` stamp after the refactor | **FAILS** | Finding 4. |
| 16 (new) | `step_from` referential integrity in `--variants` | **FAILS** | Finding 1. |
| 17 (new) | build-time invariants (access copied from base, base-digest licence) read as holding at score time | **FAILS (low)** | Finding 6. |

## Findings

**[bug] data-raw/habitat_variants_score.R:224-232, 327-334: a `--variants` whose `step_from` names a variant it does not list hangs the score and mislabels every band.** New place, reached by the round-3 per-ladder walk.
- **Neither script checks that `step_from` is in `variant`.**
  - The build's `stopifnot` (build.R:96-105) never reads `step_from`.
  - The score has no structural check at all.
- **What a gap does, in order:**
  1. **The label goes wrong silently.** `value_of("bt_rear_0p1249", ...)` on a file without that row takes 0 rows. `identical(character(0), column)` is FALSE, so it returns `default`'s 0.1049. The band itself is still computed against `score284_bt_rear_0p1249`, which exists. So `value_from`, `direction`, `bands.csv` and `bridge_band.csv`'s `in_window` all carry the wrong origin value, and nothing says so.
  2. **The core shrinks** to the listed schemas (item 9).
  3. **`chain_to()` never ends.** `v <- variants$step_from[variants$variant == v]` becomes `character(0)`. `identical(character(0), "default")` is FALSE forever and `chain` stops growing.
- **Probed** (`scratchpad/r4/gap.R`) with the loop copied verbatim and an iteration guard added: `LOOPING; v = character(0)`.
- **Where it hits.** This is reached after every validation pass has run, and it hangs rather than failing. The pre-flight already used a trimmed file (`variants_pf.csv`), so trimmed files are how this script gets run.
- **A cycle in `step_from` hangs the same way.**
- **Fix.** Near score.R:77, `stopifnot(all(variants$step_from[!is.na(variants$column)] %in% variants$variant))`, and put the same check in the build's `stopifnot`. Bound `chain_to()` by `nrow(variants)`.

**[fragile] data-raw/habitat_variants_build.R:215-224, 418-452; data-raw/habitat_variants_score.R:108-120: the round-3 fix does not make "a bundle on disk is the one its schema was built from" true.** Inside the round-3 fix (finding 4). The comment at build.R:216-217 claims it; four ways it fails:
- **`--step=base` rewrites every bundle.**
  - The bundles are written before `step` is consulted. With no `--only`, `run_variants` is every variant, so a base-only invocation rewrites every variant bundle from the current `variants.csv` and builds no variant schema.
  - Its stamp block then says `variants: <all>` and hashes them all.
  - **Pre-flight evidence.** `bundles/bt_rear_0p1449/parameters_habitat_thresholds.csv` has mtime 17:59:02, the minute `closure.txt` and `base_recompute.csv` were written. `score284_bt_rear_0p1449` does not exist.
- **Bundles are written up front, before any schema is built.** A crash on variant 1 of 3 leaves bundles 2 and 3 describing values their schemas were never built from. Because the stamp is appended only on success (build.R:462), the crashed invocation leaves no record of either the bundles it rewrote or the schemas it did rebuild.
- **Bundles are never removed.** The pre-flight `bundles/bt_rear_0p1449` is left over from an earlier invocation.
- **The score's cross-check compares the bundle to `--variants`, and both can be newer than the schema.**
  - **Nothing reads `stamp_build.txt`.** The score stamp records `--variants`' md5 but no bundle hash, so a reader cannot join a score to a build block.
  - **Resume.** A resumed `--only=<rest>` appends a block naming only the rest. The variants rebuilt by the crashed run keep whatever older block last named them, which carries an older HEAD and hash.
- **The wrong-result path needs a value edit between invocations,** which the value-bearing variant names make unlikely. But this is exactly the path the fix was written to close.
- **Fix.**
  - Write each bundle inside `run_variant()` rather than up front, and only when `step` includes variants.
  - After a variant's digest checks pass, write a per-variant record: bundle sha256, HEAD, and time. Either `bundles/<v>/built.txt` or a one-row `<schema>.score_build` table.
  - In the score, stop unless each bundle's sha matches that record, and print the shas in `stamp_score.txt`.
  - **For the base:** the score reads `default`'s thresholds at score time (`thr_default`, `value_of`) and never compares them to the build. Add the build's own `n_diff == 1` test of each variant bundle against the *current* `default`, which catches a `default` edited since the build.

**[fragile] data-raw/habitat_variants_score.R:90-93: the dirty pathspec still misses an input that decides `n_band`.** Inside the round-3 fix (finding 3a), one file over.
- **The file.** `hv_pooling()` → `lnk_species_pooling()` reads `inst/extdata/wsg_regions.csv` (R/lnk_species_pooling.R:82, 177-180). It decides which DV records pool into BT observations.
- **The package already treats it as a provenance input:** R/lnk_log.R:102-112 hashes it into the config hash for exactly this reason.
- **The pathspec covers `inst/extdata/configs` only,** so an uncommitted region edit stamps clean. The stamp's `pooling:` line hashes `species_pooling.csv` only.
- **Fix.** Widen `inst/extdata/configs` to `inst/extdata`, here and in the build's pathspec (harmless there).

**[fragile] data-raw/habitat_validate.R:284-286: a regression from this diff.** New place, the sibling-caller shape ("a fix lands in one of two callers that share a harness").
- **Before this diff,** the absence code and the taxa regexes lived in `habitat_validate.R`, so its pathspec `R inst/extdata/configs data-raw/habitat_validate.R` covered them.
- **The diff moved both out,** to `data-raw/habitat_validate_inputs.R` and `data-raw/fiss_absence_taxa.csv`, and did not widen that pathspec. The score's copy was widened; this one was not.
- **Result.** An uncommitted edit to either file changes #283's absence counts and stamps `habitat_validate_283` clean.
- **Pre-existing, same place:** it also omits `wsg_regions.csv`, and takes HEAD at the end (:308).
- **Fix.** Add `data-raw/habitat_validate_inputs.R`, `data-raw/fiss_absence_taxa.csv` and `inst/extdata` to the pathspec, and take HEAD and dirty at launch, as the score now does.

**[low] data-raw/habitat_variants_score.R:335-363: a ladder that branches below `default` is mis-assigned.**
- **The assumption.** The comment (:322-323) allows branching only at `default`, and nothing checks it.
- **What breaks.** With A→A2 and A→A3, `tips` is {A2, A3}. Row A is written by both walks, and the last one wins, so A's `ladder_tip` / `walk_status` / `walked_value` describe only one of its two ladders.
- **Not live** with the current linear `variants.csv`.
- **Fix.** Stop if any non-base `step_from` value appears more than once.

**[low] Build-time invariants read as holding at score time.**
- **Access.** `lnk_habitat_validate()` reads each variant's own `streams_access` (R/lnk_habitat_validate.R:674, 947). The equality with `score284_default` is asserted only at build (build.R:406-411), and the score never re-checks it. `run_base()` re-runs `lnk_access(merge = TRUE)` on every `--step=base|all` invocation, so a base pass after the variants can move base access while the variant copies stay put. Capture differences would then mix access into threshold effects.
  - The band function is safe: it reads no access, and its segmentation check stops on a mismatch.
  - **Fix.** Repeat the `streams_access` digest comparison per variant × WSG at the top of the score.
- **Base licence.** The base re-classify digest licence (build.R:388-396) runs only when `default` is in `run_variants`. A later `--only=<variant>` invocation, possibly at another HEAD, builds variants under no licence of its own. Note only.

## Note

- **Any stop after score.R:156 leaves partial outputs.** This includes the observation-key mismatch, UHC, the band checks and `against`. The output dir is left holding `summary.csv` / `totals.csv` / `bands*.csv` from this run and no `stamp_score.txt`.
- **That fails loud:** the exit is non-zero and the stamp is absent. Round 3's finding 7 fixed the one case that could not fail loud.
