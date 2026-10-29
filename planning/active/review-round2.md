# Code-check round 2 (#414), branch head 1f5bfdab

## Checklist read

- code-check.md: all 14 `## Mechanisms` H3s read in full (prose, table rows skipped): a guard that fails toward pass; a fixture that cannot reach the failure mode; a proxy is not the property; verification that reads its own output; a guard's scope, escape hatches, and remedies; a fix lands in one of two callers; restore the bug and prove the guard fires; a shared working tree; a wrapper's exit is not the work; zero-length, empty, and unset; the probe is broken before the world is; written data outlives the fix; serialization loses meaning silently; one fact derived twice. Not read: 23 other headings (standalone rules, security, spreadsheets).
- code-check-r.md: read `sort()` and `order()` collate by `LC_COLLATE`; `match()` treats NA as a matchable VALUE; `Rscript -e` supplies `--args` itself; `$` on a list partial-matches; a database driver's value is not a base R type; `identical()` on two reader results; CSV whitespace (`trim_ws` / `strip.white`). Not read: 104.
- code-check-shell.md: read `if ! cmd; then rc=$?`; a heredoc whose body contains its own delimiter; Quoting. Not read: 64.
- code-check-spatial.md: none apply (no spatial code in the diff). Not read: 93.

## Round-1 fixes reviewed first

- Species sort is radix now; every other sort in the digest is radix or numeric (classes) or fixed order (`.lnk_classes_bcfp`, `lnk_presence()` group formals). OK.
- The serialiser keeps NA apart from "" (and "\N" data from NA, via the backslash escape) and does not fold spellings. Both presence readers were checked: `.lnk_wsg_species_present()` is exact `"t"`, `lnk_presence()` (`.lnk_presence_truthy()`) folds `t/true/yes/1`. The digest is exact, so it is finer than both: safe direction.
- Every `parameters_fresh` column the R pipeline reads (enumerated: `species_code`, `access_gradient_max`, `observation_threshold`, `observation_date_min`, `observation_buffer_m`, `observation_species`, `observation_control_apply`) is in `.lnk_vocabulary_acc_cols`. Types come from the same `loaded` (`utils::read.csv`, local for both tables in every bundle), so the digest sees what the pipeline sees; `lnk_barrier_overrides()` folds further (`as.integer`, `as.logical`, `trimws`), safe direction.
- Blank key cells refused in the reader; match uses `which()`. OK.
- Tests: test-lnk_vocabulary.R 40 pass / 1 skip, test-lnk_log.R 323, test-lnk_pipeline_run.R 29, 0 fail / 0 error (worktree at 1f5bfdab). Note: test-lnk_log.R printed `NOTICE: schema "working" already exists, skipping`, i.e. one of its tests ran a no-op `CREATE SCHEMA IF NOT EXISTS` on the live local database.

But the same fold the round fixed on values is still present one axis over, in four places:

## Findings

- **[severity: fragile]** R/lnk_vocabulary.R:128-136 — the cut spec keeps the gradient class **values** and drops their **names**, and the names are what the pipeline reads. `.lnk_resolve_classes()` keeps names; `frs_break_find()` writes them to `gradient_barriers_raw.gradient_class`; classify labels each position `gradient_<name>`, which fresh parses as the blocking threshold (`frs_habitat_classify.R:461`, `N / 10000 >= access_gradient`); `lnk_barriers_unify()` maps species by name (`.lnk_classes_bcfp` ids). prepare's refusal (`R/lnk_pipeline_prepare.R:657-671`) checks only the classes at or above a *present* species' `access_gradient_max`. Probe: `gradient_classes: {"1400": 0.15, "2000": 0.2, "2500": 0.25, "3000": 0.3}` gives the identical cut spec to `default` (resolves to `cut-full-top`). In a group where no species with an access gradient of 0.15 is present (a BT-only group), prepare does not refuse, the 15 % positions persist as class 1400 rows that block no species, and classify's labels change, all under the default's token. The same holds for any break-only class (below every amax), which is never checked. Fix: spec the classes as `name:value` (sorted by value), e.g. `gradient_classes=1500:0.15,2000:0.2,2500:0.25,3000:0.3`, and update the two cut rows (the table is not on main yet).

- **[severity: fragile]** R/lnk_vocabulary.R:225 (with :195) — `.lnk_vocabulary_canonical()` sorts rows, which erases the `parameters_fresh` row order the pipeline reads. `.lnk_pipeline_prep_minimal()` takes `params_fresh$access_gradient_max[species_code == sp][1L]` ("take first row defensively — duplicates"). Probe: BT duplicated with amax 0.25 and 0.15, in either order: same digest (TRUE), pipeline amax 0.25 vs 0.15, so the BT barrier set and the cuts change under one `acc` token. "A vector derived from a frame is a second copy of its row order" (One fact derived twice). Fix: refuse a duplicate `species_code` in `parameters_fresh` (and a duplicate `watershed_group_code` in the presence table, which `lnk_presence()` already refuses at run time) in `.lnk_vocabulary_spec_acc()`, which makes the row sort sound.

- **[severity: fragile]** R/lnk_vocabulary.R:186 — `toupper(cfg$species)` folds a case the pipeline reads exactly: `prep_minimal` matches `params_fresh$species_code == sp`, and `lnk_pipeline_species()` intersects with the uppercase codes `.lnk_wsg_species_present()` returns. `cfg$species` is the rules.yaml key list (`R/lnk_config.R:120`). Probe: lowercase species give the same digest as default (TRUE) while `lnk_pipeline_species(c2, loaded, "ADMS")` returns 0 species against 5. Fix: drop `toupper()`; keep the radix sort.

- **[severity: fragile, low]** R/lnk_vocabulary.R:213 — `as.character()` on a double gives 15 significant digits, so the serialiser folds doubles that differ beyond that, while the pipeline compares them exactly (`classes >= sp_amax`). Probe: CH `access_gradient_max` 0.15000000000000002 digests identical to 0.15 (TRUE); the pipeline then leaves class 1500 out of CH's barrier set. `as.character(1e15 + 2)` is `"1e+15"` too. Unlikely from a hand-written CSV, but it is the fold round 1 set out to remove. Fix: write doubles with `sprintf("%.17g", x)` (NA kept apart as now), integers and characters as they are; the two acc digests then need regenerating.

## Checked, not flagged

- `study_area_run.sh` gate: `local` declared before assignment, `&& rc=0 || rc=$?` captures the status, `Rscript -e 'expr' "$CONFIG"` passes the argument without a second `--args`, `CONFIG` is restricted to `[A-Za-z0-9_]`. Exit 3 is any error raised inside `lnk_vocabulary_resolve()`, including `lnk_load_overrides()` I/O and the missing-column stops, so those print as "has no output tokens"; the R message is printed above it and the gate fails closed either way.
- `cols_log` additions reach existing `<schema>.log` tables through `.lnk_log_align_columns()`; consolidate copies shared columns only.
- `discharge_fill` is `isTRUE()` in both the spec and the pipeline; `discharge_source` validated by the same helper.
- `barrier_inputs` matches the pipeline's manifest-key gates (`!is.null(loaded$user_barriers_definite_control)` etc.), and the constant fixes its order.
