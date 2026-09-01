# Round 3 review — link#264

Scope: the round-2 fixes themselves. Five findings, all in the round-2/3 code.
Four of the five are in `scripts/update_hosts.sh`, which round 2 rewrote.

Every claim below was measured (bash probes for the `set -e` behaviour, file
reads for the rest), not reasoned about. Two shell traps flagged in the brief
were checked and are **fine**, recorded at the bottom so they are not re-checked.

---

## Findings

### 1. **[bug]** `scripts/update_hosts.sh:86-99` — a failed `R CMD INSTALL` still writes the pin

```bash
${need_sudo}R CMD INSTALL '${pkg}-${sha}' 2>&1 | tail -3
...
printf '${upkg}_GIT_SHA=%s\n'   '${sha}' >> "$RENV"
printf '${upkg}_GIT_DIRTY=%s\n' 'false'  >> "$RENV"
```

`cmd` opens with `set -e` and **not** `pipefail`. A pipeline's exit status is
the last command's, so `tail` returns 0 whatever `R CMD INSTALL` did. Measured:

```
$ printf 'set -e\nfalse 2>&1 | tail -3\necho REACHED\n' | bash
REACHED           # exit 0
```

So when the install fails — missing system dep, disk full, `sudo` refusing
non-interactively on cypher, a dependency R CMD INSTALL cannot resolve — the
script proceeds to stamp `<PKG>_GIT_SHA=<the new sha>` and `<PKG>_GIT_DIRTY=false`
into the host's `~/.Renviron` for a build that never happened. The host keeps
running the *old* package while asserting the new commit, clean.

This is the exact lie the field was added to prevent, and it is now
self-certifying: `.lnk_pkg_git_state()` takes the env var at tier 1 ahead of
everything, so `preflight_local()`'s new gate prints `✓ fresh_sha … (clean)`,
`lnk_preflight_parity()` agrees, `study_area_verify.sql` sections 1b/2b/DO all
pass, and the run records a `fresh_sha` naming code that was never installed.

Two sub-cases, and the quiet one is the dangerous one:

* package still installed at the old version → the trailing
  `Rscript -e 'cat(packageVersion(...))'` succeeds → **silent success with a
  false pin**;
* package absent entirely → that `Rscript` exits non-zero and the run aborts —
  but `~/.Renviron` has *already* been poisoned by the two `printf`s above it.

Fix: `set -eo pipefail` in `cmd`, or capture the install to a file and check
its status before the `.Renviron` block. Same class as CLAUDE.md
"A wrapper's exit 0 is not 'the work completed'" and "pipefail with ssh+tee".

---

### 2. **[bug]** `scripts/update_hosts.sh:98-99` — pinning `LINK_GIT_DIRTY=false` on the dispatcher permanently disables link#257

`install_remote()` is called for **every** `(host, pkg)` pair, and the defaults
are `PKGS=(fresh link)` / `HOSTS=(m4 m1 cypher)` (lines 31-32). So the
documented no-arg invocation writes into m1's `~/.Renviron`:

```
LINK_GIT_SHA=<sha of NewGraphEnvironment/link main at update time>
LINK_GIT_DIRTY=false
```

m1 is the dispatcher, and it runs link **from the checkout**, not from the
install — `data-raw/study_area_run.sh:975` uses `LNK_LOAD=loadall`, and
`wsg_run_one.R:28-29` then `pkgload::load_all()`s
`~/Projects/repo/link`. `~/.Renviron` is read by every `Rscript`, and
`.lnk_pkg_git_state()` tier 1 (`R/lnk_stamp.R:388-390`) wins over the `.git`
walk that previously answered here. Nothing in the tree unsets these
(`grep -rn 'unset LINK_GIT|R_ENVIRON_USER' data-raw/ scripts/ R/` → no hits).

Consequences, from the moment the script is run and for every run afterwards:

* `log.link_dirty` is `FALSE` on every dispatcher row regardless of the actual
  working tree. That is link#257 reintroduced, and in the *worse* direction:
  #257 fixed a flag that was always TRUE (loud and useless); this makes it
  always FALSE (silent and trusted). `study_area_verify.sql`'s
  `link_dirty` arm (line 229) and the DO-block `OR link_dirty` (line 451) both
  become vacuous.
* `log.link_sha` names the tarball commit of `main`, not the branch HEAD that
  actually ran. A run dispatched from a feature branch records main's sha.

Note `repo_sha` in the parity stamp is unaffected (it reads the checkout
directly), so nothing catches this — the field that *is* wrong is the one that
lands in the persist forever.

`data-raw/study_area_run.sh:988-991` states the principle this violates:
"LINK_GIT_SHA / FRESH_GIT_SHA are deliberately NOT exported here … pushing the
dispatcher's values across would launder a claim into the worker's provenance."
`update_hosts.sh` now does exactly that, machine-wide and persistently.

Minimum fix: do not write `LINK_*` keys on a host where link is used via
`load_all` — or restrict the `.Renviron` write to `pkg = fresh`, which is the
only package the pre-flight gate needs it for.

---

### 3. **[fragile]** `scripts/update_hosts.sh:92-99` — the `FRESH_*` pin is stale by construction and nothing re-derives it

`data-raw/cypher_prep.sh:159-163` is explicit that a resolver reading
`FRESH_GIT_SHA` back would make "a stale pin self-perpetuating", and re-derives
from `RemoteSha` on **every** prep. `update_hosts.sh` writes the same keys with
no such refresh, and m1/m4 are never re-prepped.

So any later change to the installed `fresh` on those hosts by a route other
than this script — `pak::local_install()` from a working checkout,
`pak::pkg_install("…/fresh@branch")`, a hand `R CMD INSTALL` — leaves the stale
tier-1 value winning. `log.fresh_sha` then names a commit that is not what ran,
`fresh_dirty` says `false`, and *every* guard added in this diff is satisfied by
the stale pin: the new pre-flight gate
(`study_area_run.sh:559-686`) reads the same env var it is gating on, parity
agrees (both hosts stale), 2b agrees, the DO block passes.

The gate cannot detect this because its only source of truth is the value the
writer put there. Worth at minimum a comment stating the invariant
("`update_hosts.sh` must be the last thing that installs `fresh` on this host"),
and preferably having the gate prefer `RemoteSha` over the env var when a
`RemoteSha` exists and disagrees.

---

### 4. **[bug]** `data-raw/study_area_verify_negative.sh:296-299` — case 6c's skip is not counted, so the script claims a pass for an assertion it never exercised

```bash
if [ "${N_HOSTS:-1}" -lt 2 ]; then
  echo "  ⊘ 6c. SKIPPED: run $RUN_UID used one host, so hosts cannot disagree."
  echo "       Absence reported as absence -- this is NOT a pass."
else
```

It says "this is NOT a pass" and then does not `fails=$((fails + 1))`. Every
other skip in the file does — case 2 (line 142), case 4 (line 190), and the new
5/6 loop (line 251). So on a single-host run (`--no-cyphers`, or any local dev
run) `fails` stays 0 and the banner at line 332 prints:

```
=== negative test PASSED: the verify script fails when it should, and
    passes when it should ===
```

…for the brand-new cross-host assertion (`study_area_verify.sql:492-500`) that
was never watched go red. That is the file's own stated failure mode arriving
through the case added to prevent it, and it is the exact "an empty result set
is not a pass" shape from CLAUDE.md: absence made indistinguishable from
evidence.

Fix: add `fails=$((fails + 1))` in the 6c skip branch, matching cases 2/4/5/6.

---

### 5. **[fragile]** `scripts/update_hosts.sh:73` — the sha is resolved once per `(host, pkg)`, not once per package

`resolve_sha` is called inside `install_remote`, which the loop at lines 111-116
invokes for each host. A default run makes six independent API calls over the
documented ~3-5 min wall time. A push to `main` landing mid-run leaves hosts on
**different** commits, each correctly self-reported.

The comment at lines 48-52 argues carefully that fetching by sha closes the
resolve/fetch race *within* one host — and then reopens the same race *across*
hosts, which is the axis that matters now that `fresh_sha` is a
`lnk_preflight_parity()` key and `study_area_verify.sql:492-500` RAISEs on
cross-host disagreement. The failure is loud (parity refuses at
`preflight_hosts`, after spin + prep), but it costs a droplet cycle and the
update script itself reports success on all six installs.

Fix: resolve once per package before the host loop and pass the sha in.

---

## Checked and clean — do not re-derive

* **`local sha` + `if ! sha=$(resolve_sha …)`** (`update_hosts.sh:60`, `73`) —
  `local` is on its own line in both places, so the return-status masking does
  not apply. Correct as written.
* **`[ ${#PKGS[@]} -eq 0 ] && PKGS=(fresh link)`** under `set -euo pipefail`
  (lines 31-32) and the `{ …; [ -n "$X" ] && printf …; } >> "$RENV"` group in
  `cypher_prep.sh:206-212`. Measured on bash: neither aborts. The new
  `FRESH_DIRTY` line does not change reachability — `FRESH_DIRTY` is non-empty
  exactly when `FRESH_SHA` is, so the group's exit status is what it was before.
* **`~/.Renviron` rewrite** (`update_hosts.sh:91-97`) — `> "$RENV.tmp"` truncates
  the *temp*, never the original; `RC > 1` bails without `mv`; `RC = 1` (file
  becomes empty) is correctly tolerated; keys cannot accumulate because the
  `grep -vE` strips this package's own pair before appending. `umask 077` covers
  the redirect itself, and `chmod 600` follows the `mv`. Nested quoting is safe:
  `${sha}` is validated 40-hex, `${upkg}` is `LINK`/`FRESH`, and `\\n` reaches
  the remote `printf` intact.
* **`resolve_sha` on an API error body** — `curl -sSL` returns 0 on a 403/404,
  but the anchored `grep -qE '^[0-9a-f]{40}$'` rejects the JSON and `return 1`
  reaches the FATAL branch. Fails loud.
* **`fresh_state` parsing** (`study_area_run.sh:559-671`) — all four states
  behave: Rscript non-zero → `"|"` → sha empty → `fail=1`; empty stdout → sha
  empty → `fail=1`; `"|false"` (sha NA, dirty resolved) → sha empty → `fail=1`;
  `"abc|"` → dirty empty → the third branch fires. `cat()` evaluates all `...`
  before emitting, so a partial line is not reachable.
* **`study_area_verify.sql` `n_prov` reuse** (lines 452 and 495) — the first use
  is fully consumed by its own `IF` before the second `INTO` overwrites it. No
  interaction.
* **`fresh_dirty` three-valued logic** — 1b's `FILTER (WHERE fresh_dirty)`
  excludes NULL (correct; the NULL state has its own NOTE at line 253), and the
  DO block's `… OR link_dirty OR fresh_dirty` evaluates TRUE whenever
  `fresh_dirty` is TRUE regardless of the other terms being NULL. Negative case
  6b exercises it.
* **Can 1b print FAIL while the script exits 0?** Swept all seven FAIL arms plus
  2b: `link_sha` (DO 450), `fwapg_sha` (450), `fresh_sha` (474-481),
  `bcfishobs_sha` (451), `link_dirty` (451), `fresh_dirty` (451),
  `bcfp_model_version` (503-513), 2b (492-500). Every one has a RAISE behind it.
* **INSERT column/value alignment** for `fresh_sha_source` and `bcfishobs_sha`
  in both `.lnk_log_run_start` (`lnk_log.R:715-753`) and
  `.lnk_log_recompute_start` (`lnk_log.R:1001-1030`) — positions match.
* **`.lnk_blank_to_na(NULL)`** returns `NA_character_` (`lnk_log.R:508-513`), so
  `.lnk_pkg_remote_sha`'s `is.na(sha)` guard is length-1 safe for a package with
  no `RemoteSha`.
* **`identical(sha, remote_sha)` tier-2 dirty gate** (`lnk_stamp.R:411-419`) —
  correct in all four arrangements (env==remote → FALSE; env≠remote → falls
  through to the `.git` walk then NA; no env, remote present → FALSE; remote
  absent → `.git` walk). The hex shape guard declines version strings.
* **6c's restore and the case-7 re-run** — restores are correlated per
  `(host, watershed_group_code)` throughout, and case 7 is what makes them
  load-bearing.
