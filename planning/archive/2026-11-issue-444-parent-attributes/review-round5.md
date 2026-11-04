# Code-check round 5, #444 (branch 444-parent-attributes-on-the-full-network, HEAD 8a1c93ac)

## Checklist read

- code-check.md: the prose of all 14 H3 under `## Mechanisms` (table rows skipped), in particular "A guard that fails toward pass" (where the guard sits; what the guard reads), "A proxy is not the property", "A guard's scope, escape hatches, and remedies", "Restore the bug and prove the guard fires". Index lines only for the rest.
- code-check-r.md, in full: "`load_all()` runs every `.R` file at the top of a package's `data/` as a data script", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "A `data-raw/` script must load the source tree, not the installed package". Index lines only for the others.
- code-check-shell.md, in full: "`git check-ignore -v` prints the matching pattern, and its exit status is not a per-file verdict", "Six git plumbing calls whose default answers a different question". Index only for the rest.
- code-check-spatial.md: index only (the join is unchanged since round 3).

Method. Lists built by grep at HEAD over `data-raw/streams_parent_build.R`, `data-raw/streams_parent.R`, `R/lnk_streams_parent.R` and the `pretest_*` functions they call (every `stop(`, `return(`, `write.table`, `dir.create`, `sys.source`, `load_all`, `file.path` read, `system2`, `tempfile`, SQL DDL/DML). Probes, none touching the repo or `fresh_default*` beyond reads: a `git clone --no-hardlinks` of the branch into the scratchpad (deleted after); `--verify --wsgs=BULK --out=<scratch>` from the clone (rc 0, BULK current); an untracked `data/x.R` in the clone (refused in `--verify`: fixes 2 and 3 hold); an ignored `R/zz_ign.R` (via `.git/info/exclude`) under the default git config (refused) and under `status.showUntrackedFiles=no` (passed, the file's code ran: finding 2); a scratch schema `zz_r5_` + 57 `a` (63 chars) with `lnk_streams_parent(conn, "TEST", <base>x, <base>y)` (self-join written: finding 1); scratch schema dropped, `zz_r5%` count 0 after.

## Enumeration

### Refusals (41: driver 15, guard 15, function 11; plus 9 in `pretest_*`)

| place (HEAD) | stands in for | holds |
|---|---|---|
| build l.38 unknown argument | only documented flags | y |
| build l.42 both schemas given | two schemas named | y |
| build l.46 schema regex lower-case | SQL-safe, case-stable name | y (length unbounded, but the guard's tokens keep a truncated pair from self-pairing: a cut-min and a cut-full-* log cannot be one table) |
| build l.53 `--out` given | operator's place | y |
| build l.58 `--out` holds this mode's file | no record overwritten | y |
| build l.79 `--wsgs` codes | real groups | y |
| build l.83 group on both sides | asked groups pair | y |
| build l.99 clean tree (loads + `--ignored` R/ data/ src/), now ahead of `--verify` | the code loaded is HEAD's | **n**: the `--ignored` call does not pin `--untracked-files`, so `status.showUntrackedFiles=no` hides ignored files (finding 2). Untracked `data/x.R` refused in `--verify` (fixes 2, 3 hold) |
| build l.106 srcrefs | reach readable | y |
| build l.110 reach holds the pipeline | walk saw the path | y |
| build l.135 pair refused | judged pair | y |
| build l.179 a group failed | every group built | y |
| verify l.194 no table | something to verify | y |
| verify l.248 no groups | something verified | y |
| verify l.253 stale | rows describe newest closed builds | y |
| guard l.57 no rows | a pair | y |
| guard l.62 one side only | each group paired | y |
| guard l.64 duplicate | once per side | y |
| guard l.67 open | finished builds | y |
| guard l.69 dirty / NA | clean builds | y |
| guard l.70 NA fresh_sha | fresh known | y |
| guard l.77 one value per side (7 cols) | one code/config per network | y |
| guard l.84 shared fresh_sha + 3 tokens | same engine and access | y |
| guard l.89 `cut-min` | minimal side | y |
| guard l.93 `cut-full-*` | full side (and never the same table) | y |
| guard l.102 species | same species | y |
| guard l.111 no reach | `none` judgeable (ahead of `pretest_none_reached`'s NULL return) | y |
| guard l.118 fresh pin | same fresh | y |
| guard l.122 unmapped | every changed file judged | y |
| guard l.127 moved | no modelling-path change | y |
| fn l.64 no build | a build exists | y |
| fn l.67 newest open | finished build | y |
| fn l.140 wsg | one code | y |
| fn l.146 schema regex lower-case (fix 1) | Postgres resolves the string as given | **n**: case closed; length not bounded, and Postgres truncates identifiers to 63 bytes (finding 1) |
| fn l.150 `identical(schema, schema_minimal)` | two different schemas | **n** (same cause, finding 1) |
| fn l.154 numeric args | sane tolerances | y |
| fn l.164 judged run_id | joined build = judged build | y |
| fn l.215 no segments | both hold the group | y |
| fn l.224 coverage | no gap or overlap | y |
| fn l.242 cut superset | one minimal parent within `tol_m` | y |
| fn l.280 rows = full segments, in a transaction | one row each; refusal keeps old rows | y |
| pretest l.57/62/66/73 map columns, repo, blanks, regex | a usable map | y |
| pretest l.81/83 config cycle, missing bundle | a readable chain | y |
| pretest l.100 git non-zero | no empty answer from a failed git | y |
| pretest l.130 one fresh pin | one pin per DESCRIPTION | y |
| pretest l.471 entries | wsg_run_one.R still calls the entries | y |

### Code paths a run reads (13) against the clean-tree check

| path | how read | checked | holds |
|---|---|---|---|
| `R/*.R`, `R/sysdata.rda` | `load_all()` | `R/` tracked/untracked; ignored only under default config | y default config; **n** under `status.showUntrackedFiles=no` (finding 2, proven) |
| `DESCRIPTION` | `load_all()`; `git show` at shas | y | y |
| `NAMESPACE` | `load_all()` | y | y |
| `tests/testthat/helper*.R` | not read (`helpers = FALSE`) | n/a | y |
| `data/*` | `load_all()` → `load_data()` | `data/` (fix 2; proven refused) | y (ignored: as R/, finding 2) |
| `src/` | `load_all(compile = NA)` | `src/` (fix 2) | y (ignored: as R/, finding 2) |
| `inst/` (configs via `pretest_config_chain`) | `read_yaml` of tracked bundles | `inst/` | y |
| `data-raw/pretest.R` | `sys.source` | y | y |
| `data-raw/streams_parent.R` | `sys.source` | y | y |
| `data-raw/streams_parent_build.R` | Rscript | y | y |
| `data-raw/wsg_run_one.R` | parse | y | y |
| `data-raw/pretest_inputs.csv` | `read.csv` | y | y |
| git objects (DESCRIPTION at shas, diff) | `git show` / `git diff` | not the tree | y |

Noted, not reported: R's startup `.Rprofile` / `.Renviron` in the working directory run before the script and are not on the list; they are the R environment, like the installed DBI, codetools and pkgload, which no row covers either. The check itself is run by code from a file it checks (`pretest_git` from `pretest.R`, and the driver checks itself); that is inherent to a self-checking script.

### Paths a run writes (8)

| path | refused / safe | holds |
|---|---|---|
| `dir.create(out)` | creates only; a refused run leaves it empty and re-usable | y |
| `<out>/pair.tsv` | refused if present; now written only after the clean check | y |
| `<out>/build.tsv` | refused if present | y |
| `<out>/verify.tsv` | refused if present; not written when the clean check refuses (proven) | y |
| `<schema>.streams_parent` DDL, index, per-group DELETE+INSERT in a transaction | driver: guarded by the pair and the run-id check | y via the driver; **n** on a direct call with names over 63 bytes (finding 1, proven) |
| `pg_temp.lnk_sp_*` | dropped by `on.exit` in the function frame | y |
| `pretest_git` stderr tempfile | `on.exit(unlink)` | y |
| `prototype_check.csv` | separate script, by design | y |

Totals: 41 + 9 refusals, 3 rows n (two of them one cause); 13 read paths, 1 n (with its ignored variants in data/ and src/); 8 written paths, 1 n.

## Findings

- **[severity: fragile]** R/lnk_streams_parent.R:142-151. Fix 1 closes case folding but not identifier truncation, the same mechanism one axis over: the regex `^[a-z_][a-z0-9_]*$` has no length bound, and Postgres truncates an unquoted identifier to 63 bytes (with only a NOTICE), so two names that differ after byte 63 pass `identical()` as different and resolve to one schema. Proven on a scratch schema (`zz_r5_` + 57 `a`, dropped): `lnk_streams_parent(conn, "TEST", <base>x, <base>y)` exits clean and writes the self-join (`id_segment_minimal = id_segment`, `run_id_minimal = run_id_full = 'f-run'`, `schema_minimal` stored untruncated as `<base>y`), the outcome round 4's finding 1 described for "x"/"X". The comment on l.143-144 says the regex is what makes the different-schemas test sound. Not reachable through the driver (the guard requires cut-min on one log and cut-full-* on the other, which one table cannot hold). Remedy: bound the length in the shared rule, `^[a-z_][a-z0-9_]{0,62}$`, in the function and the driver (l.46), or compare the resolved names (`SELECT nspname FROM pg_namespace WHERE oid = to_regnamespace(...)`).
  - **Rule:** code-check-r.md "An `information_schema` lookup by the literal table name misses what Postgres resolves" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/streams_parent_build.R:96. The ignored-file check `git status --porcelain --ignored -- R/ data/ src/` leaves `--untracked-files` to git config, while the call above it (l.94) pins `--untracked-files=all`. Under `status.showUntrackedFiles=no` (a common setting in large checkouts) `--ignored` lists nothing, so an ignored `R/*.R`, `data/*.R` or `src/` file that `load_all()` reads passes. Proven in a clone of the branch: an `R/zz_ign.R` excluded via `.git/info/exclude` is refused under the default config and, with `status.showUntrackedFiles=no`, runs ("UNCHECKED CODE LOADED") and `--verify` reports "all 1 group(s) current", rc 0; the build mode takes the same path. Not set on this machine (global and repo config unset); unknown on the dispatcher. Remedy: pass `--untracked-files=normal` (or `all`) on the l.96 call; checked: with the config set it then prints `!! R/.Renviron`.
  - **Rule:** code-check-shell.md "Six git plumbing calls whose default answers a different question" (pass the flag that names the question) ; code-check.md "A guard that fails toward pass"

## Triage and the closing enumeration (main session, 2026-11-03)

Both findings real and fixed in the next commit: the schema regex is `^[a-z_][a-z0-9_]{0,62}$` in the function and the driver; the `--ignored` status call passes `--untracked-files=all`.

Enumerated after the fix (grep over `R/lnk_streams_parent.R`, `data-raw/streams_parent_build.R`, `data-raw/streams_parent.R`):
- Schema-name checks: 2 (function l.146, driver l.47). Both lower case, at most 63 bytes.
- `git status` calls: 2 (driver l.95, l.98). Both pass `--untracked-files` explicitly, so `status.showUntrackedFiles` cannot hide a file.
- Schema-name comparisons: 2 (function l.150; driver `verify_groups()` l.240). Both compare names that passed the checks above.
- Every other row of round 4's tables re-walked by round 5 holds.

Noted, not fixed here: `pretest_changed_link()` (the gate's own function, reused) runs `git diff --name-only`, which under rename detection lists only a renamed file's new path. That is the gate's limit and editing `pretest.R` voids every gate record; it is reported, not changed.
