# Code-check round 4 (terminating) — link#274 outside readers, HEAD c2b7b7f2

## Checklist read

- `code-check.md` `## Mechanisms` H3 prose: "A guard that fails toward pass" (what the guard
  reads; provenance; defaults that decide), "A fixture that cannot reach the failure mode",
  "A proxy is not the property", "One fact derived twice".
- `code-check-r.md`: "`paste()` with a zero-length argument…", "`data.frame()` recycles a
  scalar against a zero-length column", "`match()` treats NA as a matchable VALUE",
  "`system2(stdout = TRUE)` warns on a non-zero exit…", "A `data-raw/` script must load the
  source tree…", "`read.delim()` quotes by default…".
- `code-check-shell.md`: "A failed `cd` lets every later command run…", "`if ! cmd; then
  rc=$?`…".

Method: parsed `readers_classify()` (data-raw/recompute_readers.R:78-132) for every fact it
tests, then traced each to where `recompute_readers_check.R` reads the reader's value and the
"now" value, and against what `recompute_one` (study_area_run.sh:749) actually runs. Then
walked `wsg_recompute_one.R` and everything it calls for inputs. Fix 1's edge cases were run
in R (0-row `last`, `pc[NA]`); nothing was written to the database (read-only `log` queries
for `''` in the sha columns: 0 rows in `fresh` and `fresh_default`).

## Enumeration

### 1. Facts `readers_classify()` tests

| fact | reader's value | "now" | now measured from what the recompute runs? | unknown refuses? | verdict |
|---|---|---|---|---|---|
| has_log | `<schema>.log` newest row exists | — | — | yes (`no_log`) | holds |
| open | `date_end IS NULL` of newest row by `date_start` | — | — | yes (`is_false`) | holds |
| config_hash | log | `lnk_stamp(cfg)$config_hash`; cfg from `lnk_config($CONFIG)` under load_all in REPO_ROOT, same as the job; the hash reads no in-memory schema | yes | yes; plus `config_changed_since_run` cross-checks the computation against the run's own rows | holds |
| fresh_sha | log | stamp's `software$fresh$git_sha` | env: confirmed against installed RemoteSha (fix 3); remote_sha: is the RemoteSha of the copy `packageDescription()` resolves, the loaded namespace first, which is the installed fresh link's load_all attaches in both processes; git: unreachable for an installed fresh (no `.git` in or above a library dir); NA: expect `""`, never equal to a logged sha (no `''` rows; writer maps blank to NULL) | yes | holds now-side; reader side see Finding 2 |
| fresh_dirty (now) | — | `software$fresh$dirty` must be FALSE (fix 2) | env with RemoteSha equal → FALSE by inference, or FRESH_GIT_DIRTY; remote_sha → FALSE; NA → NA → refuses | yes | holds |
| fwapg_sha | log | `.lnk_fwapg_sha()`: FWAPG_GIT_SHA (exported by preflight in a full run, unset or ~/.Renviron in `--recompute-only`), else checkout HEAD | no: the recompute runs the DB's `fwa_*` SQL functions, which no stamp records. Same stand-in the job's own `log_recompute` stamps, and the same for run groups | NA → `""` refuses | pre-existing stand-in (see 2) |
| link_dirty | log, pathspec excludes only data-raw/logs | — | — | yes (`is_false`) | holds |
| fresh_dirty (reader) | log | — | — | yes | holds |
| path_changed | `git diff --name-only <link_sha> -- READERS_PATHS` (sha to working tree, tracked) plus `dispatcher_tree_dirty` (status incl. untracked) | working tree in REPO_ROOT, the tree load_all runs | yes; ignored files under R/ or inst/extdata/: none (`git status --ignored` empty) | bad sha, absent object or git failure → NA → `sha_unresolvable`; `pc[NA]` → NA (run) | holds |
| downstream | dry run of `lnk_wsg_downstream_check(on_fail = "warn")` with the job's cfg, loaded and schema | same function, same DB state for what it reads (cabd.dams, persisted CABD barriers; no recompute writes barrier rows) | yes | error → NA, warn/override → NA, refuses | holds |
| refuse_all: dispatcher_fresh_pin_stale (fix 3) | — | `sha_source == "env"` and installed RemoteSha differs, incl. NA RemoteSha | env: RemoteSha NA → refuse (stricter than preflight, which lets a pin with no RemoteSha stand; spurious-refusal direction, label says "stale" where it is "unconfirmed"); remote_sha / git / NA: not triggered, correctly | — | holds |

### 2. What the recompute reads that could differ between a reader's build and now

- link code (R/, inst/extdata, DESCRIPTION, NAMESPACE, the job script, views build, the two driver files) — covered by path_changed + tree dirty. Holds.
- config bundle files, species, presence, overlay CSV bytes — config_hash. Holds.
- fresh (frs_network_features, outlets CSV, fallback thresholds) — fresh_sha + dirty + fix 3. Holds now-side.
- crate (ingests `user_habitat_classification`, the gate's overlay) — **not compared** (Finding 1).
- Other R deps (DBI, RPostgres, digest, R itself) — not compared; read nothing that shapes values here beyond types link coerces. Not a finding.
- Environment: LNK_SCHEMA (exported once at study_area_run.sh:527, before both paths; the check gets the same $SCHEMA in argv), LNK_VIEWS_PREBUILT (only whether views are rebuilt), LNK_LOG (logging only), PGOPTIONS (the job SETs its own). Holds.
- Persisted tables (reader's streams, streams_access, streams_habitat_<sp>, barrier_overrides; run groups' barriers) — the point of the recompute. Holds.
- Barrier views and streams_habitat_long_vw definitions — built at current code, read persisted tables only. Holds.
- DB primitives: `whse_basemapping.fwa_*` functions and FWA tables (walk, outlets), cabd.dams (dry run measures it). FWA/fwapg vintage is a stand-in (fwapg_sha) on both sides — pre-existing: already true of every recompute of a run group, and data vintage gets no token by decision.
- Access 1-vs-2 of a segment an earlier recompute set to 0 and this one lifts comes back as 1, not 2 (lnk_access merge CASE) — pre-existing merge semantics; these are exactly the segments `n_lifted_settled` counts, and `recompute_readers_lifted` names such readers.

### 3. The three fixes

- Fix 1 (`rep(..., nrow(last))`, `as.integer(...)`): run on a 0-row `last` → 0x4 frame, no error; NA link_sha indexes to NA. Holds.
- Fix 2: `!identical(dirty, FALSE)` refuses TRUE and NA. Holds.
- Fix 3: correct for every sha_source (table above); `identical()` on two length-1 characters; a whitespace or case variant of the pin refuses (spurious direction). Holds.

## Findings

- **[fragile]** data-raw/recompute_readers_check.R:142-148 (and readers_classify) — `crate` is not compared, though it ingests `user_habitat_classification`, the overlay `lnk_habitat_gate()` uses to keep spawning/rearing on access-0 segments (wsg_recompute_one.R:189). `crate` is unpinned (`Remotes: NewGraphEnvironment/crate`), and `<schema>.log.crate_version` is recorded and never read here. A reader built months ago under one crate is recomputed under whatever crate is installed now; if the newer crate drops or reshapes rows of that file, the gate blanks habitat the build kept, and the gate is one-way. Run groups are modelled under the current crate in the same run, so this is new to readers. Cheap close: select `crate_version` and refuse on difference from `utils::packageVersion("crate")` (version, not sha: it is all the log has). Low likelihood, irreversible when it happens.
  - **Rule:** code-check.md "A proxy is not the property" (fresh_sha + link paths stand for "the code the recompute runs"; one input is missing). **Inside a previous fix?** no

- **[fragile]** data-raw/recompute_readers_check.R:142-148 / data-raw/recompute_readers.R:112 — the reader's `fresh_sha` is taken from its log whatever `fresh_sha_source` says. Fix 3 now refuses a FRESH_GIT_SHA pin the installed fresh does not confirm, but only for "now"; a reader built by a hand `wsg_run_one.R` (which runs no pin-staleness check; only study_area_run.sh's preflight does) on a host with a stale ~/.Renviron pin logged the pin, not the fresh it ran. Reachable only where today's installed fresh equals that stale pin's commit, so rare. The log also carries `fresh_version` and `fresh_sha_source`; refusing a reader whose `fresh_version` differs from the installed version (or whose source is `env` with no corroboration) would close most of it. Same mechanism the round named (two sides written separately), on the reader's side.
  - **Rule:** code-check.md "A guard that fails toward pass" ("What the guard reads"; provenance read from a stand-in). **Inside a previous fix?** no (the mirror of fix 3)

No defect found in fixes 1-3. Everything else in the enumeration holds or is pre-existing as stated.
