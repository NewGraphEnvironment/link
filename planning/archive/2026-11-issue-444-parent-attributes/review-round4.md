# Code-check round 4, #444 (branch 444-parent-attributes-on-the-full-network, HEAD 4b09e814)

## Checklist read

- code-check.md: the prose of all 14 H3 under `## Mechanisms` (table rows skipped). Of the rest, index lines only.
- code-check-r.md, in full: "`load_all()` runs every `.R` file at the top of a package's `data/` as a data script", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "Postgres row order is never fixed unless the query fixes it…", "A `data-raw/` script must load the source tree, not the installed package". Index lines only for the others (rounds 1-3 read `on.exit()`, `system2()`, `strsplit()`, `nzchar(NA)`, `match()` NA, `tryCatch()` nesting, Rscript-edit).
- code-check-shell.md, code-check-spatial.md: index only (no shell in the diff; the spatial rule round 3 read still covers the join).

Enumeration built by grep over the three files (every `stop(`, `return(1L)`, `return("…")`, `write.table`, `dir.create`, `sys.source`, `load_all`, `file.path` read, SQL DDL/DML) and over the `pretest_*` functions they call (`read.csv`, `read_yaml`, `file.path`, `system2`). Probes (read-only on `fresh_default*`): pkgload 1.5.0 `load_all()` body (`load_data()` sources `data/*.R`, loads `data/*.rd[a]`; `compile = NA` builds `src/`); `--verify --wsgs=BULK --out=<scratch>` twice (second refused: fix 1 holds); `FRESH_DEFAULT.log` resolves to `fresh_default.log`; a scratch schema `zz_r4case` (dropped) joined against its upper-cased name (finding 1, proven).

## Enumeration

### Refusals (41: driver 15, guard 15, function 11)

| place | stands in for | holds |
|---|---|---|
| build l.38 unknown argument | only documented flags (`--out dir`, `--verify=x` refuse) | y |
| build l.42 both schemas given | two schemas named | y |
| build l.46 schema regex lower-case | SQL-safe, case-stable names | y |
| build l.53 `--out` given | a place chosen by the operator | y |
| build l.58 `--out` holds this mode's file | no run overwrites a record | y (proven: second `--verify` refused) |
| build l.79 `--wsgs` codes | at least one real group (`BULK,` reads as BULK, harmless) | y |
| build l.83 group on both sides | every asked group pairs | y |
| build l.99 clean tree over `loads` + ignored `R/` | the code loaded is HEAD's | **n**: `data/`, `src/` not covered (finding 2); not run in `--verify` (finding 3) |
| build l.104 srcrefs | reach readable | y |
| build l.108 reach holds the pipeline | the walk saw the modelling path | y (floor) |
| build l.133 pair refused | judged pair | y |
| build l.177 a group failed | every group built | y |
| verify l.192 no table | something to verify | y |
| verify l.246 no groups | something verified | y |
| verify l.251 stale | rows describe the newest closed builds | y (one-side groups read "newest build open"/"re-modelled": flagged, label loose) |
| guard l.57 no rows | a pair | y |
| guard l.62 one side only | each group paired | y |
| guard l.64 duplicate | once per side | y |
| guard l.67 open | finished builds | y |
| guard l.69 dirty / NA dirty | clean builds | y |
| guard l.70 NA fresh_sha | fresh known | y |
| guard l.77 one value per side (7 cols) | one code/config per network | y |
| guard l.84 fresh_sha + 3 tokens across sides | same engine and access | y |
| guard l.89 `cut-min` | minimal side | y |
| guard l.93 `cut-full-*` | full side | y |
| guard l.102 species | same species | y |
| guard l.111 no reach | `none` can be judged | y |
| guard l.118 fresh pin | same fresh between shas | y |
| guard l.122 unmapped | every changed file judged | y |
| guard l.127 moved | no modelling-path change | y (chain read at HEAD: covers the bundles both builds read; a bundle dropped from `extends:` at HEAD only matters to one side, so no hole found) |
| fn l.64 no build | a build exists | y |
| fn l.67 newest open | finished build in `streams` | y |
| fn l.140 wsg | one code | y |
| fn l.144 schema regex (allows upper case) | SQL-safe name | y as SQL; see next row |
| fn l.148 `identical(schema, schema_minimal)` | two different schemas | **n**: Postgres folds unquoted case (finding 1) |
| fn l.152 numeric args | sane tolerances (`Inf` aborts in SQL) | y |
| fn l.162 judged run_id (fix 3) | the joined build is the judged one | y (log read and streams snapshot are separate statements; a re-model opens its log row minutes before it persists `streams`, so the window is not reachable) |
| fn l.213 no segments | both networks hold the group | y |
| fn l.222 coverage | no gap or overlap | y |
| fn l.240 cut superset | each full segment in one minimal one, to `tol_m` | y |
| fn l.278 rows = full segments, in a transaction | one row each; refusal keeps old rows | y |

Note, not a finding: `ORDER BY date_start DESC` (guard l.40, fn l.59) does not end on a unique key. A tie on a microsecond `date_start` within one group is not reachable; if it were, the function would refuse (fix 3 compares) and verify could report either row.

### Code paths a run reads (13) against the clean-tree list

| path | how read | in `loads` / checked | holds |
|---|---|---|---|
| `R/*.R`, `R/sysdata.rda` | `load_all()` | `R/` (tracked, untracked, ignored) | y |
| `DESCRIPTION` | `load_all()`; git show at shas | y | y |
| `NAMESPACE` | `load_all()` | y | y |
| `tests/testthat/helper*.R` | not read (`helpers = FALSE`, fix 2) | n/a | y |
| `data/*.R`, `data/*.rd[a]` | `load_all()` → `load_data()` | **no** | **n** (finding 2; no `data/` today) |
| `src/` | `load_all(compile = NA)` → `pkgbuild::compile_dll()` | **no** | **n** (finding 2; no `src/` today) |
| `inst/` (configs via `pretest_config_chain`) | `read_yaml` of named, tracked bundles | `inst/` | y |
| `data-raw/pretest.R` | `sys.source` | y | y |
| `data-raw/streams_parent.R` | `sys.source` | y | y |
| `data-raw/streams_parent_build.R` | Rscript | y | y |
| `data-raw/wsg_run_one.R` | parse (`pretest_entries`) | y | y |
| `data-raw/pretest_inputs.csv` | `read.csv` | y | y |
| git objects (DESCRIPTION at shas, diff between shas) | `git show` / `git diff` | not the tree | y |

All of the above are read in `--verify` too, where no clean check runs (finding 3).

### Paths a run writes (8) against the `--out` refusal

| path | refused / safe | holds |
|---|---|---|
| `dir.create(out)` | creates only | y |
| `<out>/pair.tsv` | refused if present (build) | y |
| `<out>/build.tsv` | refused if present; no longer deleted up front | y |
| `<out>/verify.tsv` | refused if present (verify; proven) | y |
| `<schema>.streams_parent` create, index, per-group DELETE+INSERT in a transaction | DB; driver guarded by the pair and fix 3 | y via the driver; direct call: finding 1 |
| `pg_temp.lnk_sp_*` | dropped by `on.exit` in the function frame | y |
| `pretest_git` stderr tempfile | unlinked by `on.exit` in the function frame | y |
| `prototype_check.csv` (separate script) | by design | y |

## Findings

- **[severity: fragile]** R/lnk_streams_parent.R:143-149. The refusal "schema and schema_minimal must be two different schemas" compares the strings with `identical()`, but the regex on l.143 admits upper case and every SQL statement interpolates the names unquoted, so Postgres folds them: `lnk_streams_parent(conn, "TEST", "x", "X")` joins a schema against itself. Proven on a scratch schema `zz_r4case` (dropped): exit clean, both rows written with `id_segment_minimal = id_segment`, `schema_minimal = 'ZZ_R4CASE'`, `run_id_minimal = run_id_full = 'f-run'`. Every cut matches itself, so no later refusal fires; the function's own guards and the roxygen say the join is refused unless the networks differ by cuts, and a direct caller (the function is exported, and `run_id_*` default to NULL) gets self-parents in the table knowledge reads. Not reachable through the driver (its regex is lower case only), and a later `--verify` against the real minimal schema would flag "another minimal schema". Remedy: use the driver's regex `^[a-z_][a-z0-9_]*$` in the function too (one rule for both), or compare `tolower()`.
  - **Rule:** code-check-r.md "An `information_schema` lookup by the literal table name misses what Postgres resolves" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/streams_parent_build.R:89-97. Round 3's fix removed one unlisted path `load_all()` reads (helpers) and kept `loads` as a list; `load_all()` reads two more that are not on it. pkgload 1.5.0's `load_data()` `sys.source`s every `data/*.R` (and loads `data/*.rd[a]`) and `compile = NA` builds and loads `src/`. Neither directory exists, so an untracked `data/x.R` or `src/` would run inside the build and pass `git status --untracked-files=all -- <loads>`. Latent: same class as round 3's finding 2. Remedy: add `"data/"` and `"src/"` to `loads` and to the `--ignored` call (git status of an absent path is empty, so this costs nothing today), or refuse when either directory exists.
  - **Rule:** code-check-r.md "`load_all()` runs every `.R` file at the top of a package's `data/` as a data script" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/streams_parent_build.R:87 (before l.89-101). `--verify` returns before the clean-tree check, so its verdict comes from code nobody checked is HEAD's: a modified `verify_groups()` or an edited `R/` loaded by `load_all()` can report stale groups current. That verdict is what RUNBOOK l.2074-2079 tells the operator to act on ("if it names a group, rebuild"), and its `verify.tsv` is the committed record ("`--verify` found all 241 groups current"); the header (l.10) says the script runs "from a clean checkout". Remedy: run the `git status` check (l.91-101) before the `if (verify)` return; the srcref and reach checks can stay build-only. Verify writes under `data-raw/logs/`, outside `loads`, so the RUNBOOK's verify, build, verify_after sequence still passes.
  - **Rule:** code-check.md "A guard that fails toward pass" (where the guard sits: "a check behind a dry-run return never runs in the mode people use to be careful")
