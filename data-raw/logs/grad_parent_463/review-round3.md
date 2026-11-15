# Code check, round 3 (#463)

Reviewed `git diff 50a5d58e...HEAD` (planning/ excluded) at `06daef04`, including round 2's
fixes. Read only; no database, test, Rscript or repo script was run.

## Checklist read

- **code-check.md**: all 38 index headings read. Prose of all fourteen H3s under
  `## Mechanisms` read, table rows skipped: A guard that fails toward pass; A fixture that
  cannot reach the failure mode; A proxy is not the property; Verification that reads its own
  output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that
  share a harness; Restore the bug and prove the guard fires; A shared working tree, and what
  generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are
  three different things; The probe is broken before the world is (first two paragraphs);
  Written data outlives the fix; Serialization loses meaning silently; One fact derived twice.
  Not read in full: 24 (the 14 under "Rules that stand alone", 6 under "Security", 4 under
  "Spreadsheets and PDFs"; none names a tool or shape this diff uses).
- **code-check-r.md**: all 121 index headings read. Full sections read: "Postgres row order is
  never fixed unless the query fixes it…"; "`$` on a list partial-matches…"; "A database
  driver's value is not a base R type…"; "An `information_schema` lookup by the literal table
  name misses what Postgres resolves" (including its correlated-subquery paragraph);
  "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising…". Not read in full: 116.
- **code-check-shell.md**: all 71 index headings read; run.sh's shapes (`psql` status, `cd ||
  exit`, `$( ) || n=NA`, `set -uo pipefail` without `-e`, a subshell's exit) checked against
  their index lines. No full section read (71).
- **code-check-spatial.md**: all 94 index headings read; "FWA `upstream_route_measure` misses
  the next segment's start" checked against the 1 mm mapping by its index line. No full
  section read (94).

## The mechanism

Rounds 1 and 2 found one shape four times: **a check compares the input it reads with what it
expects, and treats an input that is absent, NULL/NA, or from another moment as agreement.**
R1's apply joined parents on `id_segment` alone (a stale row read as current); R1's
`want_tok()` read a NULL token as "not different" (`isTRUE(!NA)` is FALSE); R1's `git()` read
a failed call as empty output; R2's apply read `schema_full.streams` at apply time while
trusting the judgement made before prepare. Each passes because "no difference found" and "no
value to compare" fall into the same branch. The enumeration below asks that question of
every check in scope.

## Enumeration

"Reads as pass?" is yes only where an absent, NULL/NA, empty or stale input reaches the
check's pass branch.

| # | file:line | check | input it reads | can be stale / missing / NA / empty when read? | reads as pass? |
|---|---|---|---|---|---|
| 1 | lnk_gradient_parent.R:31 | gradient is a named map | `cfg$pipeline[["gradient"]]` | NULL means absent, and the caller maps that to `segment` on purpose (L82) | no |
| 2 | :36 | unknown keys | names(g) | no | no |
| 3 | :42 | source is segment/parent | `g$source` (no prefix siblings) | NULL/NA → `name_ok` FALSE | no (refuses) |
| 4 | :48 | segment takes no other key | names(g) | no | no |
| 5 | :55 | parent needs minimal_config, schema_full | `g[[k]]` | NULL → refuses | no |
| 6 | :59, :66 | names are plain | the values | NA/vector → refuses | no |
| 7 | :98 | config reads parent | g$source | refuses | no |
| 8 | :103 | minimal is `segment` | `lnk_config(minimal_config)` | load error raises | no |
| 9 | :109 | schema_minimal equals minimal's schema | `g$schema_minimal` | NULL skips by design (optional key) | no (intended) |
| 10 | :114 | minimal schema is plain | `m$pipeline$schema` | NULL → refuses | no |
| 11 | :139 | minimal acc/flow spec = this config's | both specs computed now | no | no |
| 12 | :145 | minimal cut matches a live token | vocabulary | unmatched/retired refuses | no |
| 13 | :155 | grad token names one parent cut | vocabulary rows for the token | 0 or 2 rows, NULL token → refuses | no |
| 14 | :181 | a build exists | newest `log` row | 0 rows → refuses | no |
| 15 | :184 | newest build closed | `date_end` | NA → refuses; read at the moment of the call (judge, then apply again) | no |
| 16 | :282 | full ≠ minimal schema | config | no | no |
| 17 | :286 | persist is neither | `cfg$pipeline$schema` after LNK_SCHEMA override (wsg_run_one.R:56) | no | no |
| 18 | :299 | clean trees | link_dirty, fresh_dirty | NA → `%in% FALSE` FALSE → dirty → refuses | no |
| 19 | :301 | fresh sha recorded | fresh_sha | NA refuses; `""` would pass, but the stamp writes NA for unknown | no |
| 20 | :302 | same fresh sha | both fresh_sha | NA excluded at 19 | no |
| 21 | :305 | same species | `array_to_string(species)` | both NULL → `identical(NA, NA)` TRUE; `.lnk_log_run_finish()` always writes species, and this is a consistency check, not the parent property | no (not reachable) |
| 22 | :315 (×8) | tokens | token_* columns, resolved tokens | NULL → NA → not identical → refuses | no |
| 23 | :323 | table exists | `to_regclass` | refuses | no |
| 24 | :325 | rows exist | n_rows | 0 refuses | no |
| 25 | :326-330 | rows joined from the newest runs and minimal schema | `string_agg(DISTINCT …)` | NA only when n_rows is 0 (guarded); two run ids give "a,b" → refuses | no |
| 26 | :331-335 | no segment without a row, no row without a segment, none off length | counts | NULL `length_metre` drops out of `abs(…) > 1e-3`; persist `length_metre` is nullable but always written from geometry | no (not reachable) |
| 27 | :370-377 | newest builds are still the judged ones | log re-read at apply | open/missing raise; named-vector `identical()` | no |
| 28 | :389, :438 | every full segment has a judged, length-matching row | streams_parent ⋈ run ids, `length_metre` | absent row → FALSE → counted; NULL length → `has_parent` NULL → `NOT NULL` uncounted, row still mapped (same not-reachable NULL as 26) | no (not reachable) |
| 29 | :431 | equal segment counts | temp tables | 0 = 0 passes, but the judge refused 0 rows at T0 and 27 proves the same run (rows deleted without a new run is the accepted race) | no |
| 30 | :435-437 | one to one | match counts | NULL measures never match → counted | no |
| 31 | :452 | rows set = n_w | UPDATE count | no | no |
| — | :445 | (no check) gradient set from `gradient_minimal` | streams_parent | `gradient_minimal` is nullable, but copied from the minimal build's generated gradient; proof.R:184 would catch it | no (not reachable) |
| 32 | lnk_pipeline_run.R:185 | judge only for `parent` | `.lnk_gradient_source(cfg)` | no | no |
| 33 | :187 | note joined to caller's notes | `notes` | NA handled | no |
| 34 | :245 | apply when judged | `parent` | set only by 32 | no |
| 35 | lnk_vocabulary.R:131 | grad spec per source | cfg | segment when absent, by design | no |
| 36 | streams_parent_build.R:194 | table exists | state NULL | refuses | no |
| 37 | :221-228 | per-group `why` (no rows, run ids, schema, newest open, counts) | `.lnk_streams_parent_state()` merged by pair groups | same semantics as the SQL it replaced (groups come from `pair`, `rows` only where n_rows > 0); empty `v` refuses | no |
| 38 | proof.R:106 | each schema has a build of each group | `newest()` | no | no |
| 39 | :109 | none open | date_end | no | no |
| 40 | :110 | none dirty | `%in% FALSE` | NA → fails | no |
| 41 | :111-112 | one link_sha, fresh_sha | unique + anyNA | 0 rows → length 0 → fails | no |
| 42 | :119-120 | tokens | `%in%` | NULL fails (R1 fix) | no |
| 43 | **:121-128** | parent notes name the newest pair runs | `log.notes`, newest full/minimal run | **NULL notes → `grepl()` NA → `TRUE && NA` NA → `stop_on(!NA)` → `isTRUE(NA)` FALSE** | **yes** |
| 44 | :130-133 | no R/, inst/, DESCRIPTION change since the builds | git (fails loud) | NA sha already failed at 41 | no |
| 45 | **:160-162** | same segments in control, parent, fresh_default | per-group counts | **a group with 0 rows in all three gives 0 = 0 everywhere, and every later check (gradient, access, habitat) is per group over joined rows, so it is vacuous for that group** | **yes** |
| 46 | :194-196 | parent gradient = gradient_minimal; control = full | joined rows | NULL counted by `IS DISTINCT FROM` / `IS NULL` | no |
| 47 | :214-215 | an access row per segment; no access difference | counts | columns from control only; same species set, so same columns | no |
| 48 | :279 | no unexplained habitat difference | `cls` | a NULL `geom` gives a NULL `cid`, and `JOIN x USING (wsg, cid)` drops that difference; persist `geom` is nullable but always written | no (not reachable) |
| 49 | :318 | near-river pair rows unique | counts | no | no |

## Findings

- **[severity: fragile]** data-raw/logs/grad_parent_463/proof.R:125-127 — the notes check is
  R1's `want_tok()` defect in the next block. `ok <- length(note) == 1L && grepl(...)`: when the
  parent build's `log.notes` is NULL, `note` is `NA`, `grepl(pattern, NA)` is `NA`, `ok` is
  `NA`, and `stop_on(!ok, …)` tests `isTRUE(NA)`, which is FALSE. So a parent build whose log row
  names no parent runs passes the one check that ties it to the newest `fresh_default` and
  `fresh_default_minimal` runs. Today's writer always sets the note for a `grad-parent` build
  (lnk_pipeline_run.R:187, and `.lnk_log_run_fail()` appends with `concat_ws`), so this is
  reachable only through a row the checker should not trust its producer for: an independent
  checker reading the producer's own record. Fix: `ok <- length(note) == 1L &&
  isTRUE(grepl(...))`.
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check.md "Zero-length, empty, and unset are three different things"

- **[severity: fragile]** data-raw/logs/grad_parent_463/proof.R:160-162 — the segments check
  compares counts and never asserts that any exist. A group with no rows in `zz469_control`,
  `fresh_default_parent` and `fresh_default` alike (closed log rows whose persisted rows were
  later dropped or cleared; not observed, and no current writer closes a row without them)
  gives `0 = 0 = 0`. Every later check is per group
  over the joined rows (`grad`, `acc`, `hab` and `cls` have no row for it), so the group passes
  `[proof] every check passed` with nothing compared. run.sh records `n_segments` in status.tsv,
  but proof.R does not read it. Fix: `stop_on(any(seg$n_control == 0), "segments: a group has no
  segments")`.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things" ; code-check.md "A guard that fails toward pass"

Round 2's fixes check out. The apply re-reads the newest builds and refuses unless they are the
judged ones (rows 15 and 27), and joins only length-matching rows from the judged runs (row 28),
so a re-model of either network after the judgement now refuses. proof.R classes every
`accessible` difference `unexplained` ahead of the `changed` arm (L262).

Nothing else in R/lnk_gradient_parent.R, the parent lines of R/lnk_pipeline_run.R and
R/lnk_vocabulary.R, or verify_groups() reads an absent or stale input as a pass, apart from the
NULL `length_metre`, `gradient_minimal` and `geom` paths marked not reachable (rows 26, 28, the
unnumbered row and 48). Those columns are nullable in the persist DDL but always written from
geometry. The dictionary's `consumed_by` lines (R/lnk_config.R:460, 477, 484, 489) were
re-derived and match.
