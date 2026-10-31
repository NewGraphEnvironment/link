# Code-check round 3: branch 429-weekly-csv-sync-skips-four-copied-bcfish (HEAD 37207eac, base e5899a02)

## Checklist read

- **code-check.md**: the prose of every H3 under `## Mechanisms` read in full except where noted: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work", "Zero-length, empty, and unset are three different things". Read in part (first paragraphs only): "The probe is broken before the world is", "Written data outlives the fix", "Serialization loses meaning silently", "One fact derived twice". Stand-alone rules: none read in full (about 25 headings not read).
- **code-check-r.md**: from the index only. Headings that apply here, taken from their index lines: "Read-back shape must match write-back shape", "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree, not the installed package", "CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests", "`tryCatch(warning = )` DISCARDS the value the expression produced", "`nzchar(NA)` is TRUE — non-empty checks silently pass NA", "`match()` treats NA as a matchable VALUE, so two unknowns join to each other", "`[[` on a named ATOMIC vector with an absent key is an error, not `NULL`", "`expect_false(identical(x, y))` cannot fail when the two are different types". Full sections not opened; about 110 headings not read.
- **code-check-shell.md**: from the index only ("Quoting", "A heredoc whose body contains its own delimiter ends early…"). The workflow's bash was checked against them. About 95 headings not read.
- **code-check-spatial.md**: not applicable (no spatial code); not read.

## Mechanism behind rounds 1 and 2

Both earlier defects are one guard failing toward pass: **a gate reads one channel for failure (a lookup hit, or an R error), while the input can fail on a channel the gate does not read (a key on the other list, or a warning)**. The gate then reads the miss as "nothing to check" or "loads OK".

Round 2 fixed the warning channel in one caller of the bundle loader, the crate schema check (`validate_canonical_schema()`). The trial write (`.lnk_sync_trial()` → `.lnk_sync_specs()` → `lnk_load_overrides()`) is a second caller that decides from loading the same new bytes, and it still catches errors only. That is the "A fix lands in one of two callers that share a harness" shape: the class was fixed twice in one place and the sibling kept it.

## Enumeration of every verdict point the branch adds or changes

| # | Place | Input | Malformed / empty / NA / warning-only / missing input | Verdict |
|---|---|---|---|---|
| 1 | `.lnk_sync_targets()` (R/lnk_csv_sync.R:9) | provenance block | NULL or a mistyped `source` gives zero targets, so zero loop passes and "clean". Guarded: test-lnk_csv_sync.R asserts the 14 stems in both bundles, and that every `source: bcfp` files entry is a target | OK |
| 2 | sync, `upstream_rel` NULL (sync:210) | provenance `path` | stop | OK |
| 3 | `fetch()` (sync:179) | S3 GET | HTTP ≥ 400 or a transport error stops the run. A zero-byte 200 gives a checksum mismatch, and `shape_fingerprint()` returns NA, which is not identical to the stored value, so shape | OK |
| 4 | `schema_of(rel)` (sync:203) | `files:` path vs provenance key | A miss gives NULL and the schema check is skipped silently (round 1's mechanism). Today the only `canonical_schema` entry (UHC, both bundles) has `source: bcfp`, and the test pins its path string as a target | OK (guarded) |
| 5 | `validate_canonical_schema()` (sync:143) | crt_ingest of the new bytes | An error or any warning becomes a schema error, so shape. Dry run today: 0 warnings | OK |
| 6 | checksum compare (sync:220) | provenance `checksum` | A missing checksum is not identical, so drift | OK |
| 7 | `shape_drift` (sync:224) | provenance `shape_checksum` | A missing `shape_checksum` gives FALSE (fail open). Measured: every target in both bundles carries checksum, shape_checksum, upstream_sha, synced and path, each with exactly one header line | OK today |
| 8 | trial `before` load (lnk_csv_sync.R:46) | current bundle | error stops the run (red) | OK |
| 9 | trial `file.copy` (lnk_csv_sync.R:54) | bundle dir | FALSE stops the run | OK |
| 10 | trial `after` load error (lnk_csv_sync.R:60) | new bytes | error goes to `tr$error` and becomes review | OK |
| 11 | **trial `after` load, warning-only** (lnk_csv_sync.R:31-37, 60) | new bytes read through `read.csv()` | **A read that loses rows with only a warning (EOF within quoted string) is not an error. The specs of non-presence files do not move, so the verdict is byte and the PR auto-merges** | **defect** |
| 12 | trial `moved` (lnk_csv_sync.R:61-63) | spec strings | Specs are always non-NA strings (`.lnk_vocabulary_specs()`) with fixed axes | OK |
| 13 | files not in `files:` (dfo_known_sockeye_lakes, wcrp_watersheds) | new bytes | Never loaded by the trial, so byte. No run reads them (only data-raw/wsg_species_presence_check.R) and they carry no token | OK by design |
| 14 | `.lnk_sync_overlay_redundant()` (lnk_csv_sync.R:74) | base and overlay | An unparseable base or overlay stops the run (red). Base `"NA"` read as NA against an overlay `"NA"` gives "not redundant". Report only; it does not decide the kind | OK |
| 15 | `.lnk_sync_drift_kind()` | three flags | `isTRUE()` on each; ranking tested | OK |
| 16 | dry-run `quit(0)` (sync:291) | flag | CI never passes it | OK |
| 17 | `update_provenance_in_yaml()` | YAML lines | A header count other than 1 stops the run. A missing field line is not added; every target has all four (row 7) | OK |
| 18 | workflow case (yml:79-93) | /tmp/sync_drift_kind | A missing file reads as none, but it is written before any `quit()`, and an R failure stops the job first. An unknown kind exits 1. Review opens a PR and exits 2 | OK |
| 19 | `.lnk_overlay_apply()` checks (R/lnk_overlay.R) | overlay CSV | These all stop: wrong columns, key column missing, duplicate base key, key-column target, blank or space-only reason, duplicate cell, unknown or blank key. A blank `column` stops with "undefined columns selected" (closed, unclear message). A misspelled `column` (`CH` for `ch`) silently adds a new column, which is the deliberate insertion rule (accepted). An empty overlay returns the base | OK |
| 20 | overlay typing (lnk_load_overrides.R:94-95) | base read as character | Identical to `read.csv()` typing on logical, Inf, hex, padded and NA columns (measured) | OK |
| 21 | `.lnk_load_entry()` canonical + overlay; non-csv + overlay | entry | stop | OK |
| 22 | `lnk_config()` overlay path (lnk_config.R:296) | entry | A missing file stops; an inherited overlay is made absolute against the parent | OK |
| 23 | `.lnk_config_files()` (lnk_log.R:90) | files | The overlay enters `config_hash` (tested) | OK |
| 24 | `pretest_inputs.csv` | new files | `R/lnk_overlay.R` any, `R/lnk_csv_sync.R` none, overlay CSV mapped to segments | OK |
| 25 | test assertions in test-lnk_csv_sync.R / test-lnk_overlay.R | | `setdiff` directions are correct (declared set must be present); the trial tests read `tr$error` and `tr$moved` directly | OK |
| 26 | "incomplete final line" muffle (lnk_load_overrides.R:82) | warning text | Matched in English; under a translated R the warning is not muffled, which makes noise and passes nothing | OK |

## Findings

- **[severity: bug]** R/lnk_csv_sync.R:31-37 (`.lnk_sync_specs()`, used by `.lnk_sync_trial()` at :60), read by data-raw/sync_bcfishpass_csvs.R:237-243. The trial treats a bundle that loads **with a warning** as loading cleanly. The bundle files a run reads through `.lnk_load_local()` (observation_exclusions, user_modelled_crossing_fixes, user_pscis_barrier_status, pscis_modelledcrossings_streams_xref, user_barriers_definite(_control), user_crossings_misc, cabd_*) are read by `utils::read.csv()`, which on a stray unbalanced quote warns "EOF within quoted string" and returns a truncated table, with no error. The header is unchanged, so there is no shape drift. Only the presence table feeds a token spec, so `moved` stays empty, `tr$error` stays NULL, and the kind is `byte`. The workflow then auto-merges the file with `gh pr merge --merge`, and every later run loads it short by the same silent warning.
  - Measured in a worktree at HEAD: one row with an unterminated note was inserted three lines from the end of `overrides/observation_exclusions.csv` (bcfishpass bundle). `read.csv` warned and returned 1,180 rows where 1,183 were expected. `.lnk_sync_trial()` returned `moved = character(0)` and `error = NULL`, so `.lnk_sync_drift_kind()` gave `"byte"`.
  - This is round 2's defect (a warning-only failure read as pass) in the sibling caller: round 2 counted warnings in `validate_canonical_schema()` only.
  - The fix does not false-alarm today: loading the current bcfishpass and default bundles through `.lnk_sync_specs()` emits 0 warnings. So `.lnk_sync_specs()` can collect warnings with `withCallingHandlers()` (the loader already muffles the benign "incomplete final line") and return them as `error`, which routes to `review`.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness" ; code-check.md "A guard that fails toward pass"
