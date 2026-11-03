# Code-check round 3, #444 (branch 444-parent-attributes-on-the-full-network, HEAD 9168ddd0)

## Checklist read

- code-check.md: the prose of all 14 H3 under `## Mechanisms` (table rows skipped). Not read in full: the 23 other H3 (index lines only).
- code-check-r.md: read "Postgres row order is never fixed unless the query fixes it…", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL…", "A value compared as `::text` in SQL…", "`$` on a list partial-matches…", "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree, not the installed package", "`match()` treats NA as a matchable VALUE…", "`tryCatch()` nests its handlers…", "`nzchar(NA)` is TRUE…", "Rscript reads a script as it runs…". 106 not read.
- code-check-spatial.md: read "FWA `upstream_route_measure` misses the next segment's start". 93 not read.
- code-check-shell.md: none read in full (no shell in the diff; git is called through `pretest_git()`/`system2()`, reviewed in round 1). 70 not read.

Probes run (read-only): log column types in both schemas (all `run_id`/`link_sha` text); `length_metre` against `upstream - downstream` on all 5,546,370 `fresh_default.streams` rows (0 off by more than 1 mm); a parent and its full segment share `linear_feature_id` on BULK, SETN, LFRA (149,143 of 149,143); `pkgload::load_all()` 1.5.0 defaults (`helpers = export_all = TRUE`; `populate_pkg_env()` sources `tests/testthat/helper*.R` into `package:link`); the driver run `--verify --wsgs=BULK --out=<scratch dir holding a sentinel verify.tsv>`: exit 0, the sentinel overwritten with no refusal.

## Mechanism

Each earlier finding is one stand-in that was assumed to coincide with a property computed somewhere else, with nothing comparing the two: a hand-written list of paths standing in for "what the run writes" and "what `load_all()` reads" (R1, R2 untracked), a default path standing in for "a scratch place" (R2 `--out`), an empty `--wsgs` standing in for "some groups" (R1), and a sentence standing in for a measured count (R2 docs). Each fix narrowed its stand-in but kept it a stand-in. Excluding `data-raw/logs` from the clean list made the write list able to reach committed files, so the next fix removed the default, and that moved "never overwrites a record" onto the operator's choice of path, which the committed README then chooses for them (finding 1). The clean list was widened to untracked files but is still a list beside `load_all()`, which reads one more path than it names (finding 2). And the same shape appears between the two halves of the guard: the pair the driver judges and the pair the function joins are two separate reads of "the newest build", which agree only while nothing re-models (finding 3).

| place | stands in for | holds now? |
|---|---|---|
| driver: unknown-argument refusal (l.36-38) | only the documented flags | yes |
| driver: `--schema`/`--schema-minimal` required, `^[a-z_][a-z0-9_]*$` (l.39-47) | two SQL-safe schema names | yes (stricter than the function's) |
| driver: `--out` required (l.52-54) | "a later run never overwrites an earlier record" (RUNBOOK l.2078) | **no**: an existing directory is accepted, `pair.tsv`/`verify.tsv` are overwritten and `build.tsv` deleted up front; the committed README tells the reader to pass the committed evidence dir (finding 1) |
| driver: `--wsgs` empty or a bad code refuses (l.69-73) | at least one real group asked for | yes (R1) |
| driver: `--wsgs` group not built on both sides refuses (l.74-77) | every asked group can be paired | yes |
| verify: no `streams_parent` table, or zero groups, exits 1 (l.178-181, 232-235) | something was verified | yes |
| verify: per-group staleness (run ids, schema, open newest, segments without rows, rows without segments, length) | rows describe the newest builds | yes for a re-model after the build; not for one during it (finding 3) |
| driver: clean tree over `loads` (l.84-91) | the code loaded and judging is HEAD's | **no, by one path**: `load_all()` also sources `tests/testthat/helper*.R` into `package:link`, where the driver's unqualified `lnk_streams_parent()`/`lnk_db_conn()` resolve, and `git status` lists no ignored file under `R/` (finding 2; latent, no helper exists) |
| driver: srcrefs present (l.93-95) | the reach can be read | yes |
| driver: reach includes `lnk_pipeline_run.R`, `lnk_pipeline_prepare.R` (l.97-100) | the walk saw the modelling path | yes, as a floor (the gate's own) |
| rows: one side only / duplicate group | each group paired once | yes |
| rows: open newest row | finished builds | yes (same rule as the function) |
| rows: `link_dirty`/`fresh_dirty` not FALSE | clean builds | yes (NA refuses) |
| rows: NA `fresh_sha` | fresh known | yes |
| rows: one value per side of link_sha, fresh_sha, config_name, config_hash, acc/flow/grad tokens | one code and config per network | yes |
| rows: fresh_sha and acc/flow/grad tokens equal across sides | the same engine and access rules | yes |
| rows: `cut-min` against `cut-full-*` | the right network on each side | yes (NA token refuses) |
| rows: species per group equal | same species cut | yes (both-NA treated equal, one-NA refuses) |
| code: fresh pin equal at both shas; changed files mapped; non-`none` refuses; `none` reached at HEAD refuses | same modelling code between the two `link_sha`s | yes, to the gate's limit (operator-accepted) |
| header claim "one set of inputs" (streams_parent.R l.6-9) | same inputs (FWA, records, primitives) | not checked by the guard; backed by the function's cut test, which refuses any group whose cuts moved, and a parent's gradient depends only on FWA geometry between its ends (shared `linear_feature_id` probed) |
| fn: wsg / schema regex, schemas differ, numeric args non-negative | safe SQL, a real pair | yes (`Inf` passes and then errors in SQL: fails toward abort) |
| fn: newest log row closed on each side | `streams` holds a finished build | yes; but read again here, independent of the driver's judged row (finding 3) |
| fn: no segments on a side | both networks hold the group | yes |
| fn: pieces cover both networks within n/1000 m | no gap or overlap in either network | yes |
| fn: every minimal cut above 0.5 m has a full cut within 1.01 m | every full segment lies in one minimal segment up to `tol_m` | yes (the straddle is bounded by the matched full cut) |
| fn: rows inserted = full segments, in one transaction | every full segment has one row; refusal keeps the old rows | yes |
| fn: `DISTINCT ON (fid) ORDER BY fid, len DESC, mid` | a reproducible pick | yes (ends on a unique key) |

| path a run writes | can overwrite something committed? |
|---|---|
| `dir.create(out)` | creates anywhere, no refusal of an existing dir |
| `<out>/pair.tsv` (build mode, after the clean check) | **yes**, when `--out` names a committed dir (README l.9 instructs `data-raw/logs/streams_parent_444`); `data-raw/logs` is outside `loads`, so nothing refuses |
| `<out>/build.tsv` (deleted at l.138 before any group, then appended) | **yes**, as above, and lost even if every group then fails |
| `<out>/verify.tsv` (verify mode, no clean check) | **yes**, as above; proven on a sentinel |
| `<schema>.streams_parent` (create, index, per-group DELETE+INSERT in a transaction) | DB only; tokens refuse a swapped or bcfishpass pair |
| `pg_temp.lnk_sp_*` | dropped on exit |
| `prototype_check.R` rewrites `prototype_check.csv` beside it | yes, by design (the evidence regenerates itself) |
| tests: `zz_test444_<pid>_{f,m}` schemas | dropped by `withr::defer` |

## Findings

- **[severity: fragile]** data-raw/streams_parent_build.R:52-54, 119, 137-138, 230; data-raw/logs/streams_parent_444/README.md:9; RUNBOOK.md:2078. R2's fix ("`--out` has no default") does not give the property the RUNBOOK states for it, "`--out` has no default, so a later run never overwrites an earlier record". The driver's message asks for "a new directory" but `dir.create(..., showWarnings = FALSE)` accepts an existing one: `pair.tsv` and `verify.tsv` are overwritten and `build.tsv` is deleted before the first group runs. The committed evidence README tells the reader to "give `--out=data-raw/logs/streams_parent_444` to write here again", which overwrites all three committed records, and the clean-tree check cannot refuse it because R1 excluded `data-raw/logs`. RUNBOOK's own sequence (verify, rebuild "the same command without `--verify`", verify again, all into `streams_parent_<run_uid>`) overwrites the first `verify.tsv`, the record of which groups were stale. Proven: `--verify --out=<dir holding a sentinel verify.tsv>` exited 0 and replaced the sentinel. Remedy: refuse an `--out` that already holds the file the mode writes (`pair.tsv`/`build.tsv` for a build, `verify.tsv` for `--verify`), and fix README l.9 and the RUNBOOK sentence (say the verify and the rebuild take separate dirs).
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "A guard that fails toward pass"

- **[severity: fragile]** data-raw/streams_parent_build.R:58, 84-91. R2's clean-tree check lists "the paths load_all() and the guard read, untracked included", but `pkgload::load_all(repo, quiet = TRUE)` takes `helpers = export_all = TRUE`, and pkgload 1.5.0's `populate_pkg_env()` sources `tests/testthat/helper*.R` into `package:link`. That is the environment the driver's unqualified `lnk_streams_parent()` and `lnk_db_conn()` resolve through (`main()` is defined in the global env), and `loads` names no `tests/` path, so a modified or untracked helper redefining either passes the check and runs. `git status --porcelain --untracked-files=all` also lists no ignored file, which `load_all()` sources from `R/` all the same. Latent: no helper file exists and no file under `R/` or `inst/` is ignored today. Remedy: remove the path rather than list it, `pkgload::load_all(repo, helpers = FALSE, quiet = TRUE)`, and refuse an ignored `R/*.R` (`git status --porcelain --ignored -- R/` lines starting `!!`).
  - **Rule:** code-check.md "A proxy is not the property" ; code-check-r.md "A `data-raw/` script must load the source tree, not the installed package"

- **[severity: fragile]** data-raw/streams_parent_build.R:68, 102, 143; R/lnk_streams_parent.R:52-74, 152, 255-256. The pair the driver judges is not the pair the function joins. The driver reads each group's newest log rows once (l.68) and judges them; `lnk_streams_parent()` then reads the newest closed row again at the group's turn and stamps that `run_id` on the rows, and nothing compares the two. A group re-modelled after l.68 (a partial re-model on the dispatcher, possibly at other code or config) is joined against a build the code guard never judged, and `--verify` afterwards reports it current because the rows name the newest build. The function's cut test still keeps the join well defined; what is bypassed is the guard's "same modelling code" judgement. Remedy: after each group, check `res`'s builds (or the inserted `run_id_full`/`run_id_minimal`) against `pair`'s `run_id` for that group and fail the group on a mismatch, or pass the judged run ids to the function and refuse inside its transaction.
  - **Rule:** code-check.md "One fact derived twice" ; code-check.md "A proxy is not the property"
