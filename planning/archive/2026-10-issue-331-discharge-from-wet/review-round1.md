## Findings

- **[bug]** data-raw/habitat_variants_build.R:323-339 vs data-raw/habitat_variants_score.R:357 — the relaxed build guard now *drops* `set` cells the base already carries, but the score still requires `n_diff == 1L + n_set(r$set)`, where `n_set()` counts the raw `set` string from variants.csv. The two are now out of step for every rung whose `set` contains a base-equal cell, and the score stops on them with "bundle <v> is not default with ... (N cells differ ...)".
  This applies to every non-base row of the committed `data-raw/habitat_score/variants_331.csv`. `default`'s BT row has `spawn_mad_max = 9999` and `rear_mad_max = 9999`, so for `bt_rear_wet_p10` (`set = rear_mad_max=9999;spawn_mad_min=0.0063;spawn_mad_max=9999`) the build drops two cells and writes a bundle that differs from `default` in 2 cells. The score expects 1 + 3 = 4.
  Reproduced with the exact formulas from both scripts against the shipped `default` thresholds: "dropped by build: rear_mad_max spawn_mad_max; build n_diff: 2; score expects 4".
  The README's motivating case (#302's rungs, which also fix `*_mad_max = 9999`) hits the same stop. So the build running now will complete, and then `habitat_variants_score.R` will refuse every variant.
  Fix: in the score, count only the `set` cells that differ from `thr_now` (as the build does), e.g. `n_diff != 1L + sum(set cells != base)`. `set_ok` already checks each set cell's value, so dropped cells are still verified.

- **[fragile]** data-raw/discharge_wet_load.R:42-44 with data-raw/cypher_prep.sh:268-289 — "skips a host that already has it" checks presence only, not which wet build is loaded. `wet::wet_catalog()` serves whatever build the published manifest currently names; the DESCRIPTION pin fixes the package, not the data build.
  So a cypher loaded at prep time can carry a newer wet build than the dispatcher's existing table (m1's is `built 2026-10-15T02:06:57Z, wet acb820f`). One run then classifies different WSGs on different discharge, and no gate fails. `preflight_hosts()` compares fresh/link SHAs and primitive vintage, not the wet table comment.
  It surfaces only after the fact: in `log_input.table_comment`, and as `matches: false` in the export's `wet_load` for the cypher-built groups. If the reproducibility bar applies, compare the dispatcher's comment with each cypher's (stripping `; subset ...`) in `preflight_hosts()`.

- **[fragile]** data-raw/discharge_wet_load.R:43-47 — `--force` calls `wet_db_load(..., months = 0, pick_only = TRUE)`. Per wet v0.4.7 (R/wet_db_load.R:92), that DELETEs the whole `historical` scenario before loading the subset.
  On a host holding the full table (m1: 103 M rows, all months and sources), `--force` silently reduces it to the ~4.5 M-row annual pick. The script header says nothing about this. Low likelihood, because `--force` is opt-in and the study_area_run.sh hint omits it, but the loss is irreversible short of a full reload.

- **[fragile, doc]** RUNBOOK.md (new #331 bullet, "Recorded state") says "The validator refuses a WSG whose logged source differs from its `cfg`". The code (`.lnk_hv_check_log`, R/lnk_habitat_validate.R:478-490) only warns, by design (accepted tradeoff 1). A reader relying on the RUNBOOK will believe there is a guard that does not exist; "refuses" should read "warns about".

- **[fragile, minor]** data-raw/study_area_run.sh:639-651 — the dispatcher discharge gate runs for `fwapg` configs too. On failure its remediation line always says `Rscript data-raw/discharge_wet_load.R`, which loads wet and cannot fix a missing fwapg table. The gate itself still fails correctly; only the printed fix is wrong for fwapg.

Checked and clean:
- every discharge reader in R/ and in data-raw/*.R / *.sh passes the source (the only fwapg-hardcoded reader left is the untouched query_habitat_thresholds_fiss.R, which has no cfg);
- fresh v0.39.0 joins fwapg discharge only in `frs_habitat()` / `frs_network_segment()`, which link does not call;
- log column migration goes through `.lnk_log_align_columns`, and consolidate copies shared columns by name;
- `lnk_config()`'s check runs on the merged manifest of an extends chain;
- the wet relation is unique per `linear_feature_id` (4,532,843 rows = distinct ids), and the preflight and coverage queries use the partial index;
- the `PIPESTATUS` subshell, `CYPHER_PREP_DISCHARGE` quoting (validated to fwapg|wet) and cypher_prep's tempfile/`if !` chain are all sound;
- built.csv read-back with `colClasses = "character"` handles empty and NA source cells.
