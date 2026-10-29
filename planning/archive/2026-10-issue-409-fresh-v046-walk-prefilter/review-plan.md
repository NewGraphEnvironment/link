# Plan review — #409 (Plan agent, 2026-10-29)

Extracted from the reviewer's hand-back by script. Dispositions are in `findings.md`, "Plan review".

## Review: #409 plan (adopt fresh v0.46.0), checked against the code

**Verdict.** The plan's main claims hold.
- link passes `aoi` on every downstream walk.
- No link session is read-only or pooled.
- `frs_cluster`'s `watershed_group_code` requirement is met.
- The species=NULL and progress-line changes cannot reach link.
- The 1d00c04c worktree with fresh 0.46 runs the same recompute code a run at the new pin would.

The weak spots:
- It misses a second array-first-element reader, `remediated_dnstr_ind`.
- Its "outputs should not move" evidence covers 8 groups, when a read-only query can settle the question for the whole province.
- The digests cannot see features dropped from a walk's arrays.
- Phase 3 has no stop rule and no reproducibility baseline for NATR.
- Several acceptance lines claim more than the cited checks prove.

Working tree note: `DESCRIPTION` (fresh >= 0.46.0, @v0.46.0) and `data-raw/pretest_inputs.csv` are already modified, and they are not committed. `data-raw/logs/prefilter_409/` exists (rerun.R copy, model_run.sh, reach.md). `model_run.sh` (Phase 3) is running now: it started 00:58Z and is on ADMS b. Its scratch library `.../scratchpad/rlib_fresh046` holds only `fresh`. Its RemoteSha 8a5ca763 equals `git rev-parse v0.46.0^{commit}`.

---

### Answers to the four questions

**(1) link call paths whose behaviour changes under fresh 0.45/0.46**
- **Temp-table session requirement: met.**
  - No `read_only`, `READ ONLY`, pgbouncer or 6432 anywhere in `R/` or `data-raw/`, except the frozen `data-raw/logs/recompute_cost_261/{walks,walk_prefilter}.R`.
  - No walk runs inside a transaction: `dbWithTransaction` appears only at `R/lnk_db_load.R:82`, `R/lnk_habitat_gate.R:236`, `R/lnk_mapping_code.R:264` and `data-raw/habitat_variants_build.R:852`, none of which wraps a walk.
  - Both `segments` inputs carry every column `.frs_walk_scope` projects, including `watershed_group_code`: `zz_lnk_streams_<aoi>` at `R/lnk_access.R:174-176`, and `<schema>.streams` at `R/lnk_pipeline_run.R:279-281`.
- **Tie order of feature arrays: half-covered.** Two link values read element `[1]`:
  - `dam_dnstr_ind` reads `anth[1]` (`R/lnk_pipeline_access.R:274-293`). The plan names this one.
  - **`remediated_dnstr_ind` reads `arr[1]` of the remediations array** (`R/lnk_pipeline_access.R:306-318`). The plan does not mention it. It is computed only at model time (`R/lnk_pipeline_run.R:290-291`). The recompute keeps the old value (`R/lnk_access.R:236-238`), so Phase 2 cannot see it; only Phase 3's three groups can.
  - The new tiebreak is `b.<feature_id_col>`, and that id is `id_barrier` **text** (`R/lnk_persist_init.R:142`, `R/lnk_barriers_unify.R:186` `aggregated_crossings_id::text`). Ties now resolve by text order: "1200000123" sorts before "197532". A CABD dam id can therefore come first where the plan's order put a PSCIS crossing first.
  - #261's "anthropogenic arrays match in nine" (`data-raw/logs/recompute_cost_261/README.md:121-125`) was measured with the old ORDER BY, without the id key. It does not test the new tiebreak.
- **`frs_cluster`'s `watershed_group_code` requirement: met.**
  - `table` is `<schema>.streams` (`R/lnk_pipeline_connect.R:102-104`).
  - `habitat` is created by fresh with the column (fresh v0.46.0 `R/frs_habitat_classify.R:236-246`).
- **Two semantic rewrites the plan does not name:**
  - `.frs_connected_waterbody`'s subtractive UPDATE now touches only habitat rows joined to `table`.
  - `frs_cluster(direction="both")` now protects phase-1 rows with `label_connect IS NOT TRUE` instead of an id list.
  - Both are equivalent for link: the working schema is dropped every run (`R/lnk_pipeline_run.R:185`, `overwrite = TRUE`), and habitat rows come only from `table`. Every species in the default bundle runs cluster "both" (`inst/extdata/configs/default/parameters_fresh.csv`). Phase 3's ADMS SK covers the connected-waterbody path. The plan should state this as checked.
- **species=NULL resolution: cannot reach link.** `.frs_run_connectivity` passes `species = sp` explicitly (fresh v0.46.0 `R/frs_habitat.R:1220,1287`).
- **Progress-line changes: cannot reach link.** link passes `verbose = FALSE` in both places (`R/lnk_pipeline_connect.R:108`, `R/lnk_pipeline_classify.R:129`).

**(2) Does the 1d00c04c worktree with fresh 0.46 via R_LIBS run the same code as the new pin? Yes, for the recompute.**
- `git diff --stat 1d00c04c HEAD -- R/` leaves every file `rerun.R` reaches untouched: `lnk_access.R`, `lnk_pipeline_access.R`, `lnk_habitat_gate.R`, `lnk_mapping_code.R` and the downstream check.
- The changes in that range are:
  - `lnk_config.R`: `observation_breaks` validation only.
  - `utils.R`: adds `.lnk_timeout_statement`.
  - `lnk_barriers_views.R`: a comment only. `build_views = FALSE` reads the views stored in the DB anyway.
  - The default `config.yaml`: `observation_breaks`, model-time only.
- 1d00c04c's floor is `fresh (>= 0.42.0)`, so `load_all()` accepts both 0.44 and 0.46.
- Caveats to record:
  - The rows were written with fresh **0.42.0** (`README.md:6`) and "before" uses 0.44.0. This is fine, because `frs_network_features` is unchanged 0.29→0.44 (`README.md:8`). Say so; the digests confirm it.
  - The run is serial, with R on m4 against the remote DB, so array transfer and parsing on m4 are inside the walk times. Production runs at -j8 on the dispatcher with `work_mem` 512 MB per sort, and SETN's sort already spills 526 MiB (`README.md:126`).
  - Put the empty `git diff 1d00c04c HEAD -- <those files>` in the README as the evidence.

**(3) The pre-run gate (#372)**
- **The fresh range is v0.42.0..v0.46.0, not v0.44.0..v0.46.0.**
  - `pretest_pick.R:95-96` reads the fresh pin from DESCRIPTION at `--since`, which defaults to the history's link SHA (1d00c04c pins `fresh@v0.42.0`).
  - So `--pick-only` judges every fresh file changed since 0.42.0, not only the seven named in the plan.
  - The plan also does not name the host or schema `--pick-only` runs against. `pretest_pick.R:66-72` refuses without `<schema>.log` history.
- **The record is voided** by the pin (`data-raw/pretest.R:504-507`) and by the edit to `pretest_inputs.csv` (`PRETEST_RULES`, `data-raw/pretest.R:51,500-503`). The plan acknowledges this.
- **The map's input for `frs_network_features.R` is stale.**
  - Row 105 says `segments`, "cost scales with the group's segments". The walk's cost now follows the features it admits and the pairs it outputs.
  - #261's own table: segments Spearman 0.605, features inside the group 0.881 (`README.md:131-138`).
  - The gate's scratch schema holds only the picks' barriers (`data-raw/pretest_run.sh:28-31`; `RUNBOOK.md:1540`), so the gate never exercises the prefilter's province-wide case. The recompute is mapped `unexercised` (`pretest_inputs.csv:50,141`).
  - So a passing gate is no evidence for this change. The plan should say so, or add an input such as `features_in_group`.
  - `RUNBOOK.md:1539` ("the recompute's cost is fresh's province-wide walk") becomes stale.
- **`test-pretest.R:480-491` skips** when there is no sibling fresh checkout or no tag, as on CI. A pass must be from a local run that did not skip.

**(4) Verification gaps:** see the Gap and Acceptance sections below.

---

### Blocker
- **B1. The "outputs unchanged" claim (NEWS v0.69.6) rests on 8 groups.**
  - Evidence: `R/lnk_pipeline_access.R:274-293,306-318`; `R/lnk_persist_init.R:142`.
  - The only way outputs can move is a co-located tie (equal wscode, localcode and measure) that mixes a dam with a non-dam (`dam_dnstr_ind`), or remediations of mixed status (`remediated_dnstr_ind`).
  - That set can be counted province-wide with one read-only query before Phase 2, for example on `fresh_default.barriers`:
    ```sql
    SELECT count(*) FILTER (WHERE n_dam > 0 AND n_dam < n)
    FROM (
      SELECT count(*) n, count(*) FILTER (WHERE barrier_source = 'CABD') n_dam
      FROM fresh_default.barriers
      WHERE barrier_source IN ('PSCIS','CABD','MODELLED_CROSSINGS')
      GROUP BY wscode_ltree, localcode_ltree, downstream_route_measure
      HAVING count(*) > 1
    ) t;
    ```
  - A count of zero closes the risk for every group. A non-zero count names the segments, so the operator decides before writing anything.

### Gap
- **G1. Phase 2's stop rule names only `dam_dnstr_ind`, and Phase 3 has no stop or attribution rule at all.** Add `remediated_dnstr_ind`. Say what happens when a Phase 3 digest differs.
- **G2. Digests of derived booleans cannot see a walk that drops features but still returns at least one per segment.**
  - `has_barriers_*` is membership only (`R/lnk_pipeline_access.R:252-262`), and arrays are not persisted (`:387-396`).
  - Compare `walks_<WSG>_<label>.tsv` `rows`/`elements` between labels. Better, add a sorted-array digest per walk in the rerun copy.
- **G3. NATR has no build-to-build reproducibility baseline.** #367's `reproducibility.csv` covers only ADMS and ELKR. A NATR mismatch could not be blamed on fresh. Add a second b build for NATR, or rebuild b on any mismatch.
- **G4. Phase 3 provenance.** `model_run.sh` stamps fresh from a separate `Rscript`, not from the build's own process. Assert each schema's `log.fresh_version` and `fresh_sha` per group in compare (`R/lnk_log.R:315-318`).
- **G5. No link test guards the speedup's single dependency.** The test should check that `lnk_pipeline_access` passes `aoi` with `direction = "downstream"`. The mocked tests (`tests/testthat/test-lnk_pipeline_access.R:26-28`) could capture the arguments. Also add a test that the DESCRIPTION floor equals the Remotes tag.
- **G6. No check that `fresh_default`'s inputs are unchanged across the runs.** #261 recorded tuple write counters before and after (`README.md:29-30`). Do the same.
- **G7. Production conditions are not measured.** These are -j8, the dispatcher running locally, and concurrent sort spills. Make "compare the next provincial `log_recompute` minutes against 2026-10-23" an explicit owed item.
- **G8. `RUNBOOK.md:1539` and CLAUDE.md:23** ("18 fresh files, the same at v0.42.0 and v0.44.0") need updating. The plan's §8d edit covers only the pin.

### Ordering
- **O1. DESCRIPTION is already bumped in the main checkout while the shared library holds 0.44.** `load_all()` refuses a fresh below the floor (CLAUDE.md:50). Every load during Phases 2–3 must come from the worktrees, or use R_LIBS.
- **O2. The shared-library install in Phase 4 must also wait for `model_run.sh`.** Phase 3's b builds use the shared 0.44, so "every before run" has to include them.
- **O3. Phase 2 run concurrently with Phase 3 contaminates walk times.** Both run R on m4, and walk times include parsing arrays in R on m4 (SETN returns 4.83 M pairs). Serialize them, or record m4's load the way `habitat_variants_build.R` does (`load_1min`).
- **O4. B→A order favours A through the cache.** #261 saw cache state move timings more than load did (`README.md:58-62`). Use B/A/A/B for every group, not only SETN, or report the bias. For LKEL and LSKE the size of the gain depends on it.
- **O5. `--pick-only` must follow the shared-library install.** `pretest_reach_repo` calls `load_all` on the bumped repo (`data-raw/pretest.R:387-388`). The plan's order is right; state the dependency.

### Assumption
- **AS1.** Text-ordered tiebreaks agree across host collations only if the ids are digit-only. That holds for `aggregated_crossings_id`; confirm for any other anthropogenic or remediation ids.
- **AS2.** Phase 3 builds groups into empty schemas, so walks see only the group's own barriers. Admitting cross-group features is exercised only by Phase 2's five groups.
- **AS3.** `rerun.R`'s timing hook (`assignInNamespace` on `frs_network_features`, `rerun.R:95-104`) times 0.46's temp-table build together with the walk. That is fine, but the two are not comparable component by component with `walk_prefilter.tsv`.
- **AS4.** Nothing reads `fresh_default` between a digest moving and the restore. `rerun.R:169-176` prints the restore statement and quits; it does not restore by itself.

### Scope
- **S1.** `lnk_access` still builds `zz_lnk_streams_<aoi>` (CREATE, 4 indexes, ANALYZE in the persist schema; `R/lnk_access.R:160-187`). That is now redundant with fresh's own temp table, since the recompute does no upstream walk. It is a follow-up issue, not this PR, because removing it would change what is measured.
- **S2.** `frs_feature_index` (fresh#277) and `frs_network_segment` changed only in docs, and link does not call either. No action.

### Acceptance
- **AC1. "Summed-work share against 36–51 %" cannot come from 5 groups.** That figure is pooled over 241 groups and calibrated on 9 (`README.md:143-150`). Compare per-group and per-walk ratios against `README.md:109-119` instead, and leave the provincial share to the next run's `log_recompute`.
- **AC2. No existing test shows "`lnk_preflight_fresh()` refuses 0.44.0".** The tests check only floor >= 0.33.0 and a synthetic 999.0.0 (`tests/testthat/test-lnk_preflight_fresh.R:80-85,149-153`). Add `expect_identical(.lnk_fresh_floor(), "0.46.0")` or a check against the Remotes pin.
- **AC3. `devtools::test()` at 0.46 says nothing about the walk:** `frs_network_features` is mocked throughout. The DB digests are the only evidence; say so.
- **AC4. "test-pretest.R passes" must mean the fresh-reach test ran.** Report it as run, not skipped (lines 480-491).
- **AC5. "Outputs unchanged" in NEWS v0.69.6 depends on B1 or G1.** If ties flip, the release is not output-neutral, and the NEWS line and version reasoning need to change.

### Critical Files for Implementation
- /Users/airvine/Projects/repo/link/R/lnk_pipeline_access.R
- /Users/airvine/Projects/repo/link/data-raw/logs/prefilter_409/rerun.R
- /Users/airvine/Projects/repo/link/data-raw/logs/prefilter_409/model_run.sh
- /Users/airvine/Projects/repo/link/data-raw/pretest_inputs.csv
- /Users/airvine/Projects/repo/link/tests/testthat/test-lnk_preflight_fresh.R
