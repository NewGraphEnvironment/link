## Problem

Three of `fresh.log`'s code-identity columns are unusable, and one upstream input
has no code pin at all. Measured 2026-09-01 against the 39 rows now in
`fresh.log` (37 from the 2026-08-31 field run, 2 from link#262's integration
runs).

| column | filled | why |
|---|---|---|
| `fresh_sha` | 15 / 39 | cyphers only — the dispatcher's value is available and never read |
| `fresh_dirty` | **0 / 39** | never set on any host, ever |
| `bcfishobs_sha` | — | **the column does not exist** |

### 1. `fresh_sha` is not missing on the dispatcher, it is unread

The standing explanation — repeated in `CLAUDE.md`, `RUNBOOK.md` and
`data-raw/study_area_verify.sql` — is that m1 installs `fresh` locally
(`RemoteType: local`, no `RemoteSha`) so there is nothing to record. **That is
no longer true.** m1's installed `fresh`:

```
Version      0.33.0
RemoteType   github
RemoteRef    v0.33.0
RemoteSha    7f12d99115b7d20302d5ed043188cb870f90f83b
```

which is byte-identical to the SHA the cyphers recorded:

```sql
SELECT DISTINCT fresh_sha FROM fresh.log WHERE fresh_sha IS NOT NULL;
-- 7f12d99115b7d20302d5ed043188cb870f90f83b
```

The column is NULL because `.lnk_pkg_git_sha()` (`R/lnk_stamp.R`) has three
tiers — `<PKG>_GIT_SHA` env var, a `.git` walk, then `NA` — and **none of them
reads `RemoteSha` from the installed DESCRIPTION**. An installed package has no
`.git`, so the dispatcher falls through to `NA` while the answer sits in
`packageDescription()`. Cyphers only populate it because `cypher_prep.sh` sets
`FRESH_GIT_SHA` explicitly.

This also means the host-aware tolerance in `study_area_verify.sql` §1b rests on
a stated reason that is false. The tolerance is still *behaviourally* right
today, but a false rationale invites someone to "fix" it in the wrong direction.

### 2. `fresh_dirty` is NULL on every row and always will be

`cypher_prep.sh:174` strips, and `:181-185` rewrites, exactly three keys:

```bash
grep -vE '^(LINK_GIT_SHA|LINK_GIT_DIRTY|FRESH_GIT_SHA)=' "$RENV" > "$RENV.tmp"
...
printf 'LINK_GIT_SHA=%s\n'   "$LINK_SHA"
printf 'LINK_GIT_DIRTY=%s\n' "$LINK_DIRTY"
[ -n "$FRESH_SHA" ] && printf 'FRESH_GIT_SHA=%s\n' "$FRESH_SHA"
```

`FRESH_GIT_DIRTY` is not among them, and on the dispatcher `fresh` has no `.git`
to walk. So we record a `fresh_sha` on cyphers with **no way to know whether that
SHA describes a modified tree** — which is the entire job of the dirty flag
(`R/lnk_stamp.R`: "A SHA recorded against a dirty tree is a lie").

Same defect class as link#257, pointed the other way: that one was always-TRUE,
this one is always-NULL. Both carry zero information.

### 3. `bcfishobs` has no code pin at all

Everything `fresh.log` + `fresh.log_input` record about it, across all 39 runs:

```
bcfishobs.observations | bcfishobs | 373050 | estimated | last_analyze 2026-08-31
bcfishobs.observations | bcfishobs |     -1 | estimated | <null>
```

A row count and a hardcoded source string. No version, no SHA, no load date.
There is a checkout at `08630cf` on this machine and nothing records it.

**This is a model input, not a reference dataset.** `bcfishobs` is a pipeline
that matches observations onto the stream network;
`lnk_barrier_overrides()` counts those observations upstream of each barrier to
decide which barriers are skipped. Different `bcfishobs` code → different
matching → different barriers → different access → different `mapping_code`.
`fwapg` gets a `fwapg_sha`; `bcfishpass` got `bcfp_model_version` in link#262;
`bcfishobs` has nothing.

*(Minor, same table: that `-1` is PG14+'s `reltuples` sentinel for "never
analyzed" — unknown, not a count. 1 of 429 rows stores it as if it were one; 39
are honestly NULL, 389 real.)*

## Proposal

All link-side. No changes to `NewGraphEnvironment/fwapg` or
`NewGraphEnvironment/bcfishobs`, and nothing upstream.

1. **A `RemoteSha` tier in `.lnk_pkg_git_sha()`**, between the env var and the
   `.git` walk: `packageDescription(pkg)$RemoteSha`. Honest — it is what `pak`
   recorded from the actual source at install time, not an inference from a
   checkout that may sit at a different commit than the installed build. Record
   `RemoteRef` too where present (`v0.33.0` reads better than a SHA).
2. **`FRESH_GIT_DIRTY` written by `cypher_prep.sh`**, added to both the strip
   list and the write block.
3. **`bcfishobs_sha` + `bcfishobs_dirty` columns**, resolved by the same
   `.lnk_pkg_git_sha()` / `.lnk_pkg_git_dirty()` path. Note `bcfishobs` is not an
   R package — it is a repo of SQL/scripts — so the resolver needs a checkout-dir
   tier like `.lnk_fwapg_sha()` already has (`BCFISHOBS_GIT_SHA` env,
   `BCFISHOBS_DIR`, then `~/Projects/repo/bcfishobs`), plus the same
   dispatcher-resolves-once-and-exports-to-both-legs treatment `FWAPG_GIT_SHA`
   gets in `study_area_run.sh`.
4. **Correct the stale "RemoteType: local" claim** in `CLAUDE.md`, `RUNBOOK.md`
   and `study_area_verify.sql`, and tighten §1b's host-aware tolerance once
   `fresh_sha` populates everywhere.

### Fork note, so it is not re-derived

Both `NewGraphEnvironment/fwapg` and `NewGraphEnvironment/bcfishobs` are **forks
of `smnorris/*`**, and both currently carry **zero local commits** — fwapg is 0
ahead / 5 behind `smnorris/fwapg`, bcfishobs is identical to
`smnorris/bcfishobs`. That is why `fwapg_sha` resolves against upstream at all,
and it is an accident of being 0-ahead rather than a property. Recording a fork
SHA is fine; recording it *without noting it came from a fork* is what would rot.

## Acceptance

- [ ] `fresh_sha` non-NULL on **every** host, dispatcher included, and equal to
      the cyphers' value for the same install
- [ ] `fresh_dirty` non-NULL on every host
- [ ] `bcfishobs_sha` present and non-NULL on every host
- [ ] Both known answers per resolver tier: a package with `RemoteSha`, one
      without; a clean checkout, a dirty one; the env override winning over both
- [ ] No stale "RemoteType: local" claim left in the repo — `git grep` it
- [ ] `study_area_verify.sql` asserts `fresh_sha` on all hosts, not just cyphers

## Why now

link#246 exists because 93 WSGs accumulated with no provenance and it was
expensive to recover from. link#262 closed the run-level gaps before the 217-WSG
run. These are the input-identity gaps at the same deadline: the run is next, and
a row written without them is not retroactively fixable.

Relates to link#262 (the run-level pin), link#257 (`link_dirty`, same class),
link#247 (`snapshot_stamp`), link#183 (host parity on link+fresh version+SHA).
Version pin: link@v0.49.0, fresh@v0.33.0 (`7f12d99`),
`NewGraphEnvironment/fwapg@e6e1eb0`, `NewGraphEnvironment/bcfishobs@08630cf`.
