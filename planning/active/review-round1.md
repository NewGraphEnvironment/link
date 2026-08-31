# Review round 1 — `main..HEAD` (#246 pre-flight gates)

Reviewed in full: `data-raw/study_area_run.sh`, `data-raw/cypher_prep.sh`,
`data-raw/study_area_buckets.R`, `data-raw/host_stamp.R`,
`data-raw/host_vintage.R`, `data-raw/wsgs_run_pipeline.sh`,
`R/lnk_preflight_{fresh,vintage,stamp,parity}.R`, the three new test files,
`DESCRIPTION`, `NAMESPACE`.

All three new test files pass (`testthat::test_local(filter="preflight")`,
85 assertions, 0 failures).

---

## Findings

### 1. [bug] `data-raw/study_area_run.sh:449` — `judge_stamps` silently disables the parity gate's `forbid_na` property

`judge_stamps()` reads the collected stamps with

```r
s <- utils::read.delim(a[1], header = FALSE, colClasses = "character",
                       col.names = strsplit(a[2], ",")[[1]])
```

`read.delim` applies `na.strings = "NA"` **even for `colClasses = "character"`**,
so the literal `"NA"` sentinel that `lnk_preflight_stamp()` deliberately emits
(`R/lnk_preflight_stamp.R:43-46`, documented at :22-23 as *"Unresolvable facts
are the literal string `"NA"`, never empty"*) is converted back to R's `NA`
before `lnk_preflight_parity()` ever sees it.

Both of the function's stated properties then fail toward pass:

* `stamps[[k]] %in% c("NA", "")` (`R/lnk_preflight_parity.R:91`) is `FALSE` for
  `NA`, so the "Nothing is unresolved" check can never fire from the shell.
* `which(stamps[[k]] != ref[[k]])` (`:112`) — `"e6e1eb0" != NA` is `NA`, which
  `which()` drops, so an NA-vs-value drift is not even reported as a mismatch.

**Failure scenario (reproduced).** Dispatcher resolves `FWAPG_GIT_SHA`; a cypher
does not (ssh env stripped, `AcceptEnv`/`PermitUserEnvironment` config, or
`.lnk_fwapg_sha()` returning NA) and stamps `fwapg_sha=NA`. Same two-row TSV,
same judge:

```
read.delim(defaults)              -> ok = TRUE   | problems: <none>
read.delim(na.strings=character(0)) -> ok = FALSE | fwapg_sha unresolved on: cy-job1
                                                    1 field mismatch(es) vs m1
```

So the run proceeds and every cypher row lands with `fwapg_sha = NULL` — the
exact provenance hole #246 exists to close — while the gate prints
`✓ host parity clean`. Same path swallows `repo_sha=NA` (non-git host),
`fresh_version=NA` (fresh not installed) and `repo_dirty=NA`.

**Why no test catches it:** every case in `tests/testthat/test-lnk_preflight_parity.R`
constructs the data frame in R (`row()` helper, lines 1-8) and never goes through
the TSV round-trip that `judge_stamps` performs — including
`"a stamp is judgeable by the parity function it feeds"` (:108), which is the
test written to guard this seam. The fixture set is structurally incapable of
reaching the defect.

**Fix:** `na.strings = character(0)` in `judge_stamps`. Worth also asserting the
column count — `read.delim` defaults to `fill = TRUE`, so a truncated ssh
response is padded rather than rejected (it happens to fail today because the
pad for a character column is `""`, which *is* in the `forbid_na` set, but that
is luck rather than design). And add one test that writes a TSV and reads it
back the way the shell does.

---

### 2. [fragile] `data-raw/study_area_run.sh:171-176` — the "second layer" schema-collision guard is unreachable

```sh
if [ -n "$SCHEMA" ] && [ "$CONFIG" != "bcfishpass" ] && [ "$SCHEMA" = "$BCFP_SCHEMA" ]; then
```

Line 131 already exits when `CONFIG != bcfishpass && -z SCHEMA_OVERRIDE`, and
this block is inside the `else` of `if [ -n "$SCHEMA_OVERRIDE" ]` (:162). So by
the time control reaches :172, `SCHEMA_OVERRIDE` is empty, which means `CONFIG`
is necessarily `bcfishpass`, which means `[ "$CONFIG" != "bcfishpass" ]` is
always false. The guard cannot go red under any input.

The comment claims it *"catches a future third config that happens to
collide"* — it cannot: such a config without `--schema=` is rejected at :131,
and with `--schema=` this branch is never entered. The extra `resolve_schema
bcfishpass` R invocation at :171 is pure cost.

To actually provide the second layer, compare the **resolved** `$SCHEMA`
(override included) against `bcfishpass`'s resolved schema for any
`CONFIG != bcfishpass`, outside the `else`.

---

### 3. [fragile] `data-raw/study_area_run.sh:29 / 109-123 / 278 / 359` — the documented bare `--preflight-only` skips every gate it was written for

The header advertises

```
#   bash data-raw/study_area_run.sh --preflight-only    # gates only, no spend
```

and describes `preflight_local()` as covering *"BOTH DO credentials forced
through a real API call"*. With no `--cy-workspaces`, `N_CY=0`, and the
branch-pushed/`@{upstream}` check (:278), both DigitalOcean credential probes
(:359-397) and the tofu s3-backend probe (:403) are all inside
`if [ "$N_CY" -gt 0 ]`. None run, and nothing prints to say they were skipped.

Confirmed by running the documented invocation on this checkout — output shows
only the fresh-symbol, fwapg-sha and vintage gates; no `origin/... is at HEAD`,
no doctl, no tofu lines. Had vintage passed, it would have printed
`✓ pre-flight clean` having never touched a credential.

That is the opposite of the stated motivation (:370-373: *"both were minted
2026-05-18 and both expired 2026-08-30"*). An operator who dry-runs the gates,
gets a clean bill, then launches for real still discovers the dead token
mid-spin.

Either have `--preflight-only` imply the cypher legs, or print an explicit
`⊘ skipped (no --cy-workspaces)` line per skipped gate so silence is never read
as a pass.

---

### 4. [fragile] `data-raw/cypher_prep.sh:158-159` — `|| true` on the `.Renviron` rewrite can wipe the file it says it is preserving

```sh
grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp" || true
mv "$RENV.tmp" "$RENV"
```

The comment directly above states the intent: *"never rewrite wholesale, since
the image may keep unrelated settings here."* But `|| true` collapses grep's
exit 1 (*no lines survived* — legitimate) with exit ≥2 (*read error*, unreadable
file, `-v` on a file grep decides is binary). On the error path the redirect has
already created an empty `$RENV.tmp`, and the unconditional `mv` installs it as
`~/.Renviron` — destroying every unrelated setting, permanently, with no
message. Classic "empty result is not a pass" plus "`cmd > file` truncates
before `cmd` runs".

Branch on the status instead:

```sh
rc=0; grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp" || rc=$?
[ "$rc" -le 1 ] || { rm -f "$RENV.tmp"; echo "FATAL: could not read $RENV" >&2; exit 1; }
mv "$RENV.tmp" "$RENV"
```

---

### 5. [fragile] `data-raw/wsgs_run_pipeline.sh:263 / 272` — new sentinel + new prep script, but this caller still pins the cypher to `origin/main`

The sentinel changed to `grep -qx "=== READY"`, which only the new
`cypher_prep.sh` emits. This caller scps the **dispatcher's working-copy** prep
script (:263) but runs it with no `CYPHER_PREP_BRANCH` (:264), so the cypher
does `git reset --hard origin/main` and `pak::local_install`s **main's** link.
The new prep script then calls `link::lnk_preflight_fresh()` (`cypher_prep.sh:173`),
which does not exist in main's link until this branch merges — so every cypher
FATALs at prep for anyone running `wsgs_run_pipeline.sh` from a feature branch.

`study_area_run.sh:580` avoids this by passing `CYPHER_PREP_BRANCH='$LINK_BRANCH'`.
Fail-loud rather than silent, and it resolves on merge, but it is a new coupling
introduced by this diff and the same one-word fix applies.

---

### 6. [security, low] `data-raw/study_area_run.sh:389` — `LNK_PREFLIGHT_DO_URL` redirects a live bearer token to an arbitrary host

```sh
code=$(printf 'header = "Authorization: Bearer %s"\n' "$tok" \
  | curl -sS --config - --max-time 20 -o /dev/null -w '%{http_code}' \
         "${LNK_PREFLIGHT_DO_URL:-https://api.digitalocean.com/v2/account}" ...)
```

Keeping the token out of `argv` via `--config -` is right. But the URL it is
sent to is an unvalidated env-var override, so anything that can set
`LNK_PREFLIGHT_DO_URL` in the dispatcher's environment exfiltrates the
DigitalOcean PAT on the next pre-flight, and the only visible symptom is a
non-200 status. Cheap hardening: require the override to match
`^https://` plus an allowlisted host, or gate it behind the same
`LNK_PREFLIGHT_DO_TOKEN` test seam so a real credential is never sent to an
overridden URL.

---

## Checked and found clean (no action)

* **BSD grep alternation** in `check_bucket_complete` (`study_area_run.sh:662`).
  `\(done\|SKIP\)` was tested against `/usr/bin/grep` (BSD grep 2.6.0-FreeBSD,
  "GNU compatible") on this machine: 2/2 matches, and the pattern matches both
  real `wsg_run_one.R` outputs (`... done in %.1f min`, `... SKIP — no modeled
  species`, R/`wsg_run_one.R:56,88`). Scripts resolve `grep` to `/usr/bin/grep`
  (the agent shell's `grep` is a ugrep wrapper — not what the script sees).
* **`set -e` and the `{ ...; } >> "$RENV"` group** in `cypher_prep.sh:160-164`.
  A trailing `[ -n "$FRESH_SHA" ] && printf ...` with an empty `FRESH_SHA`
  does **not** abort the script — the failing command precedes `&&`, so errexit
  is exempt. Verified empirically.
* **`psql` exit status** for the coverage post-condition
  (`study_area_run.sh:731-746`). A bad-schema query returns 1 locally, so the
  `else` FATAL branch is reachable and the empty-string result is only trusted
  on the success branch, as the comment claims.
* **`local rc=$?`** in `burn_cyphers` — `$?` is expanded before `local` runs, so
  this is not the `local x=$(cmd)` status-swallowing trap.
* **`fresh_out=$(...) && fresh_rc=0 || fresh_rc=$?`** (:265) correctly captures
  the R exit status; the 0/1/other tri-state is sound.
* **Empty-array expansion under `set -u`** — the script runs under homebrew
  bash 5.3 (it already requires `declare -A`), and every bare `"${CY_WS_ARR[@]}"`
  is either gated on `N_CY -gt 0` or reached only when `CYPHERS_UP=1`.
* **`.lnk_vintage_primitives()`** returns exactly 4 tables, matching the length-4
  age vector in the `lnk_preflight_vintage` `@examples`.
* **`DESCRIPTION`** — `fresh (>= 0.33.0)` in Imports is consistent with
  `Remotes: NewGraphEnvironment/fresh@v0.33.0`; `.lnk_fresh_floor()` parses it
  correctly and the floor test asserts it.
* **`study_area_buckets.R`** union-find (path halving, `<<-` into the global
  `parent`), the `new.env()` membership index (`e[["missing"]]` returns `NULL`,
  not an error), the LPT pack and the host relabel-by-descending-load all check
  out; the disjointness assertion at :157-162 is a real invariant that can fire.
* `on.exit()` at script top level (`host_vintage.R:69`, `study_area_buckets.R:93,253`)
  is a documented no-op, but the targets are a DB connection and a file
  connection that R closes and flushes at session end — no practical impact.
