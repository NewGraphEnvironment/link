# Code-check round 2 — branch `361-provincial-run-can-a-drainage-component`

Reviewer: fresh agent, read-only against `/tmp/codecheck.vz9pBy/` (diff, full changed files),
plus `data-raw/study_area_hosts.sh`, `R/lnk_wsg_resolve.R`, `R/lnk_log.R` (log DDL and the
three-state `.lnk_log_run_fail()` signal), `data-raw/habitat_validate.R` (one doc claim) and the
committed evidence under `data-raw/logs/provincial_361/` (file presence; `run_verify.log` and
`verify_negative.log` as the run's own record). Nothing was run against the database or the
cloud. `review-round1.md` was read after the view below was formed.

## Checklist read

- `code-check.index.md`: in full.
- `code-check-shell.index.md`: in full.
- `code-check-r.index.md`: in full.
- `code-check-spatial.index.md`: in full.
- `code-check.md` (full text): the prose of all 14 H3s under `## Mechanisms` (table rows
  skipped), plus "Documentation Staleness", "An ordered dispatch makes severity ordering
  load-bearing" and "An assertion that matches an interpolated value cannot see the claim
  around it". Not read: the other 16 stand-alone rules, Security, Spreadsheets/PDFs (the diff
  carries no YAML, URLs, credentials, bucket policy, spreadsheet or PDF handling).
- `code-check-shell.md` (full text): read in full "Empty arrays under `set -u`", "Quoting",
  "Heredoc precedence in pipelines", "Reading a file line-by-line drops the last line", "psql
  does not interpolate `:'var'`", "A second `trap … EXIT`", "`grep -c` prints the count",
  "`for x in $(cmd | grep …)`", "A `local` statement cannot read a variable it is assigning",
  "`if ! cmd; then rc=$?`", "A sed/awk range can run to EOF", "awk `==` compares version
  strings", "A verification command can be shadowed", "`exit` inside a loop condition", "A
  failed `cd`", "BSD vs GNU sed/grep". Not read: 48 sections (git/gh/ssh/S3/docker/curl/conda/
  Perl/Python/sips/Qt/worktrees), none of which the diff touches.
- `code-check-r.md` (full text): read in full "Read-back shape must match write-back shape",
  "A `data-raw/` script must load the source tree", "`$` on a list partial-matches", "A value
  compared as `::text`", "`paste()` with a zero-length argument", "`strsplit()` drops a
  trailing empty field", "`[[` on a named ATOMIC vector", "`match()` treats NA as a matchable
  VALUE", "Postgres row order is never fixed", "`sprintf("%g", x)` writes `Inf`", "An
  `information_schema` lookup", "Rscript reads a script as it runs", "`expect_gt()` and friends
  take no `info`", "`c()` dispatches on its first argument", "`ifelse()` with an all-NA test".
  Not read: the other ~100 sections (xml2, glue, readr, arrow/duckdb, ggplot2, terra, pak,
  roxygen, knitr, cli, climr, earthdatalogin, …), none of which the diff uses.
- `code-check-spatial.md` (full text): 0 sections read. The diff has no terra, sf, bcdata or
  GDAL code.

## What was checked, beyond round 1

Round 1's walk (order through exact mode, `${WSGS_FLAG[@]+…}`, the two-header `case`, the
`DUP` pipeline, `BUCKET_MODE` scope, the verifier's `%I`/`$1` format strings, 6f/6g isolating
their arm) was re-derived independently and holds. The items the brief named as what round 1
would have missed:

- **`--buckets-exact` × `--recompute-only`**: refused at the arg gate (line 261) before
  anything runs. × `--preflight-only`: the banner prints `buckets: exact`, the script exits at
  line 1197 before `BUCKET_MODE` is set and before any `run_wsgs_write`, so nothing reads the
  unset variable. × the EXIT trap: `on_exit` runs `burn_cyphers` and `redact_log_addresses`
  only; neither reads `BUCKET_MODE` or writes the TSV. × the second `run_wsgs_write` (line
  1467): same shell, `BUCKET_MODE` assigned at 1207/1210 and never reassigned, so both rows
  carry the same mode, as the lib comment claims.
- **Verifier superseded logic, the awkward states**: two open rows and one later finished row
  → both superseded, NOTICE names both, PASS. An open row *newer* than the group's finished row
  → `NOT EXISTS` holds, EXCEPTION. An open row whose only finished sibling is under another
  `run_uid` (a hand re-run without `LNK_RUN_UID`) → EXCEPTION, and the message's remedy ("under
  this run_uid") is the right one. An open row with `date_start` NULL cannot occur
  (`timestamptz NOT NULL`). The definition agrees with `run_coverage`'s "newest log row must be
  finished" rule in `study_area_finish.sh`, so the driver and the verifier cannot disagree on
  which of these states is incomplete. The open row still passes through every per-row
  provenance arm (link_sha, fwapg_sha, fresh_sha, bcfishobs_sha, dirty flags, pin, section 2b
  agreement); a failed attempt's row is written at run open with those values, and the real
  OKAN row passed them (`run_verify.log`), so a superseded row cannot slip a provenance defect
  through, and a failed attempt from a host on a different `fresh_sha` would still raise.
- **`pack()` with NA / zero**: `weight_of()` replaces NA with the median before `pack()` sees
  a weight, and the median is finite because the minutes path stops on zero rows and the
  segments path cannot return none. `host_speeds` is validated for length, NA and `<= 0`
  before use. A zero weight orders last and lands on host 1 by `which.min`'s first-tie rule;
  nothing divides by a weight. A host with no atoms (more hosts than atoms) prints an empty
  `--focal=`, which `study_area_wsgs.R` refuses at usage and the driver's `set -e` aborts on,
  the same as component mode has always done.
- **Files the diff both writes and reads**: `<TS>_run_wsgs.tsv` (writer adds a column, the
  only reader keys on `$1 $3 $4` and accepts both headers; no other reader in `R/`, `data-raw/`
  or `tests/`); the negative test's `VERIFY_LOG` (written by `run_verify`, replayed by
  `show_verify`). `research/study_areas.md` is written and never read.
- **Doc claims executed against the code**: every behavioural claim in CLAUDE.md, NEWS.md,
  RUNBOOK §8d, the `study_area_buckets.R` / `study_area_run.sh` / `study_area_wsgs.R` headers
  and `research/study_area_run.md` about the driver (`--exact` keeps order and applies only
  the species filter; overlap fatal in exact mode; banner text; `bucket_mode` column; both
  legs run `LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0`; `--write` refused under group
  atoms; drainage-closed assertion skipped, within-host order assertion kept; makespan under
  both atoms printed; `--host-speeds` default equal; the three-state `date_end`/`notes` signal
  in `.lnk_log_run_fail()`; `habitat_validate.R`'s default `--out`) resolves to a line that
  makes it true. Every evidence path the docs name under `data-raw/logs/provincial_361/`
  (`README.md`, `split_verdict.md`, `buckets_group4.md`, `buckets_group5.md`,
  `verify_negative.log` with 6f/6g ticks) exists. One numeric claim does not survive its own
  evidence; it is the single finding below.

## Findings

- **[fragile]** `research/study_area_run.md:224` — "one link SHA in `log` (241 rows) and
  `log_recompute` (241)". The run's own verifier output committed beside it
  (`data-raw/logs/provincial_361/run_verify.log`, section 1) counts 57 + 68 + 42 + 75 = **242**
  `log` rows for `run_uid 20261023_074321-24d85e8c`: 241 groups plus OKAN's superseded failed
  attempt, which is the very row the verifier change in this branch exists to tolerate. The
  "one link SHA" half holds (section 2 shows one `link_sha`); the row count is the figure from
  the 2026-10-17 paragraph carried forward. Harmless to the code, but it is a published number
  that the artifact it cites contradicts, in a document whose header convention is "never a
  number without its producer" — change to `241 groups (242 rows: OKAN twice)` or drop the
  parenthetical.

Nothing else: no bug, security issue or data-loss path in the branch diff.

## Observations that are not findings

Recorded so round 3 need not re-derive them; none changes behaviour today.

- `run_wsgs_write` reads `BUCKET_MODE` with a `closure` default (so the test harness can call
  it bare). If a future edit moved the first call above line 1207 of the driver, an exact run
  would record `closure` with no error. Nothing consumes the column yet, so today a wrong
  value is inert; worth knowing when something starts reading it.
- In exact mode the driver asserts nothing about the *union* of the hosts' lists being
  drainage-closed. Used as intended (lists from `study_area_buckets.R --atom=group`) the union
  is a closure by construction; a hand-written list that omits a downstream group fails at the
  recompute's error-mode guard on a schema that has never held that group, and on a schema
  that holds an earlier build of it reads that build's barriers, exactly as `--recompute-only
  --wsgs=` does and as CLAUDE.md now warns for that flag. Operator's instrument by design.
- A group repeated *within* one exact list is also caught by the `sort | uniq -d` overlap check
  (strict `lnk_wsg_resolve` keeps duplicates), but the FATAL text says "a group on two hosts".
  Fail-safe, message slightly off.
- `study_area_verify.sql` section 1's `n_wsg` column is now a row count, not a group count,
  for a host that carries a superseded attempt (m1 shows 75 for 74 groups). Display only; the
  DO block counts `DISTINCT watershed_group_code`.
