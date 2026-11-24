# Code-check round 1 — branch 501 (RB back in `default`)

Reviewed `5d45c5de` against merge-base `b89d3150`.

## Checklist read

- **code-check.md**: I read the prose of all 14 H3s under `## Mechanisms`. From "Rules that stand alone" I read "Documentation Staleness" and "An assertion that matches an interpolated value cannot see the claim around it". 22 headings not read.
- **code-check-r.md**: I read these headings.
  - "`$` on a list partial-matches, so a longer sibling key answers for a missing one"
  - "`data.frame()` recycles a scalar against a zero-length column"
  - "Postgres row order is never fixed unless the query fixes it, so a pick, a float sum and a presence check can each depend on it"
  - "`sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent"
  - "A `data-raw/` script must load the source tree, not the installed package"
  - "Inside a dplyr verb, a column named like a local variable wins"
  - "`paste()` with a zero-length argument returns length ONE, not zero"

  For base `merge()`, which no heading covers, I checked the column naming directly: `merge(z, one, by.x = "species_code", by.y = "species_obs")` yields `species_code.y`, including with zero rows. 123 headings not read.
- **code-check-shell.md**: from the index only, for "BSD vs GNU sed/grep portability" and "A variable in a sed replacement is parsed". `build.sh` already ran and is an accepted tradeoff. 73 headings not read in full.
- **code-check-spatial.md**: none apply. 96 not read.

## What I verified

- **Config checksums.** The `config.yaml` checksums for `species_pooling.csv`, `species_modelled.csv` and `wsg_species_presence_overlay.csv` match `shasum -a 256` of the files at HEAD.
- **Tokens per bundle.** `lnk_vocabulary_resolve()` at HEAD gives:

  | bundle | tokens |
  |---|---|
  | `default` | `cut-full-top-3 acc-v7 grad-seg q-fwapg` |
  | `default_tuned` | `cut-full-top-3 acc-v7 grad-seg q-wet-fill` |
  | `default_minimal` | `cut-min acc-v7 grad-seg q-fwapg` |
  | `default_parent` | `cut-full-top-3 acc-v7 grad-parent q-fwapg` |
  | `bcfishpass` | `cut-full-ssf-all-2 acc-bcfp-5 grad-seg q-fwapg` |

  No live bundle resolves to a retired token.
- **Tests.** Run in a detached worktree at HEAD with `NOT_CRAN=true`, every file below had 0 failures and 0 skips:

  | test file | passed |
  |---|---|
  | `test-lnk_observation_records` | 63 |
  | `test-lnk_presence_measures` | 54 |
  | `test-lnk_vocabulary` | 82 |
  | `test-lnk_config` | 224 |
  | `test-lnk_pipeline_species` | 19 |
  | `test-lnk_csv_sync` | 54 |
  | `test-dictionaries` | 167 |
  | `test-lnk_presence_check` | 93 |
  | `test-lnk_barrier_overrides` | 33 |
  | `test-lnk_log` | 342 |

  The last two files create and then drop their own `zz_lnk_*_test` scratch schemas on the local fwapg. I ran them before noticing that, and nothing they created is left behind.
- **Paused-only groups.** No group in `default` has only paused species present at HEAD, so the RUNBOOK's "none since RB is modelled again" holds.
- **Alias resolution.** `.lnk_record_aliases()` on `default` gives SST and WST two targets each (RB and ST) in all 246 groups. `.lnk_record_aliases_everywhere()` returns both pairs for each. `lnk_species_pooling()` keeps one row per (target, obs) in each group, so `pm_alias` cannot duplicate a (group, alias, target) row.
- **The two-row record in `.lnk_presence_check()` and the presence-check script.** The alias `merge()` keeps every hit with its `row_id`, so one record yields two rows. The script's SQL recount of `n_records`, `n_kept_own` and the zones agrees with that grain.

## Findings

- **[severity: fragile]** `data-raw/rb_st_records_check.R:145-148`: re-running the script on HEAD double-counts every SST and WST record.
  - **What happens.** The branch changed `.lnk_presence_measures()` from one row per record to one row per record and species. At HEAD every SST and WST record has two rows in `meas`, one as ST and one as RB, because the RB←SST and RB←WST alias rows resolve in all 246 groups. The script still merges `meas` into `rec` (one row per record) by `observation_key` alone: `rec <- merge(rec, m, by = "observation_key", all.x = TRUE)`. Each of the 762 SST and WST records (404 + 358 in local bcfishobs) therefore appears twice.
  - **What it inflates.** `records.csv.gz`; the `st_above` and `st_reachable` class counts; `records_as_rb`, `undated_as_rb` and `st_records_as_rb` for option c (`is_st` includes SST and WST); and the per-group `n_rb_c`.
  - **Why nothing catches it.** `stopifnot(!anyNA(rec$species_read))` does not look for duplicates. The independent check only covers `code_raw IN ('RB', 'ST')`. The run would finish silently with wrong counts.
  - **Why the committed outputs are correct.** They were produced at `1ec45ba5`, before the pooling rows landed in `997a63b9`; `records.csv.gz` has no duplicate key. The fault appears only when someone reruns the script to reproduce or refresh `data-raw/logs/rb_st_497/`.
  - **The two sibling callers were adapted.** `wsg_species_presence_check.R` replaced its `nrow` check with a per-(key, species) check, and `wsg_species_presence_map.R` switched its `anyDuplicated` to (key, species).
  - **Fix.** Keep one `meas` row per record before the merge, for example the row whose `species_code` equals the record's own steelhead or RB reading. Or merge on `observation_key` plus a species, and assert `!anyDuplicated(rec$observation_key)` after the merge.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"
