# Review round 1 — #406 `--jobs` for habitat_variants_build.R (branch diff vs 88923b52, data-raw/ only)

## Checklist read

All four indexes read in full (every heading checked against the diff).

- **code-check.md** (37 headings): read the full prose of all 14 H3s under `## Mechanisms`
  (table rows skipped). The 23 stand-alone / Security / Spreadsheets headings were checked
  from their index lines only (none applies: no YAML, URLs, credentials beyond the local
  dev DB already committed in the script, preview flags, or PDFs). Not read in full: 23.
- **code-check-r.md** (111 headings): read in full: "`on.exit()` at a script's top level never
  fires"; "A `data-raw/` script must load the source tree"; "Rscript reads a script as it runs";
  "Postgres row order is never fixed…"; "`tryCatch()` nests its handlers"; "Forked
  `parallel::mclapply()` workers segfault…"; "`stats::aggregate()` has three separate silent
  behaviours"; "A database driver's value is not a base R type"; "`$` on a list partial-matches".
  Not read in full: 102 (index lines checked).
- **code-check-shell.md** (67 headings): read in full: "A `pgrep -f` waiter matches its own
  command line"; "Parallel writers sharing one output file interleave mid-record"; "psql does not
  interpolate…". Not read in full: 64.
- **code-check-spatial.md** (93 headings): read in full: "GDAL reserves 3,276 MB per process…,
  and PSOCK workers outlive their master" (the PSOCK half applies). Not read in full: 92.

## What was verified (no database touched)

- In a scratch dir, a PSOCK cluster with `outfile = ""`, functions exported by `clusterExport`
  and a worker global set by `clusterEvalQ`, called through `clusterApplyLB(cl, x, lb, want =,
  v =, sp = NULL)` with `lb <- function(w, want, ...) f(w, want = want[[w]], ...)`:
  the exported closures resolve globals in the **worker's** global env (worker value seen, not
  the master's), `sp = NULL` arrives as NULL through `...`, results come back in `x` order,
  POSIXct survives the round trip, and worker `message()` lines land in the master's redirected
  log (so `analyze.R`'s "done in" parse sees them).
- `variant_helpers` + `conn_args` + the worker's own `conn` cover every free symbol in
  `variant_pass()` (`working_prefix`, `digest_sql`, `base_bundle`, `loaded`, `say`,
  `secs_since`, `load_1min`, `copy_access`, `digest_of`, `working_habitat_digest`); everything
  else is link/fresh/DBI, attached by the worker's `load_all()` + `library(DBI)` from the
  master's cwd. `lnk_config()` absolutizes file paths, so `cfg` serializes cleanly.
- The serial path (`--jobs=1`) runs the same steps in the same order with the same stop
  messages; the base digest lookup now happens before any group runs (stricter, not looser).
- `lnk_habitat_gate()`'s overlay is a session temp table named per group; classify's
  `streams_breaks` and discharge join are in the per-group working schema.
- macOS `pkill -f` excludes its ancestors (tested: `bash -c 'pkill -f <pat>; echo survived'`
  survives), so the documented remedy does not kill its own shell.
- `compare.R`'s perturbation check and negative control, `digest.R`'s per-group ordering on
  `(id_segment)` / `(id_segment, species_code)` (unique within a group), and `analyze.R`'s
  aggregates/merges read correctly for the nine-group, four-width run.

## Findings

- **[severity: fragile]** data-raw/habitat_variants_build.R:320 with :1018-1019 / :1057 —
  `focal <- toupper(split_csv(opt("wsgs")))` is not de-duplicated, and the base pass uses
  `wsgs_v <- focal` directly. With `--wsgs=REVL,REVL` (or any repeated code) and `--jobs > 1`,
  `clusterApplyLB` dispatches the same group to two workers at once, so two sessions
  DROP/CREATE `streams_breaks`, re-classify and digest the same working schema concurrently
  (an error at best, a digest of interleaved writes at worst); `res[wsgs_v]` then reads the
  first copy twice. Serially the repeat was a harmless second pass. Fix: `focal <-
  unique(toupper(split_csv(opt("wsgs"))))` (non-base variants already go through
  `intersect()`, which de-duplicates).
- **[severity: fragile]** data-raw/habitat_variants_build.R:74-75 (header comment) — the remedy
  "stop them with `pkill -f workRSOCK` before relaunching" kills **every** PSOCK worker on the
  host, not this build's: any other R session using `parallel::makeCluster()` on m4 (CLAUDE.md
  records other processes loading m4 during these builds) loses its workers. Per the spatial
  convention's PSOCK section, register this build's worker PIDs
  (`parallel::clusterCall(cl, Sys.getpid)`, logged with `say()`) and give the remedy as
  `kill <those pids>`, or at minimum say the pattern matches other sessions' workers.

No bugs found in the parallel dispatch, the worker setup, the result recording, or the
measurement scripts.
