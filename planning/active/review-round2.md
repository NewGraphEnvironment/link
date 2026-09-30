# Code review, round 2: staged diff for #284 step 5

## Findings

- **[severity: bug]** data-raw/habitat_variants_score.R:13-16, 292-315 against research/habitat_thresholds.md "Scoring design" (Rule). `verdict.csv`'s `walked_value` reports a different value from the rule the research doc fixed before the run. **Not inside a round-1 fix.**
  - **What the code does.** An underpowered step gets `decision = "keep (n < 10)"`. The walk treats `keep` exactly like `refuse`: it is not `"take"`, so the walk stops there, and `walked_value` falls back to `default`'s value.
  - **What the doc says.** "An underpowered step (n < 10) changes nothing. The step 1–4 verdict stands: `default_tuned` keeps 0.1349". The task plan says the same: "`default_tuned`'s 0.1349 stands."
  - **Evidence from the pre-flight.** In `preflight/verdict.csv`, both steps read `keep (n < 10)` and both rows carry `walked_value = 0.1049`. The doc's rule on the same numbers gives 0.1349. `walked_value` is the column a reader acts on in Phase 6 ("If the rule moves a value, edit `default_tuned`…"), so read literally it moves BT back to 0.1049.
  - **The mixed case.** The two also disagree when the steps are mixed: take 0.1249, then an underpowered step to 0.1349. The walk reports 0.1249 and the doc keeps 0.1349. Nothing in the walk can express "no verdict, the incumbent stands", because the walk is anchored on `default` (0.1049) and not on `default_tuned`.
  - **Fix.** Pick one rule and make the other match. Either propagate "underpowered" as a distinct walk outcome (for example `walked_value = NA`, with a `walk_status` of `underpowered at <variant>`), or change the doc.

- **[severity: fragile]** data-raw/habitat_variants_build.R:83-90 and 428-429; data-raw/habitat_variants_score.R:383-384. The stamps record a commit SHA that does not contain the code that produced the schemas and the verdict. **Not inside a round-1 fix.**
  - **In the build.** `--allow-dirty` lets it run with uncommitted changes, but the stamp does not say so. It records only `git rev-parse --short HEAD`.
  - **In the score script.** There is no dirty check at all. The stamp also omits which `--variants` / `--roles` files were used, and their hashes.
  - **Evidence from the pre-flight.** Both stamps read `link: 0.53.0 @ 823fde7`, and `git ls-tree 823fde7` contains neither `habitat_variants_build.R`, `habitat_variants_score.R` nor `R/lnk_habitat_validate_band.R`.
  - **The pre-flight score used a trimmed variants file.** No `score284_bt_rear_0p1449` schema exists, and `bands.csv` has two steps. The stamp does not say so, and the ladder changes the core (`ladder_of()` intersects every variant schema).
  - **Why it matters.** The build's own header says "A scored schema must be traceable to committed code and inputs." A full run launched with `--allow-dirty` would produce the same false pin.
  - **Fix.**
    - Write `dirty: yes/no` (the porcelain list) into both stamps.
    - Add the same check, or the same record, to the score script.
    - Record `path_variants` and `path_roles`, with their md5, in `stamp_score.txt`.

- **[severity: fragile]** planning/active/task_plan.md Phase 4 post-conditions: "20 WSGs in `score284_default`; the 8 focal WSGs in each variant schema". **Not inside a round-1 fix.**
  - **The real numbers.** `lnk_wsg_resolve(expand = TRUE)` on the 12 roles WSGs resolves to **23** WSGs (measured: LARL LFRA LPCE LSKE HARR KLUM KOTL UARL UPCE BULL KISP LILL PCEA REVL BULK CLRH ELKR MSKE PARA BABR MORR PARS BABL), and the research doc says 23. BT is active in all 12 roles WSGs, so every variant schema should hold **12** focal WSGs, not 8.
  - **Why it matters.** Phase 4 explicitly verifies "against the DB, not the exit code". Checking against 20 and 8 would report a healthy build as failed, or accept a short one.
  - **Fix.** Correct the expected counts before the full run.

## Round-1 fixes: checked

- **Fix 1 (access copied from base).** Holds.
  - `copy_access()` names its columns and runs inside a transaction.
  - The post-copy `SELECT *` digest compares row text in column order. A DDL order difference would stop the run loudly rather than pass it. Both schemas are sized by `lnk_persist_init(cfg$species)` from the same bundle, so they agree, and the pre-flight passed.
  - `streams_access` is unique on `id_segment` per WSG (44,830 / 44,830 in both schemas), so `ORDER BY t.id_segment` is deterministic.
- **Fix 2 (per-WSG `base_recompute.csv`).** Holds. The first-run `old = NULL` path works (`rbind(NULL[...], rc)`), the file is no longer read as a gate, and the per-WSG update keeps other WSGs' rows.
- **Fix 3 (`species_of` / `aoi_of`).** Holds.
  - These scope each variant exactly as the build does (`wsgs_v`), and `obs_key` compares like with like.
  - The bands read `obs_base` (the `default` run at buffer 0). That is correct because the segmentation is shared.
- **Fix 4 (`attr(absences, "covered")`).** Holds.
  - It reads the attribute from the unsubsetted frame, not from `a`, whose `[.data.frame` subset would have dropped it.
  - The `ab` and `b` rows align: the same `aoi` and species, and the same sort.

## Also checked and clean

- **Pre-flight numbers reconcile with the DB and with each other.**
  - Band km: 1121.21 − 1062.42 = 58.79, and 1150.59 − 1121.21 = 29.38.
  - Counts: n_core 64 = `default`'s n_rearing, and 64 + 1 = the variant's 65.
  - Bridge km sums: 20.78 + 26.35 + 11.66 = 58.79, and 12.87 + 12.22 + 4.28 = 29.38.
  - An independent SQL check of `score284_bt_rear_0p1249` against `score284_default` for BULL:
    - 0 spawning differences;
    - 0 rearing removed;
    - 58.788 km of rearing added;
    - the same 44,830 segments.
- **The working schema now holds BT only.** `classify(species = BT)` replaced the whole working `streams_habitat`: 44,830 rows, all BT. The `default` re-classify re-creates every species before its digest check, so the invariant is not weakened. The table is unique on `(id_segment, species_code)`, so the digest order is deterministic.
- **Thresholds come from the variant bundle.** Classify and connect resolve them from `cfg` (`.lnk_habitat_thresholds_csv(cfg)`), not from the shared `loaded`, so passing `default`'s `loaded` to the variants is correct. Breaks are rebuilt in `<working>.streams_breaks`, not in a shared schema.
- **The absence taxa CSV reproduces the old regexes.** `read.csv` leaves `\(` untouched, and the OR-join is equivalent.
- **The `habitat_validate.R` refactor leaves no dangling references.**
- **The UHC guard sees the right columns.** They are named `spawning` / `rearing`, coded integer 1 / −1 / −4 / NA, and there are no BT rows. The guard stops on any species row anywhere in BC, not only in focal WSGs. That is stricter than needed, but it fails loud.
- **`lnk_habitat_validate_band()`** matches round 1:
  - full-key joins;
  - identifier regexes before `sprintf`;
  - a segmentation digest across every schema read;
  - NA densities.
