# Findings — Code-identity gaps in fresh.log (#264)

## Measured 2026-09-01, m1

The premise of the whole issue, re-measured rather than taken from the body:

```
$ Rscript -e 'd <- packageDescription("fresh"); cat(d$Version, d$RemoteType, d$RemoteRef, d$RemoteSha)'
fresh: 0.33.0  github  v0.33.0  7f12d99115b7d20302d5ed043188cb870f90f83b
link:  0.47.3  local   -
```

So the two packages give both known answers for the new DESCRIPTION tier on
this machine, for free — `fresh` **has** a `RemoteSha`, `link` does not. That
is the fixture; no mock needed.

Note `link`'s installed copy is 0.47.3 against a repo at 0.49.0. Irrelevant
here — on the dispatcher link is `pkgload::load_all`'d from the checkout, so
`.lnk_pkg_git_sha("link")` resolves through the `.git` walk, not the install.

## Existing machinery this reuses

| need | already exists | file |
|---|---|---|
| checkout-dir SHA resolver (env → dir → conventional path → NA) | `.lnk_fwapg_sha()` | `R/lnk_log.R:1083` |
| new column on an existing table | `.lnk_log_align_columns()` runs `ADD COLUMN IF NOT EXISTS` on every init | `R/lnk_log.R:317` |
| dirty predicate with the hard-won pathspec | `.lnk_git_dirty_at()` + `.lnk_git_dirty_pathspec` | `R/lnk_stamp.R:334-360` |
| "which tier answered" column | `bcfp_pin_source` (link#262) | `R/lnk_log.R:196` |
| resolve-once-and-export-to-both-legs | the `FWAPG_GIT_SHA` block | `data-raw/study_area_run.sh:488-506` |

Nothing new is invented; every piece has a precedent in the file it lands in.

## `FRESH_GIT_DIRTY` is no longer the mechanism

The issue's proposal 2 asks `cypher_prep.sh` to write `FRESH_GIT_DIRTY`,
because `fresh_dirty` is NULL on every row. With the DESCRIPTION tier built,
a cypher resolves it **anyway**: `fresh` there is pak-installed from the
`Remotes:` pin, so `RemoteSha` is present, so the tree is by definition not a
working tree, so `dirty = FALSE`.

Keeping the shell write regardless — it makes the cypher's answer a measured
observation rather than an inference from install metadata, and it costs two
lines. But it is belt-and-braces now, not the fix, and the issue body says so.

## Two ssh legs carry the env, not one

`FWAPG_GIT_SHA` appears inside **two** quoted ssh bodies in
`data-raw/study_area_run.sh`:

- `:635` — `collect_stamps()` → `host_stamp.R` (pre-flight parity)
- `:925` — the modelling dispatch → `wsg_run_one.R`

An env exported on the local leg does not cross ssh (the `LNK_RUN_UID` lesson
from link#262). `BCFISHOBS_GIT_SHA` needs both.

`:696` and `:718` are re-check / consolidate legs that carry no provenance env
and do not need it.

## Deliberately not done

- **`bcfishobs_dirty` column.** `fwapg` has no dirty column either; the
  dispatcher gate refuses to run over a dirty checkout, so a recorded SHA is
  clean by construction. A column FALSE on every row is link#257 pointed the
  other way.
- **`link_sha_source` column.** link's tier is already inferable (git-walk on
  the `load_all` dispatcher, env on a cypher), and an unused column is what
  this issue is about.
- **`bcfishobs_sha` in the pre-flight stamp.** Would change
  `.lnk_preflight_stamp_cols()`, which is a documented shell TSV contract.
  The verifier's DO block asserts it per row instead.

## Errors Encountered

| Error | Resolution |
|-------|------------|
