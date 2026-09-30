# Code review, round 3: staged diff for #284 step 5

## Mechanism

**A partial producer read by a whole-population reader.** Every earlier finding has one shape. An artifact is written over a *subset*: one species, one invocation's WSGs or variants, one row of the walk, or one moment of the tree. A reader then treats it as describing the *whole*: every species, every WSG, the whole ladder, or the code that actually ran.

- **Round 1:**
  - The variant `streams_access` holds one species, and the access check assumed it held all of them.
  - `base_recompute.csv` covered one invocation and was read as covering all WSGs.
  - A variant schema holds one species, and the score script validated it for every species.
  - Absence rows cover some WSGs and were read as the surveyed set.
- **Round 2:**
  - The walk anchored at `default` was read as the bundle verdict.
  - A HEAD SHA was read as the code that ran.
  - The plan's counts were read as the run.

The candidate "two documents state one rule, edited separately" is a special case of this: a restatement is written once and read as if it tracked the other copy. Places this diff reaches, and the verdict for each:

1. **`lnk_habitat_validate_band()` reading `streams_habitat_<sp>` in every schema.** The exported function assumes every schema holds every species. This diff creates schemas that hold one species. **Finding 2.**
2. **Score script, validation scoped per variant species** (round-1 fix, `species_of` / `aoi_of`). Holds.
3. **Score script, the walk: per row vs per ladder** (round-2 fix). **Finding 1.**
4. **Score script, the stamp's dirty pathspec vs the files it reads** (round-2 fix). The absence taxa CSV is not covered, and the check is taken at the end of the run where the build takes it at the start. **Finding 3.**
5. **Build stamp and bundles vs the schemas built.**
   - The stamp hashes every bundle written, not the bundles whose schemas were built.
   - `stamp_build_<step>.txt` is overwritten per invocation, the same shape as the round-1 recompute CSV.
   - The score script never cross-checks either.
   - **Finding 4.**
6. **Build stamp `run_uid` line.** It is filled only if the operator exports `LNK_RUN_UID`. **Finding 5.**
7. **Plan vs research doc scope.** The plan still carries 7 schemas and a CH row. **Finding 6.**
8. **Research doc rule vs the code's rule.** The thresholds match: n ≥ 10, ratio ≥ 0.5, held-out and pooled, loosening means take when the band is habitat, and underpowered means the verdict stands. The doc/code split survives only through finding 1.
9. **`ladder_of()` / `core` vs doc ("rearing under every variant of the ladder").** Holds.
   - The core is taken over `default` plus every variant with the same species and column.
   - The nesting check (`against`) covers every row, in-sample included.
10. **README's "neither script names a species".** Holds: grep finds no species literal in either script's code.
11. **The absence `covered` set** (round-1 fix). Holds.
12. **The build's `wsgs_v` vs the score's `aoi_of`.** Both come from the same roles filter, so they agree.
13. **The `habitat_validate.R` refactor into `habitat_validate_inputs.R`.** It is a verbatim move, with the taxa CSV reproducing the regexes. Holds.
14. **The rule on a held-out-free subset.** It crashes rather than writing an empty verdict. **Finding 7** (low).

## Findings

- **[bug] data-raw/habitat_variants_score.R:298-332, inside the round-2 fix.** `walked_value` is computed per row, walking only up to that row's own step. So the rows of one ladder disagree, and every row except the outermost can report a value the rule does not give.
  - **The header says otherwise.** The header (line 37) promises "the walked-out value per ladder". Phase 6 acts on `walked_value`.
  - **Probed** with the walk block copied verbatim, in a scratch dir:
    - **take, keep (n<10), take.** Row 1 reads `taken through bt_rear_0p1249`, **0.1249**. Rows 2 and 3 read underpowered, NA. The doc's answer is "0.1349 stands". A reader of row 1 would move `default_tuned` to 0.1249.
    - **take, take, refuse.** Row 1 reads 0.1249, and rows 2 and 3 read 0.1349. The ladder answer is 0.1349.
    - **take, refuse, take.** All rows read 0.1249, which is correct.
  - **The cause.** The round-2 fix made "underpowered" a distinct outcome. It kept the loop over rows, where `chain` ends at `r$variant` rather than at the ladder's last step.
  - **Fix.** Walk once per ladder, over the chain to its outermost variant in each direction. Write that one `walk_status` / `walked_value` on every row of the ladder, or as a separate ladder row. Keep the per-step `decision` as it is.

- **[fragile] R/lnk_habitat_validate_band.R:114-176.** This is the exported function. It silently scores a species that a schema does not hold as if its habitat had been removed.
  - **The guard does not cover it.** `.lnk_hvb_check_segmentation()` checks `streams` only. The per-schema `LEFT JOIN … coalesce(h.flag, false)` reads an **empty** `streams_habitat_<sp>` as "not habitat".
  - **This diff creates exactly such schemas.** `lnk_persist_init(cfg$species)` creates every species' table, and the build persists one species into it.
  - **Probed.** `lnk_habitat_validate_band(conn, "BULL", species = c("BT","RB"), flag = "rearing", schema = "score284_bt_rear_0p1249", schema_ref = "score284_default", …)` returns RB `removed` **694.25 km** with a core of 0 km, and no error.
  - **Latent in the score script**, which passes only the step's species and that species' ladder. It is live for any caller of the exported API, and for a future ladder mixing species.
  - **Fix.** Next to the segmentation check, stop when any schema has zero `streams_habitat_<sp>` rows for a WSG where `streams` has rows, or when its row count differs from `streams`.

- **[fragile] data-raw/habitat_variants_score.R:397-406, inside the round-2 fix.** The dirty check describes neither the inputs nor the moment.
  - **(a) Inputs.** The pathspec omits `data-raw/fiss_absence_taxa.csv`, which `hv_fiss_absences()` reads (`habitat_validate_inputs.R:16,73`) and which decides `n_absence_band`. An edited taxa file stamps clean.
  - **(b) Moment.** `dirty` and `git rev-parse HEAD` run at the **end** of a long run. The build takes `dirty` at the start (`habitat_variants_build.R:84`), before `load_all()` output matters.
    - A commit made mid-run stamps the score "clean @ <new HEAD>" for code it did not run.
    - The two copies of this logic were edited separately and diverged.
  - **Fix.**
    - Add the taxa CSV to the pathspec.
    - Take the porcelain list and HEAD at the top of the script, before `load_all()` is used, and print them in the stamp.
    - The build's `write_stamp()` also reads HEAD at the end (`:429`); read it with `dirty` at `:84`.

- **[fragile] data-raw/habitat_variants_build.R:214-219, 416-419, 443; data-raw/habitat_variants_score.R:92-100.** The provenance of a scored schema is whatever bundle is on disk at score time. Nothing ties it to the invocation that built the schema. This is the round-1 `base_recompute.csv` shape again.
  - **Bundles are rewritten on every invocation.** `write_bundle()` rewrites **every** variant's bundle on every invocation, including `--step=base` and `--only=<subset>`.
  - **The stamp hashes every bundle, not every built one.** `write_stamp()` hashes all of `cfgs`, not `run_variants`. The pre-flight `stamp_build_all.txt` lists `bt_rear_0p1449=58e5ea82ebcb`, and no `score284_bt_rear_0p1449` exists.
  - **The stamp file is overwritten per step.** `stamp_build_<step>.txt` is overwritten per `--step`. So `--step=variants --only=A`, then `--only=B` (or a resume after a crash, since the stamp is written only on success), leaves a stamp that names B only.
  - **The score script never cross-checks.** It loads `bundles/<v>` and takes values from its own `--variants`, which in the pre-flight was a different, trimmed file. The step values, the bridge window and `walked_value` all come from that file. Nothing compares any of it to what the schema was built from.
  - **Fix.**
    - Hash only the variants built in the invocation, and append a per-invocation record rather than overwrite (or write per variant: `stamp_build_<variant>.txt`).
    - In the score script, stop unless each `bundles/<v>/parameters_habitat_thresholds.csv` hash matches the build record for that schema.

- **[low] data-raw/habitat_variants_build.R:420-423, 437-438.** The `run_uid` line reads `score284_default.log.run_uid`, which is NULL unless the operator exports `LNK_RUN_UID`. `lnk_pipeline_run()` only defaults to the env var.
  - **In the DB:** all three pre-flight log rows have `run_uid` NULL. The stamp reads "none", and so does the plan's Phase 3 stamp item.
  - **Fix.** `Sys.setenv(LNK_RUN_UID = <generated>)` at the top of the build when it is unset, or stamp `run_id` / `run_label` instead.
  - **Also:** the format `"%slog"` renders as `score284_defaultlog` (a dot is missing).

- **[low] planning/active/task_plan.md** ("Verification (end to end)" and Phase 5). These are stale against the revision, the round-2 class.
  - "identical segmentation and access across **all 7 schemas**" should be 4.
  - Phase 5 still lists "Question 3: the CH spawn 0.0299 band (3–4.5 %) as its own row". The research doc now says it is unscorable and CH is dropped, and nothing in the score script produces it.
  - Phase 4 was corrected; these two were not.

- **[low] data-raw/habitat_variants_score.R:289-302.** On a focal subset with no held-out WSG (for example `--wsgs=PARS`), `rule` has 0 rows.
  - `rule$walk_status <- NA_character_` then errors ("replacement has 1 row, data has 0"; probed).
  - `verdict.csv` and the stamp are never written, while `bands*.csv` are already on disk.
  - It fails loud, but it leaves an output directory without the stamp that says what produced it.
  - **Fix.** Guard with `if (nrow(rule) > 0L)`, or write the stamp before the rule.

## Note (not a code defect)

The pre-flight suggests the widened power table will shrink under the validator's filters.

- **What the power table says.** `power_windows.txt` gives ELKR + BULL 10 locations in 0.1049–0.1249, with ELKR at most 5 there (6 in the whole window, 1 in 0.1249–0.1349). So BULL is at least 5 upper-bound.
- **What the pre-flight counted.** The BULL band for that step counted **n_band = 1**.
- **What that implies.** If the full set shrinks similarly, the 33 and 22 upper bounds for steps 2 and 3 may fall below n = 10, and the result is "0.1349 stands, underpowered".
- **Which makes finding 1 decisive.** That is exactly the case where the rows of `verdict.csv` currently disagree.
