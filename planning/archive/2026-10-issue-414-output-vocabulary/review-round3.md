# Code-check round 3 (#414): enumeration verification

Reviewer: round 3, branch `414-a-vocabulary-for-link-s-outputs-how-stre` at `e2b86090`,
diff `24e40f92...HEAD`. Ran the three changed test files in a scratch worktree (vocabulary 45
pass / 1 skip, log 323, pipeline_run 29; 0 failed, 0 error). Disclosure: `tests/testthat/setup.R:36`
issued `CREATE SCHEMA IF NOT EXISTS working` against the local DB while `test-lnk_log.R` ran; the
schema already existed, so it was a no-op ("already exists, skipping"). Nothing else was written.
Worktree removed.

## Checklist read

- code-check.md: every H3 under `## Mechanisms` (a guard that fails toward pass, including
  "Defaults and normalisers"; a fixture that cannot reach the failure mode; a proxy is not the
  property; one fact derived twice; serialization loses meaning silently).
- code-check-r.md: `sort()` / `order()` collate by `LC_COLLATE`; `identical(-0, 0)` and
  digests; `match()` treats NA as a value; `paste()` with a zero-length argument; `nzchar(NA)`;
  `Rscript -e` supplies `--args`; `[[` on a named atomic; Postgres row order.
- code-check-shell.md: `if ! cmd; then rc=$?`; command substitution under `set -e`.

## Findings

- **[severity: fragile]** `R/lnk_vocabulary.R:221-226` (`.lnk_vocabulary_num`, reached from
  `.lnk_vocabulary_canonical()` line 239 via `is.double(v)`): a `Date` or `POSIXct` column is
  `is.double()`, so it is sent to the number formatter. `as.character()` gives `"2020-01-01"`,
  `as.numeric()` of that is `NA` (with a coercion warning), `lossy` becomes `NA`, and
  `out[lossy] <- ...` errors with "NAs are not allowed in subscripted assignments" (reproduced).
  Today `observation_date_min` loads as character in all three shipped bundles, so nothing hits
  it. It fails closed (every run of that config is refused), not toward pass, but with a
  message that names neither the column nor the vocabulary. If the crate canonical schema ever
  types the date column, every run refuses with that message. Narrowest fix: test
  `is.double(v) && !inherits(v, c("Date", "POSIXt"))` (or `typeof(v) == "double" &&
  is.null(attr(v, "class"))`) before calling the formatter.

- **[severity: fragile, scope]** `data-raw/wsg_recompute_one.R:47-60,176` rewrites
  `streams_access` (the authoritative access answer, #349) from the *current* config's presence
  and species (`lnk_presence(loaded$wsg_species_presence, wsg)`, `species = active`). It resolves
  no tokens and checks none, and `log_recompute` carries `config_hash` but no token columns. A
  `--recompute-only` at a later commit whose presence table changed keeps the build's
  `log.token_acc` while the shipped access columns were decided under other rules. It does not
  move cuts, and within one run the repo is frozen, so this is outside what the four tokens
  were scoped to. It is still the one writer of an `acc`-dependent output that the vocabulary
  does not guard. Either say so in the RUNBOOK section ("tokens describe the model-time build;
  a recompute is guarded by `config_hash` only"), or have the recompute resolve tokens and
  refuse when they differ from the group's newest `log` row.

Nothing else found in the round-2 fix code:
- `.lnk_vocabulary_num`: `NA` stays `NA` (the canonical step then writes `\N`), and `NaN` folds
  to `\N` with `NA`. Every reader treats both through `is.na()`, so that fold is harmless. `-0`
  writes `"0"`; no reader separates it from 0. `%.17g` always round-trips, so the lossy branch
  is injective. A named vector loses its names, which is right here.
- Duplicate-key refusal (lines 187-195): exact `duplicated()` on the raw key, NA included,
  before anything sorts. `lnk_barrier_overrides()` iterates every parameters_fresh row (not
  only the first), and `ON CONFLICT DO NOTHING` takes the union of duplicate rows' lifts, so
  the refusal is needed for a second reason besides the comment's. Keys differing by
  case or whitespace are distinct keys to every reader, and sorting them reorders only reads
  that are sets (SQL `IN`, `UNION`, `ON CONFLICT`) or array order, which readers test with `= ANY`.
- Barrier inputs from `loaded`: matches `prepare`'s `!is.null(loaded$<key>)` gates
  (`lnk_pipeline_prepare.R:192,217,239,419,524`). See row 6 below for what presence really switches.

## Enumeration verdict

| # | Agree? | Note |
|---|---|---|
| 1 | Yes | `lnk_pipeline_break()` calls `.lnk_break_order()`. The three `subsurfaceflow` tests (`prep_natural`, `prep_minimal`, classify) read `cfg$pipeline$break_order %||% character()` rather than the helper. They agree with it, because the default omits `subsurfaceflow` and an explicit value is identical in both. |
| 2 | Yes | `observations_breaks` is read only as the `observations` break source (`lnk_pipeline_break.R:113`). Access code 2 reads `<schema>.observations`. |
| 3 | Yes | Shared, closed set. |
| 4 | Yes | `lnk_pipeline_run()` never passes `classes`, so prepare resolves `.lnk_resolve_classes(NULL, cfg)`, as the spec does. An unnamed list emits values without `name:`, which no named form can produce, so there is no collision. |
| 5 | Yes | Fragile on Date (finding 1); exact for doubles. |
| 6 | Yes, and it over-approximates safely | For all three keys, an absent file behaves exactly like a declared file with no rows for the group (empty `barriers_definite`; control `DELETE` / `NOT EXISTS` against an empty table; habitat overrides adding nothing). So listing presence only makes tokens spurious, never too few. The crossings CSVs (`user_modelled_crossing_fixes`, staged only when the group has rows, `lnk_pipeline_load.R:139-152`, and `crossings_union` gating on the table; `pscis_modelledcrossings_streams_xref`, `pscis_build.R:81`) move crossing positions, so they move cuts. They have the same absent-equals-empty property, so leaving them as vintage is consistent. The CABD edit CSVs move dam positions; their absence refuses in `prep_dams` (fails closed). |
| 7 | Yes | Both sides use `isTRUE(cfg$pipeline$discharge_fill)` and `.lnk_discharge_source()`. Per group, the fill is applied only where a group is on `mad`, a rule-level `mad:` exists, or a near-river pair is measured by discharge. q-wet-fill's definition states that, and `mad_m3s` is never persisted. |
| 8 | Yes | No knob reaches `frs_col_generate()`. |
| 9 | Yes | `cfg$species` is `names(rules.yaml)`. `prep_minimal`, `lnk_pipeline_species` and persist take it as is. Its `%||% unique(pf$species_code)` fallback is covered because the whole parameters_fresh digest is included. |
| 10 | Yes | `prep_minimal` and `lnk_barriers_unify` read the same constant. |
| 11 | Yes | Both callers (`prepare.R:640`, `run.R:248`) use the default `groups`. |
| 12 | Yes | link reads only `species_code` and `access_gradient_max` (grep), and `lnk_barrier_overrides` reads the five `observation_*` columns. fresh's `frs_habitat_classify` reads `access_gradient_max` for access. |
| 13 | Yes | |
| 14 | Yes | Column order reaches readers only as set-like SQL lists. |
| 15 | Yes | See the duplicate-key note above. |
| 16 | Yes, with a remark | A type change folds where `as.character()` agrees: double `0.15` with character `"0.15"` (the test at line 165 pins that), logical `TRUE` with `"TRUE"`, integer with an integral double. I checked each against its readers. `.lnk_presence_truthy` and `.lnk_wsg_species_present` treat `TRUE` and `"TRUE"` alike. `as.integer` and `isTRUE(as.logical())` treat the folded pairs alike. `classes >= sp_amax` on a character `sp_amax` compares as text, which matches numeric order for `0.x` decimals in shortest form, the only form a folded double produces. The crate schema fixes these types anyway. No collision a reader distinguishes. |
| 17 | Yes | `\N` versus a literal `\N` is kept apart by escaping the backslash. The header line is never sorted, so a data row cannot collide with it. |

**Missing candidates.** I found no input that moves cuts or access at model time and is
neither projected nor already accepted as vintage. Checked and cleared:
- `pipeline: cabd_additions_barriers`: the placeholder rows are in `<schema>.dams` either way
  (`.lnk_dams_usa_sql` only sets the status), and crossings cut regardless of status. Status
  reaches mapping code only.
- `pipeline: apply_habitat_overlay`: habitat flags only.
- `lnk_pipeline_run(dams = FALSE)`: drops `<schema>.dams`, after which `lnk_pipeline_crossings`'
  `lnk_inputs_verify` refuses. It fails loud and is not a silent cut change.
- `parameters_habitat_method`, `parameters_habitat_thresholds` and `rules.yaml` beyond the species
  keys: habitat only.
- `user_crossings_misc`: rebuilt away by `.lnk_crossings_union`.
- `species_pooling` and `species_groups`: no reader in `R/` outside the validator, plus a
  `cfg$files` check in `lnk_log.R:134`.
- Env vars (`LNK_HABITAT_GATE`, `LNK_GUARD_DOWNSTREAM`): habitat and guards only.

The one writer outside the enumeration's frame is the post-consolidate recompute (finding 2).
It is not a projection step, so it is not a row the table is missing, but it writes `acc`-dependent
output under a config the tokens never saw.

Non-blocking doc note: `research/output_vocabulary.md`'s "The axes" table lists the cut axis
without the barrier-input files, which the RUNBOOK table and the code include.
