# Review round 2: #406 `--jobs` for habitat_variants_build.R (branch diff vs 88923b52, data-raw/ only, through f7b5a5fe)

## Checklist read

All four indexes read; each heading's index line checked against the diff (index headings
match the full files' H3s exactly).

- **code-check.md** (37 headings): read the full prose of all 14 H3s under `## Mechanisms`
  (table rows skipped). Applied hardest: "A guard that fails toward pass" (a reserved value
  on a channel: the NA sentinel below), "A guard's scope, escape hatches, and remedies" (run
  the remedy for every input: the pid remedy below), "Zero-length, empty, and unset",
  "A wrapper's exit is not the work". The 23 stand-alone / Security / Spreadsheets headings
  were checked from their index lines only. Not read in full: 23.
- **code-check-r.md** (111 headings): read in full: "`[[` on a named ATOMIC vector with an
  absent key"; "`tryCatch()` nests its handlers"; "`tryCatch(warning = )` DISCARDS the value";
  "`match()` treats NA as a matchable VALUE". Relied on round 1's full reads of `on.exit()`
  at top level, data-raw loads the source tree, Rscript reads a script as it runs, Postgres
  row order, forked mclapply, `aggregate()`, DB driver types, `$` partial match. Not read in
  full this round: 107 (index lines checked).
- **code-check-shell.md** (67 headings): index lines checked against run.sh (`set -euo
  pipefail`, guarded `cd` inside a subshell with `&&`, no `grep -c`, no ssh). Relied on round
  1's full read of "Parallel writers sharing one output file". Not read in full: 67.
- **code-check-spatial.md** (93 headings): read in full: "GDAL reserves 3,276 MB per process
  …, and PSOCK workers outlive their master". Not read in full: 92.

## What was checked (no database touched, no file run)

- Fix 1 (`focal <- unique(toupper(...))`): every path to a worker list is unique now
  (`wsgs_v` is `focal` for the base, `intersect()` otherwise; `run_variants` is `unique()`),
  so no two tasks of one pass share a working schema. Correct.
- Fix 2 (`clusterCall(cl, Sys.getpid)`): the pids are logged after `clusterEvalQ` (load_all +
  connect) and before any pass. A worker killed-master in the setup window is idle afterwards
  and exits on EOF from its socket, so the window costs nothing. The R pids are right; what
  the remedy stops short of is below.
- Serial path (`--jobs=1`): same steps, same order, same stop messages; argument order of the
  positional `variant_pass(w, v, cfg, sp, want[[w]], is_mad, sch_base)` call matches the
  signature; `!is.null(sp)` is equivalent to the old `!identical(v, base_variant)` because `sp`
  is NULL exactly when `is_base`. New `pass_wall` row also written serially (harmless).
- `want[[w]]` on a named atomic vector cannot hit "subscript out of bounds": `want` is named by
  `wsgs_v` and every dispatched `w` is in `wsgs_v`.
- `tryCatch` in `variant_pass`: expression evaluated in the function frame, so `out$... <-`
  inside it and `out$error <<-` in the handler both write the function's `out`; no handler
  raises. `vapply(res[failed], `[[`, "", "error")` binds `"error"` through `...` correctly.
- `n_segments_of()` returns `count(*)::int` (integer, length 1), so `vapply(..., integer(1))`
  holds; NA sorts last in `order(-n_seg, wsgs_v)`.
- Top-level `tryCatch(..., finally = stopCluster(cl))` replaces the dead `on.exit` shape;
  `start_cluster()`'s own `on.exit` is in a function frame and fires.
- Persisted tables carry no serial / timestamp / run-id column (`lnk_persist_init.R`), so
  digest.R's `t::text` md5 should not differ between widths for a reason unrelated to content.
- digest.R's default `--wsgs` equals `wsg_roles_331.csv`'s nine groups and #404's
  `base_habitat_digest.csv`; run.sh passes no `--wsgs`, so the build's `focal` is the same nine.
- compare.R (key coverage, perturbation, negative control) and analyze.R (step-sum check,
  `jobs == width`, merges) read correctly for nine groups x five rows x four widths.

## Findings

- **[severity: fragile]** data-raw/habitat_variants_build.R:196 (with :286-295) — the base
  digest check is now `if (!is.na(want) && !identical(dg, want)) stop(...)`, with NA used as
  the sentinel for "not the base pass, no check". But NA is also a value the base digest can
  hold: `working_habitat_digest()` returns NA (`md5(string_agg(...))` over zero rows), the
  base run writes it to `base_habitat_digest.csv`, and `read.csv(colClasses = "character")`
  reads it back as `NA_character_`. Before this change `identical(dg, NA)` stopped when the
  re-classify produced rows against an empty base; now that case passes silently, so the
  check that licenses every variant fails toward pass on one input. Reachability is low (a
  focal group with species always has habitat rows), but the sentinel shares a channel with a
  real value. Fix: pass `is_base` (or a separate `check_digest = TRUE`) and keep the old
  `identical()` test, or refuse an NA base digest in the lookup at :289-293 (`if (length(d) !=
  1L || is.na(d)) stop(...)`).

- **[severity: fragile]** data-raw/habitat_variants_build.R:20-22 (header) and :254-255 — the
  remedy for a killed build is "stop those [worker pids] before relaunching". Stopping a
  worker's R process does not stop its Postgres backend: the statement it was running carries
  on until it next writes to the client (CLAUDE.md, #319 status: "killing an R client leaves
  its backend query running: cancel it with `pg_cancel_backend`"), and an autocommit
  `CREATE TABLE AS` / `INSERT` / `DELETE` commits before it finds the client gone. A relaunch
  following the remedy can therefore run its own pass of a group while an orphaned backend is
  still writing that group's working schema or persisted rows, which is the concurrent-writer
  case fix 1 exists to prevent, one step over. With up to 16 workers this is up to 16
  backends, not the serial build's one. Fix: log each worker's backend pid beside its R pid
  (`clusterEvalQ(cl, DBI::dbGetQuery(conn, "SELECT pg_backend_pid()")[[1]])`), and give the
  remedy as killing those R pids **and** `SELECT pg_terminate_backend(pid)` for those backend
  pids (or checking `pg_stat_activity` shows none of them) before relaunching.

No bugs found in the dispatch, result recording, serial equivalence, or the measurement
scripts.
